"use client";

import { useState } from "react";
import { supabase } from "../lib/supabase";
import { sha256Hex } from "../lib/cnchWorkbook";
import { PriceWorkbook, SalaryWorkbook, parsePriceWorkbook, parseSalaryWorkbook } from "../lib/catalogWorkbook";
import { catalogImportError } from "./importErrors";

const money = new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND", maximumFractionDigits: 0 });
type Notify = (text: string) => void;

export function PriceCatalogImport({ notify, onChanged }: { notify: Notify; onChanged?: () => Promise<void> }) {
  const [file, setFile] = useState<File | null>(null),
    [preview, setPreview] = useState<PriceWorkbook | null>(null),
    [hash, setHash] = useState(""),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");

  async function inspect(next: File | null) {
    setFile(next); setPreview(null); setHash(""); setError("");
    if (!next) return;
    setBusy(true);
    try {
      const [parsed, digest] = await Promise.all([parsePriceWorkbook(next), sha256Hex(next)]);
      setPreview(parsed); setHash(digest);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Không đọc được file Excel.");
    } finally { setBusy(false); }
  }

  async function commit() {
    if (!file || !preview || busy) return;
    if (!window.confirm(
      `Cập nhật ${preview.items.length} dòng đơn giá thuộc ${preview.categories.length} hạng mục Cấp 1?\n\n` +
      `Hệ thống chỉ ghi khi toàn bộ file hợp lệ. Dòng cũ đang được việc chưa xóa sử dụng sẽ được giữ nguyên.`
    )) return;
    setBusy(true);
    const { data, error: rpcError } = await supabase.rpc("admin_import_price_catalog", {
      p_request_key: crypto.randomUUID(),
      p_source_name: file.name,
      p_source_sha256: hash,
      p_items: preview.items,
    });
    setBusy(false);
    if (rpcError) {
      setError(catalogImportError(rpcError.message));
      notify("Nhập đơn giá thất bại; dữ liệu cũ được giữ nguyên.");
      return;
    }
    const r = data as { item_count: number; category_count: number; deactivated_count: number; retained_referenced_count: number };
    notify(`Đã cập nhật ${r.item_count} đơn giá · ${r.category_count} hạng mục · ngừng dùng ${r.deactivated_count} dòng cũ · giữ lại ${r.retained_referenced_count} dòng đang có việc.`);
    setFile(null); setPreview(null); setHash("");
    if (onChanged) await onChanged();
  }

  const sample = preview?.items.slice(0, 5) ?? [];
  return <div className="card">
    <div className="card-header"><span className="ch-icon">💰</span><span className="ch-title">Cập nhật Danh mục &amp; Đơn giá bằng Excel</span><span className="badge badge-cyan">Chỉ Admin</span></div>
    <div className="card-body">
      <p className="import-help">
        File .xlsx cần các cột: <strong>Nội dung công việc (Cấp 2)</strong>, <strong>Đơn vị</strong>, <strong>Đơn giá NC dùng tính toán</strong>, <strong>Hạng mục thi công (Cấp 1)</strong>; tùy chọn <em>Mô tả kỹ thuật</em>, <em>Mã công việc</em>.
        Đơn giá trong file là con số dùng tính sản lượng/hòa vốn. Hệ thống tự suy ra đơn giá đã duyệt = đơn giá / 1,3.
        Nếu có bất kỳ dòng nào sai, toàn bộ dữ liệu cũ được giữ nguyên.
      </p>
      <a className="btn btn-secondary roster-template" href="/Mau_Don_Gia.xlsx" download>⬇️ Tải mẫu Excel đơn giá</a>
      <input className="form-control" type="file" accept=".xlsx" disabled={busy} onChange={e => void inspect(e.target.files?.[0] || null)} />
      {busy && <div className="loading-text">Đang kiểm tra file…</div>}
      {error && <div className="toast error static-toast">{error}</div>}
      {preview && <div className="import-preview">
        <strong>Đã kiểm tra: {preview.items.length} dòng đơn giá · {preview.categories.length} hạng mục Cấp 1{preview.duplicatesCollapsed > 0 && ` · gộp ${preview.duplicatesCollapsed} dòng trùng hệt nhau`}</strong>
        <span>SHA-256: {hash.slice(0, 16)}…</span>
        <div className="import-team-list">{preview.categories.slice(0, 20).map(c => <span className="badge badge-navy" key={c}>{c}</span>)}{preview.categories.length > 20 && <span className="badge badge-yellow">+{preview.categories.length - 20} hạng mục</span>}</div>
        <div className="table-wrap"><table><thead><tr><th>Cấp 1</th><th>Cấp 2</th><th>ĐV</th><th>Đơn giá tính toán</th><th>Đã duyệt (suy ra)</th></tr></thead><tbody>
          {sample.map(item => <tr key={`${item.category_name}-${item.content}`}>
            <td>{item.category_name}</td><td>{item.content}</td><td>{item.unit}</td>
            <td>{money.format(item.calc_price)}</td>
            <td>{money.format(Math.round((item.calc_price / 1.3) * 100) / 100)}</td>
          </tr>)}
        </tbody></table></div>
        <button className="btn btn-primary" disabled={busy} onClick={commit}>Xác nhận cập nhật đơn giá</button>
      </div>}
    </div>
  </div>;
}

export function SalaryStandardImport({ notify, onChanged }: { notify: Notify; onChanged?: () => Promise<void> }) {
  const [file, setFile] = useState<File | null>(null),
    [preview, setPreview] = useState<SalaryWorkbook | null>(null),
    [hash, setHash] = useState(""),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");

  async function inspect(next: File | null) {
    setFile(next); setPreview(null); setHash(""); setError("");
    if (!next) return;
    setBusy(true);
    try {
      const [parsed, digest] = await Promise.all([parseSalaryWorkbook(next), sha256Hex(next)]);
      setPreview(parsed); setHash(digest);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Không đọc được file Excel.");
    } finally { setBusy(false); }
  }

  async function commit() {
    if (!file || !preview || busy) return;
    const willWrite = preview.rows.length - preview.skippedZero;
    if (!window.confirm(
      `Cập nhật bảng lương chuẩn: ${willWrite} dòng sẽ được ghi, ${preview.skippedZero} dòng lương 0 sẽ bỏ qua.\n\n` +
      `Lương 1 ngày do hệ thống tự tính = lương tháng / 26. Chỉ ghi khi toàn bộ file hợp lệ.`
    )) return;
    setBusy(true);
    const { data, error: rpcError } = await supabase.rpc("admin_import_salary_standard", {
      p_request_key: crypto.randomUUID(),
      p_source_name: file.name,
      p_source_sha256: hash,
      p_rows: preview.rows,
    });
    setBusy(false);
    if (rpcError) {
      setError(catalogImportError(rpcError.message));
      notify("Nhập bảng lương thất bại; dữ liệu cũ được giữ nguyên.");
      return;
    }
    const r = data as { row_count: number; skipped_zero_count: number; deactivated_count: number; new_system_count: number; new_grade_count: number };
    notify(`Đã cập nhật ${r.row_count} dòng lương · bỏ qua ${r.skipped_zero_count} dòng lương 0 · ngừng dùng ${r.deactivated_count} dòng cũ · thêm ${r.new_system_count} hệ, ${r.new_grade_count} chức danh.`);
    setFile(null); setPreview(null); setHash("");
    if (onChanged) await onChanged();
  }

  return <div className="card">
    <div className="card-header"><span className="ch-icon">🧾</span><span className="ch-title">Cập nhật Bảng lương chuẩn bằng Excel</span><span className="badge badge-cyan">Chỉ Admin</span></div>
    <div className="card-body">
      <p className="import-help">
        File .xlsx cần đúng 3 cột: <strong>Hệ</strong>, <strong>Chức danh</strong>, <strong>Mức lương tháng (VNĐ)</strong>.
        Không nhập cột lương ngày — hệ thống tự tính lương tháng / 26. Dòng có mức lương 0 (thường là Tổ trưởng) sẽ được bỏ qua.
        Nếu có bất kỳ dòng nào sai, toàn bộ dữ liệu cũ được giữ nguyên.
      </p>
      <a className="btn btn-secondary roster-template" href="/Mau_Bang_Luong.xlsx" download>⬇️ Tải mẫu Excel bảng lương</a>
      <input className="form-control" type="file" accept=".xlsx" disabled={busy} onChange={e => void inspect(e.target.files?.[0] || null)} />
      {busy && <div className="loading-text">Đang kiểm tra file…</div>}
      {error && <div className="toast error static-toast">{error}</div>}
      {preview && <div className="import-preview">
        <strong>Đã kiểm tra: {preview.rows.length} dòng · {preview.systems.length} hệ · bỏ qua {preview.skippedZero} dòng lương 0</strong>
        <span>SHA-256: {hash.slice(0, 16)}…</span>
        <div className="import-team-list">{preview.systems.map(s => <span className="badge badge-navy" key={s}>{s}</span>)}</div>
        <div className="table-wrap"><table><thead><tr><th>Hệ</th><th>Chức danh</th><th>Lương tháng</th><th>Lương ngày (DB tính)</th></tr></thead><tbody>
          {preview.rows.filter(r => r.monthly_salary > 0).slice(0, 5).map(r => <tr key={`${r.system_name}-${r.grade_name}`}>
            <td>{r.system_name}</td><td>{r.grade_name}</td>
            <td>{money.format(r.monthly_salary)}</td>
            <td>{money.format(r.monthly_salary / 26)}</td>
          </tr>)}
        </tbody></table></div>
        <button className="btn btn-primary" disabled={busy} onClick={commit}>Xác nhận cập nhật bảng lương</button>
      </div>}
    </div>
  </div>;
}

export function CatalogAdminPage({ notify, onChanged }: { notify: Notify; onChanged?: () => Promise<void> }) {
  return <>
    <PriceCatalogImport notify={notify} onChanged={onChanged} />
    <div className="section-divider"><span>Bảng lương chuẩn theo Hệ × Chức danh</span></div>
    <SalaryStandardImport notify={notify} onChanged={onChanged} />
  </>;
}
