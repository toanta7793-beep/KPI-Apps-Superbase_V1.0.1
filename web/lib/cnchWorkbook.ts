import { strFromU8, unzipSync } from "fflate";

export type CnchWorkerRow={mnv:string;full_name:string;job_title:string;team_name:string;project_name:string;stt_in_team:number};
export type CnchWorkbook={workers:CnchWorkerRow[];teams:string[];sheetName:string};

const clean=(value:unknown)=>String(value??"").replace(/\s+/g," ").trim();
const norm=(value:unknown)=>clean(value).normalize("NFD").replace(/[\u0300-\u036f]/g,"").replace(/đ/g,"d").replace(/Đ/g,"D").replace(/[^a-zA-Z0-9]+/g," ").trim().toLowerCase();
const xml=(bytes:Uint8Array)=>new DOMParser().parseFromString(strFromU8(bytes),"application/xml");
const local=(node:Element,name:string)=>Array.from(node.getElementsByTagNameNS("*",name));

function sharedStrings(files:Record<string,Uint8Array>){
  const source=files["xl/sharedStrings.xml"];
  if(!source)return [];
  return local(xml(source).documentElement,"si").map(si=>local(si,"t").map(t=>t.textContent||"").join(""));
}

function rowsFromSheet(source:Uint8Array,shared:string[]){
  return local(xml(source).documentElement,"row").map(row=>{
    const values:string[]=[];
    local(row,"c").forEach(cell=>{
      const ref=cell.getAttribute("r")||"A1";
      const letters=(ref.match(/[A-Z]+/)||["A"])[0];
      let col=0;for(const ch of letters)col=col*26+ch.charCodeAt(0)-64;col--;
      const type=cell.getAttribute("t");
      const raw=local(cell,"v")[0]?.textContent||"";
      values[col]=type==="s"?shared[Number(raw)]||"":type==="inlineStr"?local(cell,"t").map(t=>t.textContent||"").join(""):raw;
    });
    return values;
  });
}

function findHeader(rows:string[][]){
  for(let row=0;row<Math.min(rows.length,20);row++){
    const h=(rows[row]||[]).map(norm);
    const maNV=h.findIndex(v=>v==="ma nhan vien"||v==="ma nv");
    const hoTen=h.findIndex(v=>v==="ho va ten"||v==="ho ten");
    const chucVu=h.findIndex(v=>v==="chuc vu");
    const tenTo=h.findIndex(v=>["ten to","to","ten to da chuan hoa","to truong","to truong da chuan hoa"].includes(v));
    const duAn=h.findIndex(v=>v==="du an"||v==="ten du an");
    if(maNV>=0&&hoTen>=0&&chucVu>=0&&tenTo>=0&&duAn>=0)return {row,maNV,hoTen,chucVu,tenTo,duAn};
  }
  return null;
}

export async function parseCnchWorkbook(file:File):Promise<CnchWorkbook>{
  if(!/\.xlsx$/i.test(file.name))throw new Error("Chỉ chấp nhận file Excel .xlsx.");
  if(file.size<=0||file.size>12*1024*1024)throw new Error("File Excel rỗng hoặc vượt quá 12 MB.");
  const files=unzipSync(new Uint8Array(await file.arrayBuffer()));
  const shared=sharedStrings(files);
  const sheets=Object.entries(files).filter(([path])=>/^xl\/worksheets\/sheet\d+\.xml$/.test(path));
  for(const [path,source] of sheets){
    const rows=rowsFromSheet(source,shared),header=findHeader(rows);if(!header)continue;
    const seen=new Set<string>(),teamOrder:string[]=[],teamKeyToName=new Map<string,string>(),teamCounts=new Map<string,number>(),workers:CnchWorkerRow[]=[];
    for(let i=header.row+1;i<rows.length;i++){
      const row=rows[i]||[],mnv=clean(row[header.maNV]).toUpperCase(),full_name=clean(row[header.hoTen]),job_title=clean(row[header.chucVu]),rawTeam=clean(row[header.tenTo]),project_name=clean(row[header.duAn]);
      if(!mnv&&!full_name&&!job_title&&!rawTeam&&!project_name)continue;
      if(!mnv||!full_name||!job_title||!rawTeam||!project_name)throw new Error(`Dòng ${i+1} thiếu MNV, Họ tên, Chức vụ, Tên Tổ hoặc Dự án.`);
      if(seen.has(mnv))throw new Error(`Trùng MNV “${mnv}” tại dòng ${i+1}.`);seen.add(mnv);
      const key=norm(rawTeam),team_name=teamKeyToName.get(key)||rawTeam;
      if(!teamKeyToName.has(key)){teamKeyToName.set(key,team_name);teamOrder.push(team_name);teamCounts.set(team_name,0)}
      const stt=(teamCounts.get(team_name)||0)+1;teamCounts.set(team_name,stt);
      workers.push({mnv,full_name,job_title,team_name,project_name,stt_in_team:stt});
    }
    if(!workers.length)throw new Error("File không có bản ghi công nhân hợp lệ.");
    if(teamOrder.length>123)throw new Error(`File có ${teamOrder.length} tổ, vượt giới hạn 123 tổ.`);
    return {workers,teams:teamOrder,sheetName:path};
  }
  throw new Error("Không nhận diện được các cột Mã nhân viên, Họ và tên, Chức vụ, Tên Tổ và Dự án.");
}

/** Đọc mọi worksheet của file .xlsx thành mảng dòng/ô dạng chuỗi. */
export async function readSheetRows(file:File,maxMb=12):Promise<Array<{path:string;rows:string[][]}>>{
  if(!/\.xlsx$/i.test(file.name))throw new Error("Chỉ chấp nhận file Excel .xlsx.");
  if(file.size<=0||file.size>maxMb*1024*1024)throw new Error(`File Excel rỗng hoặc vượt quá ${maxMb} MB.`);
  const files=unzipSync(new Uint8Array(await file.arrayBuffer()));
  const shared=sharedStrings(files);
  return Object.entries(files)
    .filter(([path])=>/^xl\/worksheets\/sheet\d+\.xml$/.test(path))
    .map(([path,source])=>({path,rows:rowsFromSheet(source,shared)}));
}

export async function sha256Hex(file:File){
  const digest=await crypto.subtle.digest("SHA-256",await file.arrayBuffer());
  return Array.from(new Uint8Array(digest),b=>b.toString(16).padStart(2,"0")).join("");
}
