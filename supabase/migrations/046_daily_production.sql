-- 046_daily_production.sql
--
-- Phần 2 "Đánh giá sản lượng", bước 1: nơi cất số liệu và ba hàm để nhập, mở khóa, tổng hợp.
-- Theo bản mô tả đã duyệt: docs/PHASE2_DANH_GIA_SAN_LUONG_SPEC.md
--
-- Vì sao phải có bảng mới thay vì dùng lại assignments.completed_qty:
-- cột đó là KIỂU CHỮ, gắn theo từng công nhân, và chỉ giữ trạng thái hiện hành. Không cộng
-- dồn được, không biết ngày nào ra ngày nào. Đây là thứ khác hẳn.
--
-- Không cấp quyền bảng cho authenticated. Mọi lối vào đi qua ba hàm security definer bên
-- dưới, giống cách jobs chỉ đọc được qua get_job_metrics. Bật RLS mà không có policy nào là
-- lớp chặn thứ hai: lỡ sau này ai đó cấp quyền bảng thì vẫn không đọc được gì.

create table if not exists public.job_daily_production (
  id          uuid primary key default gen_random_uuid(),
  job_id      uuid not null references public.jobs(id) on delete cascade,
  work_date   date not null,
  quantity    numeric(18,4) not null,
  is_locked   boolean not null default true,
  locked_at   timestamptz,
  locked_by   uuid,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid default auth.uid(),
  updated_by  uuid default auth.uid(),
  constraint uq_daily_production unique (job_id, work_date),
  -- Cho phép 0 (hôm đó không làm được gì là một sự thật cần ghi), cấm số âm.
  constraint ck_daily_production_qty check (quantity >= 0)
);

comment on table public.job_daily_production is
  'Khối lượng hoàn thành theo NGÀY của từng việc. Một dòng = một việc trong một ngày.';

create index if not exists ix_daily_production_job on public.job_daily_production(job_id);
create index if not exists ix_daily_production_date on public.job_daily_production(work_date);

alter table public.job_daily_production enable row level security;
revoke all on public.job_daily_production from anon, authenticated;

-- ---------------------------------------------------------------------------------------
-- Ghi số của một ngày. Lưu là KHÓA luôn, theo quyết định "Đồng ý là không sửa lại được nữa".
-- ---------------------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------------------
-- Mở khóa để sửa lại. CHỈ Admin. Không lưu lịch sử — đã chốt như vậy, và hệ quả của nó đã
-- ghi ở mục 10 của bản mô tả.
-- ---------------------------------------------------------------------------------------
create or replace function public.unlock_daily_production(p_job_id uuid, p_work_date date)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if app.current_role() <> 'ADMIN' then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  update public.job_daily_production
     set is_locked = false, updated_at = now(), updated_by = auth.uid()
   where job_id = p_job_id and work_date = p_work_date;
  if not found then raise exception 'PRODUCTION_ROW_NOT_FOUND'; end if;
end $$;

-- ---------------------------------------------------------------------------------------
-- Bảng Đánh giá sản lượng. Một dòng = MỘT VIỆC (quyết định 11/08/2026), không gộp theo mã
-- nhóm: các việc trong một nhóm có thể khác đơn vị (md, m², kg) nên cộng khối lượng lại thì
-- cột phần trăm mất nghĩa.
-- ---------------------------------------------------------------------------------------
create or replace function public.get_production_evaluation(
  p_team_id uuid default null, p_week_slot integer default null
) returns table (
  job_id uuid, team_id uuid, team_name text, week_slot int,
  phan_khu text, vi_tri_chi_tiet text, noi_dung text,
  muc_tieu numeric, don_vi text, start_date date, end_date date,
  luy_ke_khoi_luong numeric, luy_ke_thanh_tien numeric, luy_ke_phan_tram numeric,
  so_ngay_da_nhap int, tu_dong boolean, group_code text
)
language plpgsql stable security definer set search_path = '' as $$
declare v_allowed uuid[];
begin
  if not app.is_active_profile() or app.current_role() not in ('ADMIN','GIAM_SAT','TO_TRUONG') then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if p_week_slot is not null and p_week_slot not between 1 and 4 then
    raise exception 'INVALID_WEEK_SLOT';
  end if;

  -- Chốt phạm vi trước rồi mới lọc bằng mảng, không gọi can_access_team trong where.
  -- Gọi trong where sẽ chặn bộ tối ưu đẩy điều kiện xuống — đúng nguyên nhân đã làm bảng
  -- lương timeout ở migration 039.
  select coalesce(array_agg(t.id), '{}'::uuid[]) into v_allowed
  from public.teams t
  where t.deleted_at is null and t.is_active
    and (p_team_id is null or t.id = p_team_id)
    and app.can_access_team(t.id);
  if array_length(v_allowed, 1) is null then return; end if;

  return query
  with scoped as (
    select m.*, w.week_slot
    from app.v_job_metrics m
    join public.work_weeks w on w.id = m.week_id
    where m.team_id = any(v_allowed)
      and (p_week_slot is null or w.week_slot = p_week_slot)
  ), nhap_tay as (
    select d.job_id, sum(d.quantity)::numeric as tong, count(*)::int as so_ngay
    from public.job_daily_production d
    join scoped s on s.id = d.job_id
    group by d.job_id
  ), tinh as (
    select s.*,
           -- Đào tạo / Phát sinh: tự lũy kế theo ngày đã trôi qua, không lấy số nhập tay.
           -- Việc đã kết thúc thì đứng ở 100%, không tăng tiếp.
           case when s.is_special_labor then
             greatest(0, least(current_date, s.end_date) - s.start_date + 1)
           else null end::int as ngay_da_qua,
           coalesce(nt.tong, 0)::numeric as tong_nhap_tay,
           coalesce(nt.so_ngay, 0)::int as so_ngay_nhap
    from scoped s left join nhap_tay nt on nt.job_id = s.id
  ), luy_ke as (
    select t.*,
           case when t.is_special_labor
                then t.quantity * (case when t.work_days > 0
                                        then least(greatest(t.ngay_da_qua,0), t.work_days)::numeric / t.work_days
                                        else 0 end)
                else t.tong_nhap_tay end as kl
    from tinh t
  )
  select l.id, l.team_id, tm.leader_name, l.week_slot::int,
         l.location, l.location, l.content,
         l.quantity, l.unit, l.start_date, l.end_date,
         round(l.kl, 4),
         round(l.kl * coalesce(l.unit_price, 0), 0),
         case when l.quantity > 0 then round(l.kl / l.quantity * 100, 2) else null end,
         l.so_ngay_nhap, l.is_special_labor, l.group_code
  from luy_ke l
  join public.teams tm on tm.id = l.team_id
  order by tm.leader_name, l.start_date, l.content;
end $$;

revoke execute on function public.save_daily_production(uuid,date,numeric) from public, anon;
revoke execute on function public.unlock_daily_production(uuid,date) from public, anon;
revoke execute on function public.get_production_evaluation(uuid,integer) from public, anon;
grant  execute on function public.save_daily_production(uuid,date,numeric) to authenticated;
grant  execute on function public.unlock_daily_production(uuid,date) to authenticated;
grant  execute on function public.get_production_evaluation(uuid,integer) to authenticated;
notify pgrst, 'reload schema';
