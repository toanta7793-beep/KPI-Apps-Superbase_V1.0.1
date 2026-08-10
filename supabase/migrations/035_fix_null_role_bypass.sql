-- 035_fix_null_role_bypass.sql
--
-- LỖ HỔNG PHÂN QUYỀN — phát hiện trong UAT cục bộ ngày 10/08/2026.
--
-- app.current_role() trả NULL khi người dùng có JWT hợp lệ nhưng KHÔNG có profile
-- đang hoạt động (tài khoản vừa tạo chưa gán quyền, profile bị vô hiệu hóa,
-- hoặc profile bị xóa trong khi phiên đăng nhập còn hạn).
--
-- Trong SQL, NULL <> 'ADMIN' cho ra NULL chứ không phải TRUE, nên mọi câu
--     if app.current_role() <> 'ADMIN' then raise exception 'FORBIDDEN'; end if;
--     if app.current_role() not in ('ADMIN','GIAM_SAT','TO_TRUONG') then ... end if;
-- ĐỀU BỊ BỎ QUA. Toàn hệ thống có 29 chỗ kiểm tra quyền dạng phủ định như vậy.
--
-- Bằng chứng: một tài khoản không có profile đã ghi thành công vào public.price_items
-- qua admin_import_price_catalog, và app.price_catalog_import_backups ghi lại
-- imported_by là chính tài khoản đó.
--
-- Cách vá: sửa tại gốc thay vì viết lại 29 hàm — cho current_role() trả chuỗi rỗng
-- thay cho NULL. Khi đó '' <> 'ADMIN' là TRUE và mọi guard phủ định hoạt động trở lại,
-- còn các so sánh khẳng định ('' = 'ADMIN') vẫn cho FALSE như trước.
--
-- Hệ quả duy nhất cần xử lý kèm: policy p_shared_week_select (migration 030) dùng
-- `app.current_role() is not null`. Với chuỗi rỗng thì điều kiện này luôn đúng,
-- nên phải đổi sang so sánh khác rỗng, nếu không sẽ mở quyền đọc cho tài khoản không profile.

create or replace function app."current_role"()
returns text language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select p.role_code
       from public.profiles p
      where p.auth_user_id = auth.uid() and p.is_active = true
      limit 1),
    ''
  )
$$;

comment on function app."current_role"() is
  'Vai trò của phiên hiện tại. Trả chuỗi rỗng (KHÔNG phải NULL) khi không có profile đang hoạt động, để các guard dạng <> và NOT IN không bị NULL vô hiệu hóa.';

-- Giữ nguyên ý định ban đầu của policy: chỉ người có profile đang hoạt động mới đọc được.
drop policy if exists p_shared_week_select on public.shared_work_weeks;
create policy p_shared_week_select on public.shared_work_weeks
  for select to authenticated
  using (app.current_role() <> '');

notify pgrst, 'reload schema';
