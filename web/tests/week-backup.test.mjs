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
