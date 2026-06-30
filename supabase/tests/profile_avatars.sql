begin;

create extension if not exists pgtap;

select plan(27);

select ok(
  exists (
    select 1
    from storage.buckets
    where id = 'profile-avatars'
  ),
  'profile avatar storage bucket exists'
);

select ok(
  (
    select public
    from storage.buckets
    where id = 'profile-avatars'
  ),
  'profile avatar bucket is public for image rendering'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'profile avatars owner insert'
  ),
  'profile avatar bucket has owner insert policy'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'profile avatars owner update'
  ),
  'profile avatar bucket has owner update policy'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'profile avatars owner delete'
  ),
  'profile avatar bucket has owner delete policy'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'profile avatars public read'
  ),
  'profile avatar bucket has public read policy'
);

select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'app.update_profile_avatar(text,text)'::regprocedure
  ),
  false,
  'update_profile_avatar runs as security invoker'
);

select ok(
  (
    select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'app.update_profile_avatar(text,text)'::regprocedure
  ),
  'update_profile_avatar pins search_path to public, app'
);

select ok(
  has_function_privilege('authenticated', 'public.update_profile_avatar(text,text)', 'execute'),
  'authenticated can execute public update_profile_avatar wrapper'
);

select ok(
  not has_function_privilege('anon', 'public.update_profile_avatar(text,text)', 'execute'),
  'anon cannot execute public update_profile_avatar wrapper'
);

select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'app.current_profile()'::regprocedure
  ),
  false,
  'current_profile runs as security invoker'
);

select ok(
  has_function_privilege('authenticated', 'public.current_profile()', 'execute'),
  'authenticated can execute public current_profile wrapper'
);

select ok(
  not has_function_privilege('authenticated', 'app.mirror_clerk_profile(text,text,timestamptz,text,text,text,text)', 'execute'),
  'authenticated cannot execute app mirror_clerk_profile'
);

select ok(
  has_function_privilege('service_role', 'app.mirror_clerk_profile(text,text,timestamptz,text,text,text,text)', 'execute'),
  'service_role can execute app mirror_clerk_profile'
);

insert into public.profiles (id, handle, display_name)
values
  ('user_avatar_owner', 'avatarowner', 'Avatar Owner'),
  ('user_avatar_other', 'avatarother', 'Avatar Other');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_avatar_owner', true);

select is(
  public.update_profile_avatar(
    'https://rugmtlgufrhlxwfkumhw.supabase.co/storage/v1/object/public/profile-avatars/user_avatar_owner/avatar.jpg?v=test',
    'user_avatar_owner/avatar.jpg'
  )->>'avatar_url',
  'https://rugmtlgufrhlxwfkumhw.supabase.co/storage/v1/object/public/profile-avatars/user_avatar_owner/avatar.jpg?v=test',
  'owner can store profile avatar URL'
);

select is(
  (
    select avatar_storage_path
    from public.profiles
    where id = 'user_avatar_owner'
  ),
  'user_avatar_owner/avatar.jpg',
  'owner avatar storage path is recorded'
);

select is(
  (
    select avatar_url_source
    from public.profiles
    where id = 'user_avatar_owner'
  ),
  'app',
  'owner avatar source is marked app'
);

select is(
  (select avatar_url from public.current_profile()),
  'https://rugmtlgufrhlxwfkumhw.supabase.co/storage/v1/object/public/profile-avatars/user_avatar_owner/avatar.jpg?v=test',
  'current_profile returns current owner avatar URL'
);

select throws_ok(
  $$
    select public.update_profile_avatar(
      'https://rugmtlgufrhlxwfkumhw.supabase.co/storage/v1/object/public/profile-avatars/user_avatar_other/avatar.jpg?v=test',
      'user_avatar_other/avatar.jpg'
    )
  $$,
  '42501',
  'invalid_avatar_storage_path',
  'owner cannot store another user profile avatar path'
);

select is(
  public.update_profile_avatar(null, null)->>'avatar_url',
  null::text,
  'owner can clear profile avatar URL'
);

select is(
  (
    select avatar_storage_path
    from public.profiles
    where id = 'user_avatar_owner'
  ),
  null::text,
  'clearing profile avatar clears storage path'
);

select is(
  (
    select avatar_url_source
    from public.profiles
    where id = 'user_avatar_owner'
  ),
  'app',
  'clearing profile avatar keeps app source so Clerk does not rehydrate it'
);

reset role;

select is(
  app.mirror_clerk_profile(
    'evt_avatar_create',
    'user.created',
    '2026-06-28T19:20:00Z',
    'user_clerk_avatar',
    'clerkavatar',
    'Clerk Avatar',
    'https://clerk.example/original.jpg'
  )->>'action',
  'upserted',
  'Clerk can create profile with Clerk avatar URL'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_avatar_owner', true);

select is(
  public.update_profile_avatar(
    'https://rugmtlgufrhlxwfkumhw.supabase.co/storage/v1/object/public/profile-avatars/user_avatar_owner/avatar.jpg?v=app',
    'user_avatar_owner/avatar.jpg'
  )->>'avatar_url',
  'https://rugmtlgufrhlxwfkumhw.supabase.co/storage/v1/object/public/profile-avatars/user_avatar_owner/avatar.jpg?v=app',
  'signed-in profile can set app avatar before Clerk update'
);

reset role;

select is(
  app.mirror_clerk_profile(
    'evt_avatar_update',
    'user.updated',
    '2026-06-28T19:21:00Z',
    'user_avatar_owner',
    'avatarowner',
    'Avatar Owner Updated',
    'https://clerk.example/new.jpg'
  )->>'action',
  'upserted',
  'Clerk update still mirrors non-avatar profile fields'
);

select is(
  (
    select avatar_url
    from public.profiles
    where id = 'user_avatar_owner'
  ),
  'https://rugmtlgufrhlxwfkumhw.supabase.co/storage/v1/object/public/profile-avatars/user_avatar_owner/avatar.jpg?v=app',
  'Clerk update preserves app-selected avatar URL'
);

select is(
  (
    select avatar_url_source
    from public.profiles
    where id = 'user_avatar_owner'
  ),
  'app',
  'Clerk update preserves app avatar source'
);

select * from finish();

rollback;
