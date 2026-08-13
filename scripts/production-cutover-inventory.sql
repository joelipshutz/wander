\set ON_ERROR_STOP on
\pset pager off

\echo '== source identity =='
select
  now() at time zone 'utc' as captured_at_utc,
  current_database() as database_name,
  current_setting('server_version') as postgres_version,
  pg_size_pretty(pg_database_size(current_database())) as database_size;

\echo '== non-system schemas =='
select schema_name
from information_schema.schemata
where schema_name not like 'pg\_%' escape '\'
  and schema_name <> 'information_schema'
order by schema_name;

\echo '== installed extensions =='
select extname, extversion
from pg_extension
order by extname;

\echo '== exact relation counts: application and hosted service schemas =='
select format(
  'select %L as relation, count(*) as exact_rows from %I.%I;',
  schemaname || '.' || tablename,
  schemaname,
  tablename
)
from pg_tables
where schemaname in (
  'app',
  'auth',
  'cron',
  'public',
  'realtime',
  'storage',
  'supabase_migrations',
  'vault'
)
order by schemaname, tablename
\gexec

\echo '== storage bucket configuration =='
select id, name, public, file_size_limit, allowed_mime_types
from storage.buckets
order by id;

\echo '== storage object totals =='
select
  bucket_id,
  count(*) as object_count,
  coalesce(sum((metadata ->> 'size')::bigint), 0) as total_bytes
from storage.objects
group by bucket_id
order by bucket_id;

\echo '== migration ledger =='
select version, name
from supabase_migrations.schema_migrations
order by version;

\echo '== public function security metadata =='
select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as identity_arguments,
  p.prosecdef as security_definer,
  p.proconfig as function_config,
  p.proacl as access_control_list
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('app', 'public')
order by n.nspname, p.proname, identity_arguments;

\echo '== RLS and policies =='
select
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
from pg_policies
where schemaname in ('public', 'storage')
order by schemaname, tablename, policyname;

\echo '== scheduled jobs =='
select jobid, schedule, command, active
from cron.job
order by jobid;
