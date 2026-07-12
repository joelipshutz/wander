-- Restrict place-list RPC execution to authenticated app users.

revoke all on function app.is_place_list_owner(uuid, text) from public, anon;
revoke all on function app.is_place_list_member(uuid, text) from public, anon;
revoke all on function app.can_read_place_list(uuid, text) from public, anon;
revoke all on function app.visible_place_lists() from public, anon;
revoke all on function app.place_list_detail(uuid) from public, anon;
revoke all on function app.upsert_place_list(jsonb) from public, anon;
revoke all on function app.delete_place_list(uuid) from public, anon;
revoke all on function app.set_place_list_collaborators(uuid, text[]) from public, anon;
revoke all on function app.add_place_list_item(uuid, uuid, uuid, uuid) from public, anon;
revoke all on function app.remove_place_list_item(uuid, uuid) from public, anon;

revoke all on function public.visible_place_lists() from public, anon;
revoke all on function public.place_list_detail(uuid) from public, anon;
revoke all on function public.upsert_place_list(jsonb) from public, anon;
revoke all on function public.delete_place_list(uuid) from public, anon;
revoke all on function public.set_place_list_collaborators(uuid, text[]) from public, anon;
revoke all on function public.add_place_list_item(uuid, uuid, uuid, uuid) from public, anon;
revoke all on function public.remove_place_list_item(uuid, uuid) from public, anon;

grant usage on schema app to authenticated;
grant execute on function app.is_place_list_owner(uuid, text) to authenticated;
grant execute on function app.is_place_list_member(uuid, text) to authenticated;
grant execute on function app.can_read_place_list(uuid, text) to authenticated;
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
