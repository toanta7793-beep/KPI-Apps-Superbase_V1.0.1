-- 048_kpi_actual_production.sql
--
-- Phần 2 bước 3: cột "Sản lượng thực tế" trong màn Đánh giá KPI.
--
-- Công thức lũy kế giờ có HAI nơi cần dùng: bảng Đánh giá sản lượng và cột mới trong KPI.
-- Chép công thức sang nơi thứ hai là cách chắc chắn nhất để hai màn hình lệch nhau sau vài
-- lần sửa — đúng chuyện vừa xảy ra với quy tắc "cùng vị trí" nằm ở ba nơi. Nên tách hẳn ra
-- một view dùng chung, và cả hai hàm cùng đọc từ đó.
--
-- get_production_evaluation viết lại chỉ để đổi nguồn số liệu; kết quả không đổi.
-- get_kpi_evaluation giữ nguyên từng phép tính cũ, chỉ THÊM hai cột ở cuối.

-- ---------------------------------------------------------------------------------------
-- Lũy kế của từng việc. Một nơi duy nhất định nghĩa "làm được bao nhiêu".
-- ---------------------------------------------------------------------------------------
create or replace view app.v_job_actual_production as
select m.id as job_id,
       m.team_id,
       m.week_id,
       m.is_special_labor,
       -- Đào tạo / Phát sinh tự lũy kế theo ngày đã trôi qua, không có số nhập tay.
       -- Việc đã kết thúc thì đứng lại, không tăng tiếp.
       case when m.is_special_labor then
              m.quantity * (case when m.work_days > 0
                                 then least(greatest(greatest(0, least(current_date, m.end_date) - m.start_date + 1), 0), m.work_days)::numeric / m.work_days
                                 else 0 end)
            else coalesce(d.tong, 0) end::numeric as luy_ke_khoi_luong,
       coalesce(d.so_ngay, 0)::int as so_ngay_da_nhap
from app.v_job_metrics m
left join (
  select job_id, sum(quantity)::numeric as tong, count(*)::int as so_ngay
  from public.job_daily_production group by job_id
) d on d.job_id = m.id;

-- ---------------------------------------------------------------------------------------
-- Bảng Đánh giá sản lượng — nay đọc lũy kế từ view chung.
-- ---------------------------------------------------------------------------------------
create or replace function public.get_production_evaluation(
  p_team_id uuid default null, p_week_slot integer default null
) returns table (
  job_id uuid, team_id uuid, team_name text, week_slot int,
  phan_khu text, vi_tri_chi_tiet text, noi_dung text,
  muc_tieu numeric, don_vi text, start_date date, end_date date,
  luy_ke_khoi_luong numeric, luy_ke_thanh_tien numeric, luy_ke_phan_tram numeric,
  so_ngay_da_nhap int, tu_dong boolean, group_code text
)
language plpgsql stable security definer set search_path = '' as $$
declare v_allowed uuid[];
begin
  if not app.is_active_profile() or app.current_role() not in ('ADMIN','GIAM_SAT','TO_TRUONG') then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if p_week_slot is not null and p_week_slot not between 1 and 4 then
    raise exception 'INVALID_WEEK_SLOT';
  end if;

  select coalesce(array_agg(t.id), '{}'::uuid[]) into v_allowed
  from public.teams t
  where t.deleted_at is null and t.is_active
    and (p_team_id is null or t.id = p_team_id)
    and app.can_access_team(t.id);
  if array_length(v_allowed, 1) is null then return; end if;

  return query
  select m.id, m.team_id, tm.leader_name, w.week_slot::int,
         m.location, m.location, m.content,
         m.quantity, m.unit, m.start_date, m.end_date,
         round(a.luy_ke_khoi_luong, 4),
         round(a.luy_ke_khoi_luong * coalesce(m.unit_price, 0), 0),
         case when m.quantity > 0 then round(a.luy_ke_khoi_luong / m.quantity * 100, 2) else null end,
         a.so_ngay_da_nhap, m.is_special_labor, m.group_code
  from app.v_job_metrics m
  join app.v_job_actual_production a on a.job_id = m.id
  join public.work_weeks w on w.id = m.week_id
  join public.teams tm on tm.id = m.team_id
  where m.team_id = any(v_allowed)
    and (p_week_slot is null or w.week_slot = p_week_slot)
  order by tm.leader_name, m.start_date, m.content;
end $$;

-- ---------------------------------------------------------------------------------------
-- KPI: thêm "Sản lượng thực tế" và chênh lệch của nó so với sản lượng kế hoạch.
--
-- Đây là thước đo THỨ HAI, độc lập với chỉ báo lãi/lỗ cũ:
--   * difference_vnd  = sản lượng kế hoạch − quỹ lương  → có lãi không
--   * actual_vs_plan  = sản lượng thực tế − sản lượng kế hoạch → làm được bao nhiêu so với giao
-- Không trộn hai cái vào nhau. Một tổ có thể lãi mà vẫn chậm tiến độ, và ngược lại.
-- ---------------------------------------------------------------------------------------
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
  evaluation text,
  actual_production numeric,
  actual_vs_plan numeric,
  production_rows_entered int
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

  select coalesce(array_agg(t.id), '{}'::uuid[]) into v_allowed
  from public.teams t
  where t.deleted_at is null and t.is_active and app.can_access_team(t.id);
  if array_length(v_allowed, 1) is null then return; end if;

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
    select jp.* from app.v_job_production jp
    where jp.team_id = any(v_allowed)
      and jp.week_id is not null
      and (p_week_slot is null or jp.week_slot = p_week_slot)
  ), job_totals as (
    select s.team_id, s.week_id, s.week_slot,
           sum(s.production_value) filter (where s.job_ok)::numeric as total_production
    from scoped s
    group by s.team_id, s.week_id, s.week_slot
  ), actual as (
    -- Tổng lũy kế THÀNH TIỀN của tuần, và số dòng đã thực sự có người nhập.
    -- Số dòng đó để giao diện phân biệt "chưa ai nhập" với "làm được 0 đồng" — hai chuyện
    -- khác hẳn nhau mà nếu chỉ nhìn số tiền thì trông giống hệt.
    select m.team_id, m.week_id,
           sum(a.luy_ke_khoi_luong * coalesce(m.unit_price,0))::numeric as tien,
           sum(case when a.so_ngay_da_nhap > 0 or m.is_special_labor then 1 else 0 end)::int as so_dong
    from app.v_job_actual_production a
    join app.v_job_metrics m on m.id = a.job_id
    where m.team_id = any(v_allowed) and m.week_id is not null
    group by m.team_id, m.week_id
  ), amounts as (
    select jt.team_id, jt.week_slot,
           t.leader_name as team_name,
           w.start_date, w.end_date,
           (w.end_date - w.start_date + 1)::int as day_count,
           (coalesce(tp.daily_payroll,0) * (w.end_date - w.start_date + 1))::numeric as total_payroll,
           coalesce(jt.total_production,0)::numeric as total_production,
           coalesce(ac.tien,0)::numeric as actual_production,
           coalesce(ac.so_dong,0)::int as rows_entered
    from job_totals jt
    join public.work_weeks w on w.id = jt.week_id
    join public.teams t on t.id = jt.team_id and t.is_active
    left join app.v_team_payroll tp on tp.team_id = jt.team_id
    left join actual ac on ac.team_id = jt.team_id and ac.week_id = jt.week_id
  )
  select a.week_slot::int, a.team_name, a.start_date, a.end_date, a.day_count,
         a.total_payroll, a.total_production,
         round(a.total_production - a.total_payroll, 0),
         case
           when a.total_payroll <= 0 then 'CHƯA CẤU HÌNH QUỸ LƯƠNG'
           when round(a.total_production - a.total_payroll, 0) < 0 then 'KHÔNG ĐẠT KPI'
           else 'ĐẠT KPI'
         end,
         round(a.actual_production, 0),
         round(a.actual_production - a.total_production, 0),
         a.rows_entered
  from amounts a
  order by a.week_slot, a.team_name;
end $$;

revoke execute on function public.get_kpi_evaluation(integer) from public, anon;
revoke execute on function public.get_production_evaluation(uuid,integer) from public, anon;
grant  execute on function public.get_kpi_evaluation(integer) to authenticated;
grant  execute on function public.get_production_evaluation(uuid,integer) to authenticated;
notify pgrst, 'reload schema';
