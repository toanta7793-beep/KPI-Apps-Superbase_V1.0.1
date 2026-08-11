# Cắt phiên bản và quay về phiên bản cũ

Trả lời cho câu hỏi: *"Bản hiện tại là Ver 1.0.1, bản tiếp là Ver 1.0.2, nhưng tôi không
ưng và muốn quay về nguyên trạng Ver 1.0.1."*

---

## Trước hết: "quay về" nghĩa là gì?

Có **hai** thứ khác hẳn nhau, và chọn nhầm là mất việc:

| | Quay về **phiên bản** | Quay về **thời điểm** |
|---|---|---|
| Đưa về cũ | Mã nguồn, giao diện, cấu trúc bảng | Toàn bộ, kể cả dữ liệu |
| Dữ liệu nhập trong lúc chạy 1.0.2 | **GIỮ NGUYÊN** | **MẤT HẾT** |
| Dùng khi | Không ưng tính năng mới | Dữ liệu bị hỏng, nhập sai hàng loạt |
| Công cụ | Tài liệu này | `backup/README.md` mục 7 |

Câu hỏi "không ưng bản 1.0.2, muốn về 1.0.1" gần như luôn là **cột trái**: bỏ tính năng
mới đi, nhưng công việc đã nhập trong tuần vừa rồi phải còn.

Đừng dùng bản khôi phục dữ liệu cho việc này. Nó sẽ xóa mất mọi thứ đã nhập kể từ lúc cắt
phiên bản 1.0.2.

---

## Một phiên bản gồm bốn thứ

Muốn quay về được thì lúc **cắt** phiên bản phải đủ cả bốn. Ba thứ đầu có thể làm sau,
riêng thứ ba thì không:

| | Chốt bằng | Quay về bằng |
|---|---|---|
| 1. Mã nguồn | tag Git `v1.0.1` | `git checkout v1.0.1` |
| 2. Bản web đang chạy | mã version của Cloudflare Worker | `npx wrangler rollback <id>` |
| 3. **Cấu trúc database** | **script hoàn tác từng migration** | chạy ngược từ số lớn xuống |
| 4. Dữ liệu | điểm khôi phục (dump) | chỉ dùng khi muốn về **thời điểm** |

**Thứ 3 là thứ duy nhất không bù lại được sau.** Cắt phiên bản xong mới nhớ ra thì lược đồ
đã đi tiếp, không còn biết chắc bản cũ trông như thế nào. Vì vậy `kpi_release.ps1` **từ
chối cắt phiên bản** khi còn migration thiếu script hoàn tác.

---

## Cắt phiên bản

```
# Xem trước, không ghi gì
.\scripts\kpi_release.ps1 -Version 1.0.2 -OutputDir C:\KPI-Backups\staging

# Làm thật
.\scripts\kpi_release.ps1 -Version 1.0.2 -OutputDir C:\KPI-Backups\staging -Execute
```

Script sẽ dừng nếu: cây làm việc còn thay đổi chưa commit, tag đã tồn tại, còn migration
thiếu script hoàn tác, bộ kiểm thử hỏng, hoặc không tạo được điểm khôi phục.

Sau khi chạy, lấy mã version của Worker và điền vào phiếu phiên bản:

```
cd web; npx wrangler versions list
```

Rồi commit `docs/releases/` và `backup/restore-points/`, và `git push --follow-tags`.

---

## Quay về phiên bản cũ — bốn bước, theo đúng thứ tự

Ví dụ: đang chạy 1.0.2, muốn về 1.0.1.

### Bước 0 — chụp lại hiện trạng trước đã

```
.\backup\kpi_restore_point.ps1 -Name truoc-khi-lui-ve-1-0-1 -OutputDir C:\KPI-Backups\staging
```

Nếu lùi xong thấy còn tệ hơn thì đây là đường về. Bỏ bước này là đi một chiều.

### Bước 1 — lùi cấu trúc database

Chạy script hoàn tác của các migration thuộc 1.0.2, **theo thứ tự ngược**, từ số lớn
xuống số nhỏ. Chạy xuôi sẽ hỏng: hoàn tác 045 trước có thể xóa mất thứ mà 046 đang dựa vào.

```
psql "$env:KPI_BACKUP_DB_URL" -v ON_ERROR_STOP=1 --single-transaction -f supabase/rollback/046_xxx.sql
psql "$env:KPI_BACKUP_DB_URL" -v ON_ERROR_STOP=1 --single-transaction -f supabase/rollback/045_yyy.sql
```

Rồi xóa chúng khỏi sổ migration, nếu không lần `db push` sau sẽ tưởng chúng vẫn đang áp dụng:

```sql
delete from supabase_migrations.schema_migrations where version in ('045','046');
```

### Bước 2 — lùi bản web

```
cd web; npx wrangler rollback <version-id-cua-1.0.1> -m "Lui ve 1.0.1"
```

Mã version nằm trong `docs/releases/1.0.1.md`. Bước này gần như tức thì và luôn đảo ngược được.

### Bước 3 — lùi mã nguồn

```
git checkout v1.0.1
```

Nếu muốn nhánh `main` cũng lùi theo thì tạo một commit đảo ngược (`git revert`), **đừng**
dùng `git reset --hard` trên nhánh đã đẩy lên — người khác đã lấy về sẽ lệch nhau.

### Bước 4 — đối chiếu

Mở ứng dụng, kiểm đúng các con số trong `backup/restore-points/release-1-0-1.md`. Số tổ,
số công nhân, số việc phải **lớn hơn hoặc bằng** lúc cắt phiên bản — dữ liệu nhập thêm
trong lúc chạy 1.0.2 vẫn còn. Nếu **nhỏ hơn** thì có gì đó đã xóa mất dữ liệu; dừng lại,
đừng chạy tiếp.

---

## Thứ tự lùi có quan trọng không?

Có. Lùi **database trước, web sau**.

Bản web 1.0.2 gọi những hàm mà 1.0.1 không có. Nếu lùi web trước thì trong khoảng thời
gian giữa hai bước, bản web cũ đang chạy trên lược đồ mới — thường vẫn chạy được, nhưng
không có gì bảo đảm. Ngược lại, lùi database trước thì bản web mới sẽ báo lỗi rõ ràng
trong vài phút đó, dễ nhận ra hơn nhiều so với một lỗi âm thầm.

Nếu muốn không có phút nào lệch nhau thì phải chấp nhận vài phút ngừng dịch vụ. Với hệ
thống này thì không đáng.

---

## Những gì KHÔNG quay về được

- **Dữ liệu đã bị xóa bởi migration.** Hoàn tác một `drop column` dựng lại cột **rỗng**.
  Nội dung cũ đã đi cùng lần `drop` đầu tiên. Đây là lý do phải tạo điểm khôi phục
  **trước** khi chạy migration có tính hủy.
- **Tài khoản đăng nhập.** Không nằm trong bản sao lưu (cố ý — trong đó có mã băm mật khẩu).
- **File trong Supabase Storage.**
- **Dữ liệu chỉ tồn tại ở bản mới.** Ví dụ 1.0.2 thêm bảng sản lượng theo ngày và tổ
  trưởng đã nhập một tuần; lùi về 1.0.1 là bảng đó biến mất. Điểm khôi phục ở Bước 0 giữ
  lại phần đó, nhưng bản 1.0.1 không có chỗ để hiển thị.

---

## Cách đánh số

`X.Y.Z` cho bản có tính năng mới. `X.Y.Z.W` cho bản sửa lỗi đi sau một phiên bản đã cắt —
ví dụ `1.0.1.1` là bản sửa lỗi của `1.0.1`, để số hiệu `1.0.2` vẫn dành cho bản mở rộng
tiếp theo.

---

## Mốc nền

Migration **001–044** là Ver 1.0.1, không cần script hoàn tác — chúng dựng nên hệ thống
hiện tại và quay về trước 001 không phải tình huống có thật. Từ **045** trở đi bắt buộc.
