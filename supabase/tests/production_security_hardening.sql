begin;

create extension if not exists pgtap;

select plan(15);

select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.mirror_clerk_profile(text,text,timestamptz,text,text,text,text)'::regprocedure
  ),
  true,
  'Clerk profile mirror remains a narrow security-definer boundary'
);

select ok(
  (
    select 'search_path=app, public' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'public.mirror_clerk_profile(text,text,timestamptz,text,text,text,text)'::regprocedure
  ),
  'Clerk profile mirror pins search_path'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.mirror_clerk_profile(text,text,timestamptz,text,text,text,text)',
    'execute'
  ),
  'anonymous clients cannot execute Clerk profile mirroring'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.mirror_clerk_profile(text,text,timestamptz,text,text,text,text)',
    'execute'
  ),
  'authenticated clients cannot execute Clerk profile mirroring'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.mirror_clerk_profile(text,text,timestamptz,text,text,text,text)',
    'execute'
  ),
  'service role can execute Clerk profile mirroring'
);

select ok(
  not has_table_privilege('anon', 'public.analytics_events', 'insert'),
  'anonymous clients have no analytics insert grant'
);

select ok(
  has_table_privilege('authenticated', 'public.analytics_events', 'insert'),
  'authenticated clients retain analytics insert access'
);

select ok(
  has_table_privilege('authenticated', 'public.analytics_events', 'select'),
  'authenticated clients retain analytics read access'
);

select ok(
  not has_table_privilege('authenticated', 'public.analytics_events', 'update'),
  'authenticated clients cannot update analytics events'
);

select ok(
  not has_table_privilege('authenticated', 'public.analytics_events', 'delete'),
  'authenticated clients cannot delete analytics events'
);

set local role anon;
select set_config('request.jwt.claim.sub', '', true);

select throws_ok(
  $$ insert into public.analytics_events(user_id, name) values (null, 'anonymous_spam') $$,
  '42501',
  'permission denied for table analytics_events',
  'anonymous clients cannot create unattributed analytics events'
);

reset role;

insert into public.profiles(id, handle, display_name)
values ('user_prod_security_owner', 'prodsecurityowner', 'Production Security Owner');

insert into public.places(
  id,
  canonical_name,
  category,
  latitude,
  longitude,
  source_provider,
  source_provider_place_id
)
values
  (
    'a1000000-0000-0000-0000-000000000001',
    'Production Security Place A',
    'coffee',
    34.0522,
    -118.2437,
    'codex_security_test',
    'place-a'
  ),
  (
    'a1000000-0000-0000-0000-000000000002',
    'Production Security Place B',
    'restaurant',
    34.0523,
    -118.2438,
    'codex_security_test',
    'place-b'
  );

insert into public.user_places(
  id,
  user_id,
  place_id,
  status,
  visibility,
  source_type
)
values (
  'a2000000-0000-0000-0000-000000000001',
  'user_prod_security_owner',
  'a1000000-0000-0000-0000-000000000001',
  'been',
  'self',
  'manual'
);

insert into public.place_lists(id, owner_user_id, name, visibility)
values (
  'a3000000-0000-0000-0000-000000000001',
  'user_prod_security_owner',
  'Production Security List',
  'followers'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_prod_security_owner', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select lives_ok(
  $$
    insert into public.analytics_events(user_id, name)
    values ('user_prod_security_owner', 'authenticated_event')
  $$,
  'authenticated clients can create self-attributed analytics events'
);

select throws_ok(
  $$ insert into public.analytics_events(user_id, name) values (null, 'unattributed_event') $$,
  '42501',
  'new row violates row-level security policy for table "analytics_events"',
  'authenticated clients cannot create unattributed analytics events'
);

select lives_ok(
  $$
    insert into public.place_list_items(
      id,
      list_id,
      place_id,
      owner_user_place_id,
      added_by_user_id
    )
    values (
      'a4000000-0000-0000-0000-000000000001',
      'a3000000-0000-0000-0000-000000000001',
      'a1000000-0000-0000-0000-000000000001',
      'a2000000-0000-0000-0000-000000000001',
      'user_prod_security_owner'
    )
  $$,
  'list items accept a user-place reference for the same place'
);

select throws_ok(
  $$
    insert into public.place_list_items(
      id,
      list_id,
      place_id,
      owner_user_place_id,
      added_by_user_id
    )
    values (
      'a4000000-0000-0000-0000-000000000002',
      'a3000000-0000-0000-0000-000000000001',
      'a1000000-0000-0000-0000-000000000002',
      'a2000000-0000-0000-0000-000000000001',
      'user_prod_security_owner'
    )
  $$,
  '42501',
  'new row violates row-level security policy for table "place_list_items"',
  'list items reject a user-place reference for a different place'
);

select * from finish();

rollback;
