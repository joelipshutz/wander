begin;

create extension if not exists pgtap;

select plan(14);

select is(
  app.mirror_clerk_profile(
    'evt_user_a_create',
    'user.created',
    '2026-06-02T20:00:00Z',
    'user_a',
    'joe',
    'Joe A',
    'https://example.com/a.png'
  )->>'action',
  'upserted',
  'created user_a profile'
);

select is(
  (select handle from public.profiles where id = 'user_a'),
  'joe',
  'first user gets requested handle'
);

select is(
  app.mirror_clerk_profile(
    'evt_user_b_create',
    'user.created',
    '2026-06-02T20:01:00Z',
    'user_b',
    'joe',
    'Joe B',
    null
  )->>'action',
  'upserted',
  'created user_b profile with colliding requested handle'
);

select isnt(
  (select handle from public.profiles where id = 'user_b'),
  'joe',
  'colliding user receives a suffixed handle'
);

select is(
  (select count(distinct handle)::int from public.profiles where id in ('user_a', 'user_b')),
  2,
  'profile handles stay unique after collision'
);

select is(
  app.mirror_clerk_profile(
    'evt_user_a_create',
    'user.created',
    '2026-06-02T20:00:00Z',
    'user_a',
    'joe',
    'Joe A',
    'https://example.com/a.png'
  )->>'action',
  'duplicate_ignored',
  'duplicate webhook event is ignored'
);

select is(
  app.mirror_clerk_profile(
    'evt_user_a_delete',
    'user.deleted',
    '2026-06-02T21:00:00Z',
    'user_a',
    null,
    null,
    null
  )->>'action',
  'hard_deleted',
  'delete event permanently deletes profile'
);

select ok(
  not exists (select 1 from public.profiles where id = 'user_a'),
  'profile row is gone after delete event'
);

select is(
  app.mirror_clerk_profile(
    'evt_user_a_stale_update',
    'user.updated',
    '2026-06-02T20:59:00Z',
    'user_a',
    'joe',
    'Stale Joe',
    null
  )->>'action',
  'stale_ignored',
  'stale update after delete is ignored'
);

select ok(
  not exists (select 1 from public.profiles where id = 'user_a'),
  'stale update does not recreate permanently deleted profile'
);

select is(
  app.mirror_clerk_profile(
    'evt_user_c_delete',
    'user.deleted',
    '2026-06-02T21:00:00Z',
    'user_c',
    null,
    null,
    null
  )->>'action',
  'hard_deleted',
  'delete before profile create records mirror state'
);

select is(
  app.mirror_clerk_profile(
    'evt_user_c_stale_create',
    'user.created',
    '2026-06-02T20:00:00Z',
    'user_c',
    'joe',
    'User C',
    null
  )->>'action',
  'stale_ignored',
  'stale create after delete-before-create is ignored'
);

select is(
  public.mirror_clerk_profile(
    'evt_user_d_public_create',
    'user.created',
    '2026-06-02T22:00:00Z',
    'user_d',
    'public_rpc',
    'Public RPC',
    null
  )->>'action',
  'upserted',
  'public PostgREST wrapper mirrors profile events'
);

select is(
  (select handle from public.profiles where id = 'user_d'),
  'public_rpc',
  'public wrapper writes through to profiles'
);

select * from finish();

rollback;
