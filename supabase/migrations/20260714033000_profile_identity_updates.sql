begin;

drop function if exists public.update_own_profile(text, text, text, boolean);
drop function if exists app.update_own_profile(text, text, text, boolean);

create function app.update_own_profile(
  input_bio text default null,
  input_home_area text default null,
  input_default_visibility text default null,
  input_is_private_profile boolean default null,
  input_display_name text default null,
  input_handle text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  normalized_display_name text := nullif(trim(input_display_name), '');
  normalized_handle text := lower(nullif(trim(both '@ ' from input_handle), ''));
  updated_profile public.profiles;
begin
  if viewer_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if input_display_name is not null
     and (normalized_display_name is null or length(normalized_display_name) > 80) then
    raise exception 'invalid_display_name' using errcode = '22023';
  end if;
  if input_handle is not null
     and (normalized_handle is null or normalized_handle !~ '^[a-z0-9_]{2,39}$') then
    raise exception 'invalid_handle' using errcode = '22023';
  end if;
  if normalized_handle is not null and exists (
    select 1
    from public.profiles p
    where p.search_handle = normalized_handle
      and p.id <> viewer_id
      and p.deleted_at is null
  ) then
    raise exception 'handle_taken' using errcode = '23505';
  end if;
  if length(coalesce(input_bio, '')) > 300 then
    raise exception 'bio_too_long' using errcode = '22023';
  end if;
  if length(coalesce(input_home_area, '')) > 120 then
    raise exception 'home_area_too_long' using errcode = '22023';
  end if;
  if input_default_visibility is not null
     and input_default_visibility not in ('followers', 'mutuals', 'self') then
    raise exception 'invalid_default_visibility' using errcode = '22023';
  end if;

  update public.profiles
  set display_name = case when input_display_name is null then display_name else normalized_display_name end,
      handle = case when input_handle is null then handle else normalized_handle end,
      bio = case when input_bio is null then bio else nullif(trim(input_bio), '') end,
      home_area = case when input_home_area is null then home_area else nullif(trim(input_home_area), '') end,
      default_visibility = coalesce(input_default_visibility, default_visibility),
      is_private_profile = coalesce(input_is_private_profile, is_private_profile),
      updated_at = now()
  where id = viewer_id and deleted_at is null
  returning * into updated_profile;

  if updated_profile.id is null then
    raise exception 'profile_not_found' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'id', updated_profile.id,
    'handle', updated_profile.handle,
    'display_name', updated_profile.display_name,
    'avatar_url', updated_profile.avatar_url,
    'bio', updated_profile.bio,
    'home_area', updated_profile.home_area,
    'default_visibility', updated_profile.default_visibility,
    'is_private_profile', updated_profile.is_private_profile,
    'created_at', updated_profile.created_at
  );
end;
$$;

create function public.update_own_profile(
  input_bio text default null,
  input_home_area text default null,
  input_default_visibility text default null,
  input_is_private_profile boolean default null,
  input_display_name text default null,
  input_handle text default null
)
returns jsonb
language sql
security invoker
set search_path = app, public
as $$
  select app.update_own_profile(
    input_bio,
    input_home_area,
    input_default_visibility,
    input_is_private_profile,
    input_display_name,
    input_handle
  );
$$;

create or replace function app.mirror_clerk_profile(
  event_id text, event_type text, event_timestamp timestamptz, profile_id text,
  desired_handle text, desired_display_name text, desired_avatar_url text
)
returns jsonb
language plpgsql
security definer
set search_path = public, app
as $$
declare existing_profile public.profiles; existing_state public.clerk_profile_mirror_state; allocated_handle text;
begin
  if event_id is null or event_id = '' then raise exception 'missing_event_id'; end if;
  if profile_id is null or profile_id = '' then raise exception 'missing_profile_id'; end if;
  insert into public.clerk_webhook_events(svix_id, event_type, clerk_user_id, event_timestamp)
  values (event_id, event_type, profile_id, event_timestamp) on conflict (svix_id) do nothing;
  if not found then return jsonb_build_object('action', 'duplicate_ignored', 'profile_id', profile_id); end if;
  select * into existing_state from public.clerk_profile_mirror_state
  where clerk_user_id = profile_id for update;
  if existing_state.clerk_user_id is not null and event_timestamp < existing_state.last_event_timestamp then
    return jsonb_build_object('action', 'stale_ignored', 'profile_id', profile_id);
  end if;
  insert into public.clerk_profile_mirror_state(clerk_user_id, last_event_id, last_event_type, last_event_timestamp)
  values (profile_id, event_id, event_type, event_timestamp)
  on conflict (clerk_user_id) do update set last_event_id = excluded.last_event_id,
    last_event_type = excluded.last_event_type, last_event_timestamp = excluded.last_event_timestamp,
    updated_at = now();
  select * into existing_profile from public.profiles where id = profile_id for update;
  if event_type = 'user.deleted' then
    delete from public.profiles where id = profile_id;
    return jsonb_build_object('action', 'hard_deleted', 'profile_id', profile_id);
  end if;
  if event_type not in ('user.created', 'user.updated') then
    return jsonb_build_object('action', 'ignored', 'profile_id', profile_id, 'event_type', event_type);
  end if;
  allocated_handle := case
    when existing_profile.id is not null and existing_profile.deleted_at is null then existing_profile.handle
    else app.available_profile_handle(desired_handle, profile_id)
  end;
  insert into public.profiles(id, handle, display_name, avatar_url, avatar_url_source,
    avatar_storage_path, deleted_at, clerk_updated_at, last_clerk_event_id)
  values (profile_id, allocated_handle, coalesce(nullif(desired_display_name, ''), allocated_handle),
    desired_avatar_url, 'clerk', null, null, event_timestamp, event_id)
  on conflict (id) do update set handle = public.profiles.handle, display_name = public.profiles.display_name,
    avatar_url = case when public.profiles.avatar_url_source = 'app' then public.profiles.avatar_url else excluded.avatar_url end,
    avatar_url_source = case when public.profiles.avatar_url_source = 'app' then public.profiles.avatar_url_source else excluded.avatar_url_source end,
    avatar_storage_path = case when public.profiles.avatar_url_source = 'app' then public.profiles.avatar_storage_path else null end,
    deleted_at = null, clerk_updated_at = excluded.clerk_updated_at,
    last_clerk_event_id = excluded.last_clerk_event_id, updated_at = now();
  return jsonb_build_object('action', 'upserted', 'profile_id', profile_id, 'handle', allocated_handle);
end;
$$;

revoke all on function app.update_own_profile(text, text, text, boolean, text, text) from public, anon;
revoke all on function public.update_own_profile(text, text, text, boolean, text, text) from public, anon;
grant execute on function app.update_own_profile(text, text, text, boolean, text, text) to authenticated;
grant execute on function public.update_own_profile(text, text, text, boolean, text, text) to authenticated;

revoke all on function app.mirror_clerk_profile(text, text, timestamptz, text, text, text, text) from public, anon, authenticated;
grant execute on function app.mirror_clerk_profile(text, text, timestamptz, text, text, text, text) to service_role;

comment on function public.update_own_profile(text, text, text, boolean, text, text) is
  'Updates editable profile identity, details, and privacy defaults for the authenticated caller only.';

commit;
