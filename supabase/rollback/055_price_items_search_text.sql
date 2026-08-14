-- HOÀN TÁC 055_price_items_search_text.sql
--
-- Đưa hàm tìm về bản 054 (tự chuẩn hóa mỗi lần truy vấn) rồi bỏ cột và trigger.
--
-- ⚠️ Sau khi chạy, tìm kiếm chậm lại như cũ (~670 ms trên 8.893 dòng). Không mất dữ liệu
-- nghiệp vụ: search_text chỉ là bản sao đã chuẩn hóa của category_name + content, dựng lại
-- được bất cứ lúc nào.
--
-- Thứ tự bắt buộc: đưa hàm về bản cũ TRƯỚC (để nó thôi đọc cột), rồi mới bỏ cột.

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
  if not app.is_active_profile() then raise exception 'FORBIDDEN' using errcode='42501'; end if;

  -- Tách từ khóa: bỏ dấu, đổi mọi ký tự không phải chữ/số thành dấu cách rồi mới tách.
  select array_agg(t) into v_tokens
  from unnest(regexp_split_to_array(
         regexp_replace(app.norm_vn(coalesce(p_query,'')), '[^a-z0-9]+', ' ', 'g'), '\s+')) t
  where length(t) >= 2 or t ~ '^[0-9]+$';

  v_total := coalesce(array_length(v_tokens, 1), 0);
  if v_total = 0 then return; end if;
  if p_limit is null or p_limit < 1 or p_limit > 200 then p_limit := 60; end if;

  return query
  with ung_vien as (
    select p.id, p.category_name, p.content, p.unit, p.calc_price,
           -- Bọc hai đầu bằng dấu cách để khớp cả từ chỉ cần dùng position(' tu ').
           ' ' || regexp_replace(app.norm_vn(p.category_name || ' ' || p.content),
                                 '[^a-z0-9]+', ' ', 'g') || ' ' as chuoi_tim
    from public.price_items p
    where p.is_active
  ), cham_diem as (
    select u.*,
           (select count(*) from unnest(v_tokens) t
             where case
                     -- Từ ngắn: phải là một TỪ riêng, không nằm lọt trong từ khác.
                     when length(t) <= 3 then position(' ' || t || ' ' in u.chuoi_tim) > 0
                     -- Từ dài: khớp chuỗi con, để bắt được cả khi dính dấu câu hay hậu tố.
                     else position(t in u.chuoi_tim) > 0
                   end)::int as khop
    from ung_vien u
  )
  select c.id, c.category_name, c.content, c.unit, c.calc_price,
         c.khop, v_total, (c.khop = v_total)
  from cham_diem c
  where c.khop > 0
  order by (c.khop = v_total) desc, c.khop desc, length(c.content) asc, c.content
  limit p_limit;
end $$;

revoke execute on function public.search_catalog_candidates(text,integer) from public, anon;
grant  execute on function public.search_catalog_candidates(text,integer) to authenticated;
notify pgrst, 'reload schema';

drop trigger if exists trg_price_item_search_text on public.price_items;
drop function if exists app.price_item_fill_search_text();
alter table public.price_items drop column if exists search_text;
drop function if exists app.chuan_hoa_tim_kiem(text);

notify pgrst, 'reload schema';
