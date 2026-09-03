begin;

alter table public.place_lists add column snapshot_cover_path text
  check (snapshot_cover_path is null or snapshot_cover_path = id::text || '/snapshot.jpg');

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('list-snapshots', 'list-snapshots', false, 1048576, array['image/jpeg']);

-- All access is inherited from the existing list contract. A removed
-- collaborator, blocked viewer, or deleted list cannot read its snapshot.
create policy list_snapshot_read on storage.objects for select to authenticated
using (bucket_id = 'list-snapshots' and exists (
  select 1 from public.place_lists pl
  where storage.objects.name = pl.id::text || '/snapshot.jpg'
    and pl.deleted_at is null
    and app.can_read_place_list(pl.id, app.current_user_id())
));

create policy list_snapshot_insert on storage.objects for insert to authenticated
with check (bucket_id = 'list-snapshots' and exists (
  select 1 from public.place_lists pl
  where storage.objects.name = pl.id::text || '/snapshot.jpg'
    and pl.owner_user_id = app.current_user_id() and pl.deleted_at is null
));

create policy list_snapshot_update on storage.objects for update to authenticated
using (bucket_id = 'list-snapshots' and exists (
  select 1 from public.place_lists pl
  where storage.objects.name = pl.id::text || '/snapshot.jpg'
    and pl.owner_user_id = app.current_user_id() and pl.deleted_at is null
))
with check (bucket_id = 'list-snapshots' and exists (
  select 1 from public.place_lists pl
  where storage.objects.name = pl.id::text || '/snapshot.jpg'
    and pl.owner_user_id = app.current_user_id() and pl.deleted_at is null
));

create policy list_snapshot_delete on storage.objects for delete to authenticated
using (bucket_id = 'list-snapshots' and exists (
  select 1 from public.place_lists pl
  where storage.objects.name = pl.id::text || '/snapshot.jpg' and pl.owner_user_id = app.current_user_id()
));

-- Narrow definer mutation mirrors the existing owner-only list write model.
-- Caller cannot choose a user or arbitrary storage path; the object must exist.
create function app.set_place_list_snapshot_cover(input_list_id uuid)
returns void language plpgsql security definer set search_path = public, app
as $$
begin
  if app.current_user_id() is null then raise exception 'not_authenticated'; end if;
  update public.place_lists pl
  set snapshot_cover_path = pl.id::text || '/snapshot.jpg', updated_at = now()
  where pl.id = input_list_id and pl.owner_user_id = app.current_user_id()
    and pl.deleted_at is null and exists (
      select 1 from storage.objects o
      where o.bucket_id = 'list-snapshots' and o.name = pl.id::text || '/snapshot.jpg'
    );
  if not found then raise exception 'place_list_snapshot_not_found_or_forbidden'; end if;
end;
$$;

-- Invoker wrapper delegates to the scoped app function; no additional bypass.
create function public.set_place_list_snapshot_cover(input_list_id uuid)
returns void language sql security invoker set search_path = public, app
as $$ select app.set_place_list_snapshot_cover(input_list_id); $$;

revoke all on function app.set_place_list_snapshot_cover(uuid) from public, anon;
revoke all on function public.set_place_list_snapshot_cover(uuid) from public, anon;
grant execute on function app.set_place_list_snapshot_cover(uuid) to authenticated;
grant execute on function public.set_place_list_snapshot_cover(uuid) to authenticated;

commit;
