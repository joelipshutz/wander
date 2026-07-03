begin;

create table if not exists public.notification_preferences (
  user_id text primary key references public.profiles(id) on delete cascade,
  push_enabled boolean not null default true,
  social_graph_enabled boolean not null default true,
  shared_lists_enabled boolean not null default true,
  recommendations_enabled boolean not null default true,
  capture_enabled boolean not null default true,
  discovery_digest_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.notification_device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id text not null references public.profiles(id) on delete cascade,
  platform text not null default 'ios' check (platform = 'ios'),
  environment text not null check (environment in ('sandbox', 'production')),
  app_bundle_id text not null default 'com.grayline.wander',
  device_token text not null check (
    length(device_token) between 32 and 512
    and device_token ~ '^[A-Fa-f0-9]+$'
  ),
  token_hash text generated always as (encode(digest(device_token, 'sha256'), 'hex')) stored,
  is_active boolean not null default true,
  last_registered_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, platform, environment, token_hash)
);

create table if not exists public.notification_events (
  id uuid primary key default gen_random_uuid(),
  recipient_user_id text not null references public.profiles(id) on delete cascade,
  actor_user_id text references public.profiles(id) on delete set null,
  notification_type text not null check (
    notification_type in (
      'followed_you',
      'mutual_follow',
      'list_collaborator_added',
      'list_place_added',
      'place_saved_from_your_map',
      'capture_ready',
      'followed_activity_digest'
    )
  ),
  title text not null check (length(title) between 1 and 120),
  body text not null check (length(body) between 1 and 240),
  deeplink_url text,
  data jsonb not null default '{}'::jsonb,
  dedupe_key text,
  status text not null default 'pending' check (status in ('pending', 'claimed', 'sent', 'skipped', 'failed')),
  skip_reason text,
  not_before timestamptz not null default now(),
  claimed_at timestamptz,
  delivered_at timestamptz,
  failed_at timestamptz,
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (jsonb_typeof(data) = 'object')
);

create index if not exists notification_device_tokens_user_active_idx
  on public.notification_device_tokens(user_id, environment)
  where is_active;

create index if not exists notification_events_recipient_created_idx
  on public.notification_events(recipient_user_id, created_at desc);

create index if not exists notification_events_pending_idx
  on public.notification_events(status, not_before, created_at)
  where status = 'pending';

create unique index if not exists notification_events_pending_dedupe_idx
  on public.notification_events(dedupe_key)
  where dedupe_key is not null and status in ('pending', 'claimed');

drop trigger if exists notification_preferences_set_updated_at on public.notification_preferences;
create trigger notification_preferences_set_updated_at
  before update on public.notification_preferences
  for each row execute function app.set_updated_at();

drop trigger if exists notification_device_tokens_set_updated_at on public.notification_device_tokens;
create trigger notification_device_tokens_set_updated_at
  before update on public.notification_device_tokens
  for each row execute function app.set_updated_at();

drop trigger if exists notification_events_set_updated_at on public.notification_events;
create trigger notification_events_set_updated_at
  before update on public.notification_events
  for each row execute function app.set_updated_at();

alter table public.notification_preferences enable row level security;
alter table public.notification_device_tokens enable row level security;
alter table public.notification_events enable row level security;

drop policy if exists "notification preferences owner readable" on public.notification_preferences;
create policy "notification preferences owner readable"
  on public.notification_preferences for select
  using (user_id = app.current_user_id());

drop policy if exists "notification preferences owner writes" on public.notification_preferences;
create policy "notification preferences owner writes"
  on public.notification_preferences for all
  using (user_id = app.current_user_id())
  with check (user_id = app.current_user_id());

drop policy if exists "notification tokens owner readable" on public.notification_device_tokens;
create policy "notification tokens owner readable"
  on public.notification_device_tokens for select
  using (user_id = app.current_user_id());

drop policy if exists "notification tokens owner writes" on public.notification_device_tokens;
create policy "notification tokens owner writes"
  on public.notification_device_tokens for all
  using (user_id = app.current_user_id())
  with check (user_id = app.current_user_id());

drop policy if exists "notification events recipient readable" on public.notification_events;
create policy "notification events recipient readable"
  on public.notification_events for select
  using (recipient_user_id = app.current_user_id());

create or replace function app.ensure_notification_preferences(input_user_id text)
returns public.notification_preferences
language plpgsql
security definer
set search_path = public, app
as $$
declare
  output_preferences public.notification_preferences;
begin
  if input_user_id is null or input_user_id = '' then
    raise exception 'invalid_notification_preferences_user';
  end if;

  insert into public.notification_preferences(user_id)
  values (input_user_id)
  on conflict (user_id) do update
    set user_id = excluded.user_id
  returning * into output_preferences;

  return output_preferences;
end;
$$;

create or replace function app.notification_type_enabled(
  input_preferences public.notification_preferences,
  input_notification_type text
)
returns boolean
language sql
stable
security definer
set search_path = public, app
as $$
  select coalesce(input_preferences.push_enabled, false)
    and case
      when input_notification_type in ('followed_you', 'mutual_follow') then input_preferences.social_graph_enabled
      when input_notification_type in ('list_collaborator_added', 'list_place_added') then input_preferences.shared_lists_enabled
      when input_notification_type = 'place_saved_from_your_map' then input_preferences.recommendations_enabled
      when input_notification_type = 'capture_ready' then input_preferences.capture_enabled
      when input_notification_type = 'followed_activity_digest' then input_preferences.discovery_digest_enabled
      else false
    end
$$;

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
declare
  recipient_preferences public.notification_preferences;
  output_event_id uuid;
begin
  if input_recipient_user_id is null or input_recipient_user_id = '' then
    return null;
  end if;

  if input_actor_user_id is not null and input_actor_user_id = input_recipient_user_id then
    return null;
  end if;

  if input_notification_type not in (
    'followed_you',
    'mutual_follow',
    'list_collaborator_added',
    'list_place_added',
    'place_saved_from_your_map',
    'capture_ready',
    'followed_activity_digest'
  ) then
    raise exception 'invalid_notification_type';
  end if;

  if coalesce(jsonb_typeof(coalesce(input_data, '{}'::jsonb)), '') <> 'object' then
    raise exception 'invalid_notification_data';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = input_recipient_user_id
      and p.deleted_at is null
  ) then
    return null;
  end if;

  if input_actor_user_id is not null then
    if not exists (
      select 1
      from public.profiles p
      where p.id = input_actor_user_id
        and p.deleted_at is null
    ) then
      return null;
    end if;

    if app.is_blocked(input_recipient_user_id, input_actor_user_id) then
      return null;
    end if;
  end if;

  if not exists (
    select 1
    from public.notification_device_tokens token
    where token.user_id = input_recipient_user_id
      and token.is_active
  ) then
    return null;
  end if;

  recipient_preferences := app.ensure_notification_preferences(input_recipient_user_id);
  if not app.notification_type_enabled(recipient_preferences, input_notification_type) then
    return null;
  end if;

  if input_dedupe_key is not null then
    select id
      into output_event_id
    from public.notification_events
    where dedupe_key = input_dedupe_key
      and status in ('pending', 'claimed')
    order by created_at desc
    limit 1;

    if output_event_id is not null then
      return output_event_id;
    end if;
  end if;

  insert into public.notification_events(
    recipient_user_id,
    actor_user_id,
    notification_type,
    title,
    body,
    deeplink_url,
    data,
    dedupe_key,
    not_before
  )
  values (
    input_recipient_user_id,
    input_actor_user_id,
    input_notification_type,
    left(trim(input_title), 120),
    left(trim(input_body), 240),
    nullif(trim(coalesce(input_deeplink_url, '')), ''),
    coalesce(input_data, '{}'::jsonb),
    nullif(trim(coalesce(input_dedupe_key, '')), ''),
    coalesce(input_not_before, now())
  )
  returning id into output_event_id;

  return output_event_id;
end;
$$;

create or replace function app.notify_follow_insert()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
declare
  actor_profile public.profiles;
  reciprocal_exists boolean;
  notification_kind text;
begin
  select *
    into actor_profile
  from public.profiles
  where id = new.follower_user_id
    and deleted_at is null;

  if actor_profile.id is null then
    return new;
  end if;

  select exists (
    select 1
    from public.follows reciprocal
    where reciprocal.follower_user_id = new.followed_user_id
      and reciprocal.followed_user_id = new.follower_user_id
  ) into reciprocal_exists;

  notification_kind := case when reciprocal_exists then 'mutual_follow' else 'followed_you' end;

  perform app.queue_notification_event(
    input_recipient_user_id := new.followed_user_id,
    input_actor_user_id := new.follower_user_id,
    input_notification_type := notification_kind,
    input_title := case
      when reciprocal_exists then 'You are friends now'
      else 'New follower'
    end,
    input_body := case
      when reciprocal_exists then 'You and ' || actor_profile.display_name || ' are friends now.'
      else actor_profile.display_name || ' started following you.'
    end,
    input_deeplink_url := 'recme://profiles/' || new.follower_user_id,
    input_data := jsonb_build_object(
      'actor_user_id', new.follower_user_id,
      'actor_handle', actor_profile.handle
    ),
    input_dedupe_key := notification_kind || ':' || new.followed_user_id || ':' || new.follower_user_id
  );

  return new;
end;
$$;

drop trigger if exists follows_notify_insert on public.follows;
create trigger follows_notify_insert
  after insert on public.follows
  for each row execute function app.notify_follow_insert();

create or replace function app.notify_social_save_insert()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
declare
  actor_profile public.profiles;
  saved_place public.places;
begin
  if new.source_type <> 'social_save' or new.attribution_user_id is null then
    return new;
  end if;

  select *
    into actor_profile
  from public.profiles
  where id = new.user_id
    and deleted_at is null;

  select *
    into saved_place
  from public.places
  where id = new.place_id;

  if actor_profile.id is null or saved_place.id is null then
    return new;
  end if;

  perform app.queue_notification_event(
    input_recipient_user_id := new.attribution_user_id,
    input_actor_user_id := new.user_id,
    input_notification_type := 'place_saved_from_your_map',
    input_title := 'Your map helped',
    input_body := actor_profile.display_name || ' saved ' || saved_place.canonical_name || ' from your map.',
    input_deeplink_url := 'recme://places/' || new.place_id,
    input_data := jsonb_build_object(
      'place_id', new.place_id,
      'user_place_id', new.id,
      'actor_user_id', new.user_id,
      'actor_handle', actor_profile.handle
    ),
    input_dedupe_key := 'place_saved_from_your_map:' || new.attribution_user_id || ':' || new.user_id || ':' || new.place_id
  );

  return new;
end;
$$;

drop trigger if exists user_places_notify_social_save_insert on public.user_places;
create trigger user_places_notify_social_save_insert
  after insert on public.user_places
  for each row execute function app.notify_social_save_insert();

create or replace function app.notify_place_list_member_active()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
declare
  list_row public.place_lists;
  actor_profile public.profiles;
begin
  if new.deleted_at is not null then
    return new;
  end if;

  if tg_op = 'UPDATE' and old.deleted_at is null then
    return new;
  end if;

  select *
    into list_row
  from public.place_lists
  where id = new.list_id
    and deleted_at is null;

  if list_row.id is null or new.user_id = list_row.owner_user_id then
    return new;
  end if;

  if not app.can_read_place_list(new.list_id, new.user_id) then
    return new;
  end if;

  select *
    into actor_profile
  from public.profiles
  where id = list_row.owner_user_id
    and deleted_at is null;

  if actor_profile.id is null then
    return new;
  end if;

  perform app.queue_notification_event(
    input_recipient_user_id := new.user_id,
    input_actor_user_id := list_row.owner_user_id,
    input_notification_type := 'list_collaborator_added',
    input_title := 'Added to a list',
    input_body := actor_profile.display_name || ' added you to ' || list_row.name || '.',
    input_deeplink_url := 'recme://lists/' || new.list_id,
    input_data := jsonb_build_object(
      'list_id', new.list_id,
      'list_name', list_row.name,
      'actor_user_id', list_row.owner_user_id,
      'actor_handle', actor_profile.handle
    ),
    input_dedupe_key := 'list_collaborator_added:' || new.list_id || ':' || new.user_id
  );

  return new;
end;
$$;

drop trigger if exists place_list_members_notify_active on public.place_list_members;
create trigger place_list_members_notify_active
  after insert or update of deleted_at on public.place_list_members
  for each row execute function app.notify_place_list_member_active();

create or replace function app.notify_place_list_item_insert()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
declare
  list_row public.place_lists;
  actor_profile public.profiles;
  place_row public.places;
  recipient_id text;
begin
  if new.deleted_at is not null then
    return new;
  end if;

  select *
    into list_row
  from public.place_lists
  where id = new.list_id
    and deleted_at is null;

  select *
    into actor_profile
  from public.profiles
  where id = new.added_by_user_id
    and deleted_at is null;

  select *
    into place_row
  from public.places
  where id = new.place_id;

  if list_row.id is null or actor_profile.id is null or place_row.id is null then
    return new;
  end if;

  for recipient_id in
    select participant.user_id
    from (
      select list_row.owner_user_id as user_id
      union
      select member.user_id
      from public.place_list_members member
      where member.list_id = new.list_id
        and member.deleted_at is null
    ) participant
    where participant.user_id <> new.added_by_user_id
      and app.can_read_place_list(new.list_id, participant.user_id)
  loop
    perform app.queue_notification_event(
      input_recipient_user_id := recipient_id,
      input_actor_user_id := new.added_by_user_id,
      input_notification_type := 'list_place_added',
      input_title := 'New place on a list',
      input_body := actor_profile.display_name || ' added ' || place_row.canonical_name || ' to ' || list_row.name || '.',
      input_deeplink_url := 'recme://lists/' || new.list_id,
      input_data := jsonb_build_object(
        'list_id', new.list_id,
        'list_name', list_row.name,
        'place_id', new.place_id,
        'place_name', place_row.canonical_name,
        'actor_user_id', new.added_by_user_id,
        'actor_handle', actor_profile.handle
      ),
      input_dedupe_key := 'list_place_added:' || new.list_id || ':' || new.place_id || ':' || recipient_id
    );
  end loop;

  return new;
end;
$$;

drop trigger if exists place_list_items_notify_insert on public.place_list_items;
create trigger place_list_items_notify_insert
  after insert on public.place_list_items
  for each row execute function app.notify_place_list_item_insert();

create or replace function app.complete_extraction_job(
  input_job_id uuid,
  input_status text,
  input_candidates jsonb default '[]'::jsonb,
  input_confidence double precision default 0,
  input_provider_steps jsonb default '[]'::jsonb,
  input_error_code text default null,
  input_error_message text default null
)
returns jsonb
language plpgsql
security definer
set search_path = app, public
as $$
declare
  v_previous_status text;
  v_job public.extraction_jobs;
  v_candidates jsonb := coalesce(input_candidates, '[]'::jsonb);
  v_steps jsonb := coalesce(input_provider_steps, '[]'::jsonb);
begin
  if input_status not in ('needs_confirmation', 'complete', 'failed', 'no_place_found') then
    raise exception 'invalid_extraction_completion_status';
  end if;

  if coalesce(jsonb_typeof(v_candidates), '') <> 'array' then
    raise exception 'invalid_extraction_candidates';
  end if;

  if coalesce(jsonb_typeof(v_steps), '') <> 'array' then
    raise exception 'invalid_extraction_provider_steps';
  end if;

  select status
    into v_previous_status
  from public.extraction_jobs
  where id = input_job_id;

  update public.extraction_jobs
  set status = input_status,
      extracted_candidates_json = v_candidates,
      confidence = greatest(0, least(coalesce(input_confidence, 0), 1)),
      provider_steps_json = case
        when jsonb_array_length(v_steps) = 0 then provider_steps_json
        else v_steps
      end,
      error_code = input_error_code,
      error_message = input_error_message,
      updated_at = now()
  where id = input_job_id
  returning * into v_job;

  if v_job.id is null then
    raise exception 'extraction_job_not_found';
  end if;

  if input_status = 'needs_confirmation'
     and coalesce(v_previous_status, '') <> 'needs_confirmation' then
    perform app.queue_notification_event(
      input_recipient_user_id := v_job.owner_user_id,
      input_actor_user_id := null,
      input_notification_type := 'capture_ready',
      input_title := 'Your place is ready',
      input_body := 'Open rec.me to confirm the match.',
      input_deeplink_url := 'recme://extraction-jobs/' || v_job.id,
      input_data := jsonb_build_object(
        'extraction_job_id', v_job.id,
        'source_type', v_job.source_type,
        'status', v_job.status
      ),
      input_dedupe_key := 'capture_ready:' || v_job.id
    );
  end if;

  return app.extraction_job_result_payload(v_job);
end;
$$;

create or replace function public.get_notification_preferences()
returns public.notification_preferences
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;

  return app.ensure_notification_preferences(viewer_id);
end;
$$;

create or replace function public.update_notification_preferences(input_preferences jsonb)
returns public.notification_preferences
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  output_preferences public.notification_preferences;
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;

  if coalesce(jsonb_typeof(input_preferences), '') <> 'object' then
    raise exception 'invalid_notification_preferences_payload';
  end if;

  perform app.ensure_notification_preferences(viewer_id);

  update public.notification_preferences
  set
    push_enabled = coalesce((input_preferences->>'push_enabled')::boolean, push_enabled),
    social_graph_enabled = coalesce((input_preferences->>'social_graph_enabled')::boolean, social_graph_enabled),
    shared_lists_enabled = coalesce((input_preferences->>'shared_lists_enabled')::boolean, shared_lists_enabled),
    recommendations_enabled = coalesce((input_preferences->>'recommendations_enabled')::boolean, recommendations_enabled),
    capture_enabled = coalesce((input_preferences->>'capture_enabled')::boolean, capture_enabled),
    discovery_digest_enabled = coalesce((input_preferences->>'discovery_digest_enabled')::boolean, discovery_digest_enabled)
  where user_id = viewer_id
  returning * into output_preferences;

  return output_preferences;
end;
$$;

create or replace function public.register_push_token(
  input_device_token text,
  input_environment text default 'production',
  input_app_bundle_id text default 'com.grayline.wander'
)
returns uuid
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  normalized_token text := lower(trim(coalesce(input_device_token, '')));
  normalized_environment text := lower(trim(coalesce(input_environment, 'production')));
  output_id uuid;
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;

  if normalized_environment not in ('sandbox', 'production') then
    raise exception 'invalid_push_environment';
  end if;

  if length(normalized_token) not between 32 and 512
     or normalized_token !~ '^[a-f0-9]+$' then
    raise exception 'invalid_push_token';
  end if;

  perform app.ensure_notification_preferences(viewer_id);

  insert into public.notification_device_tokens(
    user_id,
    platform,
    environment,
    app_bundle_id,
    device_token,
    is_active,
    last_registered_at,
    last_seen_at
  )
  values (
    viewer_id,
    'ios',
    normalized_environment,
    coalesce(nullif(trim(input_app_bundle_id), ''), 'com.grayline.wander'),
    normalized_token,
    true,
    now(),
    now()
  )
  on conflict (user_id, platform, environment, token_hash)
  do update set
    app_bundle_id = excluded.app_bundle_id,
    device_token = excluded.device_token,
    is_active = true,
    last_registered_at = now(),
    last_seen_at = now()
  returning id into output_id;

  return output_id;
end;
$$;

create or replace function public.unregister_push_token(
  input_device_token text,
  input_environment text default null
)
returns void
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  normalized_token text := lower(trim(coalesce(input_device_token, '')));
  normalized_environment text := nullif(lower(trim(coalesce(input_environment, ''))), '');
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;

  update public.notification_device_tokens
  set is_active = false,
      last_seen_at = now()
  where user_id = viewer_id
    and token_hash = encode(digest(normalized_token, 'sha256'), 'hex')
    and (normalized_environment is null or environment = normalized_environment);
end;
$$;

create or replace function app.claim_pending_push_notifications(input_limit integer default 10)
returns jsonb
language plpgsql
security definer
set search_path = public, app
as $$
declare
  bounded_limit integer := least(greatest(coalesce(input_limit, 10), 1), 100);
  output_payload jsonb;
begin
  with claimed as (
    select event.id
    from public.notification_events event
    where event.status = 'pending'
      and event.not_before <= now()
      and exists (
        select 1
        from public.notification_device_tokens token
        where token.user_id = event.recipient_user_id
          and token.is_active
      )
    order by event.created_at
    for update skip locked
    limit bounded_limit
  ),
  updated as (
    update public.notification_events event
    set status = 'claimed',
        claimed_at = now()
    from claimed
    where event.id = claimed.id
    returning event.*
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'event_id', updated.id,
        'recipient_user_id', updated.recipient_user_id,
        'actor_user_id', updated.actor_user_id,
        'notification_type', updated.notification_type,
        'title', updated.title,
        'body', updated.body,
        'deeplink_url', updated.deeplink_url,
        'data', updated.data,
        'tokens', coalesce(
          (
            select jsonb_agg(
              jsonb_build_object(
                'id', token.id,
                'device_token', token.device_token,
                'environment', token.environment,
                'app_bundle_id', token.app_bundle_id
              )
              order by token.last_seen_at desc
            )
            from public.notification_device_tokens token
            where token.user_id = updated.recipient_user_id
              and token.is_active
          ),
          '[]'::jsonb
        )
      )
      order by updated.created_at
    ),
    '[]'::jsonb
  )
  into output_payload
  from updated;

  return output_payload;
end;
$$;

create or replace function public.claim_pending_push_notifications(input_limit integer default 10)
returns jsonb
language sql
security definer
set search_path = app, public
as $$
  select app.claim_pending_push_notifications(input_limit);
$$;

create or replace function app.mark_push_notification_result(
  input_event_id uuid,
  input_status text,
  input_error_message text default null
)
returns void
language plpgsql
security definer
set search_path = public, app
as $$
begin
  if input_status not in ('sent', 'failed', 'skipped') then
    raise exception 'invalid_push_result_status';
  end if;

  update public.notification_events
  set status = input_status,
      delivered_at = case when input_status = 'sent' then now() else delivered_at end,
      failed_at = case when input_status in ('failed', 'skipped') then now() else failed_at end,
      error_message = nullif(input_error_message, '')
  where id = input_event_id
    and status = 'claimed';
end;
$$;

create or replace function app.deactivate_push_tokens(
  input_token_ids uuid[],
  input_reason text default null
)
returns integer
language plpgsql
security definer
set search_path = public, app
as $$
declare
  updated_count integer;
begin
  update public.notification_device_tokens
  set is_active = false,
      last_seen_at = now()
  where id = any(coalesce(input_token_ids, array[]::uuid[]));

  get diagnostics updated_count = row_count;
  return updated_count;
end;
$$;

create or replace function public.deactivate_push_tokens(
  input_token_ids uuid[],
  input_reason text default null
)
returns integer
language sql
security definer
set search_path = app, public
as $$
  select app.deactivate_push_tokens(input_token_ids, input_reason);
$$;

create or replace function public.mark_push_notification_result(
  input_event_id uuid,
  input_status text,
  input_error_message text default null
)
returns void
language sql
security definer
set search_path = app, public
as $$
  select app.mark_push_notification_result(input_event_id, input_status, input_error_message);
$$;

comment on table public.notification_preferences is 'Per-user push notification preference buckets. Direct social/list/recommendation/capture notifications default on; discovery digest defaults off.';
comment on table public.notification_device_tokens is 'APNs device tokens registered by signed-in iOS users. Service-role workers claim active tokens for queued notification events.';
comment on table public.notification_events is 'Push notification event queue with payloads constrained to notification-safe metadata.';
comment on function app.queue_notification_event(text, text, text, text, text, text, jsonb, text, timestamptz) is 'Internal notification queue helper. Checks recipient preferences, active tokens, blocks, and dedupes pending events.';
comment on function public.register_push_token(text, text, text) is 'Authenticated RPC for the iOS app to register an APNs device token for the current user.';
comment on function public.unregister_push_token(text, text) is 'Authenticated RPC for the iOS app to deactivate an APNs device token for the current user.';
comment on function public.get_notification_preferences() is 'Authenticated RPC returning the current user notification preferences, creating defaults if needed.';
comment on function public.update_notification_preferences(jsonb) is 'Authenticated RPC for updating the current user notification preference buckets.';
comment on function public.claim_pending_push_notifications(integer) is 'Service-role RPC used by the push notification worker to claim pending notification events and active APNs tokens.';
comment on function public.mark_push_notification_result(uuid, text, text) is 'Service-role RPC used by the push notification worker to mark a claimed event sent, failed, or skipped.';
comment on function public.deactivate_push_tokens(uuid[], text) is 'Service-role RPC used by the push notification worker to deactivate APNs tokens rejected permanently by Apple.';

revoke all on public.notification_preferences from anon;
revoke all on public.notification_device_tokens from anon;
revoke all on public.notification_events from anon;

grant select, insert, update, delete on public.notification_preferences to authenticated;
grant select, insert, update, delete on public.notification_device_tokens to authenticated;
grant select on public.notification_events to authenticated;

revoke all on function app.ensure_notification_preferences(text) from public, anon, authenticated;
revoke all on function app.notification_type_enabled(public.notification_preferences, text) from public, anon, authenticated;
revoke all on function app.queue_notification_event(text, text, text, text, text, text, jsonb, text, timestamptz) from public, anon, authenticated;
revoke all on function app.notify_follow_insert() from public, anon, authenticated;
revoke all on function app.notify_social_save_insert() from public, anon, authenticated;
revoke all on function app.notify_place_list_member_active() from public, anon, authenticated;
revoke all on function app.notify_place_list_item_insert() from public, anon, authenticated;
revoke all on function app.claim_pending_push_notifications(integer) from public, anon, authenticated;
revoke all on function app.mark_push_notification_result(uuid, text, text) from public, anon, authenticated;
revoke all on function app.deactivate_push_tokens(uuid[], text) from public, anon, authenticated;
revoke all on function public.get_notification_preferences() from public, anon;
revoke all on function public.update_notification_preferences(jsonb) from public, anon;
revoke all on function public.register_push_token(text, text, text) from public, anon;
revoke all on function public.unregister_push_token(text, text) from public, anon;
revoke all on function public.claim_pending_push_notifications(integer) from public, anon, authenticated;
revoke all on function public.mark_push_notification_result(uuid, text, text) from public, anon, authenticated;
revoke all on function public.deactivate_push_tokens(uuid[], text) from public, anon, authenticated;

grant execute on function public.get_notification_preferences() to authenticated;
grant execute on function public.update_notification_preferences(jsonb) to authenticated;
grant execute on function public.register_push_token(text, text, text) to authenticated;
grant execute on function public.unregister_push_token(text, text) to authenticated;
grant execute on function app.claim_pending_push_notifications(integer) to service_role;
grant execute on function public.claim_pending_push_notifications(integer) to service_role;
grant execute on function app.mark_push_notification_result(uuid, text, text) to service_role;
grant execute on function public.mark_push_notification_result(uuid, text, text) to service_role;
grant execute on function app.deactivate_push_tokens(uuid[], text) to service_role;
grant execute on function public.deactivate_push_tokens(uuid[], text) to service_role;

-- Restate the service-role-only security posture for extraction completion after
-- adding the capture-ready queue side effect.
revoke all on function app.complete_extraction_job(uuid, text, jsonb, double precision, jsonb, text, text) from public, anon, authenticated;
revoke all on function public.complete_extraction_job(uuid, text, jsonb, double precision, jsonb, text, text) from public, anon, authenticated;
grant execute on function app.complete_extraction_job(uuid, text, jsonb, double precision, jsonb, text, text) to service_role;
grant execute on function public.complete_extraction_job(uuid, text, jsonb, double precision, jsonb, text, text) to service_role;

commit;
