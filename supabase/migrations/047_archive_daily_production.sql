-- 047_archive_daily_production.sql
--
-- Phần 2 bước 2: đưa sản lượng theo ngày vào luồng XÓA TUẦN.
--
-- Vì sao phải làm ngay cùng lúc với 046, không để lại sau:
-- quy tắc nghiệp vụ bắt buộc là xóa tuần phải **sao lưu → lưu trữ → kiểm chứng → xóa**,
-- hỏng bất kỳ bước nào là không được xóa. Bảng sản lượng vừa thêm ở 046 chưa nằm trong
-- luồng đó. Để nguyên thì lần xóa tuần đầu tiên sẽ bỏ lại các dòng sản lượng mồ côi, gắn
-- vào việc đã xóa mềm, không có trong file lưu trữ và không ai biết chúng còn ở đó.
-- Dự án này đã dính đúng loại lỗi ấy một lần: bản backup thiếu cột is_special_labor.
--
-- Ba thay đổi:
--   1. Bảng lịch sử cho sản lượng, song song với job_history.
--   2. prepare_week_archive trả thêm mảng 'production' để bản Excel có sheet thứ hai.
--   3. finalize_week_archive kiểm số dòng sản lượng, chuyển vào lịch sử, rồi mới xóa.
--
-- Điểm 3 là chỗ đáng nói: nếu tổ trưởng nhập thêm sản lượng TRONG LÚC Admin đang xóa tuần
-- thì số dòng lệch với lúc chụp, và thao tác bị TỪ CHỐI. Thà bắt Admin làm lại từ đầu còn
-- hơn xóa mất một dòng chưa có trong file lưu trữ.

alter table public.week_archive_operations
  add column if not exists production_row_count int not null default 0;

create table if not exists public.job_daily_production_history (
  id                   uuid primary key default gen_random_uuid(),
  archive_operation_id uuid not null,
  source_job_id        uuid not null,
  batch_label          text not null,
  archived_at          timestamptz not null default now(),
  team_id              uuid,
  team_name            text,
  content              text,
  location             text,
  unit                 text,
  work_date            date not null,
  quantity             numeric(18,4) not null,
  locked_at            timestamptz,
  locked_by            uuid,
  created_at           timestamptz,
  created_by           uuid
);
create index if not exists ix_production_history_op on public.job_daily_production_history(archive_operation_id);
create index if not exists ix_production_history_job on public.job_daily_production_history(source_job_id);
alter table public.job_daily_production_history enable row level security;
revoke all on public.job_daily_production_history from anon, authenticated;

-- ---------------------------------------------------------------------------------------
-- prepare: chụp thêm sản lượng. Giữ nguyên khóa 'snapshot' để phần đang chạy không vỡ;
-- sản lượng đi ở khóa mới 'production'.
-- ---------------------------------------------------------------------------------------
create or replace function public.prepare_week_archive(p_operation_id uuid, p_week_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_week public.work_weeks; v_snapshot jsonb; v_count int;
        v_production jsonb; v_prod_count int;
begin
  if app.current_role() <> 'ADMIN' then raise exception 'FORBIDDEN' using errcode='42501'; end if;

  -- Gọi lại cùng một operation_id phải trả về đúng thứ đã chụp lần đầu, không chụp lại.
  if exists (select 1 from public.week_archive_operations where id = p_operation_id) then
    select jsonb_build_object(
             'operation_id', o.id, 'week_id', o.week_id, 'team_id', o.team_id,
             'row_count', o.row_count, 'snapshot', o.snapshot, 'status', o.status,
             'production_row_count', o.production_row_count,
             'production', coalesce((
               select jsonb_agg(to_jsonb(x) order by x.content, x.work_date) from (
                 select d.job_id, d.work_date, d.quantity, d.is_locked, d.locked_at, d.locked_by,
                        d.created_at, d.created_by, j.content, j.location, m.unit, t.leader_name as team_name
                 from public.job_daily_production d
                 join public.jobs j on j.id = d.job_id and j.deleted_at is null
                 left join app.v_job_metrics m on m.id = j.id
                 left join public.teams t on t.id = j.team_id
                 where j.week_id = o.week_id) x), '[]'::jsonb))
      into v_snapshot
      from public.week_archive_operations o where o.id = p_operation_id;
    return v_snapshot;
  end if;

  select * into v_week from public.work_weeks where id = p_week_id and status = 'ACTIVE' for update;
  if v_week.id is null then raise exception 'WEEK_NOT_FOUND'; end if;

  select coalesce(jsonb_agg(to_jsonb(m) order by m.start_date, m.created_at), '[]'::jsonb), count(*)
    into v_snapshot, v_count
    from app.v_job_metrics m where m.week_id = p_week_id;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.content, x.work_date), '[]'::jsonb), count(*)
    into v_production, v_prod_count
    from (
      select d.job_id, d.work_date, d.quantity, d.is_locked, d.locked_at, d.locked_by,
             d.created_at, d.created_by, j.content, j.location, m.unit, t.leader_name as team_name
      from public.job_daily_production d
      join public.jobs j on j.id = d.job_id and j.deleted_at is null
      left join app.v_job_metrics m on m.id = j.id
      left join public.teams t on t.id = j.team_id
      where j.week_id = p_week_id
    ) x;

  insert into public.week_archive_operations(id, week_id, team_id, snapshot, row_count, production_row_count, created_by)
  values (p_operation_id, p_week_id, v_week.team_id, v_snapshot, v_count, v_prod_count, auth.uid());

  return jsonb_build_object('operation_id', p_operation_id, 'week_id', p_week_id, 'team_id', v_week.team_id,
                            'row_count', v_count, 'snapshot', v_snapshot, 'status', 'PENDING',
                            'production_row_count', v_prod_count, 'production', v_production);
end $$;

-- ---------------------------------------------------------------------------------------
-- finalize: thêm bước lưu trữ và xóa sản lượng. Các bước cũ giữ nguyên từng dòng.
-- ---------------------------------------------------------------------------------------
create or replace function public.finalize_week_archive(p_operation_id uuid, p_backup_path text, p_backup_sha256 text)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_op public.week_archive_operations; v_inserted int; v_deleted int;
        v_prod_now int; v_prod_inserted int; v_prod_deleted int;
begin
  if app.current_role() <> 'ADMIN' then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  select * into v_op from public.week_archive_operations where id = p_operation_id for update;
  if v_op.id is null then raise exception 'ARCHIVE_OPERATION_NOT_FOUND'; end if;
  if v_op.status = 'COMPLETED' then return v_op.row_count; end if;
  if coalesce(p_backup_path,'') = '' or coalesce(p_backup_sha256,'') !~ '^[0-9a-f]{64}$' then raise exception 'INVALID_BACKUP_PROOF'; end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'kpi-week-backups' and o.name = p_backup_path and coalesce((o.metadata->>'size')::bigint,0) > 0) then
    raise exception 'BACKUP_NOT_VERIFIED';
  end if;
  perform 1 from public.work_weeks where id = v_op.week_id and status = 'ACTIVE' for update;
  if not found then raise exception 'WEEK_NOT_ACTIVE'; end if;
  if (select count(*) from public.jobs where week_id = v_op.week_id and deleted_at is null) <> v_op.row_count then
    raise exception 'WEEK_CHANGED_AFTER_SNAPSHOT';
  end if;

  -- Sản lượng nhập thêm sau lúc chụp sẽ không có trong file lưu trữ. Dừng lại thay vì xóa nó.
  select count(*) into v_prod_now
  from public.job_daily_production d join public.jobs j on j.id = d.job_id
  where j.week_id = v_op.week_id and j.deleted_at is null;
  if v_prod_now <> v_op.production_row_count then raise exception 'PRODUCTION_CHANGED_AFTER_SNAPSHOT'; end if;

  insert into public.job_history(archive_operation_id,source_job_id,batch_label,archived_at,team_id,team_name,
    start_date,end_date,category_name,content,location,quantity,count_leader,count_worker1,count_worker2,count_worker3,count_helper,
    unit,unit_price,work_days,payroll,breakeven_qty,daily_qty,difference,evaluation,group_code)
  select p_operation_id,m.id,'Tuần '||w.week_slot,now(),m.team_id,t.leader_name,m.start_date,m.end_date,m.category_name,m.content,m.location,
    m.quantity,m.count_leader,m.count_worker1,m.count_worker2,m.count_worker3,m.count_helper,m.unit,m.unit_price,m.work_days,
    m.actual_labor_cost,m.total_breakeven,m.target_daily,m.difference,m.evaluation,m.group_code
  from app.v_job_metrics m join public.work_weeks w on w.id=m.week_id join public.teams t on t.id=m.team_id
  where m.week_id=v_op.week_id;
  get diagnostics v_inserted=row_count;
  if v_inserted <> v_op.row_count then raise exception 'ARCHIVE_COUNT_MISMATCH'; end if;

  insert into public.job_daily_production_history(archive_operation_id,source_job_id,batch_label,archived_at,
    team_id,team_name,content,location,unit,work_date,quantity,locked_at,locked_by,created_at,created_by)
  select p_operation_id, d.job_id, 'Tuần '||w.week_slot, now(),
         j.team_id, t.leader_name, j.content, j.location, m.unit,
         d.work_date, d.quantity, d.locked_at, d.locked_by, d.created_at, d.created_by
  from public.job_daily_production d
  join public.jobs j on j.id = d.job_id and j.deleted_at is null
  join public.work_weeks w on w.id = j.week_id
  left join app.v_job_metrics m on m.id = j.id
  left join public.teams t on t.id = j.team_id
  where j.week_id = v_op.week_id;
  get diagnostics v_prod_inserted = row_count;
  if v_prod_inserted <> v_op.production_row_count then raise exception 'PRODUCTION_ARCHIVE_COUNT_MISMATCH'; end if;

  -- Xóa hẳn, không xóa mềm: bản sao đã nằm trong lịch sử và trong file Excel. Giữ lại thì
  -- chúng gắn vào việc đã xóa và sẽ cộng nhầm vào lũy kế nếu việc được phục hồi.
  delete from public.job_daily_production d
   using public.jobs j
   where j.id = d.job_id and j.week_id = v_op.week_id and j.deleted_at is null;
  get diagnostics v_prod_deleted = row_count;
  if v_prod_deleted <> v_op.production_row_count then raise exception 'PRODUCTION_DELETE_COUNT_MISMATCH'; end if;

  update public.jobs set deleted_at=now(),week_id=null,updated_at=now(),updated_by=auth.uid()
  where week_id=v_op.week_id and deleted_at is null;
  get diagnostics v_deleted=row_count;
  if v_deleted <> v_op.row_count then raise exception 'DELETE_COUNT_MISMATCH'; end if;
  update public.work_weeks set status='ARCHIVED',updated_at=now() where id=v_op.week_id;
  update public.week_archive_operations set status='COMPLETED',backup_path=p_backup_path,
    backup_sha256=p_backup_sha256,completed_at=now() where id=p_operation_id;
  return v_deleted;
end $$;

revoke execute on function public.prepare_week_archive(uuid,uuid) from public, anon;
revoke execute on function public.finalize_week_archive(uuid,text,text) from public, anon;
grant  execute on function public.prepare_week_archive(uuid,uuid) to authenticated;
grant  execute on function public.finalize_week_archive(uuid,text,text) to authenticated;
notify pgrst, 'reload schema';
