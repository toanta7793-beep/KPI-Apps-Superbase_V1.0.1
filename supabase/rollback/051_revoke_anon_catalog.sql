-- HOÀN TÁC 051_revoke_anon_catalog.sql
--
-- ⚠️ CẢNH BÁO: chạy script này là MỞ LẠI lỗ hổng — vai trò `anon` (chưa đăng nhập) sẽ đọc
-- được lại danh sách tên tổ và toàn bộ danh mục công việc. Chỉ chạy khi đang lùi cả phiên
-- bản, và cân nhắc bỏ qua chính script này vì nó không có tác dụng gì ngoài việc mở lại
-- một thứ đáng lẽ phải đóng.
--
-- Không mất dữ liệu: chỉ là cấp quyền.

grant execute on function public.get_teams_catalog() to anon;
grant execute on function public.get_catalog_cap1() to anon;
grant execute on function public.get_catalog_cap2(text) to anon;

notify pgrst, 'reload schema';
