-- 027_payroll_parenthesized_grade_parity.sql
-- app.norm_vn preserves punctuation, so a source title like "(bậc 3)" does
-- not have a space before "bac". Match the grade token without that boundary.

create or replace view app.v_worker_salary as
with base as (
  select w.id worker_id,w.team_id,w.mnv,w.full_name,w.job_title,t.leader_name,
         app.norm_vn(w.job_title) title_n
  from public.workers w join public.teams t on t.id=w.team_id
  where w.deleted_at is null and t.deleted_at is null and t.is_active
), flags as (
  select b.*,
    (title_n like '%phu tro%' or title_n like '%tho phu%') helper_flag,
    (title_n ~ '(bac|b)[[:space:]]*1([^0-9]|$)') g1,
    (title_n ~ '(bac|b)[[:space:]]*2([^0-9]|$)') g2,
    (title_n ~ '(bac|b)[[:space:]]*3([^0-9]|$)') g3,
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
