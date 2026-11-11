begin;
set local lock_timeout = '5s';

-- Capture identity is distinct from the cover upload: a failed upload must not
-- turn the initial members into ordinary list-add activity on retry.
alter table public.place_lists add column snapshot_capture_id uuid unique;

-- Preserve the private volatile SECURITY DEFINER trigger and pinned path from
-- 20260720234500_feed_activity.sql. Only the scoped creation RPC sets this
-- transaction-local marker, and it restores the previous value before return.
create or replace function app.record_place_list_item_feed_event()
returns trigger language plpgsql volatile security definer
set search_path = public, app
as $$
declare source_user_place_id uuid;
begin
  if new.deleted_at is not null then return new; end if;
  if tg_op = 'UPDATE' and old.deleted_at is null then return new; end if;
  if tg_op = 'INSERT'
     and current_setting('app.map_snapshot_list_id', true) = new.list_id::text
     and exists (select 1 from public.place_lists pl where pl.id = new.list_id
       and pl.snapshot_capture_id is not null and pl.owner_user_id = new.added_by_user_id)
  then return new; end if;
  source_user_place_id := coalesce(new.owner_user_place_id, new.source_user_place_id);
  if source_user_place_id is null then return new; end if;
  perform app.record_feed_event(new.added_by_user_id, 'list_item_added',
    source_user_place_id, new.place_id, new.list_id, new.id);
  return new;
end;
$$;
revoke all on function app.record_place_list_item_feed_event() from public, anon, authenticated;

-- Owner-only, atomic, idempotent creation. The caller cannot select an actor
-- or seed another person's saves. Existing list/add functions retain their
-- authorization, taxonomy, notification and source-save behavior.
create function app.create_map_snapshot_list(
  input_snapshot_id uuid, input_list jsonb, input_user_place_ids uuid[]
)
returns uuid language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare
  viewer_id text := app.current_user_id();
  output_id uuid;
  source public.user_places;
  source_id uuid;
  prior_marker text := coalesce(current_setting('app.map_snapshot_list_id', true), '');
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  if input_snapshot_id is null or input_user_place_ids is null then
    raise exception 'invalid_snapshot_capture';
  end if;
  -- A unique capture key serializes concurrent retries. A lost response cannot
  -- create another list, reseed removed places, or resurrect a deleted list.
  insert into public.place_lists(id, owner_user_id, name, description, visibility, snapshot_capture_id)
  values (input_snapshot_id, viewer_id, trim(input_list->>'name'),
    coalesce(input_list->>'description', ''),
    coalesce(nullif(input_list->>'visibility', ''), 'stealth'), input_snapshot_id)
  on conflict (id) do nothing returning id into output_id;
  if output_id is null then
    if not exists (select 1 from public.place_lists pl where pl.id = input_snapshot_id
      and pl.snapshot_capture_id = input_snapshot_id and pl.owner_user_id = viewer_id
      and pl.deleted_at is null) then
      raise exception 'place_list_not_found_or_forbidden';
    end if;
    return app.upsert_place_list(input_list || jsonb_build_object('id', input_snapshot_id));
  end if;

  perform set_config('app.map_snapshot_list_id', output_id::text, true);
  for source_id in select distinct unnest(input_user_place_ids) loop
    select * into source from public.user_places up
    where up.id = source_id and up.user_id = viewer_id and up.deleted_at is null;
    if not found then raise exception 'snapshot_source_not_owned'; end if;
    perform app.add_place_list_item(output_id, source.place_id, source.id, null);
  end loop;
  perform set_config('app.map_snapshot_list_id', prior_marker, true);
  return output_id;
end;
$$;

create function public.create_map_snapshot_list(
  input_snapshot_id uuid, input_list jsonb, input_user_place_ids uuid[]
)
returns uuid language sql volatile security invoker
set search_path = pg_catalog, public, app
as $$ select app.create_map_snapshot_list(input_snapshot_id, input_list, input_user_place_ids); $$;
revoke all on function app.create_map_snapshot_list(uuid, jsonb, uuid[]) from public, anon;
revoke all on function public.create_map_snapshot_list(uuid, jsonb, uuid[]) from public, anon;
grant execute on function app.create_map_snapshot_list(uuid, jsonb, uuid[]) to authenticated;
grant execute on function public.create_map_snapshot_list(uuid, jsonb, uuid[]) to authenticated;

-- Preserve the private STABLE definer projection from 20260725214600.
-- Visibility stays with the existing feed/detail callers and storage RLS.
create or replace function app.feed_list_projection(input_list_id uuid)
returns jsonb language sql stable security definer set search_path = public, app
as $$
  select jsonb_build_object(
    'id', list.id, 'owner_user_id', list.owner_user_id, 'name', list.name,
    'description', list.description, 'visibility', list.visibility,
    'snapshot_capture_id', list.snapshot_capture_id,
    'snapshot_cover_path', list.snapshot_cover_path,
    'item_count', (select count(*)::integer from public.place_list_items item
      where item.list_id = list.id and item.deleted_at is null),
    'created_at', list.created_at, 'updated_at', list.updated_at)
  from public.place_lists list where list.id = input_list_id and list.deleted_at is null
$$;
revoke all on function app.feed_list_projection(uuid) from public, anon, authenticated;

-- Historical audit found no active uploaded snapshots. Do not resurrect or
-- rewrite deleted lists, or infer capture membership from timestamps/names.
commit;
