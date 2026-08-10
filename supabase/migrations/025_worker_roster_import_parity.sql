-- 025_worker_roster_import_parity.sql
-- Atomic Excel roster replacement matching CapNhatCNCH.js semantics.
-- Production is not changed by creating this migration file.

create table if not exists app.worker_roster_import_backups (
  id uuid primary key default gen_random_uuid(),
  request_key uuid not null unique,
  source_name text not null,
  source_sha256 text not null,
  imported_by uuid not null,
  imported_at timestamptz not null default now(),
  before_workers jsonb not null,
  before_active_team_ids uuid[] not null,
  after_worker_count int not null,
  after_team_count int not null
);

revoke all on app.worker_roster_import_backups from public, anon, authenticated;

create or replace function public.admin_import_worker_roster(
  p_request_key uuid,
  p_source_name text,
  p_source_sha256 text,
  p_workers jsonb,
  p_active_team_names text[] default '{}'::text[]
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_before jsonb;
  v_before_active uuid[];
  v_worker_count int;
  v_team_count int;
  v_archived_count int;
  v_upserted_count int;
  v_existing jsonb;
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
  if jsonb_typeof(p_workers) <> 'array' or jsonb_array_length(p_workers)=0 or jsonb_array_length(p_workers)>10000 then
    raise exception 'INVALID_WORKER_ROSTER_SIZE';
  end if;

  select jsonb_build_object(
    'worker_count', b.after_worker_count,
    'team_count', b.after_team_count,
    'source_sha256', b.source_sha256,
    'idempotent', true
  ) into v_existing
  from app.worker_roster_import_backups b
  where b.request_key=p_request_key;
  if v_existing is not null then return v_existing; end if;

  create temporary table roster_rows (
    mnv text primary key,
    full_name text not null,
    job_title text not null,
    team_name text not null,
    team_key text not null,
    stt_in_team int not null,
    team_id uuid
  ) on commit drop;

  insert into roster_rows(mnv,full_name,job_title,team_name,team_key,stt_in_team)
  select upper(btrim(x.mnv)), btrim(x.full_name), btrim(x.job_title), btrim(x.team_name),
         app.norm_vn(x.team_name), x.stt_in_team
  from jsonb_to_recordset(p_workers) as x(
    mnv text, full_name text, job_title text, team_name text, stt_in_team int
  );

  if (select count(*) from roster_rows) <> jsonb_array_length(p_workers) then
    raise exception 'DUPLICATE_MNV';
  end if;
  if exists(select 1 from roster_rows where mnv='' or full_name='' or job_title='' or team_name='' or stt_in_team<1) then
    raise exception 'INVALID_WORKER_ROW';
  end if;
  if exists(
    select 1 from roster_rows r
    where (select count(*) from public.teams t
           where t.deleted_at is null and
             (app.norm_vn(t.leader_name)=r.team_key or app.norm_vn(coalesce(t.legacy_team_name,''))=r.team_key)) <> 1
  ) then
    raise exception 'UNKNOWN_OR_AMBIGUOUS_TEAM';
  end if;

  update roster_rows r set team_id=(
    select t.id from public.teams t
    where t.deleted_at is null and
      (app.norm_vn(t.leader_name)=r.team_key or app.norm_vn(coalesce(t.legacy_team_name,''))=r.team_key)
    limit 1
  );

  if exists(
    select 1 from public.profiles p
    join public.workers w on w.id=p.worker_id
    where p.is_active and not exists(select 1 from roster_rows r where r.mnv=upper(btrim(w.mnv)))
  ) then
    raise exception 'IMPORT_WOULD_DISABLE_ACTIVE_LOGIN';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',w.id,'mnv',w.mnv,'full_name',w.full_name,'job_title',w.job_title,
    'team_id',w.team_id,'stt_in_team',w.stt_in_team,'legacy_lookup_key',w.legacy_lookup_key,
    'deleted_at',w.deleted_at
  ) order by w.mnv),'[]'::jsonb) into v_before from public.workers w;
  select coalesce(array_agg(t.id order by t.team_code),'{}'::uuid[]) into v_before_active
  from public.teams t where t.deleted_at is null and t.is_active;

  update public.workers w set
    full_name=r.full_name,
    job_title=r.job_title,
    team_id=r.team_id,
    stt_in_team=r.stt_in_team,
    legacy_lookup_key=r.team_name||'‡'||r.stt_in_team,
    deleted_at=null,
    updated_at=now(),
    updated_by=auth.uid()
  from roster_rows r where upper(btrim(w.mnv))=r.mnv;

  insert into public.workers(
    mnv,full_name,job_title,team_id,stt_in_team,legacy_lookup_key,created_by,updated_by
  )
  select r.mnv,r.full_name,r.job_title,r.team_id,r.stt_in_team,r.team_name||'‡'||r.stt_in_team,auth.uid(),auth.uid()
  from roster_rows r
  where not exists(select 1 from public.workers w where upper(btrim(w.mnv))=r.mnv);

  update public.workers w set deleted_at=now(),updated_at=now(),updated_by=auth.uid()
  where w.deleted_at is null and not exists(select 1 from roster_rows r where r.mnv=upper(btrim(w.mnv)));
  get diagnostics v_archived_count = row_count;

  -- Same as the Sheet backend: keep an active team only when it remains in the
  -- new roster. The supplied list is the pre-import active selection.
  update public.teams t set
    is_active = exists(
      select 1 from unnest(coalesce(p_active_team_names,'{}'::text[])) a(name)
      where app.norm_vn(a.name)=app.norm_vn(t.leader_name)
    ) and exists(select 1 from roster_rows r where r.team_id=t.id),
    updated_at=now(),updated_by=auth.uid()
  where t.deleted_at is null;

  select count(*),count(distinct team_id) into v_worker_count,v_team_count from roster_rows;
  v_upserted_count := v_worker_count;
  insert into app.worker_roster_import_backups(
    request_key,source_name,source_sha256,imported_by,before_workers,before_active_team_ids,
    after_worker_count,after_team_count
  ) values(
    p_request_key,btrim(p_source_name),p_source_sha256,auth.uid(),v_before,v_before_active,
    v_worker_count,v_team_count
  );

  return jsonb_build_object(
    'worker_count',v_worker_count,'team_count',v_team_count,
    'upserted_count',v_upserted_count,'archived_count',v_archived_count,
    'active_team_count',(select count(*) from public.teams where deleted_at is null and is_active),
    'source_sha256',p_source_sha256,'idempotent',false
  );
end $$;

revoke execute on function public.admin_import_worker_roster(uuid,text,text,jsonb,text[]) from public, anon;
grant execute on function public.admin_import_worker_roster(uuid,text,text,jsonb,text[]) to authenticated;

-- Clone-safe: no team is activated by migration. Activate teams through the admin roster import.
