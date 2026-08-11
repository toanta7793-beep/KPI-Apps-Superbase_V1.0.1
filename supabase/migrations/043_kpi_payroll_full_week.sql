-- 043_kpi_payroll_full_week.sql
--
-- Quyết định 11/08/2026, phương án (b): quỹ lương trong KPI tính theo SỐ NGÀY CỦA CẢ TUẦN,
-- không phải số ngày có việc.
--
-- Vì sao đây là thay đổi thật sự chứ không phải chỉnh cho đẹp:
-- Công thức cũ lấy min(ngày bắt đầu) → max(ngày kết thúc) CỦA CÁC VIỆC. Khi thu phạm vi về
-- một tuần (migration 042), nếu tuần kéo dài 01→05/09 mà các việc chỉ nằm ở 02→03/09 thì
-- day_count ra 2 chứ không phải 5, và quỹ lương chỉ tính 2 ngày.
-- Thực tế tổ vẫn được trả lương cho cả tuần, nên cách tính cũ làm chi phí thấp hơn thực tế
-- và KPI trông đẹp hơn sự thật.
--
-- Sau thay đổi này quỹ lương sẽ TĂNG với mọi tuần mà số ngày có việc ít hơn số ngày của tuần,
-- và sẽ có thêm tổ rơi vào "KHÔNG ĐẠT KPI". Đó là kết quả đúng, không phải lỗi.
--
-- Các phần khác giữ nguyên: sản lượng, chênh lệch, ngưỡng đánh giá, cổng an toàn,
-- và quy tắc bỏ việc chưa gộp tuần ra khỏi KPI.

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

  -- Cổng an toàn: có việc thiếu đơn giá hoặc tổ chưa xác định đủ Hệ/Bậc thì BÁO LỖI cả màn
  -- hình chứ không âm thầm bỏ tổ đó ra khỏi bảng. Giấu đi thì người quản lý không biết là
  -- bảng đang thiếu tổ, còn tệ hơn không có số.
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
    -- Chỉ việc ĐÃ gộp vào một tuần. Việc chưa gộp bị loại khỏi KPI.
    select jp.* from app.v_job_production jp
    where jp.week_id is not null
      and (p_week_slot is null or jp.week_slot = p_week_slot)
  ), job_totals as (
    select s.team_id, s.week_id, s.week_slot,
           sum(s.production_value) filter (where s.job_ok)::numeric as total_production
    from scoped s
    group by s.team_id, s.week_id, s.week_slot
  ), amounts as (
    select jt.team_id, jt.week_slot,
           t.leader_name as team_name,
           -- Kỳ đánh giá là CẢ TUẦN, lấy từ chính bản ghi tuần của tổ,
           -- không suy ra từ ngày của các việc nữa.
           w.start_date, w.end_date,
           (w.end_date - w.start_date + 1)::int as day_count,
           (coalesce(tp.daily_payroll,0) * (w.end_date - w.start_date + 1))::numeric as total_payroll,
           coalesce(jt.total_production,0)::numeric as total_production
    from job_totals jt
    join public.work_weeks w on w.id = jt.week_id
    join public.teams t on t.id = jt.team_id and t.is_active
    left join app.v_team_payroll tp on tp.team_id = jt.team_id
  )
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
