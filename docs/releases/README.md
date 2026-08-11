# Phiếu phiên bản

Mỗi lần cắt phiên bản, `scripts/kpi_release.ps1` ghi một file `X.Y.Z.md` vào thư mục này.
Trong đó có tag Git, commit, tên điểm khôi phục và **mã version của Cloudflare Worker**.

Mã version của Worker là thứ dễ mất nhất: nó chỉ hiện ra lúc deploy, và `wrangler rollback`
cần đúng nó để đưa bản web về. Ghi lại ngay, đừng để tìm sau.

Quy trình đầy đủ ở [../VERSIONING.md](../VERSIONING.md).

---

## Bản đang chạy trên staging (chưa cắt phiên bản)

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
