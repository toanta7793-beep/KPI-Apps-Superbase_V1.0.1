-- 056_pgv_cnch_group_code.sql
--
-- Yêu cầu 14/08/2026: phiếu PGV CNCH cần thêm một đầu mục GỘP cho mỗi mã nhóm, để phân công
-- được người làm nhiều hạng mục cùng lúc.
--
-- get_pgv_cnch đang trả về danh sách việc theo một danh sách cột cố định KHÔNG có group_code,
-- nên giao diện không có cách nào biết việc nào thuộc nhóm nào. Thêm đúng một cột.
--
-- Chỉ thêm cột vào JSON trả về. Không đổi tham số, không đổi logic, không đụng phần còn lại
-- của hàm. Giao diện cũ bỏ qua cột lạ nên không có gì vỡ nếu chưa kịp cập nhật.

create or replace function public.get_pgv_cnch(p_team_id uuid,p_receive_date date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_week public.work_weeks;v_project text;v_workers jsonb;v_jobs jsonb;v_assign jsonb;
begin
  if not app.can_access_team(p_team_id) then raise exception 'FORBIDDEN'; end if;
  select * into v_week from public.work_weeks where team_id=p_team_id and status='ACTIVE' and p_receive_date between start_date and end_date;
  if v_week.id is null then raise exception 'DATE_OUTSIDE_ACTIVE_WEEK'; end if;
  select project_name into v_project from public.teams where id=p_team_id;
  select coalesce(jsonb_agg(to_jsonb(w) order by w.stt_in_team,w.mnv),'[]'::jsonb) into v_workers from(select id,mnv,full_name,job_title,stt_in_team from public.workers where team_id=p_team_id and deleted_at is null)w;
  select coalesce(jsonb_agg(to_jsonb(j) order by j.start_date,j.created_at),'[]'::jsonb) into v_jobs from(select id,content,location,quantity,start_date,end_date,target_daily,unit,group_code,count_leader,count_worker1,count_worker2,count_worker3,count_helper,created_at from app.v_job_metrics where team_id=p_team_id and week_id=v_week.id)j;
  select coalesce(jsonb_agg(to_jsonb(a)),'[]'::jsonb) into v_assign from(select worker_id,job_id,content_label,target,completed_qty from public.assignments where week_id=v_week.id)a;
  return jsonb_build_object('project_name',v_project,'week',to_jsonb(v_week),'receive_date',p_receive_date,'assign_date',p_receive_date-1,'workers',v_workers,'jobs',v_jobs,'assignments',v_assign);
end $$;

revoke execute on function public.get_pgv_cnch(uuid,date) from public, anon;
grant  execute on function public.get_pgv_cnch(uuid,date) to authenticated;
notify pgrst, 'reload schema';
