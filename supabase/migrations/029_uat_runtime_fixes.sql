-- 029_uat_runtime_fixes.sql
-- Fix safeupdate-compatible roster replacement and match Sheet Mã Nhóm rules.

create or replace function public.admin_import_worker_roster(
  p_request_key uuid,p_source_name text,p_source_sha256 text,p_workers jsonb,
  p_active_team_names text[] default '{}'::text[]
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_before jsonb;v_before_active uuid[];v_worker_count int;v_team_count int;v_archived_count int;v_existing jsonb;
begin
  if app.current_role()<>'ADMIN' then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if p_request_key is null or btrim(coalesce(p_source_name,''))='' then raise exception 'IMPORT_METADATA_REQUIRED'; end if;
  if coalesce(p_source_sha256,'')!~'^[0-9a-f]{64}$' then raise exception 'INVALID_SOURCE_HASH'; end if;
  if jsonb_typeof(p_workers)<>'array' or jsonb_array_length(p_workers)=0 or jsonb_array_length(p_workers)>10000 then raise exception 'INVALID_WORKER_ROSTER_SIZE'; end if;
  select jsonb_build_object('worker_count',b.after_worker_count,'team_count',b.after_team_count,'source_sha256',b.source_sha256,'idempotent',true)
    into v_existing from app.worker_roster_import_backups b where b.request_key=p_request_key;
  if v_existing is not null then return v_existing; end if;

  create temporary table roster_rows(mnv text primary key,full_name text not null,job_title text not null,team_name text not null,team_key text not null,stt_in_team int not null,team_id uuid) on commit drop;
  insert into roster_rows(mnv,full_name,job_title,team_name,team_key,stt_in_team)
  select upper(btrim(x.mnv)),btrim(x.full_name),btrim(x.job_title),btrim(x.team_name),app.norm_vn(x.team_name),x.stt_in_team
  from jsonb_to_recordset(p_workers)x(mnv text,full_name text,job_title text,team_name text,stt_in_team int);
  if (select count(*) from roster_rows)<>jsonb_array_length(p_workers) then raise exception 'DUPLICATE_MNV'; end if;
  if exists(select 1 from roster_rows where mnv='' or full_name='' or job_title='' or team_name='' or stt_in_team<1) then raise exception 'INVALID_WORKER_ROW'; end if;
  if exists(select 1 from roster_rows r where (select count(*) from public.teams t where t.deleted_at is null and (app.norm_vn(t.leader_name)=r.team_key or app.norm_vn(coalesce(t.legacy_team_name,''))=r.team_key))<>1) then raise exception 'UNKNOWN_OR_AMBIGUOUS_TEAM'; end if;

  -- Explicit predicate keeps Supabase safeupdate protection enabled.
  update roster_rows r set team_id=(select t.id from public.teams t where t.deleted_at is null and (app.norm_vn(t.leader_name)=r.team_key or app.norm_vn(coalesce(t.legacy_team_name,''))=r.team_key) limit 1)
  where r.team_id is null;
  if exists(select 1 from roster_rows where team_id is null) then raise exception 'TEAM_MAPPING_FAILED'; end if;
  if exists(select 1 from public.profiles p join public.workers w on w.id=p.worker_id where p.is_active and not exists(select 1 from roster_rows r where r.mnv=upper(btrim(w.mnv)))) then raise exception 'IMPORT_WOULD_DISABLE_ACTIVE_LOGIN'; end if;

  select coalesce(jsonb_agg(jsonb_build_object('id',w.id,'mnv',w.mnv,'full_name',w.full_name,'job_title',w.job_title,'team_id',w.team_id,'stt_in_team',w.stt_in_team,'legacy_lookup_key',w.legacy_lookup_key,'deleted_at',w.deleted_at) order by w.mnv),'[]'::jsonb) into v_before from public.workers w;
  select coalesce(array_agg(t.id order by t.team_code),'{}'::uuid[]) into v_before_active from public.teams t where t.deleted_at is null and t.is_active;
  update public.workers w set full_name=r.full_name,job_title=r.job_title,team_id=r.team_id,stt_in_team=r.stt_in_team,legacy_lookup_key=r.team_name||'‡'||r.stt_in_team,deleted_at=null,updated_at=now(),updated_by=auth.uid()
  from roster_rows r where upper(btrim(w.mnv))=r.mnv;
  insert into public.workers(mnv,full_name,job_title,team_id,stt_in_team,legacy_lookup_key,created_by,updated_by)
  select r.mnv,r.full_name,r.job_title,r.team_id,r.stt_in_team,r.team_name||'‡'||r.stt_in_team,auth.uid(),auth.uid() from roster_rows r
  where not exists(select 1 from public.workers w where upper(btrim(w.mnv))=r.mnv);
  update public.workers w set deleted_at=now(),updated_at=now(),updated_by=auth.uid()
  where w.deleted_at is null and not exists(select 1 from roster_rows r where r.mnv=upper(btrim(w.mnv)));
  get diagnostics v_archived_count=row_count;
  update public.teams t set is_active=exists(select 1 from unnest(coalesce(p_active_team_names,'{}'::text[]))a(name) where app.norm_vn(a.name)=app.norm_vn(t.leader_name)) and exists(select 1 from roster_rows r where r.team_id=t.id),updated_at=now(),updated_by=auth.uid()
  where t.deleted_at is null;
  select count(*),count(distinct team_id) into v_worker_count,v_team_count from roster_rows;
  insert into app.worker_roster_import_backups(request_key,source_name,source_sha256,imported_by,before_workers,before_active_team_ids,after_worker_count,after_team_count)
  values(p_request_key,btrim(p_source_name),p_source_sha256,auth.uid(),v_before,v_before_active,v_worker_count,v_team_count);
  return jsonb_build_object('worker_count',v_worker_count,'team_count',v_team_count,'upserted_count',v_worker_count,'archived_count',v_archived_count,'active_team_count',(select count(*) from public.teams where deleted_at is null and is_active),'source_sha256',p_source_sha256,'idempotent',false);
end $$;

create or replace function public.create_job_group(p_job_ids uuid[])
returns text language plpgsql security definer set search_path='' as $$
declare v_first public.jobs;v_code text;v_date text;v_seq int;v_count int;
begin
  if coalesce(array_length(p_job_ids,1),0)<2 then raise exception 'AT_LEAST_TWO_JOBS'; end if;
  if (select count(distinct x) from unnest(p_job_ids)x)<>array_length(p_job_ids,1) then raise exception 'DUPLICATE_JOB_IDS'; end if;
  perform 1 from public.jobs where id=any(p_job_ids) and deleted_at is null for update;
  select count(*) into v_count from public.jobs where id=any(p_job_ids) and deleted_at is null;
  if v_count<>array_length(p_job_ids,1) then raise exception 'JOB_NOT_FOUND'; end if;
  select * into v_first from public.jobs where id=p_job_ids[1] and deleted_at is null;
  if app.current_role() not in ('ADMIN','GIAM_SAT','TO_TRUONG') or not app.can_access_team(v_first.team_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if btrim(coalesce(v_first.location,''))='' then raise exception 'GROUP_LOCATION_REQUIRED'; end if;
  if exists(select 1 from public.jobs j where j.id=any(p_job_ids) and j.group_code is not null) then raise exception 'REMOVE_EXISTING_GROUP_FIRST'; end if;
  if exists(select 1 from public.jobs j where j.id=any(p_job_ids) and j.team_id<>v_first.team_id) then raise exception 'GROUP_TEAM_MISMATCH'; end if;
  if exists(select 1 from public.jobs j where j.id=any(p_job_ids) and (j.start_date<>v_first.start_date or j.end_date<>v_first.end_date)) then raise exception 'GROUP_DATE_MISMATCH'; end if;
  if exists(select 1 from public.jobs j where j.id=any(p_job_ids) and btrim(coalesce(j.location,''))<>btrim(v_first.location)) then raise exception 'GROUP_LOCATION_MISMATCH'; end if;
  if exists(select 1 from public.jobs j where j.id=any(p_job_ids) and (j.count_leader,j.count_worker1,j.count_worker2,j.count_worker3,j.count_helper) is distinct from (v_first.count_leader,v_first.count_worker1,v_first.count_worker2,v_first.count_worker3,v_first.count_helper)) then raise exception 'GROUP_STAFFING_MISMATCH'; end if;
  if exists(select 1 from app.v_job_metrics m where m.id=any(p_job_ids) and (coalesce(m.unit_price,0)<=0 or coalesce(m.work_days,0)<=0 or coalesce(m.production_value,0)<=0 or coalesce(m.actual_labor_cost,-1)<0)) then raise exception 'GROUP_METRICS_INCOMPLETE'; end if;
  v_date:=to_char(v_first.start_date,'YYYYMMDD');perform pg_advisory_xact_lock(hashtext('JOB_GROUP_'||v_date));
  select coalesce(max(substring(group_code from '([0-9]+)$')::int),0)+1 into v_seq from public.jobs where group_code like 'MN-'||v_date||'-%';
  v_code:='MN-'||v_date||'-'||lpad(v_seq::text,2,'0');
  update public.jobs set group_code=v_code,updated_at=now(),updated_by=auth.uid() where id=any(p_job_ids) and deleted_at is null;
  return v_code;
end $$;

create or replace function public.remove_job_groups(p_group_codes text[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_codes text[];v_count int;
begin
  select array_agg(distinct btrim(x)) into v_codes from unnest(coalesce(p_group_codes,'{}'::text[]))x where btrim(x)<>'';
  if coalesce(array_length(v_codes,1),0)=0 then raise exception 'GROUP_CODE_REQUIRED'; end if;
  perform 1 from public.jobs where group_code=any(v_codes) and deleted_at is null for update;
  if not exists(select 1 from public.jobs where group_code=any(v_codes) and deleted_at is null) then raise exception 'GROUP_NOT_FOUND'; end if;
  if app.current_role() not in ('ADMIN','GIAM_SAT','TO_TRUONG') or exists(select 1 from public.jobs where group_code=any(v_codes) and deleted_at is null and not app.can_access_team(team_id)) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  update public.jobs set group_code=null,updated_at=now(),updated_by=auth.uid() where group_code=any(v_codes) and deleted_at is null;
  get diagnostics v_count=row_count;
  return jsonb_build_object('group_count',array_length(v_codes,1),'job_count',v_count,'codes',to_jsonb(v_codes));
end $$;

revoke execute on function public.admin_import_worker_roster(uuid,text,text,jsonb,text[]) from public,anon;
revoke execute on function public.create_job_group(uuid[]) from public,anon;
revoke execute on function public.remove_job_groups(text[]) from public,anon;
grant execute on function public.admin_import_worker_roster(uuid,text,text,jsonb,text[]) to authenticated;
grant execute on function public.create_job_group(uuid[]) to authenticated;
grant execute on function public.remove_job_groups(text[]) to authenticated;
notify pgrst,'reload schema';
