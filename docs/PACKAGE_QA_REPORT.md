# Báo cáo QA gói bản sao

## Kết quả đóng gói

| Kiểm tra | Kết quả | Ghi chú |
|---|---|---|
| Tách runtime khỏi Apps Script/Google Sheet nguồn | PASS | Clone dùng frontend + Supabase độc lập. |
| Loại deployment/project/Auth identifiers nguồn | PASS | Không tìm thấy chuỗi định danh cấm. |
| Loại dữ liệu sửa riêng UAT | PASS | Migration 025 và 028 đã bỏ block dữ liệu nguồn. |
| Kiểm tra credential pattern | PASS | Không có JWT, secret key hoặc service role key thật. |
| Frontend production build | PASS | Vinext build hoàn tất. |
| Automated tests | PASS | 5/5: PGV 6/12 dòng, render shell, quân số nhóm. |
| Mẫu Excel nhân sự | PASS | Đúng 5 cột; inspect không có lỗi công thức; render rõ ràng. |
| Production KPI VINCONS | NOT TOUCHED | Không deploy, migration hay ghi dữ liệu ra ngoài workspace. |

## Cảnh báo không chặn

- Build báo một số client chunk lớn hơn 500 kB. Trước khi có tải cao, nên tách tải động các màn PDF/Excel và trang quản trị, sau đó đo lại bundle và p95.
- Chưa thể kiểm thử project clone thật vì gói này cố ý không chứa ref/key/URL đích. Claude phải tạo Supabase/hosting mới rồi chạy UAT theo checklist.

## Cổng hiệu năng đề nghị

- Chạy thử tối thiểu 50 phiên đồng thời trên staging với dữ liệu gần quy mô thật.
- Theo dõi p95 RPC, tỷ lệ lỗi, deadlock, duplicate request và connection saturation.
- Phân trang danh sách lớn; giữ Data API max_rows hữu hạn; không tải toàn bộ catalog mỗi thao tác.
- Kiểm tra query plan/index cho jobs, assignments, teams, workers, week_id, group_code và các khóa tra catalog.
- Test double-click/idempotency cho create job, import roster, save PGV và archive tuần.

## Rollback

Clone Kit không thay đổi hệ thống nguồn. Nếu triển khai clone lỗi, rollback chỉ trong tài nguyên MỚI: quay frontend deployment trước, forward-fix migration hoặc khôi phục backup đã thử, tuyệt đối không trỏ biến môi trường sang KPI VINCONS.
