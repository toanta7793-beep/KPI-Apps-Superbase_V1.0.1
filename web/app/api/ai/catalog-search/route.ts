import { createClient } from "@supabase/supabase-js";
import {
  Candidate, LOI_NHAC_HE_THONG, decideSearchPath, dungPromptUngVien, gomCap1, locKetQuaAI,
} from "../../../../lib/catalogSearchLogic";

/**
 * Tìm hạng mục công việc: database trước, AI chỉ khi cần.
 *
 * Vì sao route này chạy ở MÁY CHỦ chứ không gọi thẳng OpenAI từ trình duyệt:
 * khóa API là secret. Gọi từ trình duyệt là đưa khóa cho bất kỳ ai mở DevTools.
 * Khóa nằm trong secret của Worker, không có trong mã nguồn, không vào Git.
 *
 * Ba tầng đảm bảo, theo thứ tự:
 *   1. Tìm bằng SQL. Có dòng khớp HẾT từ khóa -> trả luôn, KHÔNG gọi AI, không tốn tiền.
 *   2. Không có -> đưa tối đa 40 ứng viên CÓ THẬT cho mô hình xếp hạng.
 *   3. Mô hình trả về id nào không nằm trong danh sách đó -> loại bỏ.
 *
 * Hỏng ở đâu cũng KHÔNG được làm vỡ màn hình: thiếu khóa, hết hạn mức, quá thời gian chờ
 * đều rơi về kết quả tìm thường kèm một câu giải thích.
 */

const reply = (body: unknown, status = 200) =>
  Response.json(body, { status, headers: { "Cache-Control": "no-store" } });

const MODEL_MAC_DINH = "gpt-4o-mini";
const HAN_CHO_MS = 12_000;

export async function POST(request: Request) {
  try {
    const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "").trim();
    if (!token) return reply({ error: "UNAUTHENTICATED" }, 401);

    const body = (await request.json().catch(() => ({}))) as { query?: unknown };
    const query = typeof body.query === "string" ? body.query.trim() : "";
    if (query.length < 2) return reply({ error: "QUERY_TOO_SHORT" }, 400);
    if (query.length > 300) return reply({ error: "QUERY_TOO_LONG" }, 400);

    const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const publishable = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
    if (!url || !publishable) return reply({ error: "SERVER_NOT_CONFIGURED" }, 500);

    // Gọi bằng token của chính người dùng: hàm SQL tự kiểm hồ sơ hoạt động, nên route này
    // không cần (và không nên) dùng khóa quyền cao.
    const caller = createClient(url, publishable, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data, error } = await caller.rpc("search_catalog_candidates", { p_query: query, p_limit: 60 });
    if (error) return reply({ error: error.message }, 400);

    const rows = (data || []) as Candidate[];
    if (rows.length === 0) {
      return reply({ nguon: "tim-thuong", ket_qua: [], cap1: [], ghi_chu: "Không tìm thấy hạng mục nào khớp." });
    }

    const quyet_dinh = decideSearchPath(rows);
    if (quyet_dinh.nguon === "tim-thuong") {
      return reply({ nguon: "tim-thuong", ket_qua: quyet_dinh.ket_qua, cap1: gomCap1(quyet_dinh.ket_qua) });
    }

    const ungVien = quyet_dinh.ung_vien;
    const apiKey = process.env.OPENAI_API_KEY;
    // Chưa cấu hình khóa: tính năng tự tắt, màn hình vẫn dùng được với kết quả gần đúng.
    if (!apiKey) {
      const gan = ungVien.slice(0, 8);
      return reply({ nguon: "ai-tat", ket_qua: gan, cap1: gomCap1(gan),
        ghi_chu: "Chưa cấu hình AI nên đây là kết quả gần đúng theo từ khóa." });
    }

    const model = process.env.OPENAI_MODEL || MODEL_MAC_DINH;
    const huy = new AbortController();
    const dongHo = setTimeout(() => huy.abort(), HAN_CHO_MS);
    try {
      const res = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
        signal: huy.signal,
        body: JSON.stringify({
          model,
          // temperature 0: cùng câu hỏi phải ra cùng gợi ý, nếu không người dùng mất tin.
          temperature: 0,
          response_format: { type: "json_object" },
          messages: [
            { role: "system", content: LOI_NHAC_HE_THONG },
            { role: "user", content: JSON.stringify({ can_tim: query, ung_vien: dungPromptUngVien(ungVien) }) },
          ],
        }),
      });
      clearTimeout(dongHo);

      if (!res.ok) {
        const gan = ungVien.slice(0, 8);
        return reply({ nguon: "ai-loi", ket_qua: gan, cap1: gomCap1(gan),
          ghi_chu: `AI không trả lời được (mã ${res.status}). Đây là kết quả gần đúng theo từ khóa.` });
      }

      const payload = (await res.json()) as { choices?: Array<{ message?: { content?: string } }> };
      const noiDung = payload.choices?.[0]?.message?.content || "{}";
      let tho: unknown = {};
      try { tho = JSON.parse(noiDung); } catch { tho = {}; }

      const chon = locKetQuaAI(tho, ungVien);
      if (chon.length === 0) {
        const gan = ungVien.slice(0, 8);
        return reply({ nguon: "ai-khong-chon", ket_qua: gan, cap1: gomCap1(gan),
          ghi_chu: "AI không thấy hạng mục nào thật sự khớp. Đây là kết quả gần đúng theo từ khóa." });
      }
      return reply({ nguon: "ai", ket_qua: chon, cap1: gomCap1(chon) });
    } catch (loi) {
      clearTimeout(dongHo);
      const gan = ungVien.slice(0, 8);
      const quaHan = loi instanceof Error && loi.name === "AbortError";
      return reply({ nguon: "ai-loi", ket_qua: gan, cap1: gomCap1(gan),
        ghi_chu: quaHan ? "AI trả lời quá chậm. Đây là kết quả gần đúng theo từ khóa."
                        : "Không gọi được AI. Đây là kết quả gần đúng theo từ khóa." });
    }
  } catch (loi) {
    return reply({ error: loi instanceof Error ? loi.message : "CATALOG_SEARCH_FAILED" }, 400);
  }
}
