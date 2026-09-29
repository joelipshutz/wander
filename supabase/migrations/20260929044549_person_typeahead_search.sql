begin;

-- REC-631: account typeahead from the first character, by handle or any name
-- component. Preserve the stable invoker contract and existing profile RLS.
-- Prior definitions: 20260602131500_m3_foundation,
-- 20260602210000_public_app_rpc_wrappers, and
-- 20260717180000_discover_profile_recommendations. The public wrapper and
-- both authenticated-only grants remain unchanged. No visibility is granted.
create or replace function app.search_profiles_by_handle(query text)
returns table (id text, handle text, display_name text, avatar_url text, bio text, home_area text)
language sql stable security invoker
set search_path = public, app
as $$
  with normalized as (
    select lower(trim(replace(query, '@', ''))) as q
  )
  select p.id, p.handle, p.display_name, p.avatar_url, p.bio, p.home_area
  from public.profiles p cross join normalized n
  where length(n.q) between 1 and 80
    and p.id <> app.current_user_id()
    and p.deleted_at is null
    and not p.is_private_profile
    and not app.is_blocked(app.current_user_id(), p.id)
    and (
      starts_with(p.search_handle, n.q)
      or starts_with(lower(p.display_name), n.q)
      or exists (
        select 1 from regexp_split_to_table(lower(p.display_name), '\s+') as name_part
        where starts_with(name_part, n.q)
      )
    )
  order by case
    when p.search_handle = n.q then 0
    when lower(p.display_name) = n.q then 1
    when starts_with(p.search_handle, n.q) then 2
    when starts_with(lower(p.display_name), n.q) then 3
    else 4
  end, p.search_handle, p.id
  limit 50;
$$;
revoke all on function app.search_profiles_by_handle(text) from public, anon;
grant execute on function app.search_profiles_by_handle(text) to authenticated;

commit;
