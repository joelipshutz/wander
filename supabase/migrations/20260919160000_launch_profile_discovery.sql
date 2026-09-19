begin;

-- Administrator-owned configuration, separate from self-editable profiles.
-- This changes suggestion eligibility only; profile/search/account access stays intact.
create table app.profile_discovery_settings (
  profile_id text primary key references public.profiles(id) on delete cascade,
  hidden_from_suggestions boolean not null default false,
  suggestion_priority integer not null default 0 check (suggestion_priority between 0 and 1000),
  follow_on_signup boolean not null default false
);
alter table app.profile_discovery_settings enable row level security;
revoke all on app.profile_discovery_settings from public, anon, authenticated;
grant select on app.profile_discovery_settings to authenticated;
grant select, insert, update, delete on app.profile_discovery_settings to service_role;
create policy profile_discovery_settings_read on app.profile_discovery_settings
  for select to authenticated using (true);
comment on table app.profile_discovery_settings is
  'Admin-controlled suggestion exclusion, priority and one-time signup follows. No account deletion or visibility changes.';

-- Verified canonical profile IDs; never create a missing target or match a display name.
insert into app.profile_discovery_settings (profile_id, suggestion_priority, follow_on_signup)
select id, case when id = 'user_3InBzTuUhmItvfKyvQJdoelfseQ' then 100 else 0 end,
       id in ('user_3EhATWssjvHxwGiUaoWR5VTgeoy', 'user_3EsQ6OZGVoIBhjfDUUfDhpa0PLc')
from public.profiles
where id in ('user_3EhATWssjvHxwGiUaoWR5VTgeoy', 'user_3EsQ6OZGVoIBhjfDUUfDhpa0PLc',
             'user_3InBzTuUhmItvfKyvQJdoelfseQ');

-- Known demo/review fixtures plus seven accounts Joe identified as tests on
-- September 19, 2026. Match exact canonical IDs, never names or patterns.
insert into app.profile_discovery_settings (profile_id, hidden_from_suggestions)
select id, true from public.profiles
where id in (
  'user_recme_demo',
  'user_recme_demo_maya_chen', 'user_recme_demo_elena_torres',
  'user_recme_demo_marcus_reed', 'user_recme_demo_priya_shah',
  'user_recme_demo_theo_brooks', 'user_recme_demo_samira_patel',
  'recme_app_review_friend_maya', 'recme_app_review_friend_theo',
  'user_3HvoxPsyGxnoK4B0DTD7elBgHA3',
  'user_3H6Fo6Gfy6hEkrqOeIZw1OrB25Q',
  'user_3HXES5zBV3Vjo9Sdc3ExYj3SmZh',
  'user_3HtgxWK1DbBOE9KXVLCBjqMXuJI',
  'user_3J1plKJ6dqvOjw5epCnWlhagmwm',
  'user_3JQwJee5bnmIfEbqlS8kgKS7YoS',
  'user_3FmEDQY1USlBSbdPVGGuA8dOLlw',
  'user_3JBqOSE5gyVAelfQX8vOcwpbfcZ'
);

-- Preserve the historical source values and add explicit provenance for defaults.
alter table public.follows drop constraint follows_source_check;
alter table public.follows add constraint follows_source_check
  check (source in ('username', 'contacts', 'profile', 'invite_link_future', 'signup_default'));

-- Automatic follows are not deliberate social actions and must not send a push/inbox alert.
-- Keep the existing notification function and its security posture unchanged.
drop trigger follows_notify_insert on public.follows;
create trigger follows_notify_insert after insert on public.follows
  for each row when (new.source <> 'signup_default')
  execute function app.notify_follow_insert();

-- SECURITY DEFINER is required for trusted signup initialization across profile RLS.
-- No caller-selectable ID: only the just-inserted row can become the follower.
-- INSERT-only intentionally never reapplies follows on login, webhook retries,
-- onboarding/profile edits, undeletes, or after a member manually unfollows.
create function app.apply_signup_default_follows()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
begin
  if new.deleted_at is not null then
    return new;
  end if;
  insert into public.follows (follower_user_id, followed_user_id, source)
  select new.id, target.id, 'signup_default'
  from app.profile_discovery_settings settings
  join public.profiles target on target.id = settings.profile_id
  where settings.follow_on_signup
    and not settings.hidden_from_suggestions
    and target.id <> new.id
    and target.deleted_at is null
    and not target.is_private_profile
    and not app.is_blocked(new.id, target.id)
  on conflict (follower_user_id, followed_user_id) do nothing;
  return new;
end;
$$;
revoke all on function app.apply_signup_default_follows() from public, anon, authenticated;
create trigger profiles_signup_default_follows after insert on public.profiles
  for each row execute function app.apply_signup_default_follows();

-- Preserve the invoker/RLS boundary, return shape, volatility, search_path and grants
-- from 20260717180000. Priority never overrides blocks/privacy/already-followed filtering.
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
      coalesce(settings.suggestion_priority, 0) as suggestion_priority,
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
    left join app.profile_discovery_settings settings on settings.profile_id = profile.id
    cross join viewer
    where viewer.id is not null
      and profile.id <> viewer.id
      and profile.deleted_at is null
      and not coalesce(settings.hidden_from_suggestions, false)
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
          candidate.suggestion_priority desc,
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

revoke all on function app.discover_profile_recommendations(integer) from public, anon;
grant execute on function app.discover_profile_recommendations(integer) to authenticated;

commit;
