-- =====================================================================
-- seed.sql · KPI MEP → Supabase (Phase 4 Foundation)
-- Seed DANH MỤC TỐI THIỂU (cấu trúc, KHÔNG chứa PII/số tiền thật).
-- Idempotent: ON CONFLICT DO NOTHING (chạy lại không tạo trùng — test RC/Step5.15).
-- KHÔNG seed: teams/workers/price/salary amounts (dữ liệu thật → import có kiểm soát).
-- =====================================================================

-- Vai trò (AuthManager.ROLES) — DD-03
insert into public.roles (code, label, level) values
  ('ADMIN',    'Quản trị viên', 4),
  ('GIAM_SAT', 'Giám sát',      3),
  ('TO_TRUONG','Tổ trưởng',     2),
  ('XEM',      'Chỉ xem',       1)
on conflict (code) do nothing;

-- Hệ kỹ thuật (BANG_LUONG_CHUAN.A distinct) — gồm Tổ HÀN (DD-06)
insert into public.systems (code, name) values
  ('PCCC', 'Tổ PCCC'),
  ('NUOC', 'Tổ Nước'),
  ('DIEN', 'Tổ Điện'),
  ('HVAC', 'Tổ HVAC'),
  ('HAN',  'Tổ HÀN')
on conflict (code) do nothing;

-- Chức danh/bậc (BANG_LUONG_CHUAN.B distinct)
insert into public.salary_grades (name, is_leader, rank) values
  ('Tổ trưởng 1', true,  1),
  ('Tổ trưởng 2', true,  2),
  ('Thợ bậc 1',   false, 3),
  ('Thợ bậc 2',   false, 4),
  ('Thợ bậc 3',   false, 5),
  ('Thợ phụ',     false, 6)
on conflict (name) do nothing;

-- Ghi chú: salary_standards (số tiền thật), work_categories, price_items, teams, workers
-- KHÔNG seed ở đây — nạp qua quy trình staging/import có kiểm soát (Phase 3/4), giữ dữ liệu thật ngoài Git.
