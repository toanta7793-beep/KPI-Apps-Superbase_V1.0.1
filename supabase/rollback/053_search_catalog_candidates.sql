-- HOÀN TÁC 053_search_catalog_candidates.sql
--
-- Bỏ hàm tìm ứng viên hạng mục. Không mất dữ liệu: hàm chỉ đọc, không ghi gì.
-- Sau khi chạy, ô "AI tìm hạng mục" mất tác dụng; ô tìm Cấp 2 sẵn có vẫn hoạt động bình thường.

drop function if exists public.search_catalog_candidates(text,integer);

notify pgrst, 'reload schema';
