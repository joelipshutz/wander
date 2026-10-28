begin;

-- REC-657: complete current pin evidence for a bounded set of already-visible
-- canonical-place seeds. No event-time, Feed page, or viewport row limit applies.
-- This returns only authorized owner IDs and Boolean facets, never place/actor
-- content, event IDs, notes, photos, coordinates, or unreadable list identifiers.
-- SECURITY DEFINER is deliberate: feed_events, Wanna records, deletion receipts,
-- and private-list companion provenance are not directly client-readable.
-- The caller is exclusively app.current_user_id(); all per-source authorization
-- gates are restated below instead of trusting RLS inside a definer function.
-- Reviewed helper history: current_user_id (20260814090000); can_read_user_place,
-- is_blocked/is_mutual (20260602131500); can_read_place_list (20260628112000,
-- 20260810230002, 20260810233134); can_read_activity_event (20260810155601,
-- 20260810232001, 20260811044537, 20260916171502, 20260924031627);
-- can_read_visit_source/private_list_companion_origins (20260923222333);
-- repeat/historical Wannas (20260916171502, 20260916193623, 20260918062209);
-- list-detail resolution (20260818195517). None of those contracts is changed.
-- Guarded canonical alias expansion is copied from live_place_activity
-- (20261023192300): UUID references require nearby corroboration, while opaque
-- provider IDs remain case-sensitive within normalized provider namespaces.
create function public.live_map_pin_states(input_place_ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app, extensions
as $$
declare
  viewer_id text := app.current_user_id();
  query_place_ids uuid[];
begin
  if viewer_id is null or not exists (
    select 1 from public.profiles viewer where viewer.id=viewer_id and viewer.deleted_at is null
  ) then raise exception 'not_authenticated' using errcode='28000'; end if;
  if input_place_ids is null or cardinality(input_place_ids) not between 1 and 200
    or coalesce(array_ndims(input_place_ids),1) <> 1
    or exists(select 1 from unnest(input_place_ids) requested(id) where requested.id is null)
  then raise exception 'Invalid Live pin state scope' using errcode='22023'; end if;
  select array_agg(requested.id order by requested.id) into query_place_ids
    from (select distinct unnest(input_place_ids) as id) requested;

  return (
    with recursive
    requested(id) as (select unnest(query_place_ids)),
    matching_places(seed_id, id) as (
      select requested.id, seed.id from requested
      join public.places seed on seed.id=requested.id
      union
      select matched.seed_id, target.id
      from matching_places matched
      join public.places anchor on anchor.id=matched.id
      cross join lateral (
        -- Each arm uses the PK, provider/reference expression index, or existing
        -- geog GiST. Normalize text only for these scoped candidate pairs.
        select candidate.id, 'uuid'::text as evidence from public.places candidate
        where candidate.id=case when btrim(anchor.source_provider_place_id) ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
          then btrim(anchor.source_provider_place_id)::uuid end
        union
        select candidate.id, 'uuid' from public.places candidate
        where btrim(candidate.source_provider_place_id) ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
          and lower(btrim(candidate.source_provider_place_id))=anchor.id::text
        union
        select candidate.id, case when btrim(anchor.source_provider_place_id) ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
          then 'uuid' else 'provider' end from public.places candidate
        where candidate.source_provider_place_id is not null
          and nullif(btrim(anchor.source_provider_place_id),'') is not null
          and nullif(btrim(anchor.source_provider),'') is not null
          -- Provider namespaces are case insensitive; opaque IDs are not.
          -- Shared UUID-valued tokens remain weak reference evidence and must
          -- pass the same nearby/name-or-address checks below.
          and btrim(candidate.source_provider_place_id)=btrim(anchor.source_provider_place_id)
          and lower(btrim(candidate.source_provider))=lower(btrim(anchor.source_provider))
        union
        select candidate.id, 'address' from public.places candidate
        where st_dwithin(candidate.geog,anchor.geog,100)
      ) edge
      join public.places target on target.id=edge.id
      cross join lateral (
        select btrim(regexp_replace(lower(extensions.unaccent(coalesce(anchor.canonical_name,''))), '[^a-z0-9]+',' ','g')) as name_key,
          btrim(regexp_replace(lower(extensions.unaccent(coalesce(anchor.locality,''))), '[^a-z0-9]+',' ','g')) as locality_key,
          btrim(regexp_replace(lower(extensions.unaccent(coalesce(anchor.region,''))), '[^a-z0-9]+',' ','g')) as region_key,
          btrim(regexp_replace(lower(extensions.unaccent(coalesce(anchor.country,''))), '[^a-z0-9]+',' ','g')) as country_key,
          coalesce((select string_agg(coalesce(
            '{"avenue":"ave","boulevard":"blvd","circle":"cir","court":"ct","drive":"dr","highway":"hwy","lane":"ln","parkway":"pkwy","place":"pl","road":"rd","street":"st","terrace":"ter"}'::jsonb ->> token.value,
            token.value), ' ' order by token.ordinality)
            from regexp_split_to_table(btrim(regexp_replace(lower(extensions.unaccent(coalesce(anchor.address,''))), '[^a-z0-9]+',' ','g')), ' +')
              with ordinality token(value,ordinality)), '') as address_key
      ) anchor_key
      cross join lateral (
        select btrim(regexp_replace(lower(extensions.unaccent(coalesce(target.canonical_name,''))), '[^a-z0-9]+',' ','g')) as name_key,
          btrim(regexp_replace(lower(extensions.unaccent(coalesce(target.locality,''))), '[^a-z0-9]+',' ','g')) as locality_key,
          btrim(regexp_replace(lower(extensions.unaccent(coalesce(target.region,''))), '[^a-z0-9]+',' ','g')) as region_key,
          btrim(regexp_replace(lower(extensions.unaccent(coalesce(target.country,''))), '[^a-z0-9]+',' ','g')) as country_key,
          coalesce((select string_agg(coalesce(
            '{"avenue":"ave","boulevard":"blvd","circle":"cir","court":"ct","drive":"dr","highway":"hwy","lane":"ln","parkway":"pkwy","place":"pl","road":"rd","street":"st","terrace":"ter"}'::jsonb ->> token.value,
            token.value), ' ' order by token.ordinality)
            from regexp_split_to_table(btrim(regexp_replace(lower(extensions.unaccent(coalesce(target.address,''))), '[^a-z0-9]+',' ','g')), ' +')
              with ordinality token(value,ordinality)), '') as address_key
      ) target_key
      where edge.evidence='provider'
        or (st_dwithin(target.geog,anchor.geog,100) and (
          -- Provider UUID references are client supplied. Both directions and
          -- chains need nearby compatible identity evidence, not just a UUID.
          (edge.evidence='uuid' and (
            (anchor_key.name_key<>'' and target_key.name_key=anchor_key.name_key)
            or (anchor_key.address_key<>'' and target_key.address_key=anchor_key.address_key
              and anchor_key.locality_key<>'' and target_key.locality_key=anchor_key.locality_key)))
          or (edge.evidence='address'
            and anchor_key.name_key<>'' and target_key.name_key=anchor_key.name_key
            and anchor_key.address_key<>'' and target_key.address_key=anchor_key.address_key
            and anchor_key.locality_key<>'' and target_key.locality_key=anchor_key.locality_key
            and target_key.region_key=anchor_key.region_key and target_key.country_key=anchor_key.country_key)
        ))
    ),
    visible_parents as materialized (
      select matched.seed_id, saved.id as user_place_id, saved.place_id, saved.user_id as owner_id,
        saved.status, saved.source_type
      from matching_places matched
      join public.user_places saved on saved.place_id=matched.id
      join public.profiles owner on owner.id=saved.user_id
      where saved.deleted_at is null and owner.deleted_at is null
        and (saved.user_id=viewer_id or not coalesce(owner.is_private_profile,false))
        and app.can_read_user_place(viewer_id,saved.user_id,saved.visibility)
    ),
    save_evidence as materialized (
      select parent.seed_id, parent.owner_id,
        -- Existing legacy Been saves were backfilled by the visit trigger.
        -- Parent.status must not resurrect a deleted visit or a list companion.
        exists (
          select 1 from public.place_visits visit
          where visit.user_place_id=parent.user_place_id and visit.deleted_at is null
            and app.can_read_visit_source(viewer_id,visit.id)
        ) as has_been,
        (
          exists (
            select 1 from public.place_wanna_saves wanna
            join public.feed_events event on event.id=wanna.id
            where wanna.user_place_id=parent.user_place_id
              and event.user_place_id=parent.user_place_id and event.place_id=parent.place_id
              and event.actor_user_id=parent.owner_id and event.event_type='place_want_to_go'
              and event.id=app.canonical_activity_id(event.id)
              and app.can_read_activity_event(viewer_id,event.id)
              and not exists(select 1 from app.deleted_place_wannas deleted where deleted.id=wanna.id)
          )
          or exists (
            -- Older original Wanna events may lack the later independent row.
            -- Preserve visible_place_wannas/wannaSaves semantics, including a
            -- surviving historical original; never infer intent from status.
            select 1 from public.feed_events event
            where event.user_place_id=parent.user_place_id and event.place_id=parent.place_id
              and event.actor_user_id=parent.owner_id and event.event_type='place_want_to_go'
              and event.id=app.canonical_activity_id(event.id)
              and app.can_read_activity_event(viewer_id,event.id)
              and not exists(select 1 from public.place_wanna_saves wanna where wanna.id=event.id)
              and not exists(select 1 from app.deleted_place_wannas deleted where deleted.id=event.id)
              and not exists(select 1 from app.private_list_companion_origins companion
                where companion.user_place_id=parent.user_place_id)
          )
          or exists (
            -- Legacy social saves emitted place_saved instead of Wanna. The
            -- Live activity helper classifies that event using parent status.
            -- Require the surviving event and an untouched intent history so
            -- list-retained parents cannot resurrect deleted Wanna/Been state.
            select 1 from public.feed_events event
            where parent.status='wanna_go' and parent.source_type='social_save'
              and event.user_place_id=parent.user_place_id and event.place_id=parent.place_id
              and event.actor_user_id=parent.owner_id and event.event_type='place_saved'
              and event.id=app.canonical_activity_id(event.id)
              and app.can_read_activity_event(viewer_id,event.id)
              and not exists(select 1 from public.place_wanna_saves wanna where wanna.id=event.id)
              and not exists(select 1 from app.deleted_place_wannas deleted
                where deleted.user_place_id=parent.user_place_id)
              and not exists(select 1 from public.place_visits visit
                where visit.user_place_id=parent.user_place_id)
              and not exists(select 1 from app.private_list_companion_origins companion
                where companion.user_place_id=parent.user_place_id)
          )
        ) as has_wanna
      from visible_parents parent
    ),
    owner_facets as (
      select seed_id, owner_id, bool_or(has_been) as has_been, bool_or(has_wanna) as has_wanna
      from save_evidence
      group by seed_id, owner_id
      having bool_or(has_been) or bool_or(has_wanna)
    ),
    list_memberships as (
      select distinct matched.seed_id
      from matching_places matched
      join public.place_list_items item on item.place_id=matched.id
      join public.place_lists list on list.id=item.list_id
      join public.profiles list_owner on list_owner.id=list.owner_user_id
      where item.deleted_at is null and list.deleted_at is null and list_owner.deleted_at is null
        and app.can_read_place_list(list.id,viewer_id)
        and exists (
          -- Match the current readable list-detail contract. A reference must
          -- belong to this exact place, remain active, and be viewer-readable.
          select 1 from public.user_places reference
          join public.profiles reference_owner on reference_owner.id=reference.user_id
          where reference.id in (item.owner_user_place_id,item.source_user_place_id)
            and reference.place_id=item.place_id and reference.deleted_at is null
            and reference_owner.deleted_at is null
            and app.can_read_user_place(viewer_id,reference.user_id,reference.visibility)
        )
    )
    select jsonb_build_object(
      'states',coalesce((
        select jsonb_agg(jsonb_build_object(
          'place_id',requested.id,
          'saves',coalesce((
            select jsonb_agg(jsonb_build_object(
              'owner_id',facet.owner_id,'has_been',facet.has_been,'has_wanna',facet.has_wanna,
              'is_friend',facet.owner_id<>viewer_id and app.is_mutual(viewer_id,facet.owner_id)
            ) order by facet.owner_id)
            from owner_facets facet where facet.seed_id=requested.id
          ),'[]'::jsonb),
          'has_list_membership',exists(select 1 from list_memberships membership where membership.seed_id=requested.id)
        ) order by requested.id)
        from requested
      ),'[]'::jsonb),
      'complete',true,
      'fetched_at',now()
    )
  );
end;
$$;

revoke all on function public.live_map_pin_states(uuid[]) from public, anon;
grant execute on function public.live_map_pin_states(uuid[]) to authenticated;
comment on function public.live_map_pin_states(uuid[]) is
  'Complete current viewer-authorized Been/Wanna facets and readable list membership for at most 200 canonical place seeds. One scalar JSON object with every requested seed; no event window or content payload.';

-- Security posture is part of the client contract, not an incidental default.
do $$
declare procedure record;
begin
  select prosecdef, provolatile, proconfig into procedure
  from pg_proc where oid='public.live_map_pin_states(uuid[])'::regprocedure;
  if not procedure.prosecdef or procedure.provolatile<>'s'
    or not coalesce(procedure.proconfig @> array['search_path=pg_catalog, public, app, extensions'],false)
    or has_function_privilege('anon','public.live_map_pin_states(uuid[])','execute')
    or not has_function_privilege('authenticated','public.live_map_pin_states(uuid[])','execute') then
    raise exception 'Invalid Live pin state RPC security contract';
  end if;
end;
$$;

commit;
