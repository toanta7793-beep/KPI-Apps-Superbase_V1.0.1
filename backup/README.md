# Sao lưu và khôi phục — bản tự quản

Dùng khi **không mua gói trả phí của Supabase**, tức phía nhà cung cấp **không có bản backup
tự động nào**. Đây là lớp bảo vệ duy nhất ở mức toàn bộ database, nên phải chạy được thật —
không chỉ tồn tại trên giấy.

Toàn bộ quy trình dưới đây **đã được diễn tập thật** ngày 11/08/2026 với 89 tổ và 1.089 công
nhân: sao lưu → xóa 1.000 công nhân, xóa sạch bảng lương, xóa hẳn bảng `price_items` →
khôi phục → checksum khớp từng ký tự, không còn khóa ngoại mồ côi.

---

## 1. Phạm vi — cái gì được sao lưu, cái gì không

**Có:** 5 schema của ứng dụng — `public`, `app`, `staging`, `mapping`, `reconciliation`.
Bao gồm toàn bộ tổ, công nhân, danh mục, đơn giá, bảng lương, giao việc, tuần, lịch sử,
và các bảng snapshot của những lần nhập Excel.

**Không có, phải xử lý riêng:**

| Không được sao lưu | Vì sao | Xử lý khi mất |
|---|---|---|
| Tài khoản đăng nhập (schema `auth`) | Trong đó có mã băm mật khẩu; để ngoài file backup thì an toàn hơn | Mời lại người dùng bằng nút Invite trên Dashboard. Số tài khoản ít nên chi phí thấp |
| File trong Supabase Storage (bucket `kpi-week-backups`) | `pg_dump` không đụng tới Storage | Tải riêng bằng Dashboard hoặc API Storage, xem mục 6 |
| Cấu hình Auth (Site URL, redirect, chính sách mật khẩu) | Không nằm trong database | Nằm sẵn trong `supabase/config.toml`, khôi phục bằng `supabase config push` |

---

## 2. Cài đặt một lần

Cần **Docker Desktop** đang chạy. Không cần cài PostgreSQL lên máy — script gọi `pg_dump`
và `pg_restore` từ ảnh `postgres:17`, khớp với phiên bản 17.6 của Supabase.

Lấy chuỗi kết nối: Supabase Dashboard → Project Settings → Database → Connection string → **URI**.

```powershell
setx KPI_BACKUP_DB_URL "postgresql://postgres.xxxxx:MATKHAU@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres"
```

Mở **PowerShell mới** sau khi chạy `setx` thì biến mới có hiệu lực.

Chuỗi này chứa mật khẩu database. Nó nằm trong biến môi trường của tài khoản Windows,
**không nằm trong Git, không nằm trong file nào của dự án**.

Chạy thử:

```powershell
cd C:\Users\toant\OneDrive\Desktop\Nhanban\KPI-MEP-Clone
.\backup\kpi_backup.ps1 -Label production -OutputDir D:\KPI-Backups\production
```

Kết quả: `kpi_production_<ngày>-<giờ>.dump` kèm file `.sha256`, và một dòng trong `backup.log`.

---

## 3. Chạy tự động hằng ngày

Task Scheduler của Windows:

1. **Create Task** (không phải Basic Task)
2. General → **Run whether user is logged on or not**
3. Triggers → hằng ngày, chọn giờ **không ai làm việc** (ví dụ 02:00)
4. Actions → Start a program:
   - Program: `powershell.exe`
   - Arguments:
     ```
     -NoProfile -ExecutionPolicy Bypass -File "C:\Users\toant\OneDrive\Desktop\Nhanban\KPI-MEP-Clone\backup\kpi_backup.ps1" -Label production -OutputDir "D:\KPI-Backups\production"
     ```
5. Settings → bật **Run task as soon as possible after a scheduled start is missed**

Script trả mã thoát khác 0 khi hỏng, nên cột Last Run Result trong Task Scheduler phản ánh
đúng. **Mỗi tháng nên mở xem một lần** — backup hỏng âm thầm là chuyện thường gặp nhất.

Mặc định giữ **30 bản gần nhất**, đổi bằng `-KeepCount`. Với quy mô hiện tại mỗi bản khoảng
0,2 MB nên 30 bản chưa tới 10 MB.

**Để bản backup ở ổ khác hoặc máy khác với máy làm việc.** Backup nằm cùng chỗ với thứ nó
bảo vệ thì không bảo vệ được gì.

---

## 4. Khôi phục — quy trình HAI bước

Trên Supabase **không dùng được** `pg_restore --clean`. Đã thử và đều hỏng:

| Cách làm | Lỗi gặp phải |
|---|---|
| Dump toàn bộ database rồi restore | `must be owner of event trigger pgrst_drop_watch` |
| `--clean --if-exists` khi bảng đã bị xóa hẳn | `DROP TRIGGER ... ON <bảng>` vẫn lỗi vì `--if-exists` chỉ bỏ qua trigger, không bỏ qua bảng không tồn tại |
| `--clean` với dump giới hạn schema | Sinh ra `DROP SCHEMA public`, mà Supabase có đối tượng phụ thuộc → `cannot drop schema public because other objects depend on it` |
| `--disable-triggers` | `permission denied: ... is a system trigger` — cần superuser, tài khoản `postgres` của Supabase không có |

Nên mô hình đúng là: **cấu trúc dựng từ mã nguồn, dữ liệu lấy từ bản dump.**

### Bước 1 — dựng lại cấu trúc

```powershell
# Project mới còn trống
npx supabase@2.113.0 db push

# Hoặc môi trường cục bộ
npx supabase@2.113.0 db reset --no-seed
```

`--no-seed` là bắt buộc ở môi trường cục bộ: nếu chạy seed thì các bảng đã có dòng và
bước 2 sẽ đụng khóa chính.

Bước này còn có một lợi ích: cấu trúc được dựng từ **chính migration của mã nguồn**, nên
chắc chắn khớp phiên bản đang chạy, không phụ thuộc cấu trúc cũ trong file dump.

### Bước 2 — nạp dữ liệu

```powershell
setx KPI_RESTORE_DB_URL "postgresql://..."   # biến RIÊNG, khác biến dùng khi sao lưu

# Xem trước, không ghi gì
.\backup\kpi_restore.ps1 -DumpFile D:\KPI-Backups\production\kpi_production_20260811-020000.dump -ConfirmLabel production

# Ghi thật, chỉ chạy sau khi đã đọc kỹ dòng "SẼ GHI ĐÈ LÊN"
.\backup\kpi_restore.ps1 -DumpFile ... -ConfirmLabel production -Execute
```

### Các chốt chặn có sẵn trong script khôi phục

| Chốt | Tác dụng |
|---|---|
| Mặc định chạy thử | Không thêm `-Execute` thì không ghi gì |
| `-ConfirmLabel` | Phải khớp nhãn trong tên file, tránh khôi phục nhầm môi trường |
| Kiểm SHA-256 | File hỏng hoặc bị sửa là dừng |
| `pg_restore --list` | Xác nhận bản dump đọc được **trước khi** làm rỗng bảng đích |
| Biến môi trường riêng | Đích khôi phục khác biến sao lưu, không thể ghi đè nhầm vì gõ thiếu tham số |
| `--single-transaction` | Lỗi ở bất kỳ đâu là quay lui sạch, không để lại trạng thái nửa vời |
| `set -o pipefail` | Bắt buộc — thiếu nó thì `pg_restore` hỏng vẫn báo "thành công" vì mã thoát lấy từ `psql` cuối ống. Đã dính đúng bẫy này lúc diễn tập |

---

## 5. Diễn tập — ít nhất mỗi quý một lần

Backup chưa từng khôi phục thử thì chưa phải backup.

1. Chạy `kpi_backup.ps1` trên môi trường thật
2. Dựng một Supabase project **tạm**, chạy `db push`
3. Khôi phục bản dump vào project tạm đó
4. Đối chiếu: số tổ, số công nhân, số dòng đơn giá, tổng quỹ lương ngày
5. Xóa project tạm, ghi lại kết quả kèm ngày

Đối chiếu nhanh bằng SQL:

```sql
select 'workers='||(select count(*) from public.workers)
    ||' teams='||(select count(*) from public.teams)
    ||' price_items='||(select count(*) from public.price_items)
    ||' | checksum='||md5(string_agg(x,'|' order by x))
from (select mnv||full_name||job_title from public.workers) t(x);
```

Kiểm khóa ngoại còn toàn vẹn:

```sql
select count(*) as workers_mo_coi from public.workers w
 where w.team_id is not null and not exists(select 1 from public.teams t where t.id = w.team_id);
```

**Kết quả diễn tập 11/08/2026:** 1.089 công nhân, 89 tổ, 20 dòng lương; checksum trước và sau
khôi phục đều là `f721591272997bfcbc2b4beaff420fb5`; 0 khóa ngoại mồ côi.

---

## 6. File trong Supabase Storage

Bucket `kpi-week-backups` chứa file Excel mà ứng dụng tự tạo trước mỗi lần xóa tuần.
`pg_dump` **không** lấy phần này — bảng `week_archive_operations` chỉ lưu đường dẫn và SHA-256,
không lưu nội dung file.

Tải định kỳ bằng Dashboard (Storage → chọn bucket → Download), hoặc bằng API Storage với
service key. Nếu mất phần này thì mất khả năng phục hồi các tuần đã archive, còn dữ liệu đang
hoạt động vẫn nằm trong bản dump.

---

## 7. Điểm khôi phục có tên — chốt lại một thời điểm cụ thể

Dùng khi sắp làm một việc lớn (đổi công thức, nhập lại đơn giá, chạy migration mới) và muốn
chắc chắn quay lại được đúng trạng thái trước đó.

```
.\backup\kpi_restore_point.ps1 -Name truoc-khi-doi-cong-thuc-luong -OutputDir C:\KPI-Backups\staging
```

Script chốt lại **cả ba phần** của một thời điểm, vì một bản dump không đủ:

| Phần | Nằm ở đâu | Quay lại được không |
|---|---|---|
| Mã nguồn + file migration | Git | Được, chính xác |
| Dữ liệu (dòng trong bảng) | File dump | Được, chính xác |
| **Cấu trúc bảng/hàm** | **không có bản chụp riêng** | **Không tự động** |

Phần thứ ba là chỗ dễ nhầm nhất và cần nói thẳng: `kpi_restore.ps1` chạy `--data-only`, tức
chỉ nạp lại **dữ liệu**. Nó **không** đưa cấu trúc bảng về như cũ, và dự án **không có
migration lùi (down) nào**. Nếu sau thời điểm đó đã chạy thêm migration thì phải hoặc dựng
một project mới rồi chạy migration tới đúng mốc, hoặc viết một migration đảo ngược.

Script từ chối chạy khi cây làm việc còn thay đổi chưa commit — commit ghi trong điểm khôi
phục sẽ không chứa các sửa đổi dang dở, và như vậy một nửa điểm khôi phục là thứ không tái
tạo được.

Kết quả sinh ra hai file:

- `diem-khoi-phuc_<ten>.json` trong thư mục backup — kèm SHA-256 và số dòng các bảng cốt lõi.
- `backup/restore-points/<ten>.md` trong repo — **nhớ commit**. Trong đó có sẵn lệnh quay lại,
  danh sách migration đã chạy, và các con số để đối chiếu sau khi khôi phục.

Đối chiếu số dòng sau khi nạp là bước bắt buộc, không phải tùy chọn: đó là cách duy nhất
biết bản khôi phục có đúng hay không mà không phải đoán.

---

## 8. Giới hạn cần biết rõ

- **Mất tối đa 1 ngày dữ liệu.** Chỉ quay về được thời điểm bản dump gần nhất. Muốn nhỏ hơn
  thì tăng tần suất chạy, hoặc mua add-on PITR của Supabase.
- **Không tự khôi phục tài khoản đăng nhập.** Phải mời lại người dùng.
- **Phụ thuộc Docker Desktop.** Máy chạy lịch phải bật Docker.
- **Không có cảnh báo tự động khi backup hỏng.** Phải tự mở Task Scheduler xem, hoặc đọc
  `backup.log` trong thư mục đích.
