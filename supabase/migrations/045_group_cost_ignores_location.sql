-- 045_group_cost_ignores_location.sql
--
-- Sửa nốt dư âm của migration 041. Đây là chỗ thứ BA giữ quy tắc "phải cùng vị trí", và là
-- chỗ nguy hiểm nhất vì nó không chặn ai cả — nó chỉ âm thầm tính sai tiền.
--
-- BỆNH:
-- app.v_job_metrics gom chi phí nhân công theo group_key, mà group_key có cả location:
--     concat_ws('‡', team_id, group_code, start_date, end_date, coalesce(location,''), ...)
-- Sau 041 người dùng gộp được hai việc khác vị trí, nhưng vì khác location nên chúng rơi vào
-- HAI group_key khác nhau. Mỗi việc thành một nhóm một dòng, và mỗi dòng chịu TRỌN quỹ lương
-- ngày của tổ. Mã nhóm hiện ra trên màn hình nhưng không có tác dụng gì tới con số.
--
-- Đo trên dữ liệu thật (hai việc cùng tổ, cùng ngày, cùng cơ cấu nhân sự):
--     chưa gộp            : 1.538.462 + 1.538.462 = 3.076.923
--     gộp, CÙNG vị trí    : 1.282.051 +   256.410 = 1.538.462  ← đúng, chia một lần
--     gộp, KHÁC vị trí    : 1.538.462 + 1.538.462 = 3.076.923  ← y hệt chưa gộp
-- Chi phí nhân công bị tính hai lần, nên hòa vốn và chênh lệch của cả hai việc đều sai theo
-- hướng xấu hơn thực tế. Người dùng không có dấu hiệu nào để biết.
--
-- CÁCH SỬA: bỏ location khỏi group_key. Một tổ thợ trong cùng khoảng ngày là MỘT quỹ lương,
-- bất kể họ làm ở mấy vị trí — đó chính là điều 041 muốn công nhận.
--
-- CỐ Ý GIỮ LẠI ngày và cơ cấu nhân sự trong group_key. Công thức phân bổ chỉ đúng khi mọi
-- dòng trong nhóm có cùng daily_payroll, tức cùng cơ cấu nhân sự. create_job_group đã bắt
-- điều đó, nhưng nếu dữ liệu có lệch vì lý do nào khác thì tách nhóm ra vẫn an toàn hơn:
-- tách thì tính THỪA chi phí và thấy ngay, gộp bừa thì tính THIẾU và không ai biết.
--
-- Công thức phân bổ, đơn giá, sản lượng, đánh giá định mức: giữ nguyên từng chữ.

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
    -- KHÔNG còn location ở đây. Đây là toàn bộ thay đổi của migration này.
    case when group_code is null then id::text else
      concat_ws('‡',team_id::text,group_code,start_date::text,end_date::text,
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

notify pgrst, 'reload schema';
