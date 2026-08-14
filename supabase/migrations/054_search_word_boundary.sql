-- 054_search_word_boundary.sql
--
-- Sửa độ chính xác của search_catalog_candidates, phát hiện khi thử trên 8.893 dòng đơn giá
-- thật (dữ liệu cục bộ chỉ có 1 dòng nên không thể lộ ra).
--
-- BỆNH: hàm khớp từ khóa bằng position(), tức khớp CHUỖI CON. Từ ngắn vì thế dính vào giữa
-- từ khác. Gõ "bao on d160" trả về "Công tác đặt Sleeve xuyên tường" với điểm tối đa 3/3, vì:
--     "bao"  khớp trong "(Bao gồm"     -> hợp lệ
--     "on"   khớp trong "tr-ON-g nha"  -> NHIỄU, không liên quan gì tới bảo ôn
--     "d160" khớp ở đâu đó trong mô tả -> hợp lệ
-- Dòng nhiễu đứng ngang hàng với "Bảo ôn ống uPVC D160" nên đẩy kết quả đúng xuống dưới.
--
-- CÁCH SỬA: từ NGẮN (≤3 ký tự) phải khớp cả TỪ; từ dài (≥4) vẫn khớp chuỗi con.
--   * Từ ngắn là nơi sinh nhiễu: "on", "cut", "ong" nằm lọt trong hàng trăm từ khác.
--   * Từ dài gần như không bao giờ dính nhầm, mà khớp chuỗi con lại cần thiết để "d160"
--     tìm được trong "D160;" hay "uPVC D160mm" — chỗ có dấu câu dính liền.
--
-- Chuẩn hóa dấu câu thành dấu cách trước khi so, nếu không "d160;" sẽ không tách được từ.
--
-- Không đổi chữ ký hàm, không đổi thứ tự cột trả về, không đụng gì khác.

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
