create or replace function app.can_read_place_list(input_list_id uuid, viewer_id text)
returns boolean
language sql
stable
security definer
set search_path = public, app
as $$
  select exists (
    select 1
    from public.place_lists pl
    where pl.id = input_list_id
      and pl.deleted_at is null
      and viewer_id is not null
      and not app.is_blocked(viewer_id, pl.owner_user_id)
      and not exists (
        select 1
        from public.place_list_members previous_membership
        where previous_membership.list_id = pl.id
          and previous_membership.user_id = viewer_id
          and previous_membership.deleted_at is not null
      )
      and (
        pl.owner_user_id = viewer_id
        or app.is_place_list_member(pl.id, viewer_id)
        or (
          pl.visibility = 'followers'
          and app.follows(viewer_id, pl.owner_user_id)
        )
      )
  );
$$;

create or replace function app.leave_place_list(input_list_id uuid)
returns void
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  affected_rows integer;
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;

  if app.is_place_list_owner(input_list_id, viewer_id) then
    raise exception 'place_list_owner_cannot_leave';
  end if;

  update public.place_list_members
  set deleted_at = now()
  where list_id = input_list_id
    and user_id = viewer_id
    and deleted_at is null;

  get diagnostics affected_rows = row_count;
  if affected_rows = 0 then
    raise exception 'place_list_not_found_or_forbidden';
  end if;

  update public.place_lists
  set updated_at = now()
  where id = input_list_id
    and deleted_at is null;
end;
$$;

create or replace function public.leave_place_list(input_list_id uuid)
returns void
language sql
security invoker
set search_path = app, public
as $$
  select app.leave_place_list(input_list_id);
$$;

revoke all on function app.leave_place_list(uuid) from public, anon, authenticated;
revoke all on function public.leave_place_list(uuid) from public, anon;
grant execute on function public.leave_place_list(uuid) to authenticated;

comment on function public.leave_place_list(uuid) is
  'Removes the authenticated collaborator from a shared list and revokes future follower visibility until re-invited.';
