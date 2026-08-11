# Điểm khôi phục: release-1-0-1-1

| | |
|---|---|
| Tạo lúc | 2026-08-11T14:06:52+07:00 |
| Môi trường | staging |
| Git commit | `bf5c89b87d5741789167180a7c83c788b3bdde4d` |
| Nhánh | main |
| Tag | `v1.0.1.1` |
| File dump | `kpi_staging_20260811-140637.dump` |
| SHA-256 | `7403b751df1f10974e2851e4e751861b6d0a73e33eeaf90c6f2d9795d97b9e10` |
| Migration đã chạy | 001,002,003,004,005,006,010,011,012,013,014,015,016,017,018,019,020,021,022,023,024,025,026,027,028,029,030,031,032,033,034,035,036,037,038,039,040,041,042,043,044 |

Số liệu tại thời điểm chụp — dùng để đối chiếu SAU KHI khôi phục:

| Bảng | Số dòng |
|---|---|
| Tổ | 89 |
| Công nhân | 1775 |
| Việc đã giao | 2 |
| Dòng đơn giá đang dùng | 8893 |
| Tuần đang mở | 3 |
| Tài khoản đang hoạt động | 1 |

## Cách quay lại điểm này

**Trường hợp 1 — chỉ dữ liệu sai, cấu trúc bảng không đổi.**
Thường gặp: nhập nhầm file đơn giá, xóa nhầm việc, sửa hỏng danh sách công nhân.

```
git checkout bf5c89b87d5741789167180a7c83c788b3bdde4d
.\backup\kpi_restore.ps1 -DumpFile <thu-muc>\kpi_staging_20260811-140637.dump -ConfirmLabel staging -Execute
```

Nạp xong phải mở ứng dụng đối chiếu đúng các con số trong bảng trên rồi mới coi là xong.

**Trường hợp 2 — đã chạy thêm migration sau thời điểm này, cấu trúc bảng đã đổi.**
kpi_restore.ps1 dùng `--data-only` nên KHÔNG đưa cấu trúc bảng về như cũ, và hệ thống
không có migration lùi. Hai đường:

* *Chắc chắn* — tạo project Supabase MỚI, chạy migration tới đúng mốc 044,
  rồi nạp dump vào đó. Đây là bản sao đúng nguyên trạng, đổi lại phải trỏ ứng dụng sang
  project mới.
* *Nhanh* — viết một migration mới đảo ngược thay đổi. Nhanh hơn nhưng phải tự kiểm
  chứng từng thứ, và với thay đổi lớn thì dễ sót.

## Điểm này KHÔNG chứa

* **Tài khoản đăng nhập.** Schema `auth` cố tình không sao lưu vì trong đó có mã băm
  mật khẩu; để ngoài file backup thì an toàn hơn. Mất project là phải mời lại người dùng.
* **File trong Storage**, gồm cả Excel lưu khi xóa tuần. Phải tải riêng.
* **Mọi thay đổi xảy ra sau 2026-08-11T14:06:52+07:00.** Khôi phục là mất hẳn phần đó, không lấy lại được.
