-- Repair hosted place-list RPC privileges for authenticated app users.
-- These grants are idempotent and intentionally cover both the public RPC
-- wrappers and the app-schema helpers they invoke.

grant usage on schema app to authenticated;

grant select, insert, update, delete on public.place_lists to authenticated;
grant select, insert, update, delete on public.place_list_members to authenticated;
grant select, insert, update, delete on public.place_list_items to authenticated;

grant execute on function app.visible_place_lists() to authenticated;
grant execute on function app.place_list_detail(uuid) to authenticated;
grant execute on function app.upsert_place_list(jsonb) to authenticated;
grant execute on function app.delete_place_list(uuid) to authenticated;
grant execute on function app.set_place_list_collaborators(uuid, text[]) to authenticated;
grant execute on function app.add_place_list_item(uuid, uuid, uuid, uuid) to authenticated;
grant execute on function app.remove_place_list_item(uuid, uuid) to authenticated;

grant execute on function public.visible_place_lists() to authenticated;
grant execute on function public.place_list_detail(uuid) to authenticated;
grant execute on function public.upsert_place_list(jsonb) to authenticated;
grant execute on function public.delete_place_list(uuid) to authenticated;
grant execute on function public.set_place_list_collaborators(uuid, text[]) to authenticated;
grant execute on function public.add_place_list_item(uuid, uuid, uuid, uuid) to authenticated;
grant execute on function public.remove_place_list_item(uuid, uuid) to authenticated;
