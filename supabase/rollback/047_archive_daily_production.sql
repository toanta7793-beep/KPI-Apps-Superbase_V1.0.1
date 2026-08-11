-- HOÀN TÁC 047_archive_daily_production.sql
--
-- Dựng lại prepare_week_archive và finalize_week_archive đúng như bản trước 047 (bản gốc ở
-- migration 024), rồi bỏ bảng lịch sử sản lượng và cột đếm.
--
-- ⚠️ CẢNH BÁO: sau khi chạy script này, luồng xóa tuần KHÔNG còn sao lưu và KHÔNG còn xóa
-- sản lượng theo ngày. Nếu bảng job_daily_production vẫn còn (tức chưa hoàn tác 046) thì
-- lần xóa tuần tiếp theo sẽ để lại các dòng sản lượng mồ côi, gắn vào việc đã xóa mềm, và
-- không có trong file lưu trữ. Chỉ chạy script này NGAY TRƯỚC khi hoàn tác 046.
--
-- Dữ liệu đã lưu trong job_daily_production_history sẽ MẤT khi bỏ bảng. Tạo điểm khôi phục
-- trước nếu đã từng xóa tuần nào sau khi 047 có hiệu lực.

create or replace function public.prepare_week_archive(p_operation_id uuid,p_week_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_week public.work_weeks;v_snapshot jsonb;v_count int;
begin
  if app.current_role()<>'ADMIN' then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if exists(select 1 from public.week_archive_operations where id=p_operation_id) then
    return (select jsonb_build_object('operation_id',id,'week_id',week_id,'team_id',team_id,'row_count',row_count,'snapshot',snapshot,'status',status)
            from public.week_archive_operations where id=p_operation_id);
  end if;
  select * into v_week from public.work_weeks where id=p_week_id and status='ACTIVE' for update;
  if v_week.id is null then raise exception 'WEEK_NOT_FOUND'; end if;
  select coalesce(jsonb_agg(to_jsonb(m) order by m.start_date,m.created_at),'[]'::jsonb),count(*) into v_snapshot,v_count
  from app.v_job_metrics m where m.week_id=p_week_id;
  insert into public.week_archive_operations(id,week_id,team_id,snapshot,row_count,created_by)
  values(p_operation_id,p_week_id,v_week.team_id,v_snapshot,v_count,auth.uid());
  return jsonb_build_object('operation_id',p_operation_id,'week_id',p_week_id,'team_id',v_week.team_id,'row_count',v_count,'snapshot',v_snapshot,'status','PENDING');
end $$;

create or replace function public.finalize_week_archive(p_operation_id uuid,p_backup_path text,p_backup_sha256 text)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_op public.week_archive_operations;v_inserted int;v_deleted int;
begin
  if app.current_role()<>'ADMIN' then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  select * into v_op from public.week_archive_operations where id=p_operation_id for update;
  if v_op.id is null then raise exception 'ARCHIVE_OPERATION_NOT_FOUND'; end if;
  if v_op.status='COMPLETED' then return v_op.row_count; end if;
  if coalesce(p_backup_path,'')='' or coalesce(p_backup_sha256,'')!~'^[0-9a-f]{64}$' then raise exception 'INVALID_BACKUP_PROOF'; end if;
  if not exists(select 1 from storage.objects o where o.bucket_id='kpi-week-backups' and o.name=p_backup_path and coalesce((o.metadata->>'size')::bigint,0)>0) then
    raise exception 'BACKUP_NOT_VERIFIED';
  end if;
  perform 1 from public.work_weeks where id=v_op.week_id and status='ACTIVE' for update;
  if not found then raise exception 'WEEK_NOT_ACTIVE'; end if;
  if (select count(*) from public.jobs where week_id=v_op.week_id and deleted_at is null)<>v_op.row_count then raise exception 'WEEK_CHANGED_AFTER_SNAPSHOT'; end if;

  insert into public.job_history(archive_operation_id,source_job_id,batch_label,archived_at,team_id,team_name,
    start_date,end_date,category_name,content,location,quantity,count_leader,count_worker1,count_worker2,count_worker3,count_helper,
    unit,unit_price,work_days,payroll,breakeven_qty,daily_qty,difference,evaluation,group_code)
  select p_operation_id,m.id,'Tuần '||w.week_slot,now(),m.team_id,t.leader_name,m.start_date,m.end_date,m.category_name,m.content,m.location,
    m.quantity,m.count_leader,m.count_worker1,m.count_worker2,m.count_worker3,m.count_helper,m.unit,m.unit_price,m.work_days,
    m.actual_labor_cost,m.total_breakeven,m.target_daily,m.difference,m.evaluation,m.group_code
  from app.v_job_metrics m join public.work_weeks w on w.id=m.week_id join public.teams t on t.id=m.team_id
  where m.week_id=v_op.week_id;
  get diagnostics v_inserted=row_count;
  if v_inserted<>v_op.row_count then raise exception 'ARCHIVE_COUNT_MISMATCH'; end if;

  update public.jobs set deleted_at=now(),week_id=null,updated_at=now(),updated_by=auth.uid()
  where week_id=v_op.week_id and deleted_at is null;
  get diagnostics v_deleted=row_count;
  if v_deleted<>v_op.row_count then raise exception 'DELETE_COUNT_MISMATCH'; end if;
  update public.work_weeks set status='ARCHIVED',updated_at=now() where id=v_op.week_id;
  update public.week_archive_operations set status='COMPLETED',backup_path=p_backup_path,
    backup_sha256=p_backup_sha256,completed_at=now() where id=p_operation_id;
  return v_deleted;
end $$;

drop table if exists public.job_daily_production_history;
alter table public.week_archive_operations drop column if exists production_row_count;

notify pgrst, 'reload schema';
