-- HOÀN TÁC 046_daily_production.sql
--
-- ⚠️ ĐỌC TRƯỚC KHI CHẠY: script này XÓA BẢNG job_daily_production, tức xóa **toàn bộ số
-- sản lượng tổ trưởng đã nhập**. Không có cách nào lấy lại từ script hoàn tác.
--
-- Bắt buộc tạo điểm khôi phục trước:
--     .\backup\kpi_restore_point.ps1 -Name truoc-khi-go-san-luong -OutputDir C:\KPI-Backups\staging
--
-- Chỉ chạy khi đang lùi cả phiên bản. Không bao giờ chạy riêng.

drop function if exists public.get_production_evaluation(uuid,integer);
drop function if exists public.unlock_daily_production(uuid,date);
drop function if exists public.save_daily_production(uuid,date,numeric);
drop table if exists public.job_daily_production;

notify pgrst, 'reload schema';
