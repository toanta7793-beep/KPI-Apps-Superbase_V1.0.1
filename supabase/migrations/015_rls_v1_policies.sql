-- =====================================================================
-- 015_rls_v1_policies.sql · Phase 8C-v1 · RLS FAIL-CLOSED theo ma trận 8C-v1 đã chốt.
-- Chỉ 9 bảng trong scope: profiles, systems, work_categories, salary_standards,
--   price_items, workers, teams, assignments, jobs.
-- KHÔNG hiện thực: SYSTEM scope, supervisor_systems, payroll/KPI/report guard,
--   NHAN_VIEN update completed_qty, jobs update/delete theo approval-state, XEM view an toàn,
--   TO_TRUONG đọc price_items.
-- Nguyên tắc: TO authenticated (anon deny mặc định) · authorize CHỈ theo app.current_role()
--   (KHÔNG dùng roles.level) · NULL anchor => match rỗng (deny) · 1 policy/(bảng,lệnh) tránh chồng lấn
--   · INSERT chỉ WITH CHECK · UPDATE có cả USING + WITH CHECK · không FOR ALL · không USING(true) cho bảng nhạy cảm.
-- GRANT DML cho authenticated (RLS chặn hàng); bảng ngoài scope KHÔNG grant => deny-all.
-- =====================================================================
set search_path = public;

grant usage on schema public to authenticated;   -- idempotent

-- RLS bật (idempotent) cho 9 bảng scope.
alter table public.profiles          enable row level security;
alter table public.systems           enable row level security;
alter table public.work_categories   enable row level security;
alter table public.salary_standards  enable row level security;
alter table public.price_items       enable row level security;
alter table public.workers           enable row level security;
alter table public.teams             enable row level security;
alter table public.assignments       enable row level security;
alter table public.jobs              enable row level security;

-- =========================================================
-- profiles: ADMIN ALL; GS/TT/NV/XEM SELECT SELF; ngoài ADMIN không write.
-- =========================================================
grant select, insert, update, delete on public.profiles to authenticated;
drop policy if exists p_v1_profiles_select on public.profiles;
create policy p_v1_profiles_select on public.profiles for select to authenticated
  using ( (auth_user_id = auth.uid() and is_active = true) or app.current_role() = 'ADMIN' );
drop policy if exists p_v1_profiles_insert on public.profiles;
create policy p_v1_profiles_insert on public.profiles for insert to authenticated
  with check ( app.current_role() = 'ADMIN' );
drop policy if exists p_v1_profiles_update on public.profiles;
create policy p_v1_profiles_update on public.profiles for update to authenticated
  using ( app.current_role() = 'ADMIN' ) with check ( app.current_role() = 'ADMIN' );
drop policy if exists p_v1_profiles_delete on public.profiles;
create policy p_v1_profiles_delete on public.profiles for delete to authenticated
  using ( app.current_role() = 'ADMIN' );

-- =========================================================
-- systems & work_categories: SELECT mọi profile active; write ADMIN.
-- =========================================================
grant select, insert, update, delete on public.systems, public.work_categories to authenticated;

drop policy if exists p_v1_systems_select on public.systems;
create policy p_v1_systems_select on public.systems for select to authenticated
  using ( app.is_active_profile() );
drop policy if exists p_v1_systems_insert on public.systems;
create policy p_v1_systems_insert on public.systems for insert to authenticated
  with check ( app.current_role() = 'ADMIN' );
drop policy if exists p_v1_systems_update on public.systems;
create policy p_v1_systems_update on public.systems for update to authenticated
  using ( app.current_role() = 'ADMIN' ) with check ( app.current_role() = 'ADMIN' );
drop policy if exists p_v1_systems_delete on public.systems;
create policy p_v1_systems_delete on public.systems for delete to authenticated
  using ( app.current_role() = 'ADMIN' );

drop policy if exists p_v1_wcat_select on public.work_categories;
create policy p_v1_wcat_select on public.work_categories for select to authenticated
  using ( app.is_active_profile() );
drop policy if exists p_v1_wcat_insert on public.work_categories;
create policy p_v1_wcat_insert on public.work_categories for insert to authenticated
  with check ( app.current_role() = 'ADMIN' );
drop policy if exists p_v1_wcat_update on public.work_categories;
create policy p_v1_wcat_update on public.work_categories for update to authenticated
  using ( app.current_role() = 'ADMIN' ) with check ( app.current_role() = 'ADMIN' );
drop policy if exists p_v1_wcat_delete on public.work_categories;
create policy p_v1_wcat_delete on public.work_categories for delete to authenticated
  using ( app.current_role() = 'ADMIN' );

-- =========================================================
-- salary_standards & price_items: chỉ ADMIN (mọi lệnh). role khác deny.
-- =========================================================
grant select, insert, update, delete on public.salary_standards, public.price_items to authenticated;

drop policy if exists p_v1_salary_select on public.salary_standards;
create policy p_v1_salary_select on public.salary_standards for select to authenticated
  using ( app.current_role() = 'ADMIN' );
drop policy if exists p_v1_salary_insert on public.salary_standards;
create policy p_v1_salary_insert on public.salary_standards for insert to authenticated
  with check ( app.current_role() = 'ADMIN' );
drop policy if exists p_v1_salary_update on public.salary_standards;
create policy p_v1_salary_update on public.salary_standards for update to authenticated
  using ( app.current_role() = 'ADMIN' ) with check ( app.current_role() = 'ADMIN' );
drop policy if exists p_v1_salary_delete on public.salary_standards;
create policy p_v1_salary_delete on public.salary_standards for delete to authenticated
  using ( app.current_role() = 'ADMIN' );

drop policy if exists p_v1_price_select on public.price_items;
create policy p_v1_price_select on public.price_items for select to authenticated
  using ( app.current_role() = 'ADMIN' );
drop policy if exists p_v1_price_insert on public.price_items;
create policy p_v1_price_insert on public.price_items for insert to authenticated
  with check ( app.current_role() = 'ADMIN' );
drop policy if exists p_v1_price_update on public.price_items;
create policy p_v1_price_update on public.price_items for update to authenticated
  using ( app.current_role() = 'ADMIN' ) with check ( app.current_role() = 'ADMIN' );
drop policy if exists p_v1_price_delete on public.price_items;
create policy p_v1_price_delete on public.price_items for delete to authenticated
  using ( app.current_role() = 'ADMIN' );

-- =========================================================
-- workers: ADMIN ALL; TO_TRUONG SELECT TEAM; NHAN_VIEN SELECT SELF; GS/XEM deny.
-- =========================================================
grant select, insert, update, delete on public.workers to authenticated;

drop policy if exists p_v1_workers_select on public.workers;
create policy p_v1_workers_select on public.workers for select to authenticated
  using (
        app.current_role() = 'ADMIN'
     or (app.current_role() = 'TO_TRUONG' and team_id = app.current_team_id())
     or (app.current_role() = 'NHAN_VIEN' and id      = app.current_worker_id())
  );
drop policy if exists p_v1_workers_insert on public.workers;
create policy p_v1_workers_insert on public.workers for insert to authenticated
  with check ( app.current_role() = 'ADMIN' );
drop policy if exists p_v1_workers_update on public.workers;
create policy p_v1_workers_update on public.workers for update to authenticated
  using ( app.current_role() = 'ADMIN' ) with check ( app.current_role() = 'ADMIN' );
drop policy if exists p_v1_workers_delete on public.workers;
create policy p_v1_workers_delete on public.workers for delete to authenticated
  using ( app.current_role() = 'ADMIN' );

-- =========================================================
-- teams: ADMIN ALL; TO_TRUONG/NHAN_VIEN SELECT tổ mình; GS/XEM deny.
-- =========================================================
grant select, insert, update, delete on public.teams to authenticated;

drop policy if exists p_v1_teams_select on public.teams;
create policy p_v1_teams_select on public.teams for select to authenticated
  using (
        app.current_role() = 'ADMIN'
     or (app.current_role() in ('TO_TRUONG','NHAN_VIEN') and id = app.current_team_id())
  );
drop policy if exists p_v1_teams_insert on public.teams;
create policy p_v1_teams_insert on public.teams for insert to authenticated
  with check ( app.current_role() = 'ADMIN' );
drop policy if exists p_v1_teams_update on public.teams;
create policy p_v1_teams_update on public.teams for update to authenticated
  using ( app.current_role() = 'ADMIN' ) with check ( app.current_role() = 'ADMIN' );
drop policy if exists p_v1_teams_delete on public.teams;
create policy p_v1_teams_delete on public.teams for delete to authenticated
  using ( app.current_role() = 'ADMIN' );

-- =========================================================
-- assignments: ADMIN ALL; TO_TRUONG CRUD TEAM; NHAN_VIEN SELECT SELF; GS/XEM deny.
-- =========================================================
grant select, insert, update, delete on public.assignments to authenticated;

drop policy if exists p_v1_assign_select on public.assignments;
create policy p_v1_assign_select on public.assignments for select to authenticated
  using (
        app.current_role() = 'ADMIN'
     or (app.current_role() = 'TO_TRUONG' and team_id   = app.current_team_id())
     or (app.current_role() = 'NHAN_VIEN' and worker_id = app.current_worker_id())
  );
drop policy if exists p_v1_assign_insert on public.assignments;
create policy p_v1_assign_insert on public.assignments for insert to authenticated
  with check (
        app.current_role() = 'ADMIN'
     or (app.current_role() = 'TO_TRUONG' and team_id = app.current_team_id())
  );
drop policy if exists p_v1_assign_update on public.assignments;
create policy p_v1_assign_update on public.assignments for update to authenticated
  using (
        app.current_role() = 'ADMIN'
     or (app.current_role() = 'TO_TRUONG' and team_id = app.current_team_id())
  ) with check (
        app.current_role() = 'ADMIN'
     or (app.current_role() = 'TO_TRUONG' and team_id = app.current_team_id())
  );
drop policy if exists p_v1_assign_delete on public.assignments;
create policy p_v1_assign_delete on public.assignments for delete to authenticated
  using (
        app.current_role() = 'ADMIN'
     or (app.current_role() = 'TO_TRUONG' and team_id = app.current_team_id())
  );

-- =========================================================
-- jobs: ADMIN ALL; TO_TRUONG SELECT + INSERT TEAM; UPDATE/DELETE ADMIN-only (v1); GS/NV/XEM deny.
-- =========================================================
grant select, insert, update, delete on public.jobs to authenticated;

drop policy if exists p_v1_jobs_select on public.jobs;
create policy p_v1_jobs_select on public.jobs for select to authenticated
  using (
        app.current_role() = 'ADMIN'
     or (app.current_role() = 'TO_TRUONG' and team_id = app.current_team_id())
  );
drop policy if exists p_v1_jobs_insert on public.jobs;
create policy p_v1_jobs_insert on public.jobs for insert to authenticated
  with check (
        app.current_role() = 'ADMIN'
     or (app.current_role() = 'TO_TRUONG' and team_id = app.current_team_id())
  );
drop policy if exists p_v1_jobs_update on public.jobs;
create policy p_v1_jobs_update on public.jobs for update to authenticated
  using ( app.current_role() = 'ADMIN' ) with check ( app.current_role() = 'ADMIN' );
drop policy if exists p_v1_jobs_delete on public.jobs;
create policy p_v1_jobs_delete on public.jobs for delete to authenticated
  using ( app.current_role() = 'ADMIN' );

-- =========================================================
-- NGOÀI SCOPE v1 (deny-all cố ý): salary_grades, job_history, pgv_print_log — RLS bật, KHÔNG grant, KHÔNG policy.
-- Payroll/KPI/Reports/PDF/Export = compute-guard (Phase sau). APPROVE = function ADMIN-only (Phase sau).
-- =========================================================
