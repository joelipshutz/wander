begin;

-- Synthetic, collision-guarded fixtures only; standalone and smoke-runner paths
-- roll back every source, follow and block. No customer data is read or changed.
do $test$
declare
  v_viewer text := 'user_codex_live_place_viewer';
  v_friend text := 'user_codex_live_place_friend';
  v_followee text := 'user_codex_live_place_followee';
  v_stranger text := 'user_codex_live_place_stranger';
  v_private text := 'user_codex_live_place_private';
  v_blocked text := 'user_codex_live_place_blocked';
  v_deleted text := 'user_codex_live_place_deleted';
  v_place uuid := '636a0000-0000-0000-0000-000000000001';
  v_alias uuid := '636a0000-0000-0000-0000-000000000002';
  v_list uuid := '636a3000-0000-0000-0000-000000000001';
  v_item uuid := '636a4000-0000-0000-0000-000000000001';
  v_visit uuid := '636a5000-0000-0000-0000-000000000001';
  v_page jsonb; v_first jsonb; v_entry jsonb; v_cursor text; v_scope_cursor text;
  v_ids uuid[] := '{}'; v_proc record; v_invalid uuid[];
begin
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claim.canonical_user_id','',true);
  select * into strict v_proc from pg_proc
    where oid='public.live_place_activity(uuid[],text,integer)'::regprocedure;
  if not v_proc.prosecdef or v_proc.provolatile<>'s' or v_proc.prorettype<>'jsonb'::regtype
    or v_proc.pronargdefaults<>2
    or v_proc.proargnames<>array['input_place_ids','input_before','input_limit']::text[]
    or not ('search_path=pg_catalog, public, app, extensions'=any(v_proc.proconfig))
    or not has_function_privilege('authenticated',v_proc.oid,'execute')
    or has_function_privilege('anon',v_proc.oid,'execute')
    or exists(select 1 from aclexplode(coalesce(v_proc.proacl,acldefault('f',v_proc.proowner))) acl
      where acl.grantee=0 and acl.privilege_type='EXECUTE')
    or has_table_privilege('authenticated','public.feed_events','select')
  then raise exception 'place activity ABI/security posture changed'; end if;
  if exists(select 1 from public.profiles p where p.id=any(array[v_viewer,v_friend,v_followee,v_stranger,v_private,v_blocked,v_deleted])
      or p.handle like 'codex_live_place_%')
    or exists(select 1 from public.places p where p.id::text like '636a0000-%')
    or exists(select 1 from public.user_places p where p.id::text like '636a1000-%')
    or exists(select 1 from public.feed_events e where e.id::text like '636a2000-%')
    or exists(select 1 from public.place_lists l where l.id=v_list)
    or exists(select 1 from public.place_list_items i where i.id=v_item)
    or exists(select 1 from public.place_visits v where v.id::text like '636a5000-%')
  then raise exception 'reserved Live place fixture identity collision'; end if;

  insert into public.profiles(id,handle,display_name,is_private_profile) values
    (v_viewer,'codex_live_place_viewer','Place Viewer',false),
    (v_friend,'codex_live_place_friend','Place Friend',false),
    (v_followee,'codex_live_place_followee','Place Followee',false),
    (v_stranger,'codex_live_place_stranger','Place Stranger',false),
    (v_private,'codex_live_place_private','Private Actor',true),
    (v_blocked,'codex_live_place_blocked','Blocked Actor',false),
    (v_deleted,'codex_live_place_deleted','Deleted Actor',false);
  delete from public.follows f where f.follower_user_id=any(array[v_viewer,v_friend,v_followee,v_stranger,v_private,v_blocked,v_deleted])
    and f.source='signup_default';
  insert into public.follows(follower_user_id,followed_user_id,source) values
    (v_viewer,v_friend,'username'),(v_friend,v_viewer,'username'),
    (v_viewer,v_followee,'username'),(v_viewer,v_private,'username'),
    (v_viewer,v_blocked,'username'),(v_viewer,v_deleted,'username'),(v_stranger,v_viewer,'username');
  insert into public.blocks(blocker_user_id,blocked_user_id) values(v_blocked,v_viewer);

  -- 1..5 are aliases: UUID chain, qualified provider identity, normalized street.
  -- 6..16 are separate branches: address, distance, locality, blank street,
  -- different name, different provider namespace, case-sensitive opaque ID, or
  -- UUID reference with wrong metadata/distance, including a shared UUID token
  -- in the same normalized provider namespace. None may be guessed into it.
  insert into public.places(id,canonical_name,category,address,locality,region,country,
    latitude,longitude,source_provider,source_provider_place_id)
  select ('636a0000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
    case when n in(4,11,12,13,15) then 'Alias identity '||n when n=10 then 'Other shop' else 'Review Café' end,
    'coffee',
    case when n in(2,3,4,9,11,12,13,14,15,16) then null when n=5 then '10 EXAMPLE ST.' when n=6 then '20 Example Street' else '10 Example Street' end,
    case when n=8 then 'Other Town' else 'Sampleton' end,'CA','US',
    0,case when n in(7,14,16) then 0.01 else n*0.00001 end,
    case when n in(4,16) then 'MAPKIT' when n=15 then 'MapKit' when n in(12,14) then 'mapkit' when n>=5 then 'manual' else 'mapkit' end,
    case when n=1 or n=11 then 'rec636-preview-main'
      when n=2 then v_place::text when n=3 then v_alias::text
      when n=4 then 'rec636-preview-main' when n=12 then 'REC636-PREVIEW-MAIN'
      when n in(13,15,16) then v_place::text when n=14 then '636a0000-0000-0000-0000-000000000003' else 'rec636-preview-'||n end
  from generate_series(1,16) n;
  insert into public.user_places(id,user_id,place_id,status,visibility,source_type,note)
  select ('636a1000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
    case when n=3 then v_followee when n=4 then v_viewer else v_friend end,
    ('636a0000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
    'been',case when n=4 then 'self' else 'followers' end,'manual','Parent note'
  from generate_series(1,16) n;
  insert into public.user_places(id,user_id,place_id,status,visibility,source_type,note)
  select ('636a1000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
    case n when 90 then v_private when 91 then v_blocked when 92 then v_stranger
      when 94 then v_deleted when 95 then v_followee end,
    v_place,'been','followers','manual','PRIVATE SOURCE SENTINEL'
  from unnest(array[90,91,92,94,95]) n;
  update public.user_places p set deleted_at=now() where p.id='636a1000-0000-0000-0000-000000000095';
  update public.profiles p set deleted_at=now() where p.id=v_deleted;
  insert into public.place_visits(id,user_place_id,visited_at,note,rating_score) values
    (v_visit,'636a1000-0000-0000-0000-000000000001',now()-interval '4 days','Original visit note',4.5),
    ('636a5000-0000-0000-0000-000000000096','636a1000-0000-0000-0000-000000000001',now(),'PRIVATE DELETED VISIT',3);
  update public.place_visits v set deleted_at=now() where v.id='636a5000-0000-0000-0000-000000000096';
  insert into public.place_lists(id,owner_user_id,name,visibility) values(v_list,v_followee,'Preview list fixture','followers');
  insert into public.place_list_items(id,list_id,place_id,owner_user_place_id,source_user_place_id,added_by_user_id)
    values(v_item,v_list,'636a0000-0000-0000-0000-000000000003',
      '636a1000-0000-0000-0000-000000000003','636a1000-0000-0000-0000-000000000003',v_stranger);
  -- Preserve genuine sources but replace their automatic events with controlled
  -- IDs/times so sort order, privacy and original projection are deterministic.
  delete from public.feed_events e where e.actor_user_id=any(array[v_viewer,v_friend,v_followee,v_stranger,v_private,v_blocked,v_deleted]);
  insert into public.feed_events(id,actor_user_id,event_type,user_place_id,place_id,visit_id,list_id,list_item_id,occurred_at)
  select ('636a2000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
    case when n=3 then v_stranger when n=4 then v_viewer else v_friend end,
    case n when 2 then 'place_want_to_go' when 3 then 'list_item_added' when 5 then 'place_saved' else 'place_been' end,
    ('636a1000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
    ('636a0000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
    case when n=1 then v_visit end,case when n=3 then v_list end,case when n=3 then v_item end,
    case n when 1 then now()-interval '4 days' when 2 then now()-interval '3 days'
      when 3 then now()-interval '2 days' when 4 then now()-interval '1 day'
      when 5 then now()-interval '3 days' else now() end
  from generate_series(1,16) n;
  insert into public.place_wanna_saves(id,user_place_id,visibility,note,occurred_at) values
    ('636a2000-0000-0000-0000-000000000002','636a1000-0000-0000-0000-000000000002','followers','Independent Wanna note',now()-interval '3 days');
  insert into public.feed_events(id,actor_user_id,event_type,user_place_id,place_id,occurred_at) values
    ('636a2000-0000-0000-0000-000000000020',v_friend,'place_want_to_go','636a1000-0000-0000-0000-000000000001',v_place,now()-interval '5 days'),
    ('636a2000-0000-0000-0000-000000000093',v_friend,'place_want_to_go','636a1000-0000-0000-0000-000000000001',v_place,now());
  insert into public.place_wanna_saves(id,user_place_id,visibility,note,occurred_at) values
    ('636a2000-0000-0000-0000-000000000020','636a1000-0000-0000-0000-000000000001','mutuals',null,now()-interval '5 days'),
    ('636a2000-0000-0000-0000-000000000093','636a1000-0000-0000-0000-000000000001','self','PRIVATE WANNA SENTINEL',now());
  insert into public.feed_events(id,actor_user_id,event_type,user_place_id,place_id,occurred_at)
  select ('636a2000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
    case n when 90 then v_private when 91 then v_blocked when 92 then v_stranger when 94 then v_deleted when 95 then v_followee end,
    'place_been',('636a1000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,v_place,now()
  from unnest(array[90,91,92,94,95]) n;
  insert into public.feed_events(id,actor_user_id,event_type,user_place_id,place_id,visit_id,occurred_at) values
    ('636a2000-0000-0000-0000-000000000096',v_friend,'place_been','636a1000-0000-0000-0000-000000000001',v_place,'636a5000-0000-0000-0000-000000000096',now());
  -- Newer unrelated rows must be filtered before LIMIT; no loaded-page gap.
  insert into public.feed_events(id,actor_user_id,event_type,user_place_id,place_id,occurred_at)
  select ('636a2000-0000-0000-0000-'||lpad((100+n)::text,12,'0'))::uuid,v_friend,'place_been',
    '636a1000-0000-0000-0000-000000000006','636a0000-0000-0000-0000-000000000006',now()
  from generate_series(1,60) n;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_viewer,'role','authenticated')::text,true);
  set local role authenticated;
  v_first:=public.live_place_activity(array[v_place]);
  if jsonb_array_length(v_first->'activity')<>6 or v_first->>'next_cursor' is not null
    or v_first->'featured_places'<>'[]'::jsonb or v_first->>'fetched_at' is null
    or v_first::text like '%PRIVATE%'
  then raise exception 'place alias scope, privacy or envelope changed'; end if;
  if (select array_agg(e->>'id') from jsonb_array_elements(v_first->'activity') e)
    is distinct from array['636a2000-0000-0000-0000-000000000004','636a2000-0000-0000-0000-000000000003',
      '636a2000-0000-0000-0000-000000000005','636a2000-0000-0000-0000-000000000002',
      '636a2000-0000-0000-0000-000000000001','636a2000-0000-0000-0000-000000000020']::text[]
  then raise exception 'mixed activity chronology or tied ordering changed'; end if;
  if public.live_place_activity(array[v_alias])->'activity' is distinct from v_first->'activity'
    or public.live_place_activity(array['636a0000-0000-0000-0000-000000000003'::uuid])->'activity' is distinct from v_first->'activity'
  then raise exception 'bidirectional/transitive UUID aliases lost activity'; end if;
  for v_entry in select value from jsonb_array_elements(v_first->'activity') loop
    if v_entry->'media'<>'[]'::jsonb or v_entry->'actor'->>'id' is null
      or not exists(select 1 from jsonb_array_elements(v_entry->'place'->'attributes') attribute
        where attribute->>'question_key'='__viewer_taxonomy_primary_category')
    then raise exception 'Feed payload/taxonomy/media contract changed'; end if;
  end loop;
  if not exists(select 1 from jsonb_array_elements(v_first->'activity') e
      where e->>'id'='636a2000-0000-0000-0000-000000000001' and e->>'note'='Original visit note' and (e->>'rating')::numeric=4.5)
    or not exists(select 1 from jsonb_array_elements(v_first->'activity') e
      where e->>'id'='636a2000-0000-0000-0000-000000000002' and e->>'note'='Independent Wanna note' and e->'rating'='null'::jsonb)
    or not exists(select 1 from jsonb_array_elements(v_first->'activity') e
      where e->>'id'='636a2000-0000-0000-0000-000000000020' and e->'note'='null'::jsonb)
    or not exists(select 1 from jsonb_array_elements(v_first->'activity') e
      where e->>'event_type'='list_item_added' and e->'list'->>'id'=v_list::text)
  then raise exception 'original visit/Wanna/list projection changed'; end if;
  -- A readable list contributor can be outside the viewer's following graph.
  -- Reverse-only follows must not be mislabeled as mutual friendships.
  if not exists(select 1 from jsonb_array_elements(v_first->'activity') e
      where e->>'event_type'='list_item_added' and e->'actor'->>'id'=v_stranger
        and e->'actor'->>'relationship'='non_follower')
    or exists(select 1 from jsonb_array_elements(v_first->'activity') e
      where e->'actor'->>'id'=v_friend and e->'actor'->>'relationship'<>'mutual')
    or exists(select 1 from jsonb_array_elements(v_first->'activity') e
      where e->'actor'->>'id'=v_viewer and e->'actor'->>'relationship'<>'owner')
  then raise exception 'viewer relationship labels changed'; end if;
  v_page:=public.live_place_activity(array[v_place],null,2);
  loop
    for v_entry in select value from jsonb_array_elements(v_page->'activity') loop
      if (v_entry->>'id')::uuid=any(v_ids) then raise exception 'duplicate keyset row'; end if;
      v_ids:=array_append(v_ids,(v_entry->>'id')::uuid);
    end loop;
    v_cursor:=v_page->>'next_cursor'; exit when v_cursor is null;
    if cardinality(v_ids)>6 then raise exception 'unbounded keyset'; end if;
    v_page:=public.live_place_activity(array[v_place],v_cursor,2);
  end loop;
  if cardinality(v_ids)<>6 then raise exception 'keyset lost tied row'; end if;
  v_scope_cursor:=public.live_place_activity(array[v_alias,v_place],null,2)->>'next_cursor';
  perform public.live_place_activity(array[v_place,v_alias,v_place],v_scope_cursor,2);
  begin perform public.live_place_activity(array[v_place],v_scope_cursor); raise exception 'different requested scope accepted';
  exception when invalid_parameter_value then null; end;
  begin perform public.live_place_activity(array[v_place], 'broken'); raise exception 'malformed cursor accepted';
  exception when invalid_parameter_value then null; end;
  begin perform public.live_place_activity(array[v_place],split_part(public.live_place_activity(array[v_place],null,1)->>'next_cursor','|',1)||'|infinity|'||v_place); raise exception 'infinite cursor accepted';
  exception when invalid_parameter_value then null; end;
  begin perform public.live_place_activity(null); raise exception 'null scope accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.live_place_activity('{}'); raise exception 'empty scope accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.live_place_activity(array[v_place,null]); raise exception 'null identity accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.live_place_activity(array[[v_place],[v_alias]]); raise exception 'multidimensional scope accepted'; exception when invalid_parameter_value then null; end;
  select array_agg(v_place) into v_invalid from generate_series(1,101);
  begin perform public.live_place_activity(v_invalid); raise exception 'unbounded scope accepted'; exception when invalid_parameter_value then null; end;
  if jsonb_array_length(public.live_place_activity(array[v_place],null,0)->'activity')<>1
  then raise exception 'lower page bound changed'; end if;
  reset role;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_stranger,'role','authenticated')::text,true);
  set local role authenticated;
  -- The stranger owns one private fixture source; no other actor is readable.
  v_page:=public.live_place_activity(array[v_place]);
  if jsonb_array_length(v_page->'activity')<>1 or v_page->'activity'->0->'actor'->>'id'<>v_stranger
  then raise exception 'stranger read another actor'; end if;
  begin perform public.live_place_activity(array[v_place,v_alias],v_scope_cursor); raise exception 'cross-account cursor accepted';
  exception when invalid_parameter_value then null; end;
  reset role;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_viewer,'role','authenticated')::text,true);

  delete from public.follows f where f.follower_user_id=v_friend and f.followed_user_id=v_viewer;
  set local role authenticated;
  if exists(select 1 from jsonb_array_elements(public.live_place_activity(array[v_place])->'activity') e
    where e->>'id'='636a2000-0000-0000-0000-000000000020')
  then raise exception 'mutual revocation leaked repeat Wanna'; end if;
  if exists(select 1 from jsonb_array_elements(public.live_place_activity(array[v_place])->'activity') e
    where e->'actor'->>'id'=v_friend and e->'actor'->>'relationship'<>'follower')
  then raise exception 'one-way follow mislabeled'; end if;
  reset role;
  update public.profiles p set is_private_profile=true where p.id=v_friend;
  set local role authenticated;
  if exists(select 1 from jsonb_array_elements(public.live_place_activity(array[v_place])->'activity') e where e->'actor'->>'id'=v_friend)
  then raise exception 'profile privacy revocation leaked'; end if;
  reset role;
  update public.profiles p set is_private_profile=false where p.id=v_friend;
  insert into public.blocks(blocker_user_id,blocked_user_id) values(v_viewer,v_friend);
  set local role authenticated;
  if exists(select 1 from jsonb_array_elements(public.live_place_activity(array[v_place,v_alias],v_scope_cursor)->'activity') e where e->'actor'->>'id'=v_friend)
  then raise exception 'old cursor bypassed new block'; end if;
  reset role;
  delete from public.blocks b where b.blocker_user_id=v_viewer and b.blocked_user_id=v_friend;
  delete from public.follows f where f.follower_user_id=v_viewer and f.followed_user_id=v_friend;
  set local role authenticated;
  if exists(select 1 from jsonb_array_elements(public.live_place_activity(array[v_place])->'activity') e where e->'actor'->>'id'=v_friend)
  then raise exception 'follow removal leaked'; end if;
  reset role;
  update public.place_lists l set deleted_at=now() where l.id=v_list;
  set local role authenticated;
  if exists(select 1 from jsonb_array_elements(public.live_place_activity(array[v_place])->'activity') e where e->>'event_type'='list_item_added')
  then raise exception 'deleted list leaked'; end if;
  reset role;

  -- Page bounds are server enforced, including for owner activity.
  insert into public.feed_events(id,actor_user_id,event_type,user_place_id,place_id,occurred_at)
  select ('636a2000-0000-0000-0000-'||lpad((200+n)::text,12,'0'))::uuid,v_viewer,'place_been',
    '636a1000-0000-0000-0000-000000000004','636a0000-0000-0000-0000-000000000004',now()-interval '10 days'
  from generate_series(1,55) n;
  set local role authenticated;
  v_page:=public.live_place_activity(array[v_place],null,10000);
  if jsonb_array_length(v_page->'activity')<>50 or v_page->>'next_cursor' is null then raise exception 'upper page bound failed'; end if;
  if jsonb_array_length(public.live_place_activity(array[v_place],v_page->>'next_cursor',50)->'activity')<>6
  then raise exception 'bounded final page failed'; end if;
  reset role;
  update public.profiles p set deleted_at=now() where p.id=v_viewer;
  set local role authenticated;
  if public.live_place_activity(array[v_place])->'activity'<>'[]'::jsonb then raise exception 'deleted viewer read activity'; end if;
  reset role;
  perform set_config('request.jwt.claims','{"role":"authenticated"}',true);
  set local role authenticated;
  if public.live_place_activity(array[v_place])->'activity'<>'[]'::jsonb then raise exception 'missing claim read activity'; end if;
  reset role;
  perform set_config('request.jwt.claims','{"role":"anon"}',true);
  set local role anon;
  begin perform public.live_place_activity(array[v_place]); raise exception 'anonymous execute accepted';
  exception when insufficient_privilege then null; end;
  reset role;
end;
$test$;

rollback;
