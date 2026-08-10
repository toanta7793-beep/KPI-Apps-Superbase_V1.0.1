# UAT dry-run cục bộ — trước khi tạo bất kỳ Supabase project nào

- **Ngày:** 10/08/2026
- **Môi trường:** PostgreSQL 17 chạy trong Docker trên máy nội bộ (`supabase start`), dải cổng **553xx**
- **Không kết nối** tới bất kỳ Supabase project đám mây nào. Không đụng tới hệ thống KPI VINCONS.
- **Cách lặp lại:** `npx supabase@2.113.0 start` rồi `psql -f uat/uat_032_033_catalog_import.sql`

> ⚠️ Trên máy này đã có sẵn một stack Supabase cục bộ khác (`supabase_*_New-KPI`, dùng cổng mặc định 543xx).
> Vì vậy `supabase/config.toml` của bản sao được chuyển sang dải **55320–55329** và inspector **8183**.
> Đã xác nhận stack `New-KPI` không bị dừng, xóa hay ghi đè trong suốt quá trình.

## A. Áp migration

| Mục | Kết quả | Bằng chứng |
|---|---|---|
| Áp 001→033 theo thứ tự | **PASS** | 30/30 migration trong `supabase_migrations.schema_migrations` |
| Seed tối thiểu | **PASS** | 5 role, 5 hệ kỹ thuật, 6 cấp bậc |
| Không seed PII / số tiền thật | **PASS** | `price_items=0, workers=0, teams=0, salary_standards=0` |
| Đối tượng schema | **PASS** | 37 bảng · 46 policy · 281 function · 63 index |
| RLS bật trên toàn bộ bảng `public` | **PASS** | truy vấn `pg_class where not relrowsecurity` trả về rỗng |
| Mọi hàm SECURITY DEFINER đều cố định `search_path` | **PASS** | truy vấn tìm hàm thiếu `search_path` trả về rỗng |

## B. Chức năng migration 032 — nhập đơn giá

| # | Kịch bản | Kỳ vọng | Kết quả |
|---|---|---|---|
| T1 | `app.norm_vn('Đào tạo')` | `dao tao` | **PASS** |
| T3 | Nhập 4 dòng đầu tiên | 4 dòng, 3 hạng mục Cấp 1 | **PASS** |
| T4 | Quy tắc giá | `calc_price` giữ nguyên; `approved = calc/1.3` (52.000 → 40.000) | **PASS** |
| T4 | Nhận diện việc đặc biệt | "Đào tạo" ⇒ `is_special = true` | **PASS** |
| T5 | Idempotency | Gọi lại cùng `request_key` ⇒ `idempotent:true`, vẫn 4 dòng, nội dung mới bị bỏ qua | **PASS** |
| T6 | Fail-closed — khóa trùng | `DUPLICATE_PRICE_KEY`, dữ liệu cũ **nguyên vẹn 4 dòng / 3 hạng mục** | **PASS** |
| T7 | Fail-closed — thiếu đơn vị | `MISSING_UNIT` | **PASS** |
| T8 | Fail-closed — SHA-256 sai định dạng | `INVALID_SOURCE_HASH` | **PASS** |
| T10 | Dòng bị bỏ khỏi file | Dòng **đang có việc chưa xóa** ⇒ giữ `is_active=true`; dòng không ai dùng ⇒ `is_active=false`; **không xóa cứng dòng nào** | **PASS** (`deactivated=2, retained_referenced=1`) |
| T14 | Snapshot backup | Mỗi lần nhập thành công ghi 1 dòng backup kèm ảnh chụp dữ liệu **trước khi ghi** | **PASS** (lần 2 lưu 4 dòng cũ) |

## C. Chức năng migration 033 — nhập bảng lương

| # | Kịch bản | Kỳ vọng | Kết quả |
|---|---|---|---|
| T11 | Dòng lương 0 | Bị bỏ qua, không vi phạm `ck_salary_month_pos`; báo `skipped_zero_count=1` | **PASS** |
| T11 | Lương ngày | DB tự tính `= tháng / 26` (20.000.000 → 769.230,7692) | **PASS** |
| T11 | Hệ mới trong file | Tự tạo ("Tổ HÀN MỚI"), `new_system_count=1` | **PASS** |
| T12 | Fail-closed — "Tổ Điện" vs "TO DIEN" | `AMBIGUOUS_SYSTEM_NAME` | **PASS** |
| T14 | Snapshot backup | Ghi đủ | **PASS** |

## D. Phân quyền

| # | Kịch bản | Kỳ vọng | Kết quả |
|---|---|---|---|
| T2 | Profile ADMIN ⇒ `app.current_role()` | `ADMIN` | **PASS** |
| T13 | Tài khoản vai trò `XEM` gọi 2 RPC nhập | `FORBIDDEN` cả hai | **PASS** |

## E. Chưa kiểm thử ở bước này

Các mục sau **chỉ chạy được sau khi có staging thật + có dữ liệu giả đầy đủ**, chưa PASS:

- Toàn bộ luồng giao diện: đăng nhập, tạo/sửa việc, preview hòa vốn, gộp/hủy nhóm.
- Tuần 1–4: 9 ngày PASS / 10 ngày FAIL / chống overlap.
- PGV chung (2 việc → 2 dòng, 12 việc → 12 dòng), PGV CNCH (ngày giao = ngày nhận − 1).
- Quân số: dòng không nhóm, cùng mã nhóm, loại tổ trưởng.
- Xóa tuần: backup → archive → verify → delete, và trường hợp lỗi giữa chừng.
- Tải đồng thời, double-click ở tầng HTTP, khôi phục backup.
- Nhập Excel qua **giao diện** (bước này mới chỉ kiểm thử ở tầng RPC/PostgreSQL).

## F. Rollback

Dry-run này không tạo tài nguyên đám mây nào. Dọn sạch bằng:

```bash
npx supabase@2.113.0 stop --no-backup
```
