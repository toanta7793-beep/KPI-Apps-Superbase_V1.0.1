-- =====================================================================
-- 020_seed_base_roles.sql · Ensure the base application roles exist.
--
-- Remote environments receive migrations but do not automatically run
-- supabase/seed.sql. Profiles reference roles(code), so the first ADMIN
-- profile cannot be provisioned unless these rows are migration-managed.
--
-- Idempotent and non-destructive: preserve any existing role metadata.
-- =====================================================================

insert into public.roles (code, label, level) values
  ('ADMIN',     'Quản trị viên', 4),
  ('GIAM_SAT',  'Giám sát',      3),
  ('TO_TRUONG', 'Tổ trưởng',     2),
  ('XEM',       'Chỉ xem',       1)
on conflict (code) do nothing;

