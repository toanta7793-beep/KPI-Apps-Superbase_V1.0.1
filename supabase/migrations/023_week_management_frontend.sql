-- Phase 10: Week management + browser-safe Supabase contract.
create extension if not exists btree_gist;

create table if not exists public.work_weeks (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete restrict,
  week_slot smallint not null check (week_slot between 1 and 4),
  start_date date not null,
  end_date date not null,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','ARCHIVED')),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ck_work_week_dates check (end_date >= start_date and end_date - start_date + 1 <= 9)
);

create unique index if not exists uq_work_week_team_slot_active
  on public.work_weeks(team_id, week_slot) where status = 'ACTIVE';

do $$ begin
  alter table public.work_weeks add constraint ex_work_week_no_overlap
    exclude using gist (team_id with =, daterange(start_date,end_date,'[]') with &&)
    where (status = 'ACTIVE');
exception when duplicate_object then null; end $$;

alter table public.jobs add column if not exists week_id uuid references public.work_weeks(id) on delete restrict;
create index if not exists ix_jobs_week_active on public.jobs(week_id) where deleted_at is null;

alter table public.work_weeks enable row level security;
grant select, insert, update, delete on public.work_weeks to authenticated;

drop policy if exists p_week_select on public.work_weeks;
create policy p_week_select on public.work_weeks for select to authenticated using (
  app.current_role() = 'ADMIN' or team_id = app.current_team_id()
);
drop policy if exists p_week_insert on public.work_weeks;
create policy p_week_insert on public.work_weeks for insert to authenticated with check (
  app.current_role() = 'ADMIN' or (app.current_role() = 'TO_TRUONG' and team_id = app.current_team_id())
);
drop policy if exists p_week_update on public.work_weeks;
create policy p_week_update on public.work_weeks for update to authenticated
  using (app.current_role() = 'ADMIN' or (app.current_role() = 'TO_TRUONG' and team_id = app.current_team_id()))
  with check (app.current_role() = 'ADMIN' or (app.current_role() = 'TO_TRUONG' and team_id = app.current_team_id()));
drop policy if exists p_week_delete on public.work_weeks;
create policy p_week_delete on public.work_weeks for delete to authenticated using (app.current_role() = 'ADMIN');

create or replace function public.get_my_identity()
returns table(role_code text, worker_id uuid, mnv text, full_name text, team_id uuid, team_name text)
language sql stable security definer set search_path = '' as $$
  select p.role_code, w.id, w.mnv, w.full_name, w.team_id, t.leader_name
  from public.profiles p
  left join public.workers w on w.id=p.worker_id and w.deleted_at is null
  left join public.teams t on t.id=w.team_id and t.deleted_at is null
  where p.auth_user_id=auth.uid() and p.is_active
$$;
revoke execute on function public.get_my_identity() from public, anon;
grant execute on function public.get_my_identity() to authenticated;

create or replace function public.assign_jobs_to_week(p_week_id uuid, p_job_ids uuid[])
returns integer language plpgsql security definer set search_path = '' as $$
declare w public.work_weeks; affected integer;
begin
  if coalesce(array_length(p_job_ids,1),0)=0 then raise exception 'EMPTY_JOB_SELECTION'; end if;
  select * into w from public.work_weeks where id=p_week_id and status='ACTIVE' for update;
  if w.id is null then raise exception 'WEEK_NOT_FOUND'; end if;
  if not (app.current_role()='ADMIN' or (app.current_role()='TO_TRUONG' and w.team_id=app.current_team_id())) then raise exception 'FORBIDDEN'; end if;
  if exists(select 1 from public.jobs j where j.id=any(p_job_ids) and (j.deleted_at is not null or j.team_id<>w.team_id or j.start_date<w.start_date or j.end_date>w.end_date or j.week_id is not null)) then
    raise exception 'JOB_WEEK_VALIDATION_FAILED';
  end if;
  update public.jobs set week_id=w.id, updated_at=now(), updated_by=auth.uid() where id=any(p_job_ids);
  get diagnostics affected = row_count;
  if affected<>array_length(p_job_ids,1) then raise exception 'PARTIAL_ASSIGNMENT'; end if;
  return affected;
end $$;
revoke execute on function public.assign_jobs_to_week(uuid,uuid[]) from public, anon;
grant execute on function public.assign_jobs_to_week(uuid,uuid[]) to authenticated;

notify pgrst, 'reload schema';
