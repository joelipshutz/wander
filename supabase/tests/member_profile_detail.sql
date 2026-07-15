begin;

create extension if not exists pgtap;

select plan(10);

select is(
  (select prosecdef from pg_proc where oid = 'app.profile_detail(text)'::regprocedure),
  false,
  'profile detail runs as the authenticated caller'
);

select ok(
  (select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
   from pg_proc where oid = 'app.profile_detail(text)'::regprocedure),
  'app profile detail pins search_path'
);

select ok(
  (select 'search_path=app, public' = any(coalesce(proconfig, array[]::text[]))
   from pg_proc where oid = 'public.profile_detail(text)'::regprocedure),
  'public profile detail pins search_path'
);

select ok(
  has_function_privilege('authenticated', 'public.profile_detail(text)', 'execute'),
  'authenticated can execute profile detail'
);

select ok(
  not has_function_privilege('anon', 'public.profile_detail(text)', 'execute'),
  'anonymous callers cannot execute profile detail'
);

insert into public.profiles (
  id, handle, display_name, bio, home_area, is_private_profile, created_at
)
values
  ('user_member_detail_viewer', 'detailviewer', 'Detail Viewer', null, null, false, '2025-01-01T00:00:00Z'),
  ('user_member_detail_friend', 'detailfriend', 'Detail Friend', 'Trusted picks.', 'Santa Monica', false, '2024-02-03T00:00:00Z'),
  ('user_member_detail_blocked', 'detailblocked', 'Detail Blocked', null, null, false, '2024-03-04T00:00:00Z');

insert into public.follows (follower_user_id, followed_user_id, source)
values
  ('user_member_detail_viewer', 'user_member_detail_friend', 'profile'),
  ('user_member_detail_friend', 'user_member_detail_viewer', 'profile');

insert into public.blocks (blocker_user_id, blocked_user_id)
values ('user_member_detail_blocked', 'user_member_detail_viewer');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_member_detail_viewer', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select is(
  (select display_name from public.profile_detail('user_member_detail_friend')),
  'Detail Friend',
  'viewer can load a visible member profile'
);

select is(
  (select home_area from public.profile_detail('user_member_detail_friend')),
  'Santa Monica',
  'profile detail returns home area'
);

select is(
  (select created_at from public.profile_detail('user_member_detail_friend')),
  '2024-02-03T00:00:00Z'::timestamptz,
  'profile detail returns the persistent membership date'
);

select is(
  (select relationship from public.profile_detail('user_member_detail_friend')),
  'mutual',
  'profile detail returns viewer-relative relationship'
);

select is(
  (select count(*)::integer from public.profile_detail('user_member_detail_blocked')),
  0,
  'profile RLS hides a member who blocked the viewer'
);

select * from finish();

rollback;
