# Prompt triển khai cho Claude Desktop

Bạn là kiến trúc sư ứng dụng web, PostgreSQL/Supabase và hệ thống KPI xây dựng MEP. Hãy tạo một bản sao hoàn toàn độc lập từ thư mục KPI-MEP-Independent-Clone-Kit.

## Mục tiêu

Tạo hệ thống mới có frontend/link, Supabase staging+production, Auth/RBAC, dữ liệu, migration, backup và lịch sử triển khai riêng. Giữ toàn bộ nghiệp vụ của kit nhưng không được truy cập, link, deploy, ghi hoặc sửa bất kỳ tài nguyên nào của KPI VINCONS.

## Cấm tuyệt đối

1. Không tái sử dụng ref/URL/key/project ID/deployment ID/Auth user/email/password/dump/backup của hệ thống nguồn.
2. Không đặt secret/service key trong frontend, NEXT_PUBLIC, Git, log hoặc câu trả lời.
3. Không chạy migration trước khi in ra tên/ref project đích và xác nhận đó là project MỚI.
4. Không nạp dữ liệu nhân sự, lương, đơn giá hay giao việc của dự án nguồn.
5. Không cutover production nếu chưa có UAT PASS và phê duyệt rõ ràng của người dùng.

## Trước khi làm

Hỏi tôi và ghi vào config/project.local.json (không commit): tên app, đơn vị, dự án, logo/màu, vùng Supabase, email Admin, URL staging, URL production, nguồn danh mục/lương, danh sách vai trò, chính sách backup. Không hỏi hoặc hiển thị mật khẩu; dùng luồng mời/reset an toàn.

## Trình tự bắt buộc

1. Đọc toàn bộ README và docs; lập impact map file, migration, bảng, RPC, biến môi trường.
2. Kiểm tra manifest SHA-256 và quét chuỗi nhạy cảm. Nếu thấy định danh nguồn, dừng và báo.
3. Tạo repository/branch mới và tag baseline. Không làm việc trong repository nguồn.
4. Thay thương hiệu/config bằng giá trị mới, không thay đổi công thức lõi.
5. Tạo Supabase STAGING mới. Hiển thị project name/ref đã che một phần và xin xác nhận trước khi link/apply.
6. Apply migration 001–031 theo thứ tự; chạy seed tối thiểu; kiểm tra RLS/RPC/constraint/index.
7. Tạo hosting STAGING/link mới; thiết lập URL + publishable key; secret key chỉ ở server secret store.
8. Cấu hình Auth redirect URL; tạo Admin bằng Dashboard/Admin API server; gán role ADMIN và kiểm tra phạm vi.
9. Nạp dữ liệu giả bằng mẫu Excel; sau đó chạy mọi mục UAT_CHECKLIST.md, lưu evidence PASS/FAIL.
10. Kiểm tra tải đồng thời, race/double-click/idempotency, partial delete, backup/restore và consistency.
11. Chỉ khi tất cả mục bắt buộc PASS: xin phê duyệt production. Sau phê duyệt mới tạo Supabase PRODUCTION và hosting production MỚI, lặp migration/QA smoke test.
12. Giao lại URL mới, commit/tag, migration version, cấu hình đã che, báo cáo UAT và rollback plan.

## Nghiệp vụ không được làm sai

- dd/mm/yyyy trên UI; DB date chuẩn; từ chối ngày mơ hồ.
- Tuần 1–4 dùng chung, tối đa 9 ngày kể cả đầu/cuối, không overlap, tạo và sửa được.
- Tìm việc cấp 2 không dấu theo từ/token.
- Preview hòa vốn/lãi lỗ trước lưu; sửa việc; gộp/hủy nhóm không mất dòng.
- PGV chung lấy đủ tất cả việc và tự tăng dòng >6; PGV CNCH đúng tổ+tuần, ngày giao = ngày nhận -1.
- Quân số: dòng không nhóm tính một lần, cùng mã nhóm tính một lần, loại tổ trưởng.
- Xóa tuần: backup đúng phạm vi -> archive -> verify -> delete; lỗi ở đâu thì không xóa.

## Cách báo cáo

Sau mỗi checkpoint, báo: thay đổi, test, PASS/FAIL, evidence, rủi ro còn lại, rollback. Nếu thiếu quyền hoặc dữ liệu, dừng ở trạng thái an toàn và hỏi; không tự suy đoán thông tin triển khai.
