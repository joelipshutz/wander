begin;

create or replace function app.search_profiles_by_handle(query text)
returns table (
  id text,
  handle text,
  display_name text,
  avatar_url text,
  bio text,
  home_area text
)
language sql
stable
security invoker
set search_path = public, app
as $$
  with normalized as (
    select lower(trim(replace(query, '@', ''))) as q
  )
  select p.id, p.handle, p.display_name, p.avatar_url, p.bio, p.home_area
  from public.profiles p, normalized n
  where length(n.q) >= 2
    and p.id <> app.current_user_id()
    and not p.is_private_profile
    and p.deleted_at is null
    and (
      p.search_handle like n.q || '%'
      or lower(p.display_name) like n.q || '%'
    )
  order by
    case
      when p.search_handle = n.q then 0
      when p.search_handle like n.q || '%' then 1
      when lower(p.display_name) = n.q then 2
      else 3
    end,
    p.search_handle
  limit 20;
$$;

create or replace function app.profile_following(profile_id text)
returns table (
  id text,
  handle text,
  display_name text,
  avatar_url text,
  bio text,
  home_area text,
  relationship text
)
language sql
stable
security invoker
set search_path = public, app
as $$
  select
    p.id,
    p.handle,
    p.display_name,
    p.avatar_url,
    p.bio,
    p.home_area,
    app.viewer_relationship(p.id) as relationship
  from public.follows f
  join public.profiles p on p.id = f.followed_user_id
  where f.follower_user_id = profile_id
    and p.deleted_at is null
    and not p.is_private_profile
    and not app.is_blocked(app.current_user_id(), p.id)
    and not app.is_blocked(profile_id, p.id)
    and exists (
      select 1
      from public.profiles requested
      where requested.id = profile_id
        and requested.deleted_at is null
        and (
          requested.id = app.current_user_id()
          or not requested.is_private_profile
        )
    )
  order by p.search_handle
  limit 500;
$$;

create or replace function app.profile_followers(profile_id text)
returns table (
  id text,
  handle text,
  display_name text,
  avatar_url text,
  bio text,
  home_area text,
  relationship text
)
language sql
stable
security invoker
set search_path = public, app
as $$
  select
    p.id,
    p.handle,
    p.display_name,
    p.avatar_url,
    p.bio,
    p.home_area,
    app.viewer_relationship(p.id) as relationship
  from public.follows f
  join public.profiles p on p.id = f.follower_user_id
  where f.followed_user_id = profile_id
    and p.deleted_at is null
    and not p.is_private_profile
    and not app.is_blocked(app.current_user_id(), p.id)
    and not app.is_blocked(profile_id, p.id)
    and exists (
      select 1
      from public.profiles requested
      where requested.id = profile_id
        and requested.deleted_at is null
        and (
          requested.id = app.current_user_id()
          or not requested.is_private_profile
        )
    )
  order by p.search_handle
  limit 500;
$$;

create or replace function app.follow_user(profile_id text, source text default 'profile')
returns public.follows
language plpgsql
security invoker
set search_path = public, app
as $$
declare
  created_follow public.follows;
begin
  if app.current_user_id() is null then
    raise exception 'not_authenticated';
  end if;

  if app.current_user_id() = profile_id then
    raise exception 'cannot_follow_self';
  end if;

  if app.is_blocked(app.current_user_id(), profile_id) then
    raise exception 'blocked';
  end if;

  if not exists (
    select 1
    from public.profiles profile
    where profile.id = profile_id
      and profile.deleted_at is null
      and not profile.is_private_profile
  ) then
    raise exception 'profile_not_followable';
  end if;

  insert into public.follows (follower_user_id, followed_user_id, source)
  values (app.current_user_id(), profile_id, source)
  on conflict (follower_user_id, followed_user_id)
  do update set source = excluded.source, updated_at = now()
  returning * into created_follow;

  return created_follow;
end;
$$;

create or replace function app.discover_profile_recommendations(input_limit integer default 20)
returns table (
  id text,
  handle text,
  display_name text,
  avatar_url text,
  bio text,
  home_area text,
  created_at timestamptz,
  relationship text,
  reason_kind text,
  shared_follow_count integer,
  result_rank integer
)
language sql
stable
security invoker
set search_path = public, app
as $$
  with viewer as (
    select app.current_user_id() as id
  ),
  candidates as (
    select
      profile.id,
      profile.handle,
      profile.display_name,
      profile.avatar_url,
      profile.bio,
      profile.home_area,
      profile.created_at,
      exists (
        select 1
        from public.follows candidate_follow
        where candidate_follow.follower_user_id = profile.id
          and candidate_follow.followed_user_id = viewer.id
      ) as follows_viewer,
      (
        select count(distinct viewer_follow.followed_user_id)::integer
        from public.follows viewer_follow
        join public.follows shared_follow
          on shared_follow.follower_user_id = viewer_follow.followed_user_id
         and shared_follow.followed_user_id = profile.id
        join public.profiles shared_profile
          on shared_profile.id = viewer_follow.followed_user_id
         and shared_profile.deleted_at is null
         and not shared_profile.is_private_profile
        where viewer_follow.follower_user_id = viewer.id
      ) as shared_follow_count
    from public.profiles profile
    cross join viewer
    where viewer.id is not null
      and profile.id <> viewer.id
      and profile.deleted_at is null
      and not profile.is_private_profile
      and not app.is_blocked(viewer.id, profile.id)
      and not exists (
        select 1
        from public.follows existing_follow
        where existing_follow.follower_user_id = viewer.id
          and existing_follow.followed_user_id = profile.id
      )
  ),
  ranked as (
    select
      candidate.*,
      row_number() over (
        order by
          case
            when candidate.follows_viewer then 0
            when candidate.shared_follow_count > 0 then 1
            else 2
          end,
          candidate.shared_follow_count desc,
          candidate.created_at desc,
          lower(candidate.handle),
          candidate.id
      )::integer as result_rank
    from candidates candidate
  )
  select
    ranked.id,
    ranked.handle,
    ranked.display_name,
    ranked.avatar_url,
    ranked.bio,
    ranked.home_area,
    ranked.created_at,
    app.viewer_relationship(ranked.id) as relationship,
    case
      when ranked.follows_viewer then 'follows_you'
      when ranked.shared_follow_count > 0 then 'shared_follows'
      else 'suggested'
    end as reason_kind,
    ranked.shared_follow_count,
    ranked.result_rank
  from ranked
  order by ranked.result_rank
  limit least(greatest(coalesce(input_limit, 20), 1), 50);
$$;

create or replace function public.discover_profile_recommendations(input_limit integer default 20)
returns table (
  id text,
  handle text,
  display_name text,
  avatar_url text,
  bio text,
  home_area text,
  created_at timestamptz,
  relationship text,
  reason_kind text,
  shared_follow_count integer,
  result_rank integer
)
language sql
stable
security invoker
set search_path = app, public
as $$
  select * from app.discover_profile_recommendations(input_limit);
$$;

comment on function public.discover_profile_recommendations(integer) is
  'Returns bounded, RLS-visible public profile recommendations with aggregate graph reasons and no place data.';

revoke all on function app.search_profiles_by_handle(text) from public, anon;
revoke all on function app.profile_following(text) from public, anon;
revoke all on function app.profile_followers(text) from public, anon;
revoke all on function app.follow_user(text, text) from public, anon;
revoke all on function app.discover_profile_recommendations(integer) from public, anon;
revoke all on function public.search_profiles_by_handle(text) from public, anon;
revoke all on function public.profile_following(text) from public, anon;
revoke all on function public.profile_followers(text) from public, anon;
revoke all on function public.follow_user(text, text) from public, anon;
revoke all on function public.discover_profile_recommendations(integer) from public, anon;

grant execute on function app.search_profiles_by_handle(text) to authenticated;
grant execute on function app.profile_following(text) to authenticated;
grant execute on function app.profile_followers(text) to authenticated;
grant execute on function app.follow_user(text, text) to authenticated;
grant execute on function app.discover_profile_recommendations(integer) to authenticated;
grant execute on function public.search_profiles_by_handle(text) to authenticated;
grant execute on function public.profile_following(text) to authenticated;
grant execute on function public.profile_followers(text) to authenticated;
grant execute on function public.follow_user(text, text) to authenticated;
grant execute on function public.discover_profile_recommendations(integer) to authenticated;

commit;
