"use client";
import { useCallback, useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";
import { WorkerRosterImport } from "./WorkerRosterImport";
import { operationError } from "./importErrors";

type Team = { id: string; leader_name: string; is_active: boolean };
type Row = { team_id: string; team_name: string; role_name: string; worker_count: number; total_daily: number; status: string; unknown_workers: Array<{ mnv: string }> };
const money = new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND", maximumFractionDigits: 0 });

// Quỹ lương của MỘT tổ tốn khoảng 200ms; lấy hết các tổ cùng lúc tốn ~1 giây CPU và
// khi nhiều người mở trang cùng lúc thì chạm trần statement timeout của Postgres
// (đo trên staging: 10 phiên đồng thời -> 10/10 thất bại). Vì vậy mặc định chỉ tải
// tổ đang chọn; xem toàn bộ là thao tác phải bấm có chủ đích.
export function TeamPayrollPanel({ teams, canEdit, onChanged, notify }: { teams: Team[]; canEdit: boolean; onChanged: () => Promise<void>; notify: (v: string) => void }) {
  const active = useMemo(() => teams.filter(t => t.is_active), [teams]);
  const [rows, setRows] = useState<Row[]>([]);
  const [teamId, setTeamId] = useState("");
  const [allTeams, setAllTeams] = useState(false);
  const [error, setError] = useState("");

  const effective = teamId || active[0]?.id || "";

  // Dùng cho các nút bấm (nhập Excel xong thì tải lại). Không gọi từ trong effect.
  const load = useCallback(async (scope: string | null) => {
    const { data, error: rpcError } = await supabase.rpc("get_payroll_summary", { p_team_id: scope });
    if (rpcError) { setError(operationError(rpcError.message)); setRows([]); return; }
    setRows((data || []) as Row[]);
    setError("");
  }, []);

  useEffect(() => {
    if (!allTeams && !effective) return;
    let alive = true;
    void supabase.rpc("get_payroll_summary", { p_team_id: allTeams ? null : effective })
      .then(({ data, error: rpcError }) => {
        if (!alive) return;
        if (rpcError) { setError(operationError(rpcError.message)); setRows([]); }
        else { setRows((data || []) as Row[]); setError(""); }
      });
    return () => { alive = false; };
  }, [allTeams, effective]);

  // "Đang tải" suy ra từ dữ liệu đã có, không cần state riêng.
  const ready = allTeams ? rows.length > 0 : rows.some(r => r.team_id === effective);
  const shown = allTeams ? active : active.filter(t => t.id === effective);
  const byTeam = useMemo(() => new Map(shown.map(t => [t.id, rows.filter(r => r.team_id === t.id)])), [shown, rows]);
  const grandTotal = rows.reduce((s, r) => s + Number(r.total_daily), 0);

  return <>
    {canEdit && <WorkerRosterImport teams={teams} onChanged={async () => { await onChanged(); await load(allTeams ? null : effective || null); }} notify={notify} />}
    <div className="section-divider"><span>Quỹ lương theo Tổ</span></div>
    <div className="card no-print"><div className="card-body filters-row">
      <select className="form-control" value={effective} disabled={allTeams} onChange={e => setTeamId(e.target.value)}>
        {active.map(t => <option key={t.id} value={t.id}>{t.leader_name}</option>)}
      </select>
      <label className="checkbox-line">
        <input type="checkbox" checked={allTeams} onChange={e => setAllTeams(e.target.checked)} />
        <span>Xem tất cả {active.length} tổ (chậm hơn)</span>
      </label>
      {!ready && !error && <span className="loading-text">Đang tính quỹ lương…</span>}
    </div></div>
    {error && <div className="toast error static-toast">{error}</div>}
    {allTeams && rows.length > 0 && <div className="card"><div className="card-body payroll-total">
      <span>Tổng quỹ lương ngày của {active.length} tổ</span><strong>{money.format(grandTotal)}</strong>
    </div></div>}
    <div className="payroll-grid">{shown.map(team => {
      const group = byTeam.get(team.id) || [], unknown = group[0]?.unknown_workers || [];
      return <article className="payroll-card" key={team.id}>
        <div className="payroll-title"><strong>{team.leader_name}</strong><span>{group.reduce((s, r) => s + Number(r.worker_count), 0)} người</span></div>
        <div className="grade-list">{group.map(r => <div key={r.role_name}><span>{r.role_name}</span><b>{r.worker_count} · {money.format(Number(r.total_daily))}/ngày</b></div>)}</div>
        <div className="payroll-total"><span>Tổng quỹ lương ngày</span><strong>{money.format(group.reduce((s, r) => s + Number(r.total_daily), 0))}</strong></div>
        {unknown.length > 0 && <div className="login-error">{unknown.length} CNCH chưa xác định Hệ/Bậc</div>}
      </article>;
    })}</div>
  </>;
}
