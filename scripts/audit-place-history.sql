-- Read-only saved-place consistency audit. Run against the linked database.
-- Uses transaction-local authenticated claims for each owner with active saves,
-- and reports aggregates only. No user records or permissions are changed.
-- A clean result verifies the server contract; device caches and rendering
-- additionally require the iOS history/map regression tests.
begin;

create temporary table place_history_audit (
  expected_count integer,
  returned_count integer,
  missing_count integer,
  unexpected_count integer,
  status_mismatch_count integer
) on commit drop;

do $$
declare
  viewer record;
  expected_ids uuid[];
  actual_ids uuid[];
  wrong_status integer;
begin
  for viewer in select distinct user_id from public.user_places where deleted_at is null loop
    perform set_config('request.jwt.claims', jsonb_build_object(
      'sub', viewer.user_id, 'role', 'authenticated'
    )::text, true);
    set local role authenticated;

    -- RLS-authorized rows are the expected set, independently of the map RPC.
    select coalesce(array_agg(id), '{}'::uuid[]) into expected_ids
    from public.user_places where deleted_at is null;
    select coalesce(array_agg(user_place_id), '{}'::uuid[]) into actual_ids
    from public.visible_places_in_view(-90, -180, 90, 180, null, null, null);
    select count(*) into wrong_status
    from public.visible_places_in_view(-90, -180, 90, 180, null, null, null) r
    join public.user_places u on u.id = r.user_place_id
    where r.status <> u.status;

    reset role;
    insert into place_history_audit values (
      cardinality(expected_ids), cardinality(actual_ids),
      (select count(*) from unnest(expected_ids) e where not (e = any(actual_ids))),
      (select count(*) from unnest(actual_ids) a where not (a = any(expected_ids))),
      wrong_status
    );
  end loop;
end $$;

select count(*) as accounts_checked,
       sum(expected_count) as authorized_save_projections,
       sum(returned_count) as returned_save_projections,
       sum(missing_count) as missing,
       sum(unexpected_count) as unexpected,
       sum(status_mismatch_count) as status_mismatches
from place_history_audit;

select count(*) as active_saves,
       count(distinct place_id) as saved_place_records,
       count(*) filter (where status = 'been') as check_in_saves,
       count(*) filter (where status = 'wanna_go') as wanna_saves,
       count(*) filter (
         where status = 'wanna_go' and exists (
           select 1 from public.place_visits v where v.user_place_id = u.id and v.deleted_at is null
         )
       ) as wannas_with_active_check_ins,
       count(*) filter (
         where status = 'been' and not exists (
           select 1 from public.place_visits v where v.user_place_id = u.id and v.deleted_at is null
         )
       ) as check_in_saves_without_active_visits
from public.user_places u where deleted_at is null;

-- Roll back temporary state and restore the original session claims/role.
rollback;
