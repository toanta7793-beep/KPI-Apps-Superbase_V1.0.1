"use client";
/* eslint-disable jsx-a11y/label-has-associated-control */
import { FormEvent, useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";
import { DateInput } from "./DateInput";
import { operationError } from "./importErrors";
import { buildSuggestParams, endDateFor, SuggestMode } from "./suggestParams";

type Team={id:string;leader_name:string}; type Catalog={category_name:string};
export type EditableJob={id:string;team_id:string;start_date:string;end_date:string;category_name:string;content:string;location:string|null;quantity:number;count_leader:number;count_worker1:number;count_worker2:number;count_worker3:number;count_helper:number;group_code:string|null};
type Cap2={content:string;unit:string|null}; type Metrics={difference:number;production_value:number;actual_labor_cost:number;evaluation:string;target_daily:number};
const money=new Intl.NumberFormat("vi-VN",{style:"currency",currency:"VND",maximumFractionDigits:0});
const fold=(value:string)=>value.normalize("NFD").replace(/[\u0300-\u036f]/g,"").replace(/đ/g,"d").replace(/Đ/g,"D").toLowerCase();
const words=(value:string,accentSensitive:boolean)=>(accentSensitive?value.toLowerCase():fold(value)).match(/[a-zà-ỹđ0-9]+/giu)||[];
const hasVietnameseMarks=(value:string)=>/[à-ỹđ]/iu.test(value);
function searchScore(label:string,query:string){const q=query.trim();if(!q)return 1;const sensitive=hasVietnameseMarks(q),queryWords=words(q,sensitive),labelWords=words(label,sensitive);if(!queryWords.length)return 0;let score=0;for(const token of queryWords){const exact=labelWords.findIndex(word=>word===token);if(exact>=0){score+=100-exact;continue}const prefix=labelWords.findIndex(word=>word.startsWith(token));if(prefix>=0){score+=50-prefix;continue}return 0}return score}

type Suggestion={che_do:string;count_worker1:number|null;count_worker2:number|null;count_worker3:number|null;
  count_helper:number|null;tong_nguoi:number|null;work_days:number|null;quantity:number|null;
  chi_phi_nhan_cong:number|null;chenh_lech:number|null;ghi_chu:string};
const dong=new Intl.NumberFormat("vi-VN",{maximumFractionDigits:0});

export function JobEditorModal({teams,catalog,defaultTeam,job,close,done,notify}:{teams:Team[];catalog:Catalog[];defaultTeam:string;job:EditableJob|null;close:()=>void;done:()=>Promise<void>;notify:(v:string)=>void}){
  const [teamId,setTeamId]=useState(job?.team_id||defaultTeam||teams[0]?.id||""),[start,setStart]=useState(job?.start_date||""),[end,setEnd]=useState(job?.end_date||""),[category,setCategory]=useState(job?.category_name||""),[content,setContent]=useState(job?.content||""),[location,setLocation]=useState(job?.location||""),[quantity,setQuantity]=useState(String(job?.quantity||""));
  const [counts,setCounts]=useState({leader:String(job?.count_leader||0),w1:String(job?.count_worker1||0),w2:String(job?.count_worker2||0),w3:String(job?.count_worker3||0),helper:String(job?.count_helper||0)}),[items,setItems]=useState<Cap2[]>([]),[saving,setSaving]=useState(false),[preview,setPreview]=useState<Metrics|null>(null),[previewError,setPreviewError]=useState(""),[suggestionsOpen,setSuggestionsOpen]=useState(false);
  useEffect(()=>{if(!category){void Promise.resolve().then(()=>setItems([]));return}void supabase.rpc("get_catalog_cap2",{p_category_name:category}).then(({data})=>setItems((data||[]) as Cap2[]))},[category]);
  const matches=useMemo(()=>items.map(item=>({item,score:searchScore(item.content,content)})).filter(result=>result.score>0).sort((a,b)=>b.score-a.score||a.item.content.localeCompare(b.item.content,"vi")).slice(0,12).map(result=>result.item),[items,content]);
  useEffect(()=>{if(!teamId||!start||!end||!category||!content||!quantity)return;const timer=window.setTimeout(async()=>{setPreview(null);setPreviewError("");const {data,error}=await supabase.rpc("preview_job_metrics",{p_team_id:teamId,p_start_date:start,p_end_date:end,p_category_name:category,p_content:content,p_quantity:Number(quantity),p_count_leader:Number(counts.leader),p_count_worker1:Number(counts.w1),p_count_worker2:Number(counts.w2),p_count_worker3:Number(counts.w3),p_count_helper:Number(counts.helper)});if(error)setPreviewError(operationError(error.message));else setPreview(data as Metrics)},350);return()=>window.clearTimeout(timer)},[teamId,start,end,category,content,quantity,counts]);
  // Gợi ý nhân công / số ngày / khối lượng. Toàn bộ phép tính nằm ở SQL (migration 052) và
  // dùng ĐÚNG công thức chạy khi bấm Lưu, nên con số gợi ý và con số lưu không thể lệch nhau.
  const [suggestMode,setSuggestMode]=useState<SuggestMode>("NHAN_CONG");
  const [suggestions,setSuggestions]=useState<Suggestion[]>([]);
  const [suggestBusy,setSuggestBusy]=useState(false),[suggestNote,setSuggestNote]=useState("");

  async function askSuggest(){
    const built=buildSuggestParams({teamId,category,content,start,end,quantity,counts},suggestMode);
    // Thiếu dữ kiện thì nói ngay ô nào thiếu, không gửi lên rồi nhận về mã lỗi chung chung.
    if("error" in built){setSuggestions([]);setSuggestNote(built.error);return}
    setSuggestBusy(true);setSuggestNote("");
    const {data,error}=await supabase.rpc("suggest_job_staffing",built);
    setSuggestBusy(false);
    if(error){setSuggestions([]);setSuggestNote(operationError(error.message));return}
    const rows=(data||[]) as Suggestion[];
    setSuggestions(rows.filter(r=>r.che_do==="NHAN_CONG"||r.che_do==="SO_NGAY"||r.che_do==="KHOI_LUONG"));
    // Hàm SQL trả về một dòng giải thích khi không có phương án — hiện nguyên văn thay vì
    // để danh sách rỗng, vì rỗng trông như hỏng và không dạy người dùng điều gì.
    const chan=rows.find(r=>r.che_do==="KHONG_CO_PHUONG_AN"||r.che_do==="KHONG_DU_DU_LIEU");
    if(chan)setSuggestNote(chan.ghi_chu);
  }

  function applySuggestion(row:Suggestion){
    if(row.che_do==="NHAN_CONG"){
      setCounts(prev=>({...prev,w1:String(row.count_worker1??0),w2:String(row.count_worker2??0),
        w3:String(row.count_worker3??0),helper:String(row.count_helper??0)}));
      notify("Đã áp dụng cơ cấu nhân công. Xem lại ô lãi/lỗ bên dưới trước khi lưu.");
    }else if(row.che_do==="SO_NGAY"&&row.work_days){
      setEnd(endDateFor(start,row.work_days));
      notify(`Đã đặt ngày kết thúc theo ${row.work_days} ngày thi công.`);
    }else if(row.che_do==="KHOI_LUONG"&&row.quantity!=null){
      setQuantity(String(row.quantity));
      notify("Đã áp dụng khối lượng tối thiểu để có lãi.");
    }
    setSuggestions([]);
  }

  async function submit(e:FormEvent){e.preventDefault();if(!items.some(i=>i.content===content)&&!/[đd]ào tạo|phát sinh/i.test(category)){notify("Hãy chọn Công việc Cấp 2 trong danh mục gợi ý.");return}setSaving(true);const p={p_team_id:teamId,p_start_date:start,p_end_date:end,p_category_name:category,p_content:content,p_location:location,p_quantity:Number(quantity),p_count_leader:Number(counts.leader),p_count_worker1:Number(counts.w1),p_count_worker2:Number(counts.w2),p_count_worker3:Number(counts.w3),p_count_helper:Number(counts.helper)};const result=job?await supabase.rpc("update_job",{p_job_id:job.id,...p}):await supabase.rpc("create_job",{p_request_key:crypto.randomUUID(),...p});setSaving(false);if(result.error){notify(operationError(result.error.message));return}notify(job?"Đã cập nhật công việc.":"Đã lưu giao việc mới.");await done()}
  const countField=(key:keyof typeof counts,label:string)=><div className="form-group"><label>{label}</label><input className="form-control" min="0" type="number" value={counts[key]} onChange={e=>setCounts(v=>({...v,[key]:e.target.value}))}/></div>;
  return <div className="modal-overlay open"><div className="modal"><div className="modal-header"><div className="modal-title">{job?"✏️ Sửa công việc":"➕ Giao Việc Mới"}</div><button className="modal-close" onClick={close}>×</button></div><div className="modal-body"><form onSubmit={submit}>{job?.group_code&&<div className="login-error">Công việc đang thuộc nhóm {job.group_code}. Hãy hủy nhóm trước khi sửa.</div>}<div className="form-group"><label>🏢 Tổ thi công</label><select className="form-control" value={teamId} onChange={e=>setTeamId(e.target.value)} required>{teams.map(t=><option key={t.id} value={t.id}>{t.leader_name}</option>)}</select></div><div className="form-row"><div className="form-group"><label>📅 Ngày bắt đầu</label><DateInput value={start} onChange={setStart}/></div><div className="form-group"><label>📅 Ngày kết thúc</label><DateInput value={end} onChange={setEnd}/></div></div><div className="form-group"><label>🏗️ Hạng mục Cấp 1</label><select className="form-control" value={category} onChange={e=>{setCategory(e.target.value);setContent("")}} required><option value="">-- Chọn hạng mục --</option>{catalog.map(c=><option key={c.category_name}>{c.category_name}</option>)}</select></div><div className="form-group cap2-search"><label>🔎 Công việc Cấp 2 — gõ không dấu cũng tìm được</label><input className="form-control" value={content} onFocus={()=>setSuggestionsOpen(true)} onChange={e=>{setContent(e.target.value);setSuggestionsOpen(true)}} onBlur={()=>window.setTimeout(()=>setSuggestionsOpen(false),120)} placeholder="Ví dụ: ống hoặc ong" autoComplete="off" required/>{category&&content&&suggestionsOpen&&matches.length>0&&<div className="cap2-results">{matches.map(i=><button type="button" key={i.content} onMouseDown={e=>e.preventDefault()} onClick={()=>{setContent(i.content);setSuggestionsOpen(false)}}><span>{i.content}</span><small>{i.unit||""}</small></button>)}</div>}</div><div className="form-row"><div className="form-group"><label>📍 Vị trí thi công</label><input className="form-control" value={location} onChange={e=>setLocation(e.target.value)}/></div><div className="form-group"><label>📦 Tổng khối lượng</label><input className="form-control" min="0" step="any" type="number" value={quantity} onChange={e=>setQuantity(e.target.value)} required/></div></div><div className="section-divider"><span>Số lượng nhân công</span></div><div className="form-row">{countField("leader","Tổ trưởng")}{countField("w1","Thợ bậc 1")}{countField("w2","Thợ bậc 2")}{countField("w3","Thợ bậc 3")}</div>{countField("helper","Thợ phụ")}<div className="suggest-box no-print"><div className="suggest-head"><span>💡 Gợi ý tính sẵn</span><select className="form-control" value={suggestMode} onChange={e=>{setSuggestions([]);setSuggestNote("");setSuggestMode(e.target.value as SuggestMode)}}><option value="NHAN_CONG">Gợi ý số lượng nhân công</option><option value="SO_NGAY">Gợi ý số ngày thi công</option><option value="KHOI_LUONG">Gợi ý khối lượng tối thiểu</option></select><button type="button" className="btn btn-sm btn-secondary" disabled={suggestBusy} onClick={()=>void askSuggest()}>{suggestBusy?"Đang tính…":"Tính gợi ý"}</button></div><small className="suggest-hint">Tính bằng đúng công thức hòa vốn đang dùng — chênh lệch luôn dương và không quá 500.000 đ.</small>{suggestNote&&<div className="suggest-note">{suggestNote}</div>}{suggestions.map((row,i)=><button type="button" className="suggest-row" key={i} onClick={()=>applySuggestion(row)}><span className="suggest-main">{row.che_do==="NHAN_CONG"?`${row.count_worker1?`${row.count_worker1} thợ bậc 1  `:""}${row.count_worker2?`${row.count_worker2} thợ bậc 2  `:""}${row.count_worker3?`${row.count_worker3} thợ bậc 3  `:""}${row.count_helper?`${row.count_helper} thợ phụ`:""}`:row.che_do==="SO_NGAY"?`${row.work_days} ngày thi công`:`${row.quantity} (khối lượng tối thiểu)`}</span><span className="suggest-diff">lãi {dong.format(Number(row.chenh_lech||0))} đ</span></button>)}</div><div className={`job-preview ${preview&&preview.difference<0?"loss":"profit"}`}><strong>{preview?preview.evaluation:"Lãi / lỗ dự kiến"}</strong>{preview?<><b>{money.format(Number(preview.difference))}</b>{/* Dùng đúng tên gọi như ở thẻ công việc: cùng một con số thì phải cùng một tên, nếu không người dùng phải tự đoán xem hai chỗ có nói về cùng thứ hay không. */}<span>Giá trị theo KL (U) {money.format(Number(preview.production_value))} · Chi phí NC dự kiến (V) {money.format(Number(preview.actual_labor_cost))}</span></>:<span>{previewError||"Nhập đủ ngày, công việc, khối lượng và nhân công để xem trước."}</span>}</div><div className="form-actions"><button type="button" className="btn btn-secondary" onClick={close}>Hủy</button><button className="btn btn-primary" disabled={saving||!!job?.group_code}>{saving?"Đang lưu…":"💾 Lưu Giao Việc"}</button></div></form></div></div></div>;
}
