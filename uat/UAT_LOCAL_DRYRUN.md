# UAT dry-run cục bộ — trước khi tạo bất kỳ Supabase project nào

- **Ngày:** 10/08/2026 (cập nhật sau vòng UAT giao diện)
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

## E. Kiểm thử qua giao diện + PostgREST (role `authenticated`, RLS + safeupdate thật)

Chạy trên `npm run dev` trỏ vào stack cục bộ. Đây là lớp đã lộ ra lỗi mà psql (superuser) **không** bắt được.

### 🐛 Lỗi đã phát hiện và sửa

`admin_import_salary_standard` trả **400 `UPDATE requires a WHERE clause`** khi gọi qua PostgREST.
PostgREST bật `safeupdate` cho role `authenticated`, nên `update salary_rows set ...` không có `WHERE` bị từ chối.
Chạy bằng psql với quyền superuser thì **không** lỗi — vì vậy chỉ kiểm thử ở tầng SQL là chưa đủ.

Đây đúng là lỗi mà migration `029_uat_runtime_fixes.sql` của kit đã từng phải vá cho `admin_import_worker_roster`
(thêm `where r.team_id is null`). Bản sửa: thêm `where r.system_id is null or r.grade_id is null` vào 033,
kèm chú thích lý do, và quét lại toàn bộ 032/033 — **0 câu lệnh ghi nào còn thiếu WHERE**.
Sau khi sửa, `supabase db reset` áp lại 001→033 từ đầu và nhập lại thành công.

### Kết quả

| Mục UAT | Kỳ vọng | Kết quả |
|---|---|---|
| Đăng nhập / đăng xuất | Vào được, nhận đúng vai trò | **PASS** (`⚡ Quản trị viên`) |
| Menu Quản Trị chỉ hiện với ADMIN | Có | **PASS** |
| Nhập đơn giá qua UI | Preview 5 dòng/4 hạng mục + SHA-256, ghi đúng | **PASS** (52.000 → 40.000 hiển thị ngay trên preview) |
| Nhập bảng lương qua UI | 9 dòng ghi, 2 dòng lương 0 bỏ qua | **PASS** (sau khi sửa lỗi trên) |
| Nhập danh sách công nhân qua UI | 3 CNCH, 2 tổ tự tạo | **PASS** |
| Quỹ lương tự tính | "Thợ Điện bậc 2" → 17.000.000/26 = 653.846 ₫/ngày | **PASS** |
| Tìm việc cấp 2 không dấu | `get_catalog_cap2` trả đúng danh sách | **PASS** |
| Tuần 9 ngày | Lưu được | **PASS** (01/09→09/09, lưu DB dạng ISO, UI hiện dd/mm/yyyy) |
| Tuần 10 ngày | Từ chối | **PASS** (`INVALID_WEEK_RANGE_MAX_9_DAYS`) |
| Tuần chồng ngày | Từ chối | **PASS** (`SHARED_WEEK_OVERLAP`) |
| Sửa tuần | Có nút "✏️ Sửa Tuần 1" | **PASS** |
| Preview hòa vốn trước khi lưu | Đúng số học | **PASS** — 3 ngày công · đơn giá 52.000 (`calc_price`) · sản lượng 5.200.000 · quỹ lương ngày 653.846,15 · chi phí 1.961.538,46 · chênh lệch 3.238.461,54 · điểm hòa vốn 37,72 |
| Chống double-click tạo việc | Cùng `request_key` → cùng job id, không tạo trùng | **PASS** |
| PGV chung 2 việc | 2 dòng | **PASS** |
| PGV chung 12 việc | 12 dòng (tự tăng quá 6) | **PASS** |
| PGV: ngày giao = ngày nhận − 1 | assign 31/08, receive 01/09 | **PASS** |
| PGV CNCH | Nhận 03/09 → giao 02/09, đúng Tuần 1, đúng tổ | **PASS** |
| Quân số | Bảng hiện đủ 4 bậc, ghi rõ "Tổ trưởng không tham gia" | **PASS** |
| Gán việc đã gán vào tuần | Từ chối cả lô, không gán một phần | **PASS** (`JOB_MUST_FIT_SHARED_WEEK`) |
| Xóa tuần — bằng chứng backup sai | Từ chối finalize, **không xóa gì** | **PASS** (`INVALID_BACKUP_PROOF`; sau đó vẫn còn 12 việc, 2 tuần ACTIVE, thao tác archive treo ở `PENDING`) |
| RBAC vai trò XEM | FORBIDDEN ở 2 RPC nhập | **PASS** |

### ⚠️ Hai điểm cần cải thiện (chưa chặn, chưa sửa)

1. **Thông báo lỗi tuần hiện ra là mã kỹ thuật.** Người dùng nhập tuần 10 ngày chỉ thấy chữ
   `INVALID_WEEK_RANGE_MAX_9_DAYS`. Cần một hàm dịch lỗi như `rosterImportError` / `catalogImportError`
   đã có, áp cho `upsert_shared_work_week`, `assign_jobs_to_shared_week`, `create_job`, `update_job`.
2. **Tên lỗi `JOB_MUST_FIT_SHARED_WEEK` gây hiểu nhầm** — nó bắn ra cả khi việc *đã* thuộc một tuần,
   không liên quan tới chuyện ngày có nằm trong tuần hay không.

## F. Chưa kiểm thử ở bước này

Các mục sau **chỉ chạy được sau khi có staging thật + có dữ liệu giả đầy đủ**, chưa PASS:

- **Sửa việc** đã lưu (`update_job`) và **gộp/hủy mã nhóm** — chưa chạy.
- **Xóa tuần đường thành công**: backup → archive → verify → delete. Mới chỉ chứng minh nhánh THẤT BẠI không xóa gì.
- **Khôi phục backup**: chưa thử phục hồi từ file Excel/snapshot đã ghi.
- **Bản in/PDF**: chưa kiểm tra bố cục có bị cắt nội dung dài, chưa đối chiếu với PGV_MAU.xlsx.
- **Tải đồng thời**: chưa chạy nhiều phiên song song; chưa đo p95 RPC, deadlock, connection saturation.
- **RBAC đầy đủ**: mới thử ADMIN và XEM; chưa thử GIAM_SAT và TO_TRUONG với phạm vi tổ.
- **Quân số nhiều nhóm**: mới thấy bảng hiển thị, chưa dựng dữ liệu nhiều mã nhóm để đối chiếu số.

## F. Rollback

Dry-run này không tạo tài nguyên đám mây nào. Dọn sạch bằng:

```bash
npx supabase@2.113.0 stop --no-backup
```
