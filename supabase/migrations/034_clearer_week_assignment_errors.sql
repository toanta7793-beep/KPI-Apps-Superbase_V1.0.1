-- 034_clearer_week_assignment_errors.sql
-- assign_jobs_to_shared_week đang bắn cùng một mã 'JOB_MUST_FIT_SHARED_WEEK' cho HAI tình huống
-- khác hẳn nhau: (a) việc đã thuộc một tuần rồi, (b) ngày của việc nằm ngoài khoảng tuần.
-- Người dùng đọc thông báo không biết phải sửa gì. Tách thành hai mã riêng.
--
-- Toàn bộ phần còn lại của hàm giữ nguyên như 030: cùng thứ tự khóa (for update),
-- cùng kiểm tra quyền, cùng chống gán một phần. Không đổi công thức hay hành vi ghi.

create or replace function public.assign_jobs_to_shared_week(p_week_slot integer, p_job_ids uuid[])
returns integer language plpgsql security definer set search_path = '' as $$
declare v_shared public.shared_work_weeks; v_count int;
begin
  if coalesce(array_length(p_job_ids,1),0)=0 then raise exception 'EMPTY_JOB_SELECTION'; end if;
  if (select count(distinct x) from unnest(p_job_ids) x) <> array_length(p_job_ids,1) then
    raise exception 'DUPLICATE_JOB_IDS';
  end if;

  select * into v_shared from public.shared_work_weeks
   where week_slot=p_week_slot and status='ACTIVE' for update;
  if v_shared.id is null then raise exception 'SHARED_WEEK_NOT_FOUND'; end if;

  perform 1 from public.jobs where id=any(p_job_ids) and deleted_at is null for update;
  if (select count(*) from public.jobs where id=any(p_job_ids) and deleted_at is null)
     <> array_length(p_job_ids,1) then
    raise exception 'JOB_NOT_FOUND';
  end if;

  if app.current_role() not in ('ADMIN','GIAM_SAT','TO_TRUONG')
     or exists(select 1 from public.jobs where id=any(p_job_ids) and not app.can_access_team(team_id)) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  -- Hai nguyên nhân, hai mã lỗi.
  if exists(select 1 from public.jobs where id=any(p_job_ids) and week_id is not null) then
    raise exception 'JOB_ALREADY_IN_WEEK';
  end if;
  if exists(select 1 from public.jobs
             where id=any(p_job_ids)
               and (start_date < v_shared.start_date or end_date > v_shared.end_date)) then
    raise exception 'JOB_DATES_OUTSIDE_SHARED_WEEK';
  end if;

  update public.jobs j set week_id=w.id, updated_at=now(), updated_by=auth.uid()
    from public.work_weeks w
   where j.id=any(p_job_ids) and w.team_id=j.team_id and w.week_slot=p_week_slot and w.status='ACTIVE';
  get diagnostics v_count = row_count;
  if v_count <> array_length(p_job_ids,1) then raise exception 'PARTIAL_SHARED_WEEK_ASSIGNMENT'; end if;
  return v_count;
end $$;

revoke execute on function public.assign_jobs_to_shared_week(integer,uuid[]) from public, anon;
grant  execute on function public.assign_jobs_to_shared_week(integer,uuid[]) to authenticated;
notify pgrst, 'reload schema';
