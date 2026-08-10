import { createClient } from "@supabase/supabase-js";

const reply=(body:unknown,status=200)=>Response.json(body,{status,headers:{"Cache-Control":"no-store"}});
export async function POST(request:Request){
  try{
    const token=request.headers.get("authorization")?.replace(/^Bearer\s+/i,"").trim();
    const operationId=request.headers.get("x-operation-id")||"";
    const weekId=request.headers.get("x-week-id")||"";
    if(!token||!operationId||!weekId) return reply({error:"ARCHIVE_HEADERS_REQUIRED"},400);
    const url=process.env.NEXT_PUBLIC_SUPABASE_URL,publishable=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,secret=process.env.SUPABASE_SECRET_KEY;
    if(!url||!publishable||!secret) return reply({error:"SERVER_ARCHIVE_NOT_CONFIGURED"},500);
    const caller=createClient(url,publishable,{global:{headers:{Authorization:`Bearer ${token}`}},auth:{persistSession:false,autoRefreshToken:false}});
    const {data:identity,error:identityError}=await caller.rpc("get_my_access");
    if(identityError||identity?.[0]?.role_code!=="ADMIN") return reply({error:"FORBIDDEN"},403);
    const {data:prepared,error:prepareError}=await caller.rpc("prepare_week_archive",{p_operation_id:operationId,p_week_id:weekId});
    if(prepareError) throw prepareError;
    const bytes=new Uint8Array(await request.arrayBuffer());
    if(bytes.length<1000||bytes.length>10*1024*1024) return reply({error:"INVALID_EXCEL_BACKUP_SIZE"},400);
    const digest=Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",bytes))).map(value=>value.toString(16).padStart(2,"0")).join("");
    const path=`${prepared.team_id}/${prepared.week_id}/${operationId}.xlsx`;
    const admin=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
    const {error:uploadError}=await admin.storage.from("kpi-week-backups").upload(path,bytes,{contentType:"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",upsert:true});
    if(uploadError) throw uploadError;
    const {data:count,error:finalizeError}=await caller.rpc("finalize_week_archive",{p_operation_id:operationId,p_backup_path:path,p_backup_sha256:digest});
    if(finalizeError) throw finalizeError;
    return reply({ok:true,row_count:count,backup_path:path,sha256:digest});
  }catch(error){return reply({error:error instanceof Error?error.message:"ARCHIVE_FAILED",failClosed:true},400)}
}
