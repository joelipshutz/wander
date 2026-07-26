begin;

create extension if not exists pgtap;

select plan(21);

create temporary table check_in_tap_results(message text) on commit drop;

insert into check_in_tap_results select has_column('public', 'user_places', 'historical_want_note', 'user places preserve the prior Wanna note');
insert into check_in_tap_results select has_column('public', 'user_places', 'historical_want_attribute_answers', 'user places preserve prior Wanna answers');
insert into check_in_tap_results select has_column('public', 'user_places', 'historical_want_tags', 'user places preserve prior Wanna tags');
insert into check_in_tap_results select has_column('public', 'user_places', 'historical_wanted_at', 'user places preserve the prior Wanna timestamp');
insert into check_in_tap_results select has_column('public', 'feed_events', 'visit_id', 'feed events can identify an explicit check-in');

insert into check_in_tap_results select ok(
  exists (
    select 1
    from pg_constraint constraint_row
    join pg_class table_row on table_row.oid = constraint_row.conrelid
    join pg_namespace namespace_row on namespace_row.oid = table_row.relnamespace
    where namespace_row.nspname = 'public'
      and table_row.relname = 'feed_events'
      and constraint_row.contype = 'f'
      and pg_get_constraintdef(constraint_row.oid) ilike
        '%foreign key (visit_id) references place_visits(id) on delete cascade%'
  ),
  'feed event check-in subject cascades with its ticket'
);

insert into check_in_tap_results select has_function(
  'app',
  'save_own_check_in',
  array['jsonb', 'jsonb', 'jsonb', 'jsonb', 'jsonb']
);
insert into check_in_tap_results select has_function(
  'public',
  'save_own_check_in',
  array['jsonb', 'jsonb', 'jsonb', 'jsonb', 'jsonb']
);
insert into check_in_tap_results select has_function('app', 'delete_own_check_in', array['uuid']);
insert into check_in_tap_results select has_function('public', 'delete_own_check_in', array['uuid']);

insert into check_in_tap_results select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'app.save_own_check_in(jsonb,jsonb,jsonb,jsonb,jsonb)'::regprocedure
  ),
  true,
  'internal check-in save is security definer'
);
insert into check_in_tap_results select ok(
  (
    select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'app.save_own_check_in(jsonb,jsonb,jsonb,jsonb,jsonb)'::regprocedure
  ),
  'internal check-in save pins search_path'
);
insert into check_in_tap_results select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.save_own_check_in(jsonb,jsonb,jsonb,jsonb,jsonb)'::regprocedure
  ),
  false,
  'public check-in save is security invoker'
);
insert into check_in_tap_results select ok(
  (
    select 'search_path=app, public' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'public.save_own_check_in(jsonb,jsonb,jsonb,jsonb,jsonb)'::regprocedure
  ),
  'public check-in save pins search_path'
);
insert into check_in_tap_results select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'app.delete_own_check_in(uuid)'::regprocedure
  ),
  true,
  'internal check-in delete is security definer'
);
insert into check_in_tap_results select ok(
  (
    select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'app.delete_own_check_in(uuid)'::regprocedure
  ),
  'internal check-in delete pins search_path'
);
insert into check_in_tap_results select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.delete_own_check_in(uuid)'::regprocedure
  ),
  false,
  'public check-in delete is security invoker'
);
insert into check_in_tap_results select ok(
  has_function_privilege(
    'authenticated',
    'public.save_own_check_in(jsonb,jsonb,jsonb,jsonb,jsonb)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'app.save_own_check_in(jsonb,jsonb,jsonb,jsonb,jsonb)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.save_own_check_in(jsonb,jsonb,jsonb,jsonb,jsonb)',
    'execute'
  ),
  'only authenticated can call the check-in save boundary'
);
insert into check_in_tap_results select ok(
  has_function_privilege(
    'authenticated',
    'public.delete_own_check_in(uuid)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'app.delete_own_check_in(uuid)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.delete_own_check_in(uuid)',
    'execute'
  ),
  'only authenticated can call the check-in delete boundary'
);
insert into check_in_tap_results select has_trigger(
  'public',
  'place_visits',
  'place_visits_record_feed_activity',
  'explicit check-ins record one feed event'
);
insert into check_in_tap_results select ok(
  exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and tablename = 'feed_events'
      and indexname = 'feed_events_explicit_visit_unique_idx'
      and indexdef ilike '%where ((visit_id is not null)%'
  ),
  'feed has one event per explicit check-in ticket'
);

insert into check_in_tap_results(message)
select * from finish() as result(message);

do $strict_check_in_pgtap$
declare
  diagnostics text;
begin
  select string_agg(message, E'\n' order by message)
  into diagnostics
  from check_in_tap_results
  where message like 'not ok%'
    or message like '# Looks like%'
    or message like 'Bail out!%';

  if diagnostics is not null then
    raise exception 'check-in pgTAP failures: %', diagnostics;
  end if;
end;
$strict_check_in_pgtap$;

select jsonb_agg(message order by message) as message
from check_in_tap_results;

rollback;
