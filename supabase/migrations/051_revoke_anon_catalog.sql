-- 051_revoke_anon_catalog.sql
--
-- Lỗ hổng phát hiện 12/08/2026 bằng script rà soát tự động (assets/audit.sql của skill IT-webapp).
--
-- BỆNH: ba hàm danh mục vẫn cho vai trò `anon` gọi được:
--     get_teams_catalog · get_catalog_cap1 · get_catalog_cap2
-- Cả ba đều `security definer` (bỏ qua RLS) và KHÔNG có bước kiểm quyền bên trong.
--
-- Vì sao đây là lộ dữ liệu thật, không phải lo xa: khóa publishable nằm sẵn trong mã
-- JavaScript của trang web — theo thiết kế nó là công khai. Ai có địa chỉ trang là gọi được
-- RPC với vai trò `anon`. Thử trên máy cục bộ: `set role anon` rồi gọi get_teams_catalog()
-- trả về 91 dòng tên tổ. Trên môi trường thật đó là 89 TÊN NGƯỜI THẬT, cộng toàn bộ danh mục
-- công việc của công ty — cho bất kỳ ai chưa đăng nhập.
--
-- Đã kiểm trước khi thu hồi: không luồng nào cần gọi ba hàm này trước khi đăng nhập.
--   * get_catalog_cap1 nằm trong loadAll(), mà loadAll chỉ chạy khi `if(session)`.
--   * get_catalog_cap2 chỉ gọi từ hộp thoại giao việc, vốn nằm trong app đã đăng nhập.
--   * get_teams_catalog KHÔNG được frontend gọi ở bất kỳ đâu.
-- Nên thu hồi quyền của anon không làm hỏng màn hình nào.
--
-- Không đụng tới thân hàm, không đổi quyền của `authenticated`.

revoke execute on function public.get_teams_catalog() from anon;
revoke execute on function public.get_catalog_cap1() from anon;
revoke execute on function public.get_catalog_cap2(text) from anon;

-- Thu hồi cả `public` cho chắc: cấp cho PUBLIC là cấp cho mọi vai trò, kể cả anon.
revoke execute on function public.get_teams_catalog() from public;
revoke execute on function public.get_catalog_cap1() from public;
revoke execute on function public.get_catalog_cap2(text) from public;

grant execute on function public.get_teams_catalog() to authenticated;
grant execute on function public.get_catalog_cap1() to authenticated;
grant execute on function public.get_catalog_cap2(text) to authenticated;

notify pgrst, 'reload schema';
