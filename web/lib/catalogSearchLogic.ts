/**
 * Logic thuần cho "AI tìm hạng mục công việc". Để riêng khỏi route để test nạp được.
 *
 * Nguyên tắc xuyên suốt: **AI không bao giờ được sinh ra tên hạng mục.**
 * Đơn giá tra theo cặp (hạng mục cấp 1 + nội dung) khớp DUY NHẤT một dòng đang dùng. Một cái
 * tên do mô hình bịa ra sẽ không tra được đơn giá, và người dùng chỉ phát hiện khi bấm Lưu và
 * bị từ chối — tức là mô hình phá đúng cái xương sống mà nó lẽ ra chỉ giúp tìm.
 * Nên mô hình chỉ được CHỌN id từ danh sách ứng viên có thật; mọi id lạ đều bị loại ở đây.
 */

export type Candidate = {
  price_item_id: string;
  category_name: string;
  content: string;
  unit: string | null;
  calc_price: number | null;
  so_tu_khop: number;
  tong_so_tu: number;
  khop_het: boolean;
};

export type SearchOutcome =
  | { nguon: "tim-thuong"; ket_qua: Candidate[] }
  | { nguon: "can-ai"; ung_vien: Candidate[] };

/**
 * Quyết định có cần hỏi AI không. Tìm thường ra kết quả khớp HẾT từ khóa thì dừng ở đó:
 * nhanh hơn, miễn phí, và chính xác hơn mọi suy đoán ngữ nghĩa.
 */
export function decideSearchPath(rows: Candidate[], soLuong = 8): SearchOutcome {
  const khopHet = rows.filter(r => r.khop_het);
  if (khopHet.length > 0) return { nguon: "tim-thuong", ket_qua: khopHet.slice(0, soLuong) };
  // Không có dòng nào khớp hết -> đưa ứng viên gần đúng cho AI xếp hạng.
  // Giới hạn số ứng viên gửi đi để chặn cả chi phí lẫn thời gian chờ.
  return { nguon: "can-ai", ung_vien: rows.slice(0, 40) };
}

/** Gom hạng mục Cấp 1 có chứa kết quả, kèm số lượng — phần người dùng hỏi tới. */
export function gomCap1(rows: Candidate[]) {
  const dem = new Map<string, number>();
  for (const r of rows) dem.set(r.category_name, (dem.get(r.category_name) || 0) + 1);
  return [...dem.entries()]
    .map(([category_name, so_muc]) => ({ category_name, so_muc }))
    .sort((a, b) => b.so_muc - a.so_muc || a.category_name.localeCompare(b.category_name, "vi"));
}

/** Rút gọn ứng viên trước khi gửi cho mô hình: chỉ những gì cần để nó chọn đúng. */
export function dungPromptUngVien(ungVien: Candidate[]) {
  return ungVien.map(c => ({
    id: c.price_item_id,
    hang_muc: c.category_name,
    noi_dung: c.content,
    don_vi: c.unit || "",
    don_gia: c.calc_price ?? null,
  }));
}

/**
 * Nhận kết quả thô từ mô hình, giữ lại DUY NHẤT những id có thật trong danh sách ứng viên.
 * Đây là hàng rào chống bịa: mô hình trả về id lạ, trùng, hay rác đều bị loại ở đây.
 */
export function locKetQuaAI(raw: unknown, ungVien: Candidate[], soLuong = 8) {
  const theoId = new Map(ungVien.map(c => [c.price_item_id, c]));
  const chon = (raw as { chon?: unknown })?.chon;
  if (!Array.isArray(chon)) return [] as Array<Candidate & { ly_do: string }>;

  const daLay = new Set<string>();
  const ketQua: Array<Candidate & { ly_do: string }> = [];
  for (const item of chon) {
    const id = typeof item === "string" ? item : (item as { id?: unknown })?.id;
    if (typeof id !== "string") continue;
    const goc = theoId.get(id);
    if (!goc || daLay.has(id)) continue;        // id bịa ra hoặc trùng -> bỏ
    daLay.add(id);
    const lyDoRaw = typeof item === "object" && item ? (item as { ly_do?: unknown }).ly_do : "";
    ketQua.push({ ...goc, ly_do: typeof lyDoRaw === "string" ? lyDoRaw.slice(0, 160) : "" });
    if (ketQua.length >= soLuong) break;
  }
  return ketQua;
}

export const LOI_NHAC_HE_THONG =
  "Bạn giúp kỹ sư cơ điện (MEP) tìm đúng hạng mục công việc trong danh mục đơn giá của công ty. " +
  "Người dùng mô tả công việc bằng tiếng Việt, có thể thiếu dấu, viết tắt, hoặc dùng cỡ/ký hiệu khác với danh mục. " +
  "Bạn CHỈ được chọn trong danh sách ứng viên được cung cấp, KHÔNG được tạo ra tên hạng mục mới và KHÔNG được sửa tên. " +
  "Nếu không ứng viên nào thực sự phù hợp, trả về danh sách rỗng thay vì chọn bừa. " +
  "Trả về JSON đúng dạng {\"chon\":[{\"id\":\"<id ứng viên>\",\"ly_do\":\"<một câu ngắn tiếng Việt>\"}]}, " +
  "xếp ứng viên phù hợp nhất lên đầu, tối đa 8 mục.";
