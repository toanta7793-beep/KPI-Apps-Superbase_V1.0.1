// Các hàm thuần dùng chung cho việc đọc mẫu Excel danh mục/đơn giá/bảng lương.
// KHÔNG import gì để chạy trực tiếp được bằng `node --test`.

export const clean=(value:unknown)=>String(value??"").replace(/\s+/g," ").trim();
export const norm=(value:unknown)=>clean(value).normalize("NFD").replace(/[̀-ͯ]/g,"").replace(/đ/g,"d").replace(/Đ/g,"D").replace(/[^a-zA-Z0-9]+/g," ").trim().toLowerCase();

/** Số tiền phải là số thuần. Chấp nhận dấu cách và dấu phẩy ngăn nghìn, từ chối chữ và công thức. */
export function parseAmount(raw: string, row: number, label: string): number {
  const text = clean(raw).replace(/[\s,]/g, "");
  if (!text) throw new Error(`Dòng ${row} thiếu ${label}.`);
  if (!/^-?\d+(\.\d+)?$/.test(text))
    throw new Error(`Dòng ${row}: ${label} “${clean(raw)}” không phải số hợp lệ. Nhập số thuần, không nhập công thức hay ký tự tiền tệ.`);
  const value = Number(text);
  if (!Number.isFinite(value)) throw new Error(`Dòng ${row}: ${label} không đọc được.`);
  return value;
}

const findBy = (headers: string[], test: (h: string) => boolean, skip: number[] = []) =>
  headers.findIndex((h, i) => !skip.includes(i) && test(h));

export function findPriceHeader(rows: string[][]) {
  for (let row = 0; row < Math.min(rows.length, 20); row++) {
    const h = (rows[row] || []).map(norm);
    let category = findBy(h, v => v.includes("cap 1"));
    if (category < 0) category = findBy(h, v => v === "hang muc thi cong");
    if (category < 0) category = findBy(h, v => v.includes("hang muc") && !v.includes("noi dung"));
    let content = findBy(h, v => v.includes("cap 2"), [category]);
    if (content < 0) content = findBy(h, v => v.includes("noi dung cong viec"), [category]);
    const unit = findBy(h, v => v.includes("don vi"));
    const price = findBy(h, v => v.includes("don gia"));
    const tech = findBy(h, v => v.includes("mo ta"));
    const code = findBy(h, v => v.includes("ma cong viec"));
    if (category >= 0 && content >= 0 && category !== content && unit >= 0 && price >= 0)
      return { row, category, content, unit, price, tech, code };
  }
  return null;
}

export function findSalaryHeader(rows: string[][]) {
  for (let row = 0; row < Math.min(rows.length, 20); row++) {
    const h = (rows[row] || []).map(norm);
    let system = findBy(h, v => v === "he" || v === "he ky thuat");
    if (system < 0) system = findBy(h, v => v.startsWith("he "));
    const grade = findBy(h, v => v.includes("chuc danh") || v.includes("cap bac"));
    const monthly = findBy(h, v => v.includes("luong thang"));
    if (system >= 0 && grade >= 0 && monthly >= 0) return { row, system, grade, monthly };
  }
  return null;
}
