begin;

-- REC-614: An explicitly empty check-in field is authoritative. Falling back
-- to the mutable parent borrows another visit's note or aggregate rating.
-- Prior definitions: 20260725214600_check_in_feed_projection.sql and
-- 20260824080308_private_taxonomy_projections.sql. Preserve this private,
-- stable SECURITY DEFINER projection and its pinned search_path/grants.
-- Only already-authorized Feed/detail callers can invoke it; direct client
-- execution remains revoked. Viewer taxonomy and visibility are unchanged.
-- This is a read-projection fix: no saved visits or engagement are rewritten.
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
    'category', global_default.primary_category,
    'primary_category', global_default.primary_category,
    'subcategory', global_default.subcategory,
    'category_source', global_default.category_source,
    'category_confidence', global_default.category_confidence,
    'raw_provider_type', place.raw_provider_type,
    'address', place.address,
    'locality', place.locality,
    'region', place.region,
    'country', place.country,
    'time_zone_identifier', null,
    'latitude', place.latitude,
    'longitude', place.longitude,
    'status', case when source_visit.id is not null then 'been' else source_place.status end,
    'visibility', source_place.visibility,
    'note', case when source_visit.id is not null then source_visit.note else source_place.note end,
    'visited_at', case when source_visit.id is not null then source_visit.visited_at else source_place.visited_at end,
    'saved_at', case when source_visit.id is not null then source_visit.created_at else source_place.saved_at end,
    'created_at', case when source_visit.id is not null then source_visit.created_at else source_place.created_at end,
    'updated_at', case when source_visit.id is not null then source_visit.updated_at else source_place.updated_at end,
    'rating_signal', case when source_visit.id is null then source_place.rating_signal end,
    'rating_score', case when source_visit.id is not null then source_visit.rating_score else source_place.rating_score end,
    'recommended_score', null,
    'recommended_count', 0,
    'category_override', case when source_place.user_id = app.current_user_id() then source_place.category_override end,
    'subcategory_override', case when source_place.user_id = app.current_user_id() then source_place.subcategory_override end,
    'category_override_source', case when source_place.user_id = app.current_user_id() then source_place.category_override_source end,
    'category_override_confidence', case when source_place.user_id = app.current_user_id() then source_place.category_override_confidence end,
    'source_type', source_place.source_type,
    'attributes', app.viewer_taxonomy_projection_attributes(place.id)
  )
  from public.user_places source_place
  join public.places place on place.id = source_place.place_id
  join public.profiles owner on owner.id = source_place.user_id
  cross join lateral app.global_place_taxonomy(place.id) global_default
  left join public.place_visits source_visit
    on source_visit.id = input_visit_id
   and source_visit.user_place_id = source_place.id
   and source_visit.deleted_at is null
  where source_place.id = input_user_place_id
    and source_place.deleted_at is null
    and (input_visit_id is null or source_visit.id is not null)
$$;

revoke all on function app.feed_place_projection(uuid, uuid)
  from public, anon, authenticated;

comment on function app.feed_place_projection(uuid, uuid) is
  'Projects explicit check-ins exclusively from their visit, preserving empty fields; only visit-less events use parent metadata.';

-- Compose REC-614 activity aliases with REC-590 source-photo privacy, which
-- is already hosted but may not yet be present in a fresh main-only database.
-- Prior definitions: 20260811220214_activity_ticket_media.sql,
-- 20260924031627_historical_feed_identity.sql, and REC-590's hosted
-- 20260923222333_activity_source_privacy_and_ratings.sql. Retain both gates
-- when the source-privacy helper exists, regardless of deployment order.
-- SECURITY DEFINER is deliberate: authenticated callers can resolve only
-- events authorized for app.current_user_id(); photo lineage adds a narrower
-- gate when installed. Preserve the return type, stability, path and grants.
do $media_compatibility$
declare
  definition text := $definition$
create or replace function public.activity_media(input_activity_ids uuid[])
returns table(activity_id uuid, media jsonb)
language sql
stable
security definer
set search_path = pg_catalog, public, app
as $body$
  select
    requested.id as activity_id,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', photo.id,
            'url', null,
            'storage_bucket', photo.storage_bucket,
            'storage_path', photo.storage_path,
            'accessibility_label', 'Activity photo'
          )
          order by photo.sort_order, photo.created_at, photo.id
        )
        from public.visit_photos photo
        where photo.visit_id = event.visit_id
          and photo.upload_state = 'uploaded'
          and photo.deleted_at is null
          /* source_photo_gate */
      ),
      '[]'::jsonb
    ) as media
  from (select distinct unnest(coalesce(input_activity_ids, '{}'::uuid[])) as id) requested
  join public.feed_events event on event.id = app.canonical_activity_id(requested.id)
  where app.can_read_activity_event(app.current_user_id(), event.id)
  order by event.occurred_at desc, event.id desc
$body$;
$definition$;
begin
  definition := replace(definition, '/* source_photo_gate */',
    case when to_regprocedure('app.can_read_photo_source(text,uuid)') is not null
      then 'and app.can_read_photo_source(app.current_user_id(), photo.id)'
      else '' end);
  execute definition;
end;
$media_compatibility$;
revoke all on function public.activity_media(uuid[]) from public, anon;
grant execute on function public.activity_media(uuid[]) to authenticated;

commit;
