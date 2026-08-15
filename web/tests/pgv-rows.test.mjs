import test from "node:test";import assert from "node:assert/strict";import {buildPgvDisplayRows} from "../app/pgvRows.ts";
test("PGV keeps a six-row minimum for short weeks",()=>{const rows=buildPgvDisplayRows([{id:1},{id:2}]);assert.equal(rows.length,6);assert.equal(rows.filter(Boolean).length,2)});
test("PGV automatically grows beyond six rows without dropping jobs",()=>{const input=Array.from({length:12},(_,i)=>({id:i+1})),rows=buildPgvDisplayRows(input);assert.equal(rows.length,12);assert.deepEqual(rows,input)});

// --- Gộp mã nhóm thành một dòng phiếu (yêu cầu 14/08/2026) --------------------------------
import { mergePgvRows, ghepDuyNhat, cnchAssignOptions, cnchSaveValue, cnchSelectedValue, cnchDisplay } from "../app/pgvRows.ts";

const job = (over) => ({
  id: "j", group_code: null, location: "Phân khu 1.1", content: "Thi công X",
  quantity: 100, unit: "m", start_date: "2026-08-14", end_date: "2026-08-16",
  count_leader: 1, count_worker1: 0, count_worker2: 2, count_worker3: 0, count_helper: 3, ...over,
});

test("hai việc CÙNG mã nhóm gộp thành MỘT dòng, không mất việc nào", () => {
  const rows = mergePgvRows([
    job({ id: "a", group_code: "MN-1", location: "Phân khu 1.2", content: "Thi công Ống HDPE D110", quantity: 300, unit: "m" }),
    job({ id: "b", group_code: "MN-1", location: "Phân khu 1.1", content: "Thi công Phễu thu sàn DN100", quantity: 160.6, unit: "cái" }),
  ]);
  assert.equal(rows.length, 1, "phải gộp thành một dòng");
  assert.equal(rows[0].phan_khu, "Phân khu 1.2, Phân khu 1.1", "vị trí ghép bằng dấu phẩy");
  assert.equal(rows[0].vi_tri, rows[0].phan_khu);
  assert.deepEqual(rows[0].noi_dung, ["Thi công Ống HDPE D110", "Thi công Phễu thu sàn DN100"], "mỗi việc một dòng");
  assert.deepEqual(rows[0].muc_tieu, ["300 m", "160.6 cái"], "khối lượng khớp từng dòng nội dung");
  assert.equal(rows[0].noi_dung.length, rows[0].muc_tieu.length, "hai cột phải luôn cùng số dòng");
  assert.equal(rows[0].so_cn, 6, "số CN để chung, KHÔNG cộng dồn — vẫn là một tổ thợ");
  assert.equal(rows[0].start_date, "2026-08-14");
  assert.equal(rows[0].end_date, "2026-08-16");
});

test("việc KHÔNG có mã nhóm vẫn đứng riêng từng dòng", () => {
  const rows = mergePgvRows([job({ id: "a", content: "Việc A" }), job({ id: "b", content: "Việc B" })]);
  assert.equal(rows.length, 2);
  assert.deepEqual(rows.map(r => r.noi_dung[0]), ["Việc A", "Việc B"]);
});

test("nhóm nằm đúng vị trí của việc đầu tiên thuộc nhóm, không bị đẩy xuống cuối", () => {
  const rows = mergePgvRows([
    job({ id: "a", group_code: "MN-1", content: "Nhóm-1" }),
    job({ id: "b", content: "Lẻ" }),
    job({ id: "c", group_code: "MN-1", content: "Nhóm-2" }),
  ]);
  assert.equal(rows.length, 2);
  assert.deepEqual(rows[0].noi_dung, ["Nhóm-1", "Nhóm-2"]);
  assert.deepEqual(rows[1].noi_dung, ["Lẻ"]);
});

test("vị trí trùng nhau chỉ ghi một lần", () => {
  const rows = mergePgvRows([
    job({ id: "a", group_code: "MN-1", location: "Phân khu 1.1" }),
    job({ id: "b", group_code: "MN-1", location: "Phân khu 1.1" }),
  ]);
  assert.equal(rows[0].phan_khu, "Phân khu 1.1");
  assert.equal(ghepDuyNhat(["A", "", null, "A", "B"]), "A, B");
});

// --- PGV CNCH: đầu mục gộp ----------------------------------------------------------------
const cnchJobs = [
  { id: "j1", content: "Thi công Ống HDPE D110", location: "Phân khu 1.2", group_code: "MN-1" },
  { id: "j2", content: "Thi công Phễu thu sàn DN100", location: "Phân khu 1.1", group_code: "MN-1" },
  { id: "j3", content: "Việc lẻ", location: "Phân khu 2", group_code: null },
];

test("ô chọn giữ từng việc VÀ thêm một đầu mục gộp cho mỗi mã nhóm", () => {
  const o = cnchAssignOptions(cnchJobs);
  assert.deepEqual(o.slice(0, 3).map(x => x.label), ["Thi công Ống HDPE D110", "Thi công Phễu thu sàn DN100", "Việc lẻ"]);
  assert.equal(o.length, 4, "ba việc + một đầu mục gộp");
  assert.equal(o[3].label, "Thi công Ống HDPE D110, Thi công Phễu thu sàn DN100");
  assert.equal(o[3].value, "grp:MN-1");
});

test("mã nhóm chỉ có MỘT việc thì không sinh đầu mục gộp trùng lặp", () => {
  const o = cnchAssignOptions([{ id: "j1", content: "Một mình", group_code: "MN-9" }]);
  assert.equal(o.length, 1);
});

test("lưu đầu mục gộp: neo vào việc đầu của nhóm, nhãn nằm ở content_label", () => {
  assert.deepEqual(cnchSaveValue("grp:MN-1", cnchJobs),
    { job_id: "j1", content_label: "Thi công Ống HDPE D110, Thi công Phễu thu sàn DN100" });
  assert.deepEqual(cnchSaveValue("j3", cnchJobs), { job_id: "j3", content_label: null });
  assert.deepEqual(cnchSaveValue("OFF", cnchJobs), { job_id: null, content_label: null });
  assert.deepEqual(cnchSaveValue("grp:KHONG-CO", cnchJobs), { job_id: null, content_label: null });
});

test("mở lại phiếu thì ô chọn hiện đúng thứ đã lưu", () => {
  // Nhãn phải khớp CHÍNH XÁC nhãn gộp của nhóm mới được coi là dòng gộp.
  assert.equal(cnchSelectedValue({ job_id: "j1", content_label: "Thi công Ống HDPE D110, Thi công Phễu thu sàn DN100" }, cnchJobs), "grp:MN-1");
  assert.equal(cnchSelectedValue({ job_id: "j3", content_label: null }, cnchJobs), "j3");
  assert.equal(cnchSelectedValue(undefined, cnchJobs), "OFF");
  assert.equal(cnchSelectedValue({ job_id: null }, cnchJobs), "OFF");
});

test("phiếu in dòng gộp: nội dung là nhãn đã lưu, vị trí ghép của cả nhóm", () => {
  const g = cnchDisplay({ job_id: "j1", content_label: "Thi công Ống HDPE D110, Thi công Phễu thu sàn DN100" }, cnchJobs);
  assert.equal(g.content, "Thi công Ống HDPE D110, Thi công Phễu thu sàn DN100");
  assert.equal(g.location, "Phân khu 1.2, Phân khu 1.1");
  const le = cnchDisplay({ job_id: "j3" }, cnchJobs);
  assert.deepEqual(le, { content: "Việc lẻ", location: "Phân khu 2" });
  assert.deepEqual(cnchDisplay(undefined, cnchJobs), { content: "OFF", location: "" });
});

test("chọn MỘT việc lẻ mà việc đó nằm trong nhóm — KHÔNG được hiểu nhầm thành dòng gộp", () => {
  // Hàm lưu vốn luôn ghi content_label = nội dung việc, kể cả với phân công lẻ.
  const le = { job_id: "j1", content_label: "Thi công Ống HDPE D110" };
  assert.equal(cnchSelectedValue(le, cnchJobs), "j1", "phải hiện đúng việc lẻ, không phải nhóm");
  assert.deepEqual(cnchDisplay(le, cnchJobs),
    { content: "Thi công Ống HDPE D110", location: "Phân khu 1.2" },
    "vị trí chỉ của việc đó, KHÔNG ghép cả nhóm");
});

test("bản ghi cũ lưu trước khi có tính năng gộp vẫn đọc đúng", () => {
  const cu = { job_id: "j2", content_label: "Thi công Phễu thu sàn DN100" };
  assert.equal(cnchSelectedValue(cu, cnchJobs), "j2");
  assert.equal(cnchDisplay(cu, cnchJobs).location, "Phân khu 1.1");
});
