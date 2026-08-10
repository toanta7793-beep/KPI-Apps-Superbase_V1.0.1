"use client";
/* eslint-disable jsx-a11y/label-has-associated-control, @next/next/no-img-element */

import { FormEvent, ReactNode, useEffect, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { isSupabaseConfigured, supabase } from "../lib/supabase";
import { UsersAdminPanel } from "./AdminPanels";
import { TeamPayrollPanel } from "./TeamPayrollPanel";
import { DateInput } from "./DateInput";
import { EditableJob, JobEditorModal } from "./JobEditorModal";
import { validateJobGroup } from "./jobGrouping";
import { PgvCnchRpc, PgvCommonRpc } from "./PgvPanels";
import { WeekArchiveButton } from "./WeekArchiveButton";
import { StaffingCoverage } from "./StaffingCoverage";

type Identity = { role_code:string; worker_id:string|null; mnv:string|null; full_name:string|null; team_id:string|null; team_name:string|null; team_ids:string[] };
type Team = { id:string; team_code:string; leader_name:string; is_active:boolean; stt:number|null };
type Worker = { id:string; mnv:string; full_name:string; job_title:string|null; team_id:string|null; stt_in_team:number|null; teams?:{leader_name:string}|null };
type Job = { id:string; team_id:string; start_date:string; end_date:string; category_name:string; content:string; location:string|null; quantity:number; count_leader:number; count_worker1:number; count_worker2:number; count_worker3:number; count_helper:number; group_code:string|null; week_id:string|null; unit:string|null; unit_price:number|null; work_days:number; daily_payroll:number; breakeven_daily:number|null; target_daily:number|null; total_breakeven:number|null; production_value:number|null; actual_labor_cost:number|null; difference:number|null; evaluation:string };
type Week = { id:string; team_id:string; week_slot:number; start_date:string; end_date:string; status:string; teams?:{leader_name:string}|null };
type SharedWeek = { id:string; week_slot:number; start_date:string; end_date:string; status:string };
type Kpi = { team_name:string; start_date:string; end_date:string; day_count:number; total_payroll:number; total_production:number; difference_vnd:number; evaluation:string };
type Profile = { id:string; role_code:string; is_active:boolean; worker_id:string|null; workers?:{mnv:string;full_name:string;teams?:{leader_name:string}|null}|null };
type CatalogItem = { category_name:string };
type PageId = "home"|"danh-muc-to"|"nhan-su"|"giao-viec"|"danh-gia"|"pgv"|"pgvcnch"|"users";

const PAGE_TITLES:Record<PageId,string> = {
  home:"🏠 Tổng Quan", "danh-muc-to":"🏢 Danh Mục Tổ", "nhan-su":"👥 Nhân Sự & Quỹ Lương",
  "giao-viec":"📋 Giao Việc & Hòa Vốn", "danh-gia":"📊 Đánh Giá KPI", pgv:"📄 Phiếu Giao Việc (PGV)",
  pgvcnch:"👷 Phiếu PGV CNCH", users:"🔐 Phân Quyền Người Dùng",
};
const money = new Intl.NumberFormat("vi-VN",{style:"currency",currency:"VND",maximumFractionDigits:0});
const viDate=(value:string)=>{if(!/^\d{4}-\d{2}-\d{2}$/.test(value||""))return "—";const [y,m,d]=value.split("-");return `${d}/${m}/${y}`};
const isoToday = () => new Date().toISOString().slice(0,10);
const roleLabel = (role?:string) => ({ADMIN:"⚡ Quản trị viên",GIAM_SAT:"🎯 Giám sát",TO_TRUONG:"👷 Tổ trưởng",NHAN_VIEN:"👤 Nhân viên",XEM:"👁️ Chỉ xem"}[role||""]||role||"");

export default function KpiApp(){
  const [session,setSession]=useState<Session|null>(null);
  const [identity,setIdentity]=useState<Identity|null>(null);
  const [page,setPage]=useState<PageId>("home");
  const [busy,setBusy]=useState(true),[error,setError]=useState(""),[notice,setNotice]=useState("");
  const [menuOpen,setMenuOpen]=useState(false),[modal,setModal]=useState<"team"|"job"|null>(null),[editingJob,setEditingJob]=useState<Job|null>(null);
  const [teams,setTeams]=useState<Team[]>([]),[workers,setWorkers]=useState<Worker[]>([]),[jobs,setJobs]=useState<Job[]>([]),[weeks,setWeeks]=useState<Week[]>([]),[sharedWeeks,setSharedWeeks]=useState<SharedWeek[]>([]),[kpis,setKpis]=useState<Kpi[]>([]),[profiles,setProfiles]=useState<Profile[]>([]),[catalog,setCatalog]=useState<CatalogItem[]>([]);
  const [teamFilter,setTeamFilter]=useState(""),[weekFilter,setWeekFilter]=useState(""),[selectedJobs,setSelectedJobs]=useState<string[]>([]);
  const [pgvTeam,setPgvTeam]=useState(""),[pgvWeek,setPgvWeek]=useState(""),[receiveDate,setReceiveDate]=useState(isoToday());

  useEffect(()=>{ supabase.auth.getSession().then(({data})=>{setSession(data.session);setBusy(false)}); const {data}=supabase.auth.onAuthStateChange((_event,next)=>setSession(next)); return()=>data.subscription.unsubscribe(); },[]);
  useEffect(()=>{ if(session) void loadAll(); },[session]);

  async function loadAll(){
    setBusy(true); setError(""); setNotice("");
    const identityResult=await supabase.rpc("get_my_access");
    if(identityResult.error){setError(identityResult.error.message);setBusy(false);return;}
    const current=(identityResult.data?.[0]||null) as Identity|null;
    if(!current){setError("Tài khoản chưa được gắn hồ sơ hoạt động.");setBusy(false);return;}
    setIdentity(current);
    const base=[
      supabase.from("teams").select("id,team_code,leader_name,is_active,stt").is("deleted_at",null).order("stt"),
      supabase.from("workers").select("id,mnv,full_name,job_title,team_id,stt_in_team,teams(leader_name)").is("deleted_at",null).order("stt_in_team"),
      supabase.rpc("get_job_metrics",{p_team_id:null,p_week_id:null}),
      supabase.from("work_weeks").select("id,team_id,week_slot,start_date,end_date,status,teams(leader_name)").eq("status","ACTIVE").order("week_slot"),
      supabase.rpc("get_shared_work_weeks"),
      supabase.rpc("get_catalog_cap1"),
    ] as const;
    const [teamResult,workerResult,jobResult,weekResult,sharedWeekResult,catalogResult]=await Promise.all(base);
    const firstError=[teamResult,workerResult,jobResult,weekResult,sharedWeekResult,catalogResult].find(result=>result.error)?.error;
    if(firstError){setError(firstError.message);setBusy(false);return;}
    setTeams((teamResult.data||[]) as Team[]); setWorkers((workerResult.data||[]) as Worker[]); setJobs((jobResult.data||[]) as Job[]); setWeeks((weekResult.data||[]) as Week[]); setSharedWeeks((sharedWeekResult.data||[]) as SharedWeek[]); setCatalog((catalogResult.data||[]) as CatalogItem[]);
    const defaultTeam=current.team_id||((teamResult.data?.find(team=>team.is_active)?.id)||"");
    setTeamFilter(value=>value||defaultTeam); setPgvTeam(value=>value||defaultTeam);
    if(current.role_code==="ADMIN"){
      const [kpiResult,profileResult]=await Promise.all([
        supabase.rpc("get_kpi_evaluation"),
        supabase.from("profiles").select("id,role_code,is_active,worker_id,workers(mnv,full_name,teams(leader_name))").order("role_code"),
      ]);
      if(kpiResult.error) setNotice(`KPI đang khóa an toàn: ${kpiResult.error.message}`); else setKpis((kpiResult.data||[]) as Kpi[]);
      if(!profileResult.error) setProfiles((profileResult.data||[]) as Profile[]);
    }
    setBusy(false);
  }

  function navigate(next:PageId){setPage(next);setMenuOpen(false);}
  async function logout(){setIdentity(null);setTeams([]);setWorkers([]);setJobs([]);setWeeks([]);setSharedWeeks([]);setKpis([]);await supabase.auth.signOut();}
  function toast(message:string){setNotice(message);window.setTimeout(()=>setNotice(""),4500);}

  if(!isSupabaseConfigured) return <CenterCard title="Chưa cấu hình môi trường" text="Thiết lập Supabase URL và publishable key để kết nối hệ thống."/>;
  if(!session) return <Login busy={busy}/>;
  const isAdmin=identity?.role_code==="ADMIN";
  const navMain:[PageId,string,string][]=[
    ["home","🏠","Tổng Quan"],["danh-muc-to","🏢","Danh Mục Tổ"],["nhan-su","👥","Nhân Sự & Quỹ Lương"],["giao-viec","📋","Giao Việc & Hòa Vốn"],["danh-gia","📊","Đánh Giá KPI"],
  ];
  const navPgv:[PageId,string,string][]=[["pgv","📄","Phiếu PGV (Chung)"],["pgvcnch","👷","Phiếu PGV CNCH"]];
  return <div id="app">
    <div id="sidebar-overlay" className={menuOpen?"visible":""} role="button" tabIndex={0} aria-label="Đóng menu" onKeyDown={event=>{if(event.key==="Enter"||event.key===" ")setMenuOpen(false)}} onClick={()=>setMenuOpen(false)}/>
    <aside id="sidebar" className={menuOpen?"open":""}>
      <div className="logo-area"><img className="brand-logo" src="/project-logo.svg" alt="VINCONS"/><div className="app-title">THI CÔNG KPI MEP</div><div className="app-sub">Quản lý Giao Việc & Định Mức MEP</div></div>
      <div className="user-chip"><div className="u-name">👤 {identity?.full_name||session.user.email}</div><div className="u-role">{roleLabel(identity?.role_code)}</div><div className="u-email">{session.user.email}</div></div>
      <nav><div className="nav-section">Menu Chính</div>{navMain.map(item=><NavItem key={item[0]} item={item} active={page===item[0]} onClick={()=>navigate(item[0])}/>) }
        <div className="nav-section">Phiếu Giao Việc</div>{navPgv.map(item=><NavItem key={item[0]} item={item} active={page===item[0]} onClick={()=>navigate(item[0])}/>) }
        {isAdmin&&<><div className="nav-section">Quản Trị</div><NavItem item={["users","🔐","Phân Quyền"]} active={page==="users"} onClick={()=>navigate("users")}/></>}
      </nav>
      <div className="sidebar-footer"><button className="btn btn-secondary btn-full btn-sm" onClick={logout}>🚪 Đăng Xuất</button></div>
    </aside>
    <div id="main"><div id="topbar"><button className="menu-btn" onClick={()=>setMenuOpen(true)}>☰</button><div className="page-title">{PAGE_TITLES[page]}</div><div className="topbar-actions"><button className="btn-icon" onClick={loadAll} title="Làm mới">🔄</button></div></div>
      <div id="content">{error&&<div className="toast error static-toast">❌ {error}</div>}{notice&&<div className="toast static-toast">ℹ️ {notice}</div>}{busy?<Loading/>:<PageContent page={page} identity={identity} teams={teams} workers={workers} jobs={jobs} weeks={weeks} sharedWeeks={sharedWeeks} kpis={kpis} profiles={profiles} teamFilter={teamFilter} setTeamFilter={setTeamFilter} weekFilter={weekFilter} setWeekFilter={setWeekFilter} selectedJobs={selectedJobs} setSelectedJobs={setSelectedJobs} pgvTeam={pgvTeam} setPgvTeam={setPgvTeam} pgvWeek={pgvWeek} setPgvWeek={setPgvWeek} receiveDate={receiveDate} setReceiveDate={setReceiveDate} navigate={navigate} openTeam={()=>setModal("team")} openJob={()=>{setEditingJob(null);setModal("job")}} editJob={job=>{setEditingJob(job);setModal("job")}} reload={loadAll} toast={toast}/>}</div>
      <BottomNav page={page} navigate={navigate} openMenu={()=>setMenuOpen(true)}/>
    </div>
    {page==="giao-viec"&&<button className="fab show" onClick={()=>{setEditingJob(null);setModal("job")}}>＋</button>}
    {modal==="team"&&<TeamModal teams={teams} close={()=>setModal(null)} done={async()=>{setModal(null);await loadAll()}}/>}
    {modal==="job"&&<JobEditorModal teams={teams.filter(team=>team.is_active)} catalog={catalog} defaultTeam={identity?.team_id||""} job={editingJob as EditableJob|null} close={()=>{setModal(null);setEditingJob(null)}} done={async()=>{setModal(null);setEditingJob(null);await loadAll()}} notify={toast}/>}
  </div>;
}

function NavItem({item,active,onClick}:{item:[PageId,string,string];active:boolean;onClick:()=>void}){return <button className={`nav-item ${active?"active":""}`} onClick={onClick}><span className="nav-icon">{item[1]}</span>{item[2]}</button>}
function Loading(){return <div className="loading"><div className="spinner"/><div className="loading-text">Đang tải dữ liệu...</div></div>}
function CenterCard({title,text}:{title:string;text:string}){return <main className="auth-page"><div className="auth-card"><Brand/><h1>{title}</h1><p>{text}</p></div></main>}
function Brand(){return <div className="auth-brand"><img src="/project-logo.svg" alt="VINCONS"/><div><strong>THI CÔNG KPI MEP</strong><span>Quản lý Giao Việc & Định Mức MEP</span></div></div>}
function Login({busy}:{busy:boolean}){const [email,setEmail]=useState(""),[password,setPassword]=useState(""),[message,setMessage]=useState("");async function submit(event:FormEvent){event.preventDefault();setMessage("");const {error}=await supabase.auth.signInWithPassword({email,password});if(error)setMessage("Email hoặc mật khẩu không đúng.");}return <main className="auth-page"><form className="auth-card" onSubmit={submit}><Brand/><div className="login-kicker">CỔNG ĐIỀU HÀNH</div><h1>Đăng nhập THI CÔNG KPI MEP</h1><p>Hệ thống quản lý giao việc, nhân sự, quỹ lương và KPI dự án VINCONS.</p><div className="form-group"><label>Email</label><input className="form-control" type="email" value={email} onChange={event=>setEmail(event.target.value)} required/></div><div className="form-group"><label>Mật khẩu</label><input className="form-control" type="password" value={password} onChange={event=>setPassword(event.target.value)} required/></div>{message&&<div className="login-error">{message}</div>}<button className="btn btn-primary btn-full" disabled={busy}>Đăng Nhập Hệ Thống</button></form></main>}

type PageProps={page:PageId;identity:Identity|null;teams:Team[];workers:Worker[];jobs:Job[];weeks:Week[];sharedWeeks:SharedWeek[];kpis:Kpi[];profiles:Profile[];teamFilter:string;setTeamFilter:(v:string)=>void;weekFilter:string;setWeekFilter:(v:string)=>void;selectedJobs:string[];setSelectedJobs:(v:string[])=>void;pgvTeam:string;setPgvTeam:(v:string)=>void;pgvWeek:string;setPgvWeek:(v:string)=>void;receiveDate:string;setReceiveDate:(v:string)=>void;navigate:(v:PageId)=>void;openTeam:()=>void;openJob:()=>void;editJob:(job:Job)=>void;reload:()=>Promise<void>;toast:(v:string)=>void};
function PageContent(props:PageProps){switch(props.page){case"home":return <Home {...props}/>;case"danh-muc-to":return <TeamsPage {...props}/>;case"nhan-su":return <WorkersPage {...props}/>;case"giao-viec":return <JobsPage {...props}/>;case"danh-gia":return <KpiPage {...props}/>;case"pgv":return <PgvPage {...props}/>;case"pgvcnch":return <PgvCnchPage {...props}/>;case"users":return <UsersPage {...props}/>;}}

function Home({identity,teams,jobs,kpis,navigate,openJob}:PageProps){const passed=kpis.filter(k=>Number(k.difference_vnd)>=0).length,failed=kpis.filter(k=>Number(k.difference_vnd)<0).length;return <><div className="vc-hero"><div className="hero-title">Xin chào, {identity?.full_name||"Admin"}!</div><div className="hero-sub"><img className="brand-logo" src="/project-logo.svg" alt=""/> Hệ thống Quản lý KPI - MEP VINCONS</div><div className="hero-date">📅 {new Date().toLocaleDateString("vi-VN",{weekday:"long",year:"numeric",month:"long",day:"numeric"})}</div></div><div className="stats-grid"><Stat tone="green" value={passed} label="🟢 Tổ ĐẠT KPI"/><Stat tone="red" value={failed} label="🔴 Tổ KHÔNG ĐẠT"/><Stat value={jobs.length} label="📋 Việc đang giao"/><Stat tone="cyan" value={teams.filter(t=>t.is_active).length} label="🏢 Tổ hoạt động"/></div><div className="card"><div className="card-header"><span className="ch-icon">⚠️</span><span className="ch-title">Cảnh báo KPI - Cần xử lý</span></div><div className="card-body">{failed?<div className="kpi-alert-list">{kpis.filter(k=>Number(k.difference_vnd)<0).map(k=><div className="kpi-alert" key={k.team_name}><span>🔴</span><div><strong>{k.team_name}</strong><small>Chênh lệch: {money.format(Number(k.difference_vnd))}</small></div><button className="btn btn-sm btn-secondary" onClick={()=>navigate("danh-gia")}>Xem</button></div>)}</div>:<div className="empty-compact">🟢 Tất cả các Tổ đang đạt định mức KPI hoặc chưa có dữ liệu đánh giá.</div>}</div></div><div className="card"><div className="card-header"><span className="ch-icon">⚡</span><span className="ch-title">Thao Tác Nhanh</span></div><div className="card-body quick-grid"><button className="btn btn-primary" onClick={openJob}>➕ Giao Việc Mới</button><button className="btn btn-secondary" onClick={()=>navigate("danh-gia")}>📊 Xem KPI</button><button className="btn btn-cyan" onClick={()=>navigate("pgv")}>📄 Phiếu PGV</button><button className="btn btn-secondary" onClick={()=>navigate("pgvcnch")}>👷 Phiếu CNCH</button></div></div></>}
function Stat({tone="",value,label}:{tone?:string;value:number;label:string}){return <div className={`stat-card ${tone}`}><div className="sc-value">{value}</div><div className="sc-label">{label}</div></div>}

function TeamsPage({identity,teams,workers,openTeam}:PageProps){const canAdd=identity?.role_code==="ADMIN";return <div className="card"><div className="card-header"><span className="ch-icon">🏢</span><span className="ch-title">Danh Mục Các Tổ Đang Hoạt Động ({teams.filter(t=>t.is_active).length})</span>{canAdd&&<button className="ch-action" onClick={openTeam}>➕ Kích Hoạt Tổ</button>}</div><div className="card-body"><div className="to-grid">{teams.filter(t=>t.is_active).map(team=><div className="to-card" key={team.id}><div className="tc-icon">👷</div><div className="tc-name">{team.leader_name}</div><div className="tc-count">{workers.filter(w=>w.team_id===team.id).length} CNCH · {team.team_code}</div></div>)}</div></div></div>}

function WorkersPage({identity,teams,reload,toast}:PageProps){return <TeamPayrollPanel teams={teams} canEdit={identity?.role_code==="ADMIN"} onChanged={reload} notify={toast}/>;}

function JobsPage({identity,teams,jobs,weeks,sharedWeeks,teamFilter,setTeamFilter,weekFilter,setWeekFilter,selectedJobs,setSelectedJobs,reload,toast,editJob}:PageProps){
  const filtered=jobs.filter(j=>(!teamFilter||j.team_id===teamFilter)&&(!weekFilter||(weekFilter==="none"?!j.week_id:weeks.find(w=>w.id===j.week_id)?.week_slot===Number(weekFilter))));
  const teamWeeks=teamFilter?weeks.filter(w=>w.team_id===teamFilter):[];
  const [groupBusy,setGroupBusy]=useState(false);
  function toggle(id:string){setSelectedJobs(selectedJobs.includes(id)?selectedJobs.filter(v=>v!==id):[...selectedJobs,id])}
  async function assign(slot:number){if(!selectedJobs.length){toast("Hãy chọn ít nhất một công việc.");return}const {error}=await supabase.rpc("assign_jobs_to_shared_week",{p_week_slot:slot,p_job_ids:selectedJobs});if(error){toast(error.message);return}setSelectedJobs([]);toast(`Đã gộp công việc vào Tuần ${slot}.`);await reload()}
  async function groupJobs(){if(groupBusy)return;const chosen=jobs.filter(j=>selectedJobs.includes(j.id)),issue=validateJobGroup(chosen);if(issue){toast(issue);return}if(!window.confirm(`Tạo một Mã Nhóm cho ${chosen.length} công việc?\n\nChỉ thực hiện khi các việc dùng chung một tổ nhân sự. Chi phí nhân công của nhóm sẽ được phân bổ một lần theo công thức bảng tính.`))return;setGroupBusy(true);const {data,error}=await supabase.rpc("create_job_group",{p_job_ids:selectedJobs});setGroupBusy(false);if(error){toast(error.message);return}setSelectedJobs([]);toast(`Đã tạo Mã Nhóm: ${data}`);await reload()}
  async function removeGroup(){if(groupBusy)return;const chosen=jobs.filter(j=>selectedJobs.includes(j.id)),codes=[...new Set(chosen.map(j=>j.group_code).filter((v):v is string=>!!v))];if(!codes.length){toast("Hãy chọn ít nhất một công việc đang có Mã Nhóm.");return}if(!window.confirm(`Xóa Mã Nhóm ${codes.join(", ")}?\n\nTất cả công việc thuộc các mã này sẽ được gỡ nhóm; nội dung giao việc và công thức được giữ nguyên.`))return;setGroupBusy(true);const {data,error}=await supabase.rpc("remove_job_groups",{p_group_codes:codes});setGroupBusy(false);if(error){toast(error.message);return}const result=data as {group_count:number;job_count:number};setSelectedJobs([]);toast(`Đã xóa ${result.group_count} Mã Nhóm khỏi ${result.job_count} công việc.`);await reload()}
  async function unassign(){if(!selectedJobs.length)return;const {error}=await supabase.rpc("unassign_jobs_from_week",{p_job_ids:selectedJobs});if(error){toast(error.message);return}setSelectedJobs([]);toast("Đã hủy gộp công việc.");await reload()}
  return <><div className="card"><div className="card-header"><span className="ch-icon">📋</span><span className="ch-title">Giao Việc & Hòa Vốn</span></div><div className="card-body"><div className="filters-row"><select className="form-control" value={teamFilter} onChange={e=>{setTeamFilter(e.target.value);setSelectedJobs([])}}><option value="">Tất cả Tổ</option>{teams.filter(t=>t.is_active).map(t=><option key={t.id} value={t.id}>{t.leader_name}</option>)}</select><select className="form-control" value={weekFilter} onChange={e=>setWeekFilter(e.target.value)}><option value="">Tất cả Tuần</option><option value="none">Chưa gộp Tuần</option>{sharedWeeks.map(w=><option key={w.id} value={w.week_slot}>Tuần {w.week_slot}: {viDate(w.start_date)}–{viDate(w.end_date)}</option>)}</select></div><StaffingCoverage teamId={teamFilter} teamName={teams.find(team=>team.id===teamFilter)?.leader_name||""} jobs={jobs}/><div className="job-group-actions"><button className="btn btn-green" disabled={groupBusy||selectedJobs.length<2} onClick={groupJobs}>🔗 Tạo Mã Nhóm ({selectedJobs.length})</button><button className="btn btn-secondary" disabled={groupBusy||!selectedJobs.length} onClick={removeGroup}>✂️ Xóa Mã Nhóm</button></div><WeekToolbar teamWeeks={teamWeeks} sharedWeeks={sharedWeeks} selected={selectedJobs.length} assign={assign} unassign={unassign} reload={reload} toast={toast} canManage={identity?.role_code==="ADMIN"}/></div></div><div className="job-list">{filtered.map(job=>{const week=weeks.find(w=>w.id===job.week_id);return <article className={`job-card ${Number(job.difference)<0?"danger":"safe"}`} key={job.id}><label className="jc-select"><input type="checkbox" checked={selectedJobs.includes(job.id)} onChange={()=>toggle(job.id)}/></label><div className="jc-header"><span className="jc-icon">🔧</span><div className="jc-title">{job.content}</div><button className="btn btn-sm btn-secondary no-print" onClick={()=>editJob(job)}>✏️ Sửa</button></div><div className="jc-meta"><span>🏢 {teams.find(team=>team.id===job.team_id)?.leader_name}</span><span>📅 {viDate(job.start_date)}–{viDate(job.end_date)}</span><span>📍 {job.location||"Chưa có vị trí"}</span></div><div className="jc-status"><span className="badge badge-navy">{job.category_name}</span>{week?<span className="badge badge-week">TUẦN {week.week_slot}</span>:<span className="badge badge-yellow">CHƯA GỘP</span>}</div><div className="jc-numbers"><div className="jc-num"><div className="val">{job.quantity}</div><div className="lbl">Khối lượng</div></div><div className="jc-num"><div className="val">{job.count_leader+job.count_worker1+job.count_worker2+job.count_worker3+job.count_helper}</div><div className="lbl">Nhân công</div></div><div className="jc-num"><div className="val">{job.group_code||"—"}</div><div className="lbl">Mã nhóm</div></div><div className="jc-num"><div className="val">{money.format(Number(job.total_breakeven||0))}</div><div className="lbl">Hòa vốn</div></div><div className="jc-num"><div className="val">{money.format(Number(job.production_value||0))}</div><div className="lbl">Sản lượng</div></div><div className="jc-num"><div className="val">{money.format(Number(job.difference||0))}</div><div className="lbl">Chênh lệch</div></div></div></article>})}{!filtered.length&&<Empty icon="📋" title="Chưa có việc nào được giao"/>}</div></>
}

function WeekToolbar({teamWeeks,sharedWeeks,selected,assign,unassign,reload,toast,canManage}:{teamWeeks:Week[];sharedWeeks:SharedWeek[];selected:number;assign:(slot:number)=>Promise<void>;unassign:()=>Promise<void>;reload:()=>Promise<void>;toast:(v:string)=>void;canManage:boolean}){
  const [show,setShow]=useState(false),[slot,setSlot]=useState("1"),[start,setStart]=useState(""),[end,setEnd]=useState(""),[saving,setSaving]=useState(false);
  function edit(target?:SharedWeek){const nextSlot=target?.week_slot||[1,2,3,4].find(n=>!sharedWeeks.some(w=>w.week_slot===n))||1;setSlot(String(nextSlot));setStart(target?.start_date||isoToday());setEnd(target?.end_date||isoToday());setShow(true)}
  async function save(){if(!start||!end){toast("Hãy nhập đủ ngày theo dd/mm/yyyy.");return}setSaving(true);const {error}=await supabase.rpc("upsert_shared_work_week",{p_week_slot:Number(slot),p_start_date:start,p_end_date:end});setSaving(false);if(error){toast(error.message);return}setShow(false);toast(`Đã lưu Tuần ${slot} dùng chung cho các Tổ.`);await reload()}
  return <div className="week-tools"><div className="week-actions">{canManage&&<button className="btn btn-sm btn-secondary" onClick={()=>edit()}>🗓️ Tạo Tuần</button>}{sharedWeeks.map(w=><span key={w.id} className="week-shared-actions"><button className="btn btn-sm btn-primary" disabled={!selected} onClick={()=>assign(w.week_slot)}>Gộp vào Tuần {w.week_slot}</button>{canManage&&<button className="btn btn-sm btn-secondary" onClick={()=>edit(w)}>✏️ Sửa Tuần {w.week_slot}</button>}</span>)}<button className="btn btn-sm btn-red" disabled={!selected} onClick={unassign}>Hủy gộp ({selected})</button>{canManage&&teamWeeks.map(w=><WeekArchiveButton key={`archive-${w.id}`} week={w} onDone={reload} notify={toast}/>)}</div>{show&&<div className="week-create"><select className="form-control" value={slot} onChange={e=>{const next=e.target.value,target=sharedWeeks.find(w=>w.week_slot===Number(next));setSlot(next);setStart(target?.start_date||isoToday());setEnd(target?.end_date||isoToday())}}>{[1,2,3,4].map(n=><option key={n} value={n}>Tuần {n}</option>)}</select><DateInput value={start} onChange={setStart}/><DateInput value={end} onChange={setEnd}/><button className="btn btn-green" disabled={saving||!start||!end} onClick={save}>{saving?"Đang lưu…":"Lưu Tuần dùng chung"}</button></div>}</div>
}

function KpiPage({kpis}:PageProps){return <><div className="section-divider"><span>Bảng Đánh Giá KPI Tổng Hợp</span></div><div className="kpi-grid">{kpis.map(k=><article className={`kpi-card ${Number(k.difference_vnd)<0?"danger":"safe"}`} key={k.team_name}><div className="kpi-team"><span>{Number(k.difference_vnd)<0?"🔴":"🟢"}</span><strong>{k.team_name}</strong><span className={`badge ${Number(k.difference_vnd)<0?"badge-red":"badge-green"}`}>{k.evaluation}</span></div><div className="kpi-values"><div><span>Quỹ lương</span><b>{money.format(Number(k.total_payroll))}</b></div><div><span>Sản lượng</span><b>{money.format(Number(k.total_production))}</b></div><div><span>Chênh lệch</span><b>{money.format(Number(k.difference_vnd))}</b></div></div><div className="kpi-bar"><div className={`kpi-bar-fill ${Number(k.difference_vnd)<0?"danger":"safe"}`} style={{width:`${Math.min(100,Math.max(5,Number(k.total_production)/(Number(k.total_payroll)||1)*100))}%`}}/></div></article>)}{!kpis.length&&<Empty icon="📊" title="KPI đang khóa an toàn hoặc chưa đủ dữ liệu"/>}</div></>}

function PgvPage({teams,weeks,pgvTeam,setPgvTeam,pgvWeek,setPgvWeek,toast}:PageProps){return <PgvCommonRpc teams={teams} weeks={weeks} teamId={pgvTeam} setTeamId={setPgvTeam} weekId={pgvWeek} setWeekId={setPgvWeek} notify={toast}/>;}
function PgvCnchPage({identity,teams,pgvTeam,setPgvTeam,receiveDate,setReceiveDate,toast}:PageProps){return <PgvCnchRpc teams={teams} teamId={pgvTeam} setTeamId={setPgvTeam} receiveDate={receiveDate} setReceiveDate={setReceiveDate} canEdit={["ADMIN","GIAM_SAT","TO_TRUONG"].includes(identity?.role_code||"")} notify={toast}/>;}
function UsersPage({teams,workers,toast}:PageProps){return <UsersAdminPanel teams={teams} workers={workers} notify={toast}/>;}
function Empty({icon,title}:{icon:string;title:string}){return <div className="empty-state"><div className="es-icon">{icon}</div><div className="es-title">{title}</div></div>}

function TeamModal({teams,close,done}:{teams:Team[];close:()=>void;done:()=>Promise<void>}){const inactive=teams.filter(t=>!t.is_active),[id,setId]=useState(inactive[0]?.id||""),[saving,setSaving]=useState(false);async function submit(event:FormEvent){event.preventDefault();setSaving(true);const {error}=await supabase.from("teams").update({is_active:true}).eq("id",id);setSaving(false);if(error){window.alert(error.message);return;}await done();}return <Modal title="➕ Kích Hoạt Tổ Thi Công Mới" close={close}><form onSubmit={submit}><div className="form-group"><label>Chọn Tổ Từ Danh Mục Chuẩn Supabase</label><select className="form-control" value={id} onChange={e=>setId(e.target.value)} required>{inactive.map(t=><option key={t.id} value={t.id}>{t.leader_name}</option>)}</select></div><div className="form-actions"><button type="button" className="btn btn-secondary" onClick={close}>Hủy</button><button className="btn btn-primary" disabled={saving||!id}>💾 Kích Hoạt Tổ</button></div></form></Modal>}
function Modal({title,close,children}:{title:string;close:()=>void;children:ReactNode}){return <div className="modal-overlay open"><div className="modal"><div className="modal-header"><div className="modal-title">{title}</div><button className="modal-close" onClick={close}>✕</button></div>{children}</div></div>}
function BottomNav({page,navigate,openMenu}:{page:PageId;navigate:(p:PageId)=>void;openMenu:()=>void}){const items:[PageId,string,string][]=[["home","🏠","Tổng quan"],["giao-viec","📋","Giao việc"],["danh-gia","📊","KPI"],["pgv","📄","Phiếu"]];return <nav id="bottom-nav"><div className="bn-items">{items.map(item=><button key={item[0]} className={`bn-item ${page===item[0]?"active":""}`} onClick={()=>navigate(item[0])}><span className="bn-icon">{item[1]}</span>{item[2]}</button>)}<button className="bn-item" onClick={openMenu}><span className="bn-icon">☰</span>Menu</button></div></nav>}
