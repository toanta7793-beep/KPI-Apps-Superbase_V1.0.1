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

## 2b. Đặt lại mật khẩu — thủ công, theo quyết định của chủ hệ thống

Ứng dụng **cố ý không có** nút "Quên mật khẩu" và không có màn hình đặt mật khẩu mới.
Đây là lựa chọn đã cân nhắc (10/08/2026), không phải thiếu sót bỏ quên.

Khi một người dùng quên mật khẩu:

1. Admin mở Supabase Dashboard → project tương ứng → **Authentication → Users**.
2. Tìm đúng email → menu **⋯** ở cuối hàng → **Reset password**.
3. Đặt mật khẩu mới, **tối thiểu 10 ký tự** (khớp `minimum_password_length` trong config.toml).
4. Giao mật khẩu cho người dùng qua kênh riêng. **Không gửi qua nhóm chat chung, không ghi vào Git,
   không dán vào phiếu giấy.** Yêu cầu họ đổi lại sau khi vào được.

Hệ quả cần biết trước khi mở rộng số người dùng:

- Mọi lần quên mật khẩu đều phải qua Admin, người dùng **không tự khôi phục được**.
- Người ở công trường sẽ phải chờ Admin có mặt trước máy tính.
- Cách "Send password recovery" của Dashboard **chỉ giải quyết một nửa**: link đăng nhập được người dùng
  vào app (client bật `detectSessionInUrl`), nhưng vì không có màn hình đặt mật khẩu mới nên lần sau
  họ vẫn kẹt. Dùng **Reset password** như bước 2, đừng dùng recovery email.

Nếu về sau muốn người dùng tự khôi phục, cần bổ sung hai màn hình: nút "Quên mật khẩu?" ở trang đăng nhập
(gọi `resetPasswordForEmail`) và màn hình đặt mật khẩu mới khi phiên đến từ link `type=recovery`
(gọi `updateUser({ password })`).

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
