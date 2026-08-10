-- 036_data_api_grants.sql
--
-- CHẶN TRIỂN KHAI — phát hiện ngay sau khi apply lên staging ngày 10/08/2026.
--
-- Frontend đọc thẳng 4 bảng qua Data API (không qua RPC):
--     KpiApp.tsx:61  teams       .select(...)
--     KpiApp.tsx:62  workers     .select(... teams(leader_name))
--     KpiApp.tsx:64  work_weeks  .select(... teams(leader_name))
--     KpiApp.tsx:77  profiles    .select(... workers(... teams(...)))
--     KpiApp.tsx:160 teams       .update({is_active:true})   -- nút "Kích Hoạt Tổ"
--
-- Trên Supabase cloud hiện nay, bảng mới tạo trong schema public KHÔNG được tự động
-- cấp quyền cho anon/authenticated/service_role (xem ghi chú auto_expose_new_tables
-- trong supabase/config.toml). Không có migration nào cấp quyền các bảng này, nên
-- trên staging mọi lệnh đọc ở trên trả 401 và ứng dụng không tải nổi dữ liệu.
--
-- Vì sao chạy cục bộ không lộ ra: image Postgres của Supabase CLI vẫn giữ hành vi cũ,
-- authenticated được cấp SẴN toàn bộ quyền (SELECT, INSERT, UPDATE, DELETE, TRUNCATE)
-- trên mọi bảng public. Nói cách khác môi trường cục bộ RỘNG QUYỀN HƠN cloud, nên
-- "chạy được ở máy" không chứng minh được là quyền đã đúng.
--
-- Ở đây KHÔNG sao chép hành vi cục bộ. Chỉ cấp đúng phần frontend cần, và chỉ ở mức
-- cần thiết; mọi thao tác ghi khác vẫn phải đi qua RPC SECURITY DEFINER có kiểm tra vai trò.
-- RLS đã bật trên toàn bộ các bảng này và vẫn là lớp lọc dòng.

-- Dọn trước cho chắc chắn: không dựa vào quyền mà môi trường tự cấp.
revoke all on all tables in schema public from anon, authenticated;

-- anon (chưa đăng nhập) không được đọc bất cứ bảng nghiệp vụ nào.
-- Không cấp gì cho anon.

-- Chỉ đọc — RLS lọc theo vai trò và phạm vi tổ.
grant select on public.teams       to authenticated;
grant select on public.workers     to authenticated;
grant select on public.work_weeks  to authenticated;
grant select on public.profiles    to authenticated;

-- Ghi trực tiếp duy nhất mà giao diện dùng: bật/tắt hoạt động của Tổ.
-- Policy p_v1_teams_update quyết định ai được phép; ở đây chỉ mở đúng cột cần.
grant update (is_active, updated_at, updated_by) on public.teams to authenticated;

-- Không cấp gì thêm. Các bảng jobs, price_items, salary_standards, shared_work_weeks,
-- assignments, job_history, pgv_*, week_archive_operations và toàn bộ schema staging/
-- mapping/reconciliation/app đều chỉ truy cập được qua RPC SECURITY DEFINER.

notify pgrst, 'reload schema';
