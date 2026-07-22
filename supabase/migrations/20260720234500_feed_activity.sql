begin;

-- Feed events are immutable facts. The projection below deliberately evaluates
-- current graph and visibility state, so a later block, privacy change,
-- or deleted source immediately removes an old event from a viewer's feed.
create table public.feed_events (
  id uuid primary key default gen_random_uuid(),
  actor_user_id text not null references public.profiles(id) on delete cascade,
  event_type text not null check (
    event_type in (
      'place_saved',
      'place_been',
      'place_want_to_go',
      'list_created',
      'list_item_added'
    )
  ),
  user_place_id uuid references public.user_places(id) on delete set null,
  place_id uuid references public.places(id) on delete set null,
  list_id uuid references public.place_lists(id) on delete set null,
  list_item_id uuid references public.place_list_items(id) on delete set null,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  check (
    (
      event_type in ('place_saved', 'place_been', 'place_want_to_go')
      and user_place_id is not null
      and place_id is not null
      and list_id is null
      and list_item_id is null
    )
    or (
      event_type = 'list_created'
      and user_place_id is null
      and place_id is null
      and list_id is not null
      and list_item_id is null
    )
    or (
      event_type = 'list_item_added'
      and user_place_id is not null
      and place_id is not null
      and list_id is not null
      and list_item_id is not null
    )
  )
);

create index feed_events_actor_occurred_idx
  on public.feed_events (actor_user_id, occurred_at desc, id desc);

create index feed_events_place_occurred_idx
  on public.feed_events (place_id, occurred_at desc, id desc)
  where place_id is not null;

alter table public.feed_events enable row level security;

revoke all on table public.feed_events from public, anon, authenticated;

create function app.record_feed_event(
  input_actor_user_id text,
  input_event_type text,
  input_user_place_id uuid default null,
  input_place_id uuid default null,
  input_list_id uuid default null,
  input_list_item_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public, app
as $$
begin
  insert into public.feed_events (
    actor_user_id,
    event_type,
    user_place_id,
    place_id,
    list_id,
    list_item_id
  )
  values (
    input_actor_user_id,
    input_event_type,
    input_user_place_id,
    input_place_id,
    input_list_id,
    input_list_item_id
  );
end;
$$;

create function app.record_user_place_feed_event()
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

create function app.record_place_list_feed_event()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
begin
  if new.deleted_at is null then
    perform app.record_feed_event(
      new.owner_user_id,
      'list_created',
      null,
      null,
      new.id,
      null
    );
  end if;

  return new;
end;
$$;

create function app.record_place_list_item_feed_event()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
declare
  source_user_place_id uuid;
begin
  if new.deleted_at is not null then
    return new;
  end if;

  if tg_op = 'UPDATE' and old.deleted_at is null then
    return new;
  end if;

  source_user_place_id := coalesce(new.owner_user_place_id, new.source_user_place_id);
  if source_user_place_id is null then
    return new;
  end if;

  perform app.record_feed_event(
    new.added_by_user_id,
    'list_item_added',
    source_user_place_id,
    new.place_id,
    new.list_id,
    new.id
  );

  return new;
end;
$$;

drop trigger if exists user_places_record_feed_activity on public.user_places;
create trigger user_places_record_feed_activity
  after insert or update of status, deleted_at on public.user_places
  for each row execute function app.record_user_place_feed_event();

drop trigger if exists place_lists_record_feed_activity on public.place_lists;
create trigger place_lists_record_feed_activity
  after insert on public.place_lists
  for each row execute function app.record_place_list_feed_event();

drop trigger if exists place_list_items_record_feed_activity on public.place_list_items;
create trigger place_list_items_record_feed_activity
  after insert or update of deleted_at on public.place_list_items
  for each row execute function app.record_place_list_item_feed_event();

create function app.followed_feed(
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
        event.list_id,
        event.list_item_id,
        event.occurred_at
      from public.feed_events event
      join public.profiles actor on actor.id = event.actor_user_id
      where actor.deleted_at is null
        and not coalesce(actor.is_private_profile, false)
        and exists (
          select 1
          from public.follows follow
          where follow.follower_user_id = viewer_id
            and follow.followed_user_id = event.actor_user_id
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
                and app.can_read_user_place(viewer_id, source_place.user_id, source_place.visibility)
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
                and app.can_read_user_place(viewer_id, source_place.user_id, source_place.visibility)
            )
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
          'relationship', 'follower'
        ) as actor_json,
        place_projection.place_json,
        list_projection.list_json,
        case
          when page.event_type = 'list_created' then list_projection.list_description
          else place_projection.place_note
        end as note,
        case
          when page.event_type in ('place_been', 'list_item_added') then place_projection.rating_score
          else null
        end as rating
      from page
      join public.profiles actor on actor.id = page.actor_user_id
      left join lateral (
        select
          source_place.note as place_note,
          source_place.rating_score::double precision as rating_score,
          jsonb_build_object(
            'user_place_id', source_place.id,
            'place_id', place.id,
            'owner_user_id', source_place.user_id,
            'owner_handle', owner.handle,
            'owner_display_name', owner.display_name,
            'owner_avatar_url', owner.avatar_url,
            'canonical_name', place.canonical_name,
            'category', coalesce(source_place.category_override, place.primary_category, place.category),
            'primary_category', coalesce(place.primary_category, place.category),
            'subcategory', place.subcategory,
            'category_source', place.category_source,
            'category_confidence', place.category_confidence,
            'raw_provider_type', place.raw_provider_type,
            'address', place.address,
            'locality', place.locality,
            'region', place.region,
            'country', place.country,
            'time_zone_identifier', null,
            'latitude', place.latitude,
            'longitude', place.longitude,
            'status', source_place.status,
            'visibility', source_place.visibility,
            'note', source_place.note,
            'visited_at', source_place.visited_at,
            'saved_at', source_place.saved_at,
            'created_at', source_place.created_at,
            'updated_at', source_place.updated_at,
            'rating_signal', source_place.rating_signal,
            'rating_score', source_place.rating_score,
            'recommended_score', null,
            'recommended_count', 0,
            'category_override', source_place.category_override,
            'subcategory_override', source_place.subcategory_override,
            'category_override_source', source_place.category_override_source,
            'category_override_confidence', source_place.category_override_confidence,
            'source_type', source_place.source_type,
            'attributes', '[]'::jsonb
          ) as place_json
        from public.user_places source_place
        join public.places place on place.id = source_place.place_id
        join public.profiles owner on owner.id = source_place.user_id
        where source_place.id = page.user_place_id
          and source_place.deleted_at is null
      ) as place_projection on true
      left join lateral (
        select
          list.description as list_description,
          jsonb_build_object(
            'id', list.id,
            'owner_user_id', list.owner_user_id,
            'name', list.name,
            'description', list.description,
            'visibility', list.visibility,
            'item_count', (
              select count(*)::integer
              from public.place_list_items item
              where item.list_id = list.id
                and item.deleted_at is null
            ),
            'created_at', list.created_at,
            'updated_at', list.updated_at
          ) as list_json
        from public.place_lists list
        where list.id = page.list_id
          and list.deleted_at is null
      ) as list_projection on true
    ),
    rendered_featured as (
      select distinct on (event.place_id)
        event.place_id,
        event.occurred_at,
        event.id,
        place_projection.place_json,
        actor.display_name
      from eligible_events event
      join public.profiles actor on actor.id = event.actor_user_id
      join lateral (
        select jsonb_build_object(
          'user_place_id', source_place.id,
          'place_id', place.id,
          'owner_user_id', source_place.user_id,
          'owner_handle', owner.handle,
          'owner_display_name', owner.display_name,
          'owner_avatar_url', owner.avatar_url,
          'canonical_name', place.canonical_name,
          'category', coalesce(source_place.category_override, place.primary_category, place.category),
          'primary_category', coalesce(place.primary_category, place.category),
          'subcategory', place.subcategory,
          'category_source', place.category_source,
          'category_confidence', place.category_confidence,
          'raw_provider_type', place.raw_provider_type,
          'address', place.address,
          'locality', place.locality,
          'region', place.region,
          'country', place.country,
          'time_zone_identifier', null,
          'latitude', place.latitude,
          'longitude', place.longitude,
          'status', source_place.status,
          'visibility', source_place.visibility,
          'note', source_place.note,
          'visited_at', source_place.visited_at,
          'saved_at', source_place.saved_at,
          'created_at', source_place.created_at,
          'updated_at', source_place.updated_at,
          'rating_signal', source_place.rating_signal,
          'rating_score', source_place.rating_score,
          'recommended_score', null,
          'recommended_count', 0,
          'category_override', source_place.category_override,
          'subcategory_override', source_place.subcategory_override,
          'category_override_source', source_place.category_override_source,
          'category_override_confidence', source_place.category_override_confidence,
          'source_type', source_place.source_type,
          'attributes', '[]'::jsonb
        ) as place_json
        from public.user_places source_place
        join public.places place on place.id = source_place.place_id
        join public.profiles owner on owner.id = source_place.user_id
        where source_place.id = event.user_place_id
          and source_place.deleted_at is null
      ) as place_projection on true
      where event.place_id is not null
        and place_projection.place_json is not null
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
              'note', note,
              'rating', rating,
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
              'reason', format('Saved by %s', display_name)
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

create function public.followed_feed(
  input_before text default null,
  input_limit integer default 25
)
returns jsonb
language sql
stable
security invoker
set search_path = app, public
as $$
  select app.followed_feed(input_before, input_limit);
$$;

revoke all on function app.record_feed_event(text, text, uuid, uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function app.record_user_place_feed_event() from public, anon, authenticated;
revoke all on function app.record_place_list_feed_event() from public, anon, authenticated;
revoke all on function app.record_place_list_item_feed_event() from public, anon, authenticated;
revoke all on function app.followed_feed(text, integer) from public, anon;
revoke all on function public.followed_feed(text, integer) from public, anon;
grant execute on function public.followed_feed(text, integer) to authenticated;

comment on function public.followed_feed(text, integer) is
  'Returns newest-first activity from accounts followed by the current viewer, applying current block, privacy, list, and place visibility at read time.';

commit;
