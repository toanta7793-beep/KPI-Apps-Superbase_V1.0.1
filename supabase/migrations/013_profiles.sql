-- =====================================================================
-- 013_profiles.sql · Phase 8A Identity Model — bảng public.profiles.
-- Liên kết: auth.users → profiles → workers → teams → roles.
-- Business key = MNV (trên workers); worker_id = UUID kỹ thuật. KHÔNG dùng email làm khóa.
-- KHÔNG viết policy (RLS chỉ bật deny; policy ở Phase 8B). KHÔNG sửa migration cũ.
-- Idempotent: create table if not exists + guarded constraints/index.
-- =====================================================================

create table if not exists public.profiles (
  id            uuid primary key default gen_random_uuid(),
  auth_user_id  uuid not null,             -- 1 tài khoản đăng nhập (auth.users)
  worker_id     uuid,                       -- nullable: admin/viewer có thể KHÔNG phải công nhân
  role_code     text not null,              -- FK roles(code) — "role_id" trong mô hình (mã vai trò)
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  created_by    uuid,
  updated_by    uuid
);
comment on table public.profiles is 'Định danh: nối auth.users ↔ workers (MNV) + vai trò. team_id dẫn xuất qua workers.';
comment on column public.profiles.role_code is 'FK roles(code) — mã vai trò ("role_id" theo mô hình). roles dùng code làm khóa.';

-- UNIQUE: mỗi login 1 profile; mỗi worker tối đa 1 login (worker_id null cho phép nhiều).
alter table public.profiles drop constraint if exists uq_profiles_auth_user;
alter table public.profiles add  constraint uq_profiles_auth_user unique (auth_user_id);
alter table public.profiles drop constraint if exists uq_profiles_worker;
alter table public.profiles add  constraint uq_profiles_worker unique (worker_id);

-- FK
alter table public.profiles drop constraint if exists fk_profiles_auth;
alter table public.profiles add  constraint fk_profiles_auth
  foreign key (auth_user_id) references auth.users(id) on delete cascade;
alter table public.profiles drop constraint if exists fk_profiles_worker;
alter table public.profiles add  constraint fk_profiles_worker
  foreign key (worker_id) references public.workers(id) on delete set null;
alter table public.profiles drop constraint if exists fk_profiles_role;
alter table public.profiles add  constraint fk_profiles_role
  foreign key (role_code) references public.roles(code) on delete restrict;

-- Index (FK lookup)
create index if not exists ix_profiles_worker on public.profiles(worker_id);
create index if not exists ix_profiles_role   on public.profiles(role_code);
create index if not exists ix_profiles_active  on public.profiles(is_active) where is_active;

-- updated_at trigger
drop trigger if exists trg_set_updated_at on public.profiles;
create trigger trg_set_updated_at before update on public.profiles
  for each row execute function app.set_updated_at();

-- RLS: bật deny mặc định (KHÔNG policy ở Phase 8A; policy ở 014/Phase 8B).
alter table public.profiles enable row level security;
