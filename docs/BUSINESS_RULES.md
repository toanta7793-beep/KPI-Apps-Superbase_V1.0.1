# Baseline nghiệp vụ bắt buộc

## Ngày

- Giao diện nhập và hiển thị dd/mm/yyyy; database lưu kiểu date ISO.
- Parser phải từ chối giá trị mơ hồ như 05/25/2026.

## Tuần

- Có 4 slot Tuần 1–4 dùng chung; tổ sử dụng tag khi khoảng thi công nằm trong tuần.
- Cho tạo và sửa. Tính cả ngày đầu/cuối, tối đa 9 ngày.
- Các tuần ACTIVE không được chồng ngày.
- Gộp tuần không thay đổi CNCH, đơn giá, định mức hoặc công thức KPI/hòa vốn/quỹ lương.

## Giao việc và KPI

- Danh mục cấp 2 tìm theo token không dấu; ưu tiên kết quả khớp từ, không dùng khớp ký tự rời gây nhiễu.
- Trước khi lưu phải xem được hòa vốn, sản lượng, chênh lệch lãi/lỗ.
- Cho sửa việc đã lưu. Mã nhóm chỉ liên kết các dòng, không làm mất dòng PGV.

## PGV

- PGV chung lấy mọi dòng công việc thuộc đúng tổ + tuần; tự tăng số dòng khi vượt 6.
- PGV CNCH xác định tuần theo ngày nhận việc của đúng tổ; ngày giao = ngày nhận - 1.
- Control chọn tuần/ngày không nằm trong vùng in.
- Mẫu in giữ bố cục đã duyệt; nội dung dài co giãn, không cắt mất.

## Quân số

- Dòng không có mã nhóm tính một lần.
- Các dòng cùng mã nhóm chỉ tính chung một cơ cấu nhân sự.
- Tổ trưởng không tham gia phép so sánh quân số đã giao.

## Xóa tuần

- Backup đúng tổ/tuần -> archive -> xác minh -> soft delete/giải phóng slot.
- Bất kỳ bước nào lỗi: rollback và không xóa dữ liệu hoạt động.
