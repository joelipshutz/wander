begin;

-- The REST-exposed RPC must execute as its owner when it delegates to the
-- private `app.followed_feed` projection. Keeping the inner function private
-- prevents authenticated callers from bypassing the public API boundary while
-- preserving the projection's own security-definer visibility checks.
create or replace function public.followed_feed(
  input_before text default null,
  input_limit integer default 25
)
returns jsonb
language sql
stable
security definer
set search_path = app, public
as $$
  select app.followed_feed(input_before, input_limit);
$$;

revoke all on function public.followed_feed(text, integer) from public, anon;
grant execute on function public.followed_feed(text, integer) to authenticated;

comment on function public.followed_feed(text, integer) is
  'Authenticated Feed RPC. Invokes the private projection while preserving the request JWT for visibility checks.';

commit;
