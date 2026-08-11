-- 049_production_entry_state.sql
--
-- Phần 2 bước 4: giao diện cần biết ô nhập của MỘT NGÀY cụ thể đang thế nào — đã có số
-- chưa, có đang khóa không. Không có thông tin đó thì màn hình phải gọi thêm một vòng nữa
-- cho mỗi dòng, hoặc tệ hơn là đoán.
--
-- Thêm tham số p_work_date và ba cột trạng thái. Bỏ trống tham số thì hàm chạy y như trước,
-- ba cột mới trả về rỗng — nên phần đang gọi cũ không vỡ.
--
-- o_nhap_co_ton_tai tách bạch "chưa nhập" với "nhập số 0". Hai chuyện đó khác hẳn nhau mà
-- nếu chỉ nhìn khối lượng thì trông giống hệt.

drop function if exists public.get_production_evaluation(uuid,integer);

create function public.get_production_evaluation(
  p_team_id uuid default null, p_week_slot integer default null, p_work_date date default null
) returns table (
  job_id uuid, team_id uuid, team_name text, week_slot int,
  phan_khu text, vi_tri_chi_tiet text, noi_dung text,
  muc_tieu numeric, don_vi text, start_date date, end_date date,
  luy_ke_khoi_luong numeric, luy_ke_thanh_tien numeric, luy_ke_phan_tram numeric,
  so_ngay_da_nhap int, tu_dong boolean, group_code text,
  o_nhap_khoi_luong numeric, o_nhap_da_khoa boolean, o_nhap_co_ton_tai boolean
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
         a.so_ngay_da_nhap, m.is_special_labor, m.group_code,
         e.quantity, coalesce(e.is_locked, false), (e.job_id is not null)
  from app.v_job_metrics m
  join app.v_job_actual_production a on a.job_id = m.id
  join public.work_weeks w on w.id = m.week_id
  join public.teams tm on tm.id = m.team_id
  left join public.job_daily_production e on e.job_id = m.id and p_work_date is not null and e.work_date = p_work_date
  where m.team_id = any(v_allowed)
    and (p_week_slot is null or w.week_slot = p_week_slot)
  order by tm.leader_name, m.start_date, m.content;
end $$;


revoke execute on function public.get_production_evaluation(uuid,integer,date) from public, anon;
grant  execute on function public.get_production_evaluation(uuid,integer,date) to authenticated;
notify pgrst, 'reload schema';
