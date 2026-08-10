-- =====================================================================
-- 001_extensions.sql  ·  KPI MEP → Supabase (Phase 2 DESIGN ONLY)
-- Bản thiết kế, quản lý bằng Git. KHÔNG chạy lên production ở Phase 2.
-- Idempotent: dùng CREATE EXTENSION IF NOT EXISTS.
-- =====================================================================

-- UUID: gen_random_uuid() (PostgreSQL >=13 có sẵn; pgcrypto đảm bảo tương thích Supabase)
create extension if not exists pgcrypto;

-- Email so sánh không phân biệt hoa/thường (khớp Security.normalizeEmail)
create extension if not exists citext;

-- Chuẩn hóa tiếng Việt (bỏ dấu) — CHỈ hỗ trợ mapping/đối chiếu khi migrate,
-- không thay đổi dữ liệu gốc. Dùng trong hàm normalize ở Phase 3/4.
create extension if not exists unaccent;

-- (Tùy chọn) moddatetime cho trigger updated_at — Phase 4 có thể dùng thay trigger tự viết.
-- create extension if not exists moddatetime;

-- Ghi chú: RLS được bật ở 002_tables.sql (deny mặc định); policy thật ở 008_rls.sql (Phase 8).
