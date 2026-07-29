begin;

-- Canonical getrec.me previews and consent-based collaborative-list invitations.
--
-- Public previews intentionally expose only:
-- - non-private profile identity fields,
-- - venue facts that are not tied to a user's save,
-- - list metadata to the holder of an unguessable active invite token.
-- User notes, visits, visibility-scoped saves, list items, and collaborator
-- identities never cross this anonymous boundary.

create table if not exists public.place_list_invites (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null references public.place_lists(id) on delete cascade,
  created_by_user_id text not null references public.profiles(id) on delete cascade,
  token_hash text not null unique check (token_hash ~ '^[a-f0-9]{64}$'),
  expires_at timestamptz not null,
  accepted_by_user_id text references public.profiles(id) on delete set null,
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (expires_at > created_at),
  check (
    (accepted_at is null and accepted_by_user_id is null)
    or (accepted_at is not null and accepted_by_user_id is not null)
  )
);

create index if not exists place_list_invites_list_idx
  on public.place_list_invites(list_id, created_at desc);

create index if not exists place_list_invites_active_idx
  on public.place_list_invites(list_id, expires_at)
  where accepted_at is null and revoked_at is null;

create unique index if not exists place_list_invites_one_open_per_creator_idx
  on public.place_list_invites(list_id, created_by_user_id)
  where accepted_at is null and revoked_at is null;

drop trigger if exists place_list_invites_set_updated_at on public.place_list_invites;
create trigger place_list_invites_set_updated_at
  before update on public.place_list_invites
  for each row execute function app.set_updated_at();

alter table public.place_list_invites enable row level security;

revoke all on table public.place_list_invites from public, anon, authenticated;

create or replace function public.create_place_list_invite(input_list_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, app, extensions
as $$
declare
  viewer_id text := app.current_user_id();
  invite_token text;
  invite_expiry timestamptz := now() + interval '7 days';
  invite_id uuid;
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;

  perform 1
    from public.place_lists list_row
    join public.profiles owner_profile
      on owner_profile.id = list_row.owner_user_id
    where list_row.id = input_list_id
      and list_row.owner_user_id = viewer_id
      and list_row.deleted_at is null
      and owner_profile.deleted_at is null
      and not owner_profile.is_private_profile
    for update of list_row;

  if not found then
    raise exception 'place_list_not_found_or_forbidden';
  end if;

  -- One active link per owner/list keeps revocation behavior understandable.
  update public.place_list_invites
  set revoked_at = now()
  where list_id = input_list_id
    and created_by_user_id = viewer_id
    and accepted_at is null
    and revoked_at is null;

  invite_token := encode(extensions.gen_random_bytes(24), 'hex');

  insert into public.place_list_invites(
    list_id,
    created_by_user_id,
    token_hash,
    expires_at
  )
  values (
    input_list_id,
    viewer_id,
    encode(extensions.digest(invite_token, 'sha256'), 'hex'),
    invite_expiry
  )
  returning id into invite_id;

  return jsonb_build_object(
    'id', invite_id,
    'list_id', input_list_id,
    'token', invite_token,
    'expires_at', invite_expiry
  );
end;
$$;

create or replace function public.resolve_place_list_invite(input_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, extensions
as $$
declare
  viewer_id text := app.current_user_id();
  normalized_token text := lower(trim(coalesce(input_token, '')));
  result jsonb;
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;
  if normalized_token !~ '^[a-f0-9]{48}$' then
    return jsonb_build_object('status', 'invalid', 'can_accept', false);
  end if;

  select jsonb_build_object(
    'status',
      case
        when invite.revoked_at is not null then 'revoked'
        when invite.expires_at <= now() then 'expired'
        when invite.accepted_at is not null then 'accepted'
        when list_row.deleted_at is not null
          or owner_profile.deleted_at is not null
          or owner_profile.is_private_profile then 'unavailable'
        when app.is_blocked(viewer_id, list_row.owner_user_id) then 'unavailable'
        else 'active'
      end,
    'can_accept',
      invite.revoked_at is null
      and invite.expires_at > now()
      and invite.accepted_at is null
      and list_row.deleted_at is null
      and owner_profile.deleted_at is null
      and not owner_profile.is_private_profile
      and not viewer_profile.is_private_profile
      and list_row.owner_user_id <> viewer_id
      and not app.is_blocked(viewer_id, list_row.owner_user_id)
      and not app.is_place_list_member(list_row.id, viewer_id),
    'list_id', list_row.id,
    'list_name', list_row.name,
    'list_description', list_row.description,
    'owner_user_id', list_row.owner_user_id,
    'owner_handle', owner_profile.handle,
    'owner_display_name', owner_profile.display_name,
    'item_count', (
      select count(*)::integer
      from public.place_list_items item
      where item.list_id = list_row.id
        and item.deleted_at is null
    ),
    'expires_at', invite.expires_at,
    'viewer_is_owner', list_row.owner_user_id = viewer_id,
    'viewer_is_collaborator', app.is_place_list_member(list_row.id, viewer_id)
  )
  into result
  from public.place_list_invites invite
  join public.place_lists list_row on list_row.id = invite.list_id
  join public.profiles owner_profile on owner_profile.id = list_row.owner_user_id
  join public.profiles viewer_profile on viewer_profile.id = viewer_id
  where invite.token_hash = encode(
    extensions.digest(normalized_token, 'sha256'),
    'hex'
  );

  return coalesce(
    result,
    jsonb_build_object('status', 'invalid', 'can_accept', false)
  );
end;
$$;

create or replace function public.accept_place_list_invite(input_token text)
returns uuid
language plpgsql
volatile
security definer
set search_path = public, app, extensions
as $$
declare
  viewer_id text := app.current_user_id();
  normalized_token text := lower(trim(coalesce(input_token, '')));
  invite_row public.place_list_invites%rowtype;
  list_owner_id text;
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;
  if normalized_token !~ '^[a-f0-9]{48}$' then
    raise exception 'invalid_place_list_invite';
  end if;

  select invite.*
  into invite_row
  from public.place_list_invites invite
  where invite.token_hash = encode(
    extensions.digest(normalized_token, 'sha256'),
    'hex'
  )
  for update;

  if invite_row.id is null then
    raise exception 'invalid_place_list_invite';
  end if;
  if invite_row.revoked_at is not null then
    raise exception 'place_list_invite_revoked';
  end if;
  if invite_row.expires_at <= now() then
    raise exception 'place_list_invite_expired';
  end if;
  if invite_row.accepted_at is not null then
    if invite_row.accepted_by_user_id = viewer_id then
      return invite_row.list_id;
    end if;
    raise exception 'place_list_invite_already_accepted';
  end if;

  select list_row.owner_user_id
  into list_owner_id
  from public.place_lists list_row
  join public.profiles owner_profile
    on owner_profile.id = list_row.owner_user_id
  join public.profiles viewer_profile
    on viewer_profile.id = viewer_id
  where list_row.id = invite_row.list_id
    and list_row.deleted_at is null
    and owner_profile.deleted_at is null
    and not owner_profile.is_private_profile
    and viewer_profile.deleted_at is null
    and not viewer_profile.is_private_profile;

  if list_owner_id is null
    or list_owner_id = viewer_id
    or app.is_blocked(viewer_id, list_owner_id)
    or app.is_place_list_member(invite_row.list_id, viewer_id)
  then
    raise exception 'place_list_invite_unavailable';
  end if;

  insert into public.place_list_members(list_id, user_id, role, deleted_at)
  values (invite_row.list_id, viewer_id, 'collaborator', null)
  on conflict (list_id, user_id) do update
    set deleted_at = null,
        role = 'collaborator';

  update public.place_list_invites
  set accepted_by_user_id = viewer_id,
      accepted_at = now()
  where id = invite_row.id;

  update public.place_lists
  set updated_at = now()
  where id = invite_row.list_id;

  return invite_row.list_id;
end;
$$;

create or replace function public.revoke_place_list_invite(input_token text)
returns void
language plpgsql
volatile
security definer
set search_path = public, app, extensions
as $$
declare
  viewer_id text := app.current_user_id();
  normalized_token text := lower(trim(coalesce(input_token, '')));
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;
  if normalized_token !~ '^[a-f0-9]{48}$' then
    raise exception 'invalid_place_list_invite';
  end if;

  update public.place_list_invites invite
  set revoked_at = now()
  from public.place_lists list_row
  where invite.list_id = list_row.id
    and invite.token_hash = encode(
      extensions.digest(normalized_token, 'sha256'),
      'hex'
    )
    and list_row.owner_user_id = viewer_id
    and invite.accepted_at is null
    and invite.revoked_at is null;
end;
$$;

create or replace function public.public_web_preview(
  input_kind text,
  input_identifier text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, extensions
as $$
declare
  normalized_kind text := lower(trim(coalesce(input_kind, '')));
  normalized_identifier text := trim(coalesce(input_identifier, ''));
  result jsonb;
begin
  if normalized_kind not in ('profile', 'place', 'list', 'invite')
    or length(normalized_identifier) not between 1 and 256
  then
    return jsonb_build_object(
      'kind', normalized_kind,
      'is_available', false
    );
  end if;

  if normalized_kind = 'profile' then
    select jsonb_build_object(
      'kind', 'profile',
      'is_available', true,
      'eyebrow', 'Shared profile',
      'title', profile.display_name,
      'subtitle', '@' || profile.handle,
      'description', nullif(profile.bio, ''),
      'image_url', profile.avatar_url
    )
    into result
    from public.profiles profile
    where (
        profile.id = normalized_identifier
        or profile.search_handle = lower(normalized_identifier)
      )
      and profile.deleted_at is null
      and not profile.is_private_profile
    limit 1;

  elsif normalized_kind = 'place'
    and normalized_identifier ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  then
    select jsonb_build_object(
      'kind', 'place',
      'is_available', true,
      'eyebrow', 'Shared place',
      'title', place_row.canonical_name,
      'subtitle', concat_ws(' · ', nullif(place_row.category, ''), nullif(place_row.locality, '')),
      'description', nullif(place_row.address, ''),
      'place_id', place_row.id,
      'category', place_row.category,
      'primary_category', place_row.primary_category,
      'subcategory', place_row.subcategory,
      'category_source', place_row.category_source,
      'category_confidence', place_row.category_confidence,
      'raw_provider_type', place_row.raw_provider_type,
      'address', place_row.address,
      'locality', place_row.locality,
      'region', place_row.region,
      'country', place_row.country,
      'latitude', place_row.latitude,
      'longitude', place_row.longitude,
      'source_provider', place_row.source_provider,
      'source_provider_place_id', place_row.source_provider_place_id,
      'confidence', place_row.confidence
    )
    into result
    from public.places place_row
    where place_row.id = normalized_identifier::uuid;

  elsif normalized_kind = 'invite'
    and lower(normalized_identifier) ~ '^[a-f0-9]{48}$'
  then
    select jsonb_build_object(
      'kind', 'invite',
      'is_available', true,
      'eyebrow', 'List invitation',
      'title', list_row.name,
      'subtitle', 'From ' || owner_profile.display_name || ' · @' || owner_profile.handle,
      'description', nullif(list_row.description, ''),
      'item_count', (
        select count(*)::integer
        from public.place_list_items item
        where item.list_id = list_row.id
          and item.deleted_at is null
      )
    )
    into result
    from public.place_list_invites invite
    join public.place_lists list_row on list_row.id = invite.list_id
    join public.profiles owner_profile on owner_profile.id = list_row.owner_user_id
    where invite.token_hash = encode(
        extensions.digest(lower(normalized_identifier), 'sha256'),
        'hex'
      )
      and invite.accepted_at is null
      and invite.revoked_at is null
      and invite.expires_at > now()
      and list_row.deleted_at is null
      and owner_profile.deleted_at is null
      and not owner_profile.is_private_profile;
  end if;

  -- Direct list URLs are deliberately generic on the web because followers
  -- visibility is authenticated app state, not public-web visibility.
  return coalesce(
    result,
    jsonb_build_object(
      'kind', normalized_kind,
      'is_available', false
    )
  );
end;
$$;

revoke all on function public.create_place_list_invite(uuid)
  from public, anon, authenticated;
revoke all on function public.resolve_place_list_invite(text)
  from public, anon, authenticated;
revoke all on function public.accept_place_list_invite(text)
  from public, anon, authenticated;
revoke all on function public.revoke_place_list_invite(text)
  from public, anon, authenticated;
revoke all on function public.public_web_preview(text, text)
  from public, anon, authenticated;

grant execute on function public.create_place_list_invite(uuid)
  to authenticated;
grant execute on function public.resolve_place_list_invite(text)
  to authenticated;
grant execute on function public.accept_place_list_invite(text)
  to authenticated;
grant execute on function public.revoke_place_list_invite(text)
  to authenticated;
grant execute on function public.public_web_preview(text, text)
  to anon, authenticated;

comment on table public.place_list_invites is
  'Single-use, expiring collaborative-list invitations stored by SHA-256 token hash.';
comment on function public.public_web_preview(text, text) is
  'Privacy-filtered metadata for getrec.me entity previews; never returns user place content.';

commit;
;
