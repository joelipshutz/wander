begin;
-- REVIEW DRAFT: not a migration and not applied to hosted Supabase.
-- Package through the migration CLI before deployment; SQL regression/hosted smoke remain unverified.



-- REC-636: additive Live query; legacy followed_feed/activity_feed functions,
-- grants, source projections and Profile history are unchanged. The eligibility
-- and rendering CTEs are copied from 20260923015217_feed_audience.sql, whose
-- helpers include the later historical-identity and visit-metadata corrections.
-- Viewer taxonomy uses 20260824080307_private_place_taxonomy.sql and the
-- projection boundary from 20260925002745_feed_visit_metadata_identity.sql.
-- Radius reads the existing indexed places.geog geography; it only narrows
-- the current trusted Feed subset, never anonymous/public-place discovery.
-- Filters are applied before the keyset limit; no unbounded client page scan.
-- Definer is intentional because feed_events/projections are private. Caller
-- identity remains app.current_user_id(), never a supplied viewer identifier.

-- Pure shape validation: invoker is sufficient; no table reads or privileges.
-- Coordinates are unwrapped relative to the first longitude, matching Live's
-- antimeridian-aware drawing geometry. Boundary points remain included.
create function app.live_feed_polygon(input_polygon jsonb)
returns geometry language plpgsql immutable security invoker
set search_path = pg_catalog, public, app, extensions
as $$
declare vertex jsonb; latitude double precision; longitude double precision;
  origin double precision; x double precision; min_x double precision; max_x double precision;
  points geometry[] := '{}'; shape geometry;
begin
  if input_polygon is null then return null; end if;
  if jsonb_typeof(input_polygon)<>'array' then raise exception 'Invalid Live polygon' using errcode='22023'; end if;
  if jsonb_array_length(input_polygon) not between 3 and 512 then raise exception 'Invalid Live polygon' using errcode='22023'; end if;
  for vertex in select value from jsonb_array_elements(input_polygon) loop
    if jsonb_typeof(vertex)<>'object' then raise exception 'Invalid Live polygon' using errcode='22023'; end if;
    latitude := (vertex->>'latitude')::double precision;
    longitude := (vertex->>'longitude')::double precision;
    if latitude is null or longitude is null or latitude not between -90 and 90 or longitude not between -180 and 180
      or latitude::text in ('NaN','Infinity','-Infinity') or longitude::text in ('NaN','Infinity','-Infinity')
    then raise exception 'Invalid Live polygon' using errcode='22023'; end if;
    origin := coalesce(origin,longitude);
    x := longitude-origin;
    if x > 180 then x := x-360; elsif x < -180 then x := x+360; end if;
    min_x := least(coalesce(min_x,x),x);
    max_x := greatest(coalesce(max_x,x),x);
    points := array_append(points,st_setsrid(st_makepoint(x,latitude),4326));
  end loop;
  -- Hemispheric shapes have no unique planar interpretation independent of
  -- their start vertex. Ask for a smaller area instead of silently changing it.
  if max_x-min_x >= 180 then raise exception 'Invalid Live polygon' using errcode='22023'; end if;
  shape := st_makepolygon(st_makeline(array_append(points,points[1])));
  if not st_isvalid(shape) or st_isempty(shape) or st_area(shape)<=0
  then raise exception 'Invalid Live polygon' using errcode='22023'; end if;
  return shape;
exception when others then
  raise exception 'Invalid Live polygon' using errcode='22023';
end;
$$;
revoke all on function app.live_feed_polygon(jsonb) from public,anon,authenticated;

create function app.live_activity_feed(
  input_audience text,
  input_after timestamptz default null,
  input_until timestamptz default null,
  input_activity_type text default 'all',
  input_polygon jsonb default null,
  input_before text default null,
  input_limit integer default 25,
  input_center_latitude double precision default null,
  input_center_longitude double precision default null,
  input_radius_meters integer default null,
  input_category_ids text[] default null,
  input_person_ids text[] default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app, extensions
as $$
declare
  viewer_id text := app.current_user_id();
  page_limit integer := greatest(1, least(coalesce(input_limit, 25), 50));
  cursor_occurred_at timestamptz;
  cursor_id uuid;
  query_geometry geometry;
  longitude_origin double precision;
  query_key text;
  cursor_parts text[];
  query_center geography;
  query_categories text[];
  query_people text[];
begin
  if input_audience is null or input_audience not in ('everyone', 'only_me', 'only_friends') then
    raise exception 'Invalid feed audience' using errcode = '22023';
  end if;

  if input_activity_type is null or input_activity_type not in ('all','check_ins','wannas')
    or (input_after is not null and not isfinite(input_after))
    or (input_until is not null and not isfinite(input_until))
    or (input_after is not null and input_until is not null and input_after > input_until)
  then raise exception 'Invalid Live query' using errcode = '22023'; end if;
  -- Radius is a committed geographic intersection, never a broader audience.
  -- Reject partial/invalid inputs rather than silently removing a constraint.
  if num_nonnulls(input_center_latitude,input_center_longitude,input_radius_meters) not in (0,3)
    or (input_radius_meters is not null and (
      input_radius_meters not between 100 and 25000
      or input_center_latitude not between -90 and 90
      or input_center_longitude not between -180 and 180
      or input_center_latitude::text in ('NaN','Infinity','-Infinity')
      or input_center_longitude::text in ('NaN','Infinity','-Infinity')))
  then raise exception 'Invalid Live radius' using errcode='22023'; end if;
  if input_radius_meters is not null then
    query_center := st_setsrid(st_makepoint(input_center_longitude,input_center_latitude),4326)::geography;
  end if;
  if coalesce(array_ndims(input_category_ids),1)>1 or cardinality(input_category_ids)>100
    or exists(select 1 from unnest(input_category_ids) value where value is null or value !~ '^[a-z][a-z0-9_]{0,63}$')
    or coalesce(array_ndims(input_person_ids),1)>1 or cardinality(input_person_ids)>100
    or exists(select 1 from unnest(input_person_ids) value where value is null
      or length(value) not between 1 and 256 or value<>btrim(value) or value ~ '[[:cntrl:]]')
  then raise exception 'Invalid Live refinement' using errcode='22023'; end if;
  -- Set order and duplicate choices do not change the semantic cursor scope.
  select array_agg(value order by value) into query_categories
    from (select distinct value from unnest(input_category_ids) value) categories;
  select array_agg(value order by value) into query_people
    from (select distinct value from unnest(input_person_ids) value) people;
  query_geometry := app.live_feed_polygon(input_polygon);
  longitude_origin := (input_polygon->0->>'longitude')::double precision;
  -- This fingerprint is a scope binding, never an authorization capability.
  -- Auth and every source policy are still reevaluated below for each page.
  query_key := md5(jsonb_build_object('viewer',viewer_id,'audience',input_audience,
    'after',input_after at time zone 'UTC','until',input_until at time zone 'UTC',
    'type',input_activity_type,'polygon',input_polygon,
    'center_latitude',input_center_latitude,'center_longitude',input_center_longitude,
    'radius_meters',input_radius_meters,'category_ids',query_categories,'person_ids',query_people)::text);

  if viewer_id is null or not exists(select 1 from public.profiles where id=viewer_id and deleted_at is null) then
    return jsonb_build_object(
      'activity', '[]'::jsonb,
      'featured_places', '[]'::jsonb,
      'next_cursor', null,
      'fetched_at', now()
    );
  end if;

  if input_before is not null then
    cursor_parts := string_to_array(input_before,'|');
    if cardinality(cursor_parts) <> 3 or cursor_parts[1] <> query_key then
      raise exception 'Invalid Live cursor' using errcode = '22023';
    end if;
    begin
      cursor_occurred_at := cursor_parts[2]::timestamptz;
      cursor_id := cursor_parts[3]::uuid;
      if not isfinite(cursor_occurred_at) or cursor_id is null then
        raise exception 'Invalid Live cursor' using errcode = '22023';
      end if;
    exception when others then
      raise exception 'Invalid Live cursor' using errcode = '22023';
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
        and (input_after is null or event.occurred_at >= input_after)
        and (input_until is null or event.occurred_at <= input_until)
        and (query_people is null or event.actor_user_id=any(query_people))
        and (query_categories is null or exists (
          select 1 from public.user_places category_source
          cross join lateral app.viewer_place_taxonomy(category_source.place_id) viewer_taxonomy
          where category_source.id=event.user_place_id
            -- This resolves the authenticated viewer's override/snapshot/global
            -- category, not another person's private override or food type.
            and app.place_primary_category(viewer_taxonomy.primary_category)=any(query_categories)
        ))
        and (query_center is null or exists (
          select 1 from public.user_places radius_source
          join public.places radius_place on radius_place.id=radius_source.place_id
          where radius_source.id=event.user_place_id
            and st_dwithin(radius_place.geog,query_center,input_radius_meters,true)
        ))
        and (
          input_activity_type = 'all'
          or (input_activity_type = 'check_ins' and (event.event_type = 'place_been'
            or (event.event_type = 'place_saved' and exists(select 1 from public.user_places legacy
              where legacy.id=event.user_place_id and legacy.status='been'))))
          or (input_activity_type = 'wannas' and (event.event_type = 'place_want_to_go'
            or (event.event_type = 'place_saved' and exists(select 1 from public.user_places legacy
              where legacy.id=event.user_place_id and legacy.status='wanna_go'))))
        )
        and (query_geometry is null or exists (
          select 1 from public.user_places geo_source
          join public.places geo_place on geo_place.id=geo_source.place_id
          where geo_source.id=event.user_place_id
            and st_covers(query_geometry,st_setsrid(st_makepoint(
              case when geo_place.longitude-longitude_origin > 180 then geo_place.longitude-longitude_origin-360
                   when geo_place.longitude-longitude_origin < -180 then geo_place.longitude-longitude_origin+360
                   else geo_place.longitude-longitude_origin end,
              geo_place.latitude),4326))
        ))
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

revoke all on function app.live_activity_feed(text,timestamptz,timestamptz,text,jsonb,text,integer,double precision,double precision,integer,text[],text[]) from public,anon,authenticated;

create function public.live_activity_feed(
  input_audience text, input_after timestamptz default null, input_until timestamptz default null,
  input_activity_type text default 'all', input_polygon jsonb default null,
  input_before text default null, input_limit integer default 25,
  input_center_latitude double precision default null, input_center_longitude double precision default null,
  input_radius_meters integer default null, input_category_ids text[] default null, input_person_ids text[] default null
) returns jsonb language sql stable security definer
set search_path = pg_catalog, public, app, extensions
as $$
  select app.live_activity_feed(input_audience,input_after,input_until,input_activity_type,input_polygon,input_before,input_limit,
    input_center_latitude,input_center_longitude,input_radius_meters,input_category_ids,input_person_ids);
$$;
revoke all on function public.live_activity_feed(text,timestamptz,timestamptz,text,jsonb,text,integer,double precision,double precision,integer,text[],text[]) from public,anon;
grant execute on function public.live_activity_feed(text,timestamptz,timestamptz,text,jsonb,text,integer,double precision,double precision,integer,text[],text[]) to authenticated;

create index if not exists feed_events_live_time_idx on public.feed_events(occurred_at desc,id desc);
comment on function public.live_activity_feed(text,timestamptz,timestamptz,text,jsonb,text,integer,double precision,double precision,integer,text[],text[]) is
  'Authorized Live activity filtered by audience, time, type, polygon, geodesic radius, viewer category and actor before pagination. Cursors bind the account and every committed filter; no nearby-person visibility expansion.';
notify pgrst, 'reload schema';
commit;
