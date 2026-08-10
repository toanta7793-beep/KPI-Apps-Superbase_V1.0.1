# UAT checklist

Ghi Evidence, Người kiểm tra, Thời gian và PASS/FAIL cho từng mục.

- [ ] Auth: đăng nhập, reset mật khẩu, logout, session expiry.
- [ ] RBAC: ADMIN/GIAM_SAT/TO_TRUONG/XEM đúng quyền và đúng phạm vi tổ.
- [ ] Catalog: cấp 1–2, tìm không dấu, đơn vị/đơn giá/định mức đúng.
- [ ] Excel nhân sự: file chuẩn PASS; mã trùng/thiếu cột/tổ mơ hồ FAIL và dữ liệu cũ giữ nguyên.
- [ ] Quỹ lương: số người, cấp bậc, lương ngày và tổng khớp dữ liệu đối chiếu.
- [ ] Giao việc: tạo, sửa, double-click, preview hòa vốn/lãi lỗ.
- [ ] Nhóm việc: tạo nhóm, hủy nhóm, nhiều nhóm; không mất dòng.
- [ ] Tuần: tạo/sửa 1–4, 9 ngày PASS, 10 ngày FAIL, overlap FAIL.
- [ ] PGV chung: 2 việc hiện 2; 12 việc hiện 12; mẫu in/PDF không cắt nội dung.
- [ ] PGV CNCH: ngày nhận xác định đúng tuần/tổ; ngày giao = -1; control không in.
- [ ] Quân số: ungrouped tính từng dòng; cùng group tính một lần; loại tổ trưởng.
- [ ] KPI/hòa vốn: đối chiếu mẫu chuẩn và sai số bằng 0 theo quy tắc làm tròn.
- [ ] Xóa tuần: backup đúng phạm vi; lỗi backup/archive không xóa; retry không xóa lặp.
- [ ] Consistency: Web–RPC–PostgreSQL–file backup cùng tổng dòng/checksum.
- [ ] Tải đồng thời: nhiều user đọc/ghi; không race, partial update hay duplicate.
- [ ] Security: RLS, không lộ secret ở HTML/log/network bundle.
