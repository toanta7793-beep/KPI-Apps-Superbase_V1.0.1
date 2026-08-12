import { strToU8, zipSync } from "fflate";

/**
 * Bộ dựng file .xlsx cho các nút "Xuất Excel" trên màn hình.
 *
 * CỐ Ý KHÔNG dùng chung với lib/weekBackupXlsx.ts. File đó nằm trên đường XÓA TUẦN — nếu
 * nó hỏng thì một tuần dữ liệu bị xóa mà không có bản sao. Gộp hai thứ lại để tránh lặp
 * mấy chục dòng XML là đem rủi ro đó sang một tính năng chỉ để tiện xem báo cáo.
 * Lặp ở đây rẻ hơn nhiều so với cái giá của việc làm hỏng đường sao lưu.
 */

const escapeXml = (value: unknown) =>
  String(value ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

export type ExportColumn = { key: string; label: string };

// Tên cột Excel: A..Z rồi AA, AB... String.fromCharCode(65+n) sẽ sinh ký tự rác khi quá cột Z.
export const columnName = (index: number) => {
  let name = "";
  for (let n = index; n >= 0; n = Math.floor(n / 26) - 1) name = String.fromCharCode(65 + (n % 26)) + name;
  return name;
};

export function buildTableXlsx(sheetName: string, columns: ExportColumn[], rows: Record<string, unknown>[]) {
  const values: unknown[][] = [columns.map(c => c.label), ...rows.map(row => columns.map(c => row[c.key]))];
  const last = columnName(Math.max(0, columns.length - 1));
  // Số phải ra SỐ trong Excel, không phải chữ — nếu không thì không cộng, không lọc, không
  // pivot được, tức là mất hẳn lý do người ta muốn file Excel.
  const cell = (value: unknown, header: boolean, address: string) =>
    typeof value === "number" && Number.isFinite(value)
      ? `<c r="${address}"${header ? ' s="1"' : ""}><v>${value}</v></c>`
      : `<c r="${address}" t="inlineStr"${header ? ' s="1"' : ""}><is><t>${escapeXml(value)}</t></is></c>`;
  const sheet =
    `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">` +
    `<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetData>` +
    values.map((row, index) => `<row r="${index + 1}">${row.map((v, c) => cell(v, index === 0, `${columnName(c)}${index + 1}`)).join("")}</row>`).join("") +
    `</sheetData><autoFilter ref="A1:${last}${Math.max(1, values.length)}"/></worksheet>`;
  // Tên sheet trong Excel: tối đa 31 ký tự, không được chứa : \ / ? * [ ]
  const safeName = (sheetName || "Sheet1").replace(/[:\\/?*[\]]/g, "-").slice(0, 31);
  return zipSync({
    "[Content_Types].xml": strToU8('<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>'),
    "_rels/.rels": strToU8('<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'),
    "xl/workbook.xml": strToU8(`<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="${escapeXml(safeName)}" sheetId="1" r:id="rId1"/></sheets></workbook>`),
    "xl/_rels/workbook.xml.rels": strToU8('<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'),
    "xl/styles.xml": strToU8('<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Arial"/></font><font><b/><color rgb="FFFFFFFF"/><sz val="11"/><name val="Arial"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF1B2A6B"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/></cellXfs></styleSheet>'),
    "xl/worksheets/sheet1.xml": strToU8(sheet),
  }, { level: 6 });
}

/** Bỏ dấu tiếng Việt cho tên file — một số máy và trình duyệt xử lý tên có dấu không nhất quán. */
export const asciiFileName = (text: string) =>
  text.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/đ/g, "d").replace(/Đ/g, "D")
      .replace(/[^A-Za-z0-9._-]+/g, "-").replace(/-+/g, "-").replace(/^-|-$/g, "");

export function downloadXlsx(bytes: Uint8Array, fileName: string) {
  const blob = new Blob([bytes.slice() as unknown as BlobPart], {
    type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = fileName;
  document.body.appendChild(link);
  link.click();
  link.remove();
  // Thu hồi ngay sẽ hủy tải ở một số trình duyệt; để trình duyệt kịp bắt đầu rồi mới thu hồi.
  window.setTimeout(() => URL.revokeObjectURL(url), 10_000);
}
