begin;

create or replace function app.viewer_relationship(profile_id text)
returns text
language sql
stable
security invoker
set search_path = public, app
as $$
  select case
    when app.current_user_id() is null then 'non_follower'
    when profile_id = app.current_user_id() then 'owner'
    when app.is_blocked(app.current_user_id(), profile_id) then 'non_follower'
    when app.is_mutual(app.current_user_id(), profile_id) then 'mutual'
    when app.follows(app.current_user_id(), profile_id) then 'follower'
    else 'non_follower'
  end
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
    and not app.is_blocked(app.current_user_id(), p.id)
    and not app.is_blocked(profile_id, p.id)
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
    and not app.is_blocked(app.current_user_id(), p.id)
    and not app.is_blocked(profile_id, p.id)
  order by p.search_handle
  limit 500;
$$;

revoke all on function app.viewer_relationship(text) from public, anon;
revoke all on function app.profile_following(text) from public, anon;
revoke all on function app.profile_followers(text) from public, anon;
revoke all on function public.profile_relationship(text) from public, anon;
revoke all on function public.profile_following(text) from public, anon;
revoke all on function public.profile_followers(text) from public, anon;

grant execute on function app.viewer_relationship(text) to authenticated;
grant execute on function app.profile_following(text) to authenticated;
grant execute on function app.profile_followers(text) to authenticated;
grant execute on function public.profile_relationship(text) to authenticated;
grant execute on function public.profile_following(text) to authenticated;
grant execute on function public.profile_followers(text) to authenticated;

commit;
