-- =====================================================================
-- 021_jobs_shadow_source_key.sql · Phase 9E/9F prerequisite
-- Stable source identity for idempotent Sheet -> Supabase staging sync.
-- No operational write path is enabled by this migration.
-- =====================================================================

alter table public.jobs
  add column if not exists legacy_source_row int;

comment on column public.jobs.legacy_source_row is
  'Dòng nguồn GIAO_VIEC_HOA_VON (>=4), dùng cho shadow sync idempotent và reconciliation; không trả qua safe RPC.';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.jobs'::regclass
      and conname = 'ck_jobs_legacy_source_row'
  ) then
    alter table public.jobs
      add constraint ck_jobs_legacy_source_row
      check (legacy_source_row is null or legacy_source_row >= 4);
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.jobs'::regclass
      and conname = 'uq_jobs_legacy_source_row'
  ) then
    alter table public.jobs
      add constraint uq_jobs_legacy_source_row unique (legacy_source_row);
  end if;
end;
$$;
