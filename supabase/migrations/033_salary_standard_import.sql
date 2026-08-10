-- 033_salary_standard_import.sql
-- Nhập/cập nhật BẢNG LƯƠNG CHUẨN theo Hệ × Chức danh bằng Excel (Admin).
-- Cùng cơ chế an toàn với 025/032: kiểm tra toàn file trước khi ghi, snapshot backup,
-- request_key + SHA-256 chống bấm lặp, 1 transaction, chỉ ADMIN.
--
-- Cột Excel: Hệ | Chức danh | Mức lương tháng (VNĐ)
--   'Lương 1 ngày' KHÔNG nhập từ file — database tự tính:
--   salary_standards.daily_salary = monthly_salary / 26 (generated column, giữ nguyên công thức lõi).
--
-- Xử lý mức lương 0:
--   Constraint ck_salary_month_pos yêu cầu monthly_salary > 0, trong khi bảng lương thực tế
--   để 0 cho các dòng Tổ trưởng. Dòng <= 0 được BỎ QUA (không ghi) và đếm vào skipped_zero_count;
--   nếu tổ hợp đó đang tồn tại thì chuyển is_active=false. Không nới lỏng constraint.
--
-- Hệ / Chức danh mới trong file được tạo tự động (file lương là nguồn của cả hai danh sách,
-- đúng như seed.sql ghi: systems = BANG_LUONG_CHUAN.A distinct, salary_grades = cột B distinct).

create table if not exists app.salary_standard_import_backups (
  id                  uuid primary key default gen_random_uuid(),
  request_key         uuid not null unique,
  source_name         text not null,
  source_sha256       text not null,
  imported_by         uuid not null,
  imported_at         timestamptz not null default now(),
  before_standards    jsonb not null,
  after_row_count     int not null,
  skipped_zero_count  int not null,
  deactivated_count   int not null,
  new_system_count    int not null,
  new_grade_count     int not null
);

revoke all on app.salary_standard_import_backups from public, anon, authenticated;

create or replace function public.admin_import_salary_standard(
  p_request_key   uuid,
  p_source_name   text,
  p_source_sha256 text,
  p_rows          jsonb
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_existing     jsonb;
  v_before       jsonb;
  v_row_count    int;
  v_skipped      int;
  v_deactivated  int;
  v_new_systems  int;
  v_new_grades   int;
  v_inserted     int;
  v_updated      int;
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
  if jsonb_typeof(p_rows) <> 'array'
     or jsonb_array_length(p_rows) = 0
     or jsonb_array_length(p_rows) > 5000 then
    raise exception 'INVALID_SALARY_TABLE_SIZE';
  end if;

  select jsonb_build_object(
    'row_count',          b.after_row_count,
    'skipped_zero_count', b.skipped_zero_count,
    'deactivated_count',  b.deactivated_count,
    'source_sha256',      b.source_sha256,
    'idempotent',         true
  ) into v_existing
  from app.salary_standard_import_backups b
  where b.request_key = p_request_key;
  if v_existing is not null then return v_existing; end if;

  create temporary table salary_rows (
    system_name    text not null,
    grade_name     text not null,
    monthly_salary numeric(15,2) not null,
    is_leader      boolean not null default false,
    system_id      uuid,
    grade_id       uuid,
    primary key (system_name, grade_name)
  ) on commit drop;

  begin
    insert into salary_rows(system_name, grade_name, monthly_salary, is_leader)
    select btrim(x.system_name),
           btrim(x.grade_name),
           round(coalesce(x.monthly_salary, 0), 2),
           app.norm_vn(btrim(x.grade_name)) like '%to truong%'
    from jsonb_to_recordset(p_rows) as x(
      system_name text, grade_name text, monthly_salary numeric
    );
  exception when unique_violation then
    raise exception 'DUPLICATE_SALARY_KEY';
  end;

  if (select count(*) from salary_rows) <> jsonb_array_length(p_rows) then
    raise exception 'DUPLICATE_SALARY_KEY';
  end if;
  if exists(select 1 from salary_rows where system_name='' or grade_name='') then
    raise exception 'INVALID_SALARY_ROW';
  end if;
  if exists(select 1 from salary_rows where monthly_salary < 0) then
    raise exception 'NEGATIVE_SALARY';
  end if;
  -- Chặn hai chuỗi chỉ khác dấu/hoa thường trỏ về cùng một hệ hoặc cùng một chức danh.
  if exists(select 1 from salary_rows group by app.norm_vn(system_name)
            having count(distinct system_name) > 1) then
    raise exception 'AMBIGUOUS_SYSTEM_NAME';
  end if;
  if exists(select 1 from salary_rows group by app.norm_vn(grade_name)
            having count(distinct grade_name) > 1) then
    raise exception 'AMBIGUOUS_GRADE_NAME';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id',s.id,'system_id',s.system_id,'grade_id',s.grade_id,
           'monthly_salary',s.monthly_salary,'is_active',s.is_active
         ) order by s.system_id, s.grade_id),'[]'::jsonb)
    into v_before from public.salary_standards s;

  -- Hệ kỹ thuật mới.
  with new_systems as (
    insert into public.systems(code, name, created_by, updated_by)
    select upper(left(regexp_replace(app.norm_vn(r.system_name), '[^a-z0-9]', '', 'g'), 24)),
           r.system_name, auth.uid(), auth.uid()
    from (select distinct system_name from salary_rows) r
    where not exists(select 1 from public.systems s where s.name = r.system_name)
    on conflict (name) do nothing
    returning 1
  )
  select count(*) into v_new_systems from new_systems;

  -- Chức danh/bậc mới.
  with new_grades as (
    insert into public.salary_grades(name, is_leader, rank, created_by, updated_by)
    select r.grade_name,
           r.is_leader,
           (select coalesce(max(g.rank), 0) from public.salary_grades g)
             + row_number() over (order by r.grade_name),
           auth.uid(), auth.uid()
    from (select distinct grade_name, bool_or(is_leader) as is_leader
          from salary_rows group by grade_name) r
    where not exists(select 1 from public.salary_grades g where g.name = r.grade_name)
    on conflict (name) do nothing
    returning 1
  )
  select count(*) into v_new_grades from new_grades;

  -- WHERE là bắt buộc: PostgREST chạy với `safeupdate` bật cho role authenticated,
  -- UPDATE không có WHERE bị từ chối ("UPDATE requires a WHERE clause").
  -- Cùng lý do đã khiến migration 029 phải vá lại update trong admin_import_worker_roster.
  update salary_rows r
     set system_id = (select s.id from public.systems s where s.name = r.system_name),
         grade_id  = (select g.id from public.salary_grades g where g.name = r.grade_name)
   where r.system_id is null or r.grade_id is null;

  if exists(select 1 from salary_rows where system_id is null or grade_id is null) then
    raise exception 'UNRESOLVED_SYSTEM_OR_GRADE';
  end if;

  -- Chỉ ghi các dòng có lương > 0 (constraint ck_salary_month_pos).
  with upserted as (
    insert into public.salary_standards(system_id, grade_id, monthly_salary, is_active, created_by, updated_by)
    select r.system_id, r.grade_id, r.monthly_salary, true, auth.uid(), auth.uid()
    from salary_rows r
    where r.monthly_salary > 0
    on conflict (system_id, grade_id) do update
      set monthly_salary = excluded.monthly_salary,
          is_active      = true,
          updated_at     = now(),
          updated_by     = auth.uid()
    returning (xmax = 0) as was_insert
  )
  select count(*) filter (where was_insert),
         count(*) filter (where not was_insert)
    into v_inserted, v_updated
  from upserted;

  select count(*) into v_skipped from salary_rows where monthly_salary <= 0;

  -- Tổ hợp không còn trong file, hoặc trong file nhưng lương = 0 -> ngừng dùng (không xóa cứng).
  update public.salary_standards s
     set is_active = false, updated_at = now(), updated_by = auth.uid()
   where s.is_active
     and not exists(select 1 from salary_rows r
                    where r.system_id = s.system_id
                      and r.grade_id  = s.grade_id
                      and r.monthly_salary > 0);
  get diagnostics v_deactivated = row_count;

  select count(*) into v_row_count from salary_rows where monthly_salary > 0;

  insert into app.salary_standard_import_backups(
    request_key, source_name, source_sha256, imported_by, before_standards,
    after_row_count, skipped_zero_count, deactivated_count, new_system_count, new_grade_count
  ) values (
    p_request_key, btrim(p_source_name), p_source_sha256, auth.uid(), v_before,
    v_row_count, v_skipped, v_deactivated, v_new_systems, v_new_grades
  );

  return jsonb_build_object(
    'row_count',          v_row_count,
    'inserted_count',     v_inserted,
    'updated_count',      v_updated,
    'skipped_zero_count', v_skipped,
    'deactivated_count',  v_deactivated,
    'new_system_count',   v_new_systems,
    'new_grade_count',    v_new_grades,
    'source_sha256',      p_source_sha256,
    'idempotent',         false
  );
end $$;

revoke execute on function public.admin_import_salary_standard(uuid,text,text,jsonb) from public, anon;
grant  execute on function public.admin_import_salary_standard(uuid,text,text,jsonb) to authenticated;

comment on function public.admin_import_salary_standard(uuid,text,text,jsonb) is
  'Admin: nhập bảng lương chuẩn Hệ x Chức danh từ Excel. daily_salary vẫn do DB tự tính = monthly/26. Dòng lương 0 bị bỏ qua. All-or-nothing, idempotent theo request_key.';
