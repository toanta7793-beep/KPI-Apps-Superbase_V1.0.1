-- 032_price_catalog_import.sql
-- Nhập/cập nhật danh mục cấp 1–2 + đơn vị + đơn giá bằng Excel (Admin).
-- Cùng cơ chế an toàn với 025_worker_roster_import_parity.sql:
--   kiểm tra toàn bộ file trước khi ghi -> 1 dòng lỗi thì KHÔNG đổi dữ liệu cũ,
--   snapshot backup trước khi ghi, request_key + SHA-256 chống bấm lặp,
--   toàn bộ chạy trong 1 transaction, chỉ ADMIN.
--
-- Quy tắc giá (chốt với chủ sở hữu hệ thống):
--   Excel có DUY NHẤT 1 cột giá = giá DÙNG TÍNH TOÁN (đã gồm +30%) -> price_items.calc_price
--   price_items.approved_price = round(calc_price / 1.3, 2)  (chỉ để tham khảo/truy vết)
--   Công thức KPI/hòa vốn KHÔNG đổi: vẫn dùng calc_price.
--
-- Dòng cũ không còn trong file:
--   - nếu đang được job chưa xóa tham chiếu (category_name+content) -> GIỮ NGUYÊN is_active
--     (không phá KPI của việc đang chạy), đếm vào retained_referenced_count
--   - còn lại -> is_active=false (ngừng dùng), KHÔNG xóa cứng để giữ lịch sử.

create table if not exists app.price_catalog_import_backups (
  id                       uuid primary key default gen_random_uuid(),
  request_key              uuid not null unique,
  source_name              text not null,
  source_sha256            text not null,
  imported_by              uuid not null,
  imported_at              timestamptz not null default now(),
  before_price_items       jsonb not null,
  before_categories        jsonb not null,
  after_item_count         int not null,
  after_category_count     int not null,
  deactivated_count        int not null,
  retained_referenced_count int not null
);

revoke all on app.price_catalog_import_backups from public, anon, authenticated;

create or replace function public.admin_import_price_catalog(
  p_request_key   uuid,
  p_source_name   text,
  p_source_sha256 text,
  p_items         jsonb
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_existing     jsonb;
  v_before_items jsonb;
  v_before_cats  jsonb;
  v_item_count   int;
  v_cat_count    int;
  v_inserted     int;
  v_updated      int;
  v_deactivated  int;
  v_retained     int;
begin
  if app.current_role() <> 'ADMIN' then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if p_request_key is null or btrim(coalesce(p_source_name,''))='' then
    raise exception 'IMPORT_METADATA_REQUIRED';
  end if;
  if coalesce(p_source_sha256,'') !~ '^[0-9a-f]{64}$' then
    raise exception 'INVALID_SOURCE_HASH';
  end if;
  if jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0
     or jsonb_array_length(p_items) > 20000 then
    raise exception 'INVALID_PRICE_CATALOG_SIZE';
  end if;

  -- Idempotency: bấm lặp cùng request_key trả lại kết quả cũ, không ghi lần hai.
  select jsonb_build_object(
    'item_count',     b.after_item_count,
    'category_count', b.after_category_count,
    'deactivated_count', b.deactivated_count,
    'retained_referenced_count', b.retained_referenced_count,
    'source_sha256',  b.source_sha256,
    'idempotent',     true
  ) into v_existing
  from app.price_catalog_import_backups b
  where b.request_key = p_request_key;
  if v_existing is not null then return v_existing; end if;

  create temporary table price_rows (
    category_name  text not null,
    content        text not null,
    tech_desc      text,
    unit           text,
    work_code      text,
    calc_price     numeric(15,2) not null,
    approved_price numeric(15,2) not null,
    is_special     boolean not null default false,
    primary key (category_name, content)
  ) on commit drop;

  begin
    insert into price_rows(category_name,content,tech_desc,unit,work_code,calc_price,approved_price,is_special)
    select btrim(x.category_name),
           btrim(x.content),
           nullif(btrim(coalesce(x.tech_desc,'')),''),
           nullif(btrim(coalesce(x.unit,'')),''),
           nullif(btrim(coalesce(x.work_code,'')),''),
           round(x.calc_price, 2),
           round(x.calc_price / 1.3, 2),
           (app.norm_vn(btrim(x.content)) like '%dao tao%'
             or app.norm_vn(btrim(x.content)) like '%phat sinh%')
    from jsonb_to_recordset(p_items) as x(
      category_name text, content text, tech_desc text, unit text,
      work_code text, calc_price numeric
    );
  exception when unique_violation then
    raise exception 'DUPLICATE_PRICE_KEY';
  end;

  if (select count(*) from price_rows) <> jsonb_array_length(p_items) then
    raise exception 'DUPLICATE_PRICE_KEY';
  end if;
  if exists(select 1 from price_rows where category_name='' or content='') then
    raise exception 'INVALID_PRICE_ROW';
  end if;
  if exists(select 1 from price_rows where unit is null) then
    raise exception 'MISSING_UNIT';
  end if;
  if exists(select 1 from price_rows where calc_price is null or calc_price < 0) then
    raise exception 'INVALID_PRICE_VALUE';
  end if;
  if exists(select 1 from price_rows where position('‡' in category_name) > 0
                                        or position('‡' in content) > 0) then
    raise exception 'ILLEGAL_LOOKUP_SEPARATOR';
  end if;

  -- Snapshot trước khi ghi.
  select coalesce(jsonb_agg(jsonb_build_object(
           'id',p.id,'work_code',p.work_code,'category_name',p.category_name,
           'content',p.content,'tech_desc',p.tech_desc,'unit',p.unit,
           'approved_price',p.approved_price,'calc_price',p.calc_price,
           'is_special',p.is_special,'is_active',p.is_active
         ) order by p.category_name, p.content),'[]'::jsonb)
    into v_before_items from public.price_items p;
  select coalesce(jsonb_agg(jsonb_build_object(
           'id',c.id,'name',c.name,'defined_name',c.defined_name,
           'work_count',c.work_count,'is_active',c.is_active
         ) order by c.name),'[]'::jsonb)
    into v_before_cats from public.work_categories c;

  -- Cấp 1.
  insert into public.work_categories(name, work_count, created_by, updated_by)
  select r.category_name, count(*), auth.uid(), auth.uid()
  from price_rows r group by r.category_name
  on conflict (name) do update
    set work_count = excluded.work_count,
        is_active  = true,
        updated_at = now(),
        updated_by = auth.uid();

  -- Cấp 2 + đơn giá.
  with upserted as (
    insert into public.price_items(
      work_code, category_id, category_name, content, tech_desc, unit,
      approved_price, calc_price, is_special, is_active, created_by, updated_by
    )
    select r.work_code,
           (select c.id from public.work_categories c where c.name = r.category_name),
           r.category_name, r.content, r.tech_desc, r.unit,
           r.approved_price, r.calc_price, r.is_special, true, auth.uid(), auth.uid()
    from price_rows r
    on conflict (category_name, content) do update
      set work_code       = excluded.work_code,
          category_id     = excluded.category_id,
          tech_desc       = excluded.tech_desc,
          unit            = excluded.unit,
          approved_price  = excluded.approved_price,
          calc_price      = excluded.calc_price,
          is_special      = excluded.is_special,
          is_active       = true,
          updated_at      = now(),
          updated_by      = auth.uid()
    returning (xmax = 0) as was_insert
  )
  select count(*) filter (where was_insert),
         count(*) filter (where not was_insert)
    into v_inserted, v_updated
  from upserted;

  -- Dòng cũ còn được việc chưa xóa tham chiếu -> giữ nguyên để không phá KPI.
  select count(*) into v_retained
  from public.price_items p
  where p.is_active
    and not exists(select 1 from price_rows r
                   where r.category_name = p.category_name and r.content = p.content)
    and exists(select 1 from public.jobs j
               where j.deleted_at is null
                 and j.category_name = p.category_name and j.content = p.content);

  update public.price_items p
     set is_active = false, updated_at = now(), updated_by = auth.uid()
   where p.is_active
     and not exists(select 1 from price_rows r
                    where r.category_name = p.category_name and r.content = p.content)
     and not exists(select 1 from public.jobs j
                    where j.deleted_at is null
                      and j.category_name = p.category_name and j.content = p.content);
  get diagnostics v_deactivated = row_count;

  select count(*), count(distinct category_name) into v_item_count, v_cat_count from price_rows;

  insert into app.price_catalog_import_backups(
    request_key, source_name, source_sha256, imported_by,
    before_price_items, before_categories,
    after_item_count, after_category_count, deactivated_count, retained_referenced_count
  ) values (
    p_request_key, btrim(p_source_name), p_source_sha256, auth.uid(),
    v_before_items, v_before_cats,
    v_item_count, v_cat_count, v_deactivated, v_retained
  );

  return jsonb_build_object(
    'item_count',                v_item_count,
    'category_count',            v_cat_count,
    'inserted_count',            v_inserted,
    'updated_count',             v_updated,
    'deactivated_count',         v_deactivated,
    'retained_referenced_count', v_retained,
    'source_sha256',             p_source_sha256,
    'idempotent',                false
  );
end $$;

revoke execute on function public.admin_import_price_catalog(uuid,text,text,jsonb) from public, anon;
grant  execute on function public.admin_import_price_catalog(uuid,text,text,jsonb) to authenticated;

comment on function public.admin_import_price_catalog(uuid,text,text,jsonb) is
  'Admin: nhập danh mục cấp 1-2 + đơn giá từ Excel. calc_price = cột giá trong file; approved_price = calc_price/1.3. All-or-nothing, idempotent theo request_key.';
