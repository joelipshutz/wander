begin;

-- REC-636: an opened place shows its latest readable activity independently of
-- the map's audience/type/time filters. This does not introduce public discovery.
-- SECURITY DEFINER is deliberate: feed_events is private; every returned event
-- passes the current canonical-event, actor, block, source and list gates.
-- Reviewed dependencies: current_user_id (20260814090000), can_read_user_place
-- and is_blocked (20260602131500), can_read_place_list (20260810233134),
-- can_read_activity_event/canonical_activity_id (20260924031627),
-- feed_place_projection (20260925002745), feed_wanna_place_projection
-- (20260916171502), feed_list_projection (20260725214600), and Live's exact
-- viewer-taxonomy/rendered payload (20261014020238). None are replaced here.
-- Alias resolution is read-only. No place, original event or engagement is merged.
-- Supports reverse UUID-reference and qualified-provider lookups without a
-- full places scan. Address fallback uses the existing places_geog_idx.
create index if not exists places_live_provider_identity_idx on public.places
  (lower(btrim(source_provider)), btrim(source_provider_place_id))
  where source_provider_place_id is not null;
create index if not exists places_live_uuid_reference_idx on public.places
  (lower(btrim(source_provider_place_id)))
  where btrim(source_provider_place_id) ~*
    '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

create function public.live_place_activity(
  input_place_ids uuid[],
  input_before text default null,
  input_limit integer default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app, extensions
as $$
declare
  viewer_id text := app.current_user_id();
  page_limit integer := greatest(1, least(coalesce(input_limit, 20), 50));
  query_place_ids uuid[];
  query_key text;
  cursor_parts text[];
  cursor_occurred_at timestamptz;
  cursor_id uuid;
begin
  if input_place_ids is null or cardinality(input_place_ids) not between 1 and 100
    or coalesce(array_ndims(input_place_ids),1) <> 1
    or exists(select 1 from unnest(input_place_ids) requested(id) where requested.id is null)
  then raise exception 'Invalid Live place scope' using errcode='22023'; end if;
  select array_agg(requested.id order by requested.id) into query_place_ids
    from (select distinct unnest(input_place_ids) as id) requested;
  -- Bind the caller and normalized *requested* scope, not today's alias expansion.
  -- This fingerprint grants no access: every page rechecks current permissions.
  query_key := md5(jsonb_build_object('version',1,'viewer',viewer_id,'place_ids',query_place_ids)::text);
  if viewer_id is null or not exists(
    select 1 from public.profiles viewer where viewer.id=viewer_id and viewer.deleted_at is null
  ) then
    return jsonb_build_object('activity','[]'::jsonb,'featured_places','[]'::jsonb,
      'next_cursor',null,'fetched_at',now());
  end if;
  if input_before is not null then
    cursor_parts := string_to_array(input_before,'|');
    if cardinality(cursor_parts) <> 3 or cursor_parts[1] <> query_key then
      raise exception 'Invalid Live place cursor' using errcode='22023';
    end if;
    begin
      cursor_occurred_at := cursor_parts[2]::timestamptz;
      cursor_id := cursor_parts[3]::uuid;
      if cursor_occurred_at is null or not isfinite(cursor_occurred_at) or cursor_id is null then
        raise exception 'Invalid Live place cursor' using errcode='22023';
      end if;
    exception when others then
      raise exception 'Invalid Live place cursor' using errcode='22023';
    end;
  end if;

  return (
    with recursive
    matching_places(id) as (
      select seed.id from public.places seed where seed.id=any(query_place_ids)
      union
      select target.id
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
    eligible_events as (
      select event.id, event.actor_user_id, event.event_type, event.user_place_id,
        event.place_id, event.visit_id, event.list_id, event.list_item_id, event.occurred_at
      from public.feed_events event
      join matching_places matched on matched.id=event.place_id
      join public.profiles actor on actor.id=event.actor_user_id
      where actor.deleted_at is null
        and (event.actor_user_id=viewer_id or not coalesce(actor.is_private_profile,false))
        and not app.is_blocked(viewer_id,event.actor_user_id)
        and app.can_read_activity_event(viewer_id,event.id)
        -- Canonical aliases are navigation identities, not extra original posts.
        and event.id=app.canonical_activity_id(event.id)
        and (
          (event.event_type in ('place_saved','place_been','place_want_to_go')
            and exists(select 1 from public.user_places source_place
              where source_place.id=event.user_place_id and source_place.place_id=event.place_id
                and source_place.deleted_at is null
                and app.can_read_user_place(viewer_id,source_place.user_id,source_place.visibility))
            and (event.visit_id is null or exists(select 1 from public.place_visits source_visit
              where source_visit.id=event.visit_id and source_visit.user_place_id=event.user_place_id
                and source_visit.deleted_at is null)))
          or (event.event_type='list_item_added'
            and app.can_read_place_list(event.list_id,viewer_id)
            and exists(select 1 from public.user_places source_place
              where source_place.id=event.user_place_id and source_place.place_id=event.place_id
                and source_place.deleted_at is null
                and app.can_read_user_place(viewer_id,source_place.user_id,source_place.visibility)))
        )
      -- list_created has no place and is intentionally not a place-history row.
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
            when app.is_mutual(viewer_id,actor.id) then 'mutual'
            when app.follows(viewer_id,actor.id) then 'follower'
            else 'non_follower'
          end
        ) as actor_json,
        -- Live carries an authoritative viewer category for its query/facets,
        -- including unfrozen global fallback. Do not let a client's provider
        -- heuristic discard a server category match. Legacy Feed is untouched.
        case when projection.place_json is null then null else
          projection.place_json || jsonb_build_object('attributes',
            coalesce((select jsonb_agg(attribute)
              from jsonb_array_elements(coalesce(projection.place_json->'attributes','[]'::jsonb)) attribute
              where attribute->>'question_key'<>'__viewer_taxonomy_primary_category'),'[]'::jsonb)
            || jsonb_build_array(jsonb_build_object(
              'question_definition_id',null,'question_key','__viewer_taxonomy_primary_category',
              'value_type','text','value',app.place_primary_category(viewer_taxonomy.primary_category),
              'prompt',null,'options','[]'::jsonb,'is_system',true)))
        end as place_json,
        app.feed_list_projection(page.list_id) as list_json
      from page
      join public.profiles actor on actor.id = page.actor_user_id
      left join public.user_places projection_source on projection_source.id=page.user_place_id
      left join lateral app.viewer_place_taxonomy(projection_source.place_id) viewer_taxonomy on true
      cross join lateral (select app.feed_wanna_place_projection(page.user_place_id, page.visit_id, page.id) as place_json) projection
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
          select query_key || '|' || occurred_at::text || '|' || id::text
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

revoke all on function public.live_place_activity(uuid[],text,integer) from public, anon;
grant execute on function public.live_place_activity(uuid[],text,integer) to authenticated;
comment on function public.live_place_activity(uuid[],text,integer) is
  'Latest currently authorized activity for explicit place aliases, independent of discovery filters. Account/scope-bound keyset pagination; no media URLs, writes or new public visibility.';
notify pgrst, 'reload schema';
commit;
