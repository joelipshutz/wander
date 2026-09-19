-- Only execute inside the smoke runner's rollback transaction.
reset role;
insert into public.profiles (id, handle, display_name, deleted_at) values
  ('user_codex_events_owner', 'codexeventsowner', 'Events Smoke Owner', null),
  ('user_codex_events_other', 'codexeventsother', 'Events Smoke Other', null)
on conflict (id) do update set deleted_at = null;
delete from public.events_launch_interest
where user_id in ('user_codex_events_owner', 'user_codex_events_other');

do $metadata$
declare signature text;
begin
  if not (select relrowsecurity from pg_class where oid = 'public.events_launch_interest'::regclass)
    or has_table_privilege('authenticated', 'public.events_launch_interest', 'select,insert,update,delete')
    or has_table_privilege('anon', 'public.events_launch_interest', 'select,insert,update,delete')
    or not has_table_privilege('service_role', 'public.events_launch_interest', 'select') then
    raise exception 'Events interest roster grants/RLS differ from contract';
  end if;
  foreach signature in array array['public.own_events_launch_interest()', 'public.register_events_launch_interest()'] loop
    if has_function_privilege('anon', signature, 'execute')
      or not has_function_privilege('authenticated', signature, 'execute')
      or not exists (select 1 from pg_proc where oid = signature::regprocedure
        and prosecdef and 'search_path=public, app' = any(proconfig) and pronargs = 0
        and provolatile = case when signature like '%register%' then 'v' else 's' end) then
      raise exception 'Events interest RPC security differs from contract: %', signature;
    end if;
  end loop;
end
$metadata$;

set local role authenticated;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.canonical_user_id', '', true);
select set_config('request.jwt.claim.sub', 'user_codex_events_owner', true);
do $behavior$
declare first_time timestamptz; repeated_time timestamptz;
begin
  if exists (select 1 from public.own_events_launch_interest()) then
    raise exception 'Fresh account is already registered';
  end if;
  select created_at into first_time from public.register_events_launch_interest();
  select created_at into repeated_time from public.register_events_launch_interest();
  if first_time is null or first_time is distinct from repeated_time
    or (select count(*) from public.own_events_launch_interest()) <> 1
    or (select created_at from public.own_events_launch_interest()) is distinct from first_time then
    raise exception 'Events registration is not persistent and idempotent';
  end if;
  -- Canonical profile identity survives Clerk subject migration.
  perform set_config('request.jwt.claim.sub', 'user_codex_events_new_clerk_subject', true);
  perform set_config('request.jwt.claim.canonical_user_id', 'user_codex_events_owner', true);
  if (select created_at from public.register_events_launch_interest()) is distinct from first_time then
    raise exception 'Events registration ignored canonical identity';
  end if;
  perform set_config('request.jwt.claim.canonical_user_id', '', true);
  perform set_config('request.jwt.claim.sub', 'user_codex_events_other', true);
  if exists (select 1 from public.own_events_launch_interest()) then
    raise exception 'Other account received owner interest';
  end if;
  begin
    perform 1 from public.events_launch_interest;
    raise exception 'Client read private interest roster';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.events_launch_interest(user_id) values ('user_codex_events_other');
    raise exception 'Client bypassed registration RPC';
  exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claim.sub', 'user_codex_events_missing_profile', true);
  begin
    perform public.register_events_launch_interest();
    raise exception 'Missing profile registered';
  exception when raise_exception then
    if sqlerrm <> 'profile_not_found' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform public.register_events_launch_interest();
    raise exception 'Missing identity registered';
  exception when raise_exception then
    if sqlerrm <> 'not_authenticated' then raise; end if;
  end;
  begin
    perform public.own_events_launch_interest();
    raise exception 'Missing identity read interest';
  exception when raise_exception then
    if sqlerrm <> 'not_authenticated' then raise; end if;
  end;
end
$behavior$;

set local role anon;
do $anonymous$
begin
  begin
    perform public.register_events_launch_interest();
    raise exception 'Anonymous registration succeeded';
  exception when insufficient_privilege then null; end;
  begin
    perform public.own_events_launch_interest();
    raise exception 'Anonymous read succeeded';
  exception when insufficient_privilege then null; end;
end
$anonymous$;

reset role;
update public.profiles set deleted_at = now() where id = 'user_codex_events_owner';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_codex_events_owner', true);
do $deleted$
begin
  if exists (select 1 from public.own_events_launch_interest()) then
    raise exception 'Deleted profile can read interest';
  end if;
  begin
    perform public.register_events_launch_interest();
    raise exception 'Deleted profile registered';
  exception when raise_exception then
    if sqlerrm <> 'profile_not_found' then raise; end if;
  end;
end
$deleted$;
reset role;
