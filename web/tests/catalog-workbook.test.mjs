import test from "node:test";
import assert from "node:assert/strict";
import { parseAmount, findPriceHeader, findSalaryHeader } from "../lib/catalogHeaders.ts";

test("accepts plain numbers and thousand separators, rejects text and formulas", () => {
  assert.equal(parseAmount("245577.8", 2, "Đơn giá"), 245577.8);
  assert.equal(parseAmount(" 34 000 000 ", 2, "Đơn giá"), 34000000);
  assert.equal(parseAmount("1,250,000", 2, "Đơn giá"), 1250000);
  assert.equal(parseAmount("0", 2, "Đơn giá"), 0);
  for (const bad of ["=A1*1.3", "245.577đ", "hai trăm", "1.2.3", ""]) {
    assert.throws(() => parseAmount(bad, 7, "Đơn giá"), /Dòng 7/);
  }
});

test("price header maps the clone template", () => {
  const header = findPriceHeader([[
    "Nội dung công việc (Cấp 2) *", "Mô tả kỹ thuật", "Đơn vị *",
    "Đơn giá NC dùng tính toán (VNĐ) *", "Hạng mục thi công (Cấp 1) *", "Mã công việc (tùy chọn)",
  ]]);
  assert.deepEqual(header, { row: 0, category: 4, content: 0, unit: 2, price: 3, tech: 1, code: 5 });
});

test("price header keeps Cap 1 and Cap 2 apart on legacy exports", () => {
  const header = findPriceHeader([[
    "Hạng mục thi công (Nội dung công việc)", "Mô tả kỹ thuật", "Đơn vị",
    "Đơn giá NC đã duyệt (VNĐ) - DÙNG TÍNH TOÁN", "Hạng mục thi công", "Khóa tra cứu (ẩn - không sửa)",
  ]]);
  assert.ok(header, "phải nhận diện được header của file xuất cũ");
  assert.equal(header.category, 4);
  assert.equal(header.content, 0);
  assert.notEqual(header.category, header.content);
});

test("price header is rejected when a required column is missing", () => {
  assert.equal(findPriceHeader([["Nội dung công việc (Cấp 2)", "Đơn vị"]]), null);
});

test("salary header is found below a title row", () => {
  const header = findSalaryHeader([
    ["BẢNG LƯƠNG CHUẨN THEO HỆ", null, null],
    ["Hệ", "Chức danh", "Mức lương tháng (VNĐ)", "Lương 1 ngày (VNĐ)"],
  ]);
  assert.deepEqual(header, { row: 1, system: 0, grade: 1, monthly: 2 });
});

test("salary header ignores the derived daily-salary column", () => {
  const header = findSalaryHeader([["Lương 1 ngày (VNĐ)", "Hệ", "Chức danh", "Mức lương tháng (VNĐ)"]]);
  assert.equal(header.monthly, 3);
});
