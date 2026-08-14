/**
 * Dựng tham số gọi suggest_job_staffing từ trạng thái biểu mẫu giao việc.
 *
 * Để riêng khỏi component vì đây là logic thuần: Node không nạp được JSX trong test, và một
 * quy tắc "bỏ trống ô nào thì gợi ý ô đó" mà không test được là quy tắc sẽ lệch dần.
 *
 * Ẩn số được chọn TƯỜNG MINH chứ không đoán từ ô nào trống. Lý do: ngày bắt đầu và ngày kết
 * thúc luôn có sẵn giá trị mặc định trên biểu mẫu, nên "số ngày" không bao giờ trống —
 * đoán mò sẽ không bao giờ chọn được chế độ gợi ý số ngày.
 */

export type SuggestMode = "NHAN_CONG" | "SO_NGAY" | "KHOI_LUONG";

export type JobFormState = {
  teamId: string;
  category: string;
  content: string;
  start: string;
  end: string;
  quantity: string;
  counts: { leader: string; w1: string; w2: string; w3: string; helper: string };
};

export type SuggestParams = {
  p_team_id: string; p_category_name: string; p_content: string;
  p_quantity: number | null; p_work_days: number | null;
  p_count_worker1: number | null; p_count_worker2: number | null;
  p_count_worker3: number | null; p_count_helper: number | null;
};

const num = (value: string) => { const n = Number(value); return Number.isFinite(n) ? n : 0 };

/** Số ngày tính CẢ hai đầu, giống hệt work_days của v_job_metrics. */
export function workDays(start: string, end: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(start) || !/^\d{4}-\d{2}-\d{2}$/.test(end)) return 0;
  const days = Math.round((Date.parse(end) - Date.parse(start)) / 86400000) + 1;
  return days > 0 ? days : 0;
}

/**
 * Trả về params, hoặc một câu giải thích còn thiếu gì. Kiểm ở đây để người dùng biết ngay
 * thiếu ô nào, thay vì gửi lên rồi nhận về "KHONG_DU_DU_LIEU".
 */
export function buildSuggestParams(form: JobFormState, mode: SuggestMode): SuggestParams | { error: string } {
  if (!form.teamId) return { error: "Chưa chọn Tổ thi công." };
  if (!form.category || !form.content) return { error: "Chưa chọn Hạng mục và Công việc — cần để tra đơn giá." };

  const days = workDays(form.start, form.end);
  const qty = num(form.quantity);
  const crew = {
    w1: num(form.counts.w1), w2: num(form.counts.w2),
    w3: num(form.counts.w3), helper: num(form.counts.helper),
  };
  const crewTotal = crew.w1 + crew.w2 + crew.w3 + crew.helper;

  // Mỗi chế độ cần đúng HAI nhóm dữ kiện; nhóm thứ ba là thứ đi hỏi.
  if (mode === "NHAN_CONG") {
    if (qty <= 0) return { error: "Nhập Tổng khối lượng trước, rồi mới gợi ý được nhân công." };
    if (days <= 0) return { error: "Chọn ngày bắt đầu và ngày kết thúc trước." };
  } else if (mode === "SO_NGAY") {
    if (qty <= 0) return { error: "Nhập Tổng khối lượng trước." };
    if (crewTotal <= 0) return { error: "Nhập số lượng nhân công trước (tổ trưởng không tính)." };
  } else {
    if (days <= 0) return { error: "Chọn ngày bắt đầu và ngày kết thúc trước." };
    if (crewTotal <= 0) return { error: "Nhập số lượng nhân công trước (tổ trưởng không tính)." };
  }

  return {
    p_team_id: form.teamId,
    p_category_name: form.category,
    p_content: form.content,
    // Ẩn số phải gửi null: hàm SQL dựa vào đó để biết cần giải cho cái gì.
    p_quantity: mode === "KHOI_LUONG" ? null : qty,
    p_work_days: mode === "SO_NGAY" ? null : days,
    p_count_worker1: mode === "NHAN_CONG" ? null : crew.w1,
    p_count_worker2: mode === "NHAN_CONG" ? null : crew.w2,
    p_count_worker3: mode === "NHAN_CONG" ? null : crew.w3,
    p_count_helper:  mode === "NHAN_CONG" ? null : crew.helper,
  };
}

/** Ngày kết thúc khi áp dụng gợi ý số ngày. Số ngày tính cả hai đầu nên trừ 1. */
export function endDateFor(start: string, days: number) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(start) || !(days >= 1)) return start;
  return new Date(Date.parse(start) + (days - 1) * 86400000).toISOString().slice(0, 10);
}
