-- 038_payroll_perf.sql
--
-- HIỆU NĂNG — phát hiện khi đo tải trên staging ngày 11/08/2026 với quy mô thật
-- (89 tổ, 1.000 công nhân).
--
-- get_payroll_summary(null) mất khoảng 1,0–1,2 giây một lời gọi. Trang "Nhân Sự &
-- Quỹ Lương" gọi nó ở 4 chỗ với p_team_id = null. Khi nhiều người mở trang cùng lúc,
-- truy vấn chạm trần statement timeout 8 giây của Postgres:
--     10 phiên đồng thời -> 10/10 thất bại
--     25 phiên            -> 20/25 thất bại
--     50 phiên            -> 49/50 thất bại, p95 41 giây
-- Bốn RPC còn lại giữ p95 240–500ms ở cùng mức tải, nên điểm nghẽn chỉ nằm ở đây.
--
-- Đo tách phần trên Postgres cục bộ cùng quy mô:
--     quét view, chỉ đếm dòng                      6 ms
--     + phân loại Hệ/Bậc bằng regex               56 ms
--     + is_actual_leader                          62 ms
--     + TRA BẢNG LƯƠNG                           729 ms   <-- toàn bộ chi phí nằm ở đây
--
-- Nguyên nhân: app.v_worker_salary tra lương bằng một subquery TƯƠNG QUAN, chạy lại
-- cho TỪNG công nhân — 1.089 lần cho mỗi lần quét, và get_payroll_summary quét hai lần.
--
-- Cách sửa: gom bảng lương thành một bảng tra nhỏ rồi LEFT JOIN một lần.
--
-- KẾT QUẢ TRẢ VỀ KHÔNG ĐỔI, và điều này chứng minh được chứ không phải phỏng đoán:
--   * uq_salary_system_grade unique (system_id, grade_id)
--   * uq_systems_code unique (code), uq_grade_name unique (name)
--   => mỗi cặp (system.code, salary_grades.name) khớp TỐI ĐA MỘT dòng salary_standards,
--      nên min(monthly_salary) trong bảng tra bằng đúng giá trị mà LIMIT 1 trả về.
--   * grade_name hoặc system_code bằng NULL: subquery cũ trả NULL vì không khớp gì,
--      LEFT JOIN cũng cho NULL. Giống nhau.
-- Toàn bộ phần phân loại Hệ/Bậc, quy tắc Thợ phụ, quy tắc tổ trưởng và phép chia 26
-- giữ nguyên từng ký tự so với 027.

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
), salary_lookup as (
  -- Bảng tra nhỏ (số hệ x số cấp bậc), dựng MỘT lần thay cho subquery chạy mỗi công nhân.
  select s.code system_code, sg.name grade_name, min(ss.monthly_salary) monthly_salary
  from public.salary_standards ss
  join public.salary_grades sg on sg.id=ss.grade_id and sg.is_active
  join public.systems s on s.id=ss.system_id and s.is_active
  where ss.is_active
  group by s.code, sg.name
), resolved as (
  select c.*,
    case when c.is_actual_leader then 0::numeric
         when c.grade_name='Thợ phụ' then hs.monthly_salary
         else sl.monthly_salary
    end monthly_salary
  from classified c
  cross join helper_salary hs
  left join salary_lookup sl
    on sl.grade_name = c.grade_name and sl.system_code = c.system_code
)
select worker_id, team_id, grade_name, system_code, is_actual_leader,
       monthly_salary/26 daily_salary,
       (is_actual_leader or monthly_salary is not null) salary_ok,
       mnv, full_name, job_title, monthly_salary
from resolved;

notify pgrst, 'reload schema';
