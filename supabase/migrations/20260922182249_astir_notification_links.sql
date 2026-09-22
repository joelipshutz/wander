begin;

-- REC-599: Only the public origin changes. Preserve the existing trigger's
-- visibility check, recipient set, dedupe, and data.activity_id fallback used
-- by installed clients. Previously queued notifications are not rewritten.
-- SECURITY DEFINER is required to enqueue for authorized recipients; this
-- trigger is private to app and must remain uncallable by API roles.
create or replace function app.queue_activity_engagement_notification()
returns trigger
language plpgsql
volatile
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
      input_deeplink_url := 'https://astirmovement.com/activities/' || activity.id,
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

revoke all on function app.queue_activity_engagement_notification() from public, anon, authenticated;
comment on function app.queue_activity_engagement_notification() is
  'Queues visibility-checked like/comment notifications using canonical Astir links, excluding the actor.';

do $$
begin
  if not exists (
    select 1 from pg_proc
    where oid = 'app.queue_activity_engagement_notification()'::regprocedure
      and prosecdef and provolatile = 'v' and prorettype = 'trigger'::regtype
      and 'search_path=pg_catalog, public, app' = any(coalesce(proconfig, array[]::text[]))
  ) or has_function_privilege('anon', 'app.queue_activity_engagement_notification()', 'execute')
    or has_function_privilege('authenticated', 'app.queue_activity_engagement_notification()', 'execute') then
    raise exception 'engagement notification trigger security posture changed';
  end if;
end;
$$;

commit;
