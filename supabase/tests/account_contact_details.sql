begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(1);

insert into public.profiles(id, handle, display_name) values
  ('user_codex_details_owner', 'codexdetailsowner', 'Details Test Owner'),
  ('user_codex_details_other', 'codexdetailsother', 'Details Test Other');

do $metadata$
declare signature text;
begin
  if not (select relrowsecurity from pg_class where oid='public.account_contact_details'::regclass)
    or has_table_privilege('authenticated','public.account_contact_details','select,insert,update,delete')
    or has_table_privilege('anon','public.account_contact_details','select,insert,update,delete') then
    raise exception 'private details table required'; end if;
  foreach signature in array array['public.own_account_contact_details()', 'public.save_own_account_contact_details(jsonb)'] loop
    if has_function_privilege('anon',signature,'execute')
      or not has_function_privilege('authenticated',signature,'execute')
      or not (select prosecdef and proconfig @> array['search_path=public, app']
        and provolatile = case when signature like '%save_%' then 'v' else 's' end
        from pg_proc where oid=signature::regprocedure) then
      raise exception 'details RPC security violation'; end if;
  end loop;
end;
$metadata$;

set local role authenticated;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.canonical_user_id', '', true);
select set_config('request.jwt.claim.sub', 'user_codex_details_owner', true);
do $owner$
declare saved record;
begin
  if exists(select 1 from public.own_account_contact_details()) then raise exception 'unexpected initial details'; end if;
  select * into saved from public.save_own_account_contact_details(
    '{"metro_id":"los-angeles","home_country_code":"GB","phone_country_code":"US","phone_e164":"+12025550123"}');
  if saved.metro_id <> 'los-angeles' or saved.home_country_code <> 'US'
    or saved.phone_e164 <> '+12025550123' then raise exception 'save response mismatch'; end if;
  if (select phone_e164 from public.own_account_contact_details()) <> '+12025550123' then raise exception 'not persistent'; end if;
  -- Repeated save is an upsert; explicit null clears optional values.
  perform public.save_own_account_contact_details('{"metro_id":"other","phone_country_code":"GB","phone_e164":null}');
  if (select count(*) from public.own_account_contact_details()) <> 1
    or (select phone_e164 from public.own_account_contact_details()) is not null then raise exception 'clear/retry failed'; end if;
  perform public.save_own_account_contact_details('{"phone_country_code":"GB","phone_e164":"+442079460123"}');
  perform set_config('request.jwt.claim.sub', 'user_codex_details_new_clerk', true);
  perform set_config('request.jwt.claim.canonical_user_id', 'user_codex_details_owner', true);
  if (select phone_e164 from public.own_account_contact_details()) <> '+442079460123' then raise exception 'canonical identity ignored'; end if;
end;
$owner$;
select set_config('request.jwt.claim.canonical_user_id', '', true);
select set_config('request.jwt.claim.sub', 'user_codex_details_other', true);
do $isolation$
begin
  if exists(select 1 from public.own_account_contact_details()) then raise exception 'other user can see private details'; end if;
  begin
    perform 1 from public.account_contact_details;
    raise exception 'direct table read allowed';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.account_contact_details(user_id,phone_country_code) values('user_codex_details_other','US');
    raise exception 'direct table write allowed';
  exception when insufficient_privilege then null; end;
  begin
    perform public.save_own_account_contact_details('{"user_id":"user_codex_details_owner","phone_country_code":"US"}');
    raise exception 'caller supplied owner allowed';
  exception when raise_exception then if sqlerrm <> 'invalid_account_contact_details' then raise; end if; end;
  begin
    perform public.save_own_account_contact_details('{"metro_id":"unknown-metro","phone_country_code":"US"}');
    raise exception 'unknown metro allowed';
  exception when raise_exception then if sqlerrm <> 'invalid_home_metro' then raise; end if; end;
  begin
    perform public.save_own_account_contact_details('{"phone_country_code":"US","phone_e164":"+1202555012"}');
    raise exception 'nine US digits allowed';
  exception when raise_exception then if sqlerrm <> 'invalid_account_contact_details' then raise; end if; end;
  begin
    perform public.save_own_account_contact_details('{"phone_country_code":"US","phone_e164":"202-555-0123"}');
    raise exception 'unnormalized phone allowed';
  exception when raise_exception then if sqlerrm <> 'invalid_account_contact_details' then raise; end if; end;
  perform set_config('request.jwt.claim.sub', 'user_codex_details_missing', true);
  begin
    perform public.save_own_account_contact_details('{"phone_country_code":"US"}');
    raise exception 'missing profile allowed';
  exception when raise_exception then if sqlerrm <> 'profile_not_found' then raise; end if; end;
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform public.own_account_contact_details();
    raise exception 'missing identity read allowed';
  exception when raise_exception then if sqlerrm <> 'not_authenticated' then raise; end if; end;
  begin
    perform public.save_own_account_contact_details('{"phone_country_code":"US"}');
    raise exception 'missing identity write allowed';
  exception when raise_exception then if sqlerrm <> 'not_authenticated' then raise; end if; end;
end;
$isolation$;

set local role anon;
do $anonymous$
begin
  begin perform public.own_account_contact_details(); raise exception 'anonymous read allowed';
    exception when insufficient_privilege then null; end;
  begin perform public.save_own_account_contact_details('{"phone_country_code":"US"}'); raise exception 'anonymous write allowed';
    exception when insufficient_privilege then null; end;
end;
$anonymous$;

reset role;
update public.profiles set deleted_at=now() where id='user_codex_details_owner';
do $purge$ begin
  if exists(select 1 from public.account_contact_details where user_id='user_codex_details_owner') then
    raise exception 'soft delete retained phone'; end if;
end; $purge$;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_codex_details_owner', true);
do $deleted$ begin
  if exists(select 1 from public.own_account_contact_details()) then raise exception 'deleted profile can read'; end if;
  begin perform public.save_own_account_contact_details('{"phone_country_code":"US"}'); raise exception 'deleted profile can save';
    exception when raise_exception then if sqlerrm <> 'profile_not_found' then raise; end if; end;
end; $deleted$;
reset role;
select pass('private owner details, canonical identity, validation, clear/retry, anonymous denial and deletion');
select * from finish();
rollback;
