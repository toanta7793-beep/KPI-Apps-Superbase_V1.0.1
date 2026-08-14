-- 055_price_items_search_text.sql
--
-- Sửa hiệu năng của search_catalog_candidates: 670 ms trên 8.893 dòng là quá chậm cho một ô
-- tìm kiếm, nhất là khi nhiều người gõ cùng lúc.
--
-- NGUYÊN NHÂN (đo được, không phỏng đoán): hàm chuẩn hóa LẠI toàn bộ bảng cho MỖI lần gõ —
-- app.norm_vn() cộng regexp_replace() chạy 8.893 lần mỗi truy vấn. Đo riêng phần chấm điểm
-- có ép dùng kết quả: 669–688 ms. (Lần đo đầu ra 56 ms là do bộ tối ưu loại bỏ phép tính
-- vì count(*) không dùng tới nó — số đó vô nghĩa.)
--
-- CÁCH SỬA: chuẩn hóa MỘT LẦN lúc ghi, lưu vào cột riêng, rồi tìm trên cột đó.
-- Không dùng cột sinh (generated) được vì app.norm_vn khai báo STABLE chứ không IMMUTABLE;
-- đổi tính chất của một hàm nằm trong xương sống rủi ro hơn nhiều so với thêm một trigger.
--
-- ĐÃ KIỂM TRƯỚC KHI THÊM CỘT vào bảng xương sống price_items — không chỗ nào vỡ:
--   * admin_import_price_catalog chèn theo DANH SÁCH CỘT rõ ràng, không dùng select *.
--   * Ảnh chụp trước khi nhập dùng jsonb_build_object với các trường liệt kê sẵn,
--     không dùng to_jsonb(cả dòng).
--   * Không hàm nào khai báo price_items%rowtype.
--   * Frontend không đọc thẳng bảng này, chỉ gọi RPC.
-- Cột mới do trigger tự điền nên mọi luồng ghi hiện có không cần biết tới nó.

alter table public.price_items add column if not exists search_text text;

comment on column public.price_items.search_text is
  'Chuỗi tìm kiếm đã bỏ dấu và chuẩn hóa dấu câu, có dấu cách bọc hai đầu. Trigger tự điền.';

-- Chuẩn hóa dùng chung một chỗ để trigger và bản nạp lại không thể lệch nhau.
create or replace function app.chuan_hoa_tim_kiem(p_text text)
returns text language sql stable set search_path = '' as $$
  select ' ' || regexp_replace(app.norm_vn(coalesce(p_text,'')), '[^a-z0-9]+', ' ', 'g') || ' '
$$;

create or replace function app.price_item_fill_search_text()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.search_text := app.chuan_hoa_tim_kiem(coalesce(new.category_name,'') || ' ' || coalesce(new.content,''));
  return new;
end $$;

-- Chỉ chạy khi hai cột nguồn thay đổi: sửa giá hay bật/tắt is_active không cần tính lại.
drop trigger if exists trg_price_item_search_text on public.price_items;
create trigger trg_price_item_search_text
before insert or update of category_name, content on public.price_items
for each row execute function app.price_item_fill_search_text();

-- Nạp lại cho dữ liệu đang có. Không đụng category_name/content nên trigger không chạy lại.
update public.price_items
   set search_text = app.chuan_hoa_tim_kiem(coalesce(category_name,'') || ' ' || coalesce(content,''))
 where search_text is null;

-- Sau khi nạp xong thì bắt buộc phải có: trigger bảo đảm mọi dòng mới đều được điền, và
-- một dòng thiếu search_text sẽ âm thầm không bao giờ tìm thấy — đúng loại lỗi im lặng
-- cần chặn ngay ở tầng ràng buộc.
alter table public.price_items alter column search_text set not null;

-- ---------------------------------------------------------------------------------------
-- Hàm tìm: đọc cột đã chuẩn hóa sẵn. Quy tắc chấm điểm giữ NGUYÊN so với 054.
-- ---------------------------------------------------------------------------------------
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

  select array_agg(t) into v_tokens
  from unnest(regexp_split_to_array(app.chuan_hoa_tim_kiem(p_query), '\s+')) t
  where length(t) >= 2 or t ~ '^[0-9]+$';

  v_total := coalesce(array_length(v_tokens, 1), 0);
  if v_total = 0 then return; end if;
  if p_limit is null or p_limit < 1 or p_limit > 200 then p_limit := 60; end if;

  return query
  with cham_diem as (
    select p.id, p.category_name, p.content, p.unit, p.calc_price,
           (select count(*) from unnest(v_tokens) t
             where case
                     -- Từ ngắn phải là một TỪ riêng, nếu không "on" sẽ khớp trong "trong".
                     when length(t) <= 3 then position(' ' || t || ' ' in p.search_text) > 0
                     else position(t in p.search_text) > 0
                   end)::int as khop
    from public.price_items p
    where p.is_active
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
