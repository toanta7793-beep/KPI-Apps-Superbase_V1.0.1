-- HOÀN TÁC 054_search_word_boundary.sql
--
-- Đưa search_catalog_candidates về bản 053 (khớp chuỗi con cho mọi từ khóa).
--
-- ⚠️ CẢNH BÁO: bản cũ kém chính xác hơn — từ ngắn khớp lọt vào giữa từ khác, ví dụ "on"
-- khớp trong "trong", làm kết quả không liên quan đứng ngang hàng với kết quả đúng.
-- Không mất dữ liệu: hàm chỉ đọc.

create or replace function public.search_catalog_candidates(
  p_query text,
  p_limit  integer default 60
)
returns table (
  price_item_id  uuid,
  category_name  text,
  content        text,
  unit           text,
  calc_price     numeric,
  so_tu_khop     int,
  tong_so_tu     int,
  khop_het       boolean
)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_tokens text[];
  v_total  int;
begin
  -- Danh mục và đơn giá là dữ liệu kinh doanh: phải có hồ sơ đang hoạt động mới xem được.
  -- (Trước migration 051, các hàm danh mục còn cho anon gọi — không lặp lại chuyện đó.)
  if not app.is_active_profile() then raise exception 'FORBIDDEN' using errcode='42501'; end if;

  -- Bỏ dấu, tách từ, loại từ quá ngắn (1 ký tự thường là nhiễu, trừ số).
  select array_agg(t) into v_tokens
  from unnest(regexp_split_to_array(app.norm_vn(coalesce(p_query,'')), '\s+')) t
  where length(t) >= 2 or t ~ '^[0-9]+$';

  v_total := coalesce(array_length(v_tokens, 1), 0);
  if v_total = 0 then return; end if;
  if p_limit is null or p_limit < 1 or p_limit > 200 then p_limit := 60; end if;

  return query
  with ung_vien as (
    select p.id, p.category_name, p.content, p.unit, p.calc_price,
           app.norm_vn(p.category_name || ' ' || p.content) as chuoi_tim
    from public.price_items p
    where p.is_active
  ), cham_diem as (
    select u.*,
           (select count(*) from unnest(v_tokens) t where position(t in u.chuoi_tim) > 0)::int as khop
    from ung_vien u
  )
  select c.id, c.category_name, c.content, c.unit, c.calc_price,
         c.khop, v_total, (c.khop = v_total)
  from cham_diem c
  where c.khop > 0
  -- Khớp hết từ khóa lên trước; rồi tới khớp nhiều từ nhất; cuối cùng ưu tiên tên NGẮN hơn
  -- vì tên ngắn thường là hạng mục chính, tên dài là biến thể chi tiết.
  order by (c.khop = v_total) desc, c.khop desc, length(c.content) asc, c.content
  limit p_limit;
end $$;

revoke execute on function public.search_catalog_candidates(text,integer) from public, anon;
grant  execute on function public.search_catalog_candidates(text,integer) to authenticated;
notify pgrst, 'reload schema';
