-- =====================================================================
-- 016_catalog_safe_api.sql · Phase 9B — RPC catalog-safe cho đường public (giải R9-14).
-- Anon/authenticated đọc danh mục qua RPC SECURITY DEFINER, KHÔNG mở SELECT trực tiếp
--   price_items/salary_standards, KHÔNG trả đơn giá/ID nội bộ/bản ghi inactive.
-- Bảo mật: search_path='' cố định, fully-qualified, KHÔNG dynamic SQL, input trim + giới hạn độ dài,
--   chỉ is_active, revoke execute from public, grant chỉ anon+authenticated, KHÔNG grant base-table cho anon,
--   KHÔNG policy trực tiếp trên price_items, KHÔNG service_role.
-- =====================================================================

-- cap1: danh sách tên danh mục (work_categories active). Chỉ trả category_name.
create or replace function public.get_catalog_cap1()
returns table (category_name text)
language sql
stable
security definer
set search_path = ''
as $$
  select wc.name
  from public.work_categories wc
  where wc.is_active is true
    and coalesce(btrim(wc.name), '') <> ''
  group by wc.name
  order by wc.name
$$;

-- cap2: nội dung công việc theo danh mục (price_items active). Chỉ trả content + unit.
-- TUYỆT ĐỐI KHÔNG trả approved_price/calc_price/salary/id. Input: trim + tối đa 200 ký tự.
create or replace function public.get_catalog_cap2(p_category_name text)
returns table (content text, unit text)
language sql
stable
security definer
set search_path = ''
as $$
  select pi.content, coalesce(max(pi.unit), '') as unit
  from public.price_items pi
  where pi.is_active is true
    and coalesce(btrim(p_category_name), '') <> ''
    and char_length(coalesce(p_category_name, '')) <= 200
    and pi.category_name = btrim(p_category_name)
    and coalesce(btrim(pi.content), '') <> ''
  group by pi.content
  order by pi.content
$$;

comment on function public.get_catalog_cap1()      is 'Catalog-safe: tên danh mục cấp 1 (active). Không giá/ID.';
comment on function public.get_catalog_cap2(text)   is 'Catalog-safe: nội dung cấp 2 theo danh mục (active). Chỉ content+unit, KHÔNG giá/ID.';

-- Quyền tối thiểu: thu hồi execute mặc định của public, chỉ cấp anon + authenticated.
revoke execute on function public.get_catalog_cap1()    from public;
revoke execute on function public.get_catalog_cap2(text) from public;
grant  execute on function public.get_catalog_cap1()    to anon, authenticated;
grant  execute on function public.get_catalog_cap2(text) to anon, authenticated;

-- Nạp lại schema cache PostgREST (DDL runtime) để RPC hiện diện ngay.
notify pgrst, 'reload schema';
