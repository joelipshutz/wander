begin;

-- Check-in answers describe the source owner's observation. Do not copy them
-- into another person's invitation, including snapshots stored by older apps.
-- This tightens the two existing projections without rewriting stored history
-- or changing their callers, table policies, or execute grants.
create or replace function app.private_taxonomy_snapshot_projection(input_snapshot jsonb)
returns jsonb
language sql
immutable
security invoker
set search_path = ''
as $$
  select case
    when input_snapshot is null then null
    when jsonb_typeof(input_snapshot) <> 'object' then input_snapshot
    else jsonb_set(
      input_snapshot,
      '{attribute_answers}',
      coalesce((
        select jsonb_agg(answer.value order by answer.ordinality)
        from jsonb_array_elements(
          case
            when jsonb_typeof(input_snapshot->'attribute_answers') = 'array'
              then input_snapshot->'attribute_answers'
            else '[]'::jsonb
          end
        ) with ordinality answer(value, ordinality)
        where answer.value->>'question_key' is distinct from 'restaurant_cuisine'
          and left(coalesce(answer.value->>'question_key', ''), 13) <> 'place_detail_'
          and left(coalesce(answer.value->>'question_key', ''), 16) <> 'custom_question_'
      ), '[]'::jsonb),
      true
    )
  end
$$;

create or replace function app.shared_visit_source_snapshot(input_source_visit_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, app
as $$
  select app.private_taxonomy_snapshot_projection(jsonb_build_object(
    'visited_at', source_visit.visited_at,
    'note', source_visit.note,
    'rating_score', source_visit.rating_score,
    'attribute_answers', source_visit.attribute_answers,
    'tags', to_jsonb(source_visit.tags),
    'photos', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'photo_id', photo.id,
          'storage_bucket', photo.storage_bucket,
          'storage_path', photo.storage_path,
          'content_type', photo.content_type,
          'byte_size', photo.byte_size,
          'width', photo.width,
          'height', photo.height,
          'captured_at', photo.captured_at,
          'sort_order', photo.sort_order
        ) order by photo.sort_order, photo.created_at
      )
      from public.visit_photos photo
      where photo.visit_id = source_visit.id
        and photo.deleted_at is null
        and photo.upload_state = 'uploaded'
    ), '[]'::jsonb)
  ))
  from public.place_visits source_visit
  where source_visit.id = input_source_visit_id
    and source_visit.deleted_at is null
$$;

revoke all on function app.private_taxonomy_snapshot_projection(jsonb) from public, anon, authenticated;
revoke all on function app.shared_visit_source_snapshot(uuid) from public, anon, authenticated;

comment on function app.private_taxonomy_snapshot_projection(jsonb) is
  'Removes private food type and firsthand question answers from current and legacy shared-visit snapshot reads without changing stored history.';
comment on function app.shared_visit_source_snapshot(uuid) is
  'Builds an invitation snapshot without private food type or the source owner''s firsthand question answers. Ordinary tags, note, rating, and uploaded photos retain their established behavior.';

do $$
begin
  if not exists (select 1 from pg_proc
    where oid = 'app.private_taxonomy_snapshot_projection(jsonb)'::regprocedure
      and not prosecdef and provolatile = 'i'
      and ('search_path=""' = any(proconfig) or 'search_path=' = any(proconfig))) then
    raise exception 'Question snapshot projection metadata changed';
  end if;
  if not exists (select 1 from pg_proc
    where oid = 'app.shared_visit_source_snapshot(uuid)'::regprocedure
      and prosecdef and provolatile = 's'
      and 'search_path=public, app' = any(proconfig)) then
    raise exception 'Shared visit snapshot source metadata changed';
  end if;
  if has_function_privilege('anon', 'app.private_taxonomy_snapshot_projection(jsonb)', 'execute')
    or has_function_privilege('authenticated', 'app.private_taxonomy_snapshot_projection(jsonb)', 'execute')
    or has_function_privilege('anon', 'app.shared_visit_source_snapshot(uuid)', 'execute')
    or has_function_privilege('authenticated', 'app.shared_visit_source_snapshot(uuid)', 'execute') then
    raise exception 'Private snapshot helper grants changed';
  end if;
end;
$$;

commit;
