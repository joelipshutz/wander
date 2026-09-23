begin;
-- REC-587 review candidate. Contact IDs affect only this viewer's ranking;
-- they grant no visibility and are neither persisted nor treated as follows.
create function public.ranked_people_recommendations(
  input_contact_ids text[] default '{}', input_limit integer default 20
) returns table (
  id text, handle text, display_name text, avatar_url text, bio text,
  home_area text, created_at timestamptz, relationship text,
  reason_kind text, shared_follow_count integer, result_rank integer,
  contact_follow_count integer
)
language sql stable security invoker set search_path = pg_catalog, public, app as $$
  with viewer as (
    select p.id, nullif(lower(regexp_replace(trim(p.home_area), '\s+', ' ', 'g')), '') as area
    from public.profiles p where p.id = app.current_user_id() and p.deleted_at is null
  ), connections as (
    -- One row per trusted person, even if they are both a contact and a follow.
    -- Caller RLS remains authoritative; private/hidden intermediaries add no signal.
    select p.id,
      p.id = any(coalesce(input_contact_ids, '{}'::text[])) as is_contact,
      exists(select 1 from public.follows f
        where f.follower_user_id=viewer.id and f.followed_user_id=p.id) as is_followed
    from public.profiles p cross join viewer
    left join app.profile_discovery_settings settings on settings.profile_id=p.id
    where p.id<>viewer.id and p.deleted_at is null and not p.is_private_profile
      and not coalesce(settings.hidden_from_suggestions,false)
      and not app.is_blocked(viewer.id,p.id)
      and (p.id = any(coalesce(input_contact_ids, '{}'::text[]))
        or exists(select 1 from public.follows f
          where f.follower_user_id=viewer.id and f.followed_user_id=p.id))
  ), social_support as (
    select f.followed_user_id as candidate_id,
      count(distinct c.id)::integer as connection_follow_count,
      count(distinct c.id) filter(where c.is_contact)::integer as contact_follow_count,
      count(distinct c.id) filter(where c.is_followed)::integer as shared_follow_count
    from connections c join public.follows f on f.follower_user_id=c.id
    group by f.followed_user_id
  ), candidates as (
    select p.*, coalesce(settings.suggestion_priority, 0) as curated_priority,
      p.id = any(coalesce(input_contact_ids, '{}'::text[])) as is_contact,
      coalesce(viewer.area = nullif(lower(regexp_replace(trim(p.home_area), '\s+', ' ', 'g')), ''), false) as same_area,
      exists(select 1 from public.follows f where f.follower_user_id=p.id and f.followed_user_id=viewer.id) as follows_viewer,
      coalesce(support.shared_follow_count,0) as shared_follow_count,
      coalesce(support.contact_follow_count,0) as contact_follow_count,
      coalesce(support.connection_follow_count,0) as connection_follow_count
    from public.profiles p cross join viewer
    left join app.profile_discovery_settings settings on settings.profile_id=p.id
    left join social_support support on support.candidate_id=p.id
    where cardinality(coalesce(input_contact_ids,'{}'::text[])) <= 100
      and p.id<>viewer.id and p.deleted_at is null and not p.is_private_profile
      and not coalesce(settings.hidden_from_suggestions,false)
      and not app.is_blocked(viewer.id,p.id)
      and not exists(select 1 from public.follows f where f.follower_user_id=viewer.id and f.followed_user_id=p.id)
  ), scored as (
    select c.*,
      curated_priority * 10 + case when is_contact then 120 else 0 end
      + least(connection_follow_count,5)*12 + case when follows_viewer then 35 else 0 end
      + case when same_area then 30 else 0 end
      + case when nullif(trim(bio),'') is not null then 5 else 0 end
      + case when nullif(trim(avatar_url),'') is not null then 5 else 0 end as score
    from candidates c
  ), ranked as (
    select s.*, row_number() over(order by score desc, connection_follow_count desc,
      created_at desc, lower(handle), id)::integer as position from scored s
  )
  select r.id,r.handle,r.display_name,r.avatar_url,r.bio,r.home_area,r.created_at,
    app.viewer_relationship(r.id),
    case when r.is_contact then 'contacts'
      when r.contact_follow_count>0 then 'contact_follows'
      when r.shared_follow_count>0 then 'shared_follows'
      when r.follows_viewer then 'follows_you'
      when r.same_area then 'nearby' else 'suggested' end,
    r.shared_follow_count,r.position,r.contact_follow_count
  from ranked r order by r.position
  limit least(greatest(coalesce(input_limit,20),1),50);
$$;
revoke all on function public.ranked_people_recommendations(text[],integer) from public,anon;
grant execute on function public.ranked_people_recommendations(text[],integer) to authenticated;
commit;
