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


## F2. Vòng UAT thứ hai — 034/035, xóa tuần thành công, nhóm việc, RBAC theo tổ

### 🔴 Lỗ hổng phân quyền — nghiêm trọng, đã vá (migration 035)

`app.current_role()` trả **NULL** khi người dùng có JWT hợp lệ nhưng không có profile đang hoạt động
(tài khoản vừa tạo chưa gán quyền, profile bị vô hiệu hóa, hoặc bị xóa trong khi phiên còn hạn).

Trong SQL, `NULL <> 'ADMIN'` cho ra **NULL chứ không phải TRUE**, nên mọi câu lệnh dạng

```sql
if app.current_role() <> 'ADMIN' then raise exception 'FORBIDDEN'; end if;
if app.current_role() not in ('ADMIN','GIAM_SAT','TO_TRUONG') then ... end if;
```

**đều bị bỏ qua**. Toàn hệ thống có **29 chỗ kiểm tra quyền dạng phủ định** như vậy:
26 chỗ nằm trong migration của **kit gốc** (022, 024×13, 025, 028×4, 029×3, 030×3),
3 chỗ trong code mới (032, 033, 034).

**Bằng chứng khai thác:** một tài khoản không có profile đã ghi thành công một dòng vào
`public.price_items` qua `admin_import_price_catalog`, và `app.price_catalog_import_backups`
ghi lại `imported_by` chính là tài khoản đó. Dòng rác đã được xóa sau khi kiểm chứng.

**Cách vá:** sửa tại gốc thay vì viết lại 29 hàm — `app.current_role()` trả **chuỗi rỗng** thay cho NULL.
Khi đó `'' <> 'ADMIN'` là TRUE nên mọi guard phủ định hoạt động trở lại, còn so sánh khẳng định
(`'' = 'ADMIN'`) vẫn cho FALSE như cũ. Kèm theo phải sửa policy `p_shared_week_select` (migration 030)
vì nó dùng `current_role() is not null` — với chuỗi rỗng thì điều kiện đó luôn đúng và sẽ mở quyền đọc.

> ⚠️ **Cần báo cho chủ hệ thống nguồn.** 26/29 chỗ này đến từ kit gốc, nên hệ thống KPI VINCONS
> đang chạy nhiều khả năng cũng có lỗ hổng tương tự. Bản sao này không đụng tới hệ thống đó;
> việc xử lý bên nguồn là quyết định của bạn.

### Kết quả sau khi vá

| Kịch bản | Kỳ vọng | Kết quả |
|---|---|---|
| Tài khoản **không có profile** gọi `admin_import_price_catalog` | 403 FORBIDDEN | **PASS** |
| Tài khoản **không có profile** gọi `admin_import_salary_standard` | 403 FORBIDDEN | **PASS** |
| Tài khoản **không có profile** đọc `shared_work_weeks` / `jobs` | Trả về rỗng | **PASS** |
| ADMIN sau khi vá | Mọi thao tác vẫn chạy | **PASS** (11/11 test, lint sạch, tsc = baseline) |
| GIAM_SAT phạm vi Tổ MEP 01 | Thấy 1 tổ, 3 việc của đúng tổ đó | **PASS** |
| GIAM_SAT gọi RPC chỉ-ADMIN | FORBIDDEN | **PASS** |
| GIAM_SAT xem PGV tổ ngoài phạm vi | FORBIDDEN | **PASS** |
| TO_TRUONG phạm vi Tổ MEP 02 | Thấy 1 tổ, 0 việc (tổ này chưa có việc) | **PASS** |
| TO_TRUONG gọi RPC chỉ-ADMIN / PGV ngoài phạm vi | FORBIDDEN cả hai | **PASS** |

### Mã lỗi rõ nghĩa (migration 034)

| Kịch bản | Trước | Sau |
|---|---|---|
| Gộp việc **đã thuộc** một tuần | `JOB_MUST_FIT_SHARED_WEEK` | `JOB_ALREADY_IN_WEEK` — **PASS** |
| Gộp việc có **ngày ngoài** khoảng tuần | `JOB_MUST_FIT_SHARED_WEEK` | `JOB_DATES_OUTSIDE_SHARED_WEEK` — **PASS** |

Kèm `operationError()` trong `app/importErrors.ts`: 40+ mã lỗi Tuần / Giao việc / Nhóm việc / Xóa tuần
được dịch sang tiếng Việt, đã nối vào `KpiApp`, `JobEditorModal`, `WeekArchiveButton`.

### Nhóm việc và sửa việc

| Kịch bản | Kỳ vọng | Kết quả |
|---|---|---|
| Gộp 2 việc **khác vị trí** | Từ chối | **PASS** (`GROUP_LOCATION_MISMATCH`) |
| Gộp 2 việc giống hệt | Sinh mã `MN-YYYYMMDD-NN` | **PASS** (`MN-20260905-01`) |
| Sau khi gộp | **Không mất dòng nào** | **PASS** (15 việc trước và sau) |
| Sửa việc **đang trong nhóm** | Từ chối | **PASS** (`REMOVE_GROUP_BEFORE_EDIT`) |
| Hủy nhóm | Không mất dòng | **PASS** (vẫn 15 việc, 0 mã nhóm) |
| Sửa việc **sau khi** hủy nhóm | Lưu được | **PASS** (khối lượng 20 → 99) |

### Xóa tuần — đường thành công (qua giao diện, đủ chuỗi backup → archive → verify → delete)

| Bước kiểm chứng | Kết quả |
|---|---|
| Thao tác archive | `COMPLETED`, `row_count = 12`, có `backup_path` và `backup_sha256` | 
| File backup trên Storage | Có, đường dẫn `<team_id>/<week_id>/<operation_id>.xlsx` |
| Đọc lại file backup | Mở được, sheet `BACKUP_TUAN`, **1 header + 12 dòng việc — khớp `row_count`** |
| Việc trong tuần | 12 việc **xóa mềm**, 3 việc ngoài tuần còn nguyên |
| Tuần của Tổ MEP 01 | `ARCHIVED` |
| Tuần của **Tổ MEP 02** | vẫn `ACTIVE` — **backup đúng phạm vi tổ, không lan sang tổ khác** |
| Thao tác archive thất bại trước đó | vẫn treo `PENDING`, chưa từng xóa gì |

**Consistency Web–RPC–PostgreSQL–file backup: khớp trên số dòng (12).**


## F2b. Vòng UAT thứ ba — bản in PGV và phục hồi từ backup

### Bố cục PGV đối chiếu `PGV_MAU.xlsx` — **KHỚP**

Chỉ đọc bố cục của file mẫu, **không nạp nội dung "Dự án: Vũ Yên" vào bản sao**.

| | PGV_MAU.xlsx | Bản in của app |
|---|---|---|
| Khối thông tin đầu phiếu | Dự án · Hạng mục · Bên giao Việc · Bên nhận Việc · Số CN · Ngày giao việc · Ngày nhận việc · Yêu cầu kèm theo · Tài liệu kèm theo | **đủ 9 mục, cùng thứ tự** |
| Cột chính | STT · Nội dung công việc/Vị trí · Số lượng CN · Mục tiêu hoàn thành · Thời gian · Đánh giá kết quả hoàn thành · Ghi chú | **khớp 7/7** |
| Cột con | Phân khu · Lô · Block · Vị trí chi tiết/tầng · Nội dung công việc Cấp 2 · Ngày bắt đầu · Ngày kết thúc | **khớp 7/7** |

Khác biệt duy nhất là chữ nhãn: mẫu ghi "Vị trí chi tiết/tầng", app ghi "Vị trí chi tiết/tầng/mặt-trục" — chi tiết hơn, không đổi cấu trúc.

### 🐛 Backup tuần không phục hồi được đầy đủ — đã sửa

`buildWeekBackupXlsx` chỉ ghi 26 cột và **bỏ sót `is_special_labor`** cùng các cột kiểm toán
(`created_at`, `created_by`, `request_key`, `legacy_source_row`). Cờ `is_special_labor` quyết định
việc "Đào tạo"/"Phát sinh" có tính sản lượng hay không — phục hồi từ file cũ sẽ làm KPI lệch mà
**không có dấu hiệu nào báo lỗi**. Backup mà không phục hồi đủ thì cổng "backup trước khi xóa" chỉ là hình thức.

Kèm theo một lỗi sẽ phát sinh khi sửa: hàm sinh địa chỉ ô dùng `String.fromCharCode(65 + n)`,
chỉ đúng tới cột Z. Bản cũ có đúng 26 cột nên chưa lộ; nâng lên 33 cột sẽ sinh ký tự rác
(`[1`, ``...) và Excel không mở được file. Đã thay bằng hàm sinh A..Z, AA, AB... và `autoFilter`
tính theo cột cuối thay vì cố định `A1:Z`.

3 test mới trong `web/tests/week-backup.test.mjs` khóa cả hai điều này lại.

### 🐛 Mẫu Excel đơn giá dạy sai quy ước việc đặc biệt — đã sửa

`create_job` xác định việc đặc biệt bằng **HẠNG MỤC CẤP 1**: `norm_vn(category_name) in ('dao tao','phat sinh')`.
Mẫu cũ của tôi để "Đào tạo" ở cột **Nội dung Cấp 2** dưới hạng mục "KHÁC MẪU" — theo mẫu đó thì
người dùng dựng xong danh mục sẽ **không bao giờ giao được việc đặc biệt** (báo `INVALID_CATEGORY`).
Đã sửa mẫu: "Đào tạo" và "Phát sinh" là hai hạng mục Cấp 1 riêng, tô vàng, kèm 2 dòng hướng dẫn.

Migration 032 cũng đang suy `price_items.is_special` từ **nội dung**, lệch với quy tắc thật.
Đã đổi sang suy từ hạng mục cho khớp `create_job`. (Cột này hiện chưa hàm nào đọc, nhưng để lệch
là cái bẫy cho người đọc sau.)

### Vòng đầy đủ backup → xóa → phục hồi

Dựng Tuần 2 cho **Tổ MEP 02** với 3 việc, trong đó **1 việc đặc biệt** (hạng mục "Đào tạo",
khối lượng tự tính = 2 người × 2 ngày = 4 công — đúng thiết kế của kit).

| Bước | Kết quả |
|---|---|
| Archive qua giao diện | `COMPLETED`, `row_count = 3` |
| Phạm vi | Tuần 2 của **MEP 02** → `ARCHIVED`; Tuần 2 của **MEP 01** vẫn `ACTIVE` |
| File backup | 33 cột, có cột "Việc đặc biệt", giá trị `true` đúng ở dòng Đào tạo |
| Sinh SQL phục hồi | `uat/restore_week_from_backup.py` — chạy thử, ra 3 câu `insert ... on conflict (id) do update` |
| Chạy phục hồi | 3 việc trở lại hoạt động |
| **Đối chiếu trước/sau** | **KHỚP TUYỆT ĐỐI** — nội dung, hạng mục, khối lượng, cờ đặc biệt, sản lượng, hòa vốn, chênh lệch của cả 3 dòng |
| Chạy phục hồi lần 2 | Vẫn 3 việc, không nhân bản — **idempotent** |

Công cụ phục hồi **cố ý không tự kết nối và không tự chạy**: nó chỉ in ra SQL trong `begin/commit`
với `ON_ERROR_STOP` để người có quyền đọc lại rồi tự chạy. Nếu file backup thiếu cột bắt buộc
(file do bản cũ sinh ra), script dừng và nói rõ file đó không phục hồi đầy đủ được.


## F2c. Apply lên STAGING và lỗi chặn triển khai phát hiện tại đó

- Project: `kpi-vincons-staging`, ref `wqnq…vxau`, vùng `ap-southeast-1`, tạo 10/08/2026, Postgres 17.6.1.
- Đã link. Project `uxmj…uoub` (Sydney) trong cùng tài khoản **không bị đụng tới**.
- Người dùng chạy `db push --include-seed`: **32/32 migration 001→035 áp thành công**, seed chạy xong.

### 🔴 Frontend không đọc được dữ liệu trên cloud — chặn triển khai (migration 036)

Ngay sau khi apply, kiểm tra qua Data API cho thấy `authenticated` **không có quyền nào** trên
bảng `public`. Frontend đọc thẳng 4 bảng (không qua RPC):

| Nơi gọi | Bảng | Thao tác |
|---|---|---|
| `KpiApp.tsx:61` | `teams` | select |
| `KpiApp.tsx:62` | `workers` | select + embed `teams` |
| `KpiApp.tsx:64` | `work_weeks` | select + embed `teams` |
| `KpiApp.tsx:77` | `profiles` | select + embed `workers`→`teams` |
| `KpiApp.tsx:160` | `teams` | **update** `is_active` (nút "Kích Hoạt Tổ") |

Supabase cloud hiện nay **không tự cấp quyền Data API cho bảng mới** trong `public`
(đúng như ghi chú `auto_expose_new_tables` trong `config.toml`), và **không migration nào cấp quyền**
các bảng này. Hệ quả trên staging: mọi lệnh đọc trên trả **401**, ứng dụng không tải nổi
danh sách Tổ, công nhân, tuần hay hồ sơ người dùng.

**Vì sao chạy cục bộ không lộ ra:** image Postgres của Supabase CLI vẫn giữ hành vi cũ —
`authenticated` được cấp sẵn **SELECT, INSERT, UPDATE, DELETE, TRUNCATE trên mọi bảng public**.
Môi trường cục bộ **rộng quyền hơn** cloud, nên "chạy được ở máy" không chứng minh quyền đã đúng.

**Migration 036 không sao chép hành vi cục bộ.** Nó thu hồi sạch rồi cấp đúng phần cần:

```
revoke all on all tables in schema public from anon, authenticated;
grant select on teams, workers, work_weeks, profiles to authenticated;
grant update (is_active, updated_at, updated_by) on teams to authenticated;
```

anon không được cấp gì. Mọi bảng khác chỉ truy cập được qua RPC SECURITY DEFINER.

### Kiểm chứng sau khi áp 036 tại chỗ (mô phỏng đúng thế quyền của cloud)

| Kịch bản | Kỳ vọng | Kết quả |
|---|---|---|
| Đọc `teams` / `workers` / `work_weeks` / `profiles` | Được, RLS lọc dòng | **PASS** (2 / 3 / 4 / 3 dòng) |
| Đọc `jobs`, `price_items` trực tiếp | **Bị chặn** | **PASS** (403) |
| Ghi `teams.is_active` | Được | **PASS** (204) |
| Ghi `teams.leader_name` | **Bị chặn** | **PASS** (403 — quyền cấp theo CỘT) |
| `anon` (chưa đăng nhập) đọc bảng nghiệp vụ | Bị chặn | **PASS** (401) |
| `anon` gọi RPC | Bị chặn | **PASS** (401) |
| 6 RPC chính sau khi siết quyền | Chạy bình thường | **PASS** (get_my_access, get_job_metrics, get_catalog_cap1, get_shared_work_weeks, get_payroll_summary, preview_job_metrics) |
| Ứng dụng sau khi siết quyền | Đăng nhập, nhận vai trò, hiện menu Quản Trị | **PASS** |

Kết quả: thế quyền sau 036 **chặt hơn** cả môi trường cục bộ trước đó.

## F3. Chưa kiểm thử ở bước này

Các mục sau **chỉ chạy được sau khi có staging thật + có dữ liệu giả đầy đủ**, chưa PASS:

- **Bản in PDF với nội dung dài**: đã đối chiếu cấu trúc cột với PGV_MAU.xlsx, nhưng chưa in thử nội dung dài để xem có bị cắt chữ không.
- **Tải đồng thời**: chưa chạy nhiều phiên song song; chưa đo p95 RPC, deadlock, connection saturation.
- **Quân số nhiều mã nhóm**: đã kiểm ở tầng unit test; chưa dựng dữ liệu nhiều nhóm trên giao diện để đối chiếu số.
- **Reset mật khẩu / hết hạn phiên**: chưa chạy (cần SMTP thật ở staging).

## G. Rollback

Dry-run này không tạo tài nguyên đám mây nào. Dọn sạch bằng:

```bash
npx supabase@2.113.0 stop --no-backup
```
