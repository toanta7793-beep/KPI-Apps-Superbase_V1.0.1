# KPI MEP Web

Frontend độc lập cho KPI MEP, theo luồng:

`Browser → Supabase Auth → Data API/RPC + RLS → PostgreSQL`

## Phạm vi hiện tại

- Đăng nhập email/mật khẩu bằng Supabase Auth.
- Nhận diện người dùng, vai trò và phạm vi Tổ qua RPC `get_my_access()`.
- Đọc và cập nhật Giao việc, Tuần, CNCH, Công nhân, Quỹ lương và PGV qua Data API/RPC; PostgreSQL RLS giới hạn dữ liệu theo vai trò/Tổ.
- Admin có thể quản lý tài khoản qua API phía máy chủ; secret quản trị không bao giờ được gửi xuống trình duyệt.
- Apps Script hiện hữu vẫn là phương án fallback cho đến khi UAT đạt parity và được phê duyệt cutover.

## Chạy cục bộ

Yêu cầu Node.js `>=22.13.0`.

1. Sao chép `.env.example` thành `.env.local`.
2. Điền `NEXT_PUBLIC_SUPABASE_URL` và `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`.
3. Chỉ khi cần kiểm thử chức năng quản trị tài khoản, điền `SUPABASE_SECRET_KEY` ở môi trường máy chủ cục bộ.
4. Chạy `npm install`, sau đó `npm run dev`.

## Kiểm tra

- `npm run lint`: kiểm tra TypeScript/React.
- `npm run test`: build bản phát hành và kiểm thử HTML render.
- Migration PostgreSQL mới nhất nằm tại `../supabase/migrations/024_rpc_parity_user_worker.sql`.

## Bảo mật cấu hình

- Frontend chỉ dùng publishable key.
- Không đưa `SUPABASE_SECRET_KEY` hoặc `service_role` vào mã nguồn, Git, biến `NEXT_PUBLIC_*`, log hay phản hồi API.
- Trên UAT/production, secret quản trị chỉ được lưu dưới dạng biến môi trường mã hóa phía máy chủ của hệ thống hosting.
- API quản trị phải xác minh access token và vai trò `ADMIN` trước khi dùng secret phía máy chủ.
