begin;

-- Build 44's rating reset recreated this RPC as SECURITY INVOKER. Own-place
-- saves are still a controlled RPC: callers cannot choose user_id, and all
-- user-owned writes are scoped to app.current_user_id(). Keep it as a definer
-- function so canonical place upserts do not fall back to local-only failures
-- when RLS blocks direct writes through the authenticated caller.
alter function app.save_own_place(jsonb, jsonb, jsonb)
  security definer;

alter function app.save_own_place(jsonb, jsonb, jsonb)
  set search_path = public, app;

revoke all on function app.save_own_place(jsonb, jsonb, jsonb) from public, anon;
grant execute on function app.save_own_place(jsonb, jsonb, jsonb) to authenticated;

commit;
