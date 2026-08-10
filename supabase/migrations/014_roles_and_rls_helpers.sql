-- =====================================================================
-- 014_roles_and_rls_helpers.sql · Phase 8C-v1
-- (1) Thêm role NHAN_VIEN vào public.roles (KHÔNG sửa migration/seed cũ).
-- (2) Helper phân giải danh tính người gọi cho RLS — FAIL-CLOSED.
-- Nguyên tắc: authorize CHỈ theo role_code; roles.level là metadata hiển thị, KHÔNG dùng để authorize.
-- Helper: SECURITY DEFINER (bắt buộc để phân giải danh tính không đệ quy RLS), search_path cố định = '',
--         không dynamic SQL, chỉ trả giá trị dẫn xuất của CHÍNH người gọi (auth.uid()).
-- =====================================================================

-- (1) Role NHAN_VIEN (idempotent). level=1 chỉ để hiển thị (KHÔNG authorize).
insert into public.roles(code, label, level) values
  ('NHAN_VIEN', 'Nhân viên', 1)
on conflict (code) do nothing;

-- (2) Helpers (schema app đã tồn tại từ 005). Tất cả STABLE + SECURITY DEFINER + search_path=''.

-- Có profile đang hoạt động cho người gọi?
create or replace function app.is_active_profile()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(
    select 1 from public.profiles p
    where p.auth_user_id = auth.uid() and p.is_active = true
  )
$$;

-- role_code của người gọi (NULL nếu không có profile active). KHÔNG phụ thuộc worker.
create or replace function app.current_role()
returns text language sql stable security definer set search_path = '' as $$
  select p.role_code
  from public.profiles p
  where p.auth_user_id = auth.uid() and p.is_active = true
  limit 1
$$;

-- worker_id của người gọi cho phạm vi SELF. NULL nếu: không worker, hoặc worker bị xóa mềm.
create or replace function app.current_worker_id()
returns uuid language sql stable security definer set search_path = '' as $$
  select p.worker_id
  from public.profiles p
  join public.workers w on w.id = p.worker_id
  where p.auth_user_id = auth.uid() and p.is_active = true
    and w.deleted_at is null
  limit 1
$$;

-- team_id của người gọi cho phạm vi TEAM. NULL nếu: không worker/tổ, worker xóa mềm, hoặc TỔ inactive.
create or replace function app.current_team_id()
returns uuid language sql stable security definer set search_path = '' as $$
  select w.team_id
  from public.profiles p
  join public.workers w on w.id = p.worker_id
  join public.teams   t on t.id = w.team_id
  where p.auth_user_id = auth.uid() and p.is_active = true
    and w.deleted_at is null and t.is_active = true
  limit 1
$$;

comment on function app.current_role() is 'role_code người gọi (fail-closed NULL). KHÔNG dùng roles.level để authorize.';
comment on function app.current_team_id() is 'team_id người gọi cho TEAM scope; NULL nếu mất anchor/tổ inactive/worker xóa mềm (deny, không match-all).';

-- Quyền tối thiểu: THU HỒI execute mặc định của PUBLIC (chống anon gọi helper), chỉ cấp authenticated.
revoke execute on function app.is_active_profile() from public;
revoke execute on function app.current_role()      from public;
revoke execute on function app.current_worker_id()  from public;
revoke execute on function app.current_team_id()    from public;
grant usage on schema app to authenticated;
grant execute on function app.is_active_profile() to authenticated;
grant execute on function app.current_role()      to authenticated;
grant execute on function app.current_worker_id()  to authenticated;
grant execute on function app.current_team_id()    to authenticated;
