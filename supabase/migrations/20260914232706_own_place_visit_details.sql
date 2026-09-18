begin;

-- REC-485: raw place_visits.attribute_answers remains inaccessible through
-- Data API SELECT. This projection returns only the authenticated owner's
-- history, so private taxonomy and older answers survive editing a synced visit.
-- No other person's answers are returned, regardless of follows or visibility.
create function public.own_place_visit_details(input_user_place_ids uuid[])
returns table (
  id uuid,
  user_place_id uuid,
  attribute_answers jsonb,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  requested_ids uuid[];
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;

  select coalesce(array_agg(distinct requested_id), '{}'::uuid[])
  into requested_ids
  from unnest(coalesce(input_user_place_ids, '{}'::uuid[])) requested_id
  where requested_id is not null;

  if cardinality(requested_ids) > 200 then
    raise exception 'too_many_user_place_ids';
  end if;

  return query
  select visit.id, visit.user_place_id, visit.attribute_answers,
         visit.created_at, visit.updated_at
  from public.place_visits visit
  join public.user_places parent on parent.id = visit.user_place_id
  join public.profiles owner on owner.id = parent.user_id
  where visit.user_place_id = any(requested_ids)
    and parent.user_id = viewer_id
    and visit.deleted_at is null
    and parent.deleted_at is null
    and owner.deleted_at is null
  order by visit.user_place_id, visit.visited_at desc, visit.id;
end;
$$;

revoke all on function public.own_place_visit_details(uuid[]) from public, anon, authenticated;
grant execute on function public.own_place_visit_details(uuid[]) to authenticated;

comment on function public.own_place_visit_details(uuid[]) is
  'Owner-only visit answer history in batches of up to 200 parent saves. Preserves complete answer JSON and source timestamps without granting raw answer-column access or exposing another user''s answers.';

do $$
begin
  if not exists (
    select 1 from pg_proc procedure
    where procedure.oid = 'public.own_place_visit_details(uuid[])'::regprocedure
      and procedure.prosecdef
      and procedure.provolatile = 's'
      and 'search_path=public, app' = any(coalesce(procedure.proconfig, array[]::text[]))
  ) then
    raise exception 'own_place_visit_details security posture changed';
  end if;
  if has_column_privilege('authenticated', 'public.place_visits', 'attribute_answers', 'select')
    or has_function_privilege('anon', 'public.own_place_visit_details(uuid[])', 'execute')
    or not has_function_privilege('authenticated', 'public.own_place_visit_details(uuid[])', 'execute') then
    raise exception 'own_place_visit_details grants changed';
  end if;
end;
$$;

commit;
