begin;

-- Reserved synthetic identities only. This suite and its smoke-runner import
-- roll back all source, graph and list changes.
do $pin_states$
declare
  viewer text := 'user_codex_pin_state_viewer'; friend text := 'user_codex_pin_state_friend';
  followee text := 'user_codex_pin_state_followee'; stranger text := 'user_codex_pin_state_stranger';
  private_owner text := 'user_codex_pin_state_private'; blocked text := 'user_codex_pin_state_blocked';
  deleted_owner text := 'user_codex_pin_state_deleted';
  result jsonb; state jsonb; saved jsonb; proc record; requested uuid[];
begin
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claim.canonical_user_id','',true);
  perform set_config('request.jwt.claims','{}',true);
  select * into strict proc from pg_proc where oid='public.live_map_pin_states(uuid[])'::regprocedure;
  if not proc.prosecdef or proc.provolatile is distinct from 's' or proc.prorettype is distinct from 'jsonb'::regtype
    or proc.proretset or proc.proargnames is distinct from array['input_place_ids']::text[]
    or not ('search_path=pg_catalog, public, app, extensions'=any(proc.proconfig))
    or not has_function_privilege('authenticated',proc.oid,'execute')
    or has_function_privilege('anon',proc.oid,'execute')
    or exists(select 1 from aclexplode(coalesce(proc.proacl,acldefault('f',proc.proowner)))
      where grantee=0 and privilege_type='EXECUTE')
    or has_table_privilege('authenticated','public.feed_events','select')
    or has_table_privilege('authenticated','public.place_wanna_saves','select')
  then raise exception 'pin-state scalar ABI or security posture changed'; end if;
  if exists(select 1 from public.profiles where id=any(array[viewer,friend,followee,stranger,private_owner,blocked,deleted_owner])
      or handle like 'codex_pin_state_%')
    or exists(select 1 from public.places where id::text like '657b0000-%')
    or exists(select 1 from public.user_places where id::text like '657b1000-%')
    or exists(select 1 from public.place_lists where id::text like '657b3000-%')
  then raise exception 'reserved pin-state fixture identity collision'; end if;

  insert into public.profiles(id,handle,display_name,is_private_profile) values
    (viewer,'codex_pin_state_viewer','Pin Viewer',false),(friend,'codex_pin_state_friend','Pin Friend',false),
    (followee,'codex_pin_state_followee','Pin Followee',false),(stranger,'codex_pin_state_stranger','Pin Stranger',false),
    (private_owner,'codex_pin_state_private','Pin Private',true),(blocked,'codex_pin_state_blocked','Pin Blocked',false),
    (deleted_owner,'codex_pin_state_deleted','Pin Deleted',false);
  delete from public.follows where follower_user_id=any(array[viewer,friend,followee,stranger,private_owner,blocked,deleted_owner])
    and source='signup_default';
  insert into public.follows(follower_user_id,followed_user_id,source) values
    (viewer,friend,'username'),(friend,viewer,'username'),(viewer,followee,'username'),
    (viewer,private_owner,'username'),(viewer,blocked,'username'),(viewer,deleted_owner,'username');
  insert into public.blocks(blocker_user_id,blocked_user_id) values(blocked,viewer);
  insert into public.places(id,canonical_name,category,address,locality,latitude,longitude,source_provider,source_provider_place_id)
    select ('657b0000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
      case when n in(1,2) then 'Pin alias fixture' else 'Pin fixture '||n end,'coffee',
      case when n in(1,2) then '10 Pin Street' else n||' Fixture Street' end,'Sampleton',0,n*0.00001,'manual',
      case when n=2 then '657b0000-0000-0000-0000-000000000001' else 'rec657-pin-state-'||n end
    from generate_series(1,30) n;
  insert into public.user_places(id,user_id,place_id,status,visibility,source_type,note)
    select ('657b1000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
      case n when 8 then friend when 9 then followee when 10 then stranger when 11 then private_owner
        when 12 then blocked when 13 then deleted_owner when 14 then friend when 15 then friend when 16 then friend else viewer end,
      ('657b0000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
      case when n in(2,4,5,9) then 'wanna_go' else 'been' end,
      case when n in(1,2,3,4,5,6,7,14) then 'self' when n=8 then 'mutuals' else 'followers' end,
      'manual','PIN STATE CONTENT MUST NOT BE RETURNED'
    from generate_series(1,16) n;
  -- The real parent trigger supplies active backfilled visits for Been. A
  -- soft-deleted backfill keeps stale parent.status=been to catch unsafe fallback.
  update public.place_visits set deleted_at=now()
    where user_place_id='657b1000-0000-0000-0000-000000000003';
  update public.user_places set deleted_at=now() where id='657b1000-0000-0000-0000-000000000015';
  update public.profiles set deleted_at=now() where id=deleted_owner;
  -- Retain a list-only parent after deleting its last Wanna identity.
  insert into app.deleted_place_wannas(id,user_place_id)
    select id,user_place_id from public.feed_events where user_place_id='657b1000-0000-0000-0000-000000000004'
      and event_type='place_want_to_go';
  delete from public.feed_events where user_place_id='657b1000-0000-0000-0000-000000000004'
    and event_type='place_want_to_go';
  insert into app.private_list_companion_origins(user_place_id) values('657b1000-0000-0000-0000-000000000005');
  -- Historical originals remain readable Wanna records under the existing
  -- visible_place_wannas contract; independent repeats are also active records.
  insert into public.feed_events(id,actor_user_id,event_type,user_place_id,place_id,occurred_at)
    select ('657b2000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
      case when n=16 then friend else viewer end,'place_want_to_go',
      ('657b1000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
      ('657b0000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,now()-interval '1 day'
    from unnest(array[6,7,16]) n;
  insert into public.place_wanna_saves(id,user_place_id,visibility,occurred_at,is_historical_original)
    select ('657b2000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
      ('657b1000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'self',now()-interval '1 day',n=6
    from unnest(array[6,7,16]) n;

  -- List detail requires a current readable save reference. These parents have
  -- no remaining Wanna action; they support list membership only.
  insert into public.user_places(id,user_id,place_id,status,visibility,source_type)
    select ('657b1000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
      case n when 17 then viewer when 20 then blocked when 21 then private_owner when 26 then blocked else friend end,
      ('657b0000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'wanna_go',
      case when n in(17,25) then 'self' else 'followers' end,'manual' from generate_series(17,26) n;
  delete from public.feed_events where user_place_id in(
    select ('657b1000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid from generate_series(17,26) n);

  -- Legacy social saves emitted place_saved instead of an independent Wanna.
  -- A fresh one is intent; deleted Wanna/visit history or companion provenance
  -- prevents that fallback from reviving a list-only retained summary.
  insert into public.user_places(id,user_id,place_id,status,visibility,source_type)
    select ('657b1000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,viewer,
      ('657b0000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'wanna_go','self','social_save'
    from generate_series(27,30) n;
  insert into app.deleted_place_wannas(id,user_place_id)
    values('657b2000-0000-0000-0000-000000000028','657b1000-0000-0000-0000-000000000028');
  insert into public.place_visits(id,user_place_id,visited_at,deleted_at)
    values('657b5000-0000-0000-0000-000000000029','657b1000-0000-0000-0000-000000000029',now()-interval '1 day',now());
  insert into app.private_list_companion_origins(user_place_id)
    values('657b1000-0000-0000-0000-000000000030');

  insert into public.place_lists(id,owner_user_id,name,visibility,deleted_at)
    select ('657b3000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
      case n when 1 then viewer when 2 then friend when 3 then friend when 4 then blocked
        when 5 then private_owner when 6 then friend when 7 then friend else friend end,
      'Pin list fixture '||n,case when n in(1,3,8) then 'stealth' else 'followers' end,
      case when n=6 then now() else null end from generate_series(1,8) n;
  insert into public.place_list_members(list_id,user_id,role)
    values('657b3000-0000-0000-0000-000000000008',viewer,'collaborator');
  insert into public.place_list_items(id,list_id,place_id,owner_user_place_id,source_user_place_id,added_by_user_id,deleted_at)
    select ('657b4000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
      ('657b3000-0000-0000-0000-'||lpad(list_number::text,12,'0'))::uuid,
      ('657b0000-0000-0000-0000-'||lpad(place_number::text,12,'0'))::uuid,
      ('657b1000-0000-0000-0000-'||lpad(place_number::text,12,'0'))::uuid,
      ('657b1000-0000-0000-0000-'||lpad(place_number::text,12,'0'))::uuid,
      case list_number when 1 then viewer when 4 then blocked when 5 then private_owner else friend end,
      case when list_number=7 then now() else null end
    from (values (1,1,4),(2,1,5),(3,1,17),(4,2,18),(5,3,19),(6,4,20),(7,5,21),(8,6,22),(9,7,23),(10,8,24),(11,2,25),(12,2,26))
      fixture(n,list_number,place_number);

  perform set_config('request.jwt.claims',jsonb_build_object('sub',viewer,'role','authenticated')::text,true);
  set local role authenticated;
  select array_agg(('657b0000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid order by n) into requested
    from generate_series(1,30) n;
  result:=public.live_map_pin_states(requested);
  if jsonb_typeof(result) is distinct from 'object' or result->'complete' is distinct from 'true'::jsonb
    or jsonb_array_length(result->'states') is distinct from 30 or result->>'fetched_at' is null
  then raise exception 'pin states returned an incomplete scalar response'; end if;
  if (select count(distinct entry->>'place_id') from jsonb_array_elements(result->'states') entry) is distinct from 30
    or exists(select 1 from jsonb_array_elements(result->'states') entry where not (entry->>'place_id')::uuid=any(requested))
    or result::text like '%PIN STATE CONTENT MUST NOT BE RETURNED%'
  then raise exception 'pin states duplicated scope, returned unrequested scope, or exposed content'; end if;
  for state in select value from jsonb_array_elements(result->'states') loop
    if jsonb_typeof(state->'has_list_membership') is distinct from 'boolean' or jsonb_typeof(state->'saves') is distinct from 'array'
      or (select count(*) from jsonb_object_keys(state)) is distinct from 3
    then raise exception 'pin-state fields changed'; end if;
    for saved in select value from jsonb_array_elements(state->'saves') loop
      if jsonb_typeof(saved->'has_been') is distinct from 'boolean' or jsonb_typeof(saved->'has_wanna') is distinct from 'boolean'
        or jsonb_typeof(saved->'is_friend') is distinct from 'boolean' or jsonb_typeof(saved->'owner_id') is distinct from 'string'
        or (select count(*) from jsonb_object_keys(saved)) is distinct from 4
      then raise exception 'pin save-state fields changed or exposed content'; end if;
    end loop;
  end loop;
  -- Each requested alias gets a complete canonical result without duplicating
  -- an owner, even when their Been and Wanna evidence live on different IDs.
  for state in select value from jsonb_array_elements(result->'states')
    where value->>'place_id' in('657b0000-0000-0000-0000-000000000001','657b0000-0000-0000-0000-000000000002') loop
    if jsonb_array_length(state->'saves') is distinct from 1 or state->'saves'->0->>'owner_id' is distinct from viewer
      or state->'saves'->0->'has_been' is distinct from 'true'::jsonb or state->'saves'->0->'has_wanna' is distinct from 'true'::jsonb
      or state->'saves'->0->'is_friend' is distinct from 'false'::jsonb
    then raise exception 'pin-state alias resolution lost or duplicated owner state'; end if;
  end loop;
  for state in select value from jsonb_array_elements(result->'states')
    where value->>'place_id' in('657b0000-0000-0000-0000-000000000003','657b0000-0000-0000-0000-000000000004',
      '657b0000-0000-0000-0000-000000000005','657b0000-0000-0000-0000-000000000010',
      '657b0000-0000-0000-0000-000000000011','657b0000-0000-0000-0000-000000000012',
      '657b0000-0000-0000-0000-000000000013','657b0000-0000-0000-0000-000000000014',
      '657b0000-0000-0000-0000-000000000015','657b0000-0000-0000-0000-000000000028',
      '657b0000-0000-0000-0000-000000000029','657b0000-0000-0000-0000-000000000030') loop
    if exists(select 1 from jsonb_array_elements(state->'saves') evidence
      where evidence->'has_been'='true'::jsonb or evidence->'has_wanna'='true'::jsonb)
    then raise exception 'deleted, list-only, blocked, or private evidence became pin state'; end if;
  end loop;
  for state in select value from jsonb_array_elements(result->'states')
    where value->>'place_id' in('657b0000-0000-0000-0000-000000000006','657b0000-0000-0000-0000-000000000007') loop
    if not exists(select 1 from jsonb_array_elements(state->'saves') evidence where evidence->>'owner_id'=viewer
      and evidence->'has_been'='true'::jsonb and evidence->'has_wanna'='true'::jsonb)
    then raise exception 'active historical or independent Wanna record lost beside Been'; end if;
  end loop;
  select value into strict state from jsonb_array_elements(result->'states') where value->>'place_id'='657b0000-0000-0000-0000-000000000008';
  if state->'saves'->0->>'owner_id' is distinct from friend or state->'saves'->0->'is_friend' is distinct from 'true'::jsonb
    or state->'saves'->0->'has_been' is distinct from 'true'::jsonb then raise exception 'mutual Been state lost'; end if;
  select value into strict state from jsonb_array_elements(result->'states') where value->>'place_id'='657b0000-0000-0000-0000-000000000009';
  if state->'saves'->0->>'owner_id' is distinct from followee or state->'saves'->0->'is_friend' is distinct from 'false'::jsonb
    or state->'saves'->0->'has_wanna' is distinct from 'true'::jsonb then raise exception 'one-way follow incorrectly became friend or lost readable Wanna'; end if;
  select value into strict state from jsonb_array_elements(result->'states') where value->>'place_id'='657b0000-0000-0000-0000-000000000016';
  if state->'saves'->0->'has_been' is distinct from 'true'::jsonb or state->'saves'->0->'has_wanna' is distinct from 'false'::jsonb
  then raise exception 'private repeat Wanna leaked through readable Been'; end if;
  select value into strict state from jsonb_array_elements(result->'states') where value->>'place_id'='657b0000-0000-0000-0000-000000000027';
  if state->'saves'->0->>'owner_id' is distinct from viewer
    or state->'saves'->0->'has_been' is distinct from 'false'::jsonb
    or state->'saves'->0->'has_wanna' is distinct from 'true'::jsonb
  then raise exception 'fresh legacy social-save Wanna was omitted'; end if;
  for state in select value from jsonb_array_elements(result->'states') loop
    if (state->'has_list_membership'='true'::jsonb) is distinct from (state->>'place_id' in(
      '657b0000-0000-0000-0000-000000000004','657b0000-0000-0000-0000-000000000005',
      '657b0000-0000-0000-0000-000000000017','657b0000-0000-0000-0000-000000000018',
      '657b0000-0000-0000-0000-000000000021',
      '657b0000-0000-0000-0000-000000000024'))
    then raise exception 'list state ignored current list, owner, item or collaborator visibility'; end if;
  end loop;

  reset role;
  update public.place_lists set visibility='stealth' where id='657b3000-0000-0000-0000-000000000002';
  insert into public.blocks(blocker_user_id,blocked_user_id) values(friend,viewer);
  set local role authenticated;
  result:=public.live_map_pin_states(array['657b0000-0000-0000-0000-000000000008'::uuid,
    '657b0000-0000-0000-0000-000000000018'::uuid,'657b0000-0000-0000-0000-000000000024'::uuid]);
  if exists(select 1 from jsonb_array_elements(result->'states') entry
    where entry->'saves' is distinct from '[]'::jsonb or entry->'has_list_membership' is distinct from 'false'::jsonb)
  then raise exception 'fresh pin-state read retained revoked friend/list access'; end if;

  -- Unknown UUIDs are complete negative evidence; malformed or oversized scopes
  -- are rejected rather than returning a silently truncated subset.
  select array_agg(('657b9000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid) into requested from generate_series(1,200) n;
  result:=public.live_map_pin_states(requested);
  if result->'complete' is distinct from 'true'::jsonb or jsonb_array_length(result->'states') is distinct from 200
    or exists(select 1 from jsonb_array_elements(result->'states') entry
      where entry->'saves' is distinct from '[]'::jsonb or entry->'has_list_membership' is distinct from 'false'::jsonb)
  then raise exception '200-input scope was truncated or fabricated state'; end if;
  result:=public.live_map_pin_states(array[requested[1],requested[1]]);
  if result->'complete' is distinct from 'true'::jsonb or jsonb_array_length(result->'states') is distinct from 1
  then raise exception 'duplicate input did not normalize to one complete seed'; end if;
  begin perform public.live_map_pin_states(array[null::uuid]); raise exception 'null scope element accepted';
  exception when invalid_parameter_value then null; end;
  begin perform public.live_map_pin_states(null); raise exception 'null scope accepted';
  exception when invalid_parameter_value then null; end;
  begin perform public.live_map_pin_states('{}'::uuid[]); raise exception 'empty scope accepted';
  exception when invalid_parameter_value then null; end;
  begin perform public.live_map_pin_states(requested||requested[1]); raise exception 'oversized pin scope accepted';
  exception when invalid_parameter_value then null; end;
  begin perform public.live_map_pin_states(array[[requested[1]],[requested[2]]]); raise exception 'multidimensional pin scope accepted';
  exception when invalid_parameter_value then null; end;
  reset role;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',deleted_owner,'role','authenticated')::text,true);
  set local role authenticated;
  begin perform public.live_map_pin_states(array[requested[1]]); raise exception 'deleted viewer received a complete state';
  exception when invalid_authorization_specification then null; end;
  reset role;
  perform set_config('request.jwt.claims','{"role":"authenticated"}',true);
  set local role authenticated;
  begin perform public.live_map_pin_states(array[requested[1]]); raise exception 'missing viewer received a complete state';
  exception when invalid_authorization_specification then null; end;
  reset role;
  perform set_config('request.jwt.claims','{"role":"anon"}',true);
  set local role anon;
  begin perform public.live_map_pin_states(array[requested[1]]); raise exception 'anonymous pin state allowed';
  exception when insufficient_privilege then null; end;
  reset role;
end;
$pin_states$;

rollback;
