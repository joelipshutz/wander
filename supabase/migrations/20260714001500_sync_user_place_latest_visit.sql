begin;

-- user_places is the map/profile summary row. Explicit visit edits write to
-- place_visits, so keep its denormalized visit timestamp authoritative across
-- every insert, edit, soft-delete, and delete path.
create or replace function app.sync_user_place_latest_visit()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
declare
  affected_user_place_id uuid;
  latest_visited_at timestamptz;
begin
  -- Backfilled visits are derived from user_places by the existing inverse
  -- trigger. Skipping them prevents a recursive parent/child write cycle.
  if tg_op = 'DELETE' then
    if old.backfilled_from_user_place then
      return old;
    end if;
    affected_user_place_id := old.user_place_id;
  else
    if new.backfilled_from_user_place then
      return new;
    end if;
    affected_user_place_id := new.user_place_id;
  end if;

  select max(pv.visited_at)
  into latest_visited_at
  from public.place_visits pv
  where pv.user_place_id = affected_user_place_id
    and pv.deleted_at is null;

  update public.user_places up
  set visited_at = latest_visited_at,
      updated_at = now()
  where up.id = affected_user_place_id
    and up.status = 'been'
    and up.deleted_at is null
    and up.visited_at is distinct from latest_visited_at;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function app.sync_user_place_latest_visit() from public, anon, authenticated;

drop trigger if exists place_visits_sync_user_place_latest_visit on public.place_visits;
create trigger place_visits_sync_user_place_latest_visit
  after insert or update of visited_at, deleted_at or delete
  on public.place_visits
  for each row execute function app.sync_user_place_latest_visit();

with latest_visits as (
  select pv.user_place_id, max(pv.visited_at) as visited_at
  from public.place_visits pv
  where pv.deleted_at is null
  group by pv.user_place_id
)
update public.user_places up
set visited_at = latest_visits.visited_at,
    updated_at = now()
from latest_visits
where up.id = latest_visits.user_place_id
  and up.status = 'been'
  and up.deleted_at is null
  and up.visited_at is distinct from latest_visits.visited_at;

commit;
