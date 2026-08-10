-- =====================================================================
-- 010_staging.sql · KPI MEP → Supabase (Phase 4 - migration tooling)
-- Schema STAGING: nạp nguyên trạng, KHÔNG UNIQUE (cho phép trùng để lập báo cáo - DD-09).
-- Đặt ngoài schema 'public' => KHÔNG expose qua PostgREST (an toàn, không cần RLS).
-- Idempotent.
-- =====================================================================

create schema if not exists staging;

create table if not exists staging.stg_teams (
  source_row int, legacy_stt text, legacy_team_name text,
  normalized_team_name text, is_active_raw text,
  validation_status text, validation_note text, loaded_at timestamptz default now()
);

create table if not exists staging.stg_workers (
  source_row int, mnv_raw text, full_name_raw text, job_title_raw text,
  team_name_raw text, stt_in_team_raw text, legacy_lookup_key text,
  normalized_mnv text, normalized_team_name text,
  validation_status text, validation_note text, loaded_at timestamptz default now()
);

-- Đơn giá — KHÔNG UNIQUE (DD-09)
create table if not exists staging.stg_price_items (
  source_row int, work_code text, category_name_raw text, content_raw text,
  unit text, approved_price numeric, calc_price numeric, tech_desc text,
  normalized_category_name text, normalized_content text,
  duplicate_group text, duplicate_type text,
  validation_status text, validation_note text, loaded_at timestamptz default now()
);

create table if not exists staging.stg_salary_standards (
  source_row int, system_raw text, grade_raw text, monthly_raw text,
  normalized_system text, normalized_grade text,
  validation_status text, validation_note text, loaded_at timestamptz default now()
);

create table if not exists staging.stg_work_categories (
  source_row int, name_raw text, defined_name text, work_count_raw text,
  normalized_name text, validation_status text, validation_note text, loaded_at timestamptz default now()
);

-- User metadata (KHÔNG hash/secret — DD-17)
create table if not exists staging.stg_user_metadata (
  source_row int, email_raw text, full_name_raw text, role_raw text,
  team_scope_raw text, is_active_raw text, legacy_user_reference text,
  normalized_email text, validation_status text, validation_note text, loaded_at timestamptz default now()
);

comment on schema staging is 'Lớp staging migration (không UNIQUE, không expose API). Xóa được sau cutover.';
