begin;

create or replace function app.save_visible_place(input_place_id uuid, input_source_user_place_id uuid)
returns public.user_places
language plpgsql
security invoker
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  source_row public.user_places;
  saved_row public.user_places;
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;

  select *
  into source_row
  from public.user_places up
  where up.id = input_source_user_place_id
    and up.place_id = input_place_id
    and up.deleted_at is null;

  if source_row.id is null then
    raise exception 'source_not_visible';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'recme:user-place:' || viewer_id || ':' || input_place_id::text,
      0
    )
  );

  select *
  into saved_row
  from public.user_places up
  where up.user_id = viewer_id
    and up.place_id = input_place_id
    and up.deleted_at is null
    and up.status = 'been';

  if saved_row.id is not null then
    return saved_row;
  end if;

  insert into public.user_places (
    user_id,
    place_id,
    status,
    note,
    rating_signal,
    visibility,
    source_type,
    source_user_place_id,
    attribution_user_id
  )
  values (
    viewer_id,
    input_place_id,
    'wanna_go',
    null,
    source_row.rating_signal,
    'followers',
    'social_save',
    source_row.id,
    source_row.user_id
  )
  on conflict (user_id, place_id)
  do update set
    status = excluded.status,
    rating_signal = excluded.rating_signal,
    source_type = excluded.source_type,
    source_user_place_id = excluded.source_user_place_id,
    attribution_user_id = excluded.attribution_user_id,
    deleted_at = null,
    updated_at = now()
  returning * into saved_row;

  insert into public.place_attributes (user_place_id, question_definition_id, question_key, value_type, value)
  select saved_row.id, pa.question_definition_id, pa.question_key, pa.value_type, pa.value
  from public.place_attributes pa
  where pa.user_place_id = source_row.id
  on conflict (user_place_id, question_key)
  do update set
    question_definition_id = excluded.question_definition_id,
    value_type = excluded.value_type,
    value = excluded.value,
    updated_at = now();

  return saved_row;
end;
$$;

comment on function app.save_visible_place(uuid, uuid) is
  'Saves a visible place for the authenticated account without copying another memory note or overwriting the viewer''s existing note.';

revoke all on function app.save_visible_place(uuid, uuid) from public, anon;
grant execute on function app.save_visible_place(uuid, uuid) to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_proc
    where oid = 'app.save_visible_place(uuid,uuid)'::regprocedure
      and not prosecdef
      and 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
  ) then
    raise exception 'app.save_visible_place security posture changed';
  end if;

  if not has_function_privilege('authenticated', 'app.save_visible_place(uuid,uuid)', 'execute')
     or has_function_privilege('anon', 'app.save_visible_place(uuid,uuid)', 'execute') then
    raise exception 'app.save_visible_place grants are invalid';
  end if;
end;
$$;

commit;
