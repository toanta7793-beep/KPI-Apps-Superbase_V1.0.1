import type { ExportColumn } from "../lib/exportXlsx";

/**
 * Chuẩn bị dữ liệu cho hai nút Xuất Excel. Để riêng khỏi file component vì đây là logic
 * thuần — tách ra thì test nạp được trực tiếp (Node không đọc JSX), và cùng kiểu với
 * jobGrouping.ts / staffingCoverageLogic.ts.
 *
 * Quy tắc chung cho cả hai bảng: **chưa nhập thì để Ô TRỐNG, không ghi 0**. Trong Excel số 0
 * sẽ bị cộng vào tổng và vẽ vào biểu đồ như một kết quả thật, còn ô trống thì không. Đây
 * đúng bằng phân biệt đang có trên màn hình.
 */

const viDate = (value: string) => {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value || "")) return "";
  const [y, m, d] = value.split("-");
  return `${d}/${m}/${y}`;
};

export type ProductionExportRow = {
  job_id: string; team_name: string; week_slot: number;
  phan_khu: string | null; vi_tri_chi_tiet: string | null; noi_dung: string;
  muc_tieu: number; don_vi: string | null; start_date: string; end_date: string;
  luy_ke_khoi_luong: number; luy_ke_thanh_tien: number; luy_ke_phan_tram: number | null;
  so_ngay_da_nhap: number; tu_dong: boolean; group_code: string | null;
};

// Thứ tự cột giữ đúng như trên màn hình, thêm Tổ / Tuần / Mã nhóm — màn hình đã lọc sẵn nên
// không hiện thành cột, nhưng file rời khỏi màn hình thì người đọc mất ngữ cảnh đó.
export const PRODUCTION_EXPORT_COLUMNS: ExportColumn[] = [
  { key: "stt", label: "STT" }, { key: "team_name", label: "Tổ" }, { key: "week_slot", label: "Tuần" },
  { key: "phan_khu", label: "Phân khu" }, { key: "vi_tri_chi_tiet", label: "Vị trí chi tiết" },
  { key: "noi_dung", label: "Nội dung công việc" }, { key: "group_code", label: "Mã nhóm" },
  { key: "muc_tieu", label: "Mục tiêu hoàn thành" }, { key: "don_vi", label: "Đơn vị" },
  { key: "start_date", label: "Ngày bắt đầu" }, { key: "end_date", label: "Ngày kết thúc" },
  { key: "luy_ke_khoi_luong", label: "Lũy kế sản lượng" }, { key: "luy_ke_thanh_tien", label: "Lũy kế (Thành tiền VND)" },
  { key: "luy_ke_phan_tram", label: "Lũy kế (%)" }, { key: "so_ngay_da_nhap", label: "Số ngày đã nhập" },
  { key: "tu_dong", label: "Tự động lũy kế" },
];

export function toProductionExportRows(rows: ProductionExportRow[]) {
  return rows.map((row, index) => ({
    stt: index + 1, team_name: row.team_name, week_slot: row.week_slot,
    phan_khu: row.phan_khu || "", vi_tri_chi_tiet: row.vi_tri_chi_tiet || "",
    noi_dung: row.noi_dung, group_code: row.group_code || "",
    muc_tieu: Number(row.muc_tieu), don_vi: row.don_vi || "",
    start_date: viDate(row.start_date), end_date: viDate(row.end_date),
    luy_ke_khoi_luong: Number(row.luy_ke_khoi_luong),
    luy_ke_thanh_tien: Number(row.luy_ke_thanh_tien),
    luy_ke_phan_tram: (row.so_ngay_da_nhap === 0 && !row.tu_dong) ? "" : Number(row.luy_ke_phan_tram ?? 0),
    so_ngay_da_nhap: row.so_ngay_da_nhap,
    tu_dong: row.tu_dong ? "Có" : "",
  }));
}

export type KpiExportRow = {
  week_slot: number; team_name: string; start_date: string; end_date: string; day_count: number;
  total_payroll: number; total_production: number; difference_vnd: number; evaluation: string;
  actual_production: number; actual_vs_plan: number; production_rows_entered: number;
};

export const KPI_EXPORT_COLUMNS: ExportColumn[] = [
  { key: "week_slot", label: "Tuần" }, { key: "team_name", label: "Tổ" },
  { key: "start_date", label: "Từ ngày" }, { key: "end_date", label: "Đến ngày" }, { key: "day_count", label: "Số ngày" },
  { key: "total_payroll", label: "Quỹ lương (VND)" }, { key: "total_production", label: "Sản lượng giao (VND)" },
  { key: "difference_vnd", label: "Chênh lệch (VND)" }, { key: "evaluation", label: "Đánh giá KPI" },
  { key: "actual_production", label: "Sản lượng thực tế (VND)" }, { key: "actual_vs_plan", label: "Thực tế so với giao (VND)" },
  { key: "production_rows_entered", label: "Số việc đã nhập sản lượng" },
];

export function toKpiExportRows(kpis: KpiExportRow[]) {
  return kpis.map(k => ({
    week_slot: k.week_slot, team_name: k.team_name,
    start_date: viDate(k.start_date), end_date: viDate(k.end_date), day_count: k.day_count,
    total_payroll: Math.round(Number(k.total_payroll)), total_production: Math.round(Number(k.total_production)),
    difference_vnd: Math.round(Number(k.difference_vnd)), evaluation: k.evaluation,
    actual_production: k.production_rows_entered === 0 ? "" : Math.round(Number(k.actual_production)),
    actual_vs_plan: k.production_rows_entered === 0 ? "" : Math.round(Number(k.actual_vs_plan)),
    production_rows_entered: k.production_rows_entered,
  }));
}
