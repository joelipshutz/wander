begin;

create function pg_temp.require(condition boolean, message text) returns void
language plpgsql as $$ begin
  if condition is not true then raise exception 'REC-631: %', message; end if;
end $$;

select pg_temp.require(not p.prosecdef and p.provolatile='s'
  and 'search_path=public, app'=any(p.proconfig), 'search retains stable invoker posture and search_path')
from pg_proc p where p.oid='app.search_profiles_by_handle(text)'::regprocedure;
select pg_temp.require(has_function_privilege('authenticated','public.search_profiles_by_handle(text)','execute')
  and not has_function_privilege('anon','public.search_profiles_by_handle(text)','execute')
  and not has_function_privilege('anon','app.search_profiles_by_handle(text)','execute'), 'authenticated-only RPC grants');

insert into public.profiles(id,handle,display_name,is_private_profile) values
  ('user_codex_typeahead_viewer','zz631_viewer','Typeahead Viewer',false),
  ('user_codex_typeahead_caitlin','zz631_cait123','Zz631 Caitlin Cortez',false),
  ('user_codex_typeahead_private','zz631_private','Zz631 Private',true),
  ('user_codex_typeahead_blocked','zz631_blocked','Zz631 Blocked',false),
  ('user_codex_typeahead_deleted','zz631_deleted','Zz631 Deleted',false);
update public.profiles set deleted_at=now() where id='user_codex_typeahead_deleted';
insert into public.blocks(blocker_user_id,blocked_user_id)
values ('user_codex_typeahead_viewer','user_codex_typeahead_blocked');
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.canonical_user_id','',true);
select set_config('request.jwt.claim.sub','user_codex_typeahead_viewer',true);
set local role authenticated;

select pg_temp.require(exists(select 1 from public.search_profiles_by_handle('z')
  where id='user_codex_typeahead_caitlin'), 'first character returns a matching person');
select pg_temp.require((select count(*)=1 from public.search_profiles_by_handle('zz631')
  where id='user_codex_typeahead_caitlin'), 'name and handle matching returns one row per person');
select pg_temp.require(exists(select 1 from public.search_profiles_by_handle('Cortez')
  where id='user_codex_typeahead_caitlin'), 'surname matching');
select pg_temp.require(exists(select 1 from public.search_profiles_by_handle('@ZZ631_CAIT')
  where id='user_codex_typeahead_caitlin'), 'case-insensitive handle and @ prefix');
select pg_temp.require(not exists(select 1 from public.search_profiles_by_handle('zz631')
  where id in ('user_codex_typeahead_viewer','user_codex_typeahead_private',
    'user_codex_typeahead_blocked','user_codex_typeahead_deleted')), 'self/private/blocked/deleted excluded');
select pg_temp.require(not exists(select 1 from public.search_profiles_by_handle('')), 'empty search does not enumerate profiles');
select pg_temp.require(not exists(select 1 from public.search_profiles_by_handle('%')), 'percent is literal, never a wildcard');
select pg_temp.require(exists(select 1 from public.search_profiles_by_handle('zz631_c')
  where id='user_codex_typeahead_caitlin'), 'literal underscore in a handle remains searchable');
select pg_temp.require(not exists(select 1 from public.search_profiles_by_handle('zz631%')
  where id='user_codex_typeahead_caitlin'), 'punctuation does not widen a query');
reset role;

select 'REC-631 profile typeahead regression passed' as result;
rollback;
