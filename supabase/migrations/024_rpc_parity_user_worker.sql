-- Phase 10 parity gate: multi-team authorization, user/worker administration,
-- payroll/job metrics, PGV assignments and fail-closed week archive.
-- This migration is additive and does not alter catalog/source salary values.

-- ---------------------------------------------------------------------------
-- 1. Identity and multi-team authorization
-- ---------------------------------------------------------------------------
alter table public.profiles add column if not exists display_name text;
alter table public.profiles add column if not exists note text;

create table if not exists public.profile_teams (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  team_id uuid not null references public.teams(id) on delete cascade,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  primary key (profile_id, team_id)
);
alter table public.profile_teams enable row level security;
grant select, insert, update, delete on public.profile_teams to authenticated;

create or replace function app.can_access_team(p_team_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.profiles p
    where p.auth_user_id = auth.uid() and p.is_active
      and (
        p.role_code = 'ADMIN'
        or exists (
          select 1 from public.profile_teams pt
          where pt.profile_id = p.id and pt.team_id = p_team_id
        )
        or (
          p.role_code in ('TO_TRUONG','NHAN_VIEN')
          and exists (
            select 1 from public.workers w
            join public.teams t on t.id = w.team_id
            where w.id = p.worker_id and w.deleted_at is null
              and t.deleted_at is null and t.is_active and w.team_id = p_team_id
          )
        )
      )
  )
$$;
revoke execute on function app.can_access_team(uuid) from public, anon;
grant execute on function app.can_access_team(uuid) to authenticated;

drop policy if exists p_profile_teams_select on public.profile_teams;
create policy p_profile_teams_select on public.profile_teams for select to authenticated
using (
  app.current_role() = 'ADMIN'
  or profile_id = (select p.id from public.profiles p where p.auth_user_id = auth.uid() and p.is_active limit 1)
);
drop policy if exists p_profile_teams_insert on public.profile_teams;
create policy p_profile_teams_insert on public.profile_teams for insert to authenticated
with check (app.current_role() = 'ADMIN');
drop policy if exists p_profile_teams_update on public.profile_teams;
create policy p_profile_teams_update on public.profile_teams for update to authenticated
using (app.current_role() = 'ADMIN') with check (app.current_role() = 'ADMIN');
drop policy if exists p_profile_teams_delete on public.profile_teams;
create policy p_profile_teams_delete on public.profile_teams for delete to authenticated
using (app.current_role() = 'ADMIN');

create or replace function public.get_my_access()
returns table(role_code text, worker_id uuid, mnv text, full_name text, team_id uuid, team_name text, team_ids uuid[])
language sql stable security definer set search_path = '' as $$
  select p.role_code, w.id, w.mnv,
         coalesce(nullif(p.display_name,''), w.full_name),
         w.team_id, t.leader_name,
         case when p.role_code = 'ADMIN' then
           coalesce((select array_agg(x.id order by x.stt, x.leader_name)
                     from public.teams x where x.deleted_at is null and x.is_active), '{}'::uuid[])
         else
           coalesce((select array_agg(distinct q.team_id) from (
             select pt.team_id from public.profile_teams pt where pt.profile_id = p.id
             union all select w.team_id where w.team_id is not null
           ) q), '{}'::uuid[])
         end
  from public.profiles p
  left join public.workers w on w.id = p.worker_id and w.deleted_at is null
  left join public.teams t on t.id = w.team_id and t.deleted_at is null
  where p.auth_user_id = auth.uid() and p.is_active
$$;
revoke execute on function public.get_my_access() from public, anon;
grant execute on function public.get_my_access() to authenticated;

-- Replace read scopes with the shared multi-team helper.
drop policy if exists p_v1_teams_select on public.teams;
create policy p_v1_teams_select on public.teams for select to authenticated
using (deleted_at is null and app.can_access_team(id));
drop policy if exists p_v1_workers_select on public.workers;
create policy p_v1_workers_select on public.workers for select to authenticated
using (
  deleted_at is null and (
    app.current_role() = 'ADMIN'
    or app.can_access_team(team_id)
    or (app.current_role() = 'NHAN_VIEN' and id = app.current_worker_id())
  )
);
drop policy if exists p_v1_jobs_select on public.jobs;
create policy p_v1_jobs_select on public.jobs for select to authenticated
using (deleted_at is null and app.can_access_team(team_id));
drop policy if exists p_v1_assign_select on public.assignments;
create policy p_v1_assign_select on public.assignments for select to authenticated
using (app.can_access_team(team_id) or worker_id = app.current_worker_id());
drop policy if exists p_week_select on public.work_weeks;
create policy p_week_select on public.work_weeks for select to authenticated
using (app.can_access_team(team_id));

-- ---------------------------------------------------------------------------
-- 2. Admin RPCs for users and workers
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_profiles()
returns table(profile_id uuid, auth_user_id uuid, display_name text, role_code text,
              is_active boolean, worker_id uuid, mnv text, worker_name text,
              team_ids uuid[], note text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if app.current_role() <> 'ADMIN' then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  return query
  select p.id, p.auth_user_id, p.display_name, p.role_code, p.is_active,
         p.worker_id, w.mnv, w.full_name,
         coalesce(array_agg(pt.team_id) filter (where pt.team_id is not null), '{}'::uuid[]),
         p.note
  from public.profiles p
  left join public.workers w on w.id = p.worker_id
  left join public.profile_teams pt on pt.profile_id = p.id
  group by p.id, w.mnv, w.full_name
  order by p.is_active desc, p.role_code, coalesce(p.display_name,w.full_name);
end $$;

create or replace function public.admin_set_profile(
  p_auth_user_id uuid, p_display_name text, p_role_code text,
  p_is_active boolean, p_worker_id uuid default null,
  p_team_ids uuid[] default '{}'::uuid[], p_note text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_profile_id uuid;
begin
  if app.current_role() <> 'ADMIN' then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if p_auth_user_id = auth.uid() and not p_is_active then raise exception 'CANNOT_DEACTIVATE_SELF'; end if;
  if not exists(select 1 from public.roles r where r.code=p_role_code and r.is_active) then
    raise exception 'INVALID_ROLE';
  end if;
  if p_worker_id is not null and not exists(select 1 from public.workers w where w.id=p_worker_id and w.deleted_at is null) then
    raise exception 'WORKER_NOT_FOUND';
  end if;
  if exists(select 1 from unnest(coalesce(p_team_ids,'{}'::uuid[])) x
            where not exists(select 1 from public.teams t where t.id=x and t.deleted_at is null and t.is_active)) then
    raise exception 'INVALID_TEAM_SCOPE';
  end if;

  insert into public.profiles(auth_user_id,worker_id,role_code,is_active,display_name,note,created_by,updated_by)
  values(p_auth_user_id,p_worker_id,p_role_code,p_is_active,nullif(btrim(p_display_name),''),nullif(btrim(p_note),''),auth.uid(),auth.uid())
  on conflict (auth_user_id) do update set
    worker_id=excluded.worker_id, role_code=excluded.role_code, is_active=excluded.is_active,
    display_name=excluded.display_name, note=excluded.note, updated_by=auth.uid()
  returning id into v_profile_id;

  delete from public.profile_teams where profile_id=v_profile_id;
  insert into public.profile_teams(profile_id,team_id,created_by)
  select v_profile_id,x,auth.uid() from unnest(coalesce(p_team_ids,'{}'::uuid[])) x
  on conflict do nothing;
  return v_profile_id;
end $$;

create or replace function public.admin_save_worker(
  p_worker_id uuid, p_mnv text, p_full_name text, p_job_title text,
  p_team_id uuid, p_stt_in_team int default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_mnv text := upper(btrim(coalesce(p_mnv,'')));
begin
  if app.current_role() <> 'ADMIN' then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if v_mnv='' or btrim(coalesce(p_full_name,''))='' then raise exception 'MNV_AND_NAME_REQUIRED'; end if;
  if p_stt_in_team is not null and p_stt_in_team < 1 then raise exception 'INVALID_TEAM_ORDER'; end if;
  if not exists(select 1 from public.teams t where t.id=p_team_id and t.deleted_at is null) then raise exception 'TEAM_NOT_FOUND'; end if;

  if p_worker_id is null then
    select w.id into v_id from public.workers w where upper(btrim(w.mnv))=v_mnv for update;
    if v_id is null then
      insert into public.workers(mnv,full_name,job_title,team_id,stt_in_team,created_by,updated_by)
      values(v_mnv,btrim(p_full_name),nullif(btrim(p_job_title),''),p_team_id,p_stt_in_team,auth.uid(),auth.uid())
      returning id into v_id;
    else
      update public.workers set full_name=btrim(p_full_name),job_title=nullif(btrim(p_job_title),''),
        team_id=p_team_id,stt_in_team=p_stt_in_team,deleted_at=null,updated_by=auth.uid()
      where id=v_id;
    end if;
  else
    if exists(select 1 from public.workers w where upper(btrim(w.mnv))=v_mnv and w.id<>p_worker_id) then
      raise exception 'DUPLICATE_MNV';
    end if;
    update public.workers set mnv=v_mnv,full_name=btrim(p_full_name),job_title=nullif(btrim(p_job_title),''),
      team_id=p_team_id,stt_in_team=p_stt_in_team,updated_by=auth.uid()
    where id=p_worker_id and deleted_at is null returning id into v_id;
    if v_id is null then raise exception 'WORKER_NOT_FOUND'; end if;
  end if;
  return v_id;
end $$;

create or replace function public.admin_archive_worker(p_worker_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if app.current_role() <> 'ADMIN' then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if exists(select 1 from public.profiles p where p.worker_id=p_worker_id and p.is_active) then
    raise exception 'WORKER_HAS_ACTIVE_LOGIN';
  end if;
  update public.workers set deleted_at=now(),updated_by=auth.uid() where id=p_worker_id and deleted_at is null;
  if not found then raise exception 'WORKER_NOT_FOUND'; end if;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Canonical payroll classification (AutoPayrollService parity)
-- ---------------------------------------------------------------------------
create or replace view app.v_worker_salary as
with base as (
  select w.id worker_id,w.team_id,w.mnv,w.full_name,w.job_title,t.leader_name,
         app.norm_vn(w.job_title) title_n
  from public.workers w join public.teams t on t.id=w.team_id
  where w.deleted_at is null and t.deleted_at is null and t.is_active
), flags as (
  select b.*,
    (title_n like '%phu tro%' or title_n like '%tho phu%') helper_flag,
    (title_n ~ '(^| )(bac|b)[[:space:]]*1( |$)') g1,
    (title_n ~ '(^| )(bac|b)[[:space:]]*2( |$)') g2,
    (title_n ~ '(^| )(bac|b)[[:space:]]*3( |$)') g3,
    (title_n ~ '(^| )(pccc|phong chay chua chay|chua chay)( |$)') s_pccc,
    (title_n ~ '(^| )(nuoc|cap thoat nuoc|cap nuoc|thoat nuoc)( |$)') s_nuoc,
    (title_n ~ '(^| )dien( |$)') s_dien,
    (title_n ~ '(^| )(hvac|thong gio|dieu hoa khong khi|dieu hoa)( |$)') s_hvac,
    (title_n ~ '(^| )han( |$)') s_han
  from base b
), classified as (
  select f.*,
    app.norm_vn(full_name)=app.norm_vn(leader_name) is_actual_leader,
    case when helper_flag then 'Thợ phụ'
         when (g1::int+g2::int+g3::int)=1 then
           case when g1 then 'Thợ bậc 1' when g2 then 'Thợ bậc 2' else 'Thợ bậc 3' end
         else null end grade_name,
    case when (s_pccc::int+s_nuoc::int+s_dien::int+s_hvac::int+s_han::int)=1 then
      case when s_pccc then 'PCCC' when s_nuoc then 'NUOC' when s_dien then 'DIEN'
           when s_hvac then 'HVAC' else 'HAN' end else null end system_code
  from flags f
), helper_salary as (
  select case when count(*)=(select count(*) from public.systems s where s.is_active)
                    and count(distinct ss.monthly_salary)=1
              then min(ss.monthly_salary) end monthly_salary
  from public.salary_standards ss
  join public.salary_grades sg on sg.id=ss.grade_id and sg.is_active and sg.name='Thợ phụ'
  join public.systems s on s.id=ss.system_id and s.is_active
  where ss.is_active
), resolved as (
  select c.*,
    case when is_actual_leader then 0::numeric
         when grade_name='Thợ phụ' then hs.monthly_salary
         else (select ss.monthly_salary from public.salary_standards ss
               join public.salary_grades sg on sg.id=ss.grade_id
               join public.systems s on s.id=ss.system_id
               where ss.is_active and sg.is_active and s.is_active
                 and sg.name=c.grade_name and s.code=c.system_code limit 1) end monthly_salary
  from classified c cross join helper_salary hs
)
select worker_id,team_id,grade_name,system_code,is_actual_leader,
       (monthly_salary/26)::numeric daily_salary,
       (is_actual_leader or monthly_salary is not null) salary_ok,
       mnv,full_name,job_title,monthly_salary
from resolved;

create or replace view app.v_team_payroll as
select team_id,count(*)::int worker_count,
       count(*) filter(where not salary_ok and not is_actual_leader)::int unknown_salary_count,
       coalesce(sum(daily_salary) filter(where salary_ok),0)::numeric daily_payroll
from app.v_worker_salary group by team_id;

create or replace function public.get_payroll_summary(p_team_id uuid default null)
returns table(team_id uuid,team_name text,role_name text,worker_count int,
              average_monthly numeric,average_daily numeric,total_daily numeric,total_monthly numeric,
              status text,unknown_workers jsonb)
language plpgsql stable security definer set search_path = '' as $$
begin
  return query
  with roles(role_name,sort_order) as (values ('Tổ trưởng',0),('Thợ bậc 1',1),('Thợ bậc 2',2),('Thợ bậc 3',3),('Thợ phụ',4)),
  allowed as (
    select t.id,t.leader_name from public.teams t
    where t.deleted_at is null and t.is_active and (p_team_id is null or t.id=p_team_id)
      and app.can_access_team(t.id)
  ), agg as (
    select ws.team_id,ws.grade_name,count(*) filter(where ws.salary_ok)::int cnt,
      avg(ws.monthly_salary) filter(where ws.salary_ok) avg_m,
      avg(ws.daily_salary) filter(where ws.salary_ok) avg_d,
      sum(ws.daily_salary) filter(where ws.salary_ok) total_d,
      sum(ws.monthly_salary) filter(where ws.salary_ok) total_m
    from app.v_worker_salary ws where not ws.is_actual_leader group by ws.team_id,ws.grade_name
  ), unknowns as (
    select ws.team_id,jsonb_agg(jsonb_build_object('mnv',ws.mnv,'full_name',ws.full_name,'job_title',ws.job_title) order by ws.mnv) data
    from app.v_worker_salary ws where not ws.salary_ok and not ws.is_actual_leader group by ws.team_id
  )
  select a.id,a.leader_name,r.role_name,
    case when r.role_name='Tổ trưởng' then 1 else coalesce(g.cnt,0) end,
    case when r.role_name='Tổ trưởng' then 0 else coalesce(g.avg_m,0) end,
    case when r.role_name='Tổ trưởng' then 0 else coalesce(g.avg_d,0) end,
    case when r.role_name='Tổ trưởng' then 0 else coalesce(g.total_d,0) end,
    case when r.role_name='Tổ trưởng' then 0 else coalesce(g.total_m,0) end,
    case when u.data is null then 'OK - TỰ ĐỘNG' else 'CÓ '||jsonb_array_length(u.data)||' CNCH CHƯA XÁC ĐỊNH HỆ/BẬC' end,
    coalesce(u.data,'[]'::jsonb)
  from allowed a cross join roles r
  left join agg g on g.team_id=a.id and g.grade_name=r.role_name
  left join unknowns u on u.team_id=a.id
  order by a.leader_name,r.sort_order;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Job creation, canonical N:X metrics and grouping
-- ---------------------------------------------------------------------------
alter table public.jobs add column if not exists request_key uuid;
create unique index if not exists uq_jobs_request_key on public.jobs(request_key) where request_key is not null;

create or replace view app.v_job_metrics as
with role_avg as (
  select team_id,grade_name,avg(daily_salary)::numeric avg_daily
  from app.v_worker_salary where salary_ok and not is_actual_leader and grade_name is not null
  group by team_id,grade_name
), priced as (
  select j.*,(j.end_date-j.start_date+1)::int work_days,
    (j.count_worker1*coalesce((select avg_daily from role_avg r where r.team_id=j.team_id and r.grade_name='Thợ bậc 1'),0)
    +j.count_worker2*coalesce((select avg_daily from role_avg r where r.team_id=j.team_id and r.grade_name='Thợ bậc 2'),0)
    +j.count_worker3*coalesce((select avg_daily from role_avg r where r.team_id=j.team_id and r.grade_name='Thợ bậc 3'),0)
    +j.count_helper*coalesce((select avg_daily from role_avg r where r.team_id=j.team_id and r.grade_name='Thợ phụ'),0))::numeric daily_payroll,
    (select count(*) from public.price_items p where p.is_active and p.category_name=j.category_name and p.content=j.content) price_matches,
    (select min(p.unit) from public.price_items p where p.is_active and p.category_name=j.category_name and (p.content=j.content or j.is_special_labor)) unit,
    (select min(p.calc_price) from public.price_items p where p.is_active and p.category_name=j.category_name and p.content=j.content) normal_price
  from public.jobs j where j.deleted_at is null
), production as (
  select p.*,(count_leader+count_worker1+count_worker2+count_worker3+count_helper)::int total_people,
    case when is_special_labor then daily_payroll/nullif(count_leader+count_worker1+count_worker2+count_worker3+count_helper,0)
         when price_matches=1 then normal_price end::numeric unit_price
  from priced p
), valued as (
  select p.*,(quantity*unit_price)::numeric production_value,
    case when group_code is null then id::text else
      concat_ws('‡',team_id::text,group_code,start_date::text,end_date::text,coalesce(location,''),
                count_leader,count_worker1,count_worker2,count_worker3,count_helper) end group_key
  from production p
), allocated as (
  select v.*,sum(production_value) over(partition by group_key) group_value,
    count(*) over(partition by group_key) group_rows
  from valued v
)
select a.*,
  case when group_value>0 then daily_payroll*production_value/group_value else daily_payroll/nullif(group_rows,0) end::numeric allocated_daily_payroll,
  (case when group_value>0 then daily_payroll*production_value/group_value else daily_payroll/nullif(group_rows,0) end/nullif(unit_price,0))::numeric breakeven_daily,
  (quantity/nullif(work_days,0))::numeric target_daily,
  ((case when group_value>0 then daily_payroll*production_value/group_value else daily_payroll/nullif(group_rows,0) end/nullif(unit_price,0))*work_days)::numeric total_breakeven,
  ((case when group_value>0 then daily_payroll*production_value/group_value else daily_payroll/nullif(group_rows,0) end)*work_days)::numeric actual_labor_cost,
  (production_value-(case when group_value>0 then daily_payroll*production_value/group_value else daily_payroll/nullif(group_rows,0) end)*work_days)::numeric difference,
  case when unit_price is null then 'CHƯA ĐỦ ĐƠN GIÁ/LƯƠNG'
       when ((case when group_value>0 then daily_payroll*production_value/group_value else daily_payroll/nullif(group_rows,0) end/nullif(unit_price,0))*work_days)>quantity
       then 'KHÔNG ĐẠT ĐỊNH MỨC! Lỗ nhân công. Hãy giảm số lượng người hoặc giảm ngày thi công!' else 'An toàn - Đạt định mức' end evaluation
from allocated a;

create or replace view app.v_job_production as
select id job_id,team_id,start_date,end_date,
       unit_price is not null as job_ok,production_value
from app.v_job_metrics;

create or replace function public.create_job(
  p_request_key uuid,p_team_id uuid,p_start_date date,p_end_date date,
  p_category_name text,p_content text,p_location text,p_quantity numeric,
  p_count_leader int,p_count_worker1 int,p_count_worker2 int,p_count_worker3 int,p_count_helper int
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_special boolean; v_people int; v_days int;
begin
  if app.current_role() not in ('ADMIN','GIAM_SAT','TO_TRUONG') or not app.can_access_team(p_team_id) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  select j.id into v_id from public.jobs j where j.request_key=p_request_key;
  if v_id is not null then return v_id; end if;
  if not exists(select 1 from public.teams t where t.id=p_team_id and t.is_active and t.deleted_at is null) then raise exception 'TEAM_NOT_ACTIVE'; end if;
  if p_end_date<p_start_date then raise exception 'INVALID_DATES'; end if;
  if not exists(select 1 from public.work_categories c where c.name=btrim(p_category_name) and c.is_active) then raise exception 'INVALID_CATEGORY'; end if;
  if btrim(coalesce(p_content,''))='' or char_length(p_content)>200 then raise exception 'INVALID_CONTENT'; end if;
  if least(p_count_leader,p_count_worker1,p_count_worker2,p_count_worker3,p_count_helper)<0
     or greatest(p_count_leader,p_count_worker1,p_count_worker2,p_count_worker3,p_count_helper)>999 then raise exception 'INVALID_COUNTS'; end if;
  v_people:=p_count_leader+p_count_worker1+p_count_worker2+p_count_worker3+p_count_helper;
  if v_people<=0 then raise exception 'NO_WORKERS'; end if;
  v_days:=p_end_date-p_start_date+1;
  v_special:=app.norm_vn(p_category_name) in ('dao tao','phat sinh');
  if not v_special and not exists(select 1 from public.price_items p where p.is_active and p.category_name=btrim(p_category_name) and p.content=btrim(p_content)) then
    raise exception 'CONTENT_NOT_IN_CATALOG';
  end if;
  if not v_special and coalesce(p_quantity,0)<=0 then raise exception 'INVALID_QUANTITY'; end if;
  insert into public.jobs(request_key,team_id,start_date,end_date,category_name,content,location,quantity,
    count_leader,count_worker1,count_worker2,count_worker3,count_helper,is_special_labor,created_by,updated_by)
  values(p_request_key,p_team_id,p_start_date,p_end_date,btrim(p_category_name),btrim(p_content),nullif(btrim(p_location),''),
    case when v_special then v_people*v_days else p_quantity end,
    p_count_leader,p_count_worker1,p_count_worker2,p_count_worker3,p_count_helper,v_special,auth.uid(),auth.uid())
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.get_job_metrics(p_team_id uuid default null,p_week_id uuid default null)
returns setof app.v_job_metrics language sql stable security definer set search_path = '' as $$
  select m.* from app.v_job_metrics m
  where app.can_access_team(m.team_id)
    and (p_team_id is null or m.team_id=p_team_id)
    and (p_week_id is null or m.week_id=p_week_id)
  order by m.start_date desc,m.created_at desc
$$;

create or replace function public.create_job_group(p_job_ids uuid[])
returns text language plpgsql security definer set search_path = '' as $$
declare v_team uuid;v_code text;v_count int;v_date text:=to_char(current_date,'YYYYMMDD');v_seq int;
begin
  if coalesce(array_length(p_job_ids,1),0)<2 then raise exception 'AT_LEAST_TWO_JOBS'; end if;
  perform 1 from public.jobs where id=any(p_job_ids) and deleted_at is null for update;
  select count(*),(array_agg(team_id))[1] into v_count,v_team from public.jobs where id=any(p_job_ids) and deleted_at is null;
  if v_count<>array_length(p_job_ids,1) then raise exception 'JOB_NOT_FOUND_OR_DUPLICATE_IDS'; end if;
  if app.current_role() not in ('ADMIN','GIAM_SAT','TO_TRUONG') or not app.can_access_team(v_team) then raise exception 'FORBIDDEN'; end if;
  if (select count(distinct concat_ws('‡',team_id,start_date,end_date,coalesce(location,''),count_leader,count_worker1,count_worker2,count_worker3,count_helper)) from public.jobs where id=any(p_job_ids))<>1
     or exists(select 1 from public.jobs where id=any(p_job_ids) and group_code is not null) then raise exception 'GROUP_VALIDATION_FAILED'; end if;
  perform pg_advisory_xact_lock(hashtext('JOB_GROUP_'||v_date));
  select coalesce(max(substring(group_code from '([0-9]+)$')::int),0)+1 into v_seq from public.jobs where group_code like 'MN-'||v_date||'-%';
  v_code:='MN-'||v_date||'-'||lpad(v_seq::text,2,'0');
  update public.jobs set group_code=v_code,updated_at=now(),updated_by=auth.uid() where id=any(p_job_ids);
  return v_code;
end $$;

create or replace function public.remove_job_group(p_team_id uuid,p_group_code text)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_count int;
begin
  if app.current_role() not in ('ADMIN','GIAM_SAT','TO_TRUONG') or not app.can_access_team(p_team_id) then raise exception 'FORBIDDEN'; end if;
  update public.jobs set group_code=null,updated_at=now(),updated_by=auth.uid()
  where team_id=p_team_id and group_code=p_group_code and deleted_at is null;
  get diagnostics v_count=row_count; if v_count=0 then raise exception 'GROUP_NOT_FOUND'; end if; return v_count;
end $$;

create or replace function public.create_work_week(p_team_id uuid,p_week_slot int,p_start_date date,p_end_date date)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if app.current_role() not in ('ADMIN','GIAM_SAT','TO_TRUONG') or not app.can_access_team(p_team_id) then raise exception 'FORBIDDEN'; end if;
  insert into public.work_weeks(team_id,week_slot,start_date,end_date,created_by)
  values(p_team_id,p_week_slot,p_start_date,p_end_date,auth.uid()) returning id into v_id;
  return v_id;
end $$;

create or replace function public.assign_jobs_to_week(p_week_id uuid,p_job_ids uuid[])
returns integer language plpgsql security definer set search_path = '' as $$
declare v_week public.work_weeks;v_count int;
begin
  if coalesce(array_length(p_job_ids,1),0)=0 then raise exception 'EMPTY_JOB_SELECTION'; end if;
  if array_length(p_job_ids,1)<>(select count(distinct x) from unnest(p_job_ids) x) then raise exception 'DUPLICATE_JOB_IDS'; end if;
  select * into v_week from public.work_weeks where id=p_week_id and status='ACTIVE' for update;
  if v_week.id is null then raise exception 'WEEK_NOT_FOUND'; end if;
  if app.current_role() not in ('ADMIN','GIAM_SAT','TO_TRUONG') or not app.can_access_team(v_week.team_id) then raise exception 'FORBIDDEN'; end if;
  perform 1 from public.jobs where id=any(p_job_ids) for update;
  if (select count(*) from public.jobs j where j.id=any(p_job_ids) and j.deleted_at is null)<>array_length(p_job_ids,1)
     or exists(select 1 from public.jobs j where j.id=any(p_job_ids) and (j.team_id<>v_week.team_id or j.start_date<v_week.start_date or j.end_date>v_week.end_date or j.week_id is not null)) then raise exception 'JOB_WEEK_VALIDATION_FAILED'; end if;
  update public.jobs set week_id=v_week.id,updated_at=now(),updated_by=auth.uid() where id=any(p_job_ids);
  get diagnostics v_count=row_count; if v_count<>array_length(p_job_ids,1) then raise exception 'PARTIAL_ASSIGNMENT'; end if; return v_count;
end $$;

create or replace function public.unassign_jobs_from_week(p_job_ids uuid[])
returns integer language plpgsql security definer set search_path = '' as $$
declare v_team uuid;v_count int;
begin
  if coalesce(array_length(p_job_ids,1),0)=0 then raise exception 'EMPTY_JOB_SELECTION'; end if;
  perform 1 from public.jobs where id=any(p_job_ids) and deleted_at is null and week_id is not null for update;
  select count(*),(array_agg(team_id))[1] into v_count,v_team from public.jobs where id=any(p_job_ids) and deleted_at is null and week_id is not null;
  if v_count<>array_length(p_job_ids,1) then raise exception 'UNASSIGN_VALIDATION_FAILED'; end if;
  if app.current_role() not in ('ADMIN','GIAM_SAT','TO_TRUONG') or not app.can_access_team(v_team)
     or exists(select 1 from public.jobs where id=any(p_job_ids) and team_id<>v_team) then raise exception 'FORBIDDEN'; end if;
  update public.jobs set week_id=null,updated_at=now(),updated_by=auth.uid() where id=any(p_job_ids);
  get diagnostics v_count=row_count; return v_count;
end $$;

-- ---------------------------------------------------------------------------
-- 5. PGV and week-scoped CNCH assignments
-- ---------------------------------------------------------------------------
alter table public.assignments add column if not exists week_id uuid references public.work_weeks(id) on delete restrict;
alter table public.assignments add column if not exists assign_date date;
alter table public.assignments add column if not exists receive_date date;
alter table public.assignments drop constraint if exists uq_assignment_team_worker;
create unique index if not exists uq_assignment_week_worker on public.assignments(week_id,worker_id) where week_id is not null;

create table if not exists public.pgv_save_operations(
  request_key uuid primary key,week_id uuid not null references public.work_weeks(id) on delete restrict,
  payload_hash text not null,row_count int not null,created_by uuid not null,created_at timestamptz not null default now()
);
alter table public.pgv_save_operations enable row level security;

create or replace function public.get_pgv_common(p_team_id uuid,p_week_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_week public.work_weeks;v_team text;v_workers int;v_rows jsonb;
begin
  if not app.can_access_team(p_team_id) then raise exception 'FORBIDDEN'; end if;
  select * into v_week from public.work_weeks where id=p_week_id and team_id=p_team_id and status='ACTIVE';
  if v_week.id is null then raise exception 'WEEK_NOT_FOUND'; end if;
  select leader_name into v_team from public.teams where id=p_team_id;
  select count(*) into v_workers from public.workers where team_id=p_team_id and deleted_at is null;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.start_date,x.created_at),'[]'::jsonb) into v_rows
  from (select m.* from app.v_job_metrics m where m.team_id=p_team_id and m.week_id=p_week_id
        and (m.group_code is null or m.id=(select m2.id from app.v_job_metrics m2 where m2.group_key=m.group_key order by m2.created_at,m2.id limit 1))) x;
  return jsonb_build_object('team_id',p_team_id,'team_name',v_team,'week',to_jsonb(v_week),
    'assign_date',v_week.start_date-1,'receive_date',v_week.start_date,'worker_count',v_workers,'rows',v_rows);
end $$;

create or replace function public.get_pgv_cnch(p_team_id uuid,p_receive_date date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_week public.work_weeks;v_workers jsonb;v_jobs jsonb;v_assign jsonb;
begin
  if not app.can_access_team(p_team_id) then raise exception 'FORBIDDEN'; end if;
  select * into v_week from public.work_weeks where team_id=p_team_id and status='ACTIVE'
    and p_receive_date between start_date and end_date;
  if v_week.id is null then raise exception 'DATE_OUTSIDE_ACTIVE_WEEK'; end if;
  select coalesce(jsonb_agg(to_jsonb(w) order by w.stt_in_team,w.mnv),'[]'::jsonb) into v_workers
    from (select id,mnv,full_name,job_title,stt_in_team from public.workers where team_id=p_team_id and deleted_at is null) w;
  select coalesce(jsonb_agg(to_jsonb(j) order by j.start_date,j.created_at),'[]'::jsonb) into v_jobs
    from (select id,content,location,quantity,start_date,end_date,target_daily,created_at from app.v_job_metrics where team_id=p_team_id and week_id=v_week.id) j;
  select coalesce(jsonb_agg(to_jsonb(a)),'[]'::jsonb) into v_assign
    from (select worker_id,job_id,content_label,target,completed_qty from public.assignments where week_id=v_week.id) a;
  return jsonb_build_object('week',to_jsonb(v_week),'receive_date',p_receive_date,'assign_date',p_receive_date-1,
    'workers',v_workers,'jobs',v_jobs,'assignments',v_assign);
end $$;

create or replace function public.save_pgv_cnch_assignments(
  p_request_key uuid,p_team_id uuid,p_receive_date date,p_items jsonb
) returns integer language plpgsql security definer set search_path = '' as $$
declare v_week public.work_weeks;v_hash text:=md5(coalesce(p_items,'[]'::jsonb)::text);v_count int;
begin
  if app.current_role() not in ('ADMIN','GIAM_SAT','TO_TRUONG') or not app.can_access_team(p_team_id) then raise exception 'FORBIDDEN'; end if;
  select * into v_week from public.work_weeks where team_id=p_team_id and status='ACTIVE'
    and p_receive_date between start_date and end_date for update;
  if v_week.id is null then raise exception 'DATE_OUTSIDE_ACTIVE_WEEK'; end if;
  if exists(select 1 from public.pgv_save_operations o where o.request_key=p_request_key) then
    select row_count into v_count from public.pgv_save_operations where request_key=p_request_key and payload_hash=v_hash;
    if v_count is null then raise exception 'IDEMPOTENCY_KEY_REUSED'; end if; return v_count;
  end if;
  if jsonb_typeof(p_items)<>'array' then raise exception 'INVALID_ASSIGNMENT_PAYLOAD'; end if;
  if exists(select 1 from jsonb_array_elements(p_items) x
    where not exists(select 1 from public.workers w where w.id=(x->>'worker_id')::uuid and w.team_id=p_team_id and w.deleted_at is null)
       or (nullif(x->>'job_id','') is not null and not exists(select 1 from public.jobs j where j.id=(x->>'job_id')::uuid and j.team_id=p_team_id and j.week_id=v_week.id and j.deleted_at is null))
       or char_length(coalesce(x->>'target',''))>100 or char_length(coalesce(x->>'completed_qty',''))>100) then raise exception 'ASSIGNMENT_VALIDATION_FAILED'; end if;
  if (select count(*) from jsonb_array_elements(p_items))<>(select count(distinct x->>'worker_id') from jsonb_array_elements(p_items) x) then raise exception 'DUPLICATE_WORKER'; end if;
  delete from public.assignments where week_id=v_week.id;
  insert into public.assignments(team_id,week_id,worker_id,job_id,content_label,target,completed_qty,assign_date,receive_date,created_by,updated_by)
  select p_team_id,v_week.id,(x->>'worker_id')::uuid,nullif(x->>'job_id','')::uuid,
    nullif(x->>'content_label',''),nullif(x->>'target',''),nullif(x->>'completed_qty',''),p_receive_date-1,p_receive_date,auth.uid(),auth.uid()
  from jsonb_array_elements(p_items) x;
  get diagnostics v_count=row_count;
  insert into public.pgv_save_operations(request_key,week_id,payload_hash,row_count,created_by)
  values(p_request_key,v_week.id,v_hash,v_count,auth.uid());
  return v_count;
end $$;

-- ---------------------------------------------------------------------------
-- 6. Fail-closed week archive: prepare snapshot -> verified Storage backup -> finalize
-- ---------------------------------------------------------------------------
create table if not exists public.week_archive_operations(
  id uuid primary key,week_id uuid not null references public.work_weeks(id) on delete restrict,
  team_id uuid not null references public.teams(id) on delete restrict,
  status text not null default 'PENDING' check(status in('PENDING','COMPLETED')),
  snapshot jsonb not null,row_count int not null,backup_path text,backup_sha256 text,
  created_by uuid not null,created_at timestamptz not null default now(),completed_at timestamptz
);
alter table public.week_archive_operations enable row level security;
grant select on public.week_archive_operations to authenticated;
drop policy if exists p_week_archive_select on public.week_archive_operations;
create policy p_week_archive_select on public.week_archive_operations for select to authenticated
using (app.current_role()='ADMIN');

alter table public.job_history add column if not exists archive_operation_id uuid;
alter table public.job_history add column if not exists source_job_id uuid;
create unique index if not exists uq_job_history_archive_source on public.job_history(archive_operation_id,source_job_id)
where archive_operation_id is not null and source_job_id is not null;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('kpi-week-backups','kpi-week-backups',false,10485760,array['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

create or replace function public.prepare_week_archive(p_operation_id uuid,p_week_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_week public.work_weeks;v_snapshot jsonb;v_count int;
begin
  if app.current_role()<>'ADMIN' then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if exists(select 1 from public.week_archive_operations where id=p_operation_id) then
    return (select jsonb_build_object('operation_id',id,'week_id',week_id,'team_id',team_id,'row_count',row_count,'snapshot',snapshot,'status',status)
            from public.week_archive_operations where id=p_operation_id);
  end if;
  select * into v_week from public.work_weeks where id=p_week_id and status='ACTIVE' for update;
  if v_week.id is null then raise exception 'WEEK_NOT_FOUND'; end if;
  select coalesce(jsonb_agg(to_jsonb(m) order by m.start_date,m.created_at),'[]'::jsonb),count(*) into v_snapshot,v_count
  from app.v_job_metrics m where m.week_id=p_week_id;
  insert into public.week_archive_operations(id,week_id,team_id,snapshot,row_count,created_by)
  values(p_operation_id,p_week_id,v_week.team_id,v_snapshot,v_count,auth.uid());
  return jsonb_build_object('operation_id',p_operation_id,'week_id',p_week_id,'team_id',v_week.team_id,'row_count',v_count,'snapshot',v_snapshot,'status','PENDING');
end $$;

create or replace function public.finalize_week_archive(p_operation_id uuid,p_backup_path text,p_backup_sha256 text)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_op public.week_archive_operations;v_inserted int;v_deleted int;
begin
  if app.current_role()<>'ADMIN' then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  select * into v_op from public.week_archive_operations where id=p_operation_id for update;
  if v_op.id is null then raise exception 'ARCHIVE_OPERATION_NOT_FOUND'; end if;
  if v_op.status='COMPLETED' then return v_op.row_count; end if;
  if coalesce(p_backup_path,'')='' or coalesce(p_backup_sha256,'')!~'^[0-9a-f]{64}$' then raise exception 'INVALID_BACKUP_PROOF'; end if;
  if not exists(select 1 from storage.objects o where o.bucket_id='kpi-week-backups' and o.name=p_backup_path and coalesce((o.metadata->>'size')::bigint,0)>0) then
    raise exception 'BACKUP_NOT_VERIFIED';
  end if;
  perform 1 from public.work_weeks where id=v_op.week_id and status='ACTIVE' for update;
  if not found then raise exception 'WEEK_NOT_ACTIVE'; end if;
  if (select count(*) from public.jobs where week_id=v_op.week_id and deleted_at is null)<>v_op.row_count then raise exception 'WEEK_CHANGED_AFTER_SNAPSHOT'; end if;

  insert into public.job_history(archive_operation_id,source_job_id,batch_label,archived_at,team_id,team_name,
    start_date,end_date,category_name,content,location,quantity,count_leader,count_worker1,count_worker2,count_worker3,count_helper,
    unit,unit_price,work_days,payroll,breakeven_qty,daily_qty,difference,evaluation,group_code)
  select p_operation_id,m.id,'Tuần '||w.week_slot,now(),m.team_id,t.leader_name,m.start_date,m.end_date,m.category_name,m.content,m.location,
    m.quantity,m.count_leader,m.count_worker1,m.count_worker2,m.count_worker3,m.count_helper,m.unit,m.unit_price,m.work_days,
    m.actual_labor_cost,m.total_breakeven,m.target_daily,m.difference,m.evaluation,m.group_code
  from app.v_job_metrics m join public.work_weeks w on w.id=m.week_id join public.teams t on t.id=m.team_id
  where m.week_id=v_op.week_id;
  get diagnostics v_inserted=row_count;
  if v_inserted<>v_op.row_count then raise exception 'ARCHIVE_COUNT_MISMATCH'; end if;

  update public.jobs set deleted_at=now(),week_id=null,updated_at=now(),updated_by=auth.uid()
  where week_id=v_op.week_id and deleted_at is null;
  get diagnostics v_deleted=row_count;
  if v_deleted<>v_op.row_count then raise exception 'DELETE_COUNT_MISMATCH'; end if;
  update public.work_weeks set status='ARCHIVED',updated_at=now() where id=v_op.week_id;
  update public.week_archive_operations set status='COMPLETED',backup_path=p_backup_path,
    backup_sha256=p_backup_sha256,completed_at=now() where id=p_operation_id;
  return v_deleted;
end $$;

-- ---------------------------------------------------------------------------
-- Grants: no anon execution, authenticated only. Internal views stay private.
-- ---------------------------------------------------------------------------
revoke all on app.v_worker_salary,app.v_team_payroll,app.v_job_metrics from public,anon,authenticated;

do $$
declare f regprocedure;
begin
  foreach f in array array[
    'public.admin_list_profiles()'::regprocedure,
    'public.admin_set_profile(uuid,text,text,boolean,uuid,uuid[],text)'::regprocedure,
    'public.admin_save_worker(uuid,text,text,text,uuid,integer)'::regprocedure,
    'public.admin_archive_worker(uuid)'::regprocedure,
    'public.get_payroll_summary(uuid)'::regprocedure,
    'public.create_job(uuid,uuid,date,date,text,text,text,numeric,integer,integer,integer,integer,integer)'::regprocedure,
    'public.get_job_metrics(uuid,uuid)'::regprocedure,
    'public.create_job_group(uuid[])'::regprocedure,
    'public.remove_job_group(uuid,text)'::regprocedure,
    'public.create_work_week(uuid,integer,date,date)'::regprocedure,
    'public.unassign_jobs_from_week(uuid[])'::regprocedure,
    'public.get_pgv_common(uuid,uuid)'::regprocedure,
    'public.get_pgv_cnch(uuid,date)'::regprocedure,
    'public.save_pgv_cnch_assignments(uuid,uuid,date,jsonb)'::regprocedure,
    'public.prepare_week_archive(uuid,uuid)'::regprocedure,
    'public.finalize_week_archive(uuid,text,text)'::regprocedure
  ] loop
    execute format('revoke execute on function %s from public, anon',f);
    execute format('grant execute on function %s to authenticated',f);
  end loop;
end $$;

notify pgrst,'reload schema';
