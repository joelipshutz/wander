begin;

-- Engagement applies to every immutable Feed ticket. Place events retain the
-- user-place visibility boundary, while list events use the list visibility
-- contract and, for item additions, the source place boundary as well.
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
        )
    )
$$;

-- A shared activity link must resolve independently of Feed pagination. This
-- returns the same envelope shape as followed_feed for one visible event.
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

revoke all on function public.activity_detail(uuid) from public, anon;
grant execute on function public.activity_detail(uuid) to authenticated;

comment on function public.activity_detail(uuid) is
  'Returns one visibility-filtered Feed activity envelope for exact-ticket navigation.';

commit;
