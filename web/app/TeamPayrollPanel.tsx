"use client";
import { useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";
import { WorkerRosterImport } from "./WorkerRosterImport";

type Team={id:string;leader_name:string;is_active:boolean};
type Row={team_id:string;team_name:string;role_name:string;worker_count:number;total_daily:number;status:string;unknown_workers:Array<{mnv:string}>};
const money=new Intl.NumberFormat("vi-VN",{style:"currency",currency:"VND",maximumFractionDigits:0});

export function TeamPayrollPanel({teams,canEdit,onChanged,notify}:{teams:Team[];canEdit:boolean;onChanged:()=>Promise<void>;notify:(v:string)=>void}){
  const [rows,setRows]=useState<Row[]>([]),[error,setError]=useState("");
  async function load(){const {data,error}=await supabase.rpc("get_payroll_summary",{p_team_id:null});if(error){setError(error.message);return}setRows((data||[]) as Row[]);setError("")}
  useEffect(()=>{void supabase.rpc("get_payroll_summary",{p_team_id:null}).then(({data,error})=>{if(error)setError(error.message);else setRows((data||[]) as Row[])})},[]);
  const byTeam=useMemo(()=>new Map(teams.map(t=>[t.id,rows.filter(r=>r.team_id===t.id)])),[teams,rows]);
  return <>{canEdit&&<WorkerRosterImport teams={teams} onChanged={async()=>{await onChanged();await load()}} notify={notify}/>}<div className="section-divider"><span>Quỹ lương theo Tổ</span></div>{error&&<div className="toast error static-toast">{error}</div>}<div className="payroll-grid">{teams.filter(t=>t.is_active).map(team=>{const group=byTeam.get(team.id)||[],unknown=group[0]?.unknown_workers||[];return <article className="payroll-card" key={team.id}><div className="payroll-title"><strong>{team.leader_name}</strong><span>{group.reduce((s,r)=>s+Number(r.worker_count),0)} người</span></div><div className="grade-list">{group.map(r=><div key={r.role_name}><span>{r.role_name}</span><b>{r.worker_count} · {money.format(Number(r.total_daily))}/ngày</b></div>)}</div><div className="payroll-total"><span>Tổng quỹ lương ngày</span><strong>{money.format(group.reduce((s,r)=>s+Number(r.total_daily),0))}</strong></div>{unknown.length>0&&<div className="login-error">{unknown.length} CNCH chưa xác định Hệ/Bậc</div>}</article>})}</div></>;
}
