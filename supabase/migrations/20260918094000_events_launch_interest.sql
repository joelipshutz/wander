begin;

-- REC-542: explicit interest in the upcoming Events launch. No notification
-- preferences change here. The first opt-in is retained across retries.
create table public.events_launch_interest (
  user_id text primary key references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.events_launch_interest enable row level security;
revoke all on table public.events_launch_interest from public, anon, authenticated;
grant select, insert, update, delete on table public.events_launch_interest to service_role;

-- Narrow definer RPCs intentionally keep the roster inaccessible to clients.
-- Both derive identity from the signed session and exclude deleted accounts.
create function public.own_events_launch_interest()
returns table (created_at timestamptz)
language plpgsql stable security definer
set search_path = public, app
as $$
declare viewer_id text := app.current_user_id();
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  return query
  select interest.created_at
  from public.events_launch_interest interest
  join public.profiles profile on profile.id = interest.user_id
  where interest.user_id = viewer_id and profile.deleted_at is null;
end;
$$;

create function public.register_events_launch_interest()
returns table (created_at timestamptz)
language plpgsql volatile security definer
set search_path = public, app
as $$
declare viewer_id text := app.current_user_id();
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  perform 1 from public.profiles where id = viewer_id and deleted_at is null for share;
  if not found then raise exception 'profile_not_found'; end if;
  insert into public.events_launch_interest (user_id) values (viewer_id)
  on conflict (user_id) do nothing;
  return query select interest.created_at
    from public.events_launch_interest interest where interest.user_id = viewer_id;
end;
$$;

revoke all on function public.own_events_launch_interest() from public, anon, authenticated;
revoke all on function public.register_events_launch_interest() from public, anon, authenticated;
grant execute on function public.own_events_launch_interest() to authenticated;
grant execute on function public.register_events_launch_interest() to authenticated;

comment on table public.events_launch_interest is
  'Events Keep me posted opt-ins. One canonical profile ID and first confirmed opt-in timestamp per account. Private roster for Astir operations; clients use owner-only RPCs.';

commit;
