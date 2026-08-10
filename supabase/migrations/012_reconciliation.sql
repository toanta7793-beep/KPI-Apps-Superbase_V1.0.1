-- =====================================================================
-- 012_reconciliation.sql · KPI MEP → Supabase (Phase 4 - migration tooling)
-- Schema RECONCILIATION: báo cáo đối chiếu (RECONCILIATION_SPEC §5).
-- Nguyên tắc: source_count = target_ok_count + rejected_count; không bỏ âm thầm (DD-18.6).
-- Ngoài 'public' => không expose API.
-- =====================================================================

create schema if not exists reconciliation;

create table if not exists reconciliation.reconciliation_summary (
  id uuid primary key default gen_random_uuid(),
  entity text not null,
  source_count int,
  target_ok_count int,
  rejected_count int,
  delta int generated always as (coalesce(source_count,0) - coalesce(target_ok_count,0) - coalesce(rejected_count,0)) stored,
  l2_checksum_source text,
  l2_checksum_target text,
  l2_pass boolean,
  run_at timestamptz not null default now()
);

create table if not exists reconciliation.rejected_records (
  id uuid primary key default gen_random_uuid(),
  entity text not null,
  source_row int,
  natural_key text,
  reason_code text not null,
  reason_note text,
  duplicate_type text,
  status text not null default 'PENDING',   -- PENDING/APPROVED/DISCARD_APPROVED
  decided_by text,
  decided_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists reconciliation.reconciliation_row_diff (
  id uuid primary key default gen_random_uuid(),
  entity text not null,
  natural_key text,
  field text,
  source_value text,
  target_value text,
  run_at timestamptz not null default now()
);

comment on schema reconciliation is 'Báo cáo đối chiếu nguồn↔đích. delta=0 nghĩa là không hụt (DD-18.6).';
