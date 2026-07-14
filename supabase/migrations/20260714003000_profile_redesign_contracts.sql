begin;

alter table public.profiles
  drop constraint if exists profiles_bio_length,
  drop constraint if exists profiles_home_area_length;

alter table public.profiles
  add column if not exists is_private_profile boolean not null default false,
  add constraint profiles_bio_length check (bio is null or length(bio) <= 300),
  add constraint profiles_home_area_length check (home_area is null or length(home_area) <= 120);

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
  created_at timestamptz
)
language sql
stable
security invoker
set search_path = public, app
as $$
  select p.id, p.handle, p.display_name, p.avatar_url, p.bio, p.home_area,
         p.default_visibility, p.is_private_profile, p.created_at
  from public.profiles p
  where p.id = app.current_user_id() and p.deleted_at is null;
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
  created_at timestamptz
)
language sql
stable
security invoker
set search_path = app, public
as $$ select * from app.current_profile(); $$;

create or replace function app.update_own_profile(
  input_bio text default null,
  input_home_area text default null,
  input_default_visibility text default null,
  input_is_private_profile boolean default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  updated_profile public.profiles;
begin
  if viewer_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
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
  set bio = nullif(trim(input_bio), ''),
      home_area = nullif(trim(input_home_area), ''),
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

create or replace function public.update_own_profile(
  input_bio text default null,
  input_home_area text default null,
  input_default_visibility text default null,
  input_is_private_profile boolean default null
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
    input_is_private_profile
  );
$$;

create table public.profile_mutes (
  muter_user_id text not null references public.profiles(id) on delete cascade,
  muted_user_id text not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (muter_user_id, muted_user_id),
  check (muter_user_id <> muted_user_id)
);

alter table public.profile_mutes enable row level security;

create policy "profile mutes owner select"
  on public.profile_mutes for select to authenticated
  using (muter_user_id = app.current_user_id());
create policy "profile mutes owner insert"
  on public.profile_mutes for insert to authenticated
  with check (muter_user_id = app.current_user_id());
create policy "profile mutes owner delete"
  on public.profile_mutes for delete to authenticated
  using (muter_user_id = app.current_user_id());

create or replace function app.mute_profile(profile_id text)
returns void
language plpgsql
security invoker
set search_path = public, app
as $$
declare viewer_id text := app.current_user_id();
begin
  if viewer_id is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if profile_id is null or profile_id = '' or profile_id = viewer_id then
    raise exception 'invalid_profile_id' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = profile_id and deleted_at is null) then
    raise exception 'profile_not_found' using errcode = 'P0002';
  end if;
  insert into public.profile_mutes(muter_user_id, muted_user_id)
  values (viewer_id, profile_id)
  on conflict do nothing;
end;
$$;

create or replace function app.unmute_profile(profile_id text)
returns void
language sql
security invoker
set search_path = public, app
as $$
  delete from public.profile_mutes
  where muter_user_id = app.current_user_id() and muted_user_id = profile_id;
$$;

create or replace function app.muted_profiles()
returns table (
  id text, handle text, display_name text, avatar_url text,
  bio text, home_area text, relationship text
)
language sql
stable
security invoker
set search_path = public, app
as $$
  select p.id, p.handle, p.display_name, p.avatar_url, p.bio, p.home_area,
         app.viewer_relationship(p.id)
  from public.profile_mutes m
  join public.profiles p on p.id = m.muted_user_id
  where m.muter_user_id = app.current_user_id() and p.deleted_at is null
  order by p.search_handle;
$$;

create or replace function public.mute_profile(profile_id text)
returns void language sql security invoker set search_path = app, public
as $$ select app.mute_profile(profile_id); $$;
create or replace function public.unmute_profile(profile_id text)
returns void language sql security invoker set search_path = app, public
as $$ select app.unmute_profile(profile_id); $$;
create or replace function public.muted_profiles()
returns table (
  id text, handle text, display_name text, avatar_url text,
  bio text, home_area text, relationship text
)
language sql stable security invoker set search_path = app, public
as $$ select * from app.muted_profiles(); $$;

create or replace function app.blocked_profiles()
returns table (
  id text, handle text, display_name text, avatar_url text,
  bio text, home_area text, relationship text
)
language sql
stable
security invoker
set search_path = public, app
as $$
  select p.id, p.handle, p.display_name, p.avatar_url, p.bio, p.home_area,
         'non_follower'::text
  from public.blocks b
  join public.profiles p on p.id = b.blocked_user_id
  where b.blocker_user_id = app.current_user_id() and p.deleted_at is null
  order by p.search_handle;
$$;

create or replace function public.blocked_profiles()
returns table (
  id text, handle text, display_name text, avatar_url text,
  bio text, home_area text, relationship text
)
language sql stable security invoker set search_path = app, public
as $$ select * from app.blocked_profiles(); $$;

drop function if exists public.profile_visible_places(text, text[], text[]);
drop function if exists app.profile_visible_places(text, text[], text[]);

create function app.profile_visible_places(
  profile_id text,
  status_filter text[] default null,
  category_filter text[] default null
)
returns table (
  user_place_id uuid,
  place_id uuid,
  owner_user_id text,
  owner_handle text,
  owner_display_name text,
  owner_avatar_url text,
  canonical_name text,
  category text,
  primary_category text,
  subcategory text,
  category_source text,
  category_confidence double precision,
  raw_provider_type text,
  address text,
  locality text,
  region text,
  country text,
  latitude double precision,
  longitude double precision,
  status text,
  visibility text,
  note text,
  rating_signal text,
  rating_score double precision,
  recommended_score double precision,
  recommended_count integer,
  category_override text,
  subcategory_override text,
  category_override_source text,
  category_override_confidence double precision,
  source_type text,
  attributes jsonb
)
language sql
stable
security invoker
set search_path = public, app
as $$
  with visible_rows as (
    select up.id as user_place_id, p.id as place_id, up.user_id as owner_user_id,
      owner.handle as owner_handle, owner.display_name as owner_display_name,
      owner.avatar_url as owner_avatar_url, p.canonical_name,
      coalesce(up.category_override, p.primary_category, p.category) as effective_category,
      coalesce(p.primary_category, p.category) as primary_category,
      p.subcategory, p.category_source, p.category_confidence, p.raw_provider_type,
      p.address, p.locality, p.region, p.country, p.latitude, p.longitude,
      up.status, up.visibility, up.note, up.rating_signal,
      up.rating_score::double precision as rating_score,
      up.category_override, up.subcategory_override, up.category_override_source,
      up.category_override_confidence, up.source_type, up.updated_at
    from public.user_places up
    join public.places p on p.id = up.place_id
    join public.profiles owner on owner.id = up.user_id
    where up.user_id = profile_id
      and up.deleted_at is null
      and owner.deleted_at is null
      and (status_filter is null or up.status = any(status_filter))
      and (category_filter is null or coalesce(up.category_override, p.primary_category, p.category) = any(category_filter))
  ),
  rating_summary as (
    select up.place_id, round(avg(up.rating_score)::numeric, 1)::double precision as recommended_score,
           count(*)::integer as recommended_count
    from public.user_places up
    where up.deleted_at is null and up.status = 'been' and up.rating_score is not null
      and up.place_id in (select distinct place_id from visible_rows)
    group by up.place_id
  )
  select vr.user_place_id, vr.place_id, vr.owner_user_id, vr.owner_handle,
    vr.owner_display_name, vr.owner_avatar_url, vr.canonical_name,
    vr.effective_category, vr.primary_category, vr.subcategory,
    vr.category_source, vr.category_confidence, vr.raw_provider_type,
    vr.address, vr.locality, vr.region, vr.country, vr.latitude, vr.longitude,
    vr.status, vr.visibility, vr.note, vr.rating_signal, vr.rating_score,
    rs.recommended_score, coalesce(rs.recommended_count, 0),
    vr.category_override, vr.subcategory_override, vr.category_override_source,
    vr.category_override_confidence, vr.source_type,
    coalesce(jsonb_agg(jsonb_build_object(
      'question_definition_id', pa.question_definition_id,
      'question_key', pa.question_key, 'value_type', pa.value_type,
      'value', pa.value, 'prompt', qd.prompt,
      'options', coalesce(qd.options, '[]'::jsonb),
      'is_system', coalesce(qd.is_system, false)
    )) filter (where pa.id is not null), '[]'::jsonb)
  from visible_rows vr
  left join rating_summary rs on rs.place_id = vr.place_id
  left join public.place_attributes pa on pa.user_place_id = vr.user_place_id
  left join public.question_definitions qd on qd.id = pa.question_definition_id
  group by vr.user_place_id, vr.place_id, vr.owner_user_id, vr.owner_handle,
    vr.owner_display_name, vr.owner_avatar_url, vr.canonical_name,
    vr.effective_category, vr.primary_category, vr.subcategory,
    vr.category_source, vr.category_confidence, vr.raw_provider_type,
    vr.address, vr.locality, vr.region, vr.country, vr.latitude, vr.longitude,
    vr.status, vr.visibility, vr.note, vr.rating_signal, vr.rating_score,
    rs.recommended_score, rs.recommended_count, vr.category_override,
    vr.subcategory_override, vr.category_override_source,
    vr.category_override_confidence, vr.source_type, vr.updated_at
  order by vr.updated_at desc;
$$;

create function public.profile_visible_places(
  profile_id text,
  status_filter text[] default null,
  category_filter text[] default null
)
returns table (
  user_place_id uuid, place_id uuid, owner_user_id text, owner_handle text,
  owner_display_name text, owner_avatar_url text, canonical_name text,
  category text, primary_category text, subcategory text, category_source text,
  category_confidence double precision, raw_provider_type text, address text,
  locality text, region text, country text, latitude double precision,
  longitude double precision, status text, visibility text, note text,
  rating_signal text, rating_score double precision, recommended_score double precision,
  recommended_count integer, category_override text, subcategory_override text,
  category_override_source text, category_override_confidence double precision,
  source_type text, attributes jsonb
)
language sql stable security invoker set search_path = app, public
as $$ select * from app.profile_visible_places(profile_id, status_filter, category_filter); $$;

create or replace function app.queue_notification_event(
  input_recipient_user_id text,
  input_actor_user_id text,
  input_notification_type text,
  input_title text,
  input_body text,
  input_deeplink_url text default null,
  input_data jsonb default '{}'::jsonb,
  input_dedupe_key text default null,
  input_not_before timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public, app
as $$
declare recipient_preferences public.notification_preferences; output_event_id uuid;
begin
  if input_recipient_user_id is null or input_recipient_user_id = '' then return null; end if;
  if input_actor_user_id is not null and input_actor_user_id = input_recipient_user_id then return null; end if;
  if input_notification_type not in (
    'followed_you', 'mutual_follow', 'list_collaborator_added', 'list_place_added',
    'place_saved_from_your_map', 'capture_ready', 'followed_activity_digest', 'followed_place_visit'
  ) then raise exception 'invalid_notification_type'; end if;
  if coalesce(jsonb_typeof(coalesce(input_data, '{}'::jsonb)), '') <> 'object' then
    raise exception 'invalid_notification_data';
  end if;
  if not exists (select 1 from public.profiles where id = input_recipient_user_id and deleted_at is null) then return null; end if;
  if input_actor_user_id is not null then
    if not exists (select 1 from public.profiles where id = input_actor_user_id and deleted_at is null) then return null; end if;
    if app.is_blocked(input_recipient_user_id, input_actor_user_id) then return null; end if;
    if exists (
      select 1 from public.profile_mutes
      where muter_user_id = input_recipient_user_id and muted_user_id = input_actor_user_id
    ) then return null; end if;
  end if;
  if not exists (select 1 from public.notification_device_tokens where user_id = input_recipient_user_id and is_active) then return null; end if;
  recipient_preferences := app.ensure_notification_preferences(input_recipient_user_id);
  if not app.notification_type_enabled(recipient_preferences, input_notification_type) then return null; end if;
  if input_dedupe_key is not null then
    select id into output_event_id from public.notification_events
    where dedupe_key = input_dedupe_key and status in ('pending', 'claimed')
    order by created_at desc limit 1;
    if output_event_id is not null then return output_event_id; end if;
  end if;
  insert into public.notification_events(
    recipient_user_id, actor_user_id, notification_type, title, body,
    deeplink_url, data, dedupe_key, not_before
  ) values (
    input_recipient_user_id, input_actor_user_id, input_notification_type,
    left(trim(input_title), 120), left(trim(input_body), 240),
    nullif(trim(coalesce(input_deeplink_url, '')), ''), coalesce(input_data, '{}'::jsonb),
    nullif(trim(coalesce(input_dedupe_key, '')), ''), coalesce(input_not_before, now())
  ) returning id into output_event_id;
  return output_event_id;
end;
$$;

create or replace function app.claim_pending_push_notifications(input_limit integer default 10)
returns jsonb
language plpgsql
security definer
set search_path = public, app
as $$
declare bounded_limit integer := least(greatest(coalesce(input_limit, 10), 1), 100); output_payload jsonb;
begin
  with muted_events as (
    update public.notification_events event
    set status = 'skipped', failed_at = now(), claim_expires_at = null,
        error_message = 'actor_muted'
    where event.status in ('pending', 'claimed') and event.actor_user_id is not null
      and exists (
        select 1 from public.profile_mutes m
        where m.muter_user_id = event.recipient_user_id and m.muted_user_id = event.actor_user_id
      )
    returning event.id
  ), exhausted_claims as (
    update public.notification_events event
    set status = 'failed', failed_at = now(), claim_expires_at = null,
        error_message = coalesce(nullif(event.error_message, ''), 'push_claim_expired_max_attempts')
    where event.status = 'claimed' and event.claim_expires_at <= now()
      and event.attempt_count >= event.max_attempts
    returning event.id
  ), claimable as (
    select event.id from public.notification_events event
    where ((event.status = 'pending' and event.not_before <= now())
      or (event.status = 'claimed' and event.claim_expires_at <= now()))
      and event.attempt_count < event.max_attempts
      and exists (select 1 from public.notification_device_tokens token
        where token.user_id = event.recipient_user_id and token.is_active)
      and not exists (select 1 from public.profile_mutes m
        where m.muter_user_id = event.recipient_user_id and m.muted_user_id = event.actor_user_id)
    order by event.created_at for update skip locked limit bounded_limit
  ), updated as (
    update public.notification_events event
    set status = 'claimed', claimed_at = now(), claim_expires_at = now() + interval '10 minutes',
        attempt_count = event.attempt_count + 1, last_attempted_at = now()
    from claimable where event.id = claimable.id returning event.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'event_id', updated.id, 'recipient_user_id', updated.recipient_user_id,
    'actor_user_id', updated.actor_user_id, 'notification_type', updated.notification_type,
    'title', updated.title, 'body', updated.body, 'deeplink_url', updated.deeplink_url,
    'data', updated.data, 'attempt_count', updated.attempt_count,
    'max_attempts', updated.max_attempts, 'claim_expires_at', updated.claim_expires_at,
    'tokens', coalesce((select jsonb_agg(jsonb_build_object(
      'id', token.id, 'device_token', token.device_token, 'environment', token.environment,
      'app_bundle_id', token.app_bundle_id
    ) order by token.last_seen_at desc) from public.notification_device_tokens token
      where token.user_id = updated.recipient_user_id and token.is_active), '[]'::jsonb)
  ) order by updated.created_at), '[]'::jsonb) into output_payload from updated;
  return output_payload;
end;
$$;

create or replace function app.account_storage_objects(
  profile_id text,
  event_timestamp timestamptz
)
returns table(bucket_id text, object_path text)
language sql
stable
security definer
set search_path = public, app
as $$
  select 'profile-avatars'::text, p.avatar_storage_path
  from public.profiles p
  where p.id = profile_id
    and p.avatar_storage_path is not null
    and not exists (
      select 1 from public.clerk_profile_mirror_state state
      where state.clerk_user_id = profile_id
        and state.last_event_timestamp > event_timestamp
    )
  union all
  select vp.storage_bucket, vp.storage_path
  from public.visit_photos vp
  join public.place_visits pv on pv.id = vp.visit_id
  join public.user_places up on up.id = pv.user_place_id
  where up.user_id = profile_id
    and not exists (
      select 1 from public.clerk_profile_mirror_state state
      where state.clerk_user_id = profile_id
        and state.last_event_timestamp > event_timestamp
    );
$$;

create or replace function public.account_storage_objects(
  profile_id text,
  event_timestamp timestamptz
)
returns table(bucket_id text, object_path text)
language sql stable security definer set search_path = app, public
as $$ select * from app.account_storage_objects(profile_id, event_timestamp); $$;

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
  allocated_handle := app.available_profile_handle(desired_handle, profile_id);
  insert into public.profiles(id, handle, display_name, avatar_url, avatar_url_source,
    avatar_storage_path, deleted_at, clerk_updated_at, last_clerk_event_id)
  values (profile_id, allocated_handle, coalesce(nullif(desired_display_name, ''), allocated_handle),
    desired_avatar_url, 'clerk', null, null, event_timestamp, event_id)
  on conflict (id) do update set handle = allocated_handle, display_name = excluded.display_name,
    avatar_url = case when public.profiles.avatar_url_source = 'app' then public.profiles.avatar_url else excluded.avatar_url end,
    avatar_url_source = case when public.profiles.avatar_url_source = 'app' then public.profiles.avatar_url_source else excluded.avatar_url_source end,
    avatar_storage_path = case when public.profiles.avatar_url_source = 'app' then public.profiles.avatar_storage_path else null end,
    deleted_at = null, clerk_updated_at = excluded.clerk_updated_at,
    last_clerk_event_id = excluded.last_clerk_event_id, updated_at = now();
  return jsonb_build_object('action', 'upserted', 'profile_id', profile_id, 'handle', allocated_handle);
end;
$$;

revoke all on table public.profile_mutes from public, anon;
grant select, insert, delete on table public.profile_mutes to authenticated;

revoke all on function app.current_profile() from public, anon;
revoke all on function public.current_profile() from public, anon;
revoke all on function app.update_own_profile(text, text, text, boolean) from public, anon;
revoke all on function public.update_own_profile(text, text, text, boolean) from public, anon;
revoke all on function app.mute_profile(text) from public, anon;
revoke all on function app.unmute_profile(text) from public, anon;
revoke all on function app.muted_profiles() from public, anon;
revoke all on function public.mute_profile(text) from public, anon;
revoke all on function public.unmute_profile(text) from public, anon;
revoke all on function public.muted_profiles() from public, anon;
revoke all on function app.blocked_profiles() from public, anon;
revoke all on function public.blocked_profiles() from public, anon;
revoke all on function app.profile_visible_places(text, text[], text[]) from public, anon;
revoke all on function public.profile_visible_places(text, text[], text[]) from public, anon;
revoke all on function app.account_storage_objects(text, timestamptz) from public, anon, authenticated;
revoke all on function public.account_storage_objects(text, timestamptz) from public, anon, authenticated;
revoke all on function app.queue_notification_event(text, text, text, text, text, text, jsonb, text, timestamptz) from public, anon, authenticated;
revoke all on function app.claim_pending_push_notifications(integer) from public, anon, authenticated;
revoke all on function app.mirror_clerk_profile(text, text, timestamptz, text, text, text, text) from public, anon, authenticated;

grant execute on function app.current_profile() to authenticated;
grant execute on function public.current_profile() to authenticated;
grant execute on function app.update_own_profile(text, text, text, boolean) to authenticated;
grant execute on function public.update_own_profile(text, text, text, boolean) to authenticated;
grant execute on function app.mute_profile(text) to authenticated;
grant execute on function app.unmute_profile(text) to authenticated;
grant execute on function app.muted_profiles() to authenticated;
grant execute on function public.mute_profile(text) to authenticated;
grant execute on function public.unmute_profile(text) to authenticated;
grant execute on function public.muted_profiles() to authenticated;
grant execute on function app.blocked_profiles() to authenticated;
grant execute on function public.blocked_profiles() to authenticated;
grant execute on function app.profile_visible_places(text, text[], text[]) to authenticated;
grant execute on function public.profile_visible_places(text, text[], text[]) to authenticated;
grant execute on function app.account_storage_objects(text, timestamptz) to service_role;
grant execute on function public.account_storage_objects(text, timestamptz) to service_role;
grant execute on function app.claim_pending_push_notifications(integer) to service_role;
grant execute on function app.mirror_clerk_profile(text, text, timestamptz, text, text, text, text) to service_role;

comment on function public.update_own_profile(text, text, text, boolean) is 'Updates profile details and privacy defaults for the authenticated caller only.';
comment on table public.profile_mutes is 'Owner-private activity and notification suppression; unlike blocks, mutes do not change content visibility.';
comment on function public.account_storage_objects(text, timestamptz) is 'Service-role inventory used before a non-stale Clerk user.deleted hard purge.';

commit;
