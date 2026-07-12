begin;

alter table public.notification_preferences
  add column if not exists followed_activity_enabled boolean not null default true;

alter table public.notification_events
  drop constraint if exists notification_events_notification_type_check;
alter table public.notification_events
  add constraint notification_events_notification_type_check check (
    notification_type in (
      'followed_you', 'mutual_follow', 'list_collaborator_added',
      'list_place_added', 'place_saved_from_your_map', 'capture_ready',
      'followed_activity_digest', 'followed_place_visit'
    )
  );

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
      when input_notification_type = 'followed_place_visit' then input_preferences.followed_activity_enabled
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
  if input_recipient_user_id is null or input_recipient_user_id = '' then return null; end if;
  if input_actor_user_id is not null and input_actor_user_id = input_recipient_user_id then return null; end if;
  if input_notification_type not in (
    'followed_you', 'mutual_follow', 'list_collaborator_added',
    'list_place_added', 'place_saved_from_your_map', 'capture_ready',
    'followed_activity_digest', 'followed_place_visit'
  ) then raise exception 'invalid_notification_type'; end if;
  if coalesce(jsonb_typeof(coalesce(input_data, '{}'::jsonb)), '') <> 'object' then
    raise exception 'invalid_notification_data';
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = input_recipient_user_id and p.deleted_at is null
  ) then return null; end if;
  if input_actor_user_id is not null then
    if not exists (
      select 1 from public.profiles p
      where p.id = input_actor_user_id and p.deleted_at is null
    ) then return null; end if;
    if app.is_blocked(input_recipient_user_id, input_actor_user_id) then return null; end if;
  end if;
  if not exists (
    select 1 from public.notification_device_tokens token
    where token.user_id = input_recipient_user_id and token.is_active
  ) then return null; end if;

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
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  if coalesce(jsonb_typeof(input_preferences), '') <> 'object' then
    raise exception 'invalid_notification_preferences_payload';
  end if;

  perform app.ensure_notification_preferences(viewer_id);
  update public.notification_preferences set
    push_enabled = coalesce((input_preferences->>'push_enabled')::boolean, push_enabled),
    social_graph_enabled = coalesce((input_preferences->>'social_graph_enabled')::boolean, social_graph_enabled),
    shared_lists_enabled = coalesce((input_preferences->>'shared_lists_enabled')::boolean, shared_lists_enabled),
    recommendations_enabled = coalesce((input_preferences->>'recommendations_enabled')::boolean, recommendations_enabled),
    capture_enabled = coalesce((input_preferences->>'capture_enabled')::boolean, capture_enabled),
    discovery_digest_enabled = coalesce((input_preferences->>'discovery_digest_enabled')::boolean, discovery_digest_enabled),
    followed_activity_enabled = coalesce((input_preferences->>'followed_activity_enabled')::boolean, followed_activity_enabled)
  where user_id = viewer_id
  returning * into output_preferences;
  return output_preferences;
end;
$$;

create or replace function app.notify_followed_place_visit_insert()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
declare
  activity record;
  follower record;
  actor_name text;
begin
  if new.deleted_at is not null then return new; end if;

  select up.user_id, up.place_id, up.visibility, p.canonical_name,
         profile.display_name, profile.handle
  into activity
  from public.user_places up
  join public.places p on p.id = up.place_id
  join public.profiles profile on profile.id = up.user_id and profile.deleted_at is null
  where up.id = new.user_place_id
    and up.deleted_at is null
    and up.status = 'been';

  if activity.user_id is null then return new; end if;
  actor_name := coalesce(nullif(btrim(activity.display_name), ''), '@' || activity.handle);

  for follower in
    select f.follower_user_id
    from public.follows f
    where f.followed_user_id = activity.user_id
      and app.can_read_user_place(f.follower_user_id, activity.user_id, activity.visibility)
  loop
    perform app.queue_notification_event(
      input_recipient_user_id := follower.follower_user_id,
      input_actor_user_id := activity.user_id,
      input_notification_type := 'followed_place_visit',
      input_title := actor_name || ' saved a place',
      input_body := activity.canonical_name,
      input_deeplink_url := 'recme://places/' || activity.place_id,
      input_data := jsonb_build_object(
        'visit_id', new.id,
        'user_place_id', new.user_place_id,
        'place_id', activity.place_id,
        'actor_user_id', activity.user_id
      ),
      input_dedupe_key := 'followed_place_visit:' || new.id || ':' || follower.follower_user_id
    );
  end loop;
  return new;
end;
$$;

drop trigger if exists place_visits_notify_followers_after_insert on public.place_visits;
create trigger place_visits_notify_followers_after_insert
  after insert on public.place_visits
  for each row execute function app.notify_followed_place_visit_insert();

revoke all on function app.notify_followed_place_visit_insert() from public, anon, authenticated;

comment on function app.notify_followed_place_visit_insert() is
  'Queues one privacy-filtered push per eligible follower when a visited-place record is created.';

commit;
