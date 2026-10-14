begin;

-- REC-636 installation check. This file only reads catalogs, flag metadata and
-- exact reserved fixture IDs. It works after install or inside a rolled-back
-- migration preview; no app data, account flags, messages or schema are changed.
-- Confirm the project separately before execution. Generate a rollback preview:
-- node scripts/supabase-smoke-test.mjs --print-sql --migration-preview <messages.sql> --migration-preview <live.sql> --migration-test supabase/tests/rec636_dormant_metadata.sql
-- Run the complete hosted smoke suite separately after installation.
-- Function fingerprints are from the reviewed PostgreSQL 17 rollback preview.
-- Reviewed migration SHA256 supabase/migrations/20261014020218_private_contextual_messages.sql: 565b8f042e8bc1a2b8c89de41b551ce9fef63981395c17369028c6b7f2c9708f
-- Reviewed migration SHA256 supabase/migrations/20261014020238_live_activity_feed.sql: 10f9e22344724521ce8135a3e84f13e834a1af9ac0d4c9b4f7dd79171c82a125
set local lock_timeout = '5s';
set local statement_timeout = '60s';
-- Keep catalog deparsing and dynamic constraint evaluation out of app schemas.
-- pg_get_expr then qualifies custom operators/functions for the grammar guard.
set local search_path = pg_catalog;

do $metadata$
declare
  expected record; proc record; constraint_row record;
  fn oid; expected_oids oid[] := '{}'; private_table oid;
  client_role text; flag_key text; flag_type text; flag_integer integer;
  expected_registered boolean; expected_contract boolean;
  actual_registered boolean; actual_contract boolean;
  registered_expression text; contract_expression text; safe_expression text;
  registered_keys text[];
  flag_keys text[] := array[
    'debug_settings','first_visit_nux','notification_reprompt_campaign',
    'place_profile_action_variant','place_profile_save_tray_v1','profile_feedback_v1',
    'semantic_place_search_v1','social_import_apify_gemini_v1','unified_live_v1'
  ];
  type_range_probes integer := 0;
begin
  -- Exact signatures prevent a name-only scan from silently passing a missing
  -- RPC, a changed argument type/name/default count, or an additional overload.
  for expected in select * from (values
    ('app.private_message_participant_enabled(text)', 'boolean', true, 's', 'pg_catalog, public, app', false, 0, array['input_user_id'], 'sql', 'a6dcbd6d518a464e9ead69db14cc2383'),
    ('app.private_message_pair_allowed(text,text)', 'boolean', true, 's', 'pg_catalog, public, app', false, 0, array['first_user','second_user'], 'sql', '67af27f960a55fc8feda545db6d2fd1a'),
    ('app.private_message_context_allowed(text,text,text,uuid)', 'boolean', true, 's', 'pg_catalog, public, app', false, 0, array['first_user','second_user','source_kind','source_id'], 'sql', 'a4cef1bd31ae96cafb08cc379c83d1cd'),
    ('app.private_message_json(uuid,text)', 'jsonb', true, 's', 'pg_catalog, public, app', false, 0, array['message_id','viewer_id'], 'sql', '8fa48db1ce57321ecd195776238a6519'),
    ('app.private_conversation_json(uuid,text)', 'jsonb', true, 's', 'pg_catalog, public, app', false, 0, array['conversation_id','viewer_id'], 'sql', '16a4ea757347664016999fd1326a3e83'),
    ('public.private_message_conversation(uuid)', 'jsonb', true, 's', 'pg_catalog, public, app', true, 0, array['input_conversation_id'], 'plpgsql', '943b30d5b208b1fe965160d92b7f685d'),
    ('public.private_message_start(text,text,uuid)', 'jsonb', true, 'v', 'pg_catalog, public, app', true, 0, array['input_recipient_id','input_context_kind','input_context_id'], 'plpgsql', '94fdbae16e6e455e7a18e7c9730e2ac3'),
    ('public.private_message_inbox(timestamptz,uuid,integer)', 'jsonb', true, 's', 'pg_catalog, public, app', true, 3, array['input_before_at','input_before_id','input_limit'], 'plpgsql', 'bd253e15ddb729bc941de748ad999711'),
    ('public.private_message_history(uuid,timestamptz,uuid,integer)', 'jsonb', true, 's', 'pg_catalog, public, app', true, 3, array['input_conversation_id','input_before_at','input_before_id','input_limit'], 'plpgsql', 'eac81989a10be3680a2880efbec53493'),
    ('public.private_message_send(uuid,text,uuid,text,uuid)', 'jsonb', true, 'v', 'pg_catalog, public, app', true, 2, array['input_conversation_id','input_body','input_client_id','input_context_kind','input_context_id'], 'plpgsql', '686a7fd0f440f5def4595f530873dd3a'),
    ('public.private_message_mark_read(uuid,uuid)', 'jsonb', true, 'v', 'pg_catalog, public, app', true, 0, array['input_conversation_id','input_through_message_id'], 'plpgsql', 'a9b6e4ef5840e07e022722d04a2d633d'),
    ('app.live_feed_polygon(jsonb)', 'geometry', false, 'i', 'pg_catalog, public, app, extensions', false, 0, array['input_polygon'], 'plpgsql', 'dc6c59eebf7ee3eb7f831f29562ef365'),
    ('app.live_activity_feed(text,timestamptz,timestamptz,text,jsonb,text,integer,double precision,double precision,integer,text[],text[])', 'jsonb', true, 's', 'pg_catalog, public, app, extensions', false, 11, array['input_audience','input_after','input_until','input_activity_type','input_polygon','input_before','input_limit','input_center_latitude','input_center_longitude','input_radius_meters','input_category_ids','input_person_ids'], 'plpgsql', 'c75e611f44162f6504dab1d4cc113edf'),
    ('public.live_activity_feed(text,timestamptz,timestamptz,text,jsonb,text,integer,double precision,double precision,integer,text[],text[])', 'jsonb', true, 's', 'pg_catalog, public, app, extensions', true, 11, array['input_audience','input_after','input_until','input_activity_type','input_polygon','input_before','input_limit','input_center_latitude','input_center_longitude','input_radius_meters','input_category_ids','input_person_ids'], 'sql', '5d0cefdb1b9cdfaef4aa701e03e21a9c')
  ) contract(signature, return_type, definer, volatility, pinned_path, authenticated_execute, default_count, argument_names, language_name, definition_md5)
  loop
    fn := to_regprocedure(expected.signature);
    if fn is null then raise exception 'REC-636 missing function: %', expected.signature; end if;
    expected_oids := array_append(expected_oids, fn);
    select p.*, l.lanname into strict proc
      from pg_proc p join pg_language l on l.oid=p.prolang where p.oid=fn;
    if proc.prokind <> 'f' or proc.proretset
      or proc.prosecdef is distinct from expected.definer
      or proc.provolatile::text is distinct from expected.volatility
      or coalesce(proc.proconfig, array[]::text[]) <> array['search_path=' || expected.pinned_path]
      or proc.pronargdefaults <> expected.default_count
      or proc.proargnames is distinct from expected.argument_names
      or proc.lanname is distinct from expected.language_name
      or (expected.return_type <> 'geometry' and proc.prorettype <> to_regtype(expected.return_type))
      or (expected.return_type = 'geometry' and not exists (
        select 1 from pg_type t join pg_extension e on e.extnamespace=t.typnamespace
        where t.oid=proc.prorettype and t.typname='geometry' and e.extname='postgis'))
    then raise exception 'REC-636 function ABI/security metadata changed: %', expected.signature; end if;
    if md5(pg_get_functiondef(fn)) is distinct from expected.definition_md5 then
      raise exception 'REC-636 reviewed function definition changed: %',expected.signature; end if;
    if has_function_privilege('anon', fn, 'execute')
      or has_function_privilege('authenticated', fn, 'execute') is distinct from expected.authenticated_execute
      or exists(select 1 from aclexplode(coalesce(proc.proacl, acldefault('f',proc.proowner)))
        where grantee=0 and privilege_type='EXECUTE')
    then raise exception 'REC-636 function client execute grants changed: %', expected.signature; end if;
  end loop;
  if cardinality(expected_oids) <> 14 or exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where ((n.nspname='app' and p.proname in (
      'private_message_participant_enabled','private_message_pair_allowed','private_message_context_allowed',
      'private_message_json','private_conversation_json','live_feed_polygon','live_activity_feed'))
      or (n.nspname='public' and p.proname in (
      'private_message_conversation','private_message_start','private_message_inbox',
      'private_message_history','private_message_send','private_message_mark_read','live_activity_feed')))
      and not (p.oid=any(expected_oids))
  ) then raise exception 'REC-636 unexpected function overload'; end if;

  -- PostgreSQL privilege inquiry functions accept `public` for the PUBLIC
  -- pseudo-role. Named-role checks also include inherited and column grants.
  foreach private_table in array array['public.private_conversations'::regclass::oid,'public.private_messages'::regclass::oid]
  loop
    if not exists(select 1 from pg_class where oid=private_table and relkind='r' and relrowsecurity)
      or exists(select 1 from pg_policy where polrelid=private_table)
    then raise exception 'REC-636 private table must enable RLS with no client policy'; end if;
    foreach client_role in array array['public','anon','authenticated'] loop
      if has_table_privilege(client_role,private_table,'select,insert,update,delete,truncate,references,trigger')
        or has_any_column_privilege(client_role,private_table,'select,insert,update,references')
      then raise exception 'REC-636 private table grants direct access to %',client_role; end if;
    end loop;
  end loop;
  if not exists(select 1 from pg_class where oid='public.feature_flags'::regclass and relrowsecurity)
    or not has_table_privilege('authenticated','public.feature_flags','select')
  then raise exception 'REC-636 feature flags must retain RLS and authenticated reads'; end if;
  foreach client_role in array array['public','anon','authenticated'] loop
    if has_table_privilege(client_role,'public.feature_flags','insert,update,delete,truncate,references,trigger')
      or has_any_column_privilege(client_role,'public.feature_flags','insert,update,references')
    then raise exception 'REC-636 participant flags must remain operator-owned'; end if;
  end loop;
  if (select count(*) from public.feature_flags where key='unified_live_v1' and user_id is null) <> 1
    or not exists(select 1 from public.feature_flags where key='unified_live_v1'
      and user_id is null and not enabled and value_type='boolean' and integer_value is null)
  then raise exception 'REC-636 global Live must remain Boolean Off'; end if;
  if exists(select 1 from pg_attribute where attrelid='public.feature_flags'::regclass
      and attname in ('key','value_type','enabled') and (attisdropped or not attnotnull))
    or (select count(*) from pg_attribute where attrelid='public.feature_flags'::regclass
      and attname in ('key','value_type','enabled') and not attisdropped) <> 3
  then raise exception 'REC-636 feature flag keys, types and enabled values must be non-null'; end if;

  for constraint_row in select oid,conname,contype,convalidated,pg_get_expr(conbin,conrelid) as expression
    from pg_constraint where conrelid='public.feature_flags'::regclass
      and conname in ('feature_flags_registered_key_check','feature_flags_key_value_contract_check')
  loop
    if constraint_row.contype <> 'c' or not constraint_row.convalidated then
      raise exception 'REC-636 flag constraints must be validated CHECK constraints'; end if;
    -- These reviewed constraints use only pinned built-in comparisons. PostgreSQL
    -- does not record dependencies on pinned objects, so any explicit executable
    -- dependency indicates a wider contract, even if it lives in pg_catalog.
    if exists(select 1 from pg_depend dependency
        where dependency.classid='pg_catalog.pg_constraint'::regclass
          and dependency.objid=constraint_row.oid
          and dependency.refclassid in ('pg_catalog.pg_proc'::regclass,'pg_catalog.pg_operator'::regclass))
    then raise exception 'REC-636 flag constraint has an unreviewed executable dependency'; end if;
    -- Evaluate only the primitive expression language emitted by the reviewed
    -- constraints. Reject function calls/custom casts before dynamic SELECT.
    safe_expression := regexp_replace(constraint_row.expression, $quoted$'(?:[^']|'')*'$quoted$, '', 'g');
    if safe_expression ~* '\m(key|value_type|integer_value|text|integer)\M\s*\(' then
      raise exception 'REC-636 flag constraint contains a non-primitive expression'; end if;
    safe_expression := regexp_replace(safe_expression,
      '\m(key|value_type|integer_value|text|integer|AND|OR|NOT|NULL|IS|ANY|ALL|ARRAY)\M', '', 'gi');
    safe_expression := regexp_replace(safe_expression, '[0-9\[\][:space:],():=<>+\-]', '', 'g');
    if safe_expression <> '' then raise exception 'REC-636 flag constraint expression changed'; end if;
    if constraint_row.conname='feature_flags_registered_key_check' then
      registered_expression := constraint_row.expression;
    else contract_expression := constraint_row.expression; end if;
  end loop;
  if registered_expression is null or contract_expression is null then
    raise exception 'REC-636 flag contract constraints are missing'; end if;
  select array_agg(distinct matched[1] order by matched[1]) into registered_keys
    from regexp_matches(registered_expression, $quoted$'([^']*)'$quoted$, 'g') matched;
  if registered_keys is distinct from flag_keys then raise exception 'REC-636 nine-key flag registry changed'; end if;
  foreach flag_key in array flag_keys || array['rec636_unregistered_probe'] loop
    expected_registered := flag_key=any(flag_keys);
    execute format('select (%s) from (select $1::text as key) fixture',registered_expression)
      into actual_registered using flag_key;
    if actual_registered is distinct from expected_registered then
      raise exception 'REC-636 registered-key constraint changed'; end if;
    foreach flag_type in array array['boolean','integer','unsupported'] loop
      foreach flag_integer in array array[
        null::integer,-2147483648,-1,0,1,2,3,4,5,6,7,10,100,999,9999,99999,999998,999999,1000000,1000001,1000002,2147483647
      ] loop
        expected_contract := case
          when flag_key='place_profile_action_variant' then flag_type='integer' and flag_integer is not null and flag_integer between 1 and 5
          when flag_key='notification_reprompt_campaign' then flag_type='integer' and flag_integer is not null and flag_integer between 0 and 1000000
          else expected_registered and flag_type='boolean' and flag_integer is null end;
        execute format('select (%s) from (select $1::text as key,$2::text as value_type,$3::integer as integer_value) fixture',contract_expression)
          into actual_contract using flag_key,flag_type,flag_integer;
        if actual_contract is distinct from expected_contract then
          raise exception 'REC-636 flag type/range constraint changed'; end if;
        type_range_probes := type_range_probes+1;
      end loop;
    end loop;
  end loop;
  if type_range_probes <> 660 then raise exception 'REC-636 incomplete flag type/range probes'; end if;

  -- The unchanged Feed endpoint is the same contract asserted by the Live SQL
  -- regression suite. This metadata check supplements its behavior tests.
  if not exists(select 1 from pg_proc where oid='public.activity_feed(text,text,integer)'::regprocedure
      and prosecdef and provolatile='s' and prorettype='jsonb'::regtype
      and 'search_path=app, public'=any(proconfig))
    or has_function_privilege('anon','public.activity_feed(text,text,integer)','execute')
  then raise exception 'REC-636 legacy Feed security metadata changed'; end if;
end
$metadata$;

select jsonb_build_object(
  'status','passed','functions',14,'private_tables',2,'registered_flag_keys',9,
  'flag_type_range_probes',660,'global_live_enabled',false
) as rec636_dormant_metadata;

rollback;
