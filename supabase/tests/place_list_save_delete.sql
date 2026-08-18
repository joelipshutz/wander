begin;

create extension if not exists pgtap;
set local search_path = public, extensions;

select plan(8);

select ok(
  (
    select not prosecdef
      and 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'app.visible_place_lists()'::regprocedure
  ),
  'list summaries remain security invoker with a pinned search path'
);
select ok(
  (
    select not prosecdef
      and 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'app.place_list_detail(uuid)'::regprocedure
  ),
  'list detail remains security invoker with a pinned search path'
);
select ok(
  (
    select not prosecdef
      and 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'public.visible_place_lists_snapshot()'::regprocedure
  ),
  'the list snapshot remains security invoker with a pinned search path'
);
select ok(
  has_function_privilege('authenticated', 'app.visible_place_lists()', 'execute')
    and has_function_privilege('authenticated', 'app.place_list_detail(uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.visible_place_lists_snapshot()', 'execute')
    and not has_function_privilege('anon', 'public.visible_place_lists_snapshot()', 'execute'),
  'the list read boundary remains authenticated-only'
);

insert into public.profiles (id, handle, display_name)
values
  ('user_list_delete_owner', 'list_delete_owner', 'List Delete Owner'),
  ('user_list_delete_source', 'list_delete_source', 'List Delete Source');

insert into public.follows (follower_user_id, followed_user_id, source)
values ('user_list_delete_owner', 'user_list_delete_source', 'profile');

insert into public.places (
  id, canonical_name, category, latitude, longitude,
  source_provider, source_provider_place_id, confidence
)
values (
  '9a000000-0000-0000-0000-000000000001',
  'List Delete Place',
  'coffee_tea_sweets',
  34.0522,
  -118.2437,
  'place_list_delete_test',
  'list-delete-place',
  1
);

insert into public.user_places (
  id, user_id, place_id, status, visibility, nearby_confirmed, source_type, deleted_at
)
values
  (
    '9b000000-0000-0000-0000-000000000001',
    'user_list_delete_owner',
    '9a000000-0000-0000-0000-000000000001',
    'wanna_go',
    'followers',
    false,
    'manual',
    now()
  ),
  (
    '9b000000-0000-0000-0000-000000000002',
    'user_list_delete_source',
    '9a000000-0000-0000-0000-000000000001',
    'been',
    'followers',
    false,
    'manual',
    null
  );

insert into public.place_lists (id, owner_user_id, name, visibility)
values
  ('9c000000-0000-0000-0000-000000000001', 'user_list_delete_owner', 'Deleted reference', 'followers'),
  ('9c000000-0000-0000-0000-000000000002', 'user_list_delete_owner', 'Active fallback reference', 'followers');

insert into public.place_list_items (
  id, list_id, place_id, owner_user_place_id, source_user_place_id, added_by_user_id
)
values
  (
    '9d000000-0000-0000-0000-000000000001',
    '9c000000-0000-0000-0000-000000000001',
    '9a000000-0000-0000-0000-000000000001',
    '9b000000-0000-0000-0000-000000000001',
    '9b000000-0000-0000-0000-000000000001',
    'user_list_delete_owner'
  ),
  (
    '9d000000-0000-0000-0000-000000000002',
    '9c000000-0000-0000-0000-000000000002',
    '9a000000-0000-0000-0000-000000000001',
    '9b000000-0000-0000-0000-000000000001',
    '9b000000-0000-0000-0000-000000000002',
    'user_list_delete_owner'
  );

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_list_delete_owner', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select is(
  (select item_count from public.visible_place_lists() where id = '9c000000-0000-0000-0000-000000000001'),
  0,
  'a list summary excludes an item backed only by a deleted save'
);
select is(
  jsonb_array_length(public.place_list_detail('9c000000-0000-0000-0000-000000000001')->'items'),
  0,
  'list detail excludes the same unresolvable item'
);
select is(
  (select item_count from public.visible_place_lists() where id = '9c000000-0000-0000-0000-000000000002'),
  1,
  'an item remains visible when another active save reference can hydrate it'
);
select ok(
  exists (
    select 1
    from jsonb_array_elements((public.visible_place_lists_snapshot())->'owner_places') place_row
    where place_row->>'user_place_id' = '9b000000-0000-0000-0000-000000000002'
  ),
  'the list snapshot hydrates an active referenced save owned by a contributor'
);

select * from finish() as result(message);

rollback;
