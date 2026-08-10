-- =====================================================================
-- 002_tables.sql  ·  KPI MEP → Supabase (Phase 2 DESIGN ONLY)
-- Tạo bảng gốc (base tables). Cột công thức = View (Phase 4/7), KHÔNG ở đây.
-- Quy ước:
--   * PK = UUID gen_random_uuid()
--   * Tiền numeric(15,2); lương ngày numeric(18,4); khối lượng numeric(18,4)
--   * Audit: created_at/updated_at/created_by/updated_by
--   * Soft-delete: deleted_at (dữ liệu có lịch sử); is_active (danh mục)
--   * RLS: BẬT ngay (deny mặc định); policy ở 008_rls.sql (Phase 8)
-- FK/UNIQUE/CHECK đặt ở 003_constraints.sql; INDEX ở 004_indexes.sql.
-- Idempotent: CREATE TABLE IF NOT EXISTS.
-- =====================================================================

-- ------------------------------------------------------------------
-- A. DANH MỤC / THAM CHIẾU
-- ------------------------------------------------------------------

-- A1. Hệ kỹ thuật (nguồn: BANG_LUONG_CHUAN cột A distinct: Tổ PCCC/Nước/Điện/HVAC/HÀN)
create table if not exists public.systems (
  id           uuid primary key default gen_random_uuid(),
  code         text not null,                 -- slug không dấu, vd 'PCCC','NUOC','DIEN','HVAC','HAN'
  name         text not null,                 -- nhãn hiển thị, vd 'Tổ PCCC'
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  created_by   uuid,
  updated_by   uuid
);
comment on table public.systems is 'Hệ kỹ thuật (Tổ PCCC/Nước/Điện/HVAC/HÀN). Nguồn: BANG_LUONG_CHUAN.A';

-- A2. Chức danh/bậc (nguồn: BANG_LUONG_CHUAN cột B: Tổ trưởng 1/2, Thợ bậc 1/2/3, Thợ phụ)
create table if not exists public.salary_grades (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,                 -- 'Tổ trưởng 1','Thợ bậc 1',...
  rank         int,                           -- thứ tự sắp xếp (tùy chọn)
  is_leader    boolean not null default false,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  created_by   uuid,
  updated_by   uuid
);
comment on table public.salary_grades is 'Chức danh/bậc lương. Nguồn: BANG_LUONG_CHUAN.B';

-- A3. Bảng lương chuẩn (nguồn: BANG_LUONG_CHUAN). Khóa nghiệp vụ = Hệ‡Chức danh
create table if not exists public.salary_standards (
  id             uuid primary key default gen_random_uuid(),
  system_id      uuid not null,
  grade_id       uuid not null,
  monthly_salary numeric(15,2) not null,      -- C (lương tháng)
  daily_salary   numeric(18,4) generated always as (monthly_salary / 26) stored, -- D = C/26
  source_row     int,                         -- dòng nguồn (truy vết)
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  created_by     uuid,
  updated_by     uuid
);
comment on table public.salary_standards is 'Lương chuẩn theo Hệ‡Chức danh. Lương ngày = tháng/26 (DD-06).';

-- A4. Hạng mục Cấp 1 (nguồn: DANH_MUC_HANGMUC_CV, 44 dòng)
create table if not exists public.work_categories (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,                -- A: 'CTN CAO TẦNG'
  defined_name  text,                         -- B: named range (có dấu) — truy vết
  work_count    int,                          -- C: số lượng công việc
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  created_by    uuid,
  updated_by    uuid
);
comment on table public.work_categories is 'Hạng mục Cấp 1. Nguồn: DANH_MUC_HANGMUC_CV.';

-- A5. Đơn giá (nguồn: DON_GIA_ĐƠN VỊ THI CÔNG ~8902 dòng). Khóa tra = category_name‡content
create table if not exists public.price_items (
  id             uuid primary key default gen_random_uuid(),
  work_code      text,                         -- A: mã công việc (không unique)
  category_id    uuid,                         -- FK work_categories (khớp theo tên; có thể null nếu chưa map)
  category_name  text not null,                -- G: nhóm cấp 1 (giữ nguyên để dựng khóa)
  content        text not null,                -- B: nội dung (cấp 2)
  tech_desc      text,                         -- C: mô tả kỹ thuật
  unit           text,                         -- D: đơn vị
  approved_price numeric(15,2),                -- E: đơn giá đã duyệt (tham khảo)
  calc_price     numeric(15,2),                -- F: đơn giá +30% (DÙNG TÍNH TOÁN)
  lookup_key     text generated always as (category_name || '‡' || content) stored, -- = H
  is_special     boolean not null default false, -- true cho 'Đào tạo'/'Phát sinh'
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  created_by     uuid,
  updated_by     uuid
);
comment on table public.price_items is 'Đơn giá nhân công. lookup_key = category_name‡content (như DON_GIA.H).';

-- ------------------------------------------------------------------
-- B. TỔ CHỨC / NHÂN SỰ
-- ------------------------------------------------------------------

-- B1. Tổ (nguồn: DANH_MUC_TO). team_id UUID; team_code unique; tên tổ trưởng là thuộc tính (DD-02)
create table if not exists public.teams (
  id                uuid primary key default gen_random_uuid(),
  team_code         text not null,             -- mã nghiệp vụ ổn định (sinh ở Phase 3)
  leader_name       text not null,             -- E: tên tổ trưởng (thuộc tính, KHÔNG làm khóa)
  legacy_team_name  text,                      -- tên tổ gốc từ Sheet (truy vết mapping)
  stt               int,                       -- D: STT gốc
  system_id         uuid,                      -- Hệ của tổ (nếu cấu hình)
  is_active         boolean not null default false, -- có mặt ở DANH_MUC_TO!B?
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        uuid,
  updated_by        uuid,
  deleted_at        timestamptz               -- xóa mềm
);
comment on table public.teams is 'Tổ đội. Định danh bằng team_id/team_code, KHÔNG dùng tên (DD-02).';

-- B2. Công nhân CNCH (nguồn: DANH_SACH_CONG_NHAN ~1808). Khóa nghiệp vụ = MNV
create table if not exists public.workers (
  id                 uuid primary key default gen_random_uuid(),
  mnv                text not null,            -- A: mã nhân viên (unique)
  full_name          text not null,            -- B
  job_title          text,                     -- C: chức vụ gốc
  team_id            uuid,                      -- D → team (map theo tên khi migrate)
  stt_in_team        int,                      -- E
  legacy_lookup_key  text,                     -- F: khóa tra cứu cũ (mojibake) — giữ truy vết (DD-05)
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  created_by         uuid,
  updated_by         uuid,
  deleted_at         timestamptz
);
comment on table public.workers is 'Công nhân cơ hữu (CNCH). Khóa nghiệp vụ = mnv. legacy_lookup_key giữ để truy vết (DD-05).';

-- ------------------------------------------------------------------
-- C. NGHIỆP VỤ: GIAO VIỆC & PHÂN CÔNG
-- ------------------------------------------------------------------

-- C1. Giao việc (nguồn: GIAO_VIEC_HOA_VON — CHỈ cột nhập A:M + Y). Cột N..AE = View.
create table if not exists public.jobs (
  id             uuid primary key default gen_random_uuid(),
  team_id        uuid not null,                -- B
  start_date     date not null,                -- C
  end_date       date not null,                -- D
  category_name  text not null,                -- E: hạng mục Cấp 1
  content        text not null,                -- F: hạng mục Cấp 2
  location       text,                         -- G: vị trí thi công
  quantity       numeric(18,4) not null,       -- H: tổng khối lượng yêu cầu
  count_leader   int not null default 0,       -- I
  count_worker1  int not null default 0,       -- J
  count_worker2  int not null default 0,       -- K
  count_worker3  int not null default 0,       -- L
  count_helper   int not null default 0,       -- M
  group_code     text,                         -- Y: mã nhóm MN-YYYYMMDD-NN (nullable)
  is_special_labor boolean not null default false, -- 'Đào tạo'/'Phát sinh'
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  created_by     uuid,
  updated_by     uuid,
  deleted_at     timestamptz                   -- xóa mềm (= clear ở Sheet)
);
comment on table public.jobs is 'Giao việc (cột nhập). Sản lượng/hòa vốn = v_job_breakeven (Phase 7).';

-- C2. Phân công CNCH (nguồn: PHAN_CONG_CNCH). 1 công nhân / 1 phân công hiện hành / tổ
create table if not exists public.assignments (
  id             uuid primary key default gen_random_uuid(),
  team_id        uuid not null,
  worker_id      uuid not null,                -- MNV
  job_id         uuid,                          -- null = OFF (nghỉ/không giao việc)
  content_label  text,                          -- Nội dung công việc (nhãn snapshot)
  target         text,                          -- Mục tiêu hoàn thành (<=100 ký tự)
  completed_qty  text,                          -- Khối lượng hoàn thành (<=100 ký tự, lưu dạng text như Sheet)
  updated_by     uuid,
  updated_at     timestamptz not null default now(),
  created_at     timestamptz not null default now(),
  created_by     uuid
);
comment on table public.assignments is 'Phân công CNCH theo tổ. job_id null = OFF. Nguồn: PHAN_CONG_CNCH.';

-- ------------------------------------------------------------------
-- D. LƯU TRỮ / LOG (denormalized snapshot — giữ nguyên lịch sử)
-- ------------------------------------------------------------------

-- D1. Lịch sử giao việc (nguồn: LICH_SU_GIAO_VIEC)
create table if not exists public.job_history (
  id             uuid primary key default gen_random_uuid(),
  batch_label    text,                          -- Tuần/Đợt
  archived_at    timestamptz not null default now(),
  team_id        uuid,                          -- best-effort map
  team_name      text,                          -- tên tổ tại thời điểm lưu (snapshot)
  stt            int,
  start_date     date,
  end_date       date,
  category_name  text,
  content        text,
  location       text,
  quantity       numeric(18,4),
  count_leader   int,
  count_worker1  int,
  count_worker2  int,
  count_worker3  int,
  count_helper   int,
  unit           text,
  unit_price     numeric(15,2),
  work_days      int,
  payroll        numeric(18,2),
  breakeven_qty  numeric(18,4),
  daily_qty      numeric(18,4),
  difference     numeric(18,2),
  evaluation     text,
  group_code     text,
  created_at     timestamptz not null default now()
);
comment on table public.job_history is 'Lưu trữ giao việc theo tuần/đợt (snapshot). Nguồn: LICH_SU_GIAO_VIEC.';

-- D2. Lịch sử in PGV (nguồn: LUU_TRU_PGV)
create table if not exists public.pgv_print_log (
  id             uuid primary key default gen_random_uuid(),
  printed_at     timestamptz not null default now(),
  team_id        uuid,
  team_name      text,
  receiver       text,                          -- Bên nhận việc
  worker_count   text,                          -- Số CN (lưu text như Sheet)
  assign_date    date,                          -- Ngày giao
  receive_date   date,                          -- Ngày nhận
  job_stt        int,
  zone           text,                          -- Phân khu
  content        text,                          -- Nội dung công việc
  worker_qty     int,                           -- Số lượng CN
  target         text,                          -- Mục tiêu hoàn thành
  start_date     date,
  end_date       date,
  group_code     text,
  created_at     timestamptz not null default now()
);
comment on table public.pgv_print_log is 'Lịch sử in phiếu PGV. Nguồn: LUU_TRU_PGV.';

-- ------------------------------------------------------------------
-- E. XÁC THỰC / VAI TRÒ (skeleton; profiles + binding auth.users ở Phase 8)
-- ------------------------------------------------------------------

-- E1. Vai trò (mở rộng được; KHÔNG hardcode level trong policy — DD-03)
create table if not exists public.roles (
  code         text primary key,               -- 'ADMIN','GIAM_SAT','TO_TRUONG','XEM'
  label        text not null,
  level        int not null,                   -- 4/3/2/1 (mở rộng sau)
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
comment on table public.roles is 'Danh mục vai trò (mở rộng được). Nguồn: AuthManager.ROLES. profiles/RLS ở Phase 8.';

-- ------------------------------------------------------------------
-- F. BẬT RLS (deny mặc định) — policy thật ở 008_rls.sql (Phase 8)
-- ------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'systems','salary_grades','salary_standards','work_categories','price_items',
    'teams','workers','jobs','assignments','job_history','pgv_print_log','roles'
  ] loop
    -- ENABLE (deny mặc định cho anon/authenticated khi chưa có policy).
    -- FORCE để dành Phase 8 (008_rls.sql) sau khi seed xong, tránh chặn migration/seed.
    execute format('alter table public.%I enable row level security;', t);
  end loop;
end $$;
