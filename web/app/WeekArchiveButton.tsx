"use client";

import { useState } from "react";
import { supabase } from "../lib/supabase";
import { buildWeekBackupXlsx } from "../lib/weekBackupXlsx";

type Week={id:string;week_slot:number;start_date:string;end_date:string;teams?:{leader_name:string}|null};
export function WeekArchiveButton({week,onDone,notify}:{week:Week;onDone:()=>Promise<void>;notify:(text:string)=>void}){
  const [busy,setBusy]=useState(false);
  async function archive(){
    if(busy||!window.confirm(`Backup Excel và xóa Tuần ${week.week_slot}? Dữ liệu chỉ bị xóa sau khi backup được xác minh.`))return;
    setBusy(true);
    try{
      const operation=crypto.randomUUID();
      const {data:prepared,error}=await supabase.rpc("prepare_week_archive",{p_operation_id:operation,p_week_id:week.id});
      if(error)throw error;
      const bytes=buildWeekBackupXlsx((prepared.snapshot||[]) as Record<string,unknown>[]);
      const {data:session}=await supabase.auth.getSession();
      const response=await fetch("/api/weeks/archive",{method:"POST",headers:{Authorization:`Bearer ${session.session?.access_token||""}`,"Content-Type":"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet","X-Operation-Id":operation,"X-Week-Id":week.id},body:bytes});
      const result=await response.json();if(!response.ok)throw new Error(result.error||"Không thể xác minh backup.");
      const blob=new Blob([bytes],{type:"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"});const url=URL.createObjectURL(blob);const link=document.createElement("a");link.href=url;link.download=`Backup_Tuan_${week.week_slot}_${week.start_date}_${week.end_date}.xlsx`;link.click();URL.revokeObjectURL(url);
      notify(`Đã backup và xóa an toàn Tuần ${week.week_slot} (${result.row_count} công việc).`);await onDone();
    }catch(error){notify(`${error instanceof Error?error.message:"Xóa Tuần thất bại"}. Dữ liệu hoạt động không bị xóa.`)}finally{setBusy(false)}
  }
  return <button className="btn btn-sm btn-red" disabled={busy} onClick={archive}>{busy?"Đang backup…":`Backup & Xóa Tuần ${week.week_slot}`}</button>;
}
