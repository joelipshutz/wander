begin;

-- Internal counters protect the shared Google Places credential from both
-- accidental overage and authenticated abuse. Callers never read or write the
-- counters directly; ownership is derived only from app.current_user_id().
create table if not exists app.place_photo_request_counters (
  scope text primary key,
  period_key text not null,
  request_count integer not null check (request_count >= 0),
  updated_at timestamptz not null default now()
);

revoke all on table app.place_photo_request_counters from public, anon, authenticated;

create or replace function public.consume_place_photo_quota()
returns boolean
language plpgsql
volatile
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  global_period text := to_char(statement_timestamp() at time zone 'UTC', 'YYYY-MM');
  user_period text := to_char(statement_timestamp() at time zone 'UTC', 'YYYY-MM-DD');
  global_scope text := 'global';
  user_scope text;
  global_count integer := 0;
  user_count integer := 0;
begin
  if viewer_id is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  user_scope := 'user:' || viewer_id;

  -- Low-volume alpha traffic makes one transaction-scoped lock preferable to
  -- a race that could exceed the hard monthly ceiling under concurrent opens.
  perform pg_advisory_xact_lock(hashtext('recme_place_photo_quota'));

  select c.request_count into global_count
  from app.place_photo_request_counters c
  where c.scope = global_scope and c.period_key = global_period;

  select c.request_count into user_count
  from app.place_photo_request_counters c
  where c.scope = user_scope and c.period_key = user_period;

  if coalesce(global_count, 0) >= 900 or coalesce(user_count, 0) >= 120 then
    return false;
  end if;

  insert into app.place_photo_request_counters (scope, period_key, request_count, updated_at)
  values (global_scope, global_period, 1, now())
  on conflict (scope) do update
  set period_key = excluded.period_key,
      request_count = case
        when app.place_photo_request_counters.period_key = excluded.period_key
          then app.place_photo_request_counters.request_count + 1
        else 1
      end,
      updated_at = now();

  insert into app.place_photo_request_counters (scope, period_key, request_count, updated_at)
  values (user_scope, user_period, 1, now())
  on conflict (scope) do update
  set period_key = excluded.period_key,
      request_count = case
        when app.place_photo_request_counters.period_key = excluded.period_key
          then app.place_photo_request_counters.request_count + 1
        else 1
      end,
      updated_at = now();

  return true;
end;
$$;

revoke all on function public.consume_place_photo_quota() from public, anon;
grant execute on function public.consume_place_photo_quota() to authenticated;

commit;
