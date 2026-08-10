-- =====================================================================
-- 018_workers_safe_api.sql · Phase 9D — RPC workers-safe (AUTHENTICATED-ONLY, ADR-019/R9D-01).
-- Bảng public.workers có RLS v1 (TO authenticated; anon deny) ⇒ đọc qua RPC SECURITY DEFINER.
-- PII khối lượng lớn (full_name ~1808) ⇒ **CHỈ grant authenticated; revoke public + revoke anon**.
-- Allowlist TỐI THIỂU = đúng những gì congNhan dùng: mnv, full_name, job_title, team_name, stt_in_team.
--   TUYỆT ĐỐI KHÔNG trả id/team_id/legacy_lookup_key(mojibake)/created_by/updated_by/deleted_at/audit.
--   (workers KHÔNG có cột email/phone/salary — cấu trúc không tồn tại.)
-- Bảo mật: search_path='' cố định, fully-qualified, KHÔNG dynamic SQL, chỉ active (deleted_at IS NULL),
--   KHÔNG grant base-table cho anon, KHÔNG policy mới trên workers (RLS v1 nguyên), KHÔNG service_role.
-- =====================================================================

drop function if exists public.get_workers_catalog();

create function public.get_workers_catalog()
returns table (mnv text, full_name text, job_title text, team_name text, stt_in_team int)
language sql
stable
security definer
set search_path = ''
as $$
  select w.mnv, w.full_name, w.job_title, t.leader_name, w.stt_in_team
  from public.workers w
  left join public.teams t on t.id = w.team_id
  where w.deleted_at is null
    and coalesce(btrim(w.mnv), '') <> ''
  order by w.mnv, w.id   -- w.id chỉ để sắp xếp ổn định (KHÔNG trả ra)
$$;

comment on function public.get_workers_catalog() is
  'Workers-safe (AUTHENTICATED-ONLY): danh sách công nhân active (mnv, full_name, job_title, team_name, stt_in_team). KHÔNG anon; KHÔNG ID/khóa ngoài/PII dư/lương.';

-- AUTHENTICATED-ONLY: thu hồi public + anon, chỉ cấp authenticated.
revoke execute on function public.get_workers_catalog() from public;
revoke execute on function public.get_workers_catalog() from anon;
grant  execute on function public.get_workers_catalog() to authenticated;

notify pgrst, 'reload schema';
