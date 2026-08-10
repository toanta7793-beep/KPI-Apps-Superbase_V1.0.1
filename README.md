# KPI MEP Independent Clone Kit

Bộ mã nguồn mẫu để tạo một hệ thống KPI/Giao việc/Quỹ lương/PGV độc lập cho dự án MEP khác. Bộ này được tách từ baseline chức năng đã kiểm thử, nhưng không chứa khóa truy cập, ID deployment, tài khoản, tổ/công nhân, lương, đơn giá hoặc dữ liệu giao việc của hệ thống nguồn.

## Phạm vi

- Frontend React/Vinext, Supabase Auth, Data API/RPC và PostgreSQL.
- Quản trị người dùng và phân quyền ADMIN/GIAM_SAT/TO_TRUONG/XEM.
- Danh mục công việc cấp 1–2, đội/tổ, công nhân, bảng lương chuẩn.
- Giao việc, xem trước hòa vốn/lãi lỗ, sửa việc, tìm kiếm không dấu, mã nhóm.
- Tuần dùng chung 1–4, tối đa 9 ngày, chống chồng ngày; gộp/hủy gộp theo tuần.
- KPI, quỹ lương, PGV chung, PGV CNCH, kiểm soát quân số, in/PDF.
- Backup Excel + archive + xác minh rồi mới xóa tuần (fail-closed).

## Điểm bắt đầu an toàn

1. Tạo repository mới từ thư mục này; không chép ngược file vào repository nguồn.
2. Tạo hai Supabase project mới: staging và production.
3. Chạy migration trên staging mới; không link CLI tới project nguồn.
4. Điền biến môi trường staging bằng giá trị của project mới.
5. Tạo Admin đầu tiên trong Supabase Auth, sau đó gán profile ADMIN theo runbook.
6. Nạp danh mục/lương bằng quy trình được duyệt; nhập tổ và công nhân bằng mẫu Excel.
7. QA staging; chỉ cutover production sau phê duyệt bằng văn bản.

Đọc lần lượt: docs/ARCHITECTURE.md, docs/BUSINESS_RULES.md, docs/DEPLOYMENT_RUNBOOK.md, docs/UAT_CHECKLIST.md và CLAUDE_DESKTOP_PROMPT.md.
