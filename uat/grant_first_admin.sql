-- grant_first_admin.sql
-- Gán vai trò ADMIN cho tài khoản đầu tiên trên STAGING.
--
-- Chạy trong Supabase Dashboard → SQL Editor của project kpi-vincons-staging.
-- ĐỌC HẾT TRƯỚC KHI CHẠY.
--
-- Điều kiện: đã dùng nút "Invite user" trong Dashboard → Authentication → Users
-- để mời royalle.manager@gmail.com, và người nhận đã bấm link đặt mật khẩu.
-- Script này KHÔNG đặt mật khẩu và không đọc mật khẩu của ai.
--
-- Chạy lại nhiều lần cho cùng kết quả (không tạo profile trùng).

begin;

-- 1. Kiểm tra tài khoản đã tồn tại trong Auth chưa.
--    Nếu trả về 0 dòng thì DỪNG: chưa mời hoặc mời sai email.
select id, email, email_confirmed_at is not null as da_xac_nhan_email, created_at
  from auth.users
 where lower(email) = lower('royalle.manager@gmail.com');

-- 2. Tạo profile ADMIN cho đúng tài khoản đó.
insert into public.profiles (auth_user_id, role_code, is_active, display_name)
select u.id, 'ADMIN', true, 'Trần Anh Toàn'
  from auth.users u
 where lower(u.email) = lower('royalle.manager@gmail.com')
   and not exists (select 1 from public.profiles p where p.auth_user_id = u.id);

-- 3. Nếu profile đã có sẵn từ trước thì nâng lên ADMIN và mở khóa.
update public.profiles p
   set role_code = 'ADMIN', is_active = true, updated_at = now()
  from auth.users u
 where u.id = p.auth_user_id
   and lower(u.email) = lower('royalle.manager@gmail.com')
   and (p.role_code <> 'ADMIN' or p.is_active = false);

-- 4. Đối chiếu trước khi commit. Phải thấy ĐÚNG MỘT dòng, role_code = ADMIN.
select u.email, p.role_code, p.is_active, p.display_name
  from public.profiles p
  join auth.users u on u.id = p.auth_user_id;

-- 5. Toàn hệ thống phải có đúng 1 profile ở giai đoạn này.
--    Nếu ra nhiều hơn 1, DỪNG và rollback để xem có tài khoản lạ không.
select count(*) as tong_so_profile from public.profiles;

commit;
