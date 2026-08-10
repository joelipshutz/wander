-- Allow the authenticated public security-invoker wrapper to invoke its
-- private app-schema implementation, matching the established place-list RPC pattern.
grant usage on schema app to authenticated;
revoke all on function app.leave_place_list(uuid) from public, anon;
grant execute on function app.leave_place_list(uuid) to authenticated;
