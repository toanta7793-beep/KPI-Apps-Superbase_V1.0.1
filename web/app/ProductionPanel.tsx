"use client";
import { useCallback, useEffect, useState } from "react";
import { supabase } from "../lib/supabase";
import { operationError } from "./importErrors";
import { DateInput } from "./DateInput";
import { asciiFileName, buildTableXlsx, downloadXlsx } from "../lib/exportXlsx";
import { PRODUCTION_EXPORT_COLUMNS, toProductionExportRows } from "./exportRows";

type Team={id:string;leader_name:string;is_active:boolean};
type SharedWeek={week_slot:number;start_date:string;end_date:string};
export type ProductionRow={
  job_id:string;team_id:string;team_name:string;week_slot:number;
  phan_khu:string|null;vi_tri_chi_tiet:string|null;noi_dung:string;
  muc_tieu:number;don_vi:string|null;start_date:string;end_date:string;
  luy_ke_khoi_luong:number;luy_ke_thanh_tien:number;luy_ke_phan_tram:number|null;
  so_ngay_da_nhap:number;tu_dong:boolean;group_code:string|null;
  o_nhap_khoi_luong:number|null;o_nhap_da_khoa:boolean;o_nhap_co_ton_tai:boolean;
};

const money=new Intl.NumberFormat("vi-VN",{style:"currency",currency:"VND",maximumFractionDigits:0});
const qty=new Intl.NumberFormat("vi-VN",{maximumFractionDigits:2});
const viDate=(value:string)=>{if(!/^\d{4}-\d{2}-\d{2}$/.test(value||""))return "—";const [y,m,d]=value.split("-");return `${d}/${m}/${y}`};
const isoToday=()=>new Date().toISOString().slice(0,10);

// Ngày nhập phải nằm trong khoảng ngày của việc — database cũng chặn, nhưng chặn sớm ở đây
// thì người dùng biết ngay vì sao ô bị mờ thay vì bấm xong mới nhận mã lỗi.
const inRange=(row:ProductionRow,date:string)=>date>=row.start_date&&date<=row.end_date;

export function ProductionPanel({teams,sharedWeeks,canUnlock,canExport,defaultTeam,notify}:{
  teams:Team[];sharedWeeks:SharedWeek[];canUnlock:boolean;canExport:boolean;defaultTeam:string;notify:(text:string)=>void;
}){
  const [teamId,setTeamId]=useState(defaultTeam);
  const [weekSlot,setWeekSlot]=useState<string>("");
  const [workDate,setWorkDate]=useState(isoToday());
  const [rows,setRows]=useState<ProductionRow[]>([]);
  const [draft,setDraft]=useState<Record<string,string>>({});
  const [busy,setBusy]=useState(true),[savingJob,setSavingJob]=useState("");
  const [error,setError]=useState("");

  // Không đặt state đồng bộ ngay trong effect — làm vậy sinh một vòng render thừa mỗi lần
  // đổi bộ lọc. Cờ "đang tải" do chính các ô lọc bật lên (đó là sự kiện người dùng, không
  // phải effect), còn effect chỉ tắt nó khi dữ liệu về.
  const apply=useCallback((list:ProductionRow[])=>{
    setRows(list);
    // Ô nhập bám theo số đang có trong database. Không giữ lại thứ người dùng gõ dở của
    // ngày trước: đổi ngày mà số cũ còn nằm đó là cách chắc chắn để ghi nhầm ngày.
    setDraft(Object.fromEntries(list.map(row=>[row.job_id,row.o_nhap_co_ton_tai?String(row.o_nhap_khoi_luong??""):""])));
  },[]);
  const fetchRows=useCallback(async()=>supabase.rpc("get_production_evaluation",{
    p_team_id:teamId||null,p_week_slot:weekSlot?Number(weekSlot):null,p_work_date:workDate||null}),[teamId,weekSlot,workDate]);

  useEffect(()=>{
    let cancelled=false;
    void (async()=>{
      const {data,error:loadError}=await fetchRows();
      // Đổi bộ lọc nhanh tay thì lần tải cũ về sau lần mới. Bỏ kết quả cũ đi, nếu không
      // màn hình sẽ hiện số của tổ hoặc ngày mà người dùng đã rời khỏi.
      if(cancelled)return;
      setBusy(false);
      if(loadError){setError(operationError(loadError.message));setRows([]);return}
      setError("");apply((data||[]) as ProductionRow[]);
    })();
    return()=>{cancelled=true};
  },[fetchRows,apply]);

  // Dùng sau khi ghi/mở khóa: nạp lại đúng phạm vi đang xem.
  const reload=useCallback(async()=>{
    const {data,error:loadError}=await fetchRows();
    if(loadError){setError(operationError(loadError.message));return}
    setError("");apply((data||[]) as ProductionRow[]);
  },[fetchRows,apply]);

  async function save(row:ProductionRow){
    const raw=(draft[row.job_id]??"").trim();
    if(raw===""){notify("Chưa nhập khối lượng cho việc này.");return}
    const value=Number(raw);
    if(!Number.isFinite(value)||value<0){notify("Khối lượng phải là số không âm.");return}
    // Hộp thoại xác nhận rồi khóa — theo quyết định 11/08/2026. Nói rõ hậu quả trước khi
    // người dùng bấm, vì sau đó chỉ Admin mới mở lại được.
    if(!window.confirm(
      `Ghi ${qty.format(value)} ${row.don_vi||""} cho "${row.noi_dung}" ngày ${viDate(workDate)}?\n\n`+
      `Anh chắc chắn chưa? Lưu rồi sẽ KHÔNG sửa lại được nữa — chỉ Quản trị viên mở khóa được.`))return;
    setSavingJob(row.job_id);
    const {error:saveError}=await supabase.rpc("save_daily_production",{p_job_id:row.job_id,p_work_date:workDate,p_quantity:value});
    setSavingJob("");
    if(saveError){notify(operationError(saveError.message));return}
    notify("Đã ghi và khóa số liệu.");
    await reload();
  }

  async function unlock(row:ProductionRow){
    if(!window.confirm(`Mở khóa "${row.noi_dung}" ngày ${viDate(workDate)} để sửa lại?`))return;
    const {error:unlockError}=await supabase.rpc("unlock_daily_production",{p_job_id:row.job_id,p_work_date:workDate});
    if(unlockError){notify(operationError(unlockError.message));return}
    notify("Đã mở khóa. Ghi lại sẽ khóa tiếp.");
    await reload();
  }

  function exportExcel(){
    if(!canExport){notify("Chỉ Quản trị viên được xuất dữ liệu.");return}
    if(!rows.length){notify("Không có dòng nào để xuất.");return}
    const team=teamId?(activeTeams.find(t=>t.id===teamId)?.leader_name||"To"):"TatCa";
    const week=weekSlot?`Tuan${weekSlot}`:"CacTuan";
    downloadXlsx(buildTableXlsx("DanhGiaSanLuong",PRODUCTION_EXPORT_COLUMNS,toProductionExportRows(rows)),
      asciiFileName(`DanhGiaSanLuong_${team}_${week}_${workDate}`)+".xlsx");
    notify(`Đã xuất ${rows.length} dòng.`);
  }

  const activeTeams=teams.filter(team=>team.is_active);
  return <>
    <div className="card no-print"><div className="card-header"><span className="ch-icon">📈</span><span className="ch-title">Đánh Giá Sản Lượng</span></div>
      <div className="card-body">
        <div className="filters-row">
          <select className="form-control" value={teamId} onChange={event=>{setBusy(true);setTeamId(event.target.value)}}>
            <option value="">Tất cả Tổ</option>
            {activeTeams.map(team=><option key={team.id} value={team.id}>{team.leader_name}</option>)}
          </select>
          <select className="form-control" value={weekSlot} onChange={event=>{setBusy(true);setWeekSlot(event.target.value)}}>
            <option value="">Tất cả các tuần</option>
            {[1,2,3,4].map(slot=>{const week=sharedWeeks.find(item=>item.week_slot===slot);
              return <option key={slot} value={slot}>{week?`Tuần ${slot}: ${viDate(week.start_date)}–${viDate(week.end_date)}`:`Tuần ${slot} (chưa tạo)`}</option>})}
          </select>
          <DateInput value={workDate} onChange={value=>{setBusy(true);setWorkDate(value)}}/>
          {/* Chỉ Admin thấy nút này. Giao diện chỉ ẩn đi; dữ liệu thì database đã giới hạn
              theo tổ của từng người từ trước rồi. */}
          {canExport&&<button className="btn btn-secondary" disabled={busy||!rows.length} onClick={exportExcel}>⬇️ Xuất Excel</button>}
        </div>
        <p className="import-help">Ghi khối lượng làm được <strong>trong ngày {viDate(workDate)}</strong>, không phải lũy kế — hệ thống tự cộng dồn. Lưu là khóa.</p>
        {error&&<div className="toast error static-toast">{error}</div>}
        {busy&&<div className="loading-text">Đang tải…</div>}
      </div>
    </div>

    <div className="card"><div className="table-wrap"><table className="production-table">
      <thead>
        <tr><th rowSpan={2}>STT</th><th colSpan={3}>Nội dung công việc/Vị trí thực hiện</th><th rowSpan={2}>Mục tiêu hoàn thành</th>
          <th colSpan={2}>Thời gian</th><th rowSpan={2}>Nhập ngày {viDate(workDate)}</th>
          <th rowSpan={2}>Lũy kế sản lượng</th><th rowSpan={2}>Lũy kế (Thành tiền)</th><th rowSpan={2}>Lũy kế (%)</th></tr>
        <tr><th>Phân khu</th><th>Vị trí chi tiết</th><th>Nội dung công việc</th><th>Ngày bắt đầu</th><th>Ngày kết thúc</th></tr>
      </thead>
      <tbody>
        {rows.map((row,index)=>{
          const outside=!inRange(row,workDate);
          const locked=row.o_nhap_da_khoa;
          return <tr key={row.job_id} className={row.tu_dong?"row-auto":""}>
            <td>{index+1}</td>
            <td>{row.phan_khu||""}</td>
            <td>{row.vi_tri_chi_tiet||""}</td>
            <td>{row.noi_dung}{row.group_code&&<span className="badge badge-cyan">🔗 {row.group_code}</span>}</td>
            <td>{qty.format(Number(row.muc_tieu))} {row.don_vi||""}</td>
            <td>{viDate(row.start_date)}</td>
            <td>{viDate(row.end_date)}</td>
            <td className="cell-entry">
              {row.tu_dong
                ? <span className="entry-note">Tự động<small>Đào tạo / Phát sinh</small></span>
                : outside
                  ? <span className="entry-note">—<small>ngoài khoảng ngày của việc</small></span>
                  : <div className="entry-box">
                      <input className="form-control" type="number" min="0" step="any" disabled={locked||savingJob===row.job_id}
                        value={draft[row.job_id]??""} onChange={event=>setDraft(prev=>({...prev,[row.job_id]:event.target.value}))}/>
                      {locked
                        ? <>
                            <span className="badge badge-navy">🔒 Đã khóa</span>
                            {canUnlock&&<button className="btn btn-sm btn-secondary" onClick={()=>void unlock(row)}>Mở khóa</button>}
                          </>
                        : <button className="btn btn-sm btn-primary" disabled={savingJob===row.job_id} onClick={()=>void save(row)}>
                            {savingJob===row.job_id?"Đang lưu…":"Lưu"}</button>}
                    </div>}
            </td>
            <td>{qty.format(Number(row.luy_ke_khoi_luong))} {row.don_vi||""}</td>
            <td>{money.format(Number(row.luy_ke_thanh_tien))}</td>
            {/* Chưa ai nhập thì nói "chưa nhập", không hiện 0%. Làm được 0 và chưa ghi gì là
                hai chuyện khác hẳn nhau, mà nhìn số 0 thì không phân biệt được. */}
            <td>{row.so_ngay_da_nhap===0&&!row.tu_dong
              ? <span className="muted">chưa nhập</span>
              : `${qty.format(Number(row.luy_ke_phan_tram??0))}%`}</td>
          </tr>})}
        {!rows.length&&!busy&&<tr><td colSpan={11}><div className="empty-compact">Chưa có việc nào được giao trong phạm vi đang chọn.</div></td></tr>}
      </tbody>
    </table></div></div>
  </>;
}
