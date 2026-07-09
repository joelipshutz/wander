-- Allow list collaborators to add places while keeping list settings owner-only.

drop policy if exists "place list items owner writes" on public.place_list_items;
drop policy if exists "place list items owner or collaborator inserts" on public.place_list_items;
drop policy if exists "place list items owner updates" on public.place_list_items;
drop policy if exists "place list items owner deletes" on public.place_list_items;

create policy "place list items owner or collaborator inserts"
  on public.place_list_items for insert
  with check (
    (
      app.is_place_list_owner(list_id, app.current_user_id())
      or exists (
        select 1
        from public.place_list_members plm
        where plm.list_id = place_list_items.list_id
          and plm.user_id = app.current_user_id()
          and plm.deleted_at is null
      )
    )
    and added_by_user_id = app.current_user_id()
    and exists (
      select 1
      from public.user_places up
      where up.id = coalesce(owner_user_place_id, source_user_place_id)
        and up.place_id = place_id
        and up.deleted_at is null
        and app.can_read_user_place(app.current_user_id(), up.user_id, up.visibility)
    )
  );

create policy "place list items owner updates"
  on public.place_list_items for update
  using (app.is_place_list_owner(list_id, app.current_user_id()))
  with check (
    app.is_place_list_owner(list_id, app.current_user_id())
    and added_by_user_id = app.current_user_id()
    and exists (
      select 1
      from public.user_places up
      where up.id = coalesce(owner_user_place_id, source_user_place_id)
        and up.place_id = place_id
        and up.deleted_at is null
        and app.can_read_user_place(app.current_user_id(), up.user_id, up.visibility)
    )
  );

create policy "place list items owner deletes"
  on public.place_list_items for delete
  using (app.is_place_list_owner(list_id, app.current_user_id()));

create or replace function app.add_place_list_item(
  input_list_id uuid,
  input_place_id uuid,
  input_owner_user_place_id uuid default null,
  input_source_user_place_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  output_id uuid;
begin
  if not (
    app.is_place_list_owner(input_list_id, viewer_id)
    or exists (
      select 1
      from public.place_list_members plm
      where plm.list_id = input_list_id
        and plm.user_id = viewer_id
        and plm.deleted_at is null
    )
  ) then
    raise exception 'place_list_not_found_or_forbidden';
  end if;

  if not exists (
    select 1
    from public.user_places up
    where up.id = coalesce(input_owner_user_place_id, input_source_user_place_id)
      and up.place_id = input_place_id
      and up.deleted_at is null
      and app.can_read_user_place(viewer_id, up.user_id, up.visibility)
  ) then
    raise exception 'place_not_visible';
  end if;

  insert into public.place_list_items(
    list_id,
    place_id,
    owner_user_place_id,
    source_user_place_id,
    added_by_user_id
  )
  values (
    input_list_id,
    input_place_id,
    input_owner_user_place_id,
    input_source_user_place_id,
    viewer_id
  )
  on conflict (list_id, place_id) where deleted_at is null do update
    set owner_user_place_id = excluded.owner_user_place_id,
        source_user_place_id = excluded.source_user_place_id,
        added_by_user_id = excluded.added_by_user_id,
        deleted_at = null
  returning id into output_id;

  update public.place_lists
  set updated_at = now()
  where id = input_list_id;

  return output_id;
end;
$$;
