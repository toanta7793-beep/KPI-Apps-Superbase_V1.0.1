import { strToU8, zipSync } from "fflate";

const escapeXml=(value:unknown)=>String(value??"").replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");

export function buildWeekBackupXlsx(rows:Record<string,unknown>[]){
  // Backup phải KHÔI PHỤC ĐƯỢC: mọi cột nhập của public.jobs đều phải có mặt.
  // is_special_labor ('Đào tạo'/'Phát sinh') thay đổi cách tính chi phí nhân công —
  // thiếu nó thì phục hồi xong KPI sẽ lệch mà không ai biết.
  const columns=["id","team_id","start_date","end_date","category_name","content","location","quantity","count_leader","count_worker1","count_worker2","count_worker3","count_helper","is_special_labor","group_code","week_id","request_key","legacy_source_row","created_at","created_by","updated_at","updated_by","unit","unit_price","work_days","daily_payroll","breakeven_daily","target_daily","total_breakeven","production_value","actual_labor_cost","difference","evaluation"];
  const labels=["ID","Team ID","Ngày bắt đầu","Ngày kết thúc","Hạng mục Cấp 1","Nội dung công việc","Vị trí","Khối lượng","Tổ trưởng","Thợ bậc 1","Thợ bậc 2","Thợ bậc 3","Thợ phụ","Việc đặc biệt","Mã nhóm","Week ID","Request key","Dòng nguồn cũ","Tạo lúc","Người tạo","Sửa lúc","Người sửa","Đơn vị","Đơn giá","Số ngày","Quỹ lương/ngày","SL hòa vốn/ngày","SL đạt/ngày","Tổng SL hòa vốn","Sản lượng","Chi phí nhân công","Chênh lệch","Đánh giá"];
  const values=[labels,...rows.map(row=>columns.map(key=>row[key]))];
  // Tên cột Excel: A..Z rồi AA, AB... Không dùng String.fromCharCode(65+n) vì quá 26 cột sẽ ra ký tự rác.
  const columnName=(index:number)=>{let name="";for(let n=index;n>=0;n=Math.floor(n/26)-1)name=String.fromCharCode(65+(n%26))+name;return name};
  const lastColumn=columnName(columns.length-1);
  const cell=(value:unknown,header:boolean,address:string)=>typeof value==="number"&&Number.isFinite(value)
    ? `<c r="${address}"${header?' s="1"':''}><v>${value}</v></c>`
    : `<c r="${address}" t="inlineStr"${header?' s="1"':''}><is><t>${escapeXml(value)}</t></is></c>`;
  const sheet=`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetData>${values.map((row,index)=>`<row r="${index+1}">${row.map((value,column)=>cell(value,index===0,`${columnName(column)}${index+1}`)).join("")}</row>`).join("")}</sheetData><autoFilter ref="A1:${lastColumn}${Math.max(1,values.length)}"/></worksheet>`;
  return zipSync({
    "[Content_Types].xml":strToU8('<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>'),
    "_rels/.rels":strToU8('<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'),
    "xl/workbook.xml":strToU8('<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="BACKUP_TUAN" sheetId="1" r:id="rId1"/></sheets></workbook>'),
    "xl/_rels/workbook.xml.rels":strToU8('<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'),
    "xl/styles.xml":strToU8('<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Arial"/></font><font><b/><color rgb="FFFFFFFF"/><sz val="11"/><name val="Arial"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF1B2A6B"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/></cellXfs></styleSheet>'),
    "xl/worksheets/sheet1.xml":strToU8(sheet),
  },{level:6});
}
