begin;

-- Feed projections resolve explicit check-in events from their ticket row so
-- editing a later check-in never rewrites the note, rating, or date displayed
-- for an earlier event.
create or replace function app.feed_place_projection(
  input_user_place_id uuid,
  input_visit_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path = public, app
as $$
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
    'note', coalesce(source_visit.note, source_place.note),
    'visited_at', coalesce(source_visit.visited_at, source_place.visited_at),
    'saved_at', source_place.saved_at,
    'created_at', source_place.created_at,
    'updated_at', coalesce(source_visit.updated_at, source_place.updated_at),
    'rating_signal', source_place.rating_signal,
    'rating_score', coalesce(source_visit.rating_score, source_place.rating_score),
    'recommended_score', null,
    'recommended_count', 0,
    'category_override', source_place.category_override,
    'subcategory_override', source_place.subcategory_override,
    'category_override_source', source_place.category_override_source,
    'category_override_confidence', source_place.category_override_confidence,
    'source_type', source_place.source_type,
    'attributes', '[]'::jsonb
  )
  from public.user_places source_place
  join public.places place on place.id = source_place.place_id
  join public.profiles owner on owner.id = source_place.user_id
  left join public.place_visits source_visit
    on source_visit.id = input_visit_id
    and source_visit.user_place_id = source_place.id
    and source_visit.deleted_at is null
  where source_place.id = input_user_place_id
    and source_place.deleted_at is null
    and (
      input_visit_id is null
      or source_visit.id is not null
    )
$$;

create or replace function app.feed_list_projection(input_list_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, app
as $$
  select jsonb_build_object(
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
  )
  from public.place_lists list
  where list.id = input_list_id
    and list.deleted_at is null
$$;

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

revoke all on function app.feed_place_projection(uuid, uuid) from public, anon, authenticated;
revoke all on function app.feed_list_projection(uuid) from public, anon, authenticated;
revoke all on function app.followed_feed(text, integer) from public, anon;
grant execute on function app.followed_feed(text, integer) to authenticated;

comment on function app.feed_place_projection(uuid, uuid) is
  'Projects a feed place from its explicit check-in ticket when visit_id is present.';

commit;
