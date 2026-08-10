-- =====================================================================
-- 019_staging_deploy_marker.sql · Marker môi trường cho guard import staging.
-- Thay cho custom GUC app.deploy_target (remote cấm ALTER DATABASE ... SET -> ERROR 42501).
-- CHỈ tạo schema/table (structure). KHÔNG insert staging row ở migration (tránh marker "đi" production
--   khi db push) — row staging đặt THỦ CÔNG chỉ trên staging (xem STAGING_SEED_RUNBOOK).
-- Schema nội bộ: KHÔNG exposed (không thêm vào PostgREST schemas), KHÔNG grant anon/authenticated.
-- =====================================================================
create schema if not exists app_internal;

create table if not exists app_internal.deploy_target (
  project_ref text primary key,
  environment text not null,
  created_at  timestamptz not null default now()
);

comment on schema app_internal is 'Nội bộ deploy/ops. KHÔNG expose qua PostgREST. KHÔNG grant anon/authenticated.';
comment on table  app_internal.deploy_target is 'Marker môi trường cho guard import staging (project_ref + environment). Row staging đặt thủ công, KHÔNG qua migration.';

-- Least privilege: thu hồi mọi quyền của public/anon/authenticated (chỉ owner/postgres dùng).
revoke all on schema app_internal from public;
revoke all on schema app_internal from anon, authenticated;
revoke all on all tables in schema app_internal from public;
revoke all on all tables in schema app_internal from anon, authenticated;

-- Defense-in-depth: bật RLS (không policy). Owner/postgres (guard) bypass; anon/authenticated không tới được.
alter table app_internal.deploy_target enable row level security;
