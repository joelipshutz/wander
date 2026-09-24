begin;

-- REC-607: Audience is applied before the limit/cursor. Existing followed_feed
-- overloads remain untouched for older clients. This narrow read projection
-- keeps the established SECURITY DEFINER boundary because feed_events and the
-- projection helpers are not public client tables. Identity is derived only
-- from app.current_user_id(); every event/source still passes the existing
-- visibility helpers. No caller-selected viewer, writes, or new visibility rule.
-- Preserve stable JSONB output, pinned search paths, and authenticated-only RPC
-- grants from the activity-only feed contract (20260917100000).
create or replace function app.activity_feed(
  input_audience text,
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
  if input_audience is null or input_audience not in ('everyone', 'only_me', 'only_friends') then
    raise exception 'Invalid feed audience' using errcode = '22023';
  end if;

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
        and (
          (input_audience in ('everyone', 'only_me') and event.actor_user_id = viewer_id)
          or (
            input_audience in ('everyone', 'only_friends')
            and event.actor_user_id <> viewer_id
            and not coalesce(actor.is_private_profile, false)
            and exists (
              select 1 from public.follows follow
              where follow.follower_user_id = viewer_id
                and follow.followed_user_id = event.actor_user_id
            )
            and (
              input_audience = 'everyone'
              or exists (
                select 1 from public.follows reverse_follow
                where reverse_follow.follower_user_id = event.actor_user_id
                  and reverse_follow.followed_user_id = viewer_id
              )
            )
          )
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
          'relationship', case
            when actor.id = viewer_id then 'owner'
            when exists (
              select 1 from public.follows reverse_follow
              where reverse_follow.follower_user_id = actor.id
                and reverse_follow.followed_user_id = viewer_id
            ) then 'mutual'
            else 'follower'
          end
        ) as actor_json,
        app.feed_wanna_place_projection(page.user_place_id, page.visit_id, page.id) as place_json,
        app.feed_list_projection(page.list_id) as list_json
      from page
      join public.profiles actor on actor.id = page.actor_user_id
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
      'featured_places', '[]'::jsonb,
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

revoke all on function app.activity_feed(text, text, integer) from public, anon, authenticated;

create or replace function public.activity_feed(
  input_audience text,
  input_before text default null,
  input_limit integer default 25
)
returns jsonb
language sql
stable
security definer
set search_path = app, public
as $$
  select app.activity_feed(input_audience, input_before, input_limit);
$$;

revoke all on function public.activity_feed(text, text, integer) from public, anon;
grant execute on function public.activity_feed(text, text, integer) to authenticated;

comment on function public.activity_feed(text, text, integer) is
  'Authenticated activity from self and followed people, filtered by audience before pagination. Existing visibility, block, stealth, and source checks remain authoritative.';

notify pgrst, 'reload schema';
commit;
