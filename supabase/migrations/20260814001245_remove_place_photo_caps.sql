begin;

-- Google Cloud paid billing and budget monitoring are now the operational
-- controls for Google Places usage. Keep the existing authenticated RPC
-- contract so deployed Edge Functions can continue to fail closed when the
-- app session is invalid, but no longer read, increment, or enforce the legacy
-- global-monthly and per-user-daily counters.
create or replace function public.consume_place_photo_quota()
returns boolean
language plpgsql
volatile
security definer
set search_path = public, app
as $$
begin
  if app.current_user_id() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  return true;
end;
$$;

comment on function public.consume_place_photo_quota() is
  'Authenticates Google Places photo requests without applying an application-side usage cap; spend is monitored in Google Cloud billing.';

revoke all on function public.consume_place_photo_quota() from public, anon, authenticated;
grant execute on function public.consume_place_photo_quota() to authenticated;

commit;
