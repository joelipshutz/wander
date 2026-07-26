begin;

-- "Check-in" is product vocabulary. The durable parent status remains `been`
-- and each ticket is a place_visits row.
alter table public.user_places
  add column if not exists historical_want_note text,
  add column if not exists historical_want_attribute_answers jsonb,
  add column if not exists historical_want_tags text[],
  add column if not exists historical_wanted_at timestamptz;

alter table public.user_places
  drop constraint if exists user_places_historical_want_attribute_answers_check;
alter table public.user_places
  add constraint user_places_historical_want_attribute_answers_check check (
    historical_want_attribute_answers is null
    or jsonb_typeof(historical_want_attribute_answers) = 'array'
  );

alter table public.feed_events
  add column if not exists visit_id uuid
    references public.place_visits(id) on delete cascade;

alter table public.feed_events
  drop constraint if exists feed_events_check;
alter table public.feed_events
  add constraint feed_events_subject_check check (
    (
      event_type in ('place_saved', 'place_been', 'place_want_to_go')
      and user_place_id is not null
      and place_id is not null
      and list_id is null
      and list_item_id is null
      and (event_type = 'place_been' or visit_id is null)
    )
    or (
      event_type = 'list_created'
      and user_place_id is null
      and place_id is null
      and visit_id is null
      and list_id is not null
      and list_item_id is null
    )
    or (
      event_type = 'list_item_added'
      and user_place_id is not null
      and place_id is not null
      and visit_id is null
      and list_id is not null
      and list_item_id is not null
    )
  );

create unique index if not exists feed_events_explicit_visit_unique_idx
  on public.feed_events(visit_id)
  where visit_id is not null
    and event_type = 'place_been';

-- Explicit check-ins have their own feed event. Suppress the compatibility
-- parent event inside save_own_check_in so one action never emits two entries.
create or replace function app.record_user_place_feed_event()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
declare
  resolved_event_type text;
begin
  if new.deleted_at is not null then
    return new;
  end if;

  if current_setting('app.explicit_check_in', true) = 'on' then
    return new;
  end if;

  if tg_op = 'UPDATE'
    and old.deleted_at is null
    and not (old.status = 'wanna_go' and new.status = 'been') then
    return new;
  end if;

  resolved_event_type := case
    when new.source_type = 'social_save' then 'place_saved'
    when new.status = 'been' then 'place_been'
    else 'place_want_to_go'
  end;

  perform app.record_feed_event(
    new.user_id,
    resolved_event_type,
    new.id,
    new.place_id
  );

  return new;
end;
$$;

create or replace function app.record_explicit_check_in_feed_event()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
declare
  parent public.user_places;
begin
  if new.deleted_at is not null or new.backfilled_from_user_place then
    return new;
  end if;

  select *
  into parent
  from public.user_places
  where id = new.user_place_id
    and deleted_at is null;

  if parent.id is null then
    return new;
  end if;

  insert into public.feed_events (
    actor_user_id,
    event_type,
    user_place_id,
    place_id,
    visit_id,
    occurred_at
  )
  values (
    parent.user_id,
    'place_been',
    parent.id,
    parent.place_id,
    new.id,
    now()
  )
  on conflict (visit_id)
    where visit_id is not null and event_type = 'place_been'
    do nothing;

  return new;
end;
$$;

drop trigger if exists place_visits_record_feed_activity on public.place_visits;
create trigger place_visits_record_feed_activity
  after insert on public.place_visits
  for each row execute function app.record_explicit_check_in_feed_event();

-- The iOS client supplies one stable UUID per ticket. This function is the
-- atomic, idempotent write boundary for first, repeat, edited, and retried
-- check-ins. The caller can never choose another user's parent row.
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
    null
  )
  on conflict (id)
  do update set
    visited_at = excluded.visited_at,
    note = excluded.note,
    rating_score = excluded.rating_score,
    attribute_answers = excluded.attribute_answers,
    deleted_at = null,
    updated_at = now()
  returning * into saved_visit;

  update public.place_visits
  set deleted_at = coalesce(deleted_at, now()),
      updated_at = now()
  where user_place_id = saved_parent.id
    and backfilled_from_user_place
    and deleted_at is null;

  return jsonb_build_object(
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

create or replace function public.save_own_check_in(
  input_place jsonb,
  input_user_place jsonb,
  input_attributes jsonb default '[]'::jsonb,
  input_visit jsonb default '{}'::jsonb,
  input_historical_want jsonb default null
)
returns jsonb
language sql
security invoker
set search_path = app, public
as $$
  select app.save_own_check_in(
    input_place,
    input_user_place,
    input_attributes,
    input_visit,
    input_historical_want
  );
$$;

-- Last-ticket deletion restores a durable historical Wanna snapshot when one
-- exists; otherwise it removes the parent save. Remaining tickets keep `been`.
create or replace function app.sync_user_place_after_place_visit_delete()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
declare
  parent public.user_places;
  latest_visit public.place_visits;
  attr jsonb;
  attr_question_definition_id uuid;
begin
  select *
  into latest_visit
  from public.place_visits pv
  where pv.user_place_id = old.user_place_id
    and pv.deleted_at is null
  order by pv.visited_at desc, pv.created_at desc, pv.id desc
  limit 1;

  if latest_visit.id is not null then
    update public.user_places
    set status = 'been',
        note = latest_visit.note,
        rating_score = latest_visit.rating_score,
        visited_at = latest_visit.visited_at,
        deleted_at = null,
        updated_at = now()
    where id = old.user_place_id;

    delete from public.place_attributes
    where user_place_id = old.user_place_id;

    for attr in
      select value
      from jsonb_array_elements(
        coalesce(latest_visit.attribute_answers, '[]'::jsonb)
      ) as value
    loop
      select qd.id
      into attr_question_definition_id
      from public.question_definitions qd
      join public.user_places up on up.id = old.user_place_id
      where qd.question_key = nullif(attr->>'question_key', '')
        and (qd.owner_user_id = up.user_id or qd.is_system)
      order by (qd.owner_user_id = up.user_id) desc, qd.is_system desc
      limit 1;

      if nullif(attr->>'question_key', '') is not null
        and nullif(attr->>'value_type', '') is not null
        and attr ? 'value'
        and attr->'value' <> 'null'::jsonb then
        insert into public.place_attributes (
          user_place_id,
          question_definition_id,
          question_key,
          value_type,
          value
        )
        values (
          old.user_place_id,
          attr_question_definition_id,
          attr->>'question_key',
          attr->>'value_type',
          attr->'value'
        )
        on conflict (user_place_id, question_key)
        do update set
          question_definition_id = excluded.question_definition_id,
          value_type = excluded.value_type,
          value = excluded.value,
          updated_at = now();
      end if;
    end loop;

    return old;
  end if;

  select *
  into parent
  from public.user_places
  where id = old.user_place_id
  for update;

  if parent.id is null then
    return old;
  end if;

  if parent.historical_wanted_at is not null then
    update public.user_places
    set status = 'wanna_go',
        note = historical_want_note,
        rating_signal = null,
        rating_score = null,
        visited_at = null,
        saved_at = historical_wanted_at,
        planned_date = null,
        deleted_at = null,
        historical_want_note = null,
        historical_want_attribute_answers = null,
        historical_want_tags = null,
        historical_wanted_at = null,
        updated_at = now()
    where id = parent.id;

    delete from public.place_attributes
    where user_place_id = parent.id;

    for attr in
      select value
      from jsonb_array_elements(
        coalesce(parent.historical_want_attribute_answers, '[]'::jsonb)
      ) as value
    loop
      select qd.id
      into attr_question_definition_id
      from public.question_definitions qd
      where qd.question_key = nullif(attr->>'question_key', '')
        and (qd.owner_user_id = parent.user_id or qd.is_system)
      order by (qd.owner_user_id = parent.user_id) desc, qd.is_system desc
      limit 1;

      if nullif(attr->>'question_key', '') is not null
        and nullif(attr->>'value_type', '') is not null
        and attr ? 'value'
        and attr->'value' <> 'null'::jsonb then
        insert into public.place_attributes (
          user_place_id,
          question_definition_id,
          question_key,
          value_type,
          value
        )
        values (
          parent.id,
          attr_question_definition_id,
          attr->>'question_key',
          attr->>'value_type',
          attr->'value'
        )
        on conflict (user_place_id, question_key)
        do update set
          question_definition_id = excluded.question_definition_id,
          value_type = excluded.value_type,
          value = excluded.value,
          updated_at = now();
      end if;
    end loop;
  else
    update public.user_places
    set deleted_at = coalesce(deleted_at, now()),
        rating_score = null,
        visited_at = null,
        updated_at = now()
    where id = parent.id
      and status = 'been';
  end if;

  return old;
end;
$$;

create or replace function app.delete_own_check_in(input_visit_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  target public.place_visits;
  parent public.user_places;
  transition text;
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;

  select visit.*
  into target
  from public.place_visits visit
  where visit.id = input_visit_id;

  if target.id is null then
    return jsonb_build_object(
      'visit_id', input_visit_id,
      'user_place_id', null,
      'transition', 'removed'
    );
  end if;

  select *
  into parent
  from public.user_places
  where id = target.user_place_id;

  if parent.user_id is distinct from viewer_id then
    raise exception 'not_owner';
  end if;

  delete from public.place_visits
  where id = target.id;

  select *
  into parent
  from public.user_places
  where id = target.user_place_id;

  transition := case
    when parent.deleted_at is not null then 'removed'
    when parent.status = 'wanna_go' then 'wanna_go'
    else 'been'
  end;

  return jsonb_build_object(
    'visit_id', target.id,
    'user_place_id', target.user_place_id,
    'transition', transition
  );
end;
$$;

create or replace function public.delete_own_check_in(input_visit_id uuid)
returns jsonb
language sql
security invoker
set search_path = app, public
as $$
  select app.delete_own_check_in(input_visit_id);
$$;

-- Backfills and historical/imported check-ins can appear in Feed, but only a
-- current-day explicit check-in generates a push.
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
  if new.deleted_at is not null
    or new.backfilled_from_user_place
    or new.visited_at < date_trunc('day', now())
    or new.visited_at > now() then
    return new;
  end if;

  select up.user_id, up.place_id, up.visibility, place.canonical_name,
         profile.display_name, profile.handle
  into activity
  from public.user_places up
  join public.places place on place.id = up.place_id
  join public.profiles profile on profile.id = up.user_id and profile.deleted_at is null
  where up.id = new.user_place_id
    and up.deleted_at is null
    and up.status = 'been';

  if activity.user_id is null then return new; end if;
  actor_name := coalesce(nullif(btrim(activity.display_name), ''), '@' || activity.handle);

  for follower in
    select follow.follower_user_id
    from public.follows follow
    where follow.followed_user_id = activity.user_id
      and app.can_read_user_place(follow.follower_user_id, activity.user_id, activity.visibility)
  loop
    perform app.queue_notification_event(
      input_recipient_user_id := follower.follower_user_id,
      input_actor_user_id := activity.user_id,
      input_notification_type := 'followed_place_visit',
      input_title := actor_name || ' checked in',
      input_body := activity.canonical_name,
      input_deeplink_url := 'recme://places/' || activity.place_id,
      input_data := jsonb_build_object(
        'visit_id', new.id,
        'user_place_id', new.user_place_id,
        'place_id', activity.place_id,
        'actor_user_id', activity.user_id
      ),
      input_dedupe_key := 'followed_place_visit:' || new.id || ':' || follower.follower_user_id,
      input_not_before := now() + interval '2 minutes'
    );
  end loop;
  return new;
end;
$$;

revoke all on function app.record_explicit_check_in_feed_event() from public, anon, authenticated;
revoke all on function app.save_own_check_in(jsonb, jsonb, jsonb, jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.save_own_check_in(jsonb, jsonb, jsonb, jsonb, jsonb) from public, anon;
revoke all on function app.delete_own_check_in(uuid) from public, anon, authenticated;
revoke all on function public.delete_own_check_in(uuid) from public, anon;
revoke all on function app.sync_user_place_after_place_visit_delete() from public, anon, authenticated;
revoke all on function app.notify_followed_place_visit_insert() from public, anon, authenticated;

grant execute on function public.save_own_check_in(jsonb, jsonb, jsonb, jsonb, jsonb) to authenticated;
grant execute on function public.delete_own_check_in(uuid) to authenticated;
grant execute on function app.save_own_check_in(jsonb, jsonb, jsonb, jsonb, jsonb) to authenticated;
grant execute on function app.delete_own_check_in(uuid) to authenticated;

comment on function public.save_own_check_in(jsonb, jsonb, jsonb, jsonb, jsonb) is
  'Atomically and idempotently saves the authenticated user place plus one explicit check-in ticket.';
comment on function public.delete_own_check_in(uuid) is
  'Deletes one owned check-in and atomically restores historical Wanna state or removes the final parent.';
comment on column public.feed_events.visit_id is
  'Optional explicit check-in subject. Cascades the feed event when its ticket is deleted.';

commit;
