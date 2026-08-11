-- Leaving ends collaborator privileges. It must not override the ordinary
-- follower visibility that applies to any other friend of the list owner.
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
