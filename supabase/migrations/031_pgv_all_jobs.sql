-- 031_pgv_all_jobs.sql
-- PGV Chung must list every job item, including every row sharing a group code.

create or replace function public.get_pgv_common(p_team_id uuid,p_week_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_week public.work_weeks;v_team text;v_project text;v_workers int;v_rows jsonb;
begin
  if not app.can_access_team(p_team_id) then raise exception 'FORBIDDEN'; end if;
  select * into v_week from public.work_weeks where id=p_week_id and team_id=p_team_id and status='ACTIVE';
  if v_week.id is null then raise exception 'WEEK_NOT_FOUND'; end if;
  select leader_name,project_name into v_team,v_project from public.teams where id=p_team_id;
  select count(*) into v_workers from public.workers where team_id=p_team_id and deleted_at is null;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.start_date,x.created_at,x.id),'[]'::jsonb) into v_rows
  from (select m.* from app.v_job_metrics m where m.team_id=p_team_id and m.week_id=p_week_id) x;
  return jsonb_build_object('team_id',p_team_id,'team_name',v_team,'project_name',v_project,
    'week',to_jsonb(v_week),'assign_date',v_week.start_date-1,'receive_date',v_week.start_date,
    'worker_count',v_workers,'rows',v_rows);
end $$;

revoke execute on function public.get_pgv_common(uuid,uuid) from public,anon;
grant execute on function public.get_pgv_common(uuid,uuid) to authenticated;
notify pgrst,'reload schema';
