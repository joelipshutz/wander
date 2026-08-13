begin;

-- The public Clerk mirror is a service-role webhook boundary. The original
-- wrapper revoked PUBLIC but retained cloud-generated direct grants for the
-- Data API roles, which made this security-definer function client-callable.
revoke execute on function public.mirror_clerk_profile(
  text,
  text,
  timestamptz,
  text,
  text,
  text,
  text
) from public, anon, authenticated;

grant execute on function public.mirror_clerk_profile(
  text,
  text,
  timestamptz,
  text,
  text,
  text,
  text
) to service_role;

-- Analytics events are signed-in, self-attributed writes. Anonymous/null-user
-- ingestion was never used by the app and allowed unauthenticated spam.
drop policy if exists "analytics insert authenticated self" on public.analytics_events;
drop policy if exists "analytics read own" on public.analytics_events;

create policy "analytics insert authenticated self"
  on public.analytics_events for insert
  to authenticated
  with check (user_id = app.current_user_id());

create policy "analytics read own"
  on public.analytics_events for select
  to authenticated
  using (user_id = app.current_user_id());

revoke all privileges on table public.analytics_events from anon;
revoke update, delete, truncate, references, trigger on table public.analytics_events from authenticated;
grant select, insert on table public.analytics_events to authenticated;

-- Qualify outer-row columns explicitly. Without qualification, PostgreSQL
-- binds `place_id` to the inner `user_places` row, reducing the equality to a
-- tautology and allowing a list item to reference a mismatched place.
drop policy if exists "place list items owner or collaborator inserts" on public.place_list_items;
drop policy if exists "place list items owner updates" on public.place_list_items;

create policy "place list items owner or collaborator inserts"
  on public.place_list_items for insert
  to authenticated
  with check (
    (
      app.is_place_list_owner(place_list_items.list_id, app.current_user_id())
      or exists (
        select 1
        from public.place_list_members plm
        where plm.list_id = place_list_items.list_id
          and plm.user_id = app.current_user_id()
          and plm.deleted_at is null
      )
    )
    and place_list_items.added_by_user_id = app.current_user_id()
    and exists (
      select 1
      from public.user_places up
      where up.id = coalesce(
        place_list_items.owner_user_place_id,
        place_list_items.source_user_place_id
      )
        and up.place_id = place_list_items.place_id
        and up.deleted_at is null
        and app.can_read_user_place(app.current_user_id(), up.user_id, up.visibility)
    )
  );

create policy "place list items owner updates"
  on public.place_list_items for update
  to authenticated
  using (app.is_place_list_owner(place_list_items.list_id, app.current_user_id()))
  with check (
    app.is_place_list_owner(place_list_items.list_id, app.current_user_id())
    and place_list_items.added_by_user_id = app.current_user_id()
    and exists (
      select 1
      from public.user_places up
      where up.id = coalesce(
        place_list_items.owner_user_place_id,
        place_list_items.source_user_place_id
      )
        and up.place_id = place_list_items.place_id
        and up.deleted_at is null
        and app.can_read_user_place(app.current_user_id(), up.user_id, up.visibility)
    )
  );

commit;
