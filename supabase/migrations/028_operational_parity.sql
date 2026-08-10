-- 028_operational_parity.sql
-- Excel roster v2, job preview/edit/group parity, and explicitly approved UAT
-- synchronization of the sole test job with GIAO_VIEC_HOA_VON row 4.

create or replace function public.admin_import_worker_roster_v2(
  p_request_key uuid,p_source_name text,p_source_sha256 text,p_workers jsonb,
  p_active_team_names text[] default '{}'::text[]
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_next_stt int;
begin
  if app.current_role()<>'ADMIN' then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if jsonb_typeof(p_workers)<>'array' or jsonb_array_length(p_workers)=0 or jsonb_array_length(p_workers)>10000 then
    raise exception 'INVALID_WORKER_ROSTER_SIZE';
  end if;
  create temporary table roster_team_names(team_name text not null,team_key text primary key) on commit drop;
  insert into roster_team_names(team_name,team_key)
  select min(btrim(x.team_name)),app.norm_vn(x.team_name)
  from jsonb_to_recordset(p_workers) x(team_name text)
  where btrim(coalesce(x.team_name,''))<>'' group by app.norm_vn(x.team_name);
  if exists(
    select 1 from roster_team_names r where
      (select count(*) from public.teams t where t.deleted_at is null and
       (app.norm_vn(t.leader_name)=r.team_key or app.norm_vn(coalesce(t.legacy_team_name,''))=r.team_key))>1
  ) then raise exception 'AMBIGUOUS_TEAM'; end if;
  select coalesce(max(stt),0) into v_next_stt from public.teams where deleted_at is null;
  insert into public.teams(team_code,leader_name,legacy_team_name,stt,is_active,created_by,updated_by)
  select 'TEAM-'||upper(substr(md5(r.team_key),1,12)),r.team_name,r.team_name,
         v_next_stt+row_number() over(order by r.team_name),false,auth.uid(),auth.uid()
  from roster_team_names r
  where not exists(select 1 from public.teams t where t.deleted_at is null and
    (app.norm_vn(t.leader_name)=r.team_key or app.norm_vn(coalesce(t.legacy_team_name,''))=r.team_key))
  on conflict(team_code) do update set leader_name=excluded.leader_name,legacy_team_name=excluded.legacy_team_name,
    deleted_at=null,updated_at=now(),updated_by=auth.uid();
  return public.admin_import_worker_roster(p_request_key,p_source_name,p_source_sha256,p_workers,p_active_team_names);
end $$;

revoke execute on function public.admin_import_worker_roster_v2(uuid,text,text,jsonb,text[]) from public,anon;
grant execute on function public.admin_import_worker_roster_v2(uuid,text,text,jsonb,text[]) to authenticated;

create or replace function public.preview_job_metrics(
  p_team_id uuid,p_start_date date,p_end_date date,p_category_name text,p_content text,p_quantity numeric,
  p_count_leader int,p_count_worker1 int,p_count_worker2 int,p_count_worker3 int,p_count_helper int
) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_days int;v_daily numeric;v_price numeric;v_production numeric;v_cost numeric;v_diff numeric;v_breakeven numeric;v_people int;v_special boolean;
begin
  if app.current_role() not in ('ADMIN','GIAM_SAT','TO_TRUONG') or not app.can_access_team(p_team_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if p_start_date is null or p_end_date is null or p_end_date<p_start_date then raise exception 'INVALID_DATES'; end if;
  if least(p_count_leader,p_count_worker1,p_count_worker2,p_count_worker3,p_count_helper)<0 then raise exception 'INVALID_COUNTS'; end if;
  v_days:=p_end_date-p_start_date+1;v_people:=p_count_leader+p_count_worker1+p_count_worker2+p_count_worker3+p_count_helper;
  if v_people<=0 then raise exception 'NO_WORKERS'; end if;
  select (p_count_worker1*coalesce(avg(daily_salary) filter(where grade_name='Thợ bậc 1'),0)
        + p_count_worker2*coalesce(avg(daily_salary) filter(where grade_name='Thợ bậc 2'),0)
        + p_count_worker3*coalesce(avg(daily_salary) filter(where grade_name='Thợ bậc 3'),0)
        + p_count_helper*coalesce(avg(daily_salary) filter(where grade_name='Thợ phụ'),0))
    into v_daily from app.v_worker_salary where team_id=p_team_id and salary_ok and not is_actual_leader;
  v_special:=app.norm_vn(p_category_name) in ('dao tao','phat sinh');
  if v_special then v_price:=v_daily/nullif(v_people,0);v_production:=v_people*v_days*v_price;
  else
    select case when count(*)=1 then min(calc_price) end into v_price from public.price_items
    where is_active and category_name=btrim(p_category_name) and content=btrim(p_content);
    v_production:=p_quantity*v_price;
  end if;
  if v_price is null then raise exception 'PRICE_NOT_UNIQUE_OR_MISSING'; end if;
  v_cost:=v_daily*v_days;v_diff:=v_production-v_cost;v_breakeven:=v_cost/nullif(v_price,0);
  return jsonb_build_object('work_days',v_days,'daily_payroll',v_daily,'unit_price',v_price,
    'breakeven_quantity',v_breakeven,'target_daily',p_quantity/nullif(v_days,0),
    'production_value',v_production,'actual_labor_cost',v_cost,'difference',v_diff,
    'evaluation',case when v_diff<0 then 'LỖ NHÂN CÔNG' else 'AN TOÀN - ĐẠT ĐỊNH MỨC' end);
end $$;

revoke execute on function public.preview_job_metrics(uuid,date,date,text,text,numeric,integer,integer,integer,integer,integer) from public,anon;
grant execute on function public.preview_job_metrics(uuid,date,date,text,text,numeric,integer,integer,integer,integer,integer) to authenticated;

create or replace function public.update_job(
  p_job_id uuid,p_team_id uuid,p_start_date date,p_end_date date,p_category_name text,p_content text,p_location text,p_quantity numeric,
  p_count_leader int,p_count_worker1 int,p_count_worker2 int,p_count_worker3 int,p_count_helper int
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_job public.jobs;v_people int;v_days int;v_special boolean;v_week public.work_weeks;
begin
  select * into v_job from public.jobs where id=p_job_id and deleted_at is null for update;
  if v_job.id is null then raise exception 'JOB_NOT_FOUND'; end if;
  if app.current_role() not in ('ADMIN','GIAM_SAT','TO_TRUONG') or not app.can_access_team(v_job.team_id) or not app.can_access_team(p_team_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if v_job.group_code is not null then raise exception 'REMOVE_GROUP_BEFORE_EDIT'; end if;
  if p_end_date<p_start_date then raise exception 'INVALID_DATES'; end if;
  if least(p_count_leader,p_count_worker1,p_count_worker2,p_count_worker3,p_count_helper)<0 then raise exception 'INVALID_COUNTS'; end if;
  v_people:=p_count_leader+p_count_worker1+p_count_worker2+p_count_worker3+p_count_helper;if v_people<=0 then raise exception 'NO_WORKERS'; end if;
  v_days:=p_end_date-p_start_date+1;v_special:=app.norm_vn(p_category_name) in ('dao tao','phat sinh');
  if not v_special and not exists(select 1 from public.price_items where is_active and category_name=btrim(p_category_name) and content=btrim(p_content)) then raise exception 'CONTENT_NOT_IN_CATALOG'; end if;
  if v_job.week_id is not null then
    select * into v_week from public.work_weeks where id=v_job.week_id and status='ACTIVE';
    if v_week.id is null or v_week.team_id<>p_team_id or p_start_date<v_week.start_date or p_end_date>v_week.end_date then raise exception 'JOB_OUTSIDE_ASSIGNED_WEEK'; end if;
  end if;
  update public.jobs set team_id=p_team_id,start_date=p_start_date,end_date=p_end_date,category_name=btrim(p_category_name),content=btrim(p_content),
    location=nullif(btrim(p_location),''),quantity=case when v_special then v_people*v_days else p_quantity end,
    count_leader=p_count_leader,count_worker1=p_count_worker1,count_worker2=p_count_worker2,count_worker3=p_count_worker3,count_helper=p_count_helper,
    is_special_labor=v_special,updated_at=now(),updated_by=auth.uid() where id=p_job_id;
  return p_job_id;
end $$;

revoke execute on function public.update_job(uuid,uuid,date,date,text,text,text,numeric,integer,integer,integer,integer,integer) from public,anon;
grant execute on function public.update_job(uuid,uuid,date,date,text,text,text,numeric,integer,integer,integer,integer,integer) to authenticated;

create or replace function public.create_job_group(p_job_ids uuid[])
returns text language plpgsql security definer set search_path = '' as $$
declare v_team uuid;v_code text;v_count int;v_date text;v_seq int;
begin
  if coalesce(array_length(p_job_ids,1),0)<2 then raise exception 'AT_LEAST_TWO_JOBS'; end if;
  if (select count(distinct x) from unnest(p_job_ids)x)<>array_length(p_job_ids,1) then raise exception 'DUPLICATE_JOB_IDS'; end if;
  perform 1 from public.jobs where id=any(p_job_ids) and deleted_at is null for update;
  select count(*),(array_agg(team_id))[1],to_char(min(start_date),'YYYYMMDD') into v_count,v_team,v_date from public.jobs where id=any(p_job_ids) and deleted_at is null;
  if v_count<>array_length(p_job_ids,1) then raise exception 'JOB_NOT_FOUND'; end if;
  if app.current_role() not in ('ADMIN','GIAM_SAT','TO_TRUONG') or not app.can_access_team(v_team) then raise exception 'FORBIDDEN'; end if;
  if (select count(distinct concat_ws('‡',team_id,start_date,end_date,coalesce(location,''),count_leader,count_worker1,count_worker2,count_worker3,count_helper)) from public.jobs where id=any(p_job_ids))<>1
     or exists(select 1 from public.jobs where id=any(p_job_ids) and group_code is not null) then raise exception 'GROUP_VALIDATION_FAILED'; end if;
  perform pg_advisory_xact_lock(hashtext('JOB_GROUP_'||v_date));
  select coalesce(max(substring(group_code from '([0-9]+)$')::int),0)+1 into v_seq from public.jobs where group_code like 'MN-'||v_date||'-%';
  v_code:='MN-'||v_date||'-'||lpad(v_seq::text,2,'0');
  update public.jobs set group_code=v_code,updated_at=now(),updated_by=auth.uid() where id=any(p_job_ids);return v_code;
end $$;

-- Clone-safe: the source-project UAT repair block was intentionally removed.

notify pgrst,'reload schema';
