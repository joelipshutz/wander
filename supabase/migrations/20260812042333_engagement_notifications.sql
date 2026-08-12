begin;

-- Likes and comments are their own consent category. New preference rows remain
-- fully opt-in, matching the existing notification enrollment contract.
alter table public.notification_preferences
  add column if not exists engagement_enabled boolean not null default false;

alter table public.notification_preferences
  alter column engagement_enabled set default false;

alter table public.notification_events
  drop constraint if exists notification_events_notification_type_check;
alter table public.notification_events
  add constraint notification_events_notification_type_check check (
    notification_type in (
      'followed_you', 'mutual_follow', 'list_collaborator_added',
      'list_place_added', 'place_saved_from_your_map', 'capture_ready',
      'followed_activity_digest', 'followed_place_visit', 'shared_visit',
      'activity_liked', 'activity_commented'
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
      when input_notification_type = 'shared_visit' then input_preferences.shared_visits_enabled
      when input_notification_type = 'place_saved_from_your_map' then input_preferences.recommendations_enabled
      when input_notification_type = 'capture_ready' then input_preferences.capture_enabled
      when input_notification_type = 'followed_activity_digest' then input_preferences.discovery_digest_enabled
      when input_notification_type = 'followed_place_visit' then input_preferences.followed_activity_enabled
      when input_notification_type in ('activity_liked', 'activity_commented') then input_preferences.engagement_enabled
      else false
    end
$$;

-- Restate the current queue contract with the two engagement types added. The
-- actor block/mute, active-token, category-consent, and pending-dedupe gates are
-- deliberately preserved.
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
  actor_is_muted boolean := false;
begin
  if input_recipient_user_id is null or input_recipient_user_id = '' then return null; end if;
  if input_actor_user_id is not null and input_actor_user_id = input_recipient_user_id then return null; end if;
  if input_notification_type not in (
    'followed_you', 'mutual_follow', 'list_collaborator_added',
    'list_place_added', 'place_saved_from_your_map', 'capture_ready',
    'followed_activity_digest', 'followed_place_visit', 'shared_visit',
    'activity_liked', 'activity_commented'
  ) then raise exception 'invalid_notification_type'; end if;
  if coalesce(jsonb_typeof(coalesce(input_data, '{}'::jsonb)), '') <> 'object' then
    raise exception 'invalid_notification_data';
  end if;
  if not exists (
    select 1 from public.profiles profile
    where profile.id = input_recipient_user_id and profile.deleted_at is null
  ) then return null; end if;
  if input_actor_user_id is not null then
    if not exists (
      select 1 from public.profiles profile
      where profile.id = input_actor_user_id and profile.deleted_at is null
    ) then return null; end if;
    if app.is_blocked(input_recipient_user_id, input_actor_user_id) then return null; end if;
    if to_regclass('public.profile_mutes') is not null then
      execute
        'select exists (
           select 1 from public.profile_mutes
           where muter_user_id = $1 and muted_user_id = $2
         )'
      into actor_is_muted
      using input_recipient_user_id, input_actor_user_id;
      if actor_is_muted then return null; end if;
    end if;
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
    shared_visits_enabled = coalesce((input_preferences->>'shared_visits_enabled')::boolean, shared_visits_enabled),
    recommendations_enabled = coalesce((input_preferences->>'recommendations_enabled')::boolean, recommendations_enabled),
    capture_enabled = coalesce((input_preferences->>'capture_enabled')::boolean, capture_enabled),
    discovery_digest_enabled = coalesce((input_preferences->>'discovery_digest_enabled')::boolean, discovery_digest_enabled),
    followed_activity_enabled = coalesce((input_preferences->>'followed_activity_enabled')::boolean, followed_activity_enabled),
    wanna_go_reminders_enabled = coalesce((input_preferences->>'wanna_go_reminders_enabled')::boolean, wanna_go_reminders_enabled),
    engagement_enabled = coalesce((input_preferences->>'engagement_enabled')::boolean, engagement_enabled)
  where user_id = viewer_id
  returning * into output_preferences;
  return output_preferences;
end;
$$;

-- Queue one event for the post owner and each distinct prior participant. The
-- action actor is excluded, and current activity visibility is rechecked for
-- every recipient so stale engagement cannot bypass privacy changes.
create function app.queue_activity_engagement_notification()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  activity public.feed_events;
  actor public.profiles;
  actor_id text;
  action_id text;
  notification_type text;
  notification_title text;
  subject_name text;
  recipient_id text;
  notification_body text;
begin
  if tg_table_name = 'activity_likes' then
    actor_id := new.user_id;
    action_id := new.user_id;
    notification_type := 'activity_liked';
    notification_title := 'New like';
  elsif tg_table_name = 'activity_comments' then
    actor_id := new.author_user_id;
    action_id := new.id::text;
    notification_type := 'activity_commented';
    notification_title := 'New comment';
  else
    raise exception 'unsupported_activity_engagement_table';
  end if;

  select * into activity
  from public.feed_events
  where id = new.activity_id;

  select * into actor
  from public.profiles
  where id = actor_id
    and deleted_at is null;

  if activity.id is null or actor.id is null then
    return new;
  end if;

  select coalesce(place.canonical_name, list.name, 'a post')
  into subject_name
  from (select 1) singleton
  left join public.places place on place.id = activity.place_id
  left join public.place_lists list on list.id = activity.list_id;

  for recipient_id in
    select participant.user_id
    from (
      select activity.actor_user_id as user_id
      union
      select activity_like.user_id
      from public.activity_likes activity_like
      where activity_like.activity_id = activity.id
      union
      select comment.author_user_id
      from public.activity_comments comment
      where comment.activity_id = activity.id
    ) participant
    where participant.user_id <> actor_id
      and app.can_read_activity_event(participant.user_id, activity.id)
  loop
    notification_body := case
      when notification_type = 'activity_liked' and recipient_id = activity.actor_user_id
        then actor.display_name || ' liked your post about ' || subject_name || '.'
      when notification_type = 'activity_liked'
        then actor.display_name || ' liked a post you engaged with about ' || subject_name || '.'
      when recipient_id = activity.actor_user_id
        then actor.display_name || ' commented on your post about ' || subject_name || '.'
      else actor.display_name || ' also commented on a post about ' || subject_name || '.'
    end;

    perform app.queue_notification_event(
      input_recipient_user_id := recipient_id,
      input_actor_user_id := actor_id,
      input_notification_type := notification_type,
      input_title := notification_title,
      input_body := notification_body,
      input_deeplink_url := 'https://getrec.me/activities/' || activity.id,
      input_data := jsonb_strip_nulls(jsonb_build_object(
        'activity_id', activity.id,
        'place_id', activity.place_id,
        'list_id', activity.list_id,
        'event_type', activity.event_type,
        'actor_user_id', actor_id
      )),
      input_dedupe_key := notification_type || ':' || activity.id || ':' || action_id || ':' || recipient_id
    );
  end loop;

  return new;
end;
$$;

drop trigger if exists activity_likes_queue_notification on public.activity_likes;
create trigger activity_likes_queue_notification
  after insert on public.activity_likes
  for each row execute function app.queue_activity_engagement_notification();

drop trigger if exists activity_comments_queue_notification on public.activity_comments;
create trigger activity_comments_queue_notification
  after insert on public.activity_comments
  for each row execute function app.queue_activity_engagement_notification();

comment on column public.notification_preferences.engagement_enabled is
  'Opt-in push category for likes and comments on posts the user owns or has engaged with.';
comment on function app.queue_activity_engagement_notification() is
  'Queues visibility-checked like/comment notifications for an activity owner and prior participants, excluding the actor.';

revoke all on function app.notification_type_enabled(public.notification_preferences, text) from public, anon, authenticated;
revoke all on function app.queue_notification_event(text, text, text, text, text, text, jsonb, text, timestamptz) from public, anon, authenticated;
revoke all on function app.queue_activity_engagement_notification() from public, anon, authenticated;
revoke all on function public.update_notification_preferences(jsonb) from public, anon;
grant execute on function public.update_notification_preferences(jsonb) to authenticated;

do $$
declare
  default_expression text;
begin
  select pg_get_expr(attribute_default.adbin, attribute_default.adrelid)
  into default_expression
  from pg_attribute attribute
  join pg_attrdef attribute_default
    on attribute_default.adrelid = attribute.attrelid
   and attribute_default.adnum = attribute.attnum
  where attribute.attrelid = 'public.notification_preferences'::regclass
    and attribute.attname = 'engagement_enabled'
    and not attribute.attisdropped;

  if default_expression is distinct from 'false' then
    raise exception 'engagement_enabled must default off, found %', default_expression;
  end if;

  if not exists (
    select 1 from pg_proc
    where oid = 'public.update_notification_preferences(jsonb)'::regprocedure
      and prosecdef
      and 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
  ) then
    raise exception 'public.update_notification_preferences security posture changed';
  end if;

  if not exists (
    select 1 from pg_proc
    where oid = 'app.queue_activity_engagement_notification()'::regprocedure
      and prosecdef
      and 'search_path=pg_catalog, public, app' = any(coalesce(proconfig, array[]::text[]))
  ) then
    raise exception 'activity engagement notification trigger security posture is invalid';
  end if;

  if not has_function_privilege('authenticated', 'public.update_notification_preferences(jsonb)', 'execute')
     or has_function_privilege('anon', 'public.update_notification_preferences(jsonb)', 'execute')
     or has_function_privilege('authenticated', 'app.queue_activity_engagement_notification()', 'execute') then
    raise exception 'engagement notification grants are invalid';
  end if;
end;
$$;

commit;
