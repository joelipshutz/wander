begin;

-- REC-497: repeat Wannas are independent events. Never update user_places:
-- its Been/Wanna status, ratings, dates, and unique-place counters stay authoritative.
create table public.place_wanna_saves (
  id uuid primary key references public.feed_events(id) on delete cascade,
  user_place_id uuid not null references public.user_places(id) on delete cascade,
  visibility text not null check (visibility in ('followers', 'mutuals', 'self')),
  note text,
  planned_date date,
  attribute_answers jsonb not null default '[]'::jsonb
    check (jsonb_typeof(attribute_answers) = 'array'),
  occurred_at timestamptz not null default now()
);
create index place_wanna_saves_parent_date_idx
  on public.place_wanna_saves(user_place_id, occurred_at desc, id);
alter table public.place_wanna_saves enable row level security;
revoke all on public.place_wanna_saves from public, anon, authenticated;

-- Internal helpers deliberately use definer rights to read the private event
-- table. No client may call them; exposed RPCs below derive the viewer from JWT.
create function app.place_wanna_save_json(input_id uuid)
returns jsonb language sql stable security definer
set search_path = pg_catalog, public, app
as $$
  select jsonb_build_object(
    'id', wanna.id, 'owner_id', parent.user_id, 'user_place_id', parent.id,
    'occurred_at', wanna.occurred_at, 'note', wanna.note,
    'visibility', wanna.visibility, 'planned_date', wanna.planned_date,
    'attribute_answers_json', wanna.attribute_answers::text)
  from public.place_wanna_saves wanna
  join public.user_places parent on parent.id = wanna.user_place_id
  where wanna.id = input_id
$$;
revoke all on function app.place_wanna_save_json(uuid) from public, anon, authenticated;

create function public.save_own_place_wanna(input_user_place_id uuid, input_wanna jsonb)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, app
as $$
declare
  viewer_id text := app.current_user_id();
  parent public.user_places;
  requested_id uuid;
  requested_at timestamptz;
  requested_visibility text;
  existing_parent uuid;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  select * into parent from public.user_places
    where id = input_user_place_id and user_id = viewer_id and deleted_at is null
    for update;
  if parent.id is null then raise exception 'invalid_user_place_identity'; end if;
  if jsonb_typeof(input_wanna) is distinct from 'object' then
    raise exception 'invalid_wanna_payload';
  end if;
  requested_id := (input_wanna->>'id')::uuid;
  requested_at := (input_wanna->>'occurred_at')::timestamptz;
  requested_visibility := input_wanna->>'visibility';
  if requested_id is null or requested_at is null or requested_at > now() + interval '5 minutes'
     or requested_visibility is null or requested_visibility not in ('followers', 'mutuals', 'self')
     or jsonb_typeof(coalesce(input_wanna->'attribute_answers', '[]'::jsonb)) <> 'array' then
    raise exception 'invalid_wanna_payload';
  end if;
  if (select is_private_profile from public.profiles where id = viewer_id) then
    requested_visibility := 'self';
  end if;
  select user_place_id into existing_parent from public.place_wanna_saves where id = requested_id;
  if found then
    if existing_parent <> parent.id then raise exception 'wanna_identity_conflict'; end if;
    return app.place_wanna_save_json(requested_id);
  end if;
  insert into public.feed_events(id, actor_user_id, event_type, user_place_id, place_id, occurred_at)
    values(requested_id, viewer_id, 'place_want_to_go', parent.id, parent.place_id, requested_at);
  insert into public.place_wanna_saves(id, user_place_id, visibility, note, planned_date,
                                     attribute_answers, occurred_at)
    values(requested_id, parent.id, requested_visibility, nullif(input_wanna->>'note', ''),
           (input_wanna->>'planned_date')::date,
           coalesce(input_wanna->'attribute_answers', '[]'::jsonb), requested_at);
  return app.place_wanna_save_json(requested_id);
end;
$$;
revoke all on function public.save_own_place_wanna(uuid, jsonb) from public, anon;
grant execute on function public.save_own_place_wanna(uuid, jsonb) to authenticated;

create function public.visible_place_wannas(input_user_place_ids uuid[])
returns setof jsonb language sql stable security definer
set search_path = pg_catalog, public, app
as $$
  select app.place_wanna_save_json(wanna.id)
  from public.place_wanna_saves wanna
  where wanna.user_place_id = any(input_user_place_ids)
    and app.can_read_activity_event(app.current_user_id(), wanna.id)
  order by wanna.occurred_at desc, wanna.id
$$;
revoke all on function public.visible_place_wannas(uuid[]) from public, anon;
grant execute on function public.visible_place_wannas(uuid[]) to authenticated;

-- Preserve all existing block, private-profile, source visibility, visit and
-- list gates. An event can be more restrictive than its parent, never broader.
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
        and not exists (
          select 1 from public.place_wanna_saves wanna
          where wanna.id = event.id
            and not app.can_read_user_place(input_viewer_id, event.actor_user_id, wanna.visibility)
        )
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
        )
    )
$$;

revoke all on function app.can_read_activity_event(text, uuid)
  from public, anon, authenticated;

comment on function app.can_read_activity_event(text, uuid) is
  'Returns whether a viewer can engage with an immutable Feed event, including current block, profile privacy, source-place, visit, and list visibility.';

-- Event-specific notes never borrow the parent check-in's private text.
create function app.feed_wanna_place_projection(input_user_place_id uuid, input_visit_id uuid, input_event_id uuid)
returns jsonb language sql stable security definer
set search_path = pg_catalog, public, app
as $$
  select app.feed_place_projection(input_user_place_id, input_visit_id)
    || coalesce((select jsonb_build_object('note', wanna.note, 'rating_score', null)
                 from public.place_wanna_saves wanna where wanna.id = input_event_id), '{}'::jsonb)
$$;
revoke all on function app.feed_wanna_place_projection(uuid, uuid, uuid) from public, anon, authenticated;

-- Same signature, volatility, search_path and grants as the existing Feed RPC.
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
        and app.can_read_activity_event(viewer_id, event.id)
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
        app.feed_wanna_place_projection(page.user_place_id, page.visit_id, page.id) as place_json,
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
        app.feed_wanna_place_projection(event.user_place_id, event.visit_id, event.id) as place_json,
        actor.display_name
      from eligible_events event
      join public.profiles actor on actor.id = event.actor_user_id
      where event.place_id is not null
        and app.feed_wanna_place_projection(event.user_place_id, event.visit_id, event.id) is not null
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

revoke all on function app.followed_feed(text, integer) from public, anon;
grant execute on function app.followed_feed(text, integer) to authenticated;

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
    'place', app.feed_wanna_place_projection(event.user_place_id, event.visit_id, event.id),
    'list', app.feed_list_projection(event.list_id),
    'note', case
      when event.event_type = 'list_created'
        then app.feed_list_projection(event.list_id)->>'description'
      else app.feed_wanna_place_projection(event.user_place_id, event.visit_id, event.id)->>'note'
    end,
    'rating', case
      when event.event_type in ('place_been', 'list_item_added')
        then (app.feed_wanna_place_projection(event.user_place_id, event.visit_id, event.id)->>'rating_score')::double precision
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

revoke all on function public.activity_detail(uuid) from public, anon;
grant execute on function public.activity_detail(uuid) to authenticated;

comment on function public.activity_detail(uuid) is
  'Returns one visibility-filtered Feed activity envelope for exact-ticket navigation.';

commit;
