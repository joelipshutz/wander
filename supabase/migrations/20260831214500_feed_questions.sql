begin;

-- Questions are immutable Feed activity, just like a check-in or list creation.
-- Keeping the text on the event preserves one stable id for Feed, answers,
-- moderation, notifications, and deep links without exposing the event table.
alter table public.feed_events
  add column if not exists question_text text;

alter table public.feed_events
  drop constraint if exists feed_events_event_type_check;
alter table public.feed_events
  add constraint feed_events_event_type_check check (
    event_type in (
      'place_saved',
      'place_been',
      'place_want_to_go',
      'list_created',
      'list_item_added',
      'question_asked'
    )
  );

alter table public.feed_events
  drop constraint if exists feed_events_subject_check;
alter table public.feed_events
  add constraint feed_events_subject_check check (
    (
      event_type in ('place_saved', 'place_been', 'place_want_to_go')
      and user_place_id is not null
      and place_id is not null
      and (event_type = 'place_been' or visit_id is null)
      and list_id is null
      and list_item_id is null
      and question_text is null
    )
    or (
      event_type = 'list_created'
      and user_place_id is null
      and place_id is null
      and visit_id is null
      and list_id is not null
      and list_item_id is null
      and question_text is null
    )
    or (
      event_type = 'list_item_added'
      and user_place_id is not null
      and place_id is not null
      and visit_id is null
      and list_id is not null
      and list_item_id is not null
      and question_text is null
    )
    or (
      event_type = 'question_asked'
      and user_place_id is null
      and place_id is null
      and visit_id is null
      and list_id is null
      and list_item_id is null
      and question_text = btrim(question_text)
      and char_length(question_text) between 1 and 280
    )
  );

create index if not exists feed_events_questions_actor_occurred_idx
  on public.feed_events (actor_user_id, occurred_at desc, id desc)
  where event_type = 'question_asked';

-- Restate the shared deterministic content guard with Feed question text added.
create or replace function app.enforce_community_text_policy()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
begin
  case tg_table_name
    when 'places' then
      perform app.assert_community_text(new.canonical_name);
      perform app.assert_community_text(new.address);
      perform app.assert_community_text(new.locality);
      perform app.assert_community_text(new.region);
      perform app.assert_community_text(new.country);
    when 'profiles' then
      perform app.assert_community_text(new.display_name);
      perform app.assert_community_text(new.handle);
      perform app.assert_community_text(new.bio);
      perform app.assert_community_text(new.home_area);
    when 'user_places' then
      perform app.assert_community_text(new.note);
    when 'place_visits' then
      perform app.assert_community_text(new.note);
      perform app.assert_community_text(new.attribute_answers::text);
    when 'place_attributes' then
      perform app.assert_community_text(new.value::text);
    when 'place_lists' then
      perform app.assert_community_text(new.name);
      perform app.assert_community_text(new.description);
    when 'activity_comments' then
      perform app.assert_community_text(new.body);
    when 'feed_events' then
      perform app.assert_community_text(new.question_text);
  end case;
  return new;
end;
$$;

drop trigger if exists feed_events_community_text_guard on public.feed_events;
create trigger feed_events_community_text_guard
before insert or update of question_text on public.feed_events
for each row execute function app.enforce_community_text_policy();

-- A question follows the same current profile/block boundary as other Feed
-- activity. It has no place/list visibility dependency of its own.
create or replace function app.can_read_activity_event(
  input_viewer_id text,
  input_activity_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, app
as $$
  select input_viewer_id is not null
    and exists (
      select 1
      from public.feed_events event
      join public.profiles actor on actor.id = event.actor_user_id
      where event.id = input_activity_id
        and actor.deleted_at is null
        and (
          event.actor_user_id = input_viewer_id
          or not coalesce(actor.is_private_profile, false)
        )
        and not app.is_blocked(input_viewer_id, event.actor_user_id)
        and (
          (
            event.event_type in ('place_saved', 'place_been', 'place_want_to_go')
            and exists (
              select 1
              from public.user_places source_place
              where source_place.id = event.user_place_id
                and source_place.deleted_at is null
                and app.can_read_user_place(
                  input_viewer_id,
                  source_place.user_id,
                  source_place.visibility
                )
            )
            and (
              event.visit_id is null
              or exists (
                select 1
                from public.place_visits source_visit
                where source_visit.id = event.visit_id
                  and source_visit.user_place_id = event.user_place_id
                  and source_visit.deleted_at is null
              )
            )
          )
          or (
            event.event_type = 'list_created'
            and app.can_read_place_list(event.list_id, input_viewer_id)
          )
          or (
            event.event_type = 'list_item_added'
            and app.can_read_place_list(event.list_id, input_viewer_id)
            and exists (
              select 1
              from public.user_places source_place
              where source_place.id = event.user_place_id
                and source_place.deleted_at is null
                and app.can_read_user_place(
                  input_viewer_id,
                  source_place.user_id,
                  source_place.visibility
                )
            )
          )
          or (
            event.event_type = 'question_asked'
            and event.question_text is not null
            and (
              event.actor_user_id = input_viewer_id
              or exists (
                select 1
                from public.follows follow
                where follow.follower_user_id = input_viewer_id
                  and follow.followed_user_id = event.actor_user_id
              )
            )
          )
        )
    )
$$;

-- Include questions in the same keyset-paginated Feed. An author can see their
-- own question immediately; other activity remains follower-only as before.
create or replace function app.followed_feed(
  input_before text default null,
  input_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  page_limit integer := greatest(1, least(coalesce(input_limit, 25), 50));
  cursor_occurred_at timestamptz;
  cursor_id uuid;
begin
  if viewer_id is null then
    return jsonb_build_object(
      'activity', '[]'::jsonb,
      'featured_places', '[]'::jsonb,
      'next_cursor', null,
      'fetched_at', now()
    );
  end if;

  if input_before is not null and position('|' in input_before) > 1 then
    begin
      cursor_occurred_at := split_part(input_before, '|', 1)::timestamptz;
      cursor_id := split_part(input_before, '|', 2)::uuid;
    exception when others then
      cursor_occurred_at := null;
      cursor_id := null;
    end;
  end if;

  return (
    with eligible_events as (
      select
        event.id,
        event.actor_user_id,
        event.event_type,
        event.user_place_id,
        event.place_id,
        event.visit_id,
        event.list_id,
        event.list_item_id,
        event.question_text,
        event.occurred_at
      from public.feed_events event
      join public.profiles actor on actor.id = event.actor_user_id
      where actor.deleted_at is null
        and (
          (
            event.event_type = 'question_asked'
            and event.actor_user_id = viewer_id
          )
          or (
            not coalesce(actor.is_private_profile, false)
            and exists (
              select 1
              from public.follows follow
              where follow.follower_user_id = viewer_id
                and follow.followed_user_id = event.actor_user_id
            )
          )
        )
        and not app.is_blocked(viewer_id, event.actor_user_id)
        and (
          (
            event.event_type in ('place_saved', 'place_been', 'place_want_to_go')
            and exists (
              select 1
              from public.user_places source_place
              where source_place.id = event.user_place_id
                and source_place.deleted_at is null
                and app.can_read_user_place(
                  viewer_id,
                  source_place.user_id,
                  source_place.visibility
                )
            )
            and (
              event.visit_id is null
              or exists (
                select 1
                from public.place_visits source_visit
                where source_visit.id = event.visit_id
                  and source_visit.user_place_id = event.user_place_id
                  and source_visit.deleted_at is null
              )
            )
          )
          or (
            event.event_type = 'list_created'
            and app.can_read_place_list(event.list_id, viewer_id)
          )
          or (
            event.event_type = 'list_item_added'
            and app.can_read_place_list(event.list_id, viewer_id)
            and exists (
              select 1
              from public.user_places source_place
              where source_place.id = event.user_place_id
                and source_place.deleted_at is null
                and app.can_read_user_place(
                  viewer_id,
                  source_place.user_id,
                  source_place.visibility
                )
            )
          )
          or (
            event.event_type = 'question_asked'
            and event.question_text is not null
          )
        )
    ),
    cursor_filtered as (
      select *
      from eligible_events
      where cursor_occurred_at is null
        or (occurred_at, id) < (cursor_occurred_at, cursor_id)
    ),
    page_with_extra as (
      select *
      from cursor_filtered
      order by occurred_at desc, id desc
      limit page_limit + 1
    ),
    page as (
      select *
      from page_with_extra
      order by occurred_at desc, id desc
      limit page_limit
    ),
    rendered_activity as (
      select
        page.*,
        jsonb_build_object(
          'id', actor.id,
          'handle', actor.handle,
          'display_name', actor.display_name,
          'avatar_url', actor.avatar_url,
          'bio', actor.bio,
          'home_area', actor.home_area,
          'is_private_profile', actor.is_private_profile,
          'created_at', actor.created_at,
          'relationship', case
            when actor.id = viewer_id then 'owner'
            else 'follower'
          end
        ) as actor_json,
        app.feed_place_projection(page.user_place_id, page.visit_id) as place_json,
        app.feed_list_projection(page.list_id) as list_json
      from page
      join public.profiles actor on actor.id = page.actor_user_id
    ),
    rendered_featured as (
      select distinct on (event.place_id)
        event.place_id,
        event.event_type,
        event.occurred_at,
        event.id,
        app.feed_place_projection(event.user_place_id, event.visit_id) as place_json,
        actor.display_name
      from eligible_events event
      join public.profiles actor on actor.id = event.actor_user_id
      where event.place_id is not null
        and app.feed_place_projection(event.user_place_id, event.visit_id) is not null
        and not exists (
          select 1
          from public.user_places viewer_place
          where viewer_place.user_id = viewer_id
            and viewer_place.place_id = event.place_id
            and viewer_place.deleted_at is null
        )
      order by event.place_id, event.occurred_at desc, event.id desc
    ),
    featured_limited as (
      select *
      from rendered_featured
      order by occurred_at desc, id desc
      limit 8
    )
    select jsonb_build_object(
      'activity', coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', id,
              'event_type', event_type,
              'occurred_at', occurred_at,
              'actor', actor_json,
              'place', place_json,
              'list', list_json,
              'question_text', question_text,
              'note', case
                when event_type = 'list_created' then list_json->>'description'
                else place_json->>'note'
              end,
              'rating', case
                when event_type in ('place_been', 'list_item_added')
                  then (place_json->>'rating_score')::double precision
                else null
              end,
              'media', '[]'::jsonb
            )
            order by occurred_at desc, id desc
          )
          from rendered_activity
        ),
        '[]'::jsonb
      ),
      'featured_places', coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'place', place_json,
              'reason', case
                when event_type = 'place_been'
                  then format('Checked in by %s', display_name)
                else format('Saved by %s', display_name)
              end
            )
            order by occurred_at desc, id desc
          )
          from featured_limited
        ),
        '[]'::jsonb
      ),
      'next_cursor', case
        when (select count(*) from page_with_extra) > page_limit then (
          select occurred_at::text || '|' || id::text
          from page
          order by occurred_at asc, id asc
          limit 1
        )
        else null
      end,
      'fetched_at', now()
    )
  );
end;
$$;

-- Exact activity links and question creation return the same envelope shape as
-- the paginated Feed.
create or replace function public.activity_detail(input_activity_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  viewer_id text := app.current_user_id();
  result jsonb;
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;
  if not app.can_read_activity_event(viewer_id, input_activity_id) then
    raise exception 'activity_not_visible';
  end if;

  select jsonb_build_object(
    'id', event.id,
    'event_type', event.event_type,
    'occurred_at', event.occurred_at,
    'actor', jsonb_build_object(
      'id', actor.id,
      'handle', actor.handle,
      'display_name', actor.display_name,
      'avatar_url', actor.avatar_url,
      'bio', actor.bio,
      'home_area', actor.home_area,
      'is_private_profile', actor.is_private_profile,
      'created_at', actor.created_at,
      'relationship', case
        when actor.id = viewer_id then 'owner'
        when app.is_mutual(viewer_id, actor.id) then 'mutual'
        when app.follows(viewer_id, actor.id) then 'follower'
        else 'non_follower'
      end
    ),
    'place', app.feed_place_projection(event.user_place_id, event.visit_id),
    'list', app.feed_list_projection(event.list_id),
    'question_text', event.question_text,
    'note', case
      when event.event_type = 'list_created'
        then app.feed_list_projection(event.list_id)->>'description'
      else app.feed_place_projection(event.user_place_id, event.visit_id)->>'note'
    end,
    'rating', case
      when event.event_type in ('place_been', 'list_item_added')
        then (app.feed_place_projection(event.user_place_id, event.visit_id)->>'rating_score')::double precision
      else null
    end,
    'media', '[]'::jsonb
  )
  into result
  from public.feed_events event
  join public.profiles actor on actor.id = event.actor_user_id
  where event.id = input_activity_id;

  return result;
end;
$$;

create or replace function public.create_feed_question(input_question_text text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, app
as $$
declare
  viewer_id text := app.current_user_id();
  normalized_question text := btrim(coalesce(input_question_text, ''));
  saved_event public.feed_events;
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;
  if not exists (
    select 1 from public.profiles profile
    where profile.id = viewer_id and profile.deleted_at is null
  ) then
    raise exception 'profile_not_found';
  end if;
  if char_length(normalized_question) < 1 or char_length(normalized_question) > 280 then
    raise exception 'invalid_question_text';
  end if;

  perform app.assert_community_text(normalized_question);

  insert into public.feed_events (actor_user_id, event_type, question_text)
  values (viewer_id, 'question_asked', normalized_question)
  returning * into saved_event;

  return public.activity_detail(saved_event.id);
end;
$$;

-- Question notifications reuse the existing Followed activity preference. The
-- shared queue helper is restated as a strict superset of every deployed type
-- so consent, mute/block filtering, delayed-delivery expiry, and newer reminder
-- contracts stay intact.
alter table public.notification_events
  drop constraint if exists notification_events_notification_type_check;
alter table public.notification_events
  add constraint notification_events_notification_type_check check (
    notification_type in (
      'followed_you', 'mutual_follow', 'list_collaborator_added',
      'list_place_added', 'place_saved_from_your_map', 'capture_ready',
      'followed_activity_digest', 'followed_place_visit', 'shared_visit',
      'activity_liked', 'activity_commented', 'import_finished',
      'wanna_go_reminder', 'save_streak_reminder',
      'calendar_reservation_live', 'calendar_reservation_follow_up',
      'question_asked'
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
      when input_notification_type in ('capture_ready', 'import_finished') then input_preferences.capture_enabled
      when input_notification_type = 'followed_activity_digest' then input_preferences.discovery_digest_enabled
      when input_notification_type in ('followed_place_visit', 'question_asked') then input_preferences.followed_activity_enabled
      when input_notification_type in ('activity_liked', 'activity_commented') then input_preferences.engagement_enabled
      when input_notification_type = 'wanna_go_reminder' then input_preferences.wanna_go_reminders_enabled
      when input_notification_type = 'save_streak_reminder' then true
      when input_notification_type in ('calendar_reservation_live', 'calendar_reservation_follow_up')
        then coalesce(
          (to_jsonb(input_preferences)->>'reservation_reminders_enabled')::boolean,
          false
        )
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
  actor_is_muted boolean := false;
  notification_deadline timestamptz;
begin
  if input_recipient_user_id is null or input_recipient_user_id = '' then return null; end if;
  if input_actor_user_id is not null and input_actor_user_id = input_recipient_user_id then return null; end if;
  if input_notification_type not in (
    'followed_you', 'mutual_follow', 'list_collaborator_added',
    'list_place_added', 'place_saved_from_your_map', 'capture_ready',
    'followed_activity_digest', 'followed_place_visit', 'shared_visit',
    'activity_liked', 'activity_commented', 'import_finished',
    'wanna_go_reminder', 'save_streak_reminder',
    'calendar_reservation_live', 'calendar_reservation_follow_up',
    'question_asked'
  ) then raise exception 'invalid_notification_type'; end if;
  if coalesce(jsonb_typeof(coalesce(input_data, '{}'::jsonb)), '') <> 'object' then
    raise exception 'invalid_notification_data';
  end if;
  if length(trim(coalesce(input_title, ''))) not between 1 and 120
     or length(trim(coalesce(input_body, ''))) not between 1 and 240 then
    raise exception 'invalid_notification_copy';
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

  recipient_preferences := app.ensure_notification_preferences(input_recipient_user_id);
  if not app.notification_type_enabled(recipient_preferences, input_notification_type) then return null; end if;

  if input_dedupe_key is not null then
    select id into output_event_id
    from public.notification_events
    where dedupe_key = input_dedupe_key and status in ('pending', 'claimed')
    order by created_at desc limit 1;
    if output_event_id is not null then return output_event_id; end if;
  end if;

  notification_deadline := greatest(
    coalesce(input_not_before, now()) + interval '24 hours',
    now() + interval '24 hours'
  );

  insert into public.notification_events(
    recipient_user_id, actor_user_id, notification_type, title, body,
    deeplink_url, data, dedupe_key, not_before, expires_at
  ) values (
    input_recipient_user_id, input_actor_user_id, input_notification_type,
    left(trim(input_title), 120), left(trim(input_body), 240),
    nullif(trim(coalesce(input_deeplink_url, '')), ''), coalesce(input_data, '{}'::jsonb),
    nullif(trim(coalesce(input_dedupe_key, '')), ''), coalesce(input_not_before, now()),
    notification_deadline
  ) returning id into output_event_id;

  -- Production may already carry the delayed-delivery latest_at guard. Keep
  -- it synchronized without making this migration depend on that later column
  -- when the schema is rebuilt strictly from this repository's migrations.
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'notification_events'
      and column_name = 'latest_at'
  ) then
    execute 'update public.notification_events set latest_at = $2 where id = $1'
      using output_event_id, notification_deadline;
  end if;
  return output_event_id;
end;
$$;

create or replace function app.queue_feed_question_notification()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  actor_name text;
  follower_id text;
begin
  if new.event_type <> 'question_asked' or new.question_text is null then
    return new;
  end if;

  select coalesce(nullif(btrim(profile.display_name), ''), '@' || profile.handle)
  into actor_name
  from public.profiles profile
  where profile.id = new.actor_user_id
    and profile.deleted_at is null;

  if actor_name is null then return new; end if;

  for follower_id in
    select follow.follower_user_id
    from public.follows follow
    where follow.followed_user_id = new.actor_user_id
      and app.can_read_activity_event(follow.follower_user_id, new.id)
  loop
    perform app.queue_notification_event(
      input_recipient_user_id := follower_id,
      input_actor_user_id := new.actor_user_id,
      input_notification_type := 'question_asked',
      input_title := left(actor_name || ' asked a question', 120),
      input_body := left(new.question_text, 240),
      input_deeplink_url := 'https://getrec.me/activities/' || new.id,
      input_data := jsonb_build_object(
        'activity_id', new.id,
        'event_type', new.event_type,
        'actor_user_id', new.actor_user_id
      ),
      input_dedupe_key := 'question_asked:' || new.id || ':' || follower_id
    );
  end loop;

  return new;
end;
$$;

drop trigger if exists feed_questions_queue_notification on public.feed_events;
create trigger feed_questions_queue_notification
after insert on public.feed_events
for each row
when (new.event_type = 'question_asked')
execute function app.queue_feed_question_notification();

-- Answer notifications reuse the comments trigger, with question-specific copy
-- and the question text as the subject instead of the generic "a post" label.
create or replace function app.queue_activity_engagement_notification()
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

  if activity.event_type = 'question_asked' and notification_type = 'activity_commented' then
    notification_title := 'New answer';
  end if;

  select coalesce(place.canonical_name, list.name, activity.question_text, 'a post')
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
      when activity.event_type = 'question_asked'
        and notification_type = 'activity_liked'
        and recipient_id = activity.actor_user_id
        then actor.display_name || ' liked your question: ' || subject_name
      when activity.event_type = 'question_asked'
        and notification_type = 'activity_liked'
        then actor.display_name || ' liked a question you answered: ' || subject_name
      when activity.event_type = 'question_asked'
        and recipient_id = activity.actor_user_id
        then actor.display_name || ' answered your question: ' || subject_name
      when activity.event_type = 'question_asked'
        then actor.display_name || ' also answered: ' || subject_name
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
      input_body := left(notification_body, 240),
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

-- Preserve the question text in moderation snapshots without replacing the
-- established report RPC.
create or replace function app.add_question_to_content_report_snapshot()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  reported_question text;
begin
  if new.subject_kind <> 'activity' then return new; end if;

  begin
    select event.question_text
    into reported_question
    from public.feed_events event
    where event.id = new.subject_id::uuid
      and event.actor_user_id = new.reported_user_id
      and event.event_type = 'question_asked';
  exception when invalid_text_representation then
    return new;
  end;

  if reported_question is not null then
    new.content_snapshot := coalesce(new.content_snapshot, '{}'::jsonb)
      || jsonb_build_object('question_text', reported_question);
  end if;
  return new;
end;
$$;

drop trigger if exists content_reports_question_snapshot on public.content_reports;
create trigger content_reports_question_snapshot
before insert on public.content_reports
for each row execute function app.add_question_to_content_report_snapshot();

revoke all on function app.can_read_activity_event(text, uuid)
  from public, anon, authenticated;
revoke all on function app.followed_feed(text, integer)
  from public, anon, authenticated;
revoke all on function app.enforce_community_text_policy()
  from public, anon, authenticated;
revoke all on function app.notification_type_enabled(public.notification_preferences, text)
  from public, anon, authenticated;
revoke all on function app.queue_notification_event(text, text, text, text, text, text, jsonb, text, timestamptz)
  from public, anon, authenticated;
revoke all on function app.queue_feed_question_notification()
  from public, anon, authenticated;
revoke all on function app.queue_activity_engagement_notification()
  from public, anon, authenticated;
revoke all on function app.add_question_to_content_report_snapshot()
  from public, anon, authenticated;
revoke all on function public.activity_detail(uuid)
  from public, anon;
revoke all on function public.create_feed_question(text)
  from public, anon;

grant execute on function public.activity_detail(uuid) to authenticated;
grant execute on function public.create_feed_question(text) to authenticated;

comment on column public.feed_events.question_text is
  'Immutable 1-280 character text for a question_asked Feed event.';
comment on function public.create_feed_question(text) is
  'Creates one normalized question_asked event for the authenticated profile and returns its Feed envelope.';
comment on function app.queue_feed_question_notification() is
  'Queues one followed-activity push per eligible follower for a new Feed question.';

do $$
begin
  if not exists (
    select 1 from pg_proc
    where oid = 'public.create_feed_question(text)'::regprocedure
      and prosecdef
      and provolatile = 'v'
      and 'search_path=pg_catalog, public, app' = any(coalesce(proconfig, array[]::text[]))
  ) then
    raise exception 'public.create_feed_question security posture changed';
  end if;

  if not has_function_privilege('authenticated', 'public.create_feed_question(text)', 'execute')
     or has_function_privilege('anon', 'public.create_feed_question(text)', 'execute')
     or has_function_privilege('authenticated', 'app.queue_feed_question_notification()', 'execute') then
    raise exception 'question function grants are invalid';
  end if;
end;
$$;

commit;
