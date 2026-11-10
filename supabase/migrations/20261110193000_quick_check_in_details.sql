begin;

-- REC-680: a quick capture is a real visit whose optional details can be added later.
-- Existing rows retain their ratings and are never enrolled in reminders.
alter table public.place_visits add column details_pending boolean not null default false;
grant select (details_pending) on public.place_visits to authenticated;
alter table public.notification_preferences add column check_in_reminders_enabled boolean not null default true;

-- Cold owner hydration retains invitation state and original capture time across
-- devices. Preserve SECURITY INVOKER, STABLE and the RLS-filtered owner scope.
create or replace function public.current_user_calendar_snapshot()
returns jsonb
language sql
stable
security invoker
set search_path = public, app
as $$
  with viewer as (
    select app.current_user_id() as id
  ),
  place_rows as materialized (
    select place_row.*
    from viewer
    cross join lateral public.profile_visible_places(viewer.id, null, null) place_row
    where viewer.id is not null
  ),
  visit_rows as materialized (
    select
      visit.id,
      visit.user_place_id,
      visit.visited_at,
      visit.note,
      visit.rating_score::double precision as rating_score,
      visit.details_pending,
      visit.created_at,
      visit.updated_at,
      visit.tags,
      visit.backfilled_from_user_place
    from public.place_visits visit
    join place_rows place_row on place_row.user_place_id = visit.user_place_id
    where visit.deleted_at is null
  )
  select jsonb_build_object(
    'places',
    coalesce(
      (
        select jsonb_agg(to_jsonb(place_row) order by place_row.updated_at desc)
        from place_rows place_row
      ),
      '[]'::jsonb
    ),
    'visits',
    coalesce(
      (
        select jsonb_agg(
          to_jsonb(visit_row)
          order by visit_row.user_place_id, visit_row.visited_at desc, visit_row.id
        )
        from visit_rows visit_row
      ),
      '[]'::jsonb
    )
  );
$$;

revoke all on function public.current_user_calendar_snapshot() from public, anon;
grant execute on function public.current_user_calendar_snapshot() to authenticated;

-- Internal daily reservation: one event per recipient/local calendar day, including
-- concurrent workers and retries. A failed delivery consumes that day's allowance.
create table app.check_in_reminder_days (
  user_id text not null references public.profiles(id) on delete cascade,
  local_day date not null,
  event_id uuid not null references public.notification_events(id) on delete cascade,
  primary key (user_id, local_day)
);
alter table app.check_in_reminder_days enable row level security;
revoke all on app.check_in_reminder_days from public, anon, authenticated;


alter table public.notification_events drop constraint notification_events_notification_type_check;
alter table public.notification_events add constraint notification_events_notification_type_check check (notification_type in ('followed_you','mutual_follow','list_collaborator_added','list_place_added','place_saved_from_your_map','capture_ready','followed_activity_digest','followed_place_visit','shared_visit','activity_liked','activity_commented','import_finished','wanna_go_reminder','save_streak_reminder','calendar_reservation_live','calendar_reservation_follow_up','circle_question_tagged','check_in_reminder'));

-- Preserve the established definer ABI, volatility, pinned search paths and
-- grants. These internal helpers read protected preferences/sources across roles;
-- caller-scoped public writes continue to derive identity from app.current_user_id().

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
      when input_notification_type in ('place_saved_from_your_map','circle_question_tagged') then input_preferences.recommendations_enabled
      when input_notification_type in ('capture_ready', 'import_finished') then input_preferences.capture_enabled
      when input_notification_type = 'followed_activity_digest' then input_preferences.discovery_digest_enabled
      when input_notification_type = 'followed_place_visit' then input_preferences.followed_activity_enabled
      when input_notification_type in ('activity_liked', 'activity_commented') then input_preferences.engagement_enabled
      when input_notification_type = 'check_in_reminder' then input_preferences.check_in_reminders_enabled
      when input_notification_type = 'wanna_go_reminder' then input_preferences.wanna_go_reminders_enabled
      when input_notification_type = 'save_streak_reminder' then true
      when input_notification_type in ('calendar_reservation_live', 'calendar_reservation_follow_up')
        then input_preferences.reservation_reminders_enabled
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
begin
  if input_recipient_user_id is null or input_recipient_user_id = '' then return null; end if;
  if input_actor_user_id is not null and input_actor_user_id = input_recipient_user_id then return null; end if;
  if input_notification_type not in (
    'check_in_reminder', 'circle_question_tagged', 'followed_you', 'mutual_follow', 'list_collaborator_added',
    'list_place_added', 'place_saved_from_your_map', 'capture_ready',
    'followed_activity_digest', 'followed_place_visit', 'shared_visit',
    'activity_liked', 'activity_commented', 'import_finished',
    'wanna_go_reminder', 'save_streak_reminder',
    'calendar_reservation_live', 'calendar_reservation_follow_up'
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

  insert into public.notification_events(
    recipient_user_id, actor_user_id, notification_type, title, body,
    deeplink_url, data, dedupe_key, not_before, expires_at, latest_at
  ) values (
    input_recipient_user_id, input_actor_user_id, input_notification_type,
    left(trim(input_title), 120), left(trim(input_body), 240),
    nullif(trim(coalesce(input_deeplink_url, '')), ''), coalesce(input_data, '{}'::jsonb),
    nullif(trim(coalesce(input_dedupe_key, '')), ''), coalesce(input_not_before, now()),
    greatest(coalesce(input_not_before, now()) + interval '24 hours', now() + interval '24 hours'),
    greatest(coalesce(input_not_before, now()) + interval '24 hours', now() + interval '24 hours')
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
    engagement_enabled = coalesce((input_preferences->>'engagement_enabled')::boolean, engagement_enabled),
    check_in_reminders_enabled = coalesce((input_preferences->>'check_in_reminders_enabled')::boolean, check_in_reminders_enabled),
    reservation_reminders_enabled = coalesce((input_preferences->>'reservation_reminders_enabled')::boolean, reservation_reminders_enabled)
  where user_id = viewer_id
  returning * into output_preferences;
  return output_preferences;
end;
$$;

-- Narrow self-reminder producer; never exposed as an RPC. Repeated saves of
-- the same UUID cannot re-enroll it. Scheduling uses capture time, not visit date.
create function app.queue_check_in_reminder(input_visit_id uuid, input_timezone text)
returns void language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare
  visit public.place_visits;
  parent public.user_places;
  fire_at timestamptz;
  local_fire timestamp;
  zone text := coalesce(input_timezone, 'UTC');
  event_id uuid;
begin
  select * into visit from public.place_visits where id = input_visit_id;
  if not found or not visit.details_pending or visit.deleted_at is not null then return; end if;
  select * into parent from public.user_places where id = visit.user_place_id and deleted_at is null;
  if not found then return; end if;
  if exists(select 1 from public.notification_events
    where dedupe_key = 'check_in_reminder:' || input_visit_id::text) then return; end if;
  if not exists(select 1 from pg_timezone_names where name = zone) then zone := 'UTC'; end if;
  if visit.created_at + interval '48 hours' <= now() then return; end if;
  fire_at := greatest(visit.created_at + interval '3 hours', now());
  local_fire := fire_at at time zone zone;
  if extract(hour from local_fire) >= 22 then
    fire_at := (date_trunc('day',local_fire) + interval '1 day 9 hours') at time zone zone;
  elsif extract(hour from local_fire) < 9 then
    fire_at := (date_trunc('day',local_fire) + interval '9 hours') at time zone zone;
  end if;
  if fire_at >= visit.created_at + interval '48 hours' then return; end if;
  event_id := app.queue_notification_event(
    parent.user_id, null, 'check_in_reminder', 'Add details to your recent check-in',
    'Add a rating, photos or a note whenever you have a moment.',
    'recme://check-in-details/' || parent.id::text || '/' || visit.id::text,
    jsonb_build_object('user_place_id',parent.id,'visit_id',visit.id),
    'check_in_reminder:' || visit.id::text, fire_at);
  if event_id is not null then
    update public.notification_events set source = 'check_in_reminder',
      recipient_timezone = zone, priority = 10,
      expires_at = visit.created_at + interval '48 hours',
      latest_at = visit.created_at + interval '48 hours'
    where id = event_id;
  end if;
end;
$$;
revoke all on function app.queue_check_in_reminder(uuid,text) from public,anon,authenticated;

-- Trigger also covers direct-table edits and deletion. Suppression happens in
-- the same transaction as the edit, including already-claimed queue entries.
create function app.resolve_check_in_reminder()
returns trigger language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
begin
  if not new.details_pending or new.deleted_at is not null then
    update public.notification_events set status = 'skipped', skip_reason = 'check_in_details_resolved',
      claim_token = null, claim_expires_at = null
    where notification_type = 'check_in_reminder' and data->>'visit_id' = new.id::text
      and status in ('pending','claimed');
  end if;
  return new;
end;
$$;
revoke all on function app.resolve_check_in_reminder() from public,anon,authenticated;
create trigger resolve_check_in_reminder after update of details_pending,deleted_at
on public.place_visits for each row execute function app.resolve_check_in_reminder();


create or replace function app.save_own_check_in(
  input_place jsonb,
  input_user_place jsonb,
  input_attributes jsonb default '[]'::jsonb,
  input_visit jsonb default '{}'::jsonb,
  input_historical_want jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  provider text;
  provider_place_id text;
  requested_user_place_id uuid;
  prior_parent public.user_places;
  prior_attributes jsonb;
  saved_parent public.user_places;
  saved_visit public.place_visits;
  requested_visit_id uuid;
  requested_visited_at timestamptz;
  requested_rating numeric;
  existing_visit public.place_visits;
  captured_historical_note text;
  captured_historical_answers jsonb;
  captured_historical_tags text[];
  captured_historical_wanted_at timestamptz;
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;
  if coalesce(jsonb_typeof(input_place), '') <> 'object' then
    raise exception 'invalid_place_payload';
  end if;
  if coalesce(jsonb_typeof(input_user_place), '') <> 'object' then
    raise exception 'invalid_user_place_payload';
  end if;
  if coalesce(jsonb_typeof(input_attributes), 'array') <> 'array' then
    raise exception 'invalid_attributes_payload';
  end if;
  if coalesce(jsonb_typeof(input_visit), '') <> 'object' then
    raise exception 'invalid_check_in_payload';
  end if;
  if input_historical_want is not null
    and jsonb_typeof(input_historical_want) <> 'object' then
    raise exception 'invalid_historical_want_payload';
  end if;
  if input_historical_want is not null
    and jsonb_typeof(coalesce(input_historical_want->'attribute_answers', '[]'::jsonb)) <> 'array' then
    raise exception 'invalid_historical_want_attributes';
  end if;
  if input_historical_want is not null
    and jsonb_typeof(coalesce(input_historical_want->'tags', '[]'::jsonb)) <> 'array' then
    raise exception 'invalid_historical_want_tags';
  end if;

  begin
    requested_visit_id := (input_visit->>'id')::uuid;
    requested_visited_at := (input_visit->>'visited_at')::timestamptz;
  exception when others then
    raise exception 'invalid_check_in_identity_or_date';
  end;
  if requested_visit_id is null or requested_visited_at is null then
    raise exception 'invalid_check_in_identity_or_date';
  end if;
  if requested_visited_at > now() then
    raise exception 'future_check_in_not_allowed';
  end if;
  if jsonb_typeof(coalesce(input_visit->'attribute_answers', '[]'::jsonb)) <> 'array' then
    raise exception 'invalid_visit_attribute_answers_payload';
  end if;

  if nullif(input_visit->>'rating_score', '') is not null then
    requested_rating := (input_visit->>'rating_score')::numeric;
  end if;
  if requested_rating is not null and (
    requested_rating < 1
    or requested_rating > 5
    or requested_rating * 2 <> trunc(requested_rating * 2)
  ) then
    raise exception 'invalid_rating_score';
  end if;

  if nullif(input_user_place->>'id', '') is not null then
    begin
      requested_user_place_id := (input_user_place->>'id')::uuid;
    exception when others then
      raise exception 'invalid_user_place_identity';
    end;

    select up.*
    into prior_parent
    from public.user_places up
    where up.id = requested_user_place_id
      and up.user_id = viewer_id
      and up.deleted_at is null
    limit 1;

    if prior_parent.id is null then
      raise exception 'invalid_user_place_identity';
    end if;

    select place.source_provider, place.source_provider_place_id
    into provider, provider_place_id
    from public.places place
    where place.id = prior_parent.place_id;

    if nullif(provider, '') is null
      or nullif(provider_place_id, '') is null then
      raise exception 'invalid_user_place_identity';
    end if;

    input_place := input_place || jsonb_build_object(
      'source_provider', provider,
      'source_provider_place_id', provider_place_id
    );
  else
    provider := coalesce(nullif(input_place->>'source_provider', ''), 'manual');
    provider_place_id := nullif(input_place->>'source_provider_place_id', '');
    if provider_place_id is null then
      provider_place_id := 'generated:' || md5(
        provider || ':' ||
        coalesce(input_place->>'canonical_name', '') || ':' ||
        coalesce(input_place->>'latitude', '') || ':' ||
        coalesce(input_place->>'longitude', '')
      );
    end if;

    select up.*
    into prior_parent
    from public.user_places up
    join public.places place on place.id = up.place_id
    where up.user_id = viewer_id
      and place.source_provider = provider
      and place.source_provider_place_id = provider_place_id
      and up.deleted_at is null
    limit 1;
  end if;

  if prior_parent.id is not null and prior_parent.status = 'wanna_go' then
    prior_attributes := app.user_place_attribute_answers(prior_parent.id);
  end if;

  perform set_config('app.explicit_check_in', 'on', true);
  select *
  into saved_parent
  from app.save_own_place(
    input_place,
    input_user_place || jsonb_build_object(
      'status', 'been',
      'planned_date', null
    ),
    input_attributes
  );

  if saved_parent.user_id <> viewer_id then
    raise exception 'not_owner';
  end if;

  if input_historical_want is not null then
    captured_historical_note := nullif(input_historical_want->>'note', '');
    captured_historical_answers := coalesce(input_historical_want->'attribute_answers', '[]'::jsonb);
    captured_historical_tags := coalesce(
      array(
        select jsonb_array_elements_text(
          coalesce(input_historical_want->'tags', '[]'::jsonb)
        )
      ),
      '{}'::text[]
    );
    begin
      captured_historical_wanted_at := (input_historical_want->>'wanted_at')::timestamptz;
    exception when others then
      raise exception 'invalid_historical_want_date';
    end;
  elsif prior_parent.id is not null and prior_parent.status = 'wanna_go' then
    captured_historical_note := prior_parent.note;
    captured_historical_answers := coalesce(prior_attributes, '[]'::jsonb);
    captured_historical_tags := app.visit_tags_from_attribute_answers(captured_historical_answers);
    captured_historical_wanted_at := coalesce(prior_parent.saved_at, prior_parent.created_at, now());
  end if;

  if captured_historical_wanted_at is not null then
    if jsonb_typeof(coalesce(captured_historical_answers, '[]'::jsonb)) <> 'array' then
      raise exception 'invalid_historical_want_attributes';
    end if;
    update public.user_places
    set historical_want_note = captured_historical_note,
        historical_want_attribute_answers = coalesce(captured_historical_answers, '[]'::jsonb),
        historical_want_tags = coalesce(captured_historical_tags, '{}'::text[]),
        historical_wanted_at = captured_historical_wanted_at
    where id = saved_parent.id
      and user_id = viewer_id
    returning * into saved_parent;
  end if;

  select *
  into existing_visit
  from public.place_visits
  where id = requested_visit_id;

  if existing_visit.id is not null
    and existing_visit.user_place_id <> saved_parent.id then
    raise exception 'check_in_id_conflict';
  end if;

  insert into public.place_visits (
    id,
    user_place_id,
    visited_at,
    note,
    rating_score,
    attribute_answers,
    backfilled_from_user_place,
    details_pending,
    created_at,
    deleted_at
  )
  values (
    requested_visit_id,
    saved_parent.id,
    requested_visited_at,
    nullif(input_visit->>'note', ''),
    requested_rating,
    coalesce(input_visit->'attribute_answers', '[]'::jsonb),
    false,
    coalesce((input_visit->>'details_pending')::boolean, false),
    least(coalesce((input_visit->>'captured_at')::timestamptz, now()), now()),
    null
  )
  on conflict (id)
  do update set
    visited_at = excluded.visited_at,
    note = excluded.note,
    rating_score = excluded.rating_score,
    attribute_answers = excluded.attribute_answers,
    -- Resolution is monotonic: an older device/retry cannot reopen a dismissed invitation.
    details_pending = public.place_visits.details_pending and excluded.details_pending,
    deleted_at = null,
    updated_at = now()
  returning * into saved_visit;

  update public.place_visits
  set deleted_at = coalesce(deleted_at, now()),
      updated_at = now()
  where user_place_id = saved_parent.id
    and backfilled_from_user_place
    and deleted_at is null;

  if existing_visit.id is null and saved_visit.details_pending then
    perform app.queue_check_in_reminder(saved_visit.id, input_visit->>'reminder_timezone');
  end if;

  return jsonb_build_object(
    'details_pending', saved_visit.details_pending,
    'created_at', saved_visit.created_at,
    'user_place_id', saved_parent.id,
    'place_id', saved_parent.place_id,
    'visit_id', saved_visit.id,
    'visited_at', saved_visit.visited_at,
    'note', saved_visit.note,
    'rating_score', saved_visit.rating_score,
    'tags', to_jsonb(saved_visit.tags),
    'backfilled_from_user_place', saved_visit.backfilled_from_user_place
  );
end;
$$;

create or replace function app.notification_source_readable(event public.notification_events)
returns boolean language plpgsql stable security definer
set search_path = pg_catalog, public, app
as $$
declare viewer text := event.recipient_user_id;
begin
  if not exists (select 1 from public.profiles where id = viewer and deleted_at is null)
    then return false; end if;
  if event.actor_user_id is not null and (
    app.is_blocked(viewer, event.actor_user_id)
    or not exists (select 1 from public.profiles where id = event.actor_user_id and deleted_at is null)
  ) then return false; end if;
  case event.notification_type
    when 'check_in_reminder' then
      return exists (
        select 1 from public.place_visits visit
        join public.user_places parent on parent.id = visit.user_place_id
        where visit.id = app.privacy_uuid(event.data->>'visit_id')
          and parent.id = app.privacy_uuid(event.data->>'user_place_id')
          and parent.user_id = viewer and parent.deleted_at is null
          and visit.deleted_at is null and visit.details_pending
          and visit.rating_score is null and nullif(trim(visit.note),'') is null
          and not exists(select 1 from public.visit_photos photo
            where photo.visit_id = visit.id and photo.deleted_at is null)
      );
    when 'circle_question_tagged' then
      return app.can_read_circle_question(viewer,app.privacy_uuid(event.data->>'question_id'));
    when 'activity_liked', 'activity_commented' then
      return app.can_read_activity_event(viewer, app.privacy_uuid(event.data->>'activity_id'));
    when 'followed_place_visit' then
      -- REC-589 batches an import behind one notification without a visit_id.
      -- Its existing helper recomputes currently readable, non-silent sources.
      -- Keep compatibility when that optional feature has not been installed.
      if event.data->>'sender_import_id' is not null then
        if to_regprocedure('app.import_notification_content(text,text,text)') is null
          or exists (select 1 from public.profiles where id=event.actor_user_id and is_private_profile) then
          return false;
        end if;
        return app.import_notification_content(event.actor_user_id, viewer,
          event.data->>'sender_import_id') is not null;
      end if;
      return app.can_read_visit_source(viewer, app.privacy_uuid(event.data->>'visit_id'));
    when 'shared_visit' then
      return exists (
        select 1 from public.shared_visit_participants participant
        join public.shared_visit_groups shared_group on shared_group.id = participant.group_id
        where participant.id = app.privacy_uuid(event.data->>'participant_id')
          and participant.user_id = viewer and participant.status = 'pending'
          and participant.invitation_generation::text = event.data->>'invitation_generation'
          and participant.invitation_snapshot is not null and shared_group.cancelled_at is null
          and app.can_read_visit_source(viewer, shared_group.source_visit_id)
      );
    when 'list_collaborator_added' then
      return app.can_read_place_list(app.privacy_uuid(event.data->>'list_id'), viewer);
    when 'list_place_added' then
      return app.can_read_place_list(app.privacy_uuid(event.data->>'list_id'), viewer)
        and exists (select 1 from public.place_list_items item
          where item.list_id = app.privacy_uuid(event.data->>'list_id')
            and item.place_id = app.privacy_uuid(event.data->>'place_id')
            and item.added_by_user_id = event.actor_user_id and item.deleted_at is null);
    when 'place_saved_from_your_map' then
      return exists (select 1 from public.user_places saved
        join public.profiles owner on owner.id = saved.user_id
        where saved.id = app.privacy_uuid(event.data->>'user_place_id')
          and saved.user_id = event.actor_user_id and saved.deleted_at is null
          and owner.deleted_at is null and not owner.is_private_profile
          and app.can_read_user_place(viewer, saved.user_id, saved.visibility));
    when 'followed_you', 'mutual_follow' then
      return exists (select 1 from public.follows
        where follower_user_id = event.actor_user_id and followed_user_id = viewer);
    when 'capture_ready', 'import_finished', 'wanna_go_reminder', 'save_streak_reminder',
         'calendar_reservation_live', 'calendar_reservation_follow_up' then
      -- These producers are authenticated owner-only or internal self-reminders.
      return event.actor_user_id is null or event.actor_user_id = viewer;
    else return false;
  end case;
end;
$$;

-- Reserve delivery under a per-recipient lock, after all other authorization
-- checks. Retries of this event may proceed; a different event cannot use the day.
create function app.reserve_check_in_reminder_day(event public.notification_events)
returns boolean language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare
  local_now timestamp;
  reserved uuid;
begin
  if event.notification_type <> 'check_in_reminder' then return true; end if;
  local_now := now() at time zone coalesce(event.recipient_timezone,'UTC');
  if extract(hour from local_now) < 9 or extract(hour from local_now) >= 22 then return false; end if;
  perform pg_advisory_xact_lock(hashtextextended('check-in-reminder:' || event.recipient_user_id,0));
  insert into app.check_in_reminder_days(user_id,local_day,event_id)
    values(event.recipient_user_id,local_now::date,event.id)
    on conflict(user_id,local_day) do nothing;
  select event_id into reserved from app.check_in_reminder_days
    where user_id = event.recipient_user_id and local_day = local_now::date;
  return reserved = event.id;
end;
$$;
revoke all on function app.reserve_check_in_reminder_day(public.notification_events) from public,anon,authenticated;


create or replace function public.authorize_push_notification_delivery(input_event_id uuid, input_claim_token uuid)
returns jsonb language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare event public.notification_events; allowed boolean; import_content jsonb;
begin
  select * into event from public.notification_events
  where id = input_event_id and status = 'claimed' and claim_token = input_claim_token
    and claim_expires_at > now() for update;
  if not found then return null; end if;
  allowed := app.notification_source_readable(event)
    and (event.source <> 'calendar_reservation' or exists (
      select 1 from public.calendar_reservations reservation
      where reservation.user_id = event.recipient_user_id
        and reservation.completed_at is null and reservation.cancelled_at is null
        and event.conflict_group = 'calendar_reservation:' || reservation.id))
    and least(event.expires_at, event.latest_at) > now()
    and exists (select 1 from public.notification_preferences preferences
      where preferences.user_id = event.recipient_user_id
        and app.notification_type_enabled(preferences, event.notification_type))
    and not exists (select 1 from public.profile_mutes
      where muter_user_id = event.recipient_user_id and muted_user_id = event.actor_user_id);
  -- A source can become hidden after queue claim. Re-render only the frozen
  -- import manifest at final authorization so detailed copy cannot name/count
  -- a revoked place. The ledger never expands to later import saves.
  if event.notification_type = 'followed_place_visit'
      and event.data->>'sender_import_id' is not null then
    import_content := app.import_notification_content(event.actor_user_id,
      event.recipient_user_id, event.data->>'sender_import_id');
    allowed := allowed and import_content is not null;
  end if;
  if coalesce(allowed, false) then
    allowed := app.reserve_check_in_reminder_day(event);
  end if;
  if not coalesce(allowed, false) then
    update public.notification_events set status = 'skipped', skip_reason = 'source_not_visible',
      claim_token = null, claim_expires_at = null, error_message = null
      where id = event.id;
    return null;
  end if;
  if import_content is not null then
    update public.notification_events
      set body = import_content->>'body',
          deeplink_url = 'recme://places/' || (import_content->>'place_id'),
          data = data || jsonb_build_object('place_id', import_content->>'place_id',
            'place_count', import_content->'place_count')
      where id = event.id
      returning * into event;
  end if;
  return jsonb_build_object(
    'event_id', event.id, 'claim_token', event.claim_token,
    'recipient_user_id', event.recipient_user_id, 'actor_user_id', event.actor_user_id,
    'notification_type', event.notification_type,
    -- Eligibility, not the presence of an actor, controls delivery. Friends and
    -- other authorized recipients receive the producer's personalized copy.
    'title', event.title,
    'body', event.body,
    'deeplink_url', event.deeplink_url,
    'data', (select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
      from jsonb_each(event.data) where key in ('question_id','activity_id','visit_id','user_place_id','place_id',
        'list_id','participant_id','invitation_generation','group_id','source_visit_id',
        'actor_user_id','event_type','reservation_id','job_id')),
    'attempt_count', event.attempt_count, 'max_attempts', event.max_attempts,
    'claim_expires_at', event.claim_expires_at,
    'tokens', (select coalesce(jsonb_agg(jsonb_build_object('id', token.id,
      'device_token', token.device_token, 'environment', token.environment,
      'app_bundle_id', token.app_bundle_id)), '[]'::jsonb)
      from public.notification_device_tokens token
      where token.user_id = event.recipient_user_id and token.is_active
        and not exists (select 1 from public.notification_push_deliveries delivery
          where delivery.event_id = event.id and delivery.token_id = token.id
            and delivery.status in ('accepted','permanent_token_failure','permanent_event_failure')))
  );
end;
$$;

-- Restate grants deliberately; no new owner-selectable write identity.
revoke all on function app.save_own_check_in(jsonb,jsonb,jsonb,jsonb,jsonb) from public,anon,authenticated;
grant execute on function app.save_own_check_in(jsonb,jsonb,jsonb,jsonb,jsonb) to authenticated;
revoke all on function public.update_notification_preferences(jsonb) from public,anon;
grant execute on function public.update_notification_preferences(jsonb) to authenticated;
revoke all on function app.queue_notification_event(text,text,text,text,text,text,jsonb,text,timestamptz) from public,anon,authenticated;
grant execute on function app.queue_notification_event(text,text,text,text,text,text,jsonb,text,timestamptz) to service_role;
revoke all on function app.notification_type_enabled(public.notification_preferences,text) from public,anon,authenticated;
revoke all on function app.notification_source_readable(public.notification_events) from public,anon,authenticated;
revoke all on function public.authorize_push_notification_delivery(uuid,uuid) from public,anon,authenticated;
grant execute on function public.authorize_push_notification_delivery(uuid,uuid) to service_role;

commit;
