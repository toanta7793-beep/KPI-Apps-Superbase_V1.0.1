# Script hoàn tác migration

Thư mục này giữ script **đảo ngược** cho từng migration. Nó tồn tại vì một lý do rất cụ thể:

> Muốn quay từ Ver 1.0.2 về nguyên trạng Ver 1.0.1 thì phải có đường đi ngược.
> Bản sao lưu dữ liệu **không** làm được việc đó — `kpi_restore.ps1` chạy `--data-only`,
> tức chỉ nạp lại các dòng, để nguyên cấu trúc bảng và hàm.

## Quy ước

Mỗi file migration `NNN_ten.sql` phải có một file hoàn tác cùng số: `rollback/NNN_ten.sql`.

Tên phải khớp **cả số lẫn phần chữ**. Script kiểm tra so khớp theo tên file, đặt sai tên
thì coi như thiếu và không cắt phiên bản được.

## Mốc nền: 044

Các migration **001–044** là mốc nền (Ver 1.0.1), **không** cần script hoàn tác. Chúng
dựng nên hệ thống hiện tại; quay về trước 001 không phải một tình huống có thật.

Từ **045 trở đi**, mọi migration đều bắt buộc có script hoàn tác. `kpi_release.ps1`
**từ chối cắt phiên bản** nếu còn thiếu.

## Script hoàn tác phải làm gì

Đưa lược đồ về **đúng** trạng thái trước khi migration chạy — không phải "gần giống".

| Migration làm gì | Hoàn tác phải làm gì |
|---|---|
| `create table` | `drop table` |
| `add column` | `drop column` |
| `create or replace function` | **chép lại nguyên văn bản cũ** của hàm |
| `create or replace view` | chép lại nguyên văn bản cũ của view |
| `drop` một thứ gì đó | dựng lại đầy đủ, kèm quyền và index |

Chỗ dễ sai nhất là `create or replace function`. Không có cách nào tự suy ra bản cũ —
phải **mở file migration trước đó và chép lại**. Ví dụ hoàn tác của 044 chính là nội dung
của 043.

## Điều script hoàn tác KHÔNG làm được

**Dữ liệu đã mất thì không lấy lại được.** Hoàn tác một migration có `drop column` sẽ dựng
lại cột đó **rỗng**. Nếu cột đó từng chứa dữ liệu người dùng nhập, dữ liệu ấy đã đi cùng
lần `drop` đầu tiên.

Vì vậy quy trình bắt buộc là: **tạo điểm khôi phục trước khi chạy migration có tính hủy**
(`drop column`, `drop table`, `delete`, `update` hàng loạt). Xem `backup/README.md` mục 7.

## Cách chạy

Chạy theo **thứ tự ngược**, từ số lớn xuống số nhỏ, và bọc trong một transaction:

```
psql "$KPI_BACKUP_DB_URL" -v ON_ERROR_STOP=1 --single-transaction -f supabase/rollback/046_xxx.sql
psql "$KPI_BACKUP_DB_URL" -v ON_ERROR_STOP=1 --single-transaction -f supabase/rollback/045_yyy.sql
```

Chạy xuôi sẽ hỏng: hoàn tác 045 trước có thể xóa mất thứ mà 046 đang dựa vào.

Sau đó xóa các dòng tương ứng khỏi sổ migration, nếu không lần `db push` sau sẽ tưởng
chúng vẫn đang được áp dụng:

```sql
delete from supabase_migrations.schema_migrations where version in ('045','046');
```
