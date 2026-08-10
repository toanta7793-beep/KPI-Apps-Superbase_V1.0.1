import test from "node:test";
import assert from "node:assert/strict";
import { parseAmount, priceRowConflict, findPriceHeader, findSalaryHeader } from "../lib/catalogHeaders.ts";

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

test("same item at the same price is a harmless repeat, not an error", () => {
  assert.equal(priceRowConflict("CTN · Ống D90", 5, 52000, 9, 52000), null);
});

test("same item at two different prices is refused, naming both", () => {
  const msg = priceRowConflict("CTN · Ống D90", 5, 52000, 9, 61000);
  assert.match(msg, /Dòng 9/);
  assert.match(msg, /dòng 5/);
  assert.match(msg, /52\.000/);
  assert.match(msg, /61\.000/);
});

test("items differing only by dash character or by PN size stay distinct", () => {
  const a = "Thi công Côn (bạc) uPVC D90 - PN8";
  const b = "Thi công Côn (bạc) uPVC D90 – PN6";
  const c = "Thi công Côn (bạc) uPVC D90 – PN8";
  assert.notEqual(`CTN‡${a}`, `CTN‡${b}`);
  assert.notEqual(`CTN‡${a}`, `CTN‡${c}`, "gạch nối thường và gạch ngang dài phải là hai dòng khác nhau");
  assert.notEqual(`CTN‡${b}`, `CTN‡${c}`);
});
