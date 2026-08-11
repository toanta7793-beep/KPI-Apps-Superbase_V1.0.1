# Đánh giá sản lượng — bản mô tả để duyệt trước khi làm

Lập 11/08/2026. Gom toàn bộ câu trả lời của người dùng thành một bản mô tả đủ chi tiết để
đối chiếu trước khi bắt tay. **Chưa thực thi bất cứ phần nào.**

Cấu trúc bảng dưới đây đọc trực tiếp từ file `danhgiasanluong.xlsx`, không phải suy đoán.

---

## 1. Việc cần làm, nói gọn

Cuối mỗi ngày, tổ trưởng ghi khối lượng đã làm được của từng việc đã giao. Số đó ở lại
vĩnh viễn theo ngày. Hệ thống cộng dồn thành lũy kế, quy ra tiền, tính phần trăm hoàn
thành, và đưa tổng lũy kế thành tiền của tuần sang màn KPI.

---

## 2. Bảng "Đánh giá sản lượng" — 10 cột, theo đúng file Excel

**Phần đầu phiếu:** Dự án · Hạng mục · Bên giao việc · Tổ · Số CN.

| Cột | Tên | Nguồn |
|---|---|---|
| A | STT | đánh số hiển thị |
| B | **Phân khu** | `jobs.location` — cùng giá trị với cột C (quyết định: chưa tách) |
| C | **Vị trí chi tiết/tầng/mặt-trục** | `jobs.location` |
| D | Nội dung công việc | `jobs.content` |
| E | **Mục tiêu hoàn thành** | `jobs.quantity` + đơn vị — **đã có sẵn** |
| F | Ngày bắt đầu | `jobs.start_date` |
| G | Ngày kết thúc | `jobs.end_date` |
| H | **Lũy kế sản lượng** (khối lượng) | **mới** — cộng dồn từ bảng nhập theo ngày |
| I | **Lũy kế sản lượng (Thành tiền VND)** | **mới** — H × đơn giá |
| J | **Lũy kế (%) hoàn thành** | **mới** — H ÷ E |

Cột B, C, D trong file Excel nằm chung nhóm "Nội dung công việc/Vị trí thực hiện"; F, G
nằm chung nhóm "Thời gian".

---

## 3. Nhập liệu hằng ngày

* **Ai nhập:** tổ trưởng.
* **Nhập theo cái gì:** **từng dòng việc** — một con số cho mỗi việc mỗi ngày. Không nhập
  theo từng công nhân như phiếu CNCH.
* **Nhập cái gì:** khối lượng làm được **trong ngày hôm đó**, không phải lũy kế. Hệ thống
  tự cộng dồn.
* **Sang ngày mới:** số của ngày cũ giữ nguyên, ngày mới là một dòng mới.

### Khóa sau khi xác nhận

Khi bấm lưu, hiện hộp thoại:

> **Anh chắc chắn chưa? Lưu rồi sẽ không sửa lại được nữa.**
> [ Đồng ý ] [ Kiểm tra lại ]

Bấm **Đồng ý** là khóa. Chỉ **Admin** mở khóa sửa lại được. **Không lưu lịch sử sửa đổi**
(người dùng đã chọn như vậy).

---

## 4. Công thức

| Chỉ tiêu | Cách tính |
|---|---|
| Lũy kế khối lượng (H) | cộng dồn khối lượng nhập mỗi ngày của **việc đó** |
| Lũy kế thành tiền (I) | H × đơn giá tính toán của việc |
| Lũy kế % (J) | H ÷ **Mục tiêu hoàn thành (E)** = H ÷ `jobs.quantity` |

Đơn giá dùng đúng đơn giá mà hệ thống đang dùng để tính sản lượng kế hoạch, không lấy
nguồn khác — nếu không, hai màn hình sẽ ra hai con số khác nhau cho cùng một việc.

---

## 5. Ai xem được gì

| Vai trò | Phạm vi |
|---|---|
| Admin | tất cả các tổ |
| Giám sát | chỉ các tổ được giao quản lý (`profile_teams`) |
| Tổ trưởng | chỉ đúng tổ mình |
| Vai trò khác | không xem được |

Phạm vi do **database** quyết định, giao diện không lọc lại. Lọc ở trình duyệt chỉ là giấu
đi, số vẫn đã gửi tới máy người dùng.

---

## 6. Thêm vào màn Đánh giá KPI

Thêm cột **Sản lượng thực tế** = tổng **Lũy kế thành tiền (I)** của tuần đó.

Nó có chỉ báo **riêng, độc lập** với chỉ báo lãi/lỗ cũ: so Sản lượng thực tế với Sản lượng
(kế hoạch) — âm thì **đỏ**, bằng hoặc dương thì **xanh**. Cột Chênh lệch cũ giữ nguyên ý
nghĩa, không đụng tới.

Nói cách khác màn KPI sẽ có hai thước đo tách bạch: *có lãi không* (cũ) và *làm được bao
nhiêu so với đã giao* (mới).

---

## 7. Vòng đời dữ liệu

Sản lượng theo ngày giữ lại khi sang ngày mới, sang tuần mới. **Chỉ bị xóa khi dữ liệu
giao việc của tuần đó bị xóa.**

⚠️ **Đây là chỗ bắt buộc phải làm cùng lúc, không để lại sau.** Quy tắc hiện hành: xóa tuần
phải **sao lưu → lưu trữ → kiểm chứng → xóa**, hỏng bất kỳ bước nào là không được xóa. File
Excel lưu trữ hiện chỉ chứa dữ liệu giao việc. Nếu thêm bảng sản lượng mà quên đưa vào file
lưu trữ thì xóa tuần sẽ xóa mất sản lượng **không có bản sao nào**. Dự án này đã dính đúng
loại lỗi đó một lần (backup thiếu cột `is_special_labor`).

---

## 8. Phải xây mới những gì

### Đã có sẵn, không phải làm

* **Mục tiêu hoàn thành theo việc** = `jobs.quantity`, đang in ở cột 8 của PGV chung.
  *(Đánh giá trước của tôi ghi là "chưa có" — sai, đã sửa lại.)*
* Đơn giá, sản lượng kế hoạch, tuần, mã nhóm, phân quyền theo tổ.

### Phải làm mới

| Hạng mục | Ghi chú |
|---|---|
| **Bảng sản lượng theo ngày** | khóa chính (việc, ngày); có cờ khóa và người khóa |
| **Luồng mời tài khoản an toàn + cấu hình SMTP** | KHÔNG chặn việc xây phần 2; phải xong trước **ngày phát tài khoản** — xem câu hỏi 3 |
| Hàm nhập + khóa + mở khóa (Admin) | |
| Hàm tổng hợp bảng đánh giá sản lượng | |
| Màn hình "Đánh giá sản lượng" + bộ lọc theo tổ/tuần | |
| Cột "Sản lượng thực tế" trong KPI | |
| Sửa luồng xóa tuần để file lưu trữ gồm cả sản lượng | mục 7 |
| Cập nhật script sao lưu và điểm khôi phục | thêm bảng mới vào số dòng đối chiếu |

---

## 9. Không làm trong đợt này

* **Không có nút Xuất Excel** ở màn Đánh giá sản lượng. Người dùng sẽ bàn riêng ở bài toán
  phát triển tiếp.
* Không lưu lịch sử sửa đổi.
* Không có luồng gửi giám sát duyệt.

---

## 10. Rủi ro đã biết

**Khóa không lưu lịch sử.** Admin có thể sửa số sản lượng đã dùng để tính KPI mà **không
để lại dấu vết nào**. Với một Admin duy nhất là chấp nhận được; nếu sau này có nhiều Admin
thì nên xem lại. Ghi ở đây để sau không ai bất ngờ.

**Sản lượng nhập rồi mới sửa việc.** Nếu ai đó sửa khối lượng giao (`jobs.quantity`) sau
khi tổ trưởng đã nhập sản lượng thì cột % đổi theo mà không có cảnh báo. Hiện `update_job`
đã chặn sửa việc đang có mã nhóm; cần xét có chặn thêm khi việc đã có sản lượng hay không.

**Việc lao động đặc biệt** (Đào tạo, Phát sinh) đã xử lý: tự lũy kế, không nhập tay — xem
câu hỏi 4.

**Tính năng dựng xong vẫn nằm im cho tới khi có tài khoản.** Nhập sản lượng là việc hằng
ngày của 89 tổ trưởng. Đã quyết định tạo tài khoản sau, nên trong giai đoạn đó cột "Sản
lượng thực tế" sẽ trống và không có gì để nghiệm thu ngoài dữ liệu thử. Chấp nhận được,
miễn là không nhầm "chưa nhập" thành "làm được 0 đồng".

---

## 11. Bốn câu hỏi — đã trả lời 11/08/2026

### 1. Một dòng của bảng = **một VIỆC**

Nhập và hiển thị đều theo từng việc. Cột % vì vậy luôn có nghĩa: tử số và mẫu số cùng một
đơn vị.

Khác file Excel gốc ở chỗ các việc cùng mã nhóm sẽ nằm thành **nhiều dòng** thay vì được
nối lại bằng TEXTJOIN. Đây là chủ ý: dòng gộp không cộng được khối lượng khi các việc khác
đơn vị (md, m², kg), nên cột % của dòng gộp sẽ vô nghĩa. Mã nhóm vẫn hiện được để biết các
dòng nào đi cùng nhau.

### 2. **Chưa tách** Phân khu khỏi Vị trí chi tiết

Giữ nguyên một trường `jobs.location`. Hai cột B và C của bảng cùng hiện một giá trị, đúng
như bản in PGV đang làm. Không đụng tới dữ liệu đang có. Tách sau lúc nào cũng được.

### 3. Tổ trưởng chưa có tài khoản — **có email, và tạo sau cũng được**

Quyết định 11/08/2026: 89 tổ trưởng đều có email; tài khoản sẽ tạo sau, không chặn việc
xây phần 2.

Điều này **được về mặt kỹ thuật**: không có gì trong phần 2 phụ thuộc vào việc tài khoản đã
tồn tại. Bảng, hàm, màn hình, cột KPI đều dựng và kiểm thử được trước.

Nhưng ba hệ quả phải biết trước:

**(a) Cột "Sản lượng thực tế" trong KPI sẽ trống** cho tới khi tổ trưởng bắt đầu nhập. Đó
là số đúng — chưa ai nhập thì chưa có sản lượng — nhưng nhìn vào dễ tưởng hỏng. Nên hiển
thị rõ "chưa có dữ liệu nhập" thay vì số 0, vì 0 và "chưa nhập" là hai chuyện khác nhau.

**(b) Nghiệm thu cần ít nhất 1–2 tài khoản tổ trưởng thật.** Không thể nghiệm thu luồng
nhập hằng ngày bằng tài khoản Admin, vì Admin thấy mọi tổ còn tổ trưởng chỉ thấy tổ mình —
đúng phần dễ sai nhất lại là phần không được kiểm.

**(c) Luồng tạo tài khoản hiện có KHÔNG phải luồng mời.** Màn Phân Quyền hiện bắt Admin
nhập **email và mật khẩu** (tối thiểu 8 ký tự) rồi gọi `createUser` với mật khẩu đó. Nghĩa
là Admin phải tự nghĩ 89 mật khẩu, gõ vào, rồi chuyển cho từng người bằng cách nào đó.

Cách làm đó **trái quy tắc đã đặt từ đầu dự án**: *"Không hỏi hoặc hiển thị mật khẩu; dùng
luồng mời/reset an toàn."* Với một tài khoản Admin duy nhất thì chưa thành vấn đề; với 89
người thì đây là 89 mật khẩu đi qua tin nhắn hoặc giấy.

Nên trước khi phát tài khoản hàng loạt, cần bổ sung **luồng mời**: hệ thống gửi liên kết,
người nhận tự đặt mật khẩu, Admin không bao giờ thấy. Đây là việc tách rời, làm lúc nào
cũng được, nhưng phải xong **trước ngày phát tài khoản**, không phải trước ngày viết mã.

**(d) Rào cản kỹ thuật khi phát hàng loạt: chưa cấu hình SMTP.** `supabase/config.toml`
đang để trống phần `[auth.email.smtp]`, tức dùng dịch vụ thư mặc định của Supabase với giới
hạn gửi rất thấp. Mời 89 người bằng thư sẽ đụng trần ngay. Trước ngày phát tài khoản phải
cấu hình SMTP riêng (SendGrid hoặc tương đương).

### 4. Đào tạo / Phát sinh: **hiện trong bảng, không nhập tay, tự lũy kế theo ngày**

Loại việc này có khối lượng tự sinh = **số người × số ngày**, đơn vị là công. Nên không bắt
tổ trưởng nhập; hệ thống tự cộng dồn mỗi ngày trôi qua thêm đúng **số người** của việc.

| | |
|---|---|
| Lũy kế khối lượng | số người × số ngày đã trôi qua |
| Lũy kế % | ngày đã trôi qua ÷ tổng số ngày của việc |
| Ô nhập | khóa, không cho gõ tay |

**Giả định cần anh xác nhận khi làm:** "số ngày đã trôi qua" tính tới **ngày hôm nay**, và
không vượt quá ngày kết thúc của việc. Tức việc đã xong thì lũy kế đứng ở 100%, không tăng
tiếp.

---

## 12. Thứ tự thi công đề nghị

1. ~~Trả lời 4 câu hỏi ở mục 11~~ — đã trả lời 11/08/2026.
2. Tạo **2–3 tài khoản tổ trưởng thử** để còn nghiệm thu được luồng nhập theo đúng vai trò.
   (Luồng mời an toàn và cấu hình SMTP làm sau, trước ngày phát tài khoản cho cả 89 người.)
3. Bảng sản lượng theo ngày + hàm nhập + khóa.
4. **Cùng lúc** sửa luồng xóa tuần và script sao lưu (mục 7).
5. Màn hình Đánh giá sản lượng + phân quyền theo tổ.
6. Cột Sản lượng thực tế trong KPI.
