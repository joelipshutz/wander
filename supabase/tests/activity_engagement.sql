begin;

create extension if not exists pgtap;

select plan(40);

select has_table('public', 'activity_likes', 'activity likes table exists');
select has_table('public', 'activity_comments', 'activity comments table exists');

select is(
  (select relrowsecurity from pg_class where oid = 'public.activity_likes'::regclass),
  true,
  'activity likes enforce RLS'
);
select is(
  (select relrowsecurity from pg_class where oid = 'public.activity_comments'::regclass),
  true,
  'activity comments enforce RLS'
);
select ok(
  not has_table_privilege('authenticated', 'public.activity_likes', 'select'),
  'authenticated cannot read likes directly'
);
select ok(
  not has_table_privilege('authenticated', 'public.activity_comments', 'select'),
  'authenticated cannot read comments directly'
);
select has_pk('public', 'activity_likes', 'activity likes have a composite primary key');
select col_has_check(
  'public',
  'activity_comments',
  'body',
  'activity comment bodies are constrained'
);

select is(
  (select prosecdef from pg_proc where oid = 'app.can_read_activity_event(text,uuid)'::regprocedure),
  true,
  'activity visibility helper is security definer'
);
select ok(
  (
    select 'search_path=pg_catalog, public, app' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'app.can_read_activity_event(text,uuid)'::regprocedure
  ),
  'activity visibility helper pins search_path'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'app.can_read_activity_event(text,uuid)',
    'execute'
  ),
  'authenticated cannot call the visibility helper directly'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'app.activity_engagement_json(text,uuid)',
    'execute'
  ),
  'authenticated cannot call the engagement helper directly'
);

select has_function('public', 'activity_engagement_summaries', array['uuid[]']);
select has_function('public', 'place_activity_engagement_summaries', array['uuid[]']);
select has_function('public', 'set_activity_like', array['uuid', 'boolean']);
select has_function('public', 'activity_comments', array['uuid', 'text', 'integer']);
select has_function('public', 'add_activity_comment', array['uuid', 'text']);

select ok(
  (
    select bool_and(prosecdef)
    from pg_proc
    where oid in (
      'public.activity_engagement_summaries(uuid[])'::regprocedure,
      'public.place_activity_engagement_summaries(uuid[])'::regprocedure,
      'public.set_activity_like(uuid,boolean)'::regprocedure,
      'public.activity_comments(uuid,text,integer)'::regprocedure,
      'public.add_activity_comment(uuid,text)'::regprocedure
    )
  ),
  'all public activity RPCs are security definer'
);
select ok(
  (
    select bool_and('search_path=pg_catalog, public, app' = any(coalesce(proconfig, array[]::text[])))
    from pg_proc
    where oid in (
      'public.activity_engagement_summaries(uuid[])'::regprocedure,
      'public.place_activity_engagement_summaries(uuid[])'::regprocedure,
      'public.set_activity_like(uuid,boolean)'::regprocedure,
      'public.activity_comments(uuid,text,integer)'::regprocedure,
      'public.add_activity_comment(uuid,text)'::regprocedure
    )
  ),
  'all public activity RPCs pin search_path'
);
select ok(
  has_function_privilege('authenticated', 'public.activity_engagement_summaries(uuid[])', 'execute')
    and has_function_privilege('authenticated', 'public.place_activity_engagement_summaries(uuid[])', 'execute')
    and has_function_privilege('authenticated', 'public.set_activity_like(uuid,boolean)', 'execute')
    and has_function_privilege('authenticated', 'public.activity_comments(uuid,text,integer)', 'execute')
    and has_function_privilege('authenticated', 'public.add_activity_comment(uuid,text)', 'execute'),
  'authenticated can execute each public activity RPC'
);
select ok(
  not has_function_privilege('anon', 'public.activity_engagement_summaries(uuid[])', 'execute')
    and not has_function_privilege('anon', 'public.place_activity_engagement_summaries(uuid[])', 'execute')
    and not has_function_privilege('anon', 'public.set_activity_like(uuid,boolean)', 'execute')
    and not has_function_privilege('anon', 'public.activity_comments(uuid,text,integer)', 'execute')
    and not has_function_privilege('anon', 'public.add_activity_comment(uuid,text)', 'execute'),
  'anonymous callers cannot execute activity RPCs'
);

insert into public.profiles (id, handle, display_name, is_private_profile)
values
  ('engagement_owner', 'engagementowner', 'Engagement Owner', false),
  ('engagement_viewer', 'engagementviewer', 'Engagement Viewer', false),
  ('engagement_stranger', 'engagementstranger', 'Engagement Stranger', false);

insert into public.follows (follower_user_id, followed_user_id, source)
values ('engagement_viewer', 'engagement_owner', 'profile');

insert into public.places (
  id,
  canonical_name,
  category,
  latitude,
  longitude,
  source_provider,
  source_provider_place_id
)
values (
  'a1000000-0000-0000-0000-000000000001',
  'Engagement Cafe',
  'coffee',
  34.0522,
  -118.2437,
  'mapkit',
  'activity-engagement-cafe'
);

insert into public.user_places (
  id,
  user_id,
  place_id,
  status,
  visibility,
  source_type
)
values (
  'a1100000-0000-0000-0000-000000000001',
  'engagement_owner',
  'a1000000-0000-0000-0000-000000000001',
  'wanna_go',
  'followers',
  'manual'
);

select set_config('request.jwt.claim.sub', 'engagement_viewer', true);

select is(
  jsonb_array_length(
    public.activity_engagement_summaries(
      array[(select id from public.feed_events where user_place_id = 'a1100000-0000-0000-0000-000000000001')]
    )
  ),
  1,
  'a follower receives one visible activity summary'
);
select is(
  (
    public.activity_engagement_summaries(
      array[(select id from public.feed_events where user_place_id = 'a1100000-0000-0000-0000-000000000001')]
    )->0->>'like_count'
  )::integer,
  0,
  'new activity starts with zero likes'
);
select is(
  (
    public.activity_engagement_summaries(
      array[(select id from public.feed_events where user_place_id = 'a1100000-0000-0000-0000-000000000001')]
    )->0->>'comment_count'
  )::integer,
  0,
  'new activity starts with zero comments'
);
select is(
  (
    public.set_activity_like(
      (select id from public.feed_events where user_place_id = 'a1100000-0000-0000-0000-000000000001'),
      true
    )->>'viewer_has_liked'
  )::boolean,
  true,
  'viewer can like a visible activity'
);
select is(
  (
    public.activity_engagement_summaries(
      array[(select id from public.feed_events where user_place_id = 'a1100000-0000-0000-0000-000000000001')]
    )->0->>'like_count'
  )::integer,
  1,
  'visible like count increments'
);
select is(
  (
    public.set_activity_like(
      (select id from public.feed_events where user_place_id = 'a1100000-0000-0000-0000-000000000001'),
      true
    )->>'like_count'
  )::integer,
  1,
  'setting the same like state is idempotent'
);
select is(
  jsonb_array_length(
    public.place_activity_engagement_summaries(
      array['a1100000-0000-0000-0000-000000000001'::uuid]
    )
  ),
  1,
  'place history resolves its activity event'
);
select is(
  public.place_activity_engagement_summaries(
    array['a1100000-0000-0000-0000-000000000001'::uuid]
  )->0->>'user_place_id',
  'a1100000-0000-0000-0000-000000000001',
  'place history returns the source user-place id'
);
select is(
  public.add_activity_comment(
    (select id from public.feed_events where user_place_id = 'a1100000-0000-0000-0000-000000000001'),
    '  Meet me on the patio.  '
  )->'comment'->>'body',
  'Meet me on the patio.',
  'comment write trims surrounding whitespace'
);
select is(
  (
    public.activity_engagement_summaries(
      array[(select id from public.feed_events where user_place_id = 'a1100000-0000-0000-0000-000000000001')]
    )->0->>'comment_count'
  )::integer,
  1,
  'comment count increments'
);
select is(
  public.activity_comments(
    (select id from public.feed_events where user_place_id = 'a1100000-0000-0000-0000-000000000001'),
    null,
    50
  )->'comments'->0->>'body',
  'Meet me on the patio.',
  'comment page returns the posted body'
);
select is(
  (
    public.activity_comments(
      (select id from public.feed_events where user_place_id = 'a1100000-0000-0000-0000-000000000001'),
      null,
      50
    )->'engagement'->>'comment_count'
  )::integer,
  1,
  'comment page returns synchronized engagement'
);
select throws_ok(
  $$
    select public.add_activity_comment(
      (select id from public.feed_events where user_place_id = 'a1100000-0000-0000-0000-000000000001'),
      '   '
    )
  $$,
  'P0001',
  'invalid_comment_body',
  'empty comments are rejected'
);

select set_config('request.jwt.claim.sub', 'engagement_stranger', true);

select is(
  jsonb_array_length(
    public.activity_engagement_summaries(
      array[(select id from public.feed_events where user_place_id = 'a1100000-0000-0000-0000-000000000001')]
    )
  ),
  0,
  'a stranger cannot obtain engagement for follower-visible activity'
);
select throws_ok(
  $$
    select public.set_activity_like(
      (select id from public.feed_events where user_place_id = 'a1100000-0000-0000-0000-000000000001'),
      true
    )
  $$,
  'P0001',
  'activity_not_visible',
  'a stranger cannot like hidden activity'
);
select throws_ok(
  $$
    select public.add_activity_comment(
      (select id from public.feed_events where user_place_id = 'a1100000-0000-0000-0000-000000000001'),
      'Hidden comment'
    )
  $$,
  'P0001',
  'activity_not_visible',
  'a stranger cannot comment on hidden activity'
);

insert into public.blocks (blocker_user_id, blocked_user_id)
values ('engagement_viewer', 'engagement_owner');
select set_config('request.jwt.claim.sub', 'engagement_viewer', true);

select is(
  jsonb_array_length(
    public.activity_engagement_summaries(
      array[(select id from public.feed_events where user_place_id = 'a1100000-0000-0000-0000-000000000001')]
    )
  ),
  0,
  'a block immediately removes engagement summaries'
);
select throws_ok(
  $$
    select public.activity_comments(
      (select id from public.feed_events where user_place_id = 'a1100000-0000-0000-0000-000000000001'),
      null,
      50
    )
  $$,
  'P0001',
  'activity_not_visible',
  'a block immediately closes the comments boundary'
);

delete from public.blocks
where blocker_user_id = 'engagement_viewer'
  and blocked_user_id = 'engagement_owner';

select is(
  (
    public.set_activity_like(
      (select id from public.feed_events where user_place_id = 'a1100000-0000-0000-0000-000000000001'),
      false
    )->>'like_count'
  )::integer,
  0,
  'viewer can remove a like after visibility returns'
);

select * from finish();

rollback;
