begin;

-- Own-place saves are a controlled RPC: callers cannot choose user_id, and
-- all writes are scoped to app.current_user_id(). Run it as a definer so the
-- canonical places upsert does not fail RLS when the row already exists.
alter function app.save_own_place(jsonb, jsonb, jsonb)
  security definer;

alter function app.save_own_place(jsonb, jsonb, jsonb)
  set search_path = public, app;

revoke all on function app.save_own_place(jsonb, jsonb, jsonb) from public, anon;
grant execute on function app.save_own_place(jsonb, jsonb, jsonb) to authenticated;

commit;
