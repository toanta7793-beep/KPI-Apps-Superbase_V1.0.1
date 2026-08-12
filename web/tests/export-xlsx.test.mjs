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
