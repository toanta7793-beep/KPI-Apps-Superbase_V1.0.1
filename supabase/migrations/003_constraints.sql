-- =====================================================================
-- 003_constraints.sql  ·  KPI MEP → Supabase (Phase 2 DESIGN ONLY)
-- FK, UNIQUE, CHECK. Idempotent: DROP CONSTRAINT IF EXISTS + ADD.
-- =====================================================================

-- ------------------------------------------------------------------
-- UNIQUE (khóa nghiệp vụ)
-- ------------------------------------------------------------------
alter table public.systems          drop constraint if exists uq_systems_code;
alter table public.systems          add  constraint uq_systems_code unique (code);
alter table public.systems          drop constraint if exists uq_systems_name;
alter table public.systems          add  constraint uq_systems_name unique (name);

alter table public.salary_grades    drop constraint if exists uq_grade_name;
alter table public.salary_grades    add  constraint uq_grade_name unique (name);

alter table public.salary_standards drop constraint if exists uq_salary_system_grade;
alter table public.salary_standards add  constraint uq_salary_system_grade unique (system_id, grade_id); -- Hệ‡Chức danh

alter table public.work_categories  drop constraint if exists uq_category_name;
alter table public.work_categories  add  constraint uq_category_name unique (name);

alter table public.price_items       drop constraint if exists uq_price_cat_content;
alter table public.price_items       add  constraint uq_price_cat_content unique (category_name, content); -- DD-15 (flag trùng khi migrate)

alter table public.teams             drop constraint if exists uq_team_code;
alter table public.teams             add  constraint uq_team_code unique (team_code); -- DD-02

alter table public.workers           drop constraint if exists uq_worker_mnv;
alter table public.workers           add  constraint uq_worker_mnv unique (mnv);

alter table public.assignments       drop constraint if exists uq_assignment_team_worker;
alter table public.assignments       add  constraint uq_assignment_team_worker unique (team_id, worker_id);

-- ------------------------------------------------------------------
-- FOREIGN KEY
-- ------------------------------------------------------------------
alter table public.salary_standards drop constraint if exists fk_salary_system;
alter table public.salary_standards add  constraint fk_salary_system
  foreign key (system_id) references public.systems(id) on delete restrict;
alter table public.salary_standards drop constraint if exists fk_salary_grade;
alter table public.salary_standards add  constraint fk_salary_grade
  foreign key (grade_id) references public.salary_grades(id) on delete restrict;

alter table public.price_items      drop constraint if exists fk_price_category;
alter table public.price_items      add  constraint fk_price_category
  foreign key (category_id) references public.work_categories(id) on delete set null;

alter table public.teams            drop constraint if exists fk_team_system;
alter table public.teams            add  constraint fk_team_system
  foreign key (system_id) references public.systems(id) on delete set null;

alter table public.workers          drop constraint if exists fk_worker_team;
alter table public.workers          add  constraint fk_worker_team
  foreign key (team_id) references public.teams(id) on delete set null;

alter table public.jobs             drop constraint if exists fk_job_team;
alter table public.jobs             add  constraint fk_job_team
  foreign key (team_id) references public.teams(id) on delete restrict;

alter table public.assignments      drop constraint if exists fk_assignment_team;
alter table public.assignments      add  constraint fk_assignment_team
  foreign key (team_id) references public.teams(id) on delete cascade;
alter table public.assignments      drop constraint if exists fk_assignment_worker;
alter table public.assignments      add  constraint fk_assignment_worker
  foreign key (worker_id) references public.workers(id) on delete cascade;
alter table public.assignments      drop constraint if exists fk_assignment_job;
alter table public.assignments      add  constraint fk_assignment_job
  foreign key (job_id) references public.jobs(id) on delete set null;

alter table public.job_history      drop constraint if exists fk_hist_team;
alter table public.job_history      add  constraint fk_hist_team
  foreign key (team_id) references public.teams(id) on delete set null;

alter table public.pgv_print_log    drop constraint if exists fk_pgvlog_team;
alter table public.pgv_print_log    add  constraint fk_pgvlog_team
  foreign key (team_id) references public.teams(id) on delete set null;

-- ------------------------------------------------------------------
-- CHECK
-- ------------------------------------------------------------------
alter table public.roles            drop constraint if exists ck_role_level_pos;
alter table public.roles            add  constraint ck_role_level_pos check (level > 0);

alter table public.salary_standards drop constraint if exists ck_salary_month_pos;
alter table public.salary_standards add  constraint ck_salary_month_pos check (monthly_salary > 0);

alter table public.price_items      drop constraint if exists ck_price_nonneg;
alter table public.price_items      add  constraint ck_price_nonneg
  check ((approved_price is null or approved_price >= 0) and (calc_price is null or calc_price >= 0));

alter table public.teams            drop constraint if exists ck_team_code_notblank;
alter table public.teams            add  constraint ck_team_code_notblank check (btrim(team_code) <> '');
alter table public.teams            drop constraint if exists ck_team_leader_notblank;
alter table public.teams            add  constraint ck_team_leader_notblank check (btrim(leader_name) <> '');

alter table public.workers          drop constraint if exists ck_worker_mnv_notblank;
alter table public.workers          add  constraint ck_worker_mnv_notblank check (btrim(mnv) <> '');

-- jobs: ngày, số lượng, khối lượng, tổng người (khớp DataAPI.saveGiaoViec, BR-7)
alter table public.jobs             drop constraint if exists ck_job_dates;
alter table public.jobs             add  constraint ck_job_dates check (end_date >= start_date);
alter table public.jobs             drop constraint if exists ck_job_quantity_pos;
alter table public.jobs             add  constraint ck_job_quantity_pos check (quantity > 0);
alter table public.jobs             drop constraint if exists ck_job_counts_range;
alter table public.jobs             add  constraint ck_job_counts_range check (
  count_leader  between 0 and 999 and
  count_worker1 between 0 and 999 and
  count_worker2 between 0 and 999 and
  count_worker3 between 0 and 999 and
  count_helper  between 0 and 999
);
alter table public.jobs             drop constraint if exists ck_job_total_workers_pos;
alter table public.jobs             add  constraint ck_job_total_workers_pos check (
  (count_leader + count_worker1 + count_worker2 + count_worker3 + count_helper) > 0
);
alter table public.jobs             drop constraint if exists ck_job_content_len;
alter table public.jobs             add  constraint ck_job_content_len check (char_length(content) <= 200); -- BR-7

-- assignments: giới hạn 100 ký tự (AssignmentService)
alter table public.assignments      drop constraint if exists ck_assign_target_len;
alter table public.assignments      add  constraint ck_assign_target_len
  check ((target is null or char_length(target) <= 100)
     and (completed_qty is null or char_length(completed_qty) <= 100));

-- group_code định dạng MN-YYYYMMDD-NN (nếu có)
alter table public.jobs             drop constraint if exists ck_job_group_format;
alter table public.jobs             add  constraint ck_job_group_format
  check (group_code is null or group_code ~ '^MN-[0-9]{8}-[0-9]{2,}$');
