import { readSheetRows } from "./cnchWorkbook";
import { clean, norm, parseAmount, findPriceHeader, findSalaryHeader } from "./catalogHeaders";

export { parseAmount, findPriceHeader, findSalaryHeader } from "./catalogHeaders";

export type PriceRow = {
  category_name: string;
  content: string;
  tech_desc: string | null;
  unit: string;
  work_code: string | null;
  calc_price: number;
};
export type PriceWorkbook = { items: PriceRow[]; categories: string[]; sheetName: string };

export type SalaryRow = { system_name: string; grade_name: string; monthly_salary: number };
export type SalaryWorkbook = { rows: SalaryRow[]; systems: string[]; skippedZero: number; sheetName: string };

export const PRICE_ROW_LIMIT = 20000;
export const SALARY_ROW_LIMIT = 5000;

export async function parsePriceWorkbook(file: File): Promise<PriceWorkbook> {
  for (const sheet of await readSheetRows(file, 16)) {
    const header = findPriceHeader(sheet.rows);
    if (!header) continue;
    const items: PriceRow[] = [];
    const seen = new Set<string>();
    const categoryOrder: string[] = [];
    for (let i = header.row + 1; i < sheet.rows.length; i++) {
      const line = sheet.rows[i] || [];
      const category_name = clean(line[header.category]);
      const content = clean(line[header.content]);
      const unit = clean(line[header.unit]);
      const rawPrice = String(line[header.price] ?? "");
      if (!category_name && !content && !unit && !clean(rawPrice)) continue;
      if (!category_name || !content)
        throw new Error(`Dòng ${i + 1} thiếu Hạng mục Cấp 1 hoặc Nội dung công việc Cấp 2.`);
      if (!unit) throw new Error(`Dòng ${i + 1} thiếu Đơn vị.`);
      if (category_name.includes("‡") || content.includes("‡"))
        throw new Error(`Dòng ${i + 1} chứa ký tự ‡ dành riêng cho hệ thống.`);
      const calc_price = parseAmount(rawPrice, i + 1, "Đơn giá");
      if (calc_price < 0) throw new Error(`Dòng ${i + 1}: Đơn giá không được âm.`);
      const key = `${norm(category_name)}‡${norm(content)}`;
      if (seen.has(key))
        throw new Error(`Trùng khóa “${category_name} · ${content}” tại dòng ${i + 1}.`);
      seen.add(key);
      if (!categoryOrder.includes(category_name)) categoryOrder.push(category_name);
      items.push({
        category_name,
        content,
        tech_desc: header.tech >= 0 ? clean(line[header.tech]) || null : null,
        unit,
        work_code: header.code >= 0 ? clean(line[header.code]) || null : null,
        calc_price,
      });
    }
    if (!items.length) throw new Error("File không có dòng đơn giá hợp lệ.");
    if (items.length > PRICE_ROW_LIMIT)
      throw new Error(`File có ${items.length} dòng, vượt giới hạn ${PRICE_ROW_LIMIT} dòng.`);
    return { items, categories: categoryOrder, sheetName: sheet.path };
  }
  throw new Error("Không nhận diện được các cột Hạng mục Cấp 1, Nội dung công việc Cấp 2, Đơn vị và Đơn giá.");
}

export async function parseSalaryWorkbook(file: File): Promise<SalaryWorkbook> {
  for (const sheet of await readSheetRows(file, 8)) {
    const header = findSalaryHeader(sheet.rows);
    if (!header) continue;
    const rows: SalaryRow[] = [];
    const seen = new Set<string>();
    const systemOrder: string[] = [];
    const normSystem = new Map<string, string>();
    const normGrade = new Map<string, string>();
    let skippedZero = 0;
    for (let i = header.row + 1; i < sheet.rows.length; i++) {
      const line = sheet.rows[i] || [];
      const system_name = clean(line[header.system]);
      const grade_name = clean(line[header.grade]);
      const rawSalary = String(line[header.monthly] ?? "");
      if (!system_name && !grade_name && !clean(rawSalary)) continue;
      if (!system_name || !grade_name)
        throw new Error(`Dòng ${i + 1} thiếu Hệ hoặc Chức danh.`);
      const monthly_salary = parseAmount(rawSalary, i + 1, "Mức lương tháng");
      if (monthly_salary < 0) throw new Error(`Dòng ${i + 1}: Mức lương không được âm.`);
      const sKey = norm(system_name), gKey = norm(grade_name);
      const sPrev = normSystem.get(sKey);
      if (sPrev && sPrev !== system_name)
        throw new Error(`Dòng ${i + 1}: Hệ “${system_name}” trùng nghĩa với “${sPrev}” đã dùng ở trên. Viết thống nhất một cách.`);
      normSystem.set(sKey, system_name);
      const gPrev = normGrade.get(gKey);
      if (gPrev && gPrev !== grade_name)
        throw new Error(`Dòng ${i + 1}: Chức danh “${grade_name}” trùng nghĩa với “${gPrev}” đã dùng ở trên. Viết thống nhất một cách.`);
      normGrade.set(gKey, grade_name);
      const key = `${sKey}‡${gKey}`;
      if (seen.has(key))
        throw new Error(`Trùng khóa “${system_name} · ${grade_name}” tại dòng ${i + 1}.`);
      seen.add(key);
      if (!systemOrder.includes(system_name)) systemOrder.push(system_name);
      if (monthly_salary === 0) skippedZero++;
      rows.push({ system_name, grade_name, monthly_salary });
    }
    if (!rows.length) throw new Error("File không có dòng lương hợp lệ.");
    if (rows.length > SALARY_ROW_LIMIT)
      throw new Error(`File có ${rows.length} dòng, vượt giới hạn ${SALARY_ROW_LIMIT} dòng.`);
    if (rows.length === skippedZero)
      throw new Error("Toàn bộ dòng đều có mức lương 0; không có gì để cập nhật.");
    return { rows, systems: systemOrder, skippedZero, sheetName: sheet.path };
  }
  throw new Error("Không nhận diện được các cột Hệ, Chức danh và Mức lương tháng.");
}
