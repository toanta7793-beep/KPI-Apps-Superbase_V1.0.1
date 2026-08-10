-- 039_payroll_scope_pushdown.sql
--
-- HIỆU NĂNG (tiếp theo 038) — đo ngày 11/08/2026 với 89 tổ, 1.089 công nhân.
--
-- Phát hiện: phân quyền KHÔNG làm giảm khối lượng tính của get_payroll_summary.
--     ADMIN     quản 87 tổ, trả 445 dòng -> 954–1.134 ms
--     GIAM_SAT  quản  3 tổ, trả  15 dòng ->  714–909 ms
--     TO_TRUONG quản  1 tổ, trả   5 dòng ->  777–836 ms
-- Trong khi truyền thẳng p_team_id cho đúng một tổ chỉ mất 20–36 ms.
--
-- Lý do: hai CTE `agg` và `unknowns` quét app.v_worker_salary cho TOÀN BỘ công nhân
-- rồi mới join với `allowed`. Điều kiện quyền nằm trong hàm app.can_access_team() nên
-- planner không đẩy được xuống dưới; còn p_team_id là hằng số nên đẩy được, và đó là
-- toàn bộ khác biệt giữa 800 ms và 25 ms.
--
-- Cách sửa: lấy danh sách tổ được phép ra một BIẾN trước, rồi lọc view bằng biến đó.
-- Với planner thì mảng đã có giá trị là hằng số, nên nó đẩy được điều kiện vào phần quét.
--
-- Kết quả trả về không đổi: `allowed` vẫn quyết định tập tổ hiển thị như cũ, chỉ khác là
-- các CTE tổng hợp thôi không còn tính cho những tổ chắc chắn sẽ bị loại ở bước join.
-- Công thức lương, quy tắc loại tổ trưởng và phép chia 26 giữ nguyên.

create or replace function public.get_payroll_summary(p_team_id uuid default null)
returns table(team_id uuid,team_name text,role_name text,worker_count int,
              average_monthly numeric,average_daily numeric,total_daily numeric,total_monthly numeric,
              status text,unknown_workers jsonb)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_allowed uuid[];
begin
  -- Chốt phạm vi TRƯỚC, để phần quét công nhân bên dưới có điều kiện lọc là hằng số.
  select coalesce(array_agg(t.id), '{}'::uuid[]) into v_allowed
  from public.teams t
  where t.deleted_at is null and t.is_active
    and (p_team_id is null or t.id = p_team_id)
    and app.can_access_team(t.id);

  if array_length(v_allowed, 1) is null then
    return;
  end if;

  return query
  with roles(role_name,sort_order) as (
    values ('Tổ trưởng',0),('Thợ bậc 1',1),('Thợ bậc 2',2),('Thợ bậc 3',3),('Thợ phụ',4)
  ), allowed as (
    select t.id, t.leader_name from public.teams t where t.id = any(v_allowed)
  ), agg as (
    select ws.team_id,ws.grade_name,count(*) filter(where ws.salary_ok)::int cnt,
      avg(ws.monthly_salary) filter(where ws.salary_ok) avg_m,
      avg(ws.daily_salary) filter(where ws.salary_ok) avg_d,
      sum(ws.daily_salary) filter(where ws.salary_ok) total_d,
      sum(ws.monthly_salary) filter(where ws.salary_ok) total_m
    from app.v_worker_salary ws
    where ws.team_id = any(v_allowed) and not ws.is_actual_leader
    group by ws.team_id,ws.grade_name
  ), unknowns as (
    select ws.team_id,
           jsonb_agg(jsonb_build_object('mnv',ws.mnv,'full_name',ws.full_name,'job_title',ws.job_title)
                     order by ws.mnv) data
    from app.v_worker_salary ws
    where ws.team_id = any(v_allowed) and not ws.salary_ok and not ws.is_actual_leader
    group by ws.team_id
  )
  select a.id,a.leader_name,r.role_name,
    case when r.role_name='Tổ trưởng' then 1 else coalesce(g.cnt,0) end,
    case when r.role_name='Tổ trưởng' then 0 else coalesce(g.avg_m,0) end,
    case when r.role_name='Tổ trưởng' then 0 else coalesce(g.avg_d,0) end,
    case when r.role_name='Tổ trưởng' then 0 else coalesce(g.total_d,0) end,
    case when r.role_name='Tổ trưởng' then 0 else coalesce(g.total_m,0) end,
    case when u.data is null then 'OK - TỰ ĐỘNG'
         else 'CÓ '||jsonb_array_length(u.data)||' CNCH CHƯA XÁC ĐỊNH HỆ/BẬC' end,
    coalesce(u.data,'[]'::jsonb)
  from allowed a cross join roles r
  left join agg g on g.team_id=a.id and g.grade_name=r.role_name
  left join unknowns u on u.team_id=a.id
  order by a.leader_name,r.sort_order;
end $$;

revoke execute on function public.get_payroll_summary(uuid) from public, anon;
grant  execute on function public.get_payroll_summary(uuid) to authenticated;
notify pgrst, 'reload schema';
