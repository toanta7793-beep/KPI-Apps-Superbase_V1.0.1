-- =====================================================================
-- 005_functions.sql · KPI MEP → Supabase (Phase 4 Foundation)
-- Hàm tiện ích: updated_at, sinh team_code, chuẩn hóa VN (chỉ để so khớp).
-- Idempotent: create schema/or replace function.
-- =====================================================================

create schema if not exists app;  -- chứa hàm nội bộ; RLS helper thêm ở Phase 8

-- Trigger function: cập nhật updated_at khi UPDATE
create or replace function app.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Sinh team_code theo DD-08: T-<STT 3 chữ số>. STT không hợp lệ → NULL (gọi bên ngoài xử lý PENDING).
create or replace function app.gen_team_code(p_stt int)
returns text
language sql
immutable
as $$
  select case
           when p_stt is null or p_stt < 0 then null
           else 'T-' || lpad(p_stt::text, 3, '0')
         end;
$$;

-- Chuẩn hóa chuỗi tiếng Việt CHỈ để so khớp/mapping (DD-18.4) — KHÔNG dùng để ghi đè dữ liệu gốc.
-- search_path gồm extensions vì Supabase cài unaccent trong schema 'extensions'.
create or replace function app.norm_vn(p text)
returns text
language sql
stable
set search_path = public, extensions
as $$
  select btrim(regexp_replace(lower(unaccent(coalesce(p, ''))), '\s+', ' ', 'g'));
$$;

comment on function app.set_updated_at() is 'Trigger BEFORE UPDATE: set updated_at = now()';
comment on function app.gen_team_code(int) is 'DD-08: sinh team_code T-000; NULL nếu STT không hợp lệ';
comment on function app.norm_vn(text) is 'Chuẩn hóa VN (unaccent+lower+trim) CHỈ để so khớp, không đổi dữ liệu gốc';
