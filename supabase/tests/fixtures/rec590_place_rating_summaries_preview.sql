begin;

-- Rollback-only implementation preview for REC-590. Move this definition into
-- a generated migration before rollout. The all-user exception returns numbers
-- only; it must never expose contributor IDs or reuse a viewer-filtered average.
-- Definer access is deliberate: hidden ratings belong in Astir, while Friends
-- uses the same authoritative visit-access predicate as the underlying activity.
create function app.place_rating_summaries(
  input_place_id uuid default null,
  input_source_provider text default null,
  input_source_provider_place_id text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  viewer_id text := app.current_user_id();
  resolved_place_id uuid := input_place_id;
  result jsonb;
begin
  if viewer_id is null or not exists (
    select 1 from public.profiles where id = viewer_id and deleted_at is null
  ) then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  -- Search results can have a provider ID without a locally cached server ID.
  -- Resolve public place identity independently of any visible activity rows.
  if resolved_place_id is null and nullif(input_source_provider, '') is not null
      and nullif(input_source_provider_place_id, '') is not null then
    select p.id into resolved_place_id from public.places p
    where p.source_provider = input_source_provider
      and p.source_provider_place_id = input_source_provider_place_id;
  end if;

  with ratings as materialized (
    select pv.id, up.user_id, pv.rating_score, author.is_private_profile
    from public.place_visits pv
    join public.user_places up on up.id = pv.user_place_id
    join public.profiles author on author.id = up.user_id
    where up.place_id = resolved_place_id and up.deleted_at is null
      and pv.deleted_at is null and pv.rating_score is not null
      and author.deleted_at is null
  ), followed_people as (
    select user_id, avg(rating_score) as score
    from ratings
    where user_id <> viewer_id and app.follows(viewer_id, user_id)
      -- Preserve the deployed activity-detail private-profile restriction until
      -- the versioned accepted-follow/account audience policy is connected.
      and not coalesce(is_private_profile, false)
      and app.can_read_place_visit(id)
    group by user_id
  )
  select jsonb_build_object(
    'own', (select jsonb_build_object('score', round(avg(rating_score), 1), 'count', count(*))
            from ratings where user_id = viewer_id),
    'friends', (select jsonb_build_object('score', round(avg(score), 1), 'count', count(*))
                from followed_people),
    'astir', (select jsonb_build_object('score', round(avg(rating_score), 1), 'count', count(*))
              from ratings)
  ) into result;
  return result;
end;
$$;

revoke all on function app.place_rating_summaries(uuid,text,text) from public, anon, authenticated, service_role;

-- The narrow public wrapper calls the private helper without granting clients
-- helper execution. Caller identity comes from authenticated claims only.
create function public.place_rating_summaries(
  input_place_id uuid default null,
  input_source_provider text default null,
  input_source_provider_place_id text default null
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, app
as $$
  select app.place_rating_summaries(input_place_id, input_source_provider, input_source_provider_place_id)
$$;

revoke all on function public.place_rating_summaries(uuid,text,text) from public, anon, service_role;
grant execute on function public.place_rating_summaries(uuid,text,text) to authenticated;

comment on function public.place_rating_summaries(uuid,text,text) is
  'Authenticated numeric-only own, visible-followed-person, and all-user rating aggregates. Hidden ratings contribute only to Astir.';

commit;
