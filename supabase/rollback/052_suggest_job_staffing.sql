-- HOÀN TÁC 052_suggest_job_staffing.sql
--
-- Bỏ hàm gợi ý và view năng lực tổ. Không mất dữ liệu: cả hai chỉ là phép tính, không lưu gì.
-- Sau khi chạy, màn giao việc mất nút gợi ý; mọi thứ còn lại không đổi.
--
-- Thứ tự: bỏ hàm trước rồi mới bỏ view, vì hàm phụ thuộc view.

drop function if exists public.suggest_job_staffing(uuid,text,text,numeric,integer,integer,integer,integer,integer,numeric);
drop view if exists app.v_team_grade_capacity;

notify pgrst, 'reload schema';
