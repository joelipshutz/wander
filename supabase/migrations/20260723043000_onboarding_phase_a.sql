begin;

alter table public.profiles
  add column if not exists onboarding_completed_at timestamptz;

-- Everyone who already had a profile before this feature is considered
-- onboarded. New Clerk-webhook and app-created profiles keep the null default.
update public.profiles
set onboarding_completed_at = coalesce(onboarding_completed_at, now())
where deleted_at is null;

drop function if exists public.current_profile();
drop function if exists app.current_profile();

create function app.current_profile()
returns table (
  id text,
  handle text,
  display_name text,
  avatar_url text,
  bio text,
  home_area text,
  default_visibility text,
  is_private_profile boolean,
  onboarding_completed_at timestamptz,
  created_at timestamptz
)
language sql
stable
security invoker
set search_path = public, app
as $$
  select
    profile.id,
    profile.handle,
    profile.display_name,
    profile.avatar_url,
    profile.bio,
    profile.home_area,
    profile.default_visibility,
    profile.is_private_profile,
    profile.onboarding_completed_at,
    profile.created_at
  from public.profiles profile
  where profile.id = app.current_user_id()
    and profile.deleted_at is null
$$;

create function public.current_profile()
returns table (
  id text,
  handle text,
  display_name text,
  avatar_url text,
  bio text,
  home_area text,
  default_visibility text,
  is_private_profile boolean,
  onboarding_completed_at timestamptz,
  created_at timestamptz
)
language sql
stable
security invoker
set search_path = app, public
as $$
  select * from app.current_profile()
$$;

drop function if exists public.update_own_profile(text, text, text, boolean, text, text);
drop function if exists app.update_own_profile(text, text, text, boolean, text, text);

create function app.update_own_profile(
  input_bio text default null,
  input_home_area text default null,
  input_default_visibility text default null,
  input_is_private_profile boolean default null,
  input_display_name text default null,
  input_handle text default null,
  input_mark_onboarding_complete boolean default false
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
  existing_profile public.profiles;
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
    from public.profiles profile
    where profile.search_handle = normalized_handle
      and profile.id <> viewer_id
      and profile.deleted_at is null
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

  select * into existing_profile
  from public.profiles
  where id = viewer_id and deleted_at is null;

  if existing_profile.id is null then
    if normalized_display_name is null or normalized_handle is null then
      raise exception 'profile_not_found' using errcode = 'P0002';
    end if;

    -- The Clerk webhook may win this insert race. ON CONFLICT retains app-owned
    -- identity while still completing the caller's requested update.
    insert into public.profiles (
      id, handle, display_name, bio, home_area, default_visibility,
      is_private_profile, onboarding_completed_at
    ) values (
      viewer_id,
      normalized_handle,
      normalized_display_name,
      nullif(trim(input_bio), ''),
      nullif(trim(input_home_area), ''),
      coalesce(input_default_visibility, 'followers'),
      coalesce(input_is_private_profile, false),
      case when input_mark_onboarding_complete then now() else null end
    )
    on conflict (id) do update set
      display_name = normalized_display_name,
      handle = normalized_handle,
      bio = case when input_bio is null then public.profiles.bio else nullif(trim(input_bio), '') end,
      home_area = case when input_home_area is null then public.profiles.home_area else nullif(trim(input_home_area), '') end,
      default_visibility = coalesce(input_default_visibility, public.profiles.default_visibility),
      is_private_profile = coalesce(input_is_private_profile, public.profiles.is_private_profile),
      onboarding_completed_at = case
        when input_mark_onboarding_complete then coalesce(public.profiles.onboarding_completed_at, now())
        else public.profiles.onboarding_completed_at
      end,
      deleted_at = null,
      updated_at = now()
    returning * into updated_profile;
  else
    update public.profiles
    set display_name = case when input_display_name is null then display_name else normalized_display_name end,
        handle = case when input_handle is null then handle else normalized_handle end,
        bio = case when input_bio is null then bio else nullif(trim(input_bio), '') end,
        home_area = case when input_home_area is null then home_area else nullif(trim(input_home_area), '') end,
        default_visibility = coalesce(input_default_visibility, default_visibility),
        is_private_profile = coalesce(input_is_private_profile, is_private_profile),
        onboarding_completed_at = case
          when input_mark_onboarding_complete then coalesce(onboarding_completed_at, now())
          else onboarding_completed_at
        end,
        updated_at = now()
    where id = viewer_id and deleted_at is null
    returning * into updated_profile;
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
    'onboarding_completed_at', updated_profile.onboarding_completed_at,
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
  input_handle text default null,
  input_mark_onboarding_complete boolean default false
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
    input_handle,
    input_mark_onboarding_complete
  )
$$;

create function app.profile_handle_available(input_handle text)
returns boolean
language plpgsql
stable
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  normalized_handle text := lower(nullif(trim(both '@ ' from input_handle), ''));
begin
  if viewer_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if normalized_handle is null or normalized_handle !~ '^[a-z0-9_]{2,39}$' then
    return false;
  end if;
  return not exists (
    select 1 from public.profiles profile
    where profile.search_handle = normalized_handle
      and profile.id <> viewer_id
      and profile.deleted_at is null
  );
end;
$$;

create function public.profile_handle_available(input_handle text)
returns boolean
language sql
stable
security invoker
set search_path = app, public
as $$
  select app.profile_handle_available(input_handle)
$$;

revoke all on function app.current_profile() from public, anon;
revoke all on function public.current_profile() from public, anon;
revoke all on function app.update_own_profile(text, text, text, boolean, text, text, boolean) from public, anon;
revoke all on function public.update_own_profile(text, text, text, boolean, text, text, boolean) from public, anon;
revoke all on function app.profile_handle_available(text) from public, anon;
revoke all on function public.profile_handle_available(text) from public, anon;

grant execute on function app.current_profile() to authenticated;
grant execute on function public.current_profile() to authenticated;
grant execute on function app.update_own_profile(text, text, text, boolean, text, text, boolean) to authenticated;
grant execute on function public.update_own_profile(text, text, text, boolean, text, text, boolean) to authenticated;
grant execute on function app.profile_handle_available(text) to authenticated;
grant execute on function public.profile_handle_available(text) to authenticated;

comment on column public.profiles.onboarding_completed_at is
  'Server-authoritative timestamp set after the member finishes or skips Phase A onboarding.';
comment on function public.update_own_profile(text, text, text, boolean, text, text, boolean) is
  'Atomically provisions or updates the authenticated caller profile and can mark onboarding complete.';
comment on function public.profile_handle_available(text) is
  'Returns only whether a normalized handle is available to the authenticated caller.';

commit;
