begin;

-- REC-645: PostgreSQL checks SELECT policies against the candidate row for
-- INSERT ... RETURNING and INSERT ... ON CONFLICT. The one-argument helper
-- introduced in 20260923222333 rereads visit_photos by id, so a new photo cannot
-- authorize its own creation. Authorize its existing parent directly instead.
--
-- SECURITY DEFINER is intentional: authenticated callers cannot read private
-- provenance or execute the internal explicit-viewer authorization helpers.
-- Keep the original helper and recursive source checks unchanged for callers
-- that authorize persisted photos (including authenticated Storage reads).
create function app.can_read_own_photo_request(input_photo uuid, input_visit uuid)
returns boolean
language sql stable security definer
set search_path = pg_catalog, public, app
as $$
  select input_photo is not null
    and app.can_read_visit_source(app.current_user_id(), input_visit)
    and case
      when exists (
        select 1 from app.visit_photo_sources source
        where source.photo_id = input_photo
      ) then app.can_read_photo_source(app.current_user_id(), input_photo)
      else true
    end;
$$;
revoke all on function app.can_read_own_photo_request(uuid, uuid) from public, anon;
grant execute on function app.can_read_own_photo_request(uuid, uuid) to authenticated;

-- These are candidate-row values, not a reread of the old persisted row.
-- Copied photos still require their entire immutable source chain, even for
-- their owner. Existing owner/path INSERT and UPDATE checks remain authoritative
-- for writes; this policy does not grant write access or relax Storage access.
alter policy "visit photos readable through visit"
  on public.visit_photos
  using (
    deleted_at is null
    and app.can_read_own_photo_request(id, visit_id)
  );

commit;
