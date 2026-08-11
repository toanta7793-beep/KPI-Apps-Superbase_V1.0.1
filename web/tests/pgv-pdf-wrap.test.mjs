import test from "node:test";
import assert from "node:assert/strict";
import { split, rowHeight } from "../lib/downloadPgvPdf.ts";

// Font giả: mỗi ký tự rộng đúng 0.5 * size. Đủ để kiểm tra phép tính xuống dòng.
const font = { widthOfTextAtSize: (t, size) => t.length * size * 0.5 };

// cell() cắt bớt theo công thức này; rowHeight phải cho ra vừa đủ số dòng cần.
const linesCellWillDraw = (h, size) => Math.max(1, Math.floor((h - 5) / (size + 2)));

test("nội dung dài xuống dòng, không dòng nào vượt quá bề rộng ô", () => {
  // Dài như thực tế: cột này phải ghi rõ khối lượng tồn kỳ trước và khối lượng giao mới.
  const text = "Thi công tuyến ống cấp nước DN20 trục chính tầng 5 bao gồm giá đỡ ty treo và "
    + "toàn bộ phụ kiện theo bản vẽ đã được phê duyệt. Tồn kỳ trước 120m chưa hoàn thành do "
    + "vướng mặt bằng khu vực trục A đến trục C, giao mới 260m trong tuần này, yêu cầu nghiệm "
    + "thu từng đoạn trước khi lấp và gửi ảnh hiện trường hằng ngày trước 20h.";
  const width = 254; // cột Nội dung công việc: 260 trừ 6 lề
  const lines = split(font, text, 7, width);
  assert.ok(lines.length > 3, `phải xuống nhiều dòng, đang có ${lines.length}`);
  for (const l of lines) assert.ok(font.widthOfTextAtSize(l, 7) <= width, `dòng quá rộng: ${l}`);
  const joined = lines.join(" ").replace(/\s+/g, " ").trim();
  assert.equal(joined, text.replace(/\s+/g, " ").trim(), "không được mất chữ nào");
});

test("một từ dài không có dấu cách bị cắt theo ký tự thay vì tràn ra ngoài ô", () => {
  const word = "CTN-CAOTANG-TANG05-TRUCA-DEN-TRUCC-DN20-PN16-MAVATTU-0099887766";
  const width = 60;
  const lines = split(font, word, 7, width);
  assert.ok(lines.length > 1, "phải tách thành nhiều dòng");
  for (const l of lines) assert.ok(font.widthOfTextAtSize(l, 7) <= width, `dòng quá rộng: ${l}`);
  assert.equal(lines.join(""), word, "ghép lại phải đúng nguyên văn");
});

test("chiều cao dòng đủ chứa ô dài nhất, cell() không phải cắt bỏ dòng nào", () => {
  const widths = [28, 84, 260, 48, 70, 70, 104];
  const vals = [1, "Tầng 5 trục A đến trục C khu B3 phân khu phía đông",
    "Thi công tuyến ống cấp nước DN20 trục chính tầng 5 gồm giá đỡ ty treo và toàn bộ phụ kiện "
    + "theo bản vẽ đã duyệt. Tồn kỳ trước 120m chưa hoàn thành do vướng mặt bằng trục A đến "
    + "trục C, giao mới 260m trong tuần, nghiệm thu từng đoạn trước khi lấp.",
    "6", "380 m", "02/09/2026", "04/09/2026"];
  const size = 7;
  const h = rowHeight(font, vals, widths, size, 36);
  assert.ok(h > 36, `dòng phải cao hơn mức tối thiểu, đang là ${h}`);
  const need = Math.max(...vals.map((v, i) => split(font, String(v), size, widths[i] - 6).length));
  assert.ok(linesCellWillDraw(h, size) >= need,
    `cell() chỉ vẽ ${linesCellWillDraw(h, size)} dòng nhưng cần ${need}`);
});

test("nội dung ngắn vẫn giữ chiều cao tối thiểu, bố cục không co lại", () => {
  const widths = [28, 84, 260, 48, 70, 70, 104];
  const vals = [1, "T5", "Kéo dây", "2", "10 m", "02/09/2026", "04/09/2026"];
  assert.equal(rowHeight(font, vals, widths, 7, 36), 36);
});
