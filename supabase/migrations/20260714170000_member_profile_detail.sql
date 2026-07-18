begin;

create or replace function app.profile_detail(input_profile_id text)
returns table (
  id text,
  handle text,
  display_name text,
  avatar_url text,
  bio text,
  home_area text,
  is_private_profile boolean,
  created_at timestamptz,
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
    p.is_private_profile,
    p.created_at,
    app.viewer_relationship(p.id)
  from public.profiles p
  where p.id = input_profile_id
    and p.deleted_at is null;
$$;

create or replace function public.profile_detail(input_profile_id text)
returns table (
  id text,
  handle text,
  display_name text,
  avatar_url text,
  bio text,
  home_area text,
  is_private_profile boolean,
  created_at timestamptz,
  relationship text
)
language sql
stable
security invoker
set search_path = app, public
as $$
  select * from app.profile_detail(input_profile_id);
$$;

comment on function public.profile_detail(text) is
  'Returns one RLS-visible profile with viewer-relative relationship metadata.';

revoke all on function app.profile_detail(text) from public, anon;
revoke all on function public.profile_detail(text) from public, anon;
grant execute on function app.profile_detail(text) to authenticated;
grant execute on function public.profile_detail(text) to authenticated;

commit;
