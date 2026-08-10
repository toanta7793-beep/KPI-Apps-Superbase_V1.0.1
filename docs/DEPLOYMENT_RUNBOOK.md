# Runbook staging -> production

## 0. Cổng an toàn

- Xác nhận đang ở repository clone, branch clone và Supabase ref mới.
- Quét cấm: ref/URL/key/email/ID của hệ thống nguồn.
- Tạo tag/checkpoint trước migration và trước deploy.

## 1. Staging mới

- Tạo Supabase project staging độc lập.
- Link CLI bằng ref staging mới và kiểm tra lại tên project trước db push.
- Chạy migration 001–031 theo thứ tự. Migration 025/028 trong kit đã bỏ sửa dữ liệu UAT nguồn.
- Chạy seed tối thiểu; không seed PII hay số tiền thật.
- Cấu hình Auth Site URL và redirect URL của staging mới.
- Tạo hosting project/link staging mới và đặt biến môi trường.

## 2. Admin đầu tiên

- Tạo user bằng Supabase Dashboard hoặc Admin API phía server. Không viết mật khẩu vào SQL/Git.
- Đăng nhập một lần để tạo profile, sau đó gán role ADMIN bằng thao tác quản trị được kiểm soát.
- Bật MFA nếu môi trường hỗ trợ; đổi mật khẩu tạm ngay lần đầu.

## 3. UAT

- Nạp dữ liệu giả lập trước; chạy toàn bộ docs/UAT_CHECKLIST.md.
- Sau PASS mới nạp dữ liệu dự án thật qua quy trình import/đối soát.

## 4. Production mới

- Tạo Supabase production riêng, không clone khóa từ staging.
- Backup staging schema/data đã duyệt; ghi version migration và commit.
- Apply migration lên production mới, seed tối thiểu, tạo Auth riêng.
- Deploy link production mới. Không cập nhật bất kỳ deployment nào của KPI VINCONS.

## Rollback

- Frontend: quay về deployment/version trước của chính clone.
- Migration: ưu tiên forward-fix; migration phá hủy phải có backup đã khôi phục thử.
- Dữ liệu tuần: chỉ finalize delete sau khi backup và archive được xác minh.
