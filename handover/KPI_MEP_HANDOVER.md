# KPI MEP — Tài liệu bàn giao toàn hệ thống

> Tài liệu này viết cho **một kỹ sư hoặc một trợ lý AI chưa từng biết dự án**. Đọc hết file
> này là đủ để (a) dựng một bản sao độc lập cho dự án khác, hoặc (b) sửa và cải tiến hệ
> thống hiện tại mà không phá vỡ nghiệp vụ.
>
> Trạng thái: đang chạy trên staging. 46 migration, 37 hàm RPC, 23 bảng, 6 view, 29 test.
> Không có production. Ngày lập: 11/08/2026.

---

## PHẦN 0 — Đọc theo thứ tự nào

| Nếu bạn muốn | Đọc mục |
|---|---|
| Hiểu hệ thống làm gì | 1, 2 |
| Sửa/thêm tính năng | 3, 4, 5, 6 |
| Dựng bản sao cho dự án khác | 10 |
| Tránh lặp lại lỗi cũ | **9 — quan trọng nhất** |
| Vận hành, sao lưu, lùi phiên bản | 8 |

---

## PHẦN 1 — Hệ thống này giải quyết bài toán gì

Quản lý **giao việc và định mức KPI cho các tổ đội thi công cơ điện (MEP)** tại công trường.

Bài toán thực tế: một nhà thầu MEP có ~89 tổ đội, mỗi tổ 5–20 công nhân. Mỗi tuần ban chỉ
huy giao việc cho từng tổ. Câu hỏi cần trả lời liên tục là:

1. **Giao việc này có lãi không?** — giá trị sản lượng của việc so với chi phí nhân công bỏ ra.
2. **Tổ này tuần rồi làm ăn thế nào?** — tổng sản lượng so với tổng quỹ lương của cả tuần.
3. **Tổ này làm được bao nhiêu so với đã giao?** — tiến độ thực tế.
4. **In phiếu giao việc** cho tổ trưởng ký nhận, đúng mẫu công ty.

Ba câu đầu là ba **thước đo khác nhau** và hệ thống cố ý không trộn chúng: một tổ có thể có
lãi mà vẫn chậm tiến độ, và ngược lại.

### Từ vựng nghiệp vụ (bắt buộc hiểu đúng)

| Thuật ngữ | Nghĩa | Trong code |
|---|---|---|
| **Tổ** | tổ đội thi công, định danh bằng tên tổ trưởng | `teams`, `leader_name` |
| **Việc** | một dòng giao việc: tổ + khoảng ngày + hạng mục + nội dung + khối lượng + nhân công | `jobs` |
| **Hạng mục Cấp 1 / Cấp 2** | phân cấp danh mục công việc; Cấp 2 mới có đơn giá | `work_categories`, `price_items` |
| **Đơn giá (calc_price)** | tiền trên một đơn vị khối lượng (md, m², kg…) | `price_items.calc_price` |
| **Sản lượng** | khối lượng × đơn giá = giá trị công việc theo **kế hoạch** | `production_value` |
| **Quỹ lương ngày** | tổng lương ngày của nhân công được giao cho việc | `daily_payroll` |
| **Hòa vốn** | khối lượng tối thiểu phải làm để bù chi phí nhân công. **Là KHỐI LƯỢNG, không phải tiền** | `total_breakeven`, `breakeven_daily` |
| **Mã nhóm** | nhiều việc do **cùng một tổ thợ** làm trong cùng khoảng ngày → chi phí nhân công chia **một lần** cho cả nhóm | `group_code` |
| **Tuần** | 1 trong 4 ô tuần dùng chung toàn công ty | `shared_work_weeks`, `work_weeks` |
| **PGV** | Phiếu Giao Việc — bản in cho tổ trưởng ký | `get_pgv_common` |
| **PGV CNCH** | Phiếu giao việc Công Nhân Cơ Hữu hằng ngày, theo từng người | `get_pgv_cnch` |
| **Lao động đặc biệt** | Đào tạo / Phát sinh: khối lượng = số người × số ngày, đơn giá = lương ngày ÷ số người | `is_special_labor` |

---

## PHẦN 2 — Mười hai quy tắc nghiệp vụ không được phá

Đây là phần quan trọng nhất khi sửa hệ thống. Vi phạm bất kỳ điều nào là sai nghiệp vụ,
không phải sai kỹ thuật.

1. **Ngày tháng**: giao diện luôn dd/mm/yyyy, database luôn ISO. Ngày nhập nhập nhằng
   (ví dụ 03/04) phải **từ chối**, không được đoán.
2. **Tuần**: đúng 4 ô tuần dùng chung, tối đa 9 ngày mỗi tuần (bao gồm hai đầu), **không
   chồng ngày nhau**, sửa được. Chỉ ADMIN tạo/sửa tuần.
3. **Sửa tuần không được đẩy việc đã giao ra ngoài tuần** → `EDIT_WOULD_EXCLUDE_ASSIGNED_JOB`.
4. **Tìm việc Cấp 2 không dấu**: gõ "ong" phải ra "ống". Tách token, bỏ dấu.
5. **Xem trước hòa vốn trước khi lưu**: người giao việc phải thấy lãi/lỗ dự kiến trước khi
   bấm lưu (`preview_job_metrics`).
6. **Gộp mã nhóm không được làm mất dòng trên phiếu in PGV.**
7. **PGV chung lấy TẤT CẢ việc của tổ trong tuần**, số dòng vượt quá 6 vẫn phải in đủ.
8. **PGV CNCH** dùng ngày nhận việc; ngày giao việc = ngày nhận − 1.
9. **Quân số**: dòng không có mã nhóm tính một lần; các dòng **cùng mã nhóm chỉ tính chung
   một cơ cấu nhân sự**; **tổ trưởng không tính vào quân số**.
10. **Xóa tuần** phải **sao lưu → lưu trữ → kiểm chứng → xóa**. Hỏng bất kỳ bước nào là
    **không được xóa**.
11. **Gộp mã nhóm KHÔNG cần trùng vị trí** (một tổ có thể làm hai chỗ trong một ngày), nhưng
    mọi việc **phải có** vị trí, phải cùng tổ, cùng ngày, cùng cơ cấu nhân sự.
12. **KPI tính theo tuần**; quỹ lương tính theo **số ngày của cả tuần**, không phải số ngày
    có việc; việc chưa gộp vào tuần nào bị **loại khỏi KPI**.

---

## PHẦN 3 — Kiến trúc

```
┌─────────────────────────────────────────────┐
│  Frontend: Vinext (Next-like) + Vite +      │
│  React + TypeScript, chạy trên              │
│  Cloudflare Workers                          │
│  → CHỈ gọi RPC. Không viết SQL. Không tự lọc │
│    quyền.                                    │
├─────────────────────────────────────────────┤
│  PostgREST (Supabase)                        │
│  → phơi các hàm public.* thành HTTP RPC      │
├─────────────────────────────────────────────┤
│  PostgreSQL 17 (Supabase)                    │
│  → TOÀN BỘ nghiệp vụ, quyền, ràng buộc       │
│    nằm ở đây                                 │
└─────────────────────────────────────────────┘
```

### Nguyên tắc kiến trúc số một

> **Mọi quy tắc nghiệp vụ và mọi kiểm tra quyền nằm ở tầng database.**
> Giao diện chỉ hỏi và hiển thị.

Lý do: giao diện có thể bị bỏ qua (gọi API trực tiếp), và một quy tắc viết ở hai nơi sẽ lệch
nhau sau vài lần sửa. Dự án này đã trả giá đúng hai lần vì vi phạm điều đó — xem mục 9.

Hệ quả cụ thể:
* Frontend **không bao giờ** lọc danh sách theo vai trò. Nếu database trả về, tức là được phép xem.
* Mọi bảng nghiệp vụ mới **không cấp quyền trực tiếp** cho `authenticated`; truy cập qua hàm
  `security definer`.

### Cấu trúc thư mục

```
supabase/migrations/     46 file, chạy tiến, đánh số 001→049
supabase/rollback/       script hoàn tác, BẮT BUỘC từ 045 trở đi
web/app/                 màn hình React (12 file .tsx)
web/lib/                 tiện ích: xlsx, pdf, supabase client
web/tests/               29 test node:test, chạy bằng npm run test
backup/                  script sao lưu / khôi phục / điểm khôi phục (PowerShell)
scripts/                 script cắt phiên bản, đóng gói bàn giao
docs/                    tài liệu nghiệp vụ và vận hành
uat/                     nhật ký nghiệm thu, bằng chứng
```

---

## PHẦN 4 — Mô hình dữ liệu

### Nhóm danh mục
| Bảng | Vai trò |
|---|---|
| `teams` | tổ đội. `leader_name` là tên hiển thị của tổ |
| `workers` | công nhân, thuộc một tổ, có `mnv` (mã nhân viên) |
| `work_categories` | hạng mục Cấp 1 |
| `price_items` | dòng đơn giá Cấp 2: `category_name` + `content` + `unit` + `calc_price` |
| `systems`, `salary_grades`, `salary_standards` | hệ / bậc / bảng lương tháng |
| `roles` | ADMIN, GIAM_SAT, TO_TRUONG, NHAN_VIEN, XEM |

### Nhóm vận hành
| Bảng | Vai trò |
|---|---|
| `jobs` | **bảng trung tâm**: việc đã giao |
| `shared_work_weeks` | 4 ô tuần dùng chung |
| `work_weeks` | bản sao tuần cho từng tổ (`shared_work_weeks` đổ xuống) |
| `assignments` | phân công từng công nhân cho phiếu CNCH |
| `job_daily_production` | **sản lượng theo ngày** (phần 2) |

### Nhóm phân quyền
| Bảng | Vai trò |
|---|---|
| `profiles` | hồ sơ người dùng, nối `auth.users` ↔ vai trò |
| `profile_teams` | gán người dùng ↔ các tổ được xem (dùng cho GIAM_SAT và TO_TRUONG) |

### Nhóm lịch sử / lưu trữ
`job_history`, `job_daily_production_history`, `week_archive_operations`,
`pgv_save_operations`, `pgv_print_log`, và 3 bảng `app.*_import_backups`.

### Sáu view — trái tim tính toán

| View | Vai trò |
|---|---|
| `app.v_worker_salary` | lương ngày của từng công nhân (lương tháng ÷ 26) |
| `app.v_team_payroll` | quỹ lương ngày của tổ, đếm người chưa xác định được lương |
| **`app.v_job_metrics`** | **quan trọng nhất** — mọi con số của một việc |
| `app.v_job_production` | rút gọn cho KPI, kèm `week_id`/`week_slot` |
| `app.v_job_actual_production` | lũy kế sản lượng thực tế của từng việc |
| `app.v_kpi_evaluation` | (kế thừa, KPI hiện tính trong hàm) |

### `app.v_job_metrics` — đọc kỹ trước khi sửa bất cứ thứ gì về tiền

Chuỗi CTE: `role_avg → priced → production → valued → allocated → select`.

```
work_days        = end_date − start_date + 1
daily_payroll    = Σ (số người bậc i × lương ngày trung bình bậc i của tổ)
unit_price       = nếu lao động đặc biệt: daily_payroll ÷ tổng số người
                   nếu không: calc_price của dòng đơn giá khớp DUY NHẤT
production_value = quantity × unit_price

group_key        = nếu không có mã nhóm: id của việc
                   nếu có: team_id ‡ group_code ‡ start ‡ end ‡ (5 cột nhân sự)
                   ⚠ KHÔNG có location — xem lỗi #6 mục 9
group_value      = Σ production_value trong cùng group_key
allocated_daily_payroll = daily_payroll × production_value ÷ group_value
total_breakeven  = allocated_daily_payroll ÷ unit_price × work_days   ← KHỐI LƯỢNG
actual_labor_cost= allocated_daily_payroll × work_days                ← TIỀN
difference       = production_value − actual_labor_cost
```

**Cạm bẫy**: `total_breakeven` và `breakeven_daily` là **khối lượng** (md, m²…), không phải
tiền. Đưa qua bộ định dạng VNĐ là sai — lỗi này đã từng xảy ra.

**Vì sao giữ ngày và cơ cấu nhân sự trong `group_key`**: công thức phân bổ chỉ đúng khi mọi
dòng trong nhóm có cùng `daily_payroll`. Nếu dữ liệu lệch, tách nhóm ra thì tính **thừa**
chi phí và thấy ngay; gộp bừa thì tính **thiếu** và không ai biết. Chọn cái sai an toàn hơn.

---

## PHẦN 5 — Danh mục 37 hàm RPC

| Nhóm | Hàm |
|---|---|
| Danh tính | `get_my_access`, `get_my_identity`, `admin_list_profiles`, `admin_set_profile` |
| Danh mục | `get_teams_catalog`, `get_workers_catalog`, `get_catalog_cap1`, `get_catalog_cap2` |
| Nhập Excel | `admin_import_price_catalog`, `admin_import_salary_standard`, `admin_import_worker_roster(_v2)` |
| Nhân sự | `admin_save_worker`, `admin_archive_worker`, `get_payroll_summary` |
| Giao việc | `create_job`, `update_job`, `preview_job_metrics`, `get_job_metrics` |
| Mã nhóm | `create_job_group`, `remove_job_group`, `remove_job_groups` |
| Tuần | `create_work_week`, `upsert_shared_work_week`, `get_shared_work_weeks`, `assign_jobs_to_shared_week`, `assign_jobs_to_week`, `unassign_jobs_from_week` |
| Xóa tuần | `prepare_week_archive`, `finalize_week_archive` |
| Phiếu in | `get_pgv_common`, `get_pgv_cnch`, `save_pgv_cnch_assignments` |
| KPI | `get_kpi_evaluation` |
| **Sản lượng** | `save_daily_production`, `unlock_daily_production`, `get_production_evaluation` |

### Khuôn mẫu bắt buộc khi viết hàm mới

```sql
create or replace function public.ten_ham(...)
returns ... language plpgsql [stable] security definer set search_path = '' as $$
declare v_allowed uuid[];
begin
  -- 1. Kiểm vai trò TRƯỚC
  if app.current_role() not in ('ADMIN','GIAM_SAT') then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  -- 2. Chốt phạm vi tổ vào MẢNG, không gọi can_access_team trong where
  select coalesce(array_agg(t.id),'{}'::uuid[]) into v_allowed
  from public.teams t
  where t.deleted_at is null and t.is_active and app.can_access_team(t.id);
  if array_length(v_allowed,1) is null then return; end if;

  -- 3. Truy vấn, lọc bằng = any(v_allowed)
end $$;

revoke execute on function public.ten_ham(...) from public, anon;
grant  execute on function public.ten_ham(...) to authenticated;
notify pgrst, 'reload schema';
```

Ba dòng cuối **bắt buộc**. Thiếu `notify` thì PostgREST không thấy hàm mới.

---

## PHẦN 6 — Mô hình bảo mật

### Vai trò
`ADMIN` (toàn quyền) · `GIAM_SAT` (các tổ được gán) · `TO_TRUONG` (tổ mình) ·
`NHAN_VIEN` (bản thân) · `XEM` (chỉ đọc).

### Hai hàm nền

```sql
app.current_role()      -- vai trò của người đang gọi, TRẢ VỀ '' nếu không có hồ sơ
app.can_access_team(id) -- true nếu ADMIN, hoặc có trong profile_teams,
                        -- hoặc là TO_TRUONG/NHAN_VIEN thuộc tổ đó qua worker_id
```

`can_access_team` cho qua bằng **hai đường**: `profile_teams` **hoặc** `worker_id → team`.
Kiểm tra quyền mà chỉ nhìn một đường là kết luận sai.

### Quy tắc sống còn

`app.current_role()` phải `coalesce(..., '')` — **không bao giờ trả NULL**. Trong SQL,
`NULL <> 'ADMIN'` cho ra NULL chứ không phải TRUE, nên mọi câu `if role <> 'ADMIN' then
raise` sẽ **không chạy** với người dùng chưa có hồ sơ. Lỗi này đã xảy ra thật (migration
035) và cho phép ghi vào bảng đơn giá bằng tài khoản không có hồ sơ.

### Ba lớp
1. `revoke all on all tables in schema public from anon, authenticated`
2. RLS bật trên mọi bảng; bảng mới bật RLS **không có policy nào** → chỉ vào được qua RPC
3. Hàm `security definer` với `set search_path = ''` (mọi tên bảng ghi đủ schema)

### Cấp quyền Data API
Supabase cloud **không tự** phơi bảng `public` mới cho Data API. Bảng nào frontend đọc trực
tiếp (`teams`, `workers`, `work_weeks`, `profiles`) phải `grant select` tường minh
(migration 036).

---

## PHẦN 7 — Hiệu năng khi nhiều người dùng cùng lúc

Đã kiểm 50 phiên đồng thời chạy sạch.

### Bài học lớn nhất: predicate pushdown

Gọi một **hàm** trong mệnh đề `where` chặn bộ tối ưu đẩy điều kiện lọc xuống dưới. Với
`get_payroll_summary`, việc gọi `app.can_access_team(team_id)` trong `where` khiến toàn bộ
1000 công nhân bị quét cho mọi tổ → **timeout**.

Cách sửa (migration 039): chốt danh sách tổ vào `uuid[]` **trước**, rồi lọc bằng
`= any(v_allowed)` — điều kiện trở thành hằng số và đẩy xuống được.

> Cảnh báo thật từ dự án: một bản tối ưu khác (038) nhanh 35% ở máy cục bộ nhưng **không cải
> thiện gì** trên staging. Chỉ đo trên môi trường thật mới tính.

### Các nguyên tắc khác
* Truy vấn tương quan theo từng dòng (`correlated subquery` cho mỗi công nhân) là nguyên
  nhân chậm phổ biến nhất — gom thành `join` + `group by`.
* Chốt phạm vi trước, tổng hợp sau. Đừng tổng hợp rồi mới lọc.
* Đo lặp lại ít nhất 5 lần. Một lần chạy 850 ms có thể là nhiễu; 5 lần sau cho 20–36 ms.
* Frontend không tải "tất cả" theo mặc định: bảng lương mặc định chỉ tải tổ đang chọn, có
  hộp kiểm "Xem tất cả N tổ" và chỉ ADMIN thấy.

---

## PHẦN 8 — Vận hành

### Sao lưu (không mua gói trả phí ⇒ tự quản)
`backup/kpi_backup.ps1` chạy `pg_dump` qua Docker, định dạng custom, kèm SHA-256, xoay vòng
30 bản. **Chỉ sao lưu 5 schema ứng dụng** — dump toàn bộ database KHÔNG khôi phục lại được
vào Supabase (có đối tượng thuộc quyền sở hữu Supabase như `pgrst_drop_watch`).

**Không sao lưu**: tài khoản đăng nhập (schema `auth`, cố ý — chứa mã băm mật khẩu) và file
trong Storage.

### Khôi phục
`backup/kpi_restore.ps1` — `--data-only`, chạy trong **một transaction**, tạm ngưng kiểm tra
khóa ngoại bằng `session_replication_role = replica` (vì `--disable-triggers` cần superuser
mà Supabase không cấp). Mặc định là **chạy thử**, phải thêm `-Execute`.

⚠ **`--data-only` nghĩa là KHÔNG đưa cấu trúc bảng về như cũ.**

### Điểm khôi phục
`backup/kpi_restore_point.ps1` chốt **ba phần** cùng lúc: commit Git + file dump + số dòng
các bảng cốt lõi để đối chiếu sau khi khôi phục. Từ chối chạy khi cây làm việc còn thay đổi
chưa commit.

### Phiên bản và lùi phiên bản
Một phiên bản gồm **bốn thứ**: tag Git · mã version Cloudflare Worker · **script hoàn tác cho
từng migration** · điểm khôi phục.

Thứ ba là thứ duy nhất **không bù lại được sau** — cắt phiên bản xong mới nhớ thì lược đồ đã
đi tiếp. Vì vậy `scripts/kpi_release.ps1` **từ chối cắt phiên bản** khi còn migration sau mốc
nền 044 mà thiếu script hoàn tác.

**Lùi phiên bản: database TRƯỚC, web SAU.** Ngược lại thì bản web cũ chạy trên lược đồ mới —
thường vẫn chạy được, và đó chính là vấn đề: không có tín hiệu nào báo là đang sai.

Đánh số: `X.Y.Z` cho bản có tính năng, `X.Y.Z.W` cho bản sửa lỗi đi sau.

---

## PHẦN 9 — Mười sáu lỗi đã gặp và bài học

**Đây là phần giá trị nhất của tài liệu.** Mỗi mục là một lỗi thật đã tốn thời gian.

### Nhóm A — Bảo mật và đúng đắn

**1. Vai trò NULL vượt qua mọi kiểm tra (nghiêm trọng).** `current_role()` trả NULL cho tài
khoản chưa có hồ sơ; `NULL <> 'ADMIN'` ra NULL nên 29 câu chặn đều không chạy. → luôn
`coalesce(..., '')`.

**2. Cùng một quy tắc viết ở BA nơi.** Quy tắc "gộp nhóm phải trùng vị trí" nằm ở
`create_job_group`, ở `validateJobGroup` (frontend), và ở `group_key` của view. Gỡ ở
database xong tưởng đã xong; frontend vẫn chặn (bản sửa vô tác dụng), rồi view vẫn tính sai
tiền (chi phí nhân công **tính hai lần**, âm thầm). → **sửa quy tắc ở một nơi thì phải rà cả
ba tầng.**

**3. Bản sao lưu thiếu cột.** Backup tuần thiếu `is_special_labor` → khôi phục xong KPI lệch
mà không ai biết. → mỗi khi thêm cột/bảng vào luồng nghiệp vụ, **kiểm luôn đường sao lưu**.

**4. PostgREST `safeupdate`** từ chối `UPDATE` không có `WHERE` cho vai trò `authenticated`.
psql với quyền superuser **không tái hiện được** lỗi này. → thử bằng đúng vai trò thật.

**5. Supabase cloud không tự phơi bảng mới** cho Data API → frontend đọc ra rỗng mà không báo lỗi.

**6. `group_key` chứa `location`** → hai việc cùng mã nhóm khác vị trí rơi vào hai nhóm
khác nhau, mỗi việc gánh trọn quỹ lương. Mã nhóm hiện trên màn hình mà không tác động gì tới
con số. Đo được: 3.076.923 thay vì 1.538.462.

**7. Hiển thị khối lượng bằng định dạng tiền.** "Hòa vốn 619 đ" thật ra là 619 mét dài. Nằm
cạnh hai ô đúng là tiền nên không có gì để lộ ra là sai.

### Nhóm B — Công cụ và môi trường (Windows)

**8. PowerShell 5.1 đọc `.ps1` theo ANSI nếu không có BOM** → tiếng Việt thành lỗi cú pháp.
→ ghi file `.ps1` kèm BOM UTF-8 và `*.ps1 text eol=crlf` trong `.gitattributes`.

**9. `2>&1` với chương trình ngoài** biến stderr thành ErrorRecord và làm `$?` sai. → không dùng.

**10. `Get-Content -Encoding Byte` qua pipeline làm hỏng file nhị phân.** → cho `pg_dump` tự
ghi file trong container, không cho dữ liệu đi qua pipeline PowerShell.

**11. Script báo "Khôi phục xong" trong khi `pg_restore` đã hỏng** — mã thoát lấy từ `psql`
ở cuối ống. → `set -o pipefail`, và dùng `bash` chứ không phải `sh` (sh là dash, không có pipefail).

**12. `setx` ghi biến ở phạm vi User** nhưng cửa sổ đang mở không nạp lại, và
`GetEnvironmentVariable` không truyền scope chỉ đọc phạm vi tiến trình → báo "không tìm thấy
biến" trong khi biến rõ ràng đã đặt. → đọc lần lượt Process → User → Machine.

**13. `core.autocrlf=true` trên Windows** làm hỏng kiểm tra SHA-256 của MANIFEST. →
`.gitattributes` với `eol=lf` và `core.autocrlf=false` cho repo.

### Nhóm C — Cách làm việc

**14. `[auth.email] enable_signup=false` tắt TOÀN BỘ đăng nhập bằng email**, không chỉ tự
đăng ký. Muốn chặn tự đăng ký thì dùng `[auth] enable_signup`.

**15. `supabase config push` ghi đè cấu hình chặt hơn ở remote** (`max_frequency` 1m→1s,
`otp_length` 8→6). → đọc kỹ diff trước khi push cấu hình.

**16. Cổng an toàn suýt thành im lặng.** Bản nháp đầu của KPI theo tuần **lọc bỏ** các tổ có
dữ liệu thiếu ra khỏi kết quả. Người quản lý sẽ không biết bảng đang thiếu tổ — tệ hơn là
không có số. → **thà báo lỗi cả màn hình còn hơn hiển thị một bảng thiếu mà trông vẫn bình thường.**

### Nguyên tắc rút ra

> * Sai theo hướng **ồn ào** (báo lỗi, tính thừa chi phí) chứ đừng sai theo hướng **im lặng**.
> * "Chưa nhập" và "bằng 0" là hai chuyện khác nhau và **phải hiển thị khác nhau**.
> * Một quy tắc chỉ được định nghĩa ở **một nơi**; nếu buộc phải nhân bản thì ghi chú chéo.
> * Kiểm chứng bằng **đúng vai trò thật** và **đúng môi trường thật**.

---

## PHẦN 10 — Dựng bản sao độc lập cho dự án khác

### Nguyên tắc bắt buộc
Không tái sử dụng bất kỳ ref / URL / khóa / project ID / deployment ID / tài khoản / email /
dump nào của hệ thống nguồn. Không đặt secret trong frontend, `NEXT_PUBLIC`, Git hay log.
Trước khi chạy migration phải **in ra tên và ref của project đích và xác nhận đó là project MỚI**.

### Trình tự
1. Tạo project Supabase **mới**. In ra `name` + `ref`, xác nhận.
2. `supabase link` tới project mới. Chạy `supabase db push` (migration 001→049).
3. Sửa danh mục theo dự án mới: tên ứng dụng, công ty, logo, tên dự án. Xem
   `docs/CUSTOMIZATION_CHECKLIST.md`.
4. Nạp danh mục bằng 3 file Excel mẫu trong `templates/`: danh sách công nhân, đơn giá,
   bảng lương. **Không nạp dữ liệu của dự án nguồn.**
5. Tạo tài khoản ADMIN đầu tiên (`uat/grant_first_admin.sql`).
6. Cấu hình frontend: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`
   (khóa publishable là công khai theo thiết kế). `SUPABASE_SECRET_KEY` chỉ đặt ở
   **secret của Worker**, không bao giờ trong mã nguồn.
7. Deploy: `npm run build` rồi `npx wrangler deploy`.
8. Đặt lịch `kpi_backup.ps1` chạy hằng ngày.
9. Chạy `docs/UAT_CHECKLIST.md`. Chỉ cutover production khi **UAT PASS và có phê duyệt rõ ràng**.

### Ba thứ phải sửa lại cho từng dự án
* **Đơn giá** — mỗi công trình một bộ đơn giá riêng.
* **Bảng lương** — hệ/bậc và mức lương theo công ty.
* **Mẫu phiếu in PGV** — bố cục cột đã khớp mẫu VINCONS; công ty khác cần chỉnh
  `PgvPanels.tsx` và `downloadPgvPdf.ts`.

---

## PHẦN 11 — Việc còn dở và rủi ro đã biết

| Việc | Trạng thái |
|---|---|
| Luồng mời tài khoản an toàn + cấu hình SMTP | **chưa làm** — hiện Admin phải tự đặt mật khẩu, trái quy tắc dự án |
| Tài khoản cho 89 tổ trưởng | chưa tạo (đã có 3 tài khoản thử) |
| Xuất Excel báo cáo | chưa làm, để bàn sau |
| Tách Phân khu / Vị trí chi tiết | chưa làm, đã quyết định hoãn |
| Production | chưa có, đúng kế hoạch |
| Hẹn giờ sao lưu tự động | chưa đặt lịch |

| Rủi ro | Mức | Ghi chú |
|---|---|---|
| Không có PITR | Cao | chỉ quay về được các mốc tự chụp bằng tay |
| Không có migration lùi cho 001–044 | Trung bình | mốc nền; từ 045 trở đi bắt buộc |
| Tài khoản đăng nhập không được sao lưu | Trung bình | cố ý; mất project là phải mời lại |
| Khóa sản lượng không lưu lịch sử | Trung bình | Admin sửa số đã dùng tính KPI, không để lại dấu vết |
| Hai Admin sửa cùng ô tuần | Thấp | người sau đè người trước, không cảnh báo |
| Staging chứa dữ liệu thật | Trung bình | 89 tổ, 1775 công nhân thật |

---

## PHẦN 12 — Lệnh hay dùng

```bash
npx supabase start                     # dựng stack cục bộ
npx supabase migration up --local      # áp migration lên máy
npx supabase db push                   # đẩy lên project đã link
npx supabase migration list --linked   # đối chiếu migration local ↔ remote

cd web
npm run test                           # 29 test
npm run lint
npx tsc --noEmit                       # còn 6 lỗi ép kiểu có sẵn, không phát sinh thêm
npm run build && npx wrangler deploy
```

```powershell
.\backup\kpi_backup.ps1        -Label staging -OutputDir C:\KPI-Backups\staging
.\backup\kpi_restore_point.ps1 -Name truoc-khi-doi-X -OutputDir C:\KPI-Backups\staging
.\scripts\kpi_release.ps1      -Version 1.0.2 -OutputDir C:\KPI-Backups\staging -Execute
```
