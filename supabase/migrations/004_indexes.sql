-- =====================================================================
-- 004_indexes.sql  ·  KPI MEP → Supabase (Phase 2 DESIGN ONLY)
-- Index cho FK, tra cứu, và lọc soft-delete. Idempotent: CREATE INDEX IF NOT EXISTS.
-- (UNIQUE đã tạo index ngầm ở 003; ở đây là index bổ trợ.)
-- =====================================================================

-- FK indexes (tăng tốc join & cascade)
create index if not exists ix_salary_system     on public.salary_standards (system_id);
create index if not exists ix_salary_grade       on public.salary_standards (grade_id);
create index if not exists ix_price_category     on public.price_items (category_id);
create index if not exists ix_team_system        on public.teams (system_id);
create index if not exists ix_worker_team        on public.workers (team_id);
create index if not exists ix_job_team           on public.jobs (team_id);
create index if not exists ix_assign_team        on public.assignments (team_id);
create index if not exists ix_assign_worker      on public.assignments (worker_id);
create index if not exists ix_assign_job         on public.assignments (job_id);
create index if not exists ix_hist_team          on public.job_history (team_id);
create index if not exists ix_pgvlog_team        on public.pgv_print_log (team_id);

-- Tra cứu đơn giá theo khóa (như MATCH DON_GIA!H) và nhóm
create index if not exists ix_price_lookup_key   on public.price_items (lookup_key);
create index if not exists ix_price_category_name on public.price_items (category_name);
create index if not exists ix_price_work_code    on public.price_items (work_code);

-- Giao việc: lọc theo tổ còn hiệu lực, mã nhóm, hạng mục, khoảng ngày
create index if not exists ix_job_team_active    on public.jobs (team_id) where deleted_at is null;
create index if not exists ix_job_group_code     on public.jobs (group_code) where group_code is not null;
create index if not exists ix_job_category       on public.jobs (category_name);
create index if not exists ix_job_dates          on public.jobs (start_date, end_date);

-- Công nhân còn hiệu lực theo tổ; mapping theo tên tổ trưởng
create index if not exists ix_worker_team_active on public.workers (team_id) where deleted_at is null;
create index if not exists ix_team_leader_name   on public.teams (leader_name);
create index if not exists ix_team_active        on public.teams (is_active) where deleted_at is null;

-- Lịch sử: truy vấn theo đợt & thời điểm
create index if not exists ix_hist_batch         on public.job_history (batch_label);
create index if not exists ix_pgvlog_printed_at  on public.pgv_print_log (printed_at);
