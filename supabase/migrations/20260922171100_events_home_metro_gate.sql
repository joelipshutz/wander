begin;

-- REC-584: residence is the member's saved home choice, not current GPS or a
-- phone area code. Keep this read narrow so tab hydration never fetches phone.
create function public.own_events_market_access()
returns table (metro_id text)
language plpgsql stable security definer set search_path = public, app
as $$
declare viewer_id text := app.current_user_id();
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  return query select d.metro_id from public.profiles p
    left join public.account_contact_details d on d.user_id = p.id
    where p.id = viewer_id and p.deleted_at is null;
end;
$$;
revoke all on function public.own_events_market_access() from public, anon, authenticated;
grant execute on function public.own_events_market_access() to authenticated;

-- Preserve the original narrow definer posture, output, stability and canonical
-- JWT ownership from 20260918094000_events_launch_interest.sql. Old registrations
-- remain retained, but ineligible members cannot read/register through Events.
create or replace function public.own_events_launch_interest()
returns table (created_at timestamptz)
language plpgsql stable security definer set search_path = public, app
as $$
declare viewer_id text := app.current_user_id();
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  return query select interest.created_at
    from public.events_launch_interest interest
    join public.profiles profile on profile.id = interest.user_id
    join public.account_contact_details details on details.user_id = interest.user_id
    where interest.user_id = viewer_id and profile.deleted_at is null
      and details.metro_id = 'los-angeles';
end;
$$;

create or replace function public.register_events_launch_interest()
returns table (created_at timestamptz)
language plpgsql volatile security definer set search_path = public, app
as $$
declare viewer_id text := app.current_user_id();
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  perform 1 from public.profiles where id = viewer_id and deleted_at is null for share;
  if not found then raise exception 'profile_not_found'; end if;
  perform 1 from public.account_contact_details
    where user_id = viewer_id and metro_id = 'los-angeles' for share;
  if not found then raise exception 'events_not_available_in_home_area'; end if;
  insert into public.events_launch_interest (user_id) values (viewer_id)
    on conflict (user_id) do nothing;
  return query select interest.created_at from public.events_launch_interest interest
    where interest.user_id = viewer_id;
end;
$$;
revoke all on function public.own_events_launch_interest() from public, anon, authenticated;
revoke all on function public.register_events_launch_interest() from public, anon, authenticated;
grant execute on function public.own_events_launch_interest() to authenticated;
grant execute on function public.register_events_launch_interest() to authenticated;

commit;
