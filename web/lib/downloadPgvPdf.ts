"use client";
import fontkit from "@pdf-lib/fontkit";
import { PDFDocument, PDFFont, PDFPage, rgb } from "pdf-lib";
type Job={id:string;content:string;location:string|null;quantity:number;unit:string|null;start_date:string;end_date:string;target_daily:number|null;count_leader:number;count_worker1:number;count_worker2:number;count_worker3:number;count_helper:number};
type Worker={id:string;mnv:string;full_name:string;job_title:string|null};
type Assignment={worker_id:string;job_id:string|null;target:string|null;completed_qty:string|null};
type Common={team_name:string;project_name:string;assign_date:string;receive_date:string;worker_count:number;rows:Job[]};
type Cnch={project_name:string;week:{week_slot:number};receive_date:string;assign_date:string;workers:Worker[];jobs:Job[]};
const A4L:[number,number]=[841.89,595.28];
const ddmmyyyy=(iso:string)=>{const [y,m,d]=iso.split("-");return y&&m&&d?`${d}/${m}/${y}`:iso};
const safe=(v:unknown)=>v==null?"":String(v);
const people=(j:Job)=>j.count_leader+j.count_worker1+j.count_worker2+j.count_worker3+j.count_helper;
// Xuống dòng theo từ; nếu MỘT từ đã rộng hơn ô thì cắt tiếp theo ký tự.
// Thiếu nhánh cắt theo ký tự thì một mã dài không có dấu cách sẽ tràn ra ngoài khung ô.
export function split(font:PDFFont,text:string,size:number,width:number){
  const out:string[]=[];let line="";
  const pushWord=(word:string)=>{
    if(font.widthOfTextAtSize(word,size)<=width){
      const next=line?`${line} ${word}`:word;
      if(font.widthOfTextAtSize(next,size)<=width){line=next;return}
      if(line)out.push(line);line=word;return;
    }
    if(line){out.push(line);line=""}
    let chunk="";
    for(const ch of word){
      if(font.widthOfTextAtSize(chunk+ch,size)>width&&chunk){out.push(chunk);chunk=ch}
      else chunk+=ch;
    }
    line=chunk;
  };
  for(const word of safe(text).split(/\s+/)) if(word) pushWord(word);
  if(line)out.push(line);
  return out.length?out:[""]
}

// Chiều cao cần thiết để KHÔNG cắt mất chữ của bất kỳ ô nào trên cùng một dòng.
// Quy tắc nghiệp vụ: mẫu in giữ bố cục đã duyệt, nội dung dài co giãn chứ không bị cắt.
export function rowHeight(font:PDFFont,values:unknown[],widths:number[],size:number,min:number){
  let lines=1;
  values.forEach((v,i)=>{lines=Math.max(lines,split(font,safe(v),size,widths[i]-6).length)});
  return Math.max(min,lines*(size+2)+5);
}
function cell(page:PDFPage,font:PDFFont,text:string,x:number,y:number,w:number,h:number,size=7,bold?:PDFFont){page.drawRectangle({x,y:y-h,width:w,height:h,borderWidth:.55,borderColor:rgb(.1,.1,.1)});const f=bold||font;split(f,text,size,w-6).slice(0,Math.max(1,Math.floor((h-5)/(size+2)))).forEach((line,i)=>page.drawText(line,{x:x+3,y:y-size-3-i*(size+2),size,font:f}))}
function header(page:PDFPage,font:PDFFont,bold:PDFFont,title:string,projectName:string){page.drawText(title,{x:40,y:558,size:17,font:bold});page.drawText(`Dự án: ${projectName}  |  Hạng mục: Thi công cơ điện`,{x:40,y:539,size:9,font});page.drawText("VINCONS - THI CÔNG KPI MEP",{x:675,y:558,size:7,font});page.drawLine({start:{x:40,y:530},end:{x:802,y:530},thickness:1,color:rgb(.1,.16,.42)})}
async function fonts(doc:PDFDocument){doc.registerFontkit(fontkit);const [regular,bold]=await Promise.all([fetch("/BeVietnamPro-Regular.ttf").then(r=>r.arrayBuffer()),fetch("/BeVietnamPro-Bold.ttf").then(r=>r.arrayBuffer())]);return {font:await doc.embedFont(regular,{subset:true}),bold:await doc.embedFont(bold,{subset:true})}}
function save(bytes:Uint8Array,name:string){const blob=new Blob([bytes as BlobPart],{type:"application/pdf"}),url=URL.createObjectURL(blob),a=document.createElement("a");a.href=url;a.download=name;a.click();window.setTimeout(()=>URL.revokeObjectURL(url),1000)}
export async function downloadPgvCommonPdf(data:Common){const doc=await PDFDocument.create(),{font,bold}=await fonts(doc);let page=doc.addPage(A4L);header(page,font,bold,"PHIẾU GIAO VIỆC",data.project_name);page.drawText(`Bên nhận việc: ${data.team_name}`,{x:40,y:510,size:10,font:bold});page.drawText(`Số CN: ${data.worker_count}  |  Ngày giao: ${ddmmyyyy(data.assign_date)}  |  Ngày nhận: ${ddmmyyyy(data.receive_date)}`,{x:40,y:493,size:9,font});const widths=[28,84,260,48,70,70,104],heads=["STT","Vị trí","Nội dung công việc","Số CN","Mục tiêu","Bắt đầu","Kết thúc"];let y=470;const drawHead=()=>{let x=40;heads.forEach((h,i)=>{cell(page,font,h,x,y,widths[i],28,7,bold);x+=widths[i]});y-=28};drawHead();for(let i=0;i<data.rows.length;i++){const j=data.rows[i];if(y<130){page=doc.addPage(A4L);header(page,font,bold,"PHIẾU GIAO VIỆC (tiếp)",data.project_name);y=510;drawHead()}let x=40;const vals=[i+1,j.location||"",j.content,people(j),`${j.quantity} ${j.unit||""}`,ddmmyyyy(j.start_date),ddmmyyyy(j.end_date)];const h=rowHeight(font,vals,widths,7,36);vals.forEach((v,k)=>{cell(page,font,safe(v),x,y,widths[k],h);x+=widths[k]});y-=h}page.drawText("Tiểu đội trưởng                         Trung đội trưởng                         Đại đội trưởng",{x:125,y:54,size:9,font:bold});save(await doc.save(),`PGV_${data.team_name}_${data.receive_date}.pdf`)}
export async function downloadPgvCnchPdf(data:Cnch,teamName:string,items:Record<string,Assignment>){const doc=await PDFDocument.create(),{font,bold}=await fonts(doc);let page=doc.addPage(A4L);header(page,font,bold,"PHIẾU GIAO VIỆC CÔNG NHÂN CƠ HỮU HẰNG NGÀY",data.project_name);page.drawText(`Bên nhận việc: ${teamName}`,{x:40,y:510,size:10,font:bold});page.drawText(`Ngày giao: ${ddmmyyyy(data.assign_date)}  |  Ngày nhận: ${ddmmyyyy(data.receive_date)}  |  Tuần ${data.week.week_slot}`,{x:40,y:493,size:9,font});const widths=[28,82,58,74,230,100,90,100],heads=["STT","Họ và tên","MNV","Chức vụ","Nội dung công việc","Mục tiêu","Vị trí","KL thực tế"];let y=470;const drawHead=()=>{let x=40;heads.forEach((h,i)=>{cell(page,font,h,x,y,widths[i],30,6.5,bold);x+=widths[i]});y-=30};drawHead();for(let i=0;i<data.workers.length;i++){const w=data.workers[i],a=items[w.id],j=data.jobs.find(v=>v.id===a?.job_id);if(y<110){page=doc.addPage(A4L);header(page,font,bold,"PHIẾU GIAO VIỆC CNCH (tiếp)",data.project_name);y=510;drawHead()}let x=40;const vals=[i+1,w.full_name,w.mnv,w.job_title||"",j?.content||"OFF",a?.target||"",j?.location||"",a?.completed_qty||""];const h=rowHeight(font,vals,widths,6.2,30);vals.forEach((v,k)=>{cell(page,font,safe(v),x,y,widths[k],h,6.2);x+=widths[k]});y-=h}save(await doc.save(),`PGV_CNCH_${teamName}_${data.receive_date}.pdf`)}
