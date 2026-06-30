begin;

alter table public.profiles
  add column if not exists avatar_url_source text not null default 'clerk'
    check (avatar_url_source in ('clerk', 'app')),
  add column if not exists avatar_storage_path text;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'profile-avatars',
  'profile-avatars',
  true,
  524288,
  array['image/jpeg']::text[]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "profile avatars public read" on storage.objects;
drop policy if exists "profile avatars owner insert" on storage.objects;
drop policy if exists "profile avatars owner update" on storage.objects;
drop policy if exists "profile avatars owner delete" on storage.objects;

create policy "profile avatars public read"
  on storage.objects for select
  to public
  using (bucket_id = 'profile-avatars');

create policy "profile avatars owner insert"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'profile-avatars'
    and (storage.foldername(name))[1] = app.current_user_id()
  );

create policy "profile avatars owner update"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'profile-avatars'
    and (storage.foldername(name))[1] = app.current_user_id()
  )
  with check (
    bucket_id = 'profile-avatars'
    and (storage.foldername(name))[1] = app.current_user_id()
  );

create policy "profile avatars owner delete"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'profile-avatars'
    and (storage.foldername(name))[1] = app.current_user_id()
  );

create or replace function app.update_profile_avatar(
  avatar_url text default null,
  storage_path text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public, app
as $$
declare
  current_profile public.profiles;
  current_user text := app.current_user_id();
  trimmed_avatar_url text := nullif(trim(avatar_url), '');
  trimmed_storage_path text := nullif(trim(storage_path), '');
  avatar_url_prefix constant text := 'https://rugmtlgufrhlxwfkumhw.supabase.co/storage/v1/object/public/profile-avatars/';
begin
  if current_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if (trimmed_avatar_url is null) <> (trimmed_storage_path is null) then
    raise exception 'avatar_url_and_storage_path_must_match' using errcode = '22023';
  end if;

  if trimmed_storage_path is not null
    and trimmed_storage_path <> current_user || '/avatar.jpg' then
    raise exception 'invalid_avatar_storage_path' using errcode = '42501';
  end if;

  if trimmed_avatar_url is not null
    and left(trimmed_avatar_url, length(avatar_url_prefix || trimmed_storage_path)) <> avatar_url_prefix || trimmed_storage_path then
    raise exception 'invalid_avatar_url' using errcode = '22023';
  end if;

  update public.profiles
  set
    avatar_url = trimmed_avatar_url,
    avatar_storage_path = trimmed_storage_path,
    avatar_url_source = 'app',
    updated_at = now()
  where id = current_user
    and deleted_at is null
  returning *
  into current_profile;

  if current_profile.id is null then
    raise exception 'profile_not_found' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'avatar_url', current_profile.avatar_url,
    'avatar_storage_path', current_profile.avatar_storage_path
  );
end;
$$;

create or replace function public.update_profile_avatar(
  avatar_url text default null,
  storage_path text default null
)
returns jsonb
language sql
security invoker
set search_path = app, public
as $$
  select app.update_profile_avatar(avatar_url, storage_path);
$$;

comment on function public.update_profile_avatar(text, text) is
  'Updates the authenticated caller profile avatar URL after Storage upload, or clears it after delete.';

revoke all on function app.update_profile_avatar(text, text) from public, anon;
revoke all on function public.update_profile_avatar(text, text) from public, anon;

grant execute on function app.update_profile_avatar(text, text) to authenticated;
grant execute on function public.update_profile_avatar(text, text) to authenticated;

create or replace function app.current_profile()
returns table (
  id text,
  handle text,
  display_name text,
  avatar_url text,
  bio text,
  home_area text,
  default_visibility text
)
language sql
stable
security invoker
set search_path = public, app
as $$
  select
    p.id,
    p.handle,
    p.display_name,
    p.avatar_url,
    p.bio,
    p.home_area,
    p.default_visibility
  from public.profiles p
  where p.id = app.current_user_id()
    and p.deleted_at is null;
$$;

create or replace function public.current_profile()
returns table (
  id text,
  handle text,
  display_name text,
  avatar_url text,
  bio text,
  home_area text,
  default_visibility text
)
language sql
stable
security invoker
set search_path = app, public
as $$
  select *
  from app.current_profile();
$$;

comment on function public.current_profile() is
  'Returns the authenticated caller profile shell for app startup hydration.';

revoke all on function app.current_profile() from public, anon;
revoke all on function public.current_profile() from public, anon;

grant execute on function app.current_profile() to authenticated;
grant execute on function public.current_profile() to authenticated;

create or replace function app.mirror_clerk_profile(
  event_id text,
  event_type text,
  event_timestamp timestamptz,
  profile_id text,
  desired_handle text,
  desired_display_name text,
  desired_avatar_url text
)
returns jsonb
language plpgsql
security definer
set search_path = public, app
as $$
declare
  existing_profile public.profiles;
  existing_state public.clerk_profile_mirror_state;
  allocated_handle text;
begin
  if event_id is null or event_id = '' then
    raise exception 'missing_event_id';
  end if;

  if profile_id is null or profile_id = '' then
    raise exception 'missing_profile_id';
  end if;

  insert into public.clerk_webhook_events (svix_id, event_type, clerk_user_id, event_timestamp)
  values (event_id, event_type, profile_id, event_timestamp)
  on conflict (svix_id) do nothing;

  if not found then
    return jsonb_build_object('action', 'duplicate_ignored', 'profile_id', profile_id);
  end if;

  select *
  into existing_state
  from public.clerk_profile_mirror_state s
  where s.clerk_user_id = profile_id
  for update;

  if existing_state.clerk_user_id is not null
    and event_timestamp < existing_state.last_event_timestamp then
    return jsonb_build_object('action', 'stale_ignored', 'profile_id', profile_id);
  end if;

  insert into public.clerk_profile_mirror_state (
    clerk_user_id,
    last_event_id,
    last_event_type,
    last_event_timestamp
  )
  values (
    profile_id,
    event_id,
    event_type,
    event_timestamp
  )
  on conflict (clerk_user_id) do update set
    last_event_id = excluded.last_event_id,
    last_event_type = excluded.last_event_type,
    last_event_timestamp = excluded.last_event_timestamp,
    updated_at = now();

  select *
  into existing_profile
  from public.profiles p
  where p.id = profile_id
  for update;

  if event_type = 'user.deleted' then
    update public.profiles
    set
      deleted_at = coalesce(deleted_at, now()),
      clerk_updated_at = event_timestamp,
      last_clerk_event_id = event_id,
      updated_at = now()
    where id = profile_id;

    return jsonb_build_object('action', 'soft_deleted', 'profile_id', profile_id);
  end if;

  if event_type not in ('user.created', 'user.updated') then
    return jsonb_build_object('action', 'ignored', 'profile_id', profile_id, 'event_type', event_type);
  end if;

  allocated_handle := case
    when existing_profile.id is not null and existing_profile.deleted_at is null then existing_profile.handle
    else app.available_profile_handle(desired_handle, profile_id)
  end;

  insert into public.profiles (
    id,
    handle,
    display_name,
    avatar_url,
    avatar_url_source,
    avatar_storage_path,
    deleted_at,
    clerk_updated_at,
    last_clerk_event_id
  )
  values (
    profile_id,
    allocated_handle,
    coalesce(nullif(desired_display_name, ''), allocated_handle),
    desired_avatar_url,
    'clerk',
    null,
    null,
    event_timestamp,
    event_id
  )
  on conflict (id) do update set
    handle = allocated_handle,
    display_name = excluded.display_name,
    avatar_url = case
      when public.profiles.avatar_url_source = 'app' then public.profiles.avatar_url
      else excluded.avatar_url
    end,
    avatar_url_source = case
      when public.profiles.avatar_url_source = 'app' then public.profiles.avatar_url_source
      else excluded.avatar_url_source
    end,
    avatar_storage_path = case
      when public.profiles.avatar_url_source = 'app' then public.profiles.avatar_storage_path
      else null
    end,
    deleted_at = null,
    clerk_updated_at = excluded.clerk_updated_at,
    last_clerk_event_id = excluded.last_clerk_event_id,
    updated_at = now();

  return jsonb_build_object('action', 'upserted', 'profile_id', profile_id, 'handle', allocated_handle);
end;
$$;

revoke all on function app.mirror_clerk_profile(text, text, timestamptz, text, text, text, text) from public, anon, authenticated;
grant execute on function app.mirror_clerk_profile(text, text, timestamptz, text, text, text, text) to service_role;

drop function if exists public.visible_places_in_view(double precision, double precision, double precision, double precision, text[], text[], text[]);
drop function if exists public.profile_visible_places(text, text[], text[]);
drop function if exists app.visible_places_in_view(double precision, double precision, double precision, double precision, text[], text[], text[]);
drop function if exists app.profile_visible_places(text, text[], text[]);

create or replace function app.visible_places_in_view(
  min_lat double precision,
  min_lng double precision,
  max_lat double precision,
  max_lng double precision,
  status_filter text[] default null,
  category_filter text[] default null,
  owner_scope text[] default null
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
  latitude double precision,
  longitude double precision,
  status text,
  visibility text,
  note text,
  rating_signal text,
  rating_score integer,
  recommended_score double precision,
  recommended_count integer,
  source_type text,
  attributes jsonb
)
language sql
stable
security invoker
as $$
  with visible_rows as (
    select
      up.id as user_place_id,
      p.id as place_id,
      up.user_id as owner_user_id,
      owner.handle as owner_handle,
      owner.display_name as owner_display_name,
      owner.avatar_url as owner_avatar_url,
      p.canonical_name,
      p.category,
      p.latitude,
      p.longitude,
      up.status,
      up.visibility,
      up.note,
      up.rating_signal,
      up.rating_score::integer as rating_score,
      up.source_type
    from public.user_places up
    join public.places p on p.id = up.place_id
    join public.profiles owner on owner.id = up.user_id
    where up.deleted_at is null
      and p.latitude between min_lat and max_lat
      and p.longitude between min_lng and max_lng
      and (status_filter is null or up.status = any(status_filter))
      and (category_filter is null or p.category = any(category_filter))
      and (
        owner_scope is null
        or ('you' = any(owner_scope) and up.user_id = app.current_user_id())
        or ('following' = any(owner_scope) and up.user_id <> app.current_user_id() and app.follows(app.current_user_id(), up.user_id))
        or ('friends' = any(owner_scope) and up.user_id <> app.current_user_id() and app.is_mutual(app.current_user_id(), up.user_id))
        or ('social' = any(owner_scope) and up.user_id <> app.current_user_id())
      )
  ),
  visible_rating_rows as (
    select up.place_id, up.rating_score
    from public.user_places up
    where up.deleted_at is null
      and up.status = 'been'
      and up.rating_score is not null
      and up.place_id in (select distinct place_id from visible_rows)
  ),
  rating_summary as (
    select
      place_id,
      round(avg(rating_score)::numeric, 1)::double precision as recommended_score,
      count(*)::integer as recommended_count
    from visible_rating_rows
    group by place_id
  )
  select
    vr.user_place_id,
    vr.place_id,
    vr.owner_user_id,
    vr.owner_handle,
    vr.owner_display_name,
    vr.owner_avatar_url,
    vr.canonical_name,
    vr.category,
    vr.latitude,
    vr.longitude,
    vr.status,
    vr.visibility,
    vr.note,
    vr.rating_signal,
    vr.rating_score,
    rs.recommended_score,
    coalesce(rs.recommended_count, 0),
    vr.source_type,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'question_definition_id', pa.question_definition_id,
          'question_key', pa.question_key,
          'value_type', pa.value_type,
          'value', pa.value,
          'prompt', qd.prompt,
          'options', coalesce(qd.options, '[]'::jsonb),
          'is_system', coalesce(qd.is_system, false)
        )
      ) filter (where pa.id is not null),
      '[]'::jsonb
    ) as attributes
  from visible_rows vr
  left join rating_summary rs on rs.place_id = vr.place_id
  left join public.place_attributes pa on pa.user_place_id = vr.user_place_id
  left join public.question_definitions qd on qd.id = pa.question_definition_id
  group by
    vr.user_place_id,
    vr.place_id,
    vr.owner_user_id,
    vr.owner_handle,
    vr.owner_display_name,
    vr.owner_avatar_url,
    vr.canonical_name,
    vr.category,
    vr.latitude,
    vr.longitude,
    vr.status,
    vr.visibility,
    vr.note,
    vr.rating_signal,
    vr.rating_score,
    rs.recommended_score,
    rs.recommended_count,
    vr.source_type;
$$;

create or replace function app.profile_visible_places(
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
  latitude double precision,
  longitude double precision,
  status text,
  visibility text,
  note text,
  rating_signal text,
  rating_score integer,
  recommended_score double precision,
  recommended_count integer,
  source_type text,
  attributes jsonb
)
language sql
stable
security invoker
as $$
  with visible_rows as (
    select
      up.id as user_place_id,
      p.id as place_id,
      up.user_id as owner_user_id,
      owner.handle as owner_handle,
      owner.display_name as owner_display_name,
      owner.avatar_url as owner_avatar_url,
      p.canonical_name,
      p.category,
      p.latitude,
      p.longitude,
      up.status,
      up.visibility,
      up.note,
      up.rating_signal,
      up.rating_score::integer as rating_score,
      up.source_type,
      up.updated_at
    from public.user_places up
    join public.places p on p.id = up.place_id
    join public.profiles owner on owner.id = up.user_id
    where up.user_id = profile_id
      and up.deleted_at is null
      and (status_filter is null or up.status = any(status_filter))
      and (category_filter is null or p.category = any(category_filter))
  ),
  visible_rating_rows as (
    select up.place_id, up.rating_score
    from public.user_places up
    where up.deleted_at is null
      and up.status = 'been'
      and up.rating_score is not null
      and up.place_id in (select distinct place_id from visible_rows)
  ),
  rating_summary as (
    select
      place_id,
      round(avg(rating_score)::numeric, 1)::double precision as recommended_score,
      count(*)::integer as recommended_count
    from visible_rating_rows
    group by place_id
  )
  select
    vr.user_place_id,
    vr.place_id,
    vr.owner_user_id,
    vr.owner_handle,
    vr.owner_display_name,
    vr.owner_avatar_url,
    vr.canonical_name,
    vr.category,
    vr.latitude,
    vr.longitude,
    vr.status,
    vr.visibility,
    vr.note,
    vr.rating_signal,
    vr.rating_score,
    rs.recommended_score,
    coalesce(rs.recommended_count, 0),
    vr.source_type,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'question_definition_id', pa.question_definition_id,
          'question_key', pa.question_key,
          'value_type', pa.value_type,
          'value', pa.value,
          'prompt', qd.prompt,
          'options', coalesce(qd.options, '[]'::jsonb),
          'is_system', coalesce(qd.is_system, false)
        )
      ) filter (where pa.id is not null),
      '[]'::jsonb
    ) as attributes
  from visible_rows vr
  left join rating_summary rs on rs.place_id = vr.place_id
  left join public.place_attributes pa on pa.user_place_id = vr.user_place_id
  left join public.question_definitions qd on qd.id = pa.question_definition_id
  group by
    vr.user_place_id,
    vr.place_id,
    vr.owner_user_id,
    vr.owner_handle,
    vr.owner_display_name,
    vr.owner_avatar_url,
    vr.canonical_name,
    vr.category,
    vr.latitude,
    vr.longitude,
    vr.status,
    vr.visibility,
    vr.note,
    vr.rating_signal,
    vr.rating_score,
    rs.recommended_score,
    rs.recommended_count,
    vr.source_type,
    vr.updated_at
  order by vr.updated_at desc;
$$;

create or replace function public.visible_places_in_view(
  min_lat double precision,
  min_lng double precision,
  max_lat double precision,
  max_lng double precision,
  status_filter text[] default null,
  category_filter text[] default null,
  owner_scope text[] default null
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
  latitude double precision,
  longitude double precision,
  status text,
  visibility text,
  note text,
  rating_signal text,
  rating_score integer,
  recommended_score double precision,
  recommended_count integer,
  source_type text,
  attributes jsonb
)
language sql
stable
security invoker
set search_path = app, public
as $$
  select *
  from app.visible_places_in_view(
    min_lat,
    min_lng,
    max_lat,
    max_lng,
    status_filter,
    category_filter,
    owner_scope
  );
$$;

create or replace function public.profile_visible_places(
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
  latitude double precision,
  longitude double precision,
  status text,
  visibility text,
  note text,
  rating_signal text,
  rating_score integer,
  recommended_score double precision,
  recommended_count integer,
  source_type text,
  attributes jsonb
)
language sql
stable
security invoker
set search_path = app, public
as $$
  select *
  from app.profile_visible_places(profile_id, status_filter, category_filter);
$$;

revoke all on function app.visible_places_in_view(double precision, double precision, double precision, double precision, text[], text[], text[]) from public, anon;
revoke all on function public.visible_places_in_view(double precision, double precision, double precision, double precision, text[], text[], text[]) from public, anon;
revoke all on function app.profile_visible_places(text, text[], text[]) from public, anon;
revoke all on function public.profile_visible_places(text, text[], text[]) from public, anon;

grant execute on function app.visible_places_in_view(double precision, double precision, double precision, double precision, text[], text[], text[]) to authenticated;
grant execute on function public.visible_places_in_view(double precision, double precision, double precision, double precision, text[], text[], text[]) to authenticated;
grant execute on function app.profile_visible_places(text, text[], text[]) to authenticated;
grant execute on function public.profile_visible_places(text, text[], text[]) to authenticated;

commit;
