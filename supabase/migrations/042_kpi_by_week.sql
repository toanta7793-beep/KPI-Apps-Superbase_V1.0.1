-- 042_kpi_by_week.sql
--
-- Theo yêu cầu vận hành ngày 11/08/2026, phương án (a):
--   * KPI có bộ lọc chọn Tuần 1–4, chỉ tính các việc thuộc tuần đó.
--   * Việc CHƯA gộp vào tuần nào thì BỎ KHỎI KPI.
--
-- Trước đây get_kpi_evaluation() gom toàn bộ việc chưa xóa của tổ và lấy
-- min(ngày bắt đầu) → max(ngày kết thúc) làm kỳ đánh giá, hoàn toàn không biết tới tuần.
-- Hệ quả: một việc lẻ nằm ngoài mọi tuần vẫn kéo dài kỳ đánh giá và làm phình quỹ lương
-- (quỹ lương = lương ngày × số ngày của kỳ), tức KPI bị sai theo hướng khắt khe hơn thực tế.
--
-- CÔNG THỨC GIỮ NGUYÊN TỪNG PHÉP TÍNH:
--   day_count        = ngày kết thúc lớn nhất − ngày bắt đầu nhỏ nhất + 1
--   total_payroll    = lương ngày của tổ × day_count
--   total_production = tổng sản lượng các việc hợp lệ
--   difference_vnd   = làm tròn(total_production − total_payroll)
--   đánh giá         = CHƯA CẤU HÌNH QUỸ LƯƠNG / KHÔNG ĐẠT KPI / ĐẠT KPI
-- Khác biệt duy nhất: phạm vi các việc được đưa vào phép tính.
--
-- Cổng an toàn "KPI compute guard" cũng thu về đúng tuần đang xem. Trước đây một việc thiếu
-- đơn giá ở tuần khác cũng chặn toàn bộ màn hình KPI; nay chỉ chặn đúng tuần có vấn đề.

-- v_job_production cần biết việc thuộc tuần nào.
-- Cột mới phải nằm CUỐI: create or replace view chỉ cho thêm cột ở cuối, chèn vào giữa sẽ
-- báo "cannot change name of view column".
create or replace view app.v_job_production as
select m.id as job_id,
       m.team_id,
       m.start_date,
       m.end_date,
       (m.unit_price is not null) as job_ok,
       m.production_value,
       m.week_id,
       w.week_slot
from app.v_job_metrics m
left join public.work_weeks w on w.id = m.week_id;

-- Đổi kiểu trả về nên phải bỏ hàm cũ trước.
drop function if exists public.get_kpi_evaluation();
drop function if exists public.get_kpi_evaluation(integer);

create function public.get_kpi_evaluation(p_week_slot integer default null)
returns table (
  week_slot int,
  team_name text,
  start_date date,
  end_date date,
  day_count int,
  total_payroll numeric,
  total_production numeric,
  difference_vnd numeric,
  evaluation text
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.is_active_profile() or app.current_role() <> 'ADMIN' then
    raise exception 'KPI canary requires an active ADMIN profile.' using errcode='42501';
  end if;
  if p_week_slot is not null and p_week_slot not between 1 and 4 then
    raise exception 'INVALID_WEEK_SLOT';
  end if;

  -- Cổng an toàn giữ nguyên cách hành xử cũ: có việc thiếu đơn giá hoặc tổ chưa xác định
  -- đủ Hệ/Bậc thì BÁO LỖI cả màn hình, KHÔNG âm thầm bỏ tổ đó ra khỏi bảng.
  -- Giấu đi thì người quản lý không biết là bảng đang thiếu tổ, còn tệ hơn không có số.
  -- Khác bản cũ ở đúng một chỗ: chỉ xét trong phạm vi tuần đang xem, và nói rõ tổ nào.
  if exists (
    select 1
    from app.v_job_production jp
    join public.teams t on t.id = jp.team_id and t.is_active
    left join app.v_team_payroll tp on tp.team_id = jp.team_id
    where jp.week_id is not null
      and (p_week_slot is null or jp.week_slot = p_week_slot)
      and (coalesce(tp.unknown_salary_count,1) > 0 or not jp.job_ok or jp.production_value is null)
  ) then
    raise exception 'KPI compute guard failed: incomplete salary or job pricing. Tổ: %',
      (select string_agg(distinct t.leader_name, ', ')
         from app.v_job_production jp
         join public.teams t on t.id = jp.team_id and t.is_active
         left join app.v_team_payroll tp on tp.team_id = jp.team_id
        where jp.week_id is not null
          and (p_week_slot is null or jp.week_slot = p_week_slot)
          and (coalesce(tp.unknown_salary_count,1) > 0 or not jp.job_ok or jp.production_value is null))
      using errcode='P0001';
  end if;

  return query
  with scoped as (
    -- Chỉ việc ĐÃ gộp vào một tuần. Việc chưa gộp bị loại khỏi KPI theo đúng yêu cầu.
    select jp.* from app.v_job_production jp
    where jp.week_id is not null
      and (p_week_slot is null or jp.week_slot = p_week_slot)
  ), job_totals as (
    select s.team_id, s.week_slot,
           min(s.start_date) as start_date,
           max(s.end_date) as end_date,
           sum(s.production_value) filter (where s.job_ok)::numeric as total_production
    from scoped s
    group by s.team_id, s.week_slot
  ), amounts as (
    select jt.team_id, jt.week_slot,
           t.leader_name as team_name,
           jt.start_date, jt.end_date,
           (jt.end_date - jt.start_date + 1)::int as day_count,
           (coalesce(tp.daily_payroll,0) * (jt.end_date - jt.start_date + 1))::numeric as total_payroll,
           coalesce(jt.total_production,0)::numeric as total_production
    from job_totals jt
    join public.teams t on t.id = jt.team_id and t.is_active
    left join app.v_team_payroll tp on tp.team_id = jt.team_id
  )
  -- week_slot trong work_weeks là smallint, phải ép về int cho khớp kiểu trả về.
  select a.week_slot::int, a.team_name, a.start_date, a.end_date, a.day_count,
         a.total_payroll, a.total_production,
         round(a.total_production - a.total_payroll, 0),
         case
           when a.total_payroll <= 0 then 'CHƯA CẤU HÌNH QUỸ LƯƠNG'
           when round(a.total_production - a.total_payroll, 0) < 0 then 'KHÔNG ĐẠT KPI'
           else 'ĐẠT KPI'
         end
  from amounts a
  order by a.week_slot, a.team_name;
end $$;

revoke execute on function public.get_kpi_evaluation(integer) from public, anon;
grant  execute on function public.get_kpi_evaluation(integer) to authenticated;
notify pgrst, 'reload schema';
