# Phiếu phiên bản

Mỗi lần cắt phiên bản, `scripts/kpi_release.ps1` ghi một file `X.Y.Z.md` vào thư mục này.
Trong đó có tag Git, commit, tên điểm khôi phục và **mã version của Cloudflare Worker**.

Mã version của Worker là thứ dễ mất nhất: nó chỉ hiện ra lúc deploy, và `wrangler rollback`
cần đúng nó để đưa bản web về. Ghi lại ngay, đừng để tìm sau.

Quy trình đầy đủ ở [../VERSIONING.md](../VERSIONING.md).

---

## Bản đang chạy trên staging — ĐANG LỆCH so với v1.0.1

Sau khi cắt v1.0.1 đã deploy thêm **một bản sửa lỗi** (gộp mã nhóm không còn đòi trùng vị
trí ở giao diện). Staging vì vậy **đi trước tag v1.0.1 một commit**, chưa được đặt tên
phiên bản.

| | |
|---|---|
| Cloudflare Worker version | `107f8ac9-9243-491e-ab69-939a4857235d` |
| Nội dung | sửa `validateJobGroup` — chỉ frontend, không có migration |

Cắt thành phiên bản mới khi nào cũng được; vì không có migration nên không cần script hoàn tác.

---

## Bản đã cắt v1.0.1

| | |
|---|---|
| Ngày | 11/08/2026 |
| Commit | `2528f28` |
| Migration cao nhất | 044 |
| Cloudflare Worker version | `b361bf61-a2f1-4929-b579-8940ece284c2` |
| URL | https://kpi-enterprise-platform-web.toanta7793.workers.dev |
| Project Supabase | `kpi-vincons-staging` (`wqnqaqesxohqblsfvxau`) |

Đây là bản dự kiến cắt thành **Ver 1.0.1**. Ghi lại ở đây để mã version của Worker không
bị mất trong lúc chờ cắt phiên bản. Khi cắt, truyền vào script:

```
.\scripts\kpi_release.ps1 -Version 1.0.1 -OutputDir C:\KPI-Backups\staging `
  -WorkerVersionId b361bf61-a2f1-4929-b579-8940ece284c2 -Execute
```
