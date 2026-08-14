import test from "node:test";
import assert from "node:assert/strict";
import { unzipSync, strFromU8 } from "fflate";
import { buildTableXlsx, columnName, asciiFileName } from "../lib/exportXlsx.ts";
import { toProductionExportRows, toKpiExportRows } from "../app/exportRows.ts";
import { operationError } from "../app/importErrors.ts";

const sheet = (cols, rows) => strFromU8(unzipSync(buildTableXlsx("Test", cols, rows))["xl/worksheets/sheet1.xml"]);

test("file xuất ra là xlsx hợp lệ, đủ các phần Excel cần để mở được", () => {
  const files = unzipSync(buildTableXlsx("DanhGiaKPI", [{ key: "a", label: "A" }], []));
  for (const part of ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/_rels/workbook.xml.rels", "xl/styles.xml", "xl/worksheets/sheet1.xml"]) {
    assert.ok(files[part], `thiếu ${part}`);
  }
  assert.ok(strFromU8(files["xl/workbook.xml"]).includes("DanhGiaKPI"), "tên sheet phải vào workbook");
});

test("số ghi ra dạng SỐ, chữ ghi ra dạng chữ", () => {
  const xml = sheet([{ key: "n", label: "So" }, { key: "s", label: "Chu" }], [{ n: 1750000, s: "Tổ A" }]);
  assert.ok(xml.includes("<v>1750000</v>"), "số phải là <v>, nếu là chữ thì Excel không cộng được");
  assert.ok(xml.includes("Tổ A"), "chữ tiếng Việt phải giữ nguyên");
});

test("địa chỉ ô đi quá cột Z không sinh ký tự rác", () => {
  assert.equal(columnName(25), "Z");
  assert.equal(columnName(26), "AA");
  const cols = Array.from({ length: 30 }, (_, i) => ({ key: `c${i}`, label: `C${i}` }));
  assert.doesNotMatch(sheet(cols, []), /r="[^A-Z0-9"]/);
});

test("tên sheet quá dài hoặc có ký tự cấm được cắt gọn — Excel từ chối mở nếu không", () => {
  const wb = strFromU8(unzipSync(buildTableXlsx("Tên/rất:dài*không[hợp]lệ vượt quá ba mươi mốt ký tự", [{ key: "a", label: "A" }], []))["xl/workbook.xml"]);
  const name = wb.match(/name="([^"]*)"/)[1];
  assert.ok(name.length <= 31, "tên sheet phải ≤ 31 ký tự");
  assert.doesNotMatch(name, /[:\?*[\]/]/, "không được còn ký tự cấm");
});

test("chưa nhập sản lượng thì cột % để TRỐNG, không phải 0", () => {
  const [chuaNhap, daNhap] = toProductionExportRows([
    { job_id: "a", team_name: "T", week_slot: 1, noi_dung: "X", muc_tieu: 100, don_vi: "m", start_date: "2026-09-01", end_date: "2026-09-05", luy_ke_khoi_luong: 0, luy_ke_thanh_tien: 0, luy_ke_phan_tram: 0, so_ngay_da_nhap: 0, tu_dong: false, group_code: null, phan_khu: null, vi_tri_chi_tiet: null, o_nhap_khoi_luong: null, o_nhap_da_khoa: false, o_nhap_co_ton_tai: false },
    { job_id: "b", team_name: "T", week_slot: 1, noi_dung: "Y", muc_tieu: 100, don_vi: "m", start_date: "2026-09-01", end_date: "2026-09-05", luy_ke_khoi_luong: 35, luy_ke_thanh_tien: 1750000, luy_ke_phan_tram: 35, so_ngay_da_nhap: 1, tu_dong: false, group_code: null, phan_khu: null, vi_tri_chi_tiet: null, o_nhap_khoi_luong: null, o_nhap_da_khoa: false, o_nhap_co_ton_tai: false },
  ]);
  assert.equal(chuaNhap.luy_ke_phan_tram, "", "chưa nhập phải là ô trống — số 0 sẽ bị Excel cộng như kết quả thật");
  assert.equal(daNhap.luy_ke_phan_tram, 35);
  assert.equal(chuaNhap.start_date, "01/09/2026", "ngày trong file phải là dd/mm/yyyy");
});

test("KPI: chưa nhập sản lượng thì hai cột thực tế để TRỐNG, không phải 0", () => {
  const [chuaNhap, daNhap] = toKpiExportRows([
    { week_slot: 1, team_name: "A", start_date: "2026-09-01", end_date: "2026-09-05", day_count: 5, total_payroll: 100, total_production: 200, difference_vnd: 100, evaluation: "ĐẠT KPI", actual_production: 0, actual_vs_plan: -200, production_rows_entered: 0 },
    { week_slot: 2, team_name: "A", start_date: "2026-09-08", end_date: "2026-09-12", day_count: 5, total_payroll: 100, total_production: 200, difference_vnd: 100, evaluation: "ĐẠT KPI", actual_production: 150, actual_vs_plan: -50, production_rows_entered: 3 },
  ]);
  assert.equal(chuaNhap.actual_production, "", "chưa ai nhập thì không được ghi 0");
  assert.equal(chuaNhap.actual_vs_plan, "", "chênh lệch cũng không được ghi khi chưa có gì để so");
  assert.equal(daNhap.actual_production, 150);
  assert.equal(daNhap.actual_vs_plan, -50);
  // Chỉ báo lãi/lỗ cũ KHÔNG được đụng tới, kể cả khi chưa có sản lượng thực tế.
  assert.equal(chuaNhap.difference_vnd, 100);
  assert.equal(chuaNhap.evaluation, "ĐẠT KPI");
});

test("tên file bỏ dấu tiếng Việt", () => {
  // Gạch dưới là ký tự hợp lệ nên giữ nguyên; chỉ dấu tiếng Việt và khoảng trắng bị đổi.
  assert.equal(asciiFileName("DanhGiaSanLuong_Tổ Bùi Văn Dưỡng_Tuần1"), "DanhGiaSanLuong_To-Bui-Van-Duong_Tuan1");
  assert.doesNotMatch(asciiFileName("Tổ Đường/Ngõ*1"), /[^A-Za-z0-9._-]/, "không được còn ký tự lạ trong tên file");
});

// Thứ tự trong bảng dịch là phụ thuộc ngầm dễ vỡ: ARCHIVE_COUNT_MISMATCH là chuỗi con của
// PRODUCTION_ARCHIVE_COUNT_MISMATCH, nên dòng PRODUCTION_* phải đứng TRƯỚC mới thắng.
test("mã lỗi sản lượng dịch đúng, không bị dòng chung nuốt mất", () => {
  assert.match(operationError("PRODUCTION_LOCKED"), /đã được lưu và khóa/);
  assert.match(operationError("PRODUCTION_DATE_OUTSIDE_JOB"), /ngoài khoảng ngày/);
  assert.match(operationError("SPECIAL_LABOR_AUTO_ACCUMULATED"), /tự lũy kế/);
  assert.match(operationError("PRODUCTION_ARCHIVE_COUNT_MISMATCH"), /sản lượng không khớp/);
  assert.match(operationError("ARCHIVE_COUNT_MISMATCH"), /Số dòng backup không khớp/);
});

// --- Gợi ý nhân công / ngày / khối lượng -------------------------------------------------
import { buildSuggestParams, workDays, endDateFor } from "../app/suggestParams.ts";

const form = (over = {}) => ({
  teamId: "t1", category: "HM", content: "Ống uPVC D110",
  start: "2026-09-01", end: "2026-09-05", quantity: "145",
  counts: { leader: "1", w1: "0", w2: "2", w3: "0", helper: "0" }, ...over,
});

test("số ngày tính CẢ hai đầu, giống work_days của công thức", () => {
  assert.equal(workDays("2026-09-01", "2026-09-05"), 5);
  assert.equal(workDays("2026-09-01", "2026-09-01"), 1);
  assert.equal(workDays("2026-09-05", "2026-09-01"), 0, "ngày kết thúc trước ngày bắt đầu là không hợp lệ");
});

test("ẩn số phải gửi null — hàm SQL dựa vào đó để biết cần giải cho cái gì", () => {
  const crew = buildSuggestParams(form(), "NHAN_CONG");
  assert.equal(crew.p_count_worker1, null, "hỏi nhân công thì cơ cấu phải null");
  assert.equal(crew.p_quantity, 145);
  assert.equal(crew.p_work_days, 5);

  const days = buildSuggestParams(form(), "SO_NGAY");
  assert.equal(days.p_work_days, null, "hỏi số ngày thì số ngày phải null");
  assert.equal(days.p_count_worker2, 2);

  const qty = buildSuggestParams(form(), "KHOI_LUONG");
  assert.equal(qty.p_quantity, null, "hỏi khối lượng thì khối lượng phải null");
  assert.equal(qty.p_work_days, 5);
});

test("tổ trưởng KHÔNG được gửi đi — không nằm trong quỹ lương ngày", () => {
  const p = buildSuggestParams(form(), "SO_NGAY");
  assert.ok(!("p_count_leader" in p), "gửi tổ trưởng lên là sai công thức hòa vốn");
});

test("thiếu dữ kiện thì nói rõ thiếu gì, không gửi đi rồi mới báo", () => {
  assert.match(buildSuggestParams(form({ teamId: "" }), "NHAN_CONG").error, /Tổ/);
  assert.match(buildSuggestParams(form({ content: "" }), "NHAN_CONG").error, /đơn giá/);
  assert.match(buildSuggestParams(form({ quantity: "0" }), "NHAN_CONG").error, /khối lượng/i);
  assert.match(buildSuggestParams(form({ counts: { leader: "1", w1: "0", w2: "0", w3: "0", helper: "0" } }), "SO_NGAY").error, /nhân công/i);
  assert.match(buildSuggestParams(form({ start: "", end: "" }), "KHOI_LUONG").error, /ngày/i);
});

test("áp dụng gợi ý số ngày đặt đúng ngày kết thúc (tính cả hai đầu)", () => {
  assert.equal(endDateFor("2026-09-01", 5), "2026-09-05");
  assert.equal(endDateFor("2026-09-01", 1), "2026-09-01");
});
