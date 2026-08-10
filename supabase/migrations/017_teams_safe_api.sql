-- =====================================================================
-- 017_teams_safe_api.sql · Phase 9C — RPC teams-safe cho đường public đọc danh mục Tổ.
-- Bảng public.teams có RLS v1 (TO authenticated; anon deny) ⇒ đọc qua RPC SECURITY DEFINER.
-- R9C-01 (a): cho phép anon + authenticated EXECUTE (phạm vi pilot).
-- Allowlist đầu ra TỐI THIỂU: team_name, is_active (đúng những gì getDanhMucTo dùng).
--   TUYỆT ĐỐI KHÔNG trả id/team_id/leader_id/worker_id/email/phone/salary/system_id/stt/audit/note.
--   (team_name = teams.leader_name, chỉ coi là NHÃN hiển thị của tổ — không tạo trường leader_name.)
-- Bảo mật: search_path='' cố định, fully-qualified, KHÔNG dynamic SQL, revoke execute from public,
--   grant chỉ anon+authenticated, KHÔNG grant base-table cho anon, KHÔNG policy mới trên teams, KHÔNG service_role.
-- Trả CẢ tổ active lẫn inactive (kèm is_active) để app suy ra active (B) vs master (E) — R9C-05.
-- =====================================================================

-- Đổi chữ ký (bỏ team_id) ⇒ drop trước khi tạo (create-or-replace không đổi được return type).
drop function if exists public.get_teams_catalog();

create function public.get_teams_catalog()
returns table (team_name text, is_active boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select t.leader_name, t.is_active
  from public.teams t
  where coalesce(btrim(t.leader_name), '') <> ''
  order by t.leader_name, t.id   -- t.id chỉ dùng để sắp xếp ổn định (KHÔNG trả ra)
$$;

comment on function public.get_teams_catalog() is
  'Teams-safe: danh mục tổ (team_name=nhãn, is_active). Allowlist tối thiểu — KHÔNG trả ID/khóa ngoài/PII/số liệu nhạy cảm.';

revoke execute on function public.get_teams_catalog() from public;
grant  execute on function public.get_teams_catalog() to anon, authenticated;

notify pgrst, 'reload schema';
