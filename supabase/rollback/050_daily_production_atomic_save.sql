-- HOÀN TÁC 050_daily_production_atomic_save.sql
--
-- Đưa save_daily_production về bản của 046 (SELECT rồi mới INSERT/UPDATE).
--
-- ⚠️ CẢNH BÁO: bản cũ có khe hở tranh chấp — hai người cùng ghi một việc trong một ngày thì
-- người thứ hai nhận lỗi Postgres thô "duplicate key value violates unique constraint" thay
-- vì PRODUCTION_LOCKED. Không mất dữ liệu, nhưng thông báo sai bản chất.
-- Chỉ chạy khi đang lùi cả phiên bản.
--
-- Không đụng tới dữ liệu: đây chỉ là định nghĩa hàm.

create or replace function public.save_daily_production(
  p_job_id uuid, p_work_date date, p_quantity numeric
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_job public.jobs; v_id uuid; v_locked boolean;
begin
  if app.current_role() not in ('ADMIN','GIAM_SAT','TO_TRUONG') then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  select * into v_job from public.jobs where id = p_job_id and deleted_at is null;
  if v_job.id is null then raise exception 'JOB_NOT_FOUND'; end if;
  if not app.can_access_team(v_job.team_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;

  -- Đào tạo / Phát sinh có khối lượng tự sinh = số người × số ngày. Ghi tay vào đó là
  -- ghi đè lên một con số hệ thống tự tính, nên chặn hẳn thay vì để người dùng tự đoán.
  if v_job.is_special_labor then raise exception 'SPECIAL_LABOR_AUTO_ACCUMULATED'; end if;

  -- Ngày ghi phải nằm trong khoảng ngày của việc. Không có ràng buộc này thì một ngày gõ
  -- nhầm sẽ lặng lẽ cộng vào lũy kế và không ai truy ra được.
  if p_work_date < v_job.start_date or p_work_date > v_job.end_date then
    raise exception 'PRODUCTION_DATE_OUTSIDE_JOB';
  end if;
  if p_quantity is null or p_quantity < 0 then raise exception 'PRODUCTION_QTY_INVALID'; end if;

  select id, is_locked into v_id, v_locked
  from public.job_daily_production where job_id = p_job_id and work_date = p_work_date;

  if v_id is not null and v_locked then raise exception 'PRODUCTION_LOCKED'; end if;

  if v_id is null then
    insert into public.job_daily_production(job_id, work_date, quantity, is_locked, locked_at, locked_by)
    values (p_job_id, p_work_date, p_quantity, true, now(), auth.uid())
    returning id into v_id;
  else
    update public.job_daily_production
       set quantity = p_quantity, is_locked = true, locked_at = now(), locked_by = auth.uid(),
           updated_at = now(), updated_by = auth.uid()
     where id = v_id;
  end if;
  return v_id;
end $$;

revoke execute on function public.save_daily_production(uuid,date,numeric) from public, anon;
grant  execute on function public.save_daily_production(uuid,date,numeric) to authenticated;
notify pgrst, 'reload schema';
