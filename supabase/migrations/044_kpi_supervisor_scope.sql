-- 044_kpi_supervisor_scope.sql
--
-- Quyết định 11/08/2026: "Giám sát chỉ được coi KPI tổ mình phụ trách thôi."
--
-- Trước đây get_kpi_evaluation chặn thẳng mọi vai trò khác ADMIN, nên giám sát không mở
-- được màn hình KPI. Nay ADMIN xem tất cả, GIAM_SAT chỉ xem các tổ được gán trong
-- profile_teams. Các vai trò còn lại (TO_TRUONG, NHAN_VIEN, XEM) vẫn KHÔNG xem được KPI:
-- bảng này để lộ quỹ lương của tổ, mở rộng thêm phải là quyết định riêng.
--
-- Phạm vi tổ chốt bằng app.can_access_team() rồi đổ vào một mảng uuid TRƯỚC khi truy vấn,
-- theo đúng cách đã dùng ở migration 039. Gọi hàm ngay trong mệnh đề where sẽ chặn bộ tối
-- ưu đẩy điều kiện lọc xuống, và đó chính là nguyên nhân bảng lương từng bị timeout.
--
-- Hai điểm phải giữ đúng, nếu không là sai nghiệp vụ chứ không chỉ sai quyền:
--   * Cổng an toàn cũng phải thu về đúng phạm vi. Nếu không, một tổ thiếu đơn giá ở nơi
--     khác sẽ làm giám sát không xem được KPI tổ mình, mà lại không hiểu vì sao.
--   * Giám sát chưa được gán tổ nào thì trả về BẢNG RỖNG, không phải báo lỗi. Chưa được
--     phân công là chuyện bình thường, không phải sự cố.
--
-- Công thức tính giữ nguyên hoàn toàn so với 043.

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
declare
  v_role text := app.current_role();
  v_allowed uuid[];
begin
  if not app.is_active_profile() or v_role not in ('ADMIN','GIAM_SAT') then
    raise exception 'KPI chỉ dành cho Admin và Giám sát.' using errcode='42501';
  end if;
  if p_week_slot is not null and p_week_slot not between 1 and 4 then
    raise exception 'INVALID_WEEK_SLOT';
  end if;

  -- Chốt phạm vi trước. ADMIN đi qua can_access_team với mọi tổ; GIAM_SAT chỉ qua được
  -- các tổ có trong profile_teams.
  select coalesce(array_agg(t.id), '{}'::uuid[]) into v_allowed
  from public.teams t
  where t.deleted_at is null and t.is_active and app.can_access_team(t.id);

  if array_length(v_allowed, 1) is null then
    return;
  end if;

  -- Cổng an toàn: có việc thiếu đơn giá hoặc tổ chưa xác định đủ Hệ/Bậc thì BÁO LỖI cả
  -- màn hình chứ không âm thầm bỏ tổ đó ra khỏi bảng. Giấu đi thì người quản lý không biết
  -- là bảng đang thiếu tổ, còn tệ hơn không có số.
  if exists (
    select 1
    from app.v_job_production jp
    join public.teams t on t.id = jp.team_id and t.is_active
    left join app.v_team_payroll tp on tp.team_id = jp.team_id
    where jp.team_id = any(v_allowed)
      and jp.week_id is not null
      and (p_week_slot is null or jp.week_slot = p_week_slot)
      and (coalesce(tp.unknown_salary_count,1) > 0 or not jp.job_ok or jp.production_value is null)
  ) then
    raise exception 'KPI compute guard failed: incomplete salary or job pricing. Tổ: %',
      (select string_agg(distinct t.leader_name, ', ')
         from app.v_job_production jp
         join public.teams t on t.id = jp.team_id and t.is_active
         left join app.v_team_payroll tp on tp.team_id = jp.team_id
        where jp.team_id = any(v_allowed)
          and jp.week_id is not null
          and (p_week_slot is null or jp.week_slot = p_week_slot)
          and (coalesce(tp.unknown_salary_count,1) > 0 or not jp.job_ok or jp.production_value is null))
      using errcode='P0001';
  end if;

  return query
  with scoped as (
    -- Chỉ việc ĐÃ gộp vào một tuần, và chỉ trong phạm vi tổ được phép.
    select jp.* from app.v_job_production jp
    where jp.team_id = any(v_allowed)
      and jp.week_id is not null
      and (p_week_slot is null or jp.week_slot = p_week_slot)
  ), job_totals as (
    select s.team_id, s.week_id, s.week_slot,
           sum(s.production_value) filter (where s.job_ok)::numeric as total_production
    from scoped s
    group by s.team_id, s.week_id, s.week_slot
  ), amounts as (
    select jt.team_id, jt.week_slot,
           t.leader_name as team_name,
           -- Kỳ đánh giá là CẢ TUẦN, lấy từ chính bản ghi tuần của tổ (migration 043).
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
