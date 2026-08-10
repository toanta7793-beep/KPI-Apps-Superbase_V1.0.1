-- 030_shared_weeks_projects_pgv.sql
-- Shared editable week definitions, project per team, and PGV project parity.

alter table public.teams add column if not exists project_name text not null default 'DỰ ÁN MẪU';
update public.teams set project_name='DỰ ÁN MẪU' where btrim(coalesce(project_name,''))='';

create table if not exists public.shared_work_weeks(
  id uuid primary key default gen_random_uuid(),
  week_slot smallint not null check(week_slot between 1 and 4),
  start_date date not null,
  end_date date not null,
  status text not null default 'ACTIVE' check(status in ('ACTIVE','ARCHIVED')),
  created_by uuid default auth.uid(),created_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),updated_at timestamptz not null default now(),
  constraint ck_shared_week_dates check(end_date>=start_date and end_date-start_date+1<=9)
);
create unique index if not exists uq_shared_week_slot_active on public.shared_work_weeks(week_slot) where status='ACTIVE';
do $$ begin
  alter table public.shared_work_weeks add constraint ex_shared_week_no_overlap
    exclude using gist(daterange(start_date,end_date,'[]') with &&) where(status='ACTIVE');
exception when duplicate_object then null; end $$;
alter table public.shared_work_weeks enable row level security;
grant select on public.shared_work_weeks to authenticated;
drop policy if exists p_shared_week_select on public.shared_work_weeks;
create policy p_shared_week_select on public.shared_work_weeks for select to authenticated using(app.current_role() is not null);

-- Choose the existing definition with the most assigned jobs, then the broadest valid range.
insert into public.shared_work_weeks(week_slot,start_date,end_date,created_by,updated_by)
select week_slot,start_date,end_date,auth.uid(),auth.uid() from(
  select w.week_slot,w.start_date,w.end_date,count(j.id) job_count,
         row_number() over(partition by w.week_slot order by count(j.id) desc,(w.end_date-w.start_date) desc,max(w.updated_at) desc) rn
  from public.work_weeks w left join public.jobs j on j.week_id=w.id and j.deleted_at is null
  where w.status='ACTIVE' group by w.week_slot,w.start_date,w.end_date
) ranked where rn=1
on conflict(week_slot) where status='ACTIVE' do nothing;

create or replace function public.get_shared_work_weeks()
returns table(id uuid,week_slot smallint,start_date date,end_date date,status text)
language sql stable security definer set search_path='' as $$
  select w.id,w.week_slot,w.start_date,w.end_date,w.status from public.shared_work_weeks w
  where w.status='ACTIVE' order by w.week_slot
$$;
revoke execute on function public.get_shared_work_weeks() from public,anon;
grant execute on function public.get_shared_work_weeks() to authenticated;

create or replace function public.upsert_shared_work_week(p_week_slot int,p_start_date date,p_end_date date)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_team public.teams;
begin
  if app.current_role()<>'ADMIN' then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if p_week_slot not between 1 and 4 then raise exception 'INVALID_WEEK_SLOT'; end if;
  if p_start_date is null or p_end_date is null or p_end_date<p_start_date or p_end_date-p_start_date+1>9 then raise exception 'INVALID_WEEK_RANGE_MAX_9_DAYS'; end if;
  perform pg_advisory_xact_lock(hashtext('SHARED_WORK_WEEK'));
  if exists(select 1 from public.shared_work_weeks where status='ACTIVE' and week_slot<>p_week_slot and daterange(start_date,end_date,'[]')&&daterange(p_start_date,p_end_date,'[]')) then raise exception 'SHARED_WEEK_OVERLAP'; end if;
  if exists(select 1 from public.jobs j join public.work_weeks w on w.id=j.week_id where j.deleted_at is null and w.status='ACTIVE' and w.week_slot=p_week_slot and (j.start_date<p_start_date or j.end_date>p_end_date)) then raise exception 'EDIT_WOULD_EXCLUDE_ASSIGNED_JOB'; end if;
  insert into public.shared_work_weeks(week_slot,start_date,end_date,status,created_by,updated_by)
  values(p_week_slot,p_start_date,p_end_date,'ACTIVE',auth.uid(),auth.uid())
  on conflict(week_slot) where status='ACTIVE' do update set start_date=excluded.start_date,end_date=excluded.end_date,updated_at=now(),updated_by=auth.uid()
  returning id into v_id;
  for v_team in select * from public.teams where deleted_at is null and is_active order by id for update loop
    update public.work_weeks set start_date=p_start_date,end_date=p_end_date,updated_at=now()
    where team_id=v_team.id and week_slot=p_week_slot and status='ACTIVE';
    if not found then
      insert into public.work_weeks(team_id,week_slot,start_date,end_date,status,created_by)
      values(v_team.id,p_week_slot,p_start_date,p_end_date,'ACTIVE',auth.uid());
    end if;
  end loop;
  return v_id;
end $$;
revoke execute on function public.upsert_shared_work_week(integer,date,date) from public,anon;
grant execute on function public.upsert_shared_work_week(integer,date,date) to authenticated;

create or replace function public.assign_jobs_to_shared_week(p_week_slot int,p_job_ids uuid[])
returns integer language plpgsql security definer set search_path='' as $$
declare v_shared public.shared_work_weeks;v_count int;
begin
  if coalesce(array_length(p_job_ids,1),0)=0 then raise exception 'EMPTY_JOB_SELECTION'; end if;
  if (select count(distinct x) from unnest(p_job_ids)x)<>array_length(p_job_ids,1) then raise exception 'DUPLICATE_JOB_IDS'; end if;
  select * into v_shared from public.shared_work_weeks where week_slot=p_week_slot and status='ACTIVE' for update;
  if v_shared.id is null then raise exception 'SHARED_WEEK_NOT_FOUND'; end if;
  perform 1 from public.jobs where id=any(p_job_ids) and deleted_at is null for update;
  if (select count(*) from public.jobs where id=any(p_job_ids) and deleted_at is null)<>array_length(p_job_ids,1) then raise exception 'JOB_NOT_FOUND'; end if;
  if app.current_role() not in ('ADMIN','GIAM_SAT','TO_TRUONG') or exists(select 1 from public.jobs where id=any(p_job_ids) and not app.can_access_team(team_id)) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if exists(select 1 from public.jobs where id=any(p_job_ids) and (week_id is not null or start_date<v_shared.start_date or end_date>v_shared.end_date)) then raise exception 'JOB_MUST_FIT_SHARED_WEEK'; end if;
  update public.jobs j set week_id=w.id,updated_at=now(),updated_by=auth.uid()
  from public.work_weeks w where j.id=any(p_job_ids) and w.team_id=j.team_id and w.week_slot=p_week_slot and w.status='ACTIVE';
  get diagnostics v_count=row_count;
  if v_count<>array_length(p_job_ids,1) then raise exception 'PARTIAL_SHARED_WEEK_ASSIGNMENT'; end if;
  return v_count;
end $$;
revoke execute on function public.assign_jobs_to_shared_week(integer,uuid[]) from public,anon;
grant execute on function public.assign_jobs_to_shared_week(integer,uuid[]) to authenticated;

create or replace function public.admin_import_worker_roster_v2(
  p_request_key uuid,p_source_name text,p_source_sha256 text,p_workers jsonb,
  p_active_team_names text[] default '{}'::text[]
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_next_stt int;v_result jsonb;
begin
  if app.current_role()<>'ADMIN' then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if jsonb_typeof(p_workers)<>'array' or jsonb_array_length(p_workers)=0 or jsonb_array_length(p_workers)>10000 then raise exception 'INVALID_WORKER_ROSTER_SIZE'; end if;
  create temporary table roster_team_names(team_name text not null,team_key text primary key,project_name text not null) on commit drop;
  if exists(select 1 from jsonb_to_recordset(p_workers)x(team_name text,project_name text) group by app.norm_vn(x.team_name) having count(distinct app.norm_vn(x.project_name))<>1) then raise exception 'TEAM_PROJECT_MUST_BE_CONSISTENT'; end if;
  insert into roster_team_names(team_name,team_key,project_name)
  select min(btrim(x.team_name)),app.norm_vn(x.team_name),min(btrim(x.project_name))
  from jsonb_to_recordset(p_workers)x(team_name text,project_name text)
  where btrim(coalesce(x.team_name,''))<>'' and btrim(coalesce(x.project_name,''))<>'' group by app.norm_vn(x.team_name);
  if (select count(distinct app.norm_vn(x.team_name)) from jsonb_to_recordset(p_workers)x(team_name text))<>(select count(*) from roster_team_names) then raise exception 'PROJECT_REQUIRED_FOR_EVERY_TEAM'; end if;
  if exists(select 1 from roster_team_names r where(select count(*) from public.teams t where t.deleted_at is null and(app.norm_vn(t.leader_name)=r.team_key or app.norm_vn(coalesce(t.legacy_team_name,''))=r.team_key))>1) then raise exception 'AMBIGUOUS_TEAM'; end if;
  select coalesce(max(stt),0) into v_next_stt from public.teams where deleted_at is null;
  insert into public.teams(team_code,leader_name,legacy_team_name,project_name,stt,is_active,created_by,updated_by)
  select 'TEAM-'||upper(substr(md5(r.team_key),1,12)),r.team_name,r.team_name,r.project_name,v_next_stt+row_number() over(order by r.team_name),false,auth.uid(),auth.uid()
  from roster_team_names r where not exists(select 1 from public.teams t where t.deleted_at is null and(app.norm_vn(t.leader_name)=r.team_key or app.norm_vn(coalesce(t.legacy_team_name,''))=r.team_key))
  on conflict(team_code) do update set leader_name=excluded.leader_name,legacy_team_name=excluded.legacy_team_name,project_name=excluded.project_name,deleted_at=null,updated_at=now(),updated_by=auth.uid();
  update public.teams t set project_name=r.project_name,updated_at=now(),updated_by=auth.uid() from roster_team_names r
  where t.deleted_at is null and(app.norm_vn(t.leader_name)=r.team_key or app.norm_vn(coalesce(t.legacy_team_name,''))=r.team_key);
  v_result:=public.admin_import_worker_roster(p_request_key,p_source_name,p_source_sha256,p_workers,p_active_team_names);
  insert into public.work_weeks(team_id,week_slot,start_date,end_date,status,created_by)
  select t.id,s.week_slot,s.start_date,s.end_date,'ACTIVE',auth.uid() from public.teams t cross join public.shared_work_weeks s
  where t.deleted_at is null and t.is_active and s.status='ACTIVE' and not exists(select 1 from public.work_weeks w where w.team_id=t.id and w.week_slot=s.week_slot and w.status='ACTIVE');
  return v_result;
end $$;
revoke execute on function public.admin_import_worker_roster_v2(uuid,text,text,jsonb,text[]) from public,anon;
grant execute on function public.admin_import_worker_roster_v2(uuid,text,text,jsonb,text[]) to authenticated;

create or replace function public.get_pgv_common(p_team_id uuid,p_week_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_week public.work_weeks;v_team text;v_project text;v_workers int;v_rows jsonb;
begin
  if not app.can_access_team(p_team_id) then raise exception 'FORBIDDEN'; end if;
  select * into v_week from public.work_weeks where id=p_week_id and team_id=p_team_id and status='ACTIVE';
  if v_week.id is null then raise exception 'WEEK_NOT_FOUND'; end if;
  select leader_name,project_name into v_team,v_project from public.teams where id=p_team_id;
  select count(*) into v_workers from public.workers where team_id=p_team_id and deleted_at is null;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.start_date,x.created_at),'[]'::jsonb) into v_rows from(select m.* from app.v_job_metrics m where m.team_id=p_team_id and m.week_id=p_week_id and(m.group_code is null or m.id=(select m2.id from app.v_job_metrics m2 where m2.group_key=m.group_key order by m2.created_at,m2.id limit 1)))x;
  return jsonb_build_object('team_id',p_team_id,'team_name',v_team,'project_name',v_project,'week',to_jsonb(v_week),'assign_date',v_week.start_date-1,'receive_date',v_week.start_date,'worker_count',v_workers,'rows',v_rows);
end $$;

create or replace function public.get_pgv_cnch(p_team_id uuid,p_receive_date date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_week public.work_weeks;v_project text;v_workers jsonb;v_jobs jsonb;v_assign jsonb;
begin
  if not app.can_access_team(p_team_id) then raise exception 'FORBIDDEN'; end if;
  select * into v_week from public.work_weeks where team_id=p_team_id and status='ACTIVE' and p_receive_date between start_date and end_date;
  if v_week.id is null then raise exception 'DATE_OUTSIDE_ACTIVE_WEEK'; end if;
  select project_name into v_project from public.teams where id=p_team_id;
  select coalesce(jsonb_agg(to_jsonb(w) order by w.stt_in_team,w.mnv),'[]'::jsonb) into v_workers from(select id,mnv,full_name,job_title,stt_in_team from public.workers where team_id=p_team_id and deleted_at is null)w;
  select coalesce(jsonb_agg(to_jsonb(j) order by j.start_date,j.created_at),'[]'::jsonb) into v_jobs from(select id,content,location,quantity,start_date,end_date,target_daily,unit,count_leader,count_worker1,count_worker2,count_worker3,count_helper,created_at from app.v_job_metrics where team_id=p_team_id and week_id=v_week.id)j;
  select coalesce(jsonb_agg(to_jsonb(a)),'[]'::jsonb) into v_assign from(select worker_id,job_id,content_label,target,completed_qty from public.assignments where week_id=v_week.id)a;
  return jsonb_build_object('project_name',v_project,'week',to_jsonb(v_week),'receive_date',p_receive_date,'assign_date',p_receive_date-1,'workers',v_workers,'jobs',v_jobs,'assignments',v_assign);
end $$;

-- Align all current active teams to the canonical definitions only when no assigned job would be excluded.
do $$ declare s public.shared_work_weeks;t public.teams;begin
  for s in select * from public.shared_work_weeks where status='ACTIVE' loop
    for t in select * from public.teams where deleted_at is null and is_active loop
      update public.work_weeks w set start_date=s.start_date,end_date=s.end_date,updated_at=now()
      where w.team_id=t.id and w.week_slot=s.week_slot and w.status='ACTIVE'
        and not exists(select 1 from public.jobs j where j.week_id=w.id and j.deleted_at is null and(j.start_date<s.start_date or j.end_date>s.end_date));
      if not exists(select 1 from public.work_weeks w where w.team_id=t.id and w.week_slot=s.week_slot and w.status='ACTIVE') then
        insert into public.work_weeks(team_id,week_slot,start_date,end_date,status) values(t.id,s.week_slot,s.start_date,s.end_date,'ACTIVE');
      end if;
    end loop;
  end loop;
end $$;

notify pgrst,'reload schema';
