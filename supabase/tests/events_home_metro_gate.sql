begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(1);
insert into public.profiles(id,handle,display_name) values
  ('user_codex_gate_la','codexgatela','Gate LA'),
  ('user_codex_gate_other','codexgateother','Gate Other');
do $metadata$
declare signature text;
begin
  foreach signature in array array['public.own_events_market_access()', 'public.own_events_launch_interest()', 'public.register_events_launch_interest()'] loop
    if has_function_privilege('anon',signature,'execute')
      or not has_function_privilege('authenticated',signature,'execute')
      or not (select prosecdef and proconfig @> array['search_path=public, app'] and pronargs=0
        and provolatile = case when signature like '%register%' then 'v' else 's' end
        from pg_proc where oid=signature::regprocedure) then
      raise exception 'Events gate RPC security differs from contract'; end if;
  end loop;
  if pg_get_function_result('public.own_events_market_access()'::regprocedure) <> 'TABLE(metro_id text)' then
    raise exception 'Gate hydration must not expose phone or precise location'; end if;
end; $metadata$;

set local role authenticated;
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.canonical_user_id','',true);
select set_config('request.jwt.claim.sub','user_codex_gate_la',true);
do $gate$
declare original_time timestamptz; repeat_time timestamptz;
begin
  if (select metro_id from public.own_events_market_access()) is not null then raise exception 'unknown home incorrectly resolved'; end if;
  begin perform public.register_events_launch_interest(); raise exception 'unknown home registered';
    exception when raise_exception then if sqlerrm <> 'events_not_available_in_home_area' then raise; end if; end;
  perform public.save_own_account_contact_details('{"metro_id":"orange-county","phone_country_code":"US"}');
  begin perform public.register_events_launch_interest(); raise exception 'Orange County registered';
    exception when raise_exception then if sqlerrm <> 'events_not_available_in_home_area' then raise; end if; end;
  perform public.save_own_account_contact_details('{"metro_id":"inland-empire","phone_country_code":"US"}');
  begin perform public.register_events_launch_interest(); raise exception 'Inland Empire registered';
    exception when raise_exception then if sqlerrm <> 'events_not_available_in_home_area' then raise; end if; end;
  perform public.save_own_account_contact_details('{"metro_id":"los-angeles","phone_country_code":"GB","phone_e164":"+442079460123"}');
  if (select metro_id from public.own_events_market_access()) <> 'los-angeles' then raise exception 'saved home not returned'; end if;
  select created_at into original_time from public.register_events_launch_interest();
  select created_at into repeat_time from public.register_events_launch_interest();
  if original_time is null or original_time is distinct from repeat_time then raise exception 'LA interest not idempotent'; end if;
  -- A foreign phone does not affect eligibility; only a deliberate home edit does.
  perform public.save_own_account_contact_details('{"metro_id":"new-york","phone_country_code":"US"}');
  if exists(select 1 from public.own_events_launch_interest()) then raise exception 'outside member can read Events interest'; end if;
  begin perform public.register_events_launch_interest(); raise exception 'outside member registered';
    exception when raise_exception then if sqlerrm <> 'events_not_available_in_home_area' then raise; end if; end;
  perform public.save_own_account_contact_details('{"metro_id":"los-angeles","phone_country_code":"US"}');
  if (select created_at from public.own_events_launch_interest()) is distinct from original_time then raise exception 'home edit discarded original interest'; end if;
  perform set_config('request.jwt.claim.sub','user_codex_gate_new_clerk_subject',true);
  perform set_config('request.jwt.claim.canonical_user_id','user_codex_gate_la',true);
  if (select metro_id from public.own_events_market_access()) <> 'los-angeles' then raise exception 'canonical identity ignored'; end if;
  perform set_config('request.jwt.claim.canonical_user_id','',true);
  perform set_config('request.jwt.claim.sub','user_codex_gate_other',true);
  if (select metro_id from public.own_events_market_access()) is not null then raise exception 'another user received LA home'; end if;
  if exists(select 1 from public.own_events_launch_interest()) then raise exception 'another user received LA interest'; end if;
  perform set_config('request.jwt.claim.sub','',true);
  begin perform public.own_events_market_access(); raise exception 'missing identity read gate';
    exception when raise_exception then if sqlerrm <> 'not_authenticated' then raise; end if; end;
end; $gate$;
set local role anon;
do $anon$ begin
  begin perform public.own_events_market_access(); raise exception 'anonymous read gate';
    exception when insufficient_privilege then null; end;
end; $anon$;
reset role;
select pass('LA-only Events registration and owner-only metro hydration, unknown/outside denial, canonical identity and remembered interest');
select * from finish();
rollback;
