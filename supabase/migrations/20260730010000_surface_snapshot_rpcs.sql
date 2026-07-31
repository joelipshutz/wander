begin;

create or replace function public.current_user_calendar_snapshot()
returns jsonb
language sql
stable
security invoker
set search_path = public, app
as $$
  with viewer as (
    select app.current_user_id() as id
  ),
  place_rows as materialized (
    select place_row.*
    from viewer
    cross join lateral public.profile_visible_places(viewer.id, null, null) place_row
    where viewer.id is not null
  ),
  visit_rows as materialized (
    select
      visit.id,
      visit.user_place_id,
      visit.visited_at,
      visit.note,
      visit.rating_score::double precision as rating_score,
      visit.tags,
      visit.backfilled_from_user_place
    from public.place_visits visit
    join place_rows place_row on place_row.user_place_id = visit.user_place_id
    where visit.deleted_at is null
  )
  select jsonb_build_object(
    'places',
    coalesce(
      (
        select jsonb_agg(to_jsonb(place_row) order by place_row.updated_at desc)
        from place_rows place_row
      ),
      '[]'::jsonb
    ),
    'visits',
    coalesce(
      (
        select jsonb_agg(
          to_jsonb(visit_row)
          order by visit_row.user_place_id, visit_row.visited_at desc, visit_row.id
        )
        from visit_rows visit_row
      ),
      '[]'::jsonb
    )
  );
$$;

create or replace function public.visible_place_lists_snapshot()
returns jsonb
language sql
stable
security invoker
set search_path = public, app
as $$
  with summaries as materialized (
    select summary.*
    from public.visible_place_lists() summary
  ),
  owner_ids as materialized (
    select distinct summary.owner_user_id
    from summaries summary
  ),
  owner_places as materialized (
    select place_row.*
    from owner_ids owner
    cross join lateral public.profile_visible_places(owner.owner_user_id, null, null) place_row
  ),
  relationships as materialized (
    select
      owner.owner_user_id as profile_id,
      public.profile_relationship(owner.owner_user_id) as relationship
    from owner_ids owner
  )
  select jsonb_build_object(
    'summaries',
    coalesce(
      (
        select jsonb_agg(to_jsonb(summary) order by summary.updated_at desc, summary.id)
        from summaries summary
      ),
      '[]'::jsonb
    ),
    'details',
    coalesce(
      (
        select jsonb_agg(detail order by summary.updated_at desc, summary.id)
        from summaries summary
        cross join lateral (
          select public.place_list_detail(summary.id) as detail
        ) list_detail
        where detail is not null
      ),
      '[]'::jsonb
    ),
    'owner_places',
    coalesce(
      (
        select jsonb_agg(
          to_jsonb(place_row)
          order by place_row.owner_user_id, place_row.updated_at desc, place_row.user_place_id
        )
        from owner_places place_row
      ),
      '[]'::jsonb
    ),
    'relationships',
    coalesce(
      (
        select jsonb_agg(
          to_jsonb(relationship_row)
          order by relationship_row.profile_id
        )
        from relationships relationship_row
      ),
      '[]'::jsonb
    )
  );
$$;

create or replace function public.social_surface_snapshot(
  min_lat double precision,
  min_lng double precision,
  max_lat double precision,
  max_lng double precision
)
returns jsonb
language sql
stable
security invoker
set search_path = public, app
as $$
  with viewer as (
    select app.current_user_id() as id
  ),
  following_rows as materialized (
    select following_row.*
    from viewer
    cross join lateral public.profile_following(viewer.id) following_row
    where viewer.id is not null
  ),
  follower_rows as materialized (
    select follower_row.*
    from viewer
    cross join lateral public.profile_followers(viewer.id) follower_row
    where viewer.id is not null
  ),
  viewport_places as materialized (
    select place_row.*
    from public.visible_places_in_view(
      min_lat,
      min_lng,
      max_lat,
      max_lng,
      null,
      null,
      null
    ) place_row
  ),
  wanna_go_plans as materialized (
    select plan.*
    from public.own_wanna_go_plans() plan
  ),
  followed_places as materialized (
    select place_row.*
    from following_rows followed_profile
    cross join lateral public.profile_visible_places(followed_profile.id, null, null) place_row
  ),
  relationships as materialized (
    select
      followed_profile.id as profile_id,
      public.profile_relationship(followed_profile.id) as relationship
    from following_rows followed_profile
  )
  select jsonb_build_object(
    'following',
    coalesce(
      (
        select jsonb_agg(to_jsonb(following_row) order by lower(following_row.handle), following_row.id)
        from following_rows following_row
      ),
      '[]'::jsonb
    ),
    'followers',
    coalesce(
      (
        select jsonb_agg(to_jsonb(follower_row) order by lower(follower_row.handle), follower_row.id)
        from follower_rows follower_row
      ),
      '[]'::jsonb
    ),
    'viewport_places',
    coalesce(
      (
        select jsonb_agg(
          to_jsonb(place_row)
          order by place_row.updated_at desc, place_row.user_place_id
        )
        from viewport_places place_row
      ),
      '[]'::jsonb
    ),
    'wanna_go_plans',
    coalesce(
      (
        select jsonb_agg(
          to_jsonb(plan)
          order by plan.planned_date, plan.user_place_id
        )
        from wanna_go_plans plan
      ),
      '[]'::jsonb
    ),
    'followed_places',
    coalesce(
      (
        select jsonb_agg(
          to_jsonb(place_row)
          order by place_row.owner_user_id, place_row.updated_at desc, place_row.user_place_id
        )
        from followed_places place_row
      ),
      '[]'::jsonb
    ),
    'relationships',
    coalesce(
      (
        select jsonb_agg(
          to_jsonb(relationship_row)
          order by relationship_row.profile_id
        )
        from relationships relationship_row
      ),
      '[]'::jsonb
    )
  );
$$;

comment on function public.current_user_calendar_snapshot() is
  'Batches the authenticated owner calendar places and visits into one RLS-filtered response. SECURITY INVOKER preserves user_places and place_visits policies.';
comment on function public.visible_place_lists_snapshot() is
  'Batches visible list summaries, details, owner places, and viewer relationships. SECURITY INVOKER composes existing authenticated RLS-filtered contracts.';
comment on function public.social_surface_snapshot(double precision, double precision, double precision, double precision) is
  'Batches signed-in social graph, viewport, Wanna plan, followed-place, and relationship reads. SECURITY INVOKER preserves the existing visibility contracts.';

revoke all on function public.current_user_calendar_snapshot() from public, anon;
revoke all on function public.visible_place_lists_snapshot() from public, anon;
revoke all on function public.social_surface_snapshot(double precision, double precision, double precision, double precision) from public, anon;

grant execute on function public.current_user_calendar_snapshot() to authenticated;
grant execute on function public.visible_place_lists_snapshot() to authenticated;
grant execute on function public.social_surface_snapshot(double precision, double precision, double precision, double precision) to authenticated;

do $$
declare
  signature regprocedure;
begin
  foreach signature in array array[
    'public.current_user_calendar_snapshot()'::regprocedure,
    'public.visible_place_lists_snapshot()'::regprocedure,
    'public.social_surface_snapshot(double precision,double precision,double precision,double precision)'::regprocedure
  ]
  loop
    if not exists (
      select 1
      from pg_proc procedure
      where procedure.oid = signature
        and not procedure.prosecdef
        and 'search_path=public, app' = any(coalesce(procedure.proconfig, array[]::text[]))
    ) then
      raise exception 'surface snapshot RPC % must be SECURITY INVOKER with a pinned search_path', signature;
    end if;

    if not has_function_privilege('authenticated', signature, 'execute')
       or has_function_privilege('anon', signature, 'execute') then
      raise exception 'surface snapshot RPC % must be authenticated-only', signature;
    end if;
  end loop;
end;
$$;

commit;
