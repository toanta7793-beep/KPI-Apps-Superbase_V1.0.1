# Phần mở rộng: Đánh giá sản lượng — tổng hợp phạm vi và đánh giá hệ thống

Cập nhật 11/08/2026. Tài liệu này gom lại toàn bộ phần **dự kiến mở rộng** và **đánh giá
hiện trạng hệ thống**. Phần mở rộng CHƯA thực thi, theo đúng yêu cầu.

---

## 1. Những gì đã xong (không còn nằm trong phần dự kiến)

| Nội dung | Migration / commit |
|---|---|
| Gộp mã nhóm không còn bắt trùng vị trí | 041 |
| Hạng mục Cấp 1 rỗng tự ngừng dùng | 040 |
| Bản in PGV không cắt nội dung dài, tỉ lệ cột theo mẫu | `downloadPgvPdf.ts`, `kpi.css` |
| Quân số tính đúng khi có nhiều mã nhóm | đã kiểm chứng trên giao diện |
| Đơn giá trùng: chỉ trùng khi cùng cả giá | 037 |
| KPI tính theo tuần, có bộ lọc Tuần 1–4 | 042 |
| Việc chưa gộp tuần bị loại khỏi KPI | 042 |
| Quỹ lương tính theo số ngày của cả tuần | 043 |
| Giám sát xem được KPI các tổ mình phụ trách | 044 |
| Quy trình cắt phiên bản và quay về phiên bản cũ | [VERSIONING.md](VERSIONING.md) |

---

## 2. Phạm vi phần "Đánh giá sản lượng" — đã chốt

Các điểm dưới đây đã được người dùng xác nhận, không cần hỏi lại.

**Nhập liệu.** Cuối ngày tổ trưởng ghi khối lượng hoàn thành **theo từng dòng việc** —
một con số cho mỗi việc mỗi ngày. Không nhập theo từng công nhân như phiếu CNCH.

**Công thức lũy kế.**

| Chỉ tiêu | Cách tính |
|---|---|
| Lũy kế khối lượng | cộng dồn khối lượng nhập mỗi ngày của việc đó |
| Lũy kế thành tiền | lũy kế khối lượng × đơn giá tính toán của việc |
| Lũy kế (%) | lũy kế khối lượng ÷ **khối lượng giao của việc** (ở Mục tiêu hoàn thành tổng) |

**Khóa số liệu.** Khi lưu, hiện hộp thoại "Anh chắc chắn chưa? Lưu rồi sẽ không sửa lại
được nữa" với hai lựa chọn Đồng ý / Kiểm tra lại. Đồng ý là **khóa dòng**. Chỉ **Admin**
mở khóa sửa lại được. **Không lưu lịch sử sửa đổi.**

**KPI.** Thêm cột **Sản lượng thực tế** = tổng lũy kế thành tiền của tuần đó. Nó có chỉ
báo **riêng, độc lập** với chỉ báo lãi/lỗ cũ: so Sản lượng thực tế với Sản lượng (kế
hoạch), âm thì đỏ, bằng hoặc dương thì xanh. Cột Chênh lệch cũ giữ nguyên ý nghĩa.

**Phân quyền xem.** Giám sát chỉ xem các tổ được giao quản lý. Tổ trưởng chỉ xem đúng tổ
mình. Admin xem tất cả.

**Xuất Excel.** *Đã đổi so với đề xuất ban đầu:* **bỏ** nút xuất ở màn Đánh giá sản lượng,
chỉ để **một** nút ở màn **Đánh giá KPI theo tuần**. Admin xuất được tất cả tổ, giám sát
chỉ xuất các tổ mình quản lý, tổ trưởng không cần.

**Vòng đời dữ liệu.** Sản lượng theo ngày giữ lại khi sang ngày mới. Chỉ bị xóa khi dữ
liệu giao việc của tuần đó bị xóa.

---

## 3. Những thứ database chưa có — phải làm mới

> Đã rà lại 11/08/2026 sau khi đọc `danhgiasanluong.xlsx` và mã nguồn bản in.
> **Còn hai, không phải ba.** Bản mô tả đầy đủ: [PHASE2_DANH_GIA_SAN_LUONG_SPEC.md](PHASE2_DANH_GIA_SAN_LUONG_SPEC.md).

| Báo cáo cần | Hiện trạng |
|---|---|
| ~~"Mục tiêu hoàn thành" theo từng việc~~ | **ĐÁNH GIÁ NÀY SAI, đã sửa 11/08/2026.** Nó có sẵn: cột 8 của PGV chung đang in `jobs.quantity` + đơn vị. Tôi đã kết luận là "để trống, viết tay" mà không đọc mã nguồn bản in. Không phải làm mới. |
| **Phân khu tách khỏi Vị trí chi tiết** | Chỉ có một trường `jobs.location`. Bản in đang lấy cùng một trường cho cả hai cột. |
| **Khối lượng hoàn thành theo NGÀY** | Không tồn tại. `assignments.completed_qty` là kiểu **chữ**, theo từng công nhân, và chỉ giữ trạng thái hiện hành — không phải lịch sử theo ngày, không cộng dồn được. |

Hai thứ còn lại vẫn phải làm mới hoàn toàn. Phần 2 vẫn là phân hệ thứ hai của hệ thống,
chỉ là nhẹ hơn ước lượng ban đầu một phần.

---

## 4. Khối lượng công việc ước lượng

Đây là **phân hệ thứ hai** của hệ thống, ngang tầm phần Giao việc hiện có:

* 1–2 bảng mới (sản lượng theo ngày; mục tiêu hoàn thành theo việc)
* 4–5 hàm RPC (nhập, khóa, mở khóa, tổng hợp, xuất)
* 1 màn hình mới + sửa màn KPI
* 1 chức năng xuất Excel (hiện hệ thống **chưa có** nút xuất Excel nào — xem mục 6)
* Kéo theo sửa: luồng xóa tuần, phân quyền, sao lưu

---

## 5. Rủi ro và việc cần quyết trước khi làm

### 5.1 Luồng xóa tuần sẽ trở thành sao lưu thiếu — phải sửa cùng lúc

Quy tắc nghiệp vụ bắt buộc: xóa tuần phải **sao lưu → lưu trữ → kiểm chứng → xóa**, hỏng
bất kỳ bước nào là không được xóa. File Excel lưu trữ hiện chỉ chứa dữ liệu giao việc.

Nếu thêm bảng sản lượng theo ngày mà **không** đưa vào file lưu trữ, thì xóa tuần sẽ xóa
mất sản lượng đã nhập **mà không có bản sao nào**. Đây đúng là loại lỗi đã từng xảy ra
một lần trong dự án này (backup thiếu cột `is_special_labor`). Phải làm cùng lúc, không
để lại sau.

### 5.2 Khóa không lưu lịch sử — hệ quả cần biết trước

Người dùng đã chọn không lưu lịch sử sửa đổi. Hệ quả: **Admin có thể sửa số sản lượng đã
dùng để tính KPI mà không để lại dấu vết nào.** Với một Admin duy nhất là chấp nhận được;
nếu sau này có nhiều Admin thì nên xem lại. Ghi ở đây để sau này không ai bất ngờ.

### 5.3 Hai câu hỏi — đã trả lời 11/08/2026

**(a) Giám sát có được xem màn hình KPI không? → CÓ, chỉ tổ mình phụ trách.**
Đã làm ở migration 044. Admin xem tất cả, giám sát xem các tổ có trong `profile_teams`,
các vai trò còn lại vẫn không xem được. Phạm vi do database quyết định, giao diện không
lọc lại. Riêng phần **xuất Excel** người dùng sẽ bàn sau ở bài toán phát triển tiếp.

**(b) Các tổ có bao giờ chạy tuần lệch ngày nhau không? → KHÔNG BAO GIỜ.**
Admin đặt sẵn tuần cho toàn công ty, mọi tổ chạy cùng một khoảng ngày. Vì vậy thiết kế
hiện tại — 4 ô tuần dùng chung cho tất cả các tổ — là **đúng với thực tế vận hành**, không
phải hạn chế cần khắc phục. Rủi ro này coi như đóng.

Hệ quả kèm theo: quỹ lương tính theo số ngày của tuần (migration 043) là đồng nhất cho mọi
tổ, không có trường hợp hai tổ cùng tuần mà khác số ngày.

---

## 6. Đánh giá hiện trạng hệ thống

### Đang vững

| Mặt | Hiện trạng |
|---|---|
| Phân quyền | RBAC + RLS ở tầng database, không phụ thuộc giao diện. Lỗ hổng vai trò rỗng đã bịt (035). |
| Dữ liệu ra vào | Nhập Excel có kiểm tra trước khi ghi, hỏng thì giữ nguyên dữ liệu cũ. |
| Quy tắc nghiệp vụ | Ràng buộc ở tầng database (không chồng tuần, tối đa 9 ngày, không loại việc đã giao ra khỏi tuần), không thể lách bằng giao diện. |
| Bản in | PGV chung và PGV CNCH đã kiểm chứng không cắt nội dung, tỉ lệ cột theo mẫu. |
| Sao lưu | Có script sao lưu + khôi phục, đã diễn tập thật một lần và đã sửa 4 lỗi phát hiện trong lúc diễn tập. |
| Hiệu năng | Bảng lương đã xử lý timeout (039). 50 phiên đồng thời chạy sạch. |

### Điểm yếu đã biết

| Điểm yếu | Mức | Ghi chú |
|---|---|---|
| **Không có PITR** | Cao | Không mua gói Pro nên không quay lại được thời điểm bất kỳ. Chỉ quay về được các mốc **tự chụp bằng tay**. Giữa hai mốc là mất. |
| **Không có migration lùi cho 001–044** | Trung bình | Đây là mốc nền, chấp nhận được. Từ **045 trở đi bắt buộc có script hoàn tác**, `kpi_release.ps1` không cho cắt phiên bản nếu thiếu. Xem [VERSIONING.md](VERSIONING.md). |
| **Tài khoản đăng nhập không được sao lưu** | Trung bình | Cố ý (tránh để mã băm mật khẩu trong file backup). Mất project là phải mời lại toàn bộ người dùng. |
| ~~4 ô tuần dùng chung cho 89 tổ~~ | — | **Đã đóng.** Các tổ không bao giờ chạy lệch tuần, nên đây là thiết kế đúng chứ không phải hạn chế. |
| **Hai Admin sửa cùng ô tuần** | Thấp | Không loạn dữ liệu (có khóa xử lý), nhưng **người sau đè người trước, không cảnh báo**. Chỉ thành vấn đề khi có nhiều hơn một Admin. |
| ~~Màn KPI chỉ Admin xem được~~ | — | **Đã xử lý** ở migration 044: giám sát xem được KPI các tổ mình phụ trách. |
| **Staging đang chứa dữ liệu thật** | Trung bình | 89 tổ, 1000 công nhân thật. Thử nghiệm trên đó là thử trên dữ liệu thật. |
| **Chưa có production** | — | Đúng kế hoạch. Chưa được phép cutover khi chưa có UAT PASS và phê duyệt. |

---

## 7. Thứ tự đề nghị khi bắt tay làm phần 2

1. ~~Trả lời hai câu hỏi ở 5.3~~ — đã trả lời 11/08/2026.
2. Thêm trường "Mục tiêu hoàn thành" theo việc + tách Phân khu / Vị trí chi tiết.
   Làm trước vì cả báo cáo lẫn bản in đều phụ thuộc.
3. Bảng sản lượng theo ngày + khóa sau xác nhận.
4. **Cùng lúc** sửa luồng xóa tuần để file lưu trữ bao gồm sản lượng (5.1).
5. Màn "Đánh giá sản lượng" + phân quyền xem theo tổ.
6. Cột "Sản lượng thực tế" trong KPI.
7. Xuất Excel ở màn KPI theo tuần.
