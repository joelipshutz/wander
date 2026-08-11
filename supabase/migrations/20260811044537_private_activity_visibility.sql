begin;

-- Exact activity links must enforce the same private-profile boundary as the
-- paginated Feed. The actor keeps access to their own place-history activity,
-- while followers lose access as soon as the profile becomes private.
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
        )
    )
$$;

revoke all on function app.can_read_activity_event(text, uuid)
  from public, anon, authenticated;

comment on function app.can_read_activity_event(text, uuid) is
  'Returns whether a viewer can engage with an immutable Feed event, including current block, profile privacy, source-place, visit, and list visibility.';

commit;
