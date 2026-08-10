-- =====================================================================
-- 006_triggers.sql · KPI MEP → Supabase (Phase 4 Foundation)
-- Gắn trigger updated_at cho các bảng có cột updated_at.
-- Idempotent: drop trigger if exists + create.
-- (job_history, pgv_print_log chỉ có created_at → không gắn.)
-- =====================================================================

do $$
declare t text;
begin
  foreach t in array array[
    'systems','salary_grades','salary_standards','work_categories','price_items',
    'teams','workers','jobs','assignments','roles'
  ] loop
    execute format('drop trigger if exists trg_set_updated_at on public.%I;', t);
    execute format(
      'create trigger trg_set_updated_at before update on public.%I
         for each row execute function app.set_updated_at();', t);
  end loop;
end $$;
