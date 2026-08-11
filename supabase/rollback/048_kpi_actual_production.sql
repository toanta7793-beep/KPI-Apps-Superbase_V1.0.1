-- HOÀN TÁC 048_kpi_actual_production.sql
--
-- Bỏ cột "Sản lượng thực tế" khỏi KPI, đưa get_kpi_evaluation về bản 044 và
-- get_production_evaluation về bản 046 (tự tính lũy kế, không dùng view chung), rồi bỏ view.
--
-- Không mất dữ liệu: bảng job_daily_production và lịch sử giữ nguyên. Chỉ là KPI thôi không
-- hiển thị sản lượng thực tế nữa.
--
-- Thứ tự quan trọng: phải bỏ hai hàm phụ thuộc TRƯỚC rồi mới bỏ view, nếu không Postgres
-- sẽ từ chối vì còn thứ đang dùng nó.

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

  -- Chốt phạm vi trước rồi mới lọc bằng mảng, không gọi can_access_team trong where.
  -- Gọi trong where sẽ chặn bộ tối ưu đẩy điều kiện xuống — đúng nguyên nhân đã làm bảng
  -- lương timeout ở migration 039.
  select coalesce(array_agg(t.id), '{}'::uuid[]) into v_allowed
  from public.teams t
  where t.deleted_at is null and t.is_active
    and (p_team_id is null or t.id = p_team_id)
    and app.can_access_team(t.id);
  if array_length(v_allowed, 1) is null then return; end if;

  return query
  with scoped as (
    select m.*, w.week_slot
    from app.v_job_metrics m
    join public.work_weeks w on w.id = m.week_id
    where m.team_id = any(v_allowed)
      and (p_week_slot is null or w.week_slot = p_week_slot)
  ), nhap_tay as (
    select d.job_id, sum(d.quantity)::numeric as tong, count(*)::int as so_ngay
    from public.job_daily_production d
    join scoped s on s.id = d.job_id
    group by d.job_id
  ), tinh as (
    select s.*,
           -- Đào tạo / Phát sinh: tự lũy kế theo ngày đã trôi qua, không lấy số nhập tay.
           -- Việc đã kết thúc thì đứng ở 100%, không tăng tiếp.
           case when s.is_special_labor then
             greatest(0, least(current_date, s.end_date) - s.start_date + 1)
           else null end::int as ngay_da_qua,
           coalesce(nt.tong, 0)::numeric as tong_nhap_tay,
           coalesce(nt.so_ngay, 0)::int as so_ngay_nhap
    from scoped s left join nhap_tay nt on nt.job_id = s.id
  ), luy_ke as (
    select t.*,
           case when t.is_special_labor
                then t.quantity * (case when t.work_days > 0
                                        then least(greatest(t.ngay_da_qua,0), t.work_days)::numeric / t.work_days
                                        else 0 end)
                else t.tong_nhap_tay end as kl
    from tinh t
  )
  select l.id, l.team_id, tm.leader_name, l.week_slot::int,
         l.location, l.location, l.content,
         l.quantity, l.unit, l.start_date, l.end_date,
         round(l.kl, 4),
         round(l.kl * coalesce(l.unit_price, 0), 0),
         case when l.quantity > 0 then round(l.kl / l.quantity * 100, 2) else null end,
         l.so_ngay_nhap, l.is_special_labor, l.group_code
  from luy_ke l
  join public.teams tm on tm.id = l.team_id
  order by tm.leader_name, l.start_date, l.content;
end $$;


revoke execute on function public.get_kpi_evaluation(integer) from public, anon;
revoke execute on function public.get_production_evaluation(uuid,integer) from public, anon;
grant  execute on function public.get_kpi_evaluation(integer) to authenticated;
grant  execute on function public.get_production_evaluation(uuid,integer) to authenticated;

drop view if exists app.v_job_actual_production;

notify pgrst, 'reload schema';
