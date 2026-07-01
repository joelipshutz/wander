begin;

create extension if not exists pgtap;

select plan(3);

select is_empty(
  $$
    with app_tables(table_name) as (
      values
        ('analytics_events'),
        ('blocks'),
        ('clerk_profile_mirror_state'),
        ('clerk_webhook_events'),
        ('extraction_jobs'),
        ('follows'),
        ('place_attributes'),
        ('place_list_items'),
        ('place_list_members'),
        ('place_lists'),
        ('places'),
        ('profiles'),
        ('question_definitions'),
        ('source_artifacts'),
        ('sync_tombstones'),
        ('user_places')
    )
    select app_tables.table_name
    from app_tables
    where not exists (
      select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = app_tables.table_name
        and c.relkind in ('r', 'p')
        and c.relrowsecurity
    )
    order by app_tables.table_name
  $$,
  'all app-owned public tables have row level security enabled'
);

select is_empty(
  $$
    select table_name, privilege_type
    from information_schema.table_privileges
    where table_schema = 'public'
      and grantee = 'anon'
      and not (
        table_name = 'question_definitions'
        and privilege_type = 'SELECT'
      )
    order by table_name, privilege_type
  $$,
  'anon table grants are limited to question_definitions read'
);

select is_empty(
  $$
    select table_name, privilege_type
    from information_schema.table_privileges
    where table_schema = 'public'
      and lower(grantee) = 'public'
    order by table_name, privilege_type
  $$,
  'public role has no direct public table grants'
);

select * from finish();

rollback;
