-- 050_daily_production_atomic_save.sql
--
-- QA 12/08/2026: sửa một lỗi tranh chấp trong save_daily_production.
--
-- BỆNH: hàm đang làm hai bước tách rời — SELECT xem đã có dòng chưa, rồi mới INSERT hoặc
-- UPDATE. Giữa hai bước đó có một khe hở. Hai người cùng ghi cho MỘT việc trong MỘT ngày
-- (ví dụ tổ trưởng và giám sát cùng nhập hộ lúc cuối ngày) thì cả hai đều thấy "chưa có
-- dòng nào" và cùng INSERT. Người thứ hai đụng ràng buộc uq_daily_production và nhận về
--     duplicate key value violates unique constraint "uq_daily_production"
-- Đây là lỗi Postgres thô, không có bản dịch, và nó nói sai bản chất: sự thật là dòng đó
-- vừa bị người khác ghi và khóa, tức PRODUCTION_LOCKED.
--
-- CÁCH SỬA: gộp thành MỘT câu lệnh nguyên tử.
--   insert ... on conflict (job_id, work_date) do update ... where d.is_locked = false
-- Postgres tự khóa dòng khi xử lý xung đột nên không còn khe hở nào.
--   * Dòng chưa có       -> INSERT, trả về id.
--   * Dòng có, chưa khóa -> UPDATE, trả về id.
--   * Dòng có, ĐANG KHÓA -> mệnh đề where không thỏa, KHÔNG có dòng nào trả về
--                           -> v_id là null -> báo đúng PRODUCTION_LOCKED.
--
-- Mọi kiểm tra khác (vai trò, phạm vi tổ, lao động đặc biệt, ngày trong khoảng việc, khối
-- lượng không âm) giữ NGUYÊN từng dòng. Chỉ đổi cách ghi.

create or replace function public.save_daily_production(
  p_job_id uuid, p_work_date date, p_quantity numeric
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_job public.jobs; v_id uuid;
begin
  if app.current_role() not in ('ADMIN','GIAM_SAT','TO_TRUONG') then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  select * into v_job from public.jobs where id = p_job_id and deleted_at is null;
  if v_job.id is null then raise exception 'JOB_NOT_FOUND'; end if;
  if not app.can_access_team(v_job.team_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;

  -- Đào tạo / Phát sinh có khối lượng tự sinh = số người × số ngày. Ghi tay vào đó là ghi
  -- đè lên một con số hệ thống tự tính, nên chặn hẳn thay vì để người dùng tự đoán.
  if v_job.is_special_labor then raise exception 'SPECIAL_LABOR_AUTO_ACCUMULATED'; end if;

  -- Ngày ghi phải nằm trong khoảng ngày của việc. Không có ràng buộc này thì một ngày gõ
  -- nhầm sẽ lặng lẽ cộng vào lũy kế và không ai truy ra được.
  if p_work_date < v_job.start_date or p_work_date > v_job.end_date then
    raise exception 'PRODUCTION_DATE_OUTSIDE_JOB';
  end if;
  if p_quantity is null or p_quantity < 0 then raise exception 'PRODUCTION_QTY_INVALID'; end if;

  insert into public.job_daily_production as d (job_id, work_date, quantity, is_locked, locked_at, locked_by)
  values (p_job_id, p_work_date, p_quantity, true, now(), auth.uid())
  on conflict (job_id, work_date) do update
     set quantity = excluded.quantity, is_locked = true, locked_at = now(), locked_by = auth.uid(),
         updated_at = now(), updated_by = auth.uid()
   where d.is_locked = false
  returning d.id into v_id;

  if v_id is null then raise exception 'PRODUCTION_LOCKED'; end if;
  return v_id;
end $$;

revoke execute on function public.save_daily_production(uuid,date,numeric) from public, anon;
grant  execute on function public.save_daily_production(uuid,date,numeric) to authenticated;
notify pgrst, 'reload schema';
