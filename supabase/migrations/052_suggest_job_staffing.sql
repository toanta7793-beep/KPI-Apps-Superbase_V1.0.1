-- 052_suggest_job_staffing.sql
--
-- Gợi ý nhân công / số ngày / khối lượng sao cho việc CÓ LÃI nhưng không lãi quá nhiều.
-- Quyết định 13/08/2026: tính bằng SQL chính xác, KHÔNG dùng AI.
--
-- Vì sao không dùng AI cho phần này, dù yêu cầu ban đầu nhắc tới OpenAI:
--   * Công thức tính sản lượng là xương sống phải tuân thủ 100%. Một mô hình ngôn ngữ ƯỚC
--     LƯỢNG phép nhân chia; ở đây cần TÍNH.
--   * Cùng đầu vào phải luôn ra cùng kết quả. Mô hình sinh không đảm bảo điều đó.
--   * Không gian tìm kiếm rất nhỏ (mỗi tổ vài chục tổ hợp sau khi chặn cận), duyệt hết trong
--     mili giây, miễn phí, không phụ thuộc mạng.
--   * Mô hình có thể gợi ý cơ cấu thợ mà tổ không hề có người.
--
-- BA THỨ BẮT BUỘC GIỐNG HỆT phần đang chạy, nếu lệch là gợi ý sai so với lúc lưu thật:
--   1. Tra đơn giá: y hệt create_job — chỉ nhận khi khớp DUY NHẤT một dòng đơn giá đang dùng.
--   2. Lương ngày theo bậc: y hệt CTE role_avg của app.v_job_metrics —
--      avg(daily_salary) với salary_ok, không phải tổ trưởng, grade_name không rỗng.
--   3. Chênh lệch = khối lượng × đơn giá − quỹ lương ngày × số ngày.
--      Tổ trưởng KHÔNG tính vào quỹ lương ngày.
--
-- Ràng buộc theo quyết định của người dùng:
--   * Chỉ gợi ý trong phạm vi QUÂN SỐ THẬT của tổ.
--   * Chênh lệch phải DƯƠNG và không vượt 500.000 (mặc định), tính cho CẢ VIỆC.
--   * Trong các phương án hợp lệ, ưu tiên phương án XẾP ĐƯỢC NHIỀU NGƯỜI NHẤT.
--     (Càng ít người thì chênh lệch càng cao; trần 500.000 chính là cách nói
--     "xếp đủ người nhất có thể mà vẫn có lãi".)

-- ---------------------------------------------------------------------------------------
-- Năng lực của tổ theo bậc: vừa là ĐƠN GIÁ NGÀY, vừa là SỐ NGƯỜI CÓ SẴN.
-- Bộ lọc phải khớp CTE role_avg trong app.v_job_metrics. Có test khoá lại điều này.
-- ---------------------------------------------------------------------------------------
create or replace view app.v_team_grade_capacity as
select team_id,
       grade_name,
       count(*)::int              as so_nguoi_co_san,
       avg(daily_salary)::numeric as luong_ngay_tb
from app.v_worker_salary
where salary_ok and not is_actual_leader and grade_name is not null
group by team_id, grade_name;

-- ---------------------------------------------------------------------------------------
-- Hàm gợi ý. Chế độ tự suy ra từ tham số nào bỏ trống:
--   khối lượng + số ngày            -> gợi ý CƠ CẤU NHÂN CÔNG
--   khối lượng + cơ cấu nhân công   -> gợi ý SỐ NGÀY
--   cơ cấu nhân công + số ngày      -> gợi ý KHỐI LƯỢNG tối thiểu
-- ---------------------------------------------------------------------------------------
create or replace function public.suggest_job_staffing(
  p_team_id       uuid,
  p_category_name text,
  p_content       text,
  p_quantity      numeric default null,
  p_work_days     integer default null,
  p_count_worker1 integer default null,
  p_count_worker2 integer default null,
  p_count_worker3 integer default null,
  p_count_helper  integer default null,
  p_max_surplus   numeric default 500000
)
returns table (
  che_do            text,
  count_worker1     int,
  count_worker2     int,
  count_worker3     int,
  count_helper      int,
  tong_nguoi        int,
  work_days         int,
  quantity          numeric,
  don_gia           numeric,
  san_luong         numeric,
  chi_phi_nhan_cong numeric,
  chenh_lech        numeric,
  ghi_chu           text
)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_price numeric;
  v_r1 numeric := 0; v_r2 numeric := 0; v_r3 numeric := 0; v_rh numeric := 0;
  v_a1 int := 0;     v_a2 int := 0;     v_a3 int := 0;     v_ah int := 0;
  v_daily numeric;   v_san_luong numeric;  v_ngan_sach_ngay numeric;
  v_co_nhan_cong boolean;
begin
  if app.current_role() not in ('ADMIN','GIAM_SAT','TO_TRUONG') then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if not app.can_access_team(p_team_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;

  -- Đào tạo / Phát sinh có khối lượng tự sinh = số người × số ngày, không có đơn giá tra
  -- được, nên không có gì để tối ưu. Chặn hẳn thay vì trả về số vô nghĩa.
  if app.norm_vn(p_category_name) in ('dao tao','phat sinh') then
    raise exception 'SPECIAL_LABOR_NO_SUGGESTION';
  end if;

  -- Tra đơn giá GIỐNG HỆT create_job. Lệch một chữ ở đây là gợi ý một đằng, lưu một nẻo.
  select case when count(*) = 1 then min(calc_price) end into v_price
  from public.price_items
  where is_active and category_name = btrim(p_category_name) and content = btrim(p_content);
  if v_price is null or v_price <= 0 then raise exception 'PRICE_NOT_UNIQUE_OR_MISSING'; end if;

  select coalesce(max(luong_ngay_tb) filter (where grade_name = 'Thợ bậc 1'), 0),
         coalesce(max(luong_ngay_tb) filter (where grade_name = 'Thợ bậc 2'), 0),
         coalesce(max(luong_ngay_tb) filter (where grade_name = 'Thợ bậc 3'), 0),
         coalesce(max(luong_ngay_tb) filter (where grade_name = 'Thợ phụ'),   0),
         coalesce(max(so_nguoi_co_san) filter (where grade_name = 'Thợ bậc 1'), 0),
         coalesce(max(so_nguoi_co_san) filter (where grade_name = 'Thợ bậc 2'), 0),
         coalesce(max(so_nguoi_co_san) filter (where grade_name = 'Thợ bậc 3'), 0),
         coalesce(max(so_nguoi_co_san) filter (where grade_name = 'Thợ phụ'),   0)
    into v_r1, v_r2, v_r3, v_rh, v_a1, v_a2, v_a3, v_ah
  from app.v_team_grade_capacity where team_id = p_team_id;

  if v_a1 + v_a2 + v_a3 + v_ah = 0 then
    return query select 'KHONG_DU_DU_LIEU'::text, null::int,null::int,null::int,null::int,null::int,
      null::int,null::numeric, v_price, null::numeric,null::numeric,null::numeric,
      'Tổ chưa có công nhân nào xác định được lương ngày. Kiểm tra danh sách CNCH và bảng lương.'::text;
    return;
  end if;

  v_co_nhan_cong := coalesce(p_count_worker1,0) + coalesce(p_count_worker2,0)
                  + coalesce(p_count_worker3,0) + coalesce(p_count_helper,0) > 0;

  -- =========================================================================
  -- CHẾ ĐỘ 1 — có khối lượng + số ngày, thiếu nhân công  → gợi ý CƠ CẤU
  -- =========================================================================
  if p_quantity is not null and p_work_days is not null and not v_co_nhan_cong then
    if p_quantity <= 0 or p_work_days < 1 then raise exception 'INVALID_QUANTITY'; end if;
    v_san_luong := p_quantity * v_price;
    -- Chi phí phải nhỏ hơn sản lượng, nên quỹ lương ngày bị chặn trên. Dùng cận này để
    -- thu hẹp không gian duyệt: mỗi bậc chỉ cần xét tới số người mà ngân sách còn cho phép.
    v_ngan_sach_ngay := v_san_luong / p_work_days;

    return query
    with combos as (
      select c1.n as w1, c2.n as w2, c3.n as w3, ch.n as wh
      from generate_series(0, least(v_a1, case when v_r1 > 0 then floor(v_ngan_sach_ngay / v_r1)::int else 0 end)) c1(n),
           generate_series(0, least(v_a2, case when v_r2 > 0 then floor(v_ngan_sach_ngay / v_r2)::int else 0 end)) c2(n),
           generate_series(0, least(v_a3, case when v_r3 > 0 then floor(v_ngan_sach_ngay / v_r3)::int else 0 end)) c3(n),
           generate_series(0, least(v_ah, case when v_rh > 0 then floor(v_ngan_sach_ngay / v_rh)::int else 0 end)) ch(n)
      where c1.n + c2.n + c3.n + ch.n > 0
    ), scored as (
      select w1, w2, w3, wh,
             (w1*v_r1 + w2*v_r2 + w3*v_r3 + wh*v_rh)::numeric as luong_ngay,
             (w1 + w2 + w3 + wh)::int as tong
      from combos
    ), ket as (
      select s.*, (s.luong_ngay * p_work_days)::numeric as chi_phi,
             (v_san_luong - s.luong_ngay * p_work_days)::numeric as chenh
      from scored s
    )
    select 'NHAN_CONG'::text, k.w1, k.w2, k.w3, k.wh, k.tong,
           p_work_days, p_quantity, v_price, round(v_san_luong,0), round(k.chi_phi,0), round(k.chenh,0),
           ('Xếp được ' || k.tong || ' người, còn lãi ' || to_char(round(k.chenh,0),'FM999G999G999') || ' đ.')::text
    from ket k
    where k.chenh > 0 and k.chenh <= p_max_surplus
    -- Nhiều người nhất trước; cùng số người thì chọn phương án còn nhiều lãi hơn (rẻ hơn).
    order by k.tong desc, k.chenh desc
    limit 5;

    if not found then
      return query select 'KHONG_CO_PHUONG_AN'::text, null::int,null::int,null::int,null::int,null::int,
        p_work_days, p_quantity, v_price, round(v_san_luong,0), null::numeric, null::numeric,
        ('Không cơ cấu nào của tổ vừa có lãi vừa trong mức ' || to_char(p_max_surplus,'FM999G999G999')
         || ' đ. Sản lượng ' || to_char(round(v_san_luong,0),'FM999G999G999')
         || ' đ chia cho ' || p_work_days || ' ngày chỉ đủ trả ' || to_char(round(v_ngan_sach_ngay,0),'FM999G999G999')
         || ' đ/ngày. Hãy tăng khối lượng, giảm số ngày, hoặc nới mức chênh lệch.')::text;
    end if;
    return;
  end if;

  -- =========================================================================
  -- CHẾ ĐỘ 2 — có khối lượng + nhân công, thiếu số ngày  → gợi ý SỐ NGÀY
  -- =========================================================================
  if p_quantity is not null and v_co_nhan_cong and p_work_days is null then
    if p_quantity <= 0 then raise exception 'INVALID_QUANTITY'; end if;
    v_daily := coalesce(p_count_worker1,0)*v_r1 + coalesce(p_count_worker2,0)*v_r2
             + coalesce(p_count_worker3,0)*v_r3 + coalesce(p_count_helper,0)*v_rh;
    if v_daily <= 0 then raise exception 'INVALID_COUNTS'; end if;
    v_san_luong := p_quantity * v_price;

    return query
    with d as (select generate_series(1, greatest(1, ceil(v_san_luong / v_daily)::int)) as ngay)
    select 'SO_NGAY'::text,
           coalesce(p_count_worker1,0), coalesce(p_count_worker2,0),
           coalesce(p_count_worker3,0), coalesce(p_count_helper,0),
           (coalesce(p_count_worker1,0)+coalesce(p_count_worker2,0)
            +coalesce(p_count_worker3,0)+coalesce(p_count_helper,0))::int,
           d.ngay, p_quantity, v_price, round(v_san_luong,0),
           round(v_daily * d.ngay, 0), round(v_san_luong - v_daily * d.ngay, 0),
           ('Thi công ' || d.ngay || ' ngày thì còn lãi '
            || to_char(round(v_san_luong - v_daily * d.ngay,0),'FM999G999G999') || ' đ.')::text
    from d
    where v_san_luong - v_daily * d.ngay > 0
      and v_san_luong - v_daily * d.ngay <= p_max_surplus
    -- Nhiều ngày nhất trước: cho tổ nhiều thời gian nhất mà vẫn có lãi.
    order by d.ngay desc
    limit 5;

    if not found then
      return query select 'KHONG_CO_PHUONG_AN'::text,
        coalesce(p_count_worker1,0), coalesce(p_count_worker2,0),
        coalesce(p_count_worker3,0), coalesce(p_count_helper,0),
        (coalesce(p_count_worker1,0)+coalesce(p_count_worker2,0)
         +coalesce(p_count_worker3,0)+coalesce(p_count_helper,0))::int,
        null::int, p_quantity, v_price, round(v_san_luong,0), null::numeric, null::numeric,
        ('Với cơ cấu này, quỹ lương ' || to_char(round(v_daily,0),'FM999G999G999')
         || ' đ/ngày. Không số ngày nguyên nào cho chênh lệch dương và ≤ '
         || to_char(p_max_surplus,'FM999G999G999') || ' đ. Hãy giảm người hoặc tăng khối lượng.')::text;
    end if;
    return;
  end if;

  -- =========================================================================
  -- CHẾ ĐỘ 3 — có nhân công + số ngày, thiếu khối lượng → gợi ý KHỐI LƯỢNG
  -- =========================================================================
  if v_co_nhan_cong and p_work_days is not null and p_quantity is null then
    if p_work_days < 1 then raise exception 'INVALID_QUANTITY'; end if;
    v_daily := coalesce(p_count_worker1,0)*v_r1 + coalesce(p_count_worker2,0)*v_r2
             + coalesce(p_count_worker3,0)*v_r3 + coalesce(p_count_helper,0)*v_rh;
    if v_daily <= 0 then raise exception 'INVALID_COUNTS'; end if;

    return query
    -- Khối lượng tối thiểu để có lãi, làm tròn LÊN 2 chữ số thập phân: làm tròn xuống có
    -- thể rơi đúng vào điểm hòa vốn hoặc lỗ.
    with q as (
      select ceil(((v_daily * p_work_days) / v_price) * 100 + 1) / 100 as kl_min,
             floor((((v_daily * p_work_days) + p_max_surplus) / v_price) * 100) / 100 as kl_max
    )
    select 'KHOI_LUONG'::text,
           coalesce(p_count_worker1,0), coalesce(p_count_worker2,0),
           coalesce(p_count_worker3,0), coalesce(p_count_helper,0),
           (coalesce(p_count_worker1,0)+coalesce(p_count_worker2,0)
            +coalesce(p_count_worker3,0)+coalesce(p_count_helper,0))::int,
           p_work_days, q.kl_min, v_price, round(q.kl_min * v_price, 0),
           round(v_daily * p_work_days, 0), round(q.kl_min * v_price - v_daily * p_work_days, 0),
           ('Cần làm tối thiểu ' || trim(to_char(q.kl_min,'FM999G999G990D99'))
            || ' để có lãi; tới ' || trim(to_char(q.kl_max,'FM999G999G990D99'))
            || ' thì lãi chạm mức ' || to_char(p_max_surplus,'FM999G999G999') || ' đ.')::text
    from q where q.kl_min > 0;
    return;
  end if;

  -- Không đủ dữ kiện để suy ra ẩn số nào.
  return query select 'KHONG_DU_DU_LIEU'::text, null::int,null::int,null::int,null::int,null::int,
    null::int, null::numeric, v_price, null::numeric, null::numeric, null::numeric,
    'Cần nhập đúng HAI trong ba nhóm: khối lượng, số ngày, cơ cấu nhân công.'::text;
end $$;

revoke execute on function public.suggest_job_staffing(uuid,text,text,numeric,integer,integer,integer,integer,integer,numeric) from public, anon;
grant  execute on function public.suggest_job_staffing(uuid,text,text,numeric,integer,integer,integer,integer,integer,numeric) to authenticated;
notify pgrst, 'reload schema';
