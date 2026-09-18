begin;
create extension if not exists pgtap;
select plan(22);

select has_function('public', 'own_place_visit_details', array['uuid[]']);
select is((select prosecdef from pg_proc where oid = 'public.own_place_visit_details(uuid[])'::regprocedure), true,
  'owner answer projection is an explicit security-definer boundary');
select is((select provolatile::text from pg_proc where oid = 'public.own_place_visit_details(uuid[])'::regprocedure), 's',
  'owner answer projection is stable');
select ok((select 'search_path=public, app' = any(proconfig) from pg_proc
  where oid = 'public.own_place_visit_details(uuid[])'::regprocedure), 'search path is pinned');
select function_privs_are('public', 'own_place_visit_details', array['uuid[]'], 'authenticated', array['EXECUTE']);
select function_privs_are('public', 'own_place_visit_details', array['uuid[]'], 'anon', array[]::text[]);
select ok(not has_column_privilege('authenticated', 'public.place_visits', 'attribute_answers', 'select'),
  'the raw answer column remains denied');

insert into public.profiles (id, handle, display_name) values
  ('visit_detail_owner', 'visitdetailowner', 'Visit Detail Owner'),
  ('visit_detail_follower', 'visitdetailfollower', 'Visit Detail Follower'),
  ('visit_detail_stranger', 'visitdetailstranger', 'Visit Detail Stranger');
insert into public.follows (follower_user_id, followed_user_id, source)
values ('visit_detail_follower', 'visit_detail_owner', 'profile');
set local role authenticated;
select set_config('request.jwt.claim.sub', 'visit_detail_owner', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

-- Exercise the authenticated save contract. Do not insert or update visit
-- rows directly: the production RPC owns parent/backfill reconciliation.
do $fixture$
declare
  saved jsonb;
  place_payload jsonb := '{"canonical_name":"Visit Detail Fixture","category":"coffee_tea_sweets","primary_category":"coffee_tea_sweets","subcategory":"Coffee shop","category_source":"user","latitude":0,"longitude":0,"source_provider":"test","source_provider_place_id":"visit-detail-fixture","confidence":1}';
  save_payload jsonb := '{"status":"been","visibility":"followers","nearby_confirmed":false,"source_type":"manual"}';
  details jsonb := '[{"question_key":"place_detail_outlets","value_type":"single_choice","value":"None found"},{"question_key":"restaurant_cuisine","value_type":"restaurant_cuisine","value":"Thai"},{"question_key":"custom_question_old","value_type":"text","value":{"kept":true}}]';
begin
  saved := public.save_own_check_in(place_payload, save_payload, details,
    jsonb_build_object('id', 'b4850000-0000-0000-0000-000000000003', 'visited_at', '2026-09-01T12:00:00Z', 'attribute_answers', details), null);
  if nullif(saved->>'user_place_id', '') is null then raise exception 'Fixture save returned no parent'; end if;
  perform set_config('recme.visit_details_parent', saved->>'user_place_id', true);
  perform public.save_own_check_in(place_payload, save_payload, '[]'::jsonb,
    jsonb_build_object('id', 'b4850000-0000-0000-0000-000000000004', 'visited_at', '2026-09-02T12:00:00Z', 'attribute_answers', '[]'::jsonb), null);
end
$fixture$;
select ok((select attribute_answers @> '[{"question_key":"place_detail_outlets","value":"None found"}]'::jsonb
  from public.own_place_visit_details(array[current_setting('recme.visit_details_parent')::uuid]::uuid[])
  where id = 'b4850000-0000-0000-0000-000000000003'), 'owner reads explicit negative answers');
select ok((select attribute_answers @> '[{"question_key":"restaurant_cuisine","value":"Thai"},{"question_key":"custom_question_old","value_type":"text","value":{"kept":true}}]'::jsonb
  from public.own_place_visit_details(array[current_setting('recme.visit_details_parent')::uuid]::uuid[])
  where id = 'b4850000-0000-0000-0000-000000000003'), 'owner retains private and unrecognized historical values');
select is((select attribute_answers from public.own_place_visit_details(array[current_setting('recme.visit_details_parent')::uuid]::uuid[])
  where id = 'b4850000-0000-0000-0000-000000000004'), '[]'::jsonb, 'empty answers are returned explicitly');
select is((select count(*) from public.own_place_visit_details(array[current_setting('recme.visit_details_parent')::uuid,current_setting('recme.visit_details_parent')::uuid]::uuid[])),
  (select count(*) from public.own_place_visit_details(array[current_setting('recme.visit_details_parent')::uuid]::uuid[])), 'parent IDs are deduplicated');
select is((select count(*) from public.own_place_visit_details('{}'::uuid[])), 0::bigint, 'empty scope returns no rows');
select is((select count(*) from public.own_place_visit_details(null::uuid[])), 0::bigint, 'null scope returns no rows');
select is((select count(*) from public.own_place_visit_details(array['b4850000-0000-0000-0000-999999999999']::uuid[])),
  0::bigint, 'unknown parent IDs reveal no data');
select ok((select created_at is not null and updated_at >= created_at
  from public.own_place_visit_details(array[current_setting('recme.visit_details_parent')::uuid])
  where id = 'b4850000-0000-0000-0000-000000000003'), 'source creation and edit timestamps are returned');
select throws_ok($$select * from public.own_place_visit_details(array(select md5(n::text)::uuid from generate_series(1,201) n))$$,
  'P0001', 'too_many_user_place_ids', 'large requests are bounded');
select throws_ok($$select attribute_answers from public.place_visits limit 1$$, '42501', null,
  'owner still cannot read the raw answer column');

select set_config('request.jwt.claim.sub', 'visit_detail_follower', true);
select is((select count(*) from public.own_place_visit_details(array[current_setting('recme.visit_details_parent')::uuid]::uuid[])),
  0::bigint, 'even an authorized follower receives no owner answers');
select set_config('request.jwt.claim.sub', 'visit_detail_stranger', true);
select is((select count(*) from public.own_place_visit_details(array[current_setting('recme.visit_details_parent')::uuid]::uuid[])),
  0::bigint, 'a stranger receives no owner answers');

select set_config('request.jwt.claim.sub', 'visit_detail_owner', true);
select public.delete_own_check_in('b4850000-0000-0000-0000-000000000003'::uuid);
select is((select count(*) from public.own_place_visit_details(array[current_setting('recme.visit_details_parent')::uuid]::uuid[])
  where id = 'b4850000-0000-0000-0000-000000000003'), 0::bigint, 'deleted visits are omitted');
select public.delete_own_user_place(current_setting('recme.visit_details_parent')::uuid);
select is((select count(*) from public.own_place_visit_details(array[current_setting('recme.visit_details_parent')::uuid]::uuid[])),
  0::bigint, 'deleted parent saves are omitted');

reset role;
set local role anon;
select throws_ok($$select * from public.own_place_visit_details('{}'::uuid[])$$, '42501', null, 'anonymous execution is denied');
reset role;
select * from finish();
rollback;
