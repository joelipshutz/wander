begin;

create extension if not exists pgtap;
set local search_path = public, extensions;

select plan(28);

select has_table(
  'public',
  'place_list_invites',
  'place list invitation hashes have a dedicated table'
);
select has_function('public', 'create_place_list_invite', array['uuid']);
select has_function('public', 'resolve_place_list_invite', array['text']);
select has_function('public', 'accept_place_list_invite', array['text']);
select has_function('public', 'revoke_place_list_invite', array['text']);
select has_function('public', 'public_web_preview', array['text', 'text']);

select ok(
  (
    select bool_and(proc.prosecdef)
    from pg_proc proc
    join pg_namespace namespace on namespace.oid = proc.pronamespace
    where namespace.nspname = 'public'
      and proc.proname = any(array[
        'create_place_list_invite',
        'resolve_place_list_invite',
        'accept_place_list_invite',
        'revoke_place_list_invite',
        'public_web_preview'
      ])
  ),
  'invite and preview RPCs are narrow security-definer boundaries'
);

select ok(
  (
    select bool_and(
      'search_path=public, app, extensions'
        = any(coalesce(proc.proconfig, array[]::text[]))
    )
    from pg_proc proc
    join pg_namespace namespace on namespace.oid = proc.pronamespace
    where namespace.nspname = 'public'
      and proc.proname = any(array[
        'create_place_list_invite',
        'resolve_place_list_invite',
        'accept_place_list_invite',
        'revoke_place_list_invite',
        'public_web_preview'
      ])
  ),
  'invite and preview RPCs pin their search path'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.place_list_invites',
    'select'
  ),
  'authenticated callers cannot enumerate invitation hashes'
);

select ok(
  exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and tablename = 'place_list_invites'
      and indexname = 'place_list_invites_one_open_per_creator_idx'
      and indexdef ilike 'create unique index%'
      and indexdef ilike '%where ((accepted_at is null) and (revoked_at is null))%'
  ),
  'a list owner cannot create concurrent open invitation links'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.create_place_list_invite(uuid)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.resolve_place_list_invite(text)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.accept_place_list_invite(text)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.revoke_place_list_invite(text)',
    'execute'
  ),
  'authenticated app users can use the invitation lifecycle'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.create_place_list_invite(uuid)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.resolve_place_list_invite(text)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.accept_place_list_invite(text)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.revoke_place_list_invite(text)',
    'execute'
  ),
  'anonymous callers cannot create, resolve, accept, or revoke invitations'
);

select ok(
  has_function_privilege(
    'anon',
    'public.public_web_preview(text,text)',
    'execute'
  ),
  'anonymous website requests can use the privacy-filtered preview RPC'
);

insert into public.profiles(
  id,
  handle,
  display_name,
  avatar_url,
  bio,
  home_area,
  default_visibility,
  is_private_profile,
  deleted_at
)
values
  (
    'user_web_link_owner',
    'web_link_owner',
    'Web Link Owner',
    'https://example.com/owner.jpg',
    'Public profile bio',
    'Los Angeles',
    'followers',
    false,
    null
  ),
  (
    'user_web_link_collaborator',
    'web_link_collab',
    'Web Link Collaborator',
    null,
    null,
    null,
    'followers',
    false,
    null
  ),
  (
    'user_web_link_private',
    'web_link_private',
    'Private Link Owner',
    null,
    'Must not appear',
    null,
    'self',
    true,
    null
  )
on conflict (id) do update set
  handle = excluded.handle,
  display_name = excluded.display_name,
  avatar_url = excluded.avatar_url,
  bio = excluded.bio,
  home_area = excluded.home_area,
  default_visibility = excluded.default_visibility,
  is_private_profile = excluded.is_private_profile,
  deleted_at = excluded.deleted_at;

insert into public.places(
  id,
  canonical_name,
  category,
  address,
  locality,
  region,
  country,
  latitude,
  longitude,
  source_provider,
  source_provider_place_id
)
values (
  '7bdfb34e-521e-4bc8-8466-0315adf12a5a',
  'Preview Coffee',
  'coffee',
  '123 Preview Street',
  'Los Angeles',
  'CA',
  'US',
  34.05,
  -118.24,
  'codex_web_link_test',
  'preview-coffee'
)
on conflict (id) do update set
  canonical_name = excluded.canonical_name,
  category = excluded.category,
  address = excluded.address,
  locality = excluded.locality;

insert into public.place_lists(
  id,
  owner_user_id,
  name,
  description,
  visibility,
  deleted_at
)
values
  (
    'fab8d4ce-a09f-41c9-a383-aa6974340e84',
    'user_web_link_owner',
    'Preview weekend',
    'A safe list description',
    'followers',
    null
  ),
  (
    '012096e1-818a-4f19-b0b6-b67f27e52b9c',
    'user_web_link_private',
    'Hidden weekend',
    'Must stay hidden',
    'stealth',
    null
  )
on conflict (id) do update set
  owner_user_id = excluded.owner_user_id,
  name = excluded.name,
  description = excluded.description,
  visibility = excluded.visibility,
  deleted_at = excluded.deleted_at;

create temporary table web_link_tap_invites (
  purpose text primary key,
  token text not null,
  list_id uuid not null
) on commit drop;
grant select, insert, update on table web_link_tap_invites to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_web_link_owner', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

insert into web_link_tap_invites(purpose, token, list_id)
select
  'accept',
  result->>'token',
  (result->>'list_id')::uuid
from public.create_place_list_invite(
  'fab8d4ce-a09f-41c9-a383-aa6974340e84'
) result;

select is(
  (select length(token) from web_link_tap_invites where purpose = 'accept'),
  48,
  'created invitation tokens have 192 bits of entropy'
);

select ok(
  (
    select invite.token_hash <> tap.token
    from public.place_list_invites invite
    join web_link_tap_invites tap on tap.list_id = invite.list_id
    where tap.purpose = 'accept'
      and invite.revoked_at is null
  ),
  'raw invitation tokens are never stored'
);

set local role anon;
select is(
  public.public_web_preview('profile', 'user_web_link_owner')->>'title',
  'Web Link Owner',
  'non-private profile identity can render on the public web'
);
select is(
  public.public_web_preview('profile', 'user_web_link_private')->>'is_available',
  'false',
  'private profiles never render on the public web'
);
select is(
  public.public_web_preview(
    'place',
    '7bdfb34e-521e-4bc8-8466-0315adf12a5a'
  )->>'title',
  'Preview Coffee',
  'venue facts can render without exposing a user save'
);
select is(
  public.public_web_preview(
    'list',
    'fab8d4ce-a09f-41c9-a383-aa6974340e84'
  )->>'is_available',
  'false',
  'direct list URLs stay generic without authenticated visibility'
);
select is(
  (
    select public.public_web_preview('invite', token)->>'title'
    from web_link_tap_invites
    where purpose = 'accept'
  ),
  'Preview weekend',
  'an active unguessable invitation can preview safe list metadata'
);
select ok(
  (
    select not (
      public.public_web_preview('invite', token)
        ?| array['items', 'notes', 'collaborators']
    )
    from web_link_tap_invites
    where purpose = 'accept'
  ),
  'public invitation previews exclude list contents and identities'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_web_link_collaborator', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select is(
  (
    select public.resolve_place_list_invite(token)->>'status'
    from web_link_tap_invites
    where purpose = 'accept'
  ),
  'active',
  'a collaborator can resolve an active invitation'
);
select is(
  (
    select public.resolve_place_list_invite(token)->>'can_accept'
    from web_link_tap_invites
    where purpose = 'accept'
  ),
  'true',
  'a valid collaborator is offered explicit acceptance'
);

select public.accept_place_list_invite(token)
from web_link_tap_invites
where purpose = 'accept';

select ok(
  app.is_place_list_member(
    'fab8d4ce-a09f-41c9-a383-aa6974340e84',
    'user_web_link_collaborator'
  ),
  'accepting an invitation creates list membership'
);
select is(
  (
    select public.accept_place_list_invite(token)::text
    from web_link_tap_invites
    where purpose = 'accept'
  ),
  'fab8d4ce-a09f-41c9-a383-aa6974340e84',
  'the same recipient can safely replay acceptance'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_web_link_owner', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

insert into web_link_tap_invites(purpose, token, list_id)
select
  'existing-collaborator',
  result->>'token',
  (result->>'list_id')::uuid
from public.create_place_list_invite(
  'fab8d4ce-a09f-41c9-a383-aa6974340e84'
) result;

select set_config('request.jwt.claim.sub', 'user_web_link_collaborator', true);
select throws_ok(
  $$
    select public.accept_place_list_invite(token)
    from web_link_tap_invites
    where purpose = 'existing-collaborator'
  $$,
  'P0001',
  'place_list_invite_unavailable',
  'an existing collaborator cannot consume a fresh single-use invitation'
);

set local role anon;
select is(
  (
    select public.public_web_preview('invite', token)->>'is_available'
    from web_link_tap_invites
    where purpose = 'accept'
  ),
  'false',
  'accepted invitation previews stop resolving'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_web_link_private', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$
    select public.create_place_list_invite(
      '012096e1-818a-4f19-b0b6-b67f27e52b9c'
    )
  $$,
  'P0001',
  'place_list_not_found_or_forbidden',
  'private profiles cannot create new collaborative invitations'
);

select * from finish() as result(message);

rollback;
