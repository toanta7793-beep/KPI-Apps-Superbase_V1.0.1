# Nạp dữ liệu cho dự án mới

## Thứ tự

1. Hệ kỹ thuật và cấp bậc lương.
2. Bảng lương chuẩn theo hệ/cấp bậc.
3. Danh mục cấp 1, danh mục cấp 2, đơn vị, đơn giá, định mức.
4. Danh sách tổ và dự án.
5. Danh sách công nhân bằng templates/Mau_Danh_Sach_CNCH.xlsx.
6. Tài khoản Auth và phạm vi tổ.

## Quy tắc nhập nhân sự

- Đúng 5 cột: Mã nhân viên, Họ và tên, Chức vụ, Tên Tổ, Dự án.
- Mã nhân viên duy nhất; tên tổ được chuẩn hóa không dấu để đối chiếu nhưng giữ nguyên chuỗi hiển thị.
- Kiểm tra toàn bộ file trước khi ghi. Một dòng lỗi thì không thay đổi dữ liệu cũ.
- Ghi backup snapshot trước import; request_key và SHA-256 ngăn bấm lặp.
- Không đưa danh sách nhân sự thật vào Git.
