begin;

-- Compatibility visits deliberately reuse the immutable parent event. Returning
-- their visit ID here joins the history tile to that same conversation without
-- creating duplicate Feed entries or moving existing likes/comments.
-- Preserve the original stable SECURITY DEFINER boundary, pinned search_path,
-- authenticated-only grant, 100-parent limit, and can_read_activity_event check.
create or replace function public.place_activity_engagement_summaries(
  input_user_place_ids uuid[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  viewer_id text := app.current_user_id();
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;
  if coalesce(cardinality(input_user_place_ids), 0) > 100 then
    raise exception 'too_many_user_place_ids';
  end if;

  return coalesce(
    (
      select jsonb_agg(
        app.activity_engagement_json(viewer_id, event.id)
          || jsonb_build_object(
            'user_place_id', event.user_place_id,
            'visit_id', coalesce(event.visit_id, compatibility_visit.id),
            'event_type', event.event_type,
            'occurred_at', event.occurred_at
          )
        order by event.occurred_at desc, event.id desc
      )
      from public.feed_events event
      left join public.place_visits compatibility_visit
        on event.visit_id is null
        and event.event_type in ('place_been', 'place_saved')
        and compatibility_visit.user_place_id = event.user_place_id
        and compatibility_visit.backfilled_from_user_place
        and compatibility_visit.deleted_at is null
      where event.user_place_id = any(coalesce(input_user_place_ids, '{}'::uuid[]))
        and event.event_type in ('place_saved', 'place_been', 'place_want_to_go')
        and app.can_read_activity_event(viewer_id, event.id)
    ),
    '[]'::jsonb
  );
end;
$$;


revoke all on function public.place_activity_engagement_summaries(uuid[]) from public, anon;
grant execute on function public.place_activity_engagement_summaries(uuid[]) to authenticated;

-- Explicit visits created before per-visit Feed recording need their own event.
-- This private maintenance operation is idempotent. It never changes existing
-- events or engagement, never revives deleted sources, and uses historical
-- timestamps rather than publishing old check-ins as new activity. Normal future
-- explicit visits are already covered by record_explicit_check_in_feed_event.
create function app.backfill_missing_check_in_events()
returns void
language sql
volatile
security definer
set search_path = pg_catalog, public, app
as $$
  insert into public.feed_events (
    actor_user_id, event_type, user_place_id, place_id, visit_id, occurred_at
  )
  select parent.user_id, 'place_been', parent.id, parent.place_id, visit.id, visit.visited_at
  from public.place_visits visit
  join public.user_places parent on parent.id = visit.user_place_id
  join public.profiles actor on actor.id = parent.user_id
  where visit.deleted_at is null
    and parent.deleted_at is null
    and actor.deleted_at is null
    and not visit.backfilled_from_user_place
    and not exists (select 1 from public.feed_events event where event.visit_id = visit.id)
  on conflict (visit_id) where visit_id is not null and event_type = 'place_been'
  do nothing;
$$;
revoke all on function app.backfill_missing_check_in_events() from public, anon, authenticated;
select app.backfill_missing_check_in_events();

commit;
