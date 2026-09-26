begin;

-- REC-589 / review 1A: a queued group is a snapshot, not a continuing grant
-- to its place names. Check the whole rendered snapshot, not just whether
-- one place is still visible. Partial revocation must also hide stale counts.
--
-- queue snapshot -> current visible group -> exact match? -> readable
--                                      \-> changed/empty -> hidden
-- The existing worker refreshes a changed group at claim. Delivered OS
-- notifications cannot be recalled; subsequent database reads are protected.
--
-- This narrow definer reads the private ledger through the existing renderer
-- and binds the event to authenticated claims. Callers supply only an event ID.
create function app.can_read_own_import_notification(input_event_id uuid)
returns boolean language plpgsql stable security definer
set search_path = pg_catalog, public, app
as $$
declare
  event public.notification_events;
  content jsonb;
begin
  select * into event from public.notification_events
    where id = input_event_id and recipient_user_id = app.current_user_id();
  if event.id is null then return false; end if;
  if event.data->>'sender_import_id' is null then return true; end if;
  content := app.import_notification_content(event.actor_user_id,
    event.recipient_user_id, event.data->>'sender_import_id');
  return content is not null
    and event.notification_type = 'followed_place_visit'
    and event.body = content->>'body'
    and event.deeplink_url = 'recme://places/' || (content->>'place_id')
    and event.data->>'place_id' = content->>'place_id'
    and event.data->'place_count' = content->'place_count';
end;
$$;
revoke all on function app.can_read_own_import_notification(uuid) from public, anon;
grant execute on function app.can_read_own_import_notification(uuid) to authenticated;

-- RESTRICTIVE composes with the existing recipient policy and future source
-- authorization policies: another permissive policy cannot bypass this guard.
-- The existing raw SELECT grant and non-import event behavior are unchanged.
create policy "import notification snapshots require current visibility"
  on public.notification_events as restrictive for select to authenticated
  using (data->>'sender_import_id' is null or app.can_read_own_import_notification(id));

commit;
