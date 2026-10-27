begin;

-- REC-650: legacy Wanna events predate place_wanna_saves. Their note lives in
-- the parent's historical snapshot after conversion to a check-in; a null
-- snapshot is intentional and must not borrow the mutable current note.
-- Prior helper: 20260916171502_repeat_wanna_saves.sql. Base projection reviewed:
-- 20260725214600, 20260824080308, 20260925002745. Keep the private JSONB/STABLE
-- SECURITY DEFINER contract, pinned search_path and revoked client grants.
-- Definer rights read private event/snapshot data only for existing callers,
-- which enforce current viewer, source, profile, block and event visibility.
-- No saved data, event identity, engagement or authorization policy changes.
create or replace function app.feed_wanna_place_projection(
  input_user_place_id uuid, input_visit_id uuid, input_event_id uuid
)
returns jsonb language sql stable security definer
set search_path = pg_catalog, public, app
as $$
  select app.feed_place_projection(input_user_place_id, input_visit_id)
    || coalesce(
      (select jsonb_build_object('note', wanna.note, 'rating_score', null)
       from public.place_wanna_saves wanna
       where wanna.id = input_event_id and wanna.user_place_id = input_user_place_id),
      (select jsonb_build_object(
         'note', case
           when parent.historical_wanted_at is not null then parent.historical_want_note
           when parent.status = 'wanna_go' then parent.note
           else null
         end,
         'rating_score', null)
       from public.feed_events event
       join public.user_places parent on parent.id = event.user_place_id
       where event.id = input_event_id
         and event.user_place_id = input_user_place_id
         and event.actor_user_id = parent.user_id
         and event.place_id = parent.place_id
         and event.event_type = 'place_want_to_go'
         and event.visit_id is null and input_visit_id is null
         and parent.deleted_at is null),
      '{}'::jsonb)
$$;

revoke all on function app.feed_wanna_place_projection(uuid, uuid, uuid)
  from public, anon, authenticated;
comment on function app.feed_wanna_place_projection(uuid, uuid, uuid) is
  'Projects Wanna notes from their own event or historical snapshot, preserving null; other activity retains its base projection.';

commit;
