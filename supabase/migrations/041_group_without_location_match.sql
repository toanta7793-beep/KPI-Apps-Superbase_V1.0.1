-- 041_group_without_location_match.sql
--
-- Theo yêu cầu vận hành ngày 11/08/2026, phương án (a).
--
-- Trước đây create_job_group từ chối gộp khi hai việc khác vị trí (GROUP_LOCATION_MISMATCH).
-- Thực tế một tổ trong cùng một ngày có thể làm ở hai vị trí khác nhau mà vẫn là một
-- cơ cấu nhân sự, nên yêu cầu trùng vị trí là sai với cách làm ngoài công trường.
--
-- Bỏ hẳn phép so vị trí. Các điều kiện còn lại GIỮ NGUYÊN, vì chúng mới là thứ bảo đảm
-- mã nhóm có nghĩa khi tính quân số:
--   * cùng Tổ                                  -> GROUP_TEAM_MISMATCH
--   * cùng ngày bắt đầu và ngày kết thúc       -> GROUP_DATE_MISMATCH
--   * cùng cơ cấu nhân sự                      -> GROUP_STAFFING_MISMATCH
--   * đủ số liệu để tính                       -> GROUP_METRICS_INCOMPLETE
--   * chưa thuộc nhóm nào khác                 -> REMOVE_EXISTING_GROUP_FIRST
--
-- Vẫn giữ GROUP_LOCATION_REQUIRED: mỗi việc phải có vị trí, chỉ là không bắt trùng nhau.
-- Bỏ luôn thì phiếu in ra sẽ có dòng trống ở cột vị trí.
--
-- Lưu ý cho sau này: hiện "Phân khu" và "Vị trí chi tiết" trên phiếu in đều lấy từ CÙNG
-- một trường jobs.location. Nếu về sau tách thành các trường riêng thì có thể cân nhắc
-- bắt trùng ở mức Phân khu mà vẫn cho khác Vị trí chi tiết.

create or replace function public.create_job_group(p_job_ids uuid[])
returns text language plpgsql security definer set search_path='' as $$
declare v_first public.jobs;v_code text;v_date text;v_seq int;v_count int;
begin
  if coalesce(array_length(p_job_ids,1),0)<2 then raise exception 'AT_LEAST_TWO_JOBS'; end if;
  if (select count(distinct x) from unnest(p_job_ids)x)<>array_length(p_job_ids,1) then raise exception 'DUPLICATE_JOB_IDS'; end if;
  perform 1 from public.jobs where id=any(p_job_ids) and deleted_at is null for update;
  select count(*) into v_count from public.jobs where id=any(p_job_ids) and deleted_at is null;
  if v_count<>array_length(p_job_ids,1) then raise exception 'JOB_NOT_FOUND'; end if;
  select * into v_first from public.jobs where id=p_job_ids[1] and deleted_at is null;
  if app.current_role() not in ('ADMIN','GIAM_SAT','TO_TRUONG') or not app.can_access_team(v_first.team_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;

  -- Mỗi việc vẫn phải có vị trí, nhưng KHÔNG bắt các việc trùng vị trí nhau.
  if exists(select 1 from public.jobs j where j.id=any(p_job_ids) and btrim(coalesce(j.location,''))='') then
    raise exception 'GROUP_LOCATION_REQUIRED';
  end if;

  if exists(select 1 from public.jobs j where j.id=any(p_job_ids) and j.group_code is not null) then raise exception 'REMOVE_EXISTING_GROUP_FIRST'; end if;
  if exists(select 1 from public.jobs j where j.id=any(p_job_ids) and j.team_id<>v_first.team_id) then raise exception 'GROUP_TEAM_MISMATCH'; end if;
  if exists(select 1 from public.jobs j where j.id=any(p_job_ids) and (j.start_date<>v_first.start_date or j.end_date<>v_first.end_date)) then raise exception 'GROUP_DATE_MISMATCH'; end if;
  if exists(select 1 from public.jobs j where j.id=any(p_job_ids)
            and (j.count_leader,j.count_worker1,j.count_worker2,j.count_worker3,j.count_helper)
                is distinct from (v_first.count_leader,v_first.count_worker1,v_first.count_worker2,v_first.count_worker3,v_first.count_helper)) then
    raise exception 'GROUP_STAFFING_MISMATCH';
  end if;
  if exists(select 1 from app.v_job_metrics m where m.id=any(p_job_ids)
            and (coalesce(m.unit_price,0)<=0 or coalesce(m.work_days,0)<=0 or coalesce(m.production_value,0)<=0
                 or coalesce(m.actual_labor_cost,0)<=0)) then
    raise exception 'GROUP_METRICS_INCOMPLETE';
  end if;

  v_date:=to_char(v_first.start_date,'YYYYMMDD');
  perform pg_advisory_xact_lock(hashtext('JOB_GROUP_'||v_date));
  select coalesce(max(substring(group_code from '([0-9]+)$')::int),0)+1 into v_seq
  from public.jobs where group_code like 'MN-'||v_date||'-%';
  v_code:='MN-'||v_date||'-'||lpad(v_seq::text,2,'0');
  update public.jobs set group_code=v_code,updated_at=now(),updated_by=auth.uid()
   where id=any(p_job_ids) and deleted_at is null;
  return v_code;
end $$;

revoke execute on function public.create_job_group(uuid[]) from public, anon;
grant  execute on function public.create_job_group(uuid[]) to authenticated;
notify pgrst, 'reload schema';
