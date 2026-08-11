import test from "node:test";
import assert from "node:assert/strict";
import { unzipSync, strFromU8 } from "fflate";
import { buildWeekBackupXlsx } from "../lib/weekBackupXlsx.ts";

const sheetXml = rows => strFromU8(unzipSync(buildWeekBackupXlsx(rows))["xl/worksheets/sheet1.xml"]);

test("backup carries every input column of public.jobs so a restore is lossless", () => {
  const xml = sheetXml([]);
  for (const label of ["Việc đặc biệt", "Mã nhóm", "Khối lượng", "Vị trí", "Tổ trưởng", "Thợ phụ"]) {
    assert.ok(xml.includes(label), `thiếu cột “${label}” trong backup`);
  }
});

test("column addresses go past Z instead of emitting junk characters", () => {
  const xml = sheetXml([]);
  assert.ok(xml.includes('r="Z1"'), "phải có cột Z");
  assert.ok(xml.includes('r="AA1"'), "phải có cột AA");
  assert.ok(xml.includes('r="AG1"'), "cột cuối phải là AG");
  assert.doesNotMatch(xml, /r="[^A-Z0-9"]/, "không được sinh ký tự ngoài A-Z trong địa chỉ ô");
  assert.ok(xml.includes('ref="A1:AG1"'), "autoFilter phải phủ tới cột cuối");
});

test("is_special_labor survives the round trip", () => {
  const xml = sheetXml([{ id: "j1", content: "Đào tạo", is_special_labor: true, quantity: 0 }]);
  assert.match(xml, /<t>true<\/t>/);
  assert.match(xml, /<t>Đào tạo<\/t>/);
});

// Sản lượng theo ngày phải nằm trong file backup. Nếu thiếu, xóa tuần sẽ xóa mất số tổ
// trưởng đã nhập mà không có bản sao nào — đúng loại lỗi đã xảy ra một lần với cột
// is_special_labor.
const prodXml = production => strFromU8(unzipSync(buildWeekBackupXlsx([], production))["xl/worksheets/sheet2.xml"]);

test("backup has a second sheet carrying daily production", () => {
  const files = unzipSync(buildWeekBackupXlsx([], []));
  assert.ok(files["xl/worksheets/sheet2.xml"], "thiếu sheet sản lượng");
  const workbook = strFromU8(files["xl/workbook.xml"]);
  assert.ok(workbook.includes("SAN_LUONG_NGAY"), "workbook phải khai báo sheet SAN_LUONG_NGAY");
  const types = strFromU8(files["[Content_Types].xml"]);
  assert.ok(types.includes("sheet2.xml"), "Content_Types phải khai báo sheet2 — thiếu là Excel không mở được");
  const rels = strFromU8(files["xl/_rels/workbook.xml.rels"]);
  assert.ok(rels.includes("worksheets/sheet2.xml"), "rels phải trỏ tới sheet2");
});

test("every production column needed to restore is present", () => {
  const xml = prodXml([]);
  for (const label of ["Ngày", "Khối lượng hoàn thành", "Đã khóa", "Job ID"]) {
    assert.ok(xml.includes(label), `thiếu cột “${label}”`);
  }
});

test("production rows are written, not silently dropped", () => {
  const xml = prodXml([
    { job_id: "j1", content: "Lắp ống", work_date: "2026-09-02", quantity: 11, is_locked: true, unit: "md" },
    { job_id: "j1", content: "Lắp ống", work_date: "2026-09-03", quantity: 22, is_locked: true, unit: "md" },
  ]);
  assert.ok(xml.includes("2026-09-02") && xml.includes("2026-09-03"), "thiếu ngày");
  assert.ok(xml.includes("<v>11</v>") && xml.includes("<v>22</v>"), "khối lượng phải ghi dạng số, không phải chữ");
  assert.equal((xml.match(/<row /g) || []).length, 3, "phải có 1 dòng tiêu đề + 2 dòng dữ liệu");
});
