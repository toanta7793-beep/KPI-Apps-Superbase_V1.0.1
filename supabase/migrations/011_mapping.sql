-- =====================================================================
-- 011_mapping.sql · KPI MEP → Supabase (Phase 4 - migration tooling)
-- Schema MAPPING: nguồn sự thật của UUID (retry ổn định - DD-18.5).
-- Khóa tự nhiên UNIQUE => insert lại KHÔNG sinh UUID mới (ON CONFLICT DO NOTHING).
-- Ngoài 'public' => không expose API.
-- =====================================================================

create schema if not exists mapping;

-- Danh mục: khóa = normalized name (ổn định)
create table if not exists mapping.map_systems (
  normalized_system text primary key,
  system_code text,
  system_id uuid not null default gen_random_uuid()
);
create table if not exists mapping.map_grades (
  normalized_grade text primary key,
  grade_id uuid not null default gen_random_uuid()
);
create table if not exists mapping.map_categories (
  normalized_name text primary key,
  category_id uuid not null default gen_random_uuid()
);

-- Tổ: khóa ổn định = source_row (mỗi dòng nguồn = 1 team_id). Tên trùng KHÔNG gộp (DD-02/DD-08).
create table if not exists mapping.map_teams (
  source_row int primary key,
  legacy_stt text,
  legacy_team_name text,
  normalized_team_name text,
  team_code text,                 -- T-<stt> hoặc PENDING-<source_row>
  team_id uuid not null default gen_random_uuid(),
  mapping_status text not null default 'NEW',   -- NEW/MATCHED/PENDING/CONFLICT/REJECTED
  mapping_note text
);

-- Công nhân: khóa nghiệp vụ = mnv
create table if not exists mapping.map_workers (
  mnv text primary key,
  source_row int,
  legacy_team_name text,
  team_code text,
  worker_id uuid not null default gen_random_uuid(),
  mapping_status text not null default 'NEW',
  mapping_note text
);

-- Đơn giá: khóa ổn định = source_row (dữ liệu nguồn có thể trùng khóa nghiệp vụ)
create table if not exists mapping.map_price_items (
  source_row int primary key,
  lookup_key text,
  price_item_id uuid not null default gen_random_uuid(),
  duplicate_type text,
  mapping_status text not null default 'NEW'
);

-- User: khóa = normalized email (metadata, KHÔNG hash - DD-17)
create table if not exists mapping.map_users (
  normalized_email text primary key,
  legacy_user_reference text,
  profile_placeholder_id uuid not null default gen_random_uuid(),
  mapping_status text not null default 'NEW'
);

comment on schema mapping is 'Bảng ánh xạ mã cũ→UUID, bền vững để retry ổn định (DD-18.5).';
