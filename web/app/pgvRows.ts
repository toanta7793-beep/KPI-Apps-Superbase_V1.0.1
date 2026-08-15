/**
 * Dựng dòng cho phiếu PGV. Dùng chung cho BẢN IN HTML và BẢN PDF.
 *
 * Vì sao phải dùng chung: hai bản in cùng một phiếu mà tính dòng ở hai nơi thì sớm muộn sẽ
 * lệch nhau, và người dùng chỉ phát hiện khi cầm hai tờ giấy khác nhau trên tay.
 */

export type PgvJobLike = {
  id: string;
  group_code: string | null;
  location: string | null;
  content: string;
  quantity: number;
  unit: string | null;
  start_date: string;
  end_date: string;
  count_leader: number; count_worker1: number; count_worker2: number;
  count_worker3: number; count_helper: number;
};

/** Số người của một việc. Tổ trưởng CÓ tính ở đây vì phiếu in đếm đầu người có mặt. */
export const pgvPeople = (j: Pick<PgvJobLike, "count_leader" | "count_worker1" | "count_worker2" | "count_worker3" | "count_helper">) =>
  j.count_leader + j.count_worker1 + j.count_worker2 + j.count_worker3 + j.count_helper;

/** Ghép danh sách, bỏ rỗng và bỏ trùng. "Phân khu 1.1, Phân khu 1.1" đọc rất vô lý. */
export const ghepDuyNhat = (values: Array<string | null | undefined>) =>
  [...new Set(values.map(v => (v || "").trim()).filter(Boolean))].join(", ");

export type PgvRow = {
  key: string;
  group_code: string | null;
  phan_khu: string;
  vi_tri: string;
  /** Mỗi việc một dòng trong cùng một ô. */
  noi_dung: string[];
  /** Khối lượng tương ứng TỪNG dòng nội dung — hai mảng này phải luôn cùng độ dài. */
  muc_tieu: string[];
  so_cn: number;
  start_date: string;
  end_date: string;
};

/**
 * Gộp các việc CÙNG MÃ NHÓM thành MỘT dòng phiếu (yêu cầu 14/08/2026).
 *
 * Không phải là bỏ bớt việc: mọi việc vẫn hiện, chỉ nằm thành nhiều dòng bên trong một ô.
 * Đây là điểm khác hẳn cách làm cũ trước migration 031 — hồi đó phiếu chỉ in một việc đại
 * diện cho cả nhóm và **mất hẳn** các việc còn lại. Quy tắc nghiệp vụ "gộp mã nhóm không được
 * làm mất dòng trên phiếu in" vẫn được giữ nguyên.
 *
 * Việc không có mã nhóm đứng riêng một dòng như cũ.
 * Thứ tự giữ theo thứ tự đầu vào; nhóm xuất hiện ở vị trí của việc đầu tiên thuộc nhóm đó.
 */
export function mergePgvRows(jobs: PgvJobLike[]): PgvRow[] {
  const rows: PgvRow[] = [];
  const viTriNhom = new Map<string, number>();   // group_code -> chỉ số dòng trong rows
  const jobsCuaNhom = new Map<string, PgvJobLike[]>();

  for (const job of jobs) {
    const ma = job.group_code;
    if (!ma) {
      rows.push({
        key: job.id, group_code: null,
        phan_khu: job.location || "", vi_tri: job.location || "",
        noi_dung: [job.content],
        muc_tieu: [`${job.quantity} ${job.unit || ""}`.trim()],
        so_cn: pgvPeople(job),
        start_date: job.start_date, end_date: job.end_date,
      });
      continue;
    }
    if (!viTriNhom.has(ma)) {
      viTriNhom.set(ma, rows.length);
      jobsCuaNhom.set(ma, []);
      rows.push({
        key: `grp:${ma}`, group_code: ma,
        phan_khu: "", vi_tri: "", noi_dung: [], muc_tieu: [],
        // Cùng mã nhóm thì cơ cấu nhân sự giống hệt nhau (create_job_group bắt buộc), nên
        // lấy của việc đầu là đúng — KHÔNG cộng dồn, vì đó vẫn là một tổ thợ.
        so_cn: pgvPeople(job),
        start_date: job.start_date, end_date: job.end_date,
      });
    }
    jobsCuaNhom.get(ma)!.push(job);
  }

  // Điền các ô gộp sau khi đã biết đủ thành viên của từng nhóm.
  for (const [ma, ds] of jobsCuaNhom) {
    const row = rows[viTriNhom.get(ma)!];
    row.phan_khu = ghepDuyNhat(ds.map(j => j.location));
    row.vi_tri = row.phan_khu;
    row.noi_dung = ds.map(j => j.content);
    row.muc_tieu = ds.map(j => `${j.quantity} ${j.unit || ""}`.trim());
  }
  return rows;
}

// ---------------------------------------------------------------------------------------
// PGV CNCH: ô chọn phân công
// ---------------------------------------------------------------------------------------

export type CnchOption = { value: string; label: string };

/**
 * Danh sách chọn cho cột "Phân công": từng việc một, CỘNG THÊM một đầu mục gộp cho mỗi mã
 * nhóm (quyết định 14/08/2026) để phân công được người làm nhiều hạng mục cùng lúc.
 *
 * Chỉ sinh đầu mục gộp theo MÃ NHÓM chứ không sinh mọi tổ hợp: mã nhóm đã đúng nghĩa "cùng
 * tổ thợ, cùng khoảng ngày, làm cùng lúc", còn liệt kê mọi tổ hợp thì 5 việc đã ra 26 dòng.
 */
export function cnchAssignOptions(jobs: Array<Pick<PgvJobLike, "id" | "content" | "group_code">>): CnchOption[] {
  const options: CnchOption[] = jobs.map(j => ({ value: j.id, label: j.content }));
  const theoNhom = new Map<string, string[]>();
  for (const j of jobs) {
    if (!j.group_code) continue;
    if (!theoNhom.has(j.group_code)) theoNhom.set(j.group_code, []);
    theoNhom.get(j.group_code)!.push(j.content);
  }
  for (const [ma, contents] of theoNhom) {
    // Một việc lẻ mang mã nhóm thì đầu mục gộp trùng y hệt việc đó — thêm vào chỉ gây rối.
    if (contents.length < 2) continue;
    options.push({ value: `grp:${ma}`, label: contents.join(", ") });
  }
  return options;
}

/** Tách giá trị ô chọn thành thứ cần lưu xuống database. */
export function cnchSaveValue(
  value: string,
  jobs: Array<Pick<PgvJobLike, "id" | "content" | "group_code">>,
): { job_id: string | null; content_label: string | null } {
  if (!value || value === "OFF") return { job_id: null, content_label: null };
  if (!value.startsWith("grp:")) return { job_id: value, content_label: null };
  const ma = value.slice(4);
  const ds = jobs.filter(j => j.group_code === ma);
  if (ds.length === 0) return { job_id: null, content_label: null };
  // Neo vào việc đầu của nhóm để giữ khóa ngoại thật; nhãn hiển thị nằm ở content_label.
  return { job_id: ds[0].id, content_label: ds.map(j => j.content).join(", ") };
}

type CnchItem = { job_id?: string | null; content_label?: string | null };

/**
 * Bản ghi này có phải một dòng GỘP không? Trả về các việc của nhóm nếu đúng.
 *
 * Không thể chỉ dựa vào "có content_label và việc neo thuộc một nhóm": hàm lưu vốn LUÔN ghi
 * content_label bằng nội dung của việc, kể cả khi người dùng chọn một việc lẻ mà việc đó
 * tình cờ nằm trong nhóm. Dựa vào đó sẽ hiểu nhầm phân công lẻ thành phân công gộp và in ra
 * vị trí của cả nhóm.
 * Nên phải so KHỚP CHÍNH XÁC nhãn đã lưu với nhãn gộp của nhóm. Cách này cũng đọc đúng các
 * bản ghi cũ lưu từ trước khi có tính năng gộp.
 */
function nhomGopCuaBanGhi<T extends Pick<PgvJobLike, "id" | "content" | "group_code">>(
  item: CnchItem | undefined,
  jobs: T[],
): T[] | null {
  const neo = item?.job_id ? jobs.find(j => j.id === item.job_id) : undefined;
  if (!neo?.group_code || !item?.content_label) return null;
  const ds = jobs.filter(j => j.group_code === neo.group_code);
  if (ds.length < 2) return null;
  return item.content_label === ds.map(j => j.content).join(", ") ? ds : null;
}

/** Từ bản ghi đã lưu, suy ngược ra giá trị đang chọn của ô. */
export function cnchSelectedValue(
  item: CnchItem | undefined,
  jobs: Array<Pick<PgvJobLike, "id" | "content" | "group_code">>,
): string {
  if (!item?.job_id) return "OFF";
  const nhom = nhomGopCuaBanGhi(item, jobs);
  if (nhom) return `grp:${nhom[0].group_code}`;
  return item.job_id;
}

/**
 * Nội dung và vị trí hiển thị trên phiếu in CNCH.
 * Dòng gộp lấy nhãn đã lưu và ghép vị trí của mọi việc trong nhóm (quyết định 14/08/2026).
 */
export function cnchDisplay(
  item: CnchItem | undefined,
  jobs: Array<Pick<PgvJobLike, "id" | "content" | "location" | "group_code">>,
): { content: string; location: string } {
  const neo = item?.job_id ? jobs.find(j => j.id === item.job_id) : undefined;
  if (!neo) return { content: "OFF", location: "" };
  const nhom = nhomGopCuaBanGhi(item, jobs);
  if (nhom) return { content: item!.content_label!, location: ghepDuyNhat(nhom.map(j => j.location)) };
  return { content: neo.content, location: neo.location || "" };
}

/** Đệm cho đủ số dòng tối thiểu của mẫu phiếu. Giữ nguyên hành vi cũ. */
export function buildPgvDisplayRows<T>(rows: T[], minimumRows = 6): (T | null)[] {
  return Array.from({ length: Math.max(minimumRows, rows.length) }, (_, index) => rows[index] || null);
}
