\set ON_ERROR_STOP off
\timing off
\pset pager off

-- ============================================================
-- UAT cục bộ cho migration 032/033. Toàn bộ dữ liệu là GIẢ ĐỊNH.
-- ============================================================

-- Admin giả lập
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111','authenticated','authenticated','uat-admin@local.test','x',now(),now(),now())
on conflict (id) do nothing;
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000','22222222-2222-2222-2222-222222222222','authenticated','authenticated','uat-xem@local.test','x',now(),now(),now())
on conflict (id) do nothing;
insert into public.profiles (auth_user_id, role_code, is_active, display_name)
values ('11111111-1111-1111-1111-111111111111','ADMIN',true,'UAT Admin'),
       ('22222222-2222-2222-2222-222222222222','XEM',true,'UAT Xem')
on conflict do nothing;

\echo '=== T1. unaccent: Đào tạo -> ? ==='
select app.norm_vn('Đào tạo') as dao_tao, app.norm_vn('Phát sinh') as phat_sinh, app.norm_vn('Tổ Điện') as to_dien;

set request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
\echo '=== T2. current_role phải = ADMIN ==='
select app.current_role();

\echo '=== T3. Nhập đơn giá lần đầu (4 dòng) ==='
select public.admin_import_price_catalog(
  'aaaaaaaa-0000-0000-0000-000000000001','Mau_Don_Gia.xlsx',
  repeat('a',64),
  '[{"category_name":"CTN MAU","content":"Thi cong ong DN20","tech_desc":"PPR","unit":"m","work_code":"C1","calc_price":52000},
    {"category_name":"CTN MAU","content":"Lap chau rua","tech_desc":null,"unit":"bo","work_code":"C2","calc_price":240000},
    {"category_name":"DIEN MAU","content":"Keo day 2.5","tech_desc":null,"unit":"m","work_code":"D1","calc_price":9500},
    {"category_name":"KHAC MAU","content":"Đào tạo","tech_desc":null,"unit":"cong","work_code":null,"calc_price":0}]'::jsonb);

\echo '=== T4. calc_price giữ nguyên, approved = calc/1.3, is_special cho Đào tạo ==='
select category_name, content, unit, calc_price, approved_price, is_special, is_active
from public.price_items order by category_name, content;

\echo '=== T5. Idempotency: gọi lại cùng request_key -> idempotent=true, KHÔNG ghi thêm ==='
select public.admin_import_price_catalog('aaaaaaaa-0000-0000-0000-000000000001','Mau_Don_Gia.xlsx',repeat('a',64),
  '[{"category_name":"KHAC","content":"khong duoc ghi","unit":"m","calc_price":1}]'::jsonb);
select count(*) as so_dong_van_la_4 from public.price_items;

\echo '=== T6. FAIL-CLOSED: file có khóa trùng -> lỗi, dữ liệu cũ nguyên vẹn ==='
select public.admin_import_price_catalog('aaaaaaaa-0000-0000-0000-000000000002','trung.xlsx',repeat('b',64),
  '[{"category_name":"X","content":"Y","unit":"m","calc_price":1},
    {"category_name":"X","content":"Y","unit":"m","calc_price":2}]'::jsonb);
select count(*) as van_la_4_dong, (select count(*) from public.work_categories) as van_la_3_hang_muc from public.price_items;

\echo '=== T7. FAIL-CLOSED: thiếu đơn vị -> lỗi ==='
select public.admin_import_price_catalog('aaaaaaaa-0000-0000-0000-000000000003','thieu-dv.xlsx',repeat('c',64),
  '[{"category_name":"X","content":"Y","unit":"","calc_price":1}]'::jsonb);

\echo '=== T8. FAIL-CLOSED: sha256 sai định dạng -> lỗi ==='
select public.admin_import_price_catalog('aaaaaaaa-0000-0000-0000-000000000004','hash-sai.xlsx','khong-phai-sha',
  '[{"category_name":"X","content":"Y","unit":"m","calc_price":1}]'::jsonb);

\echo '=== T9. Tạo 1 việc đang dùng dòng "Keo day 2.5" ==='
insert into public.systems(code,name) values ('UATSYS','Tổ UAT') on conflict do nothing;
insert into public.teams(id,team_code,leader_name,is_active,created_at,updated_at,project_name)
values (gen_random_uuid(),'UAT-01','To Truong UAT',true,now(),now(),'DU AN UAT') on conflict do nothing;
insert into public.jobs(team_id,start_date,end_date,category_name,content,quantity,count_worker1)
select id,'2026-08-01','2026-08-05','DIEN MAU','Keo day 2.5',100,2 from public.teams where team_code='UAT-01';
select count(*) as so_viec from public.jobs where deleted_at is null;

\echo '=== T10. Nhập file MỚI bỏ hẳn "Keo day 2.5" và "Lap chau rua" ==='
\echo '     Kỳ vọng: "Keo day 2.5" GIỮ active (đang có việc), "Lap chau rua" -> ngừng dùng'
select public.admin_import_price_catalog('aaaaaaaa-0000-0000-0000-000000000005','lan2.xlsx',repeat('d',64),
  '[{"category_name":"CTN MAU","content":"Thi cong ong DN20","unit":"m","calc_price":55000}]'::jsonb);
select category_name, content, calc_price, is_active from public.price_items order by category_name, content;

\echo '=== T11. Bảng lương: 0 bị bỏ qua, >0 được ghi, lương ngày = /26 ==='
select public.admin_import_salary_standard('bbbbbbbb-0000-0000-0000-000000000001','Mau_Bang_Luong.xlsx',repeat('e',64),
  '[{"system_name":"Tổ PCCC","grade_name":"Tổ trưởng 1","monthly_salary":0},
    {"system_name":"Tổ PCCC","grade_name":"Thợ bậc 1","monthly_salary":20000000},
    {"system_name":"Tổ PCCC","grade_name":"Thợ bậc 2","monthly_salary":17000000},
    {"system_name":"Tổ HÀN MỚI","grade_name":"Thợ bậc 1","monthly_salary":18000000}]'::jsonb);
select s.name as he, g.name as chuc_danh, ss.monthly_salary, ss.daily_salary, ss.is_active
from public.salary_standards ss join public.systems s on s.id=ss.system_id
join public.salary_grades g on g.id=ss.grade_id order by s.name, g.name;

\echo '=== T12. FAIL-CLOSED: hai cách viết cùng một Hệ -> lỗi ==='
select public.admin_import_salary_standard('bbbbbbbb-0000-0000-0000-000000000002','mo-ho.xlsx',repeat('f',64),
  '[{"system_name":"Tổ Điện","grade_name":"Thợ bậc 1","monthly_salary":1000},
    {"system_name":"TO DIEN","grade_name":"Thợ bậc 2","monthly_salary":2000}]'::jsonb);

\echo '=== T13. RBAC: tài khoản XEM gọi RPC -> phải FORBIDDEN ==='
set request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
select app.current_role() as role_hien_tai;
select public.admin_import_price_catalog('cccccccc-0000-0000-0000-000000000001','trom.xlsx',repeat('9',64),
  '[{"category_name":"X","content":"Y","unit":"m","calc_price":1}]'::jsonb);
select public.admin_import_salary_standard('cccccccc-0000-0000-0000-000000000002','trom.xlsx',repeat('9',64),
  '[{"system_name":"A","grade_name":"B","monthly_salary":1}]'::jsonb);

\echo '=== T14. Snapshot backup đã ghi cho từng lần nhập thành công ==='
set request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
select source_name, after_item_count, deactivated_count, retained_referenced_count,
       jsonb_array_length(before_price_items) as so_dong_backup_truoc_khi_ghi
from app.price_catalog_import_backups order by imported_at;
select source_name, after_row_count, skipped_zero_count, new_system_count, new_grade_count,
       jsonb_array_length(before_standards) as so_dong_backup_truoc_khi_ghi
from app.salary_standard_import_backups order by imported_at;
