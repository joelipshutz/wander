begin;

create extension if not exists pgtap;
select no_plan();

-- REC-421: recording a private save and publishing it are separate contracts.
-- Every fixture and authenticated write below rolls back.
insert into public.profiles (id, handle, display_name, is_private_profile)
values
  ('rec421_owner', 'rec421owner', 'Stealth Test Owner', false),
  ('rec421_follower', 'rec421follower', 'Stealth Test Follower', false),
  ('rec421_stranger', 'rec421stranger', 'Stealth Test Stranger', false);
insert into public.follows (follower_user_id, followed_user_id, source)
values ('rec421_follower', 'rec421_owner', 'profile');

create temporary table stealth_saves (user_place_id uuid, place_id uuid);
create temporary table stealth_events (id uuid);
grant all on stealth_saves, stealth_events to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'rec421_owner', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

insert into stealth_saves
select (saved->>'user_place_id')::uuid, (saved->>'place_id')::uuid
from (values ('wanna_go'), ('been')) statuses(status)
cross join lateral public.save_own_place(
  jsonb_build_object(
    'canonical_name', 'Stealth Test ' || status,
    'category', 'coffee_tea_sweets', 'latitude', 34, 'longitude', -118,
    'source_provider', 'mapkit', 'source_provider_place_id', 'rec421-' || status
  ),
  jsonb_build_object('status', status, 'visibility', 'self', 'source_type', 'manual'),
  '[]'::jsonb
) saved;

select is((select count(*)::integer from public.profile_visible_places('rec421_owner')), 2,
  'owner profile retains both stealth Wanna and Been saves');
select is(jsonb_array_length(public.current_user_calendar_snapshot()->'places'), 2,
  'owner activity/calendar snapshot includes stealth saves');

reset role;
insert into stealth_events select id from public.feed_events where actor_user_id = 'rec421_owner';
select is((select count(*)::integer from stealth_events), 2,
  'stealth saves still record their immutable activity events');
select ok(not has_table_privilege('authenticated', 'public.feed_events', 'select'),
  'clients cannot bypass activity authorization through the raw event table');
select ok(not has_function_privilege('anon', 'public.activity_detail(uuid)', 'execute'),
  'anonymous clients cannot read exact activity');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'rec421_owner', true);
select lives_ok(format('select public.activity_detail(%L::uuid)', id),
  'owner can open each stealth activity ticket') from stealth_events;

select set_config('request.jwt.claim.sub', 'rec421_follower', true);
select is((select count(*)::integer from public.profile_visible_places('rec421_owner')), 0,
  'follower cannot see stealth saves in owner profile');
select is(jsonb_array_length(public.followed_feed()->'activity'), 0,
  'follower feed contains no stealth activity');
select is(jsonb_array_length(public.place_activity_engagement_summaries(array(select user_place_id from stealth_saves))), 0,
  'place card activity summaries do not expose stealth saves');
select throws_ok(format('select public.activity_detail(%L::uuid)', id), 'P0001', 'activity_not_visible',
  'follower cannot open a stealth ticket by known ID') from stealth_events;

select set_config('request.jwt.claim.sub', 'rec421_stranger', true);
select is((select count(*)::integer from public.profile_visible_places('rec421_owner')), 0,
  'stranger cannot see stealth saves in owner profile');
select throws_ok(format('select public.activity_detail(%L::uuid)', id), 'P0001', 'activity_not_visible',
  'stranger cannot open a stealth ticket by known ID') from stealth_events;

-- Switching visibility changes access, not history or event identity.
reset role;
update public.user_places set visibility = 'followers' where user_id = 'rec421_owner';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'rec421_follower', true);
select is(jsonb_array_length(public.followed_feed()->'activity'), 2,
  'non-stealth follower activity still works');
select lives_ok(format('select public.activity_detail(%L::uuid)', id),
  'follower can open a shared ticket') from stealth_events;

reset role;
update public.user_places set visibility = 'self' where user_id = 'rec421_owner';
select is((select count(*)::integer from public.feed_events where actor_user_id = 'rec421_owner'), 2,
  'stealth transitions neither erase nor duplicate activity history');
set local role authenticated;
select set_config('request.jwt.claim.sub', 'rec421_follower', true);
select is(jsonb_array_length(public.followed_feed()->'activity'), 0,
  'turning stealth back on removes previously shared feed activity');
select throws_ok(format('select public.activity_detail(%L::uuid)', id), 'P0001', 'activity_not_visible',
  'stealth revokes access to previously shared exact tickets') from stealth_events;
select set_config('request.jwt.claim.sub', 'rec421_owner', true);
select is(jsonb_array_length(public.current_user_calendar_snapshot()->'places'), 2,
  'owner history survives all visibility transitions');

reset role;
do $strict_pgtap$
declare diagnostics text;
begin
  select string_agg(message, E'\n') into diagnostics from finish() as result(message);
  if diagnostics ~ '(failed|planned)' then
    raise exception 'Stealth activity regression failed: %', diagnostics;
  end if;
end;
$strict_pgtap$;

rollback;
