-- =====================================================================
-- 022_kpi_safe_api.sql · Phase 9E — KPI compute guard (ADMIN canary)
-- Internal views remain in schema app (not exposed by PostgREST).
-- Public RPC returns only aggregate KPI fields; no IDs, wages or unit prices.
-- VND rule: round(final production - payroll, 0), no ±1,000 tolerance.
-- =====================================================================

create or replace view app.v_worker_salary as
with classified as (
  select
    w.id as worker_id,
    w.team_id,
    w.full_name,
    t.leader_name,
    app.norm_vn(w.job_title) as title_n,
    case
      when app.norm_vn(w.job_title) like '%phu tro%'
        or app.norm_vn(w.job_title) like '%tho phu%' then 'Thợ phụ'
      when app.norm_vn(w.job_title) ~ '(bac|b)[[:space:]]*1([^0-9]|$)' then 'Thợ bậc 1'
      when app.norm_vn(w.job_title) ~ '(bac|b)[[:space:]]*2([^0-9]|$)' then 'Thợ bậc 2'
      when app.norm_vn(w.job_title) ~ '(bac|b)[[:space:]]*3([^0-9]|$)' then 'Thợ bậc 3'
      else null
    end as grade_name,
    case
      when app.norm_vn(w.job_title) ~ '(^| )(pccc|phong chay chua chay|chua chay)( |$)' then 'PCCC'
      when app.norm_vn(w.job_title) ~ '(^| )(nuoc|cap thoat nuoc|cap nuoc|thoat nuoc)( |$)' then 'NUOC'
      when app.norm_vn(w.job_title) ~ '(^| )dien( |$)' then 'DIEN'
      when app.norm_vn(w.job_title) ~ '(^| )(hvac|thong gio|dieu hoa khong khi|dieu hoa)( |$)' then 'HVAC'
      when app.norm_vn(w.job_title) ~ '(^| )han( |$)' then 'HAN'
      else null
    end as system_code
  from public.workers w
  join public.teams t on t.id = w.team_id
  where w.deleted_at is null and t.is_active = true
), resolved as (
  select
    c.*,
    app.norm_vn(c.full_name) = app.norm_vn(c.leader_name) as is_actual_leader,
    case
      when app.norm_vn(c.full_name) = app.norm_vn(c.leader_name) then 0::numeric
      when c.grade_name = 'Thợ phụ' then (
        select min(ss.daily_salary)
        from public.salary_standards ss
        join public.salary_grades sg on sg.id = ss.grade_id
        where ss.is_active and sg.is_active and sg.name = 'Thợ phụ'
      )
      else (
        select min(ss.daily_salary)
        from public.salary_standards ss
        join public.salary_grades sg on sg.id = ss.grade_id
        join public.systems s on s.id = ss.system_id
        where ss.is_active and sg.is_active and s.is_active
          and sg.name = c.grade_name and s.code = c.system_code
      )
    end as daily_salary,
    case
      when app.norm_vn(c.full_name) = app.norm_vn(c.leader_name) then true
      when c.grade_name is null then false
      when c.grade_name = 'Thợ phụ' then (
        select count(distinct ss.daily_salary) = 1
        from public.salary_standards ss
        join public.salary_grades sg on sg.id = ss.grade_id
        where ss.is_active and sg.is_active and sg.name = 'Thợ phụ'
      )
      when c.system_code is null then false
      else (
        select count(*) = 1
        from public.salary_standards ss
        join public.salary_grades sg on sg.id = ss.grade_id
        join public.systems s on s.id = ss.system_id
        where ss.is_active and sg.is_active and s.is_active
          and sg.name = c.grade_name and s.code = c.system_code
      )
    end as salary_ok
  from classified c
)
select worker_id, team_id, grade_name, system_code, is_actual_leader,
       daily_salary, salary_ok
from resolved;

create or replace view app.v_team_payroll as
select
  team_id,
  count(*)::int as worker_count,
  count(*) filter (where not salary_ok or daily_salary is null)::int as unknown_salary_count,
  coalesce(sum(daily_salary) filter (where salary_ok), 0)::numeric as daily_payroll
from app.v_worker_salary
group by team_id;

create or replace view app.v_job_production as
with role_avg as (
  select team_id, grade_name, avg(daily_salary)::numeric as avg_daily_salary
  from app.v_worker_salary
  where salary_ok and not is_actual_leader and grade_name is not null
  group by team_id, grade_name
), base as (
  select
    j.id as job_id,
    j.team_id,
    j.start_date,
    j.end_date,
    j.quantity,
    j.is_special_labor,
    j.count_leader,
    j.count_worker1,
    j.count_worker2,
    j.count_worker3,
    j.count_helper,
    (select count(*) from public.price_items p
      where p.is_active and p.category_name = j.category_name and p.content = j.content) as price_match_count,
    (select min(p.calc_price) from public.price_items p
      where p.is_active and p.category_name = j.category_name and p.content = j.content) as normal_unit_price,
    (select avg_daily_salary from role_avg r where r.team_id=j.team_id and r.grade_name='Thợ bậc 1') as wage_1,
    (select avg_daily_salary from role_avg r where r.team_id=j.team_id and r.grade_name='Thợ bậc 2') as wage_2,
    (select avg_daily_salary from role_avg r where r.team_id=j.team_id and r.grade_name='Thợ bậc 3') as wage_3,
    (select avg_daily_salary from role_avg r where r.team_id=j.team_id and r.grade_name='Thợ phụ') as wage_helper
  from public.jobs j
  where j.deleted_at is null
), computed as (
  select
    b.*,
    (count_leader + count_worker1 + count_worker2 + count_worker3 + count_helper) as total_people,
    (
      count_worker1 * coalesce(wage_1,0) +
      count_worker2 * coalesce(wage_2,0) +
      count_worker3 * coalesce(wage_3,0) +
      count_helper  * coalesce(wage_helper,0)
    )::numeric as special_daily_payroll,
    case
      when not is_special_labor then price_match_count = 1 and normal_unit_price is not null
      else
        (count_leader + count_worker1 + count_worker2 + count_worker3 + count_helper) > 0
        and (count_worker1 = 0 or wage_1 is not null)
        and (count_worker2 = 0 or wage_2 is not null)
        and (count_worker3 = 0 or wage_3 is not null)
        and (count_helper = 0 or wage_helper is not null)
    end as job_ok
  from base b
)
select
  job_id, team_id, start_date, end_date, job_ok,
  case
    when not is_special_labor then quantity * normal_unit_price
    when total_people > 0 then quantity * special_daily_payroll / total_people
    else null
  end::numeric as production_value
from computed;

create or replace view app.v_kpi_evaluation as
with job_totals as (
  select
    jp.team_id,
    min(jp.start_date) as start_date,
    max(jp.end_date) as end_date,
    count(*) filter (where not jp.job_ok or jp.production_value is null)::int as invalid_job_count,
    sum(jp.production_value) filter (where jp.job_ok)::numeric as total_production
  from app.v_job_production jp
  group by jp.team_id
), amounts as (
  select
    jt.team_id,
    t.leader_name as team_name,
    jt.start_date,
    jt.end_date,
    (jt.end_date - jt.start_date + 1)::int as day_count,
    coalesce(tp.unknown_salary_count, 1)::int as unknown_salary_count,
    jt.invalid_job_count,
    coalesce(tp.daily_payroll, 0)::numeric as daily_payroll,
    (coalesce(tp.daily_payroll,0) * (jt.end_date - jt.start_date + 1))::numeric as total_payroll,
    coalesce(jt.total_production,0)::numeric as total_production
  from job_totals jt
  join public.teams t on t.id=jt.team_id and t.is_active
  left join app.v_team_payroll tp on tp.team_id=jt.team_id
), evaluated as (
  select a.*, (a.total_production-a.total_payroll)::numeric as raw_difference,
         round(a.total_production-a.total_payroll,0)::numeric as difference_vnd
  from amounts a
)
select
  team_id, team_name, start_date, end_date, day_count,
  total_payroll, total_production, raw_difference, difference_vnd,
  case
    when total_payroll <= 0 then 'CHƯA CẤU HÌNH QUỸ LƯƠNG'
    when difference_vnd < 0 then 'KHÔNG ĐẠT KPI'
    else 'ĐẠT KPI'
  end as evaluation,
  unknown_salary_count, invalid_job_count
from evaluated;

drop function if exists public.get_kpi_evaluation();

create function public.get_kpi_evaluation()
returns table (
  team_name text,
  start_date date,
  end_date date,
  day_count int,
  total_payroll numeric,
  total_production numeric,
  difference_vnd numeric,
  evaluation text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app.is_active_profile() or app.current_role() <> 'ADMIN' then
    raise exception 'KPI canary requires an active ADMIN profile.' using errcode='42501';
  end if;

  if exists (
    select 1 from app.v_kpi_evaluation k
    where k.unknown_salary_count > 0 or k.invalid_job_count > 0
  ) then
    raise exception 'KPI compute guard failed: incomplete salary or job pricing.' using errcode='P0001';
  end if;

  return query
  select k.team_name,k.start_date,k.end_date,k.day_count,
         k.total_payroll,k.total_production,k.difference_vnd,k.evaluation
  from app.v_kpi_evaluation k
  order by k.team_name;
end;
$$;

comment on function public.get_kpi_evaluation() is
  'Phase 9E ADMIN canary: KPI tổng theo tổ, ROUND chênh lệch đến 1 VND, không dung sai ±1000; fail-closed nếu thiếu lương/đơn giá. Không trả ID/lương ngày/đơn giá.';

revoke all on app.v_worker_salary from public, anon, authenticated;
revoke all on app.v_team_payroll from public, anon, authenticated;
revoke all on app.v_job_production from public, anon, authenticated;
revoke all on app.v_kpi_evaluation from public, anon, authenticated;
revoke execute on function public.get_kpi_evaluation() from public;
revoke execute on function public.get_kpi_evaluation() from anon;
grant execute on function public.get_kpi_evaluation() to authenticated;

notify pgrst, 'reload schema';
