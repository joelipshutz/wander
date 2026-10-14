begin;

do $test$
declare
  viewer text := 'user_codex_live_viewer'; friend text := 'user_codex_live_friend';
  followee text := 'user_codex_live_followee'; stranger text := 'user_codex_live_stranger';
  since_time timestamptz := now()-interval '7 days'; until_time timestamptz := now()+interval '5 minutes';
  area jsonb := '[{"latitude":-1,"longitude":-1},{"latitude":-1,"longitude":1},{"latitude":1,"longitude":1},{"latitude":1,"longitude":-1}]';
  date_line jsonb := '[{"latitude":-1,"longitude":179},{"latitude":-1,"longitude":-179},{"latitude":1,"longitude":-179},{"latitude":1,"longitude":179}]';
  page jsonb; following_page jsonb; cursor text; item jsonb; ids uuid[] := '{}'; proc record; list_id uuid := gen_random_uuid();
  legacy_id uuid := gen_random_uuid(); first_page_cursor text;
begin
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claim.canonical_user_id','',true);
  for proc in select * from pg_proc where oid in (
    'public.live_activity_feed(text,timestamptz,timestamptz,text,jsonb,text,integer,double precision,double precision,integer,text[],text[])'::regprocedure,
    'app.live_activity_feed(text,timestamptz,timestamptz,text,jsonb,text,integer,double precision,double precision,integer,text[],text[])'::regprocedure)
  loop
    if not proc.prosecdef or proc.provolatile<>'s' or proc.prorettype<>'jsonb'::regtype
      or not ('search_path=pg_catalog, public, app, extensions'=any(proc.proconfig))
      or has_function_privilege('anon',proc.oid,'execute')
      or exists(select 1 from aclexplode(coalesce(proc.proacl,acldefault('f',proc.proowner))) where grantee=0 and privilege_type='EXECUTE')
    then raise exception 'Live function security posture changed'; end if;
  end loop;
  if not has_function_privilege('authenticated','public.live_activity_feed(text,timestamptz,timestamptz,text,jsonb,text,integer,double precision,double precision,integer,text[],text[])','execute')
    or has_function_privilege('authenticated','app.live_activity_feed(text,timestamptz,timestamptz,text,jsonb,text,integer,double precision,double precision,integer,text[],text[])','execute')
    or has_function_privilege('authenticated','app.live_feed_polygon(jsonb)','execute')
    or has_table_privilege('authenticated','public.feed_events','select')
  then raise exception 'Live public/private grants changed'; end if;
  -- The preexisting APIs retain their audited security posture.
  if not (select prosecdef and provolatile='s' and 'search_path=app, public'=any(proconfig)
      from pg_proc where oid='public.activity_feed(text,text,integer)'::regprocedure)
    or has_function_privilege('anon','public.activity_feed(text,text,integer)','execute')
  then raise exception 'legacy Feed security changed'; end if;

  insert into public.profiles(id,handle,display_name,is_private_profile) values
    (viewer,'codex_live_viewer','Live Viewer',false),(friend,'codex_live_friend','Live Friend',false),
    (followee,'codex_live_followee','Live Followee',false),(stranger,'codex_live_stranger','Live Stranger',false);
  -- Signup defaults are production configuration, not part of this fixture's
  -- known audience. Remove only these synthetic accounts' automatic edges.
  delete from public.follows
    where follower_user_id in (viewer,friend,followee,stranger) and source='signup_default';
  insert into public.follows(follower_user_id,followed_user_id,source) values
    (viewer,friend,'username'),(friend,viewer,'username'),(viewer,followee,'username');
  insert into public.places(id,canonical_name,category,latitude,longitude,source_provider,source_provider_place_id)
    select ('63600000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'Live fixture '||n,'coffee',
      case when n<=60 then 20 else 0 end,case when n<=60 then 20 else 0 end,'manual','rec636-live-'||n
    from generate_series(1,70) n;
  insert into public.user_places(id,user_id,place_id,status,visibility,source_type,note)
    select ('63610000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
      case n when 67 then stranger when 68 then followee when 69 then viewer else friend end,
      ('63600000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
      case when n<=60 or n=70 then 'wanna_go' else 'been' end,
      case when n in(66,69) then 'self' when n=62 then 'mutuals' else 'followers' end,
      'manual',case when n in(66,67) then 'PRIVATE MUST NOT LEAK' else 'Visible fixture' end
    from generate_series(1,70) n;
  -- Isolate this suite from trigger multiplicity while preserving real source
  -- visibility/projection helpers. Facts are fixture-only and roll back.
  delete from public.feed_events where actor_user_id in(viewer,friend,followee,stranger);
  insert into public.feed_events(id,actor_user_id,event_type,user_place_id,place_id,occurred_at)
    select ('63620000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
      case n when 67 then stranger when 68 then followee when 69 then viewer else friend end,
      case when n<=60 or n=70 then 'place_want_to_go' else 'place_been' end,
      ('63610000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
      ('63600000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
      case when n<=60 then now()-interval '1 hour' when n=70 then now()-interval '30 days' else now()-interval '2 days' end
    from generate_series(1,70) n;
  insert into public.feed_events(id,actor_user_id,event_type,user_place_id,place_id,occurred_at)
    values(legacy_id,friend,'place_saved','63610000-0000-0000-0000-000000000061','63600000-0000-0000-0000-000000000061',now()-interval '2 days');
  insert into public.place_lists(id,owner_user_id,name,visibility) values(list_id,friend,'Live list-only fixture','followers');

  perform set_config('request.jwt.claims',jsonb_build_object('sub',viewer,'role','authenticated')::text,true);
  set local role authenticated;
  page := public.live_activity_feed('everyone');
  -- Live adds canonical viewer category metadata; source records/order stay exact.
  if (select jsonb_agg(e #- '{place,attributes}') from jsonb_array_elements(page->'activity') e)
    is distinct from (select jsonb_agg(e #- '{place,attributes}') from jsonb_array_elements(public.activity_feed('everyone',null,25)->'activity') e)
  then raise exception 'unfiltered Live differs from authoritative Feed'; end if;
  if page::text like '%PRIVATE MUST NOT LEAK%' then raise exception 'unauthorized source leaked'; end if;
  -- Sixty newer, nonmatching Wannas precede all Check-ins. A loaded-page filter
  -- would return no result; server pre-pagination must return all eight matches.
  page := public.live_activity_feed('everyone',since_time,until_time,'check_ins',area,null,50);
  if jsonb_array_length(page->'activity')<>8 or page->>'next_cursor' is not null
  then raise exception 'filtered page gap or incorrect legacy status classification'; end if;
  if not exists(select 1 from jsonb_array_elements(page->'activity') e where (e->>'id')::uuid=legacy_id)
  then raise exception 'legacy Been save excluded from Check-ins'; end if;
  if page::text like '%PRIVATE MUST NOT LEAK%' then raise exception 'filtered private source leaked'; end if;
  page := public.live_activity_feed('everyone',since_time,until_time,'check_ins',area,null,2);
  first_page_cursor := page->>'next_cursor';
  loop
    for item in select value from jsonb_array_elements(page->'activity') loop
      if (item->>'id')::uuid=any(ids) then raise exception 'duplicate activity across keyset pages'; end if;
      ids:=array_append(ids,(item->>'id')::uuid);
    end loop;
    cursor:=page->>'next_cursor';
    exit when cursor is null;
    if cardinality(ids)>20 then raise exception 'unbounded pagination'; end if;
    page:=public.live_activity_feed('everyone',since_time,until_time,'check_ins',area,cursor,2);
  end loop;
  if cardinality(ids)<>8 then raise exception 'filtered keyset lost rows at tied timestamps'; end if;
  page:=public.live_activity_feed('everyone',since_time,until_time,'wannas',null,null,10000);
  if jsonb_array_length(page->'activity')<>50 or page->>'next_cursor' is null then raise exception 'bounded Wanna page failed'; end if;
  page:=public.live_activity_feed('everyone',since_time,until_time,'wannas',null,page->>'next_cursor',50);
  if jsonb_array_length(page->'activity')<>10 or page->>'next_cursor' is not null then raise exception 'time cutoff or final page wrong'; end if;
  if jsonb_array_length(public.live_activity_feed('everyone',since_time,until_time,'wannas',area)->'activity')<>0 then raise exception 'out-of-area Wanna leaked'; end if;
  if jsonb_array_length(public.live_activity_feed('only_me',since_time,until_time,'check_ins',area)->'activity')<>1 then raise exception 'owner Self activity missing'; end if;
  if jsonb_array_length(public.live_activity_feed('only_friends',since_time,until_time,'check_ins',area)->'activity')<>6 then raise exception 'mutual audience widened'; end if;
  page:=public.live_activity_feed('everyone',null,null,'all',null,null,50);
  if not exists(select 1 from jsonb_array_elements(page->'activity') e where e->>'event_type'='list_created' and e->'place'='null'::jsonb)
  then raise exception 'list-only activity omitted without a geographic filter'; end if;
  if exists(select 1 from jsonb_array_elements(public.live_activity_feed('everyone',null,null,'all',area,null,50)->'activity') e where e->>'event_type'='list_created')
  then raise exception 'unmapped list incorrectly passed geographic filter'; end if;
  begin perform public.live_activity_feed('everyone',since_time,until_time,'wannas',area,first_page_cursor); raise exception 'cross-type cursor accepted';
  exception when invalid_parameter_value then null; end;
  begin perform public.live_activity_feed('only_me',since_time,until_time,'check_ins',area,first_page_cursor); raise exception 'cross-audience cursor accepted';
  exception when invalid_parameter_value then null; end;
  begin perform public.live_activity_feed('everyone',since_time-interval '1 day',until_time,'check_ins',area,first_page_cursor); raise exception 'cross-time cursor accepted';
  exception when invalid_parameter_value then null; end;
  begin perform public.live_activity_feed('everyone',since_time,until_time,'check_ins',null,first_page_cursor); raise exception 'cross-area cursor accepted';
  exception when invalid_parameter_value then null; end;
  begin perform public.live_activity_feed('everyone',input_before=>'broken'); raise exception 'malformed cursor reset silently';
  exception when invalid_parameter_value then null; end;
  begin perform public.live_activity_feed('everyone',input_polygon=>'[]'); raise exception 'empty polygon accepted';
  exception when invalid_parameter_value then null; end;
  begin perform public.live_activity_feed('everyone',input_polygon=>'[{"latitude":0,"longitude":0},{"latitude":1,"longitude":1},{"latitude":0,"longitude":1},{"latitude":1,"longitude":0}]'); raise exception 'self-intersecting polygon accepted';
  exception when invalid_parameter_value then null; end;
  begin perform public.live_activity_feed('everyone',input_polygon=>'[{"latitude":-10,"longitude":0},{"latitude":-10,"longitude":120},{"latitude":10,"longitude":-120}]'); raise exception 'ambiguous wide polygon accepted';
  exception when invalid_parameter_value then null; end;
  begin perform public.live_activity_feed('everyone',input_polygon=>'[{"latitude":-10,"longitude":120},{"latitude":10,"longitude":-120},{"latitude":-10,"longitude":0}]'); raise exception 'rotated ambiguous polygon accepted';
  exception when invalid_parameter_value then null; end;
  reset role;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',stranger,'role','authenticated')::text,true);
  set local role authenticated;
  begin perform public.live_activity_feed('everyone',since_time,until_time,'check_ins',area,first_page_cursor); raise exception 'cross-account cursor accepted';
  exception when invalid_parameter_value then null; end;
  reset role;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',viewer,'role','authenticated')::text,true);

  update public.places set longitude=179.5 where id='63600000-0000-0000-0000-000000000068';
  set local role authenticated;
  page:=public.live_activity_feed('everyone',since_time,until_time,'check_ins',date_line);
  if jsonb_array_length(page->'activity')<>1 or page->'activity'->0->'actor'->>'id'<>followee then raise exception 'antimeridian polygon widened or lost point'; end if;
  reset role;
  update public.places set longitude=1 where id='63600000-0000-0000-0000-000000000068';
  set local role authenticated;
  if not exists(select 1 from jsonb_array_elements(public.live_activity_feed('everyone',since_time,until_time,'check_ins',area)->'activity') e where e->'actor'->>'id'=followee)
  then raise exception 'polygon boundary excluded'; end if;
  reset role;
  delete from public.follows where follower_user_id=friend and followed_user_id=viewer;
  set local role authenticated;
  if public.live_activity_feed('only_friends')->'activity'<>'[]'::jsonb then raise exception 'friendship loss not enforced'; end if;
  if exists(select 1 from jsonb_array_elements(public.live_activity_feed('everyone',since_time,until_time,'check_ins',area)->'activity') e where e->>'id'='63620000-0000-0000-0000-000000000062')
  then raise exception 'revoked mutual source leaked'; end if;
  reset role;
  insert into public.blocks(blocker_user_id,blocked_user_id) values(friend,viewer);
  set local role authenticated;
  if exists(select 1 from jsonb_array_elements(public.live_activity_feed('everyone')->'activity') e where e->'actor'->>'id'=friend)
  then raise exception 'hard-blocked actor leaked'; end if;
  reset role;
  update public.user_places set deleted_at=now() where id='63610000-0000-0000-0000-000000000068';
  set local role authenticated;
  if exists(select 1 from jsonb_array_elements(public.live_activity_feed('everyone')->'activity') e where e->'actor'->>'id'=followee)
  then raise exception 'deleted source leaked'; end if;
  reset role;
  perform set_config('request.jwt.claims','{"role":"anon"}',true);
  set local role anon;
  begin perform public.live_activity_feed('everyone'); raise exception 'anonymous Live accepted';
  exception when insufficient_privilege then null; end;
  reset role;
end;
$test$;

-- Independent refinement fixtures: every filtered query must pass sixty newer
-- nonmatches before reaching its first eligible result. All changes roll back.
do $refinements$
declare
  viewer text := 'user_codex_live_refine_viewer'; actor text := 'user_codex_live_refine_actor';
  other_actor text := 'user_codex_live_refine_other'; stranger text := 'user_codex_live_refine_stranger';
  page jsonb; next_page jsonb; cursor text; item jsonb; invalid_query jsonb;
  until_time timestamptz := now()+interval '5 minutes';
  area jsonb := '[{"latitude":-0.01,"longitude":-0.01},{"latitude":-0.01,"longitude":0.01},{"latitude":0.01,"longitude":0.01},{"latitude":0.01,"longitude":-0.01}]';
begin
  reset role;
  insert into public.profiles(id,handle,display_name,is_private_profile) values
    (viewer,'codex_live_refine_viewer','Refine Viewer',false),(actor,'codex_live_refine_actor','Refine Actor',false),
    (other_actor,'codex_live_refine_other','Refine Other',false),(stranger,'codex_live_refine_stranger','Refine Stranger',false);
  delete from public.follows
    where follower_user_id in (viewer,actor,other_actor,stranger) and source='signup_default';
  insert into public.follows(follower_user_id,followed_user_id,source) values
    (viewer,actor,'username'),(actor,viewer,'username'),(viewer,other_actor,'username');
  insert into public.places(id,canonical_name,category,primary_category,latitude,longitude,source_provider,source_provider_place_id)
    select ('63630000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'Refinement fixture '||n,
      case when n<=60 then 'coffee_tea_sweets' else 'restaurants_food' end,
      case when n<=60 then 'coffee_tea_sweets' else 'restaurants_food' end,
      0,case when n<=60 then 20 when n=64 then 0.1 else 0 end,'manual','rec636-refine-'||n
    from generate_series(1,66) n;
  -- Conflicting provider evidence must not make the client discard a returned
  -- canonical category match; the Live-only viewer attribute is authoritative.
  update public.places set raw_provider_type='MKPOICategoryCafe'
    where id='63630000-0000-0000-0000-000000000063';
  insert into public.user_places(id,user_id,place_id,status,visibility,source_type,category_override,category_override_source)
    select ('63640000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
      case when n<=60 or n=66 then other_actor when n=65 then stranger else actor end,
      ('63630000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'been','followers','manual',
      case when n=64 then 'bars_nightlife' end,case when n=64 then 'user' end
    from generate_series(1,66) n;
  -- One viewer has a private frozen snapshot; another place has their own
  -- override. Neither may use the source actor's private category instead.
  insert into public.place_taxonomy_snapshots(user_id,place_id,primary_category,captured_for)
    values(viewer,'63630000-0000-0000-0000-000000000061','bars_nightlife','backfill');
  insert into public.user_places(id,user_id,place_id,status,visibility,source_type,category_override,category_override_source)
    values('63640000-0000-0000-0000-000000000162',viewer,'63630000-0000-0000-0000-000000000062',
      'been','self','manual','wellness_fitness','user');
  delete from public.feed_events where actor_user_id in(viewer,actor,other_actor,stranger);
  insert into public.feed_events(id,actor_user_id,event_type,user_place_id,place_id,occurred_at)
    select ('63650000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
      case when n<=60 or n=66 then other_actor when n=65 then stranger else actor end,'place_been',
      ('63640000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
      ('63630000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
      case when n<=60 then now()-interval '1 hour' else now()-interval '2 days' end
    from generate_series(1,66) n;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',viewer,'role','authenticated')::text,true);
  set local role authenticated;

  page:=public.live_activity_feed('everyone',input_limit=>50,input_category_ids=>array['restaurants_food']);
  if jsonb_array_length(page->'activity')<>3 or page->>'next_cursor' is not null
  then raise exception 'category filter after limit or wrong viewer taxonomy'; end if;
  if jsonb_array_length(public.live_activity_feed('everyone',input_limit=>50,input_person_ids=>array[actor])->'activity')<>4
  then raise exception 'person filter after limit or wrong actor identity'; end if;
  if jsonb_array_length(public.live_activity_feed('everyone',input_center_latitude=>0,input_center_longitude=>0,input_radius_meters=>5000)->'activity')<>4
  then raise exception 'radius filter after limit or wrong 5km geography'; end if;
  if public.live_activity_feed('everyone',input_person_ids=>array[stranger])->'activity'<>'[]'::jsonb
  then raise exception 'person refinement granted stranger visibility'; end if;
  if public.live_activity_feed('only_friends',input_person_ids=>array[other_actor])->'activity'<>'[]'::jsonb
  then raise exception 'person refinement bypassed mutual audience'; end if;
  if public.live_activity_feed('everyone',input_category_ids=>array['unknown_category'])->'activity'<>'[]'::jsonb
  then raise exception 'unknown category widened results'; end if;

  -- Canonical viewer category travels with each Live projection, including
  -- the unfrozen fallback, so the native client need not reinterpret it.
  for item in select value from jsonb_array_elements(page->'activity') loop
    if not exists(select 1 from jsonb_array_elements(item->'place'->'attributes') attribute
      where attribute->>'question_key'='__viewer_taxonomy_primary_category' and attribute->>'value'='restaurants_food')
      or item->'place'->>'category_override' is not null
    then raise exception 'Live category payload mismatched or actor override leaked'; end if;
  end loop;
  if jsonb_array_length(public.live_activity_feed('everyone',input_person_ids=>array[actor],input_category_ids=>array['bars_nightlife'])->'activity')<>1
    or jsonb_array_length(public.live_activity_feed('everyone',input_person_ids=>array[actor],input_category_ids=>array['wellness_fitness'])->'activity')<>1
  then raise exception 'viewer snapshot or viewer override ignored'; end if;

  page:=public.live_activity_feed('everyone',input_until=>until_time,input_limit=>1,input_center_latitude=>0,
    input_center_longitude=>0,input_radius_meters=>25000,input_category_ids=>array['restaurants_food'],input_person_ids=>array[actor]);
  cursor:=page->>'next_cursor';
  if jsonb_array_length(page->'activity')<>1 or cursor is null then raise exception '25km combined filtered page missing'; end if;
  next_page:=public.live_activity_feed('everyone',input_until=>until_time,input_before=>cursor,input_limit=>1,input_center_latitude=>0,
    input_center_longitude=>0,input_radius_meters=>25000,input_category_ids=>array['restaurants_food','restaurants_food'],input_person_ids=>array[actor,actor]);
  if jsonb_array_length(next_page->'activity')<>1 or next_page->>'next_cursor' is not null
    or page->'activity'->0->>'id'=next_page->'activity'->0->>'id'
  then raise exception 'combined tied-cursor pagination or duplicate-set normalization failed'; end if;
  if jsonb_array_length(public.live_activity_feed('everyone',input_polygon=>area,input_center_latitude=>0,input_center_longitude=>0,
    input_radius_meters=>25000,input_category_ids=>array['restaurants_food'],input_person_ids=>array[actor])->'activity')<>1
  then raise exception 'drawn area must intersect radius'; end if;
  if jsonb_array_length(public.live_activity_feed('everyone',input_center_latitude=>0,input_center_longitude=>0,
    input_radius_meters=>5000,input_category_ids=>array['restaurants_food'],input_person_ids=>array[actor])->'activity')<>1
  then raise exception '5km explicit radius did not narrow 25km'; end if;

  -- Every changed semantic dimension invalidates the prior cursor.
  begin perform public.live_activity_feed('everyone',input_until=>until_time,input_before=>cursor,input_center_latitude=>0,
    input_center_longitude=>0,input_radius_meters=>5000,input_category_ids=>array['restaurants_food'],input_person_ids=>array[actor]);
    raise exception 'cross-radius cursor accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.live_activity_feed('everyone',input_until=>until_time,input_before=>cursor,input_center_latitude=>0.01,
    input_center_longitude=>0,input_radius_meters=>25000,input_category_ids=>array['restaurants_food'],input_person_ids=>array[actor]);
    raise exception 'cross-center cursor accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.live_activity_feed('everyone',input_until=>until_time,input_before=>cursor,input_center_latitude=>0,
    input_center_longitude=>0,input_radius_meters=>25000,input_category_ids=>array['bars_nightlife'],input_person_ids=>array[actor]);
    raise exception 'cross-category cursor accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.live_activity_feed('everyone',input_until=>until_time,input_before=>cursor,input_center_latitude=>0,
    input_center_longitude=>0,input_radius_meters=>25000,input_category_ids=>array['restaurants_food'],input_person_ids=>array[other_actor]);
    raise exception 'cross-person cursor accepted'; exception when invalid_parameter_value then null; end;
  page:=public.live_activity_feed('everyone',input_limit=>1,input_category_ids=>array['restaurants_food','bars_nightlife'],input_person_ids=>array[actor,other_actor]);
  perform public.live_activity_feed('everyone',input_before=>page->>'next_cursor',input_category_ids=>array['bars_nightlife','restaurants_food'],input_person_ids=>array[other_actor,actor]);
  page:=public.live_activity_feed('everyone',input_limit=>1);
  perform public.live_activity_feed('everyone',input_before=>page->>'next_cursor',input_category_ids=>'{}'::text[],input_person_ids=>'{}'::text[]);

  for invalid_query in select value from jsonb_array_elements('[
    {"lat":0,"lon":0},{"lat":0,"radius":5000},{"lat":0,"lon":0,"radius":99},
    {"lat":0,"lon":0,"radius":25001},{"lat":91,"lon":0,"radius":5000},
    {"lat":0,"lon":181,"radius":5000},{"lat":"NaN","lon":0,"radius":5000}]'::jsonb) loop
    begin perform public.live_activity_feed('everyone',input_center_latitude=>(invalid_query->>'lat')::double precision,
      input_center_longitude=>(invalid_query->>'lon')::double precision,input_radius_meters=>(invalid_query->>'radius')::integer);
      raise exception 'invalid radius accepted'; exception when invalid_parameter_value then null; end;
  end loop;
  begin perform public.live_activity_feed('everyone',input_category_ids=>array[null::text]);
    raise exception 'null category accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.live_activity_feed('everyone',input_person_ids=>array['']);
    raise exception 'empty person accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.live_activity_feed('everyone',input_person_ids=>array_fill(actor,array[101]));
    raise exception 'unbounded person input accepted'; exception when invalid_parameter_value then null; end;

  reset role;
  update public.places set longitude=179.99 where id='63630000-0000-0000-0000-000000000064';
  set local role authenticated;
  if jsonb_array_length(public.live_activity_feed('everyone',input_center_latitude=>0,input_center_longitude=>-179.99,
    input_radius_meters=>5000,input_category_ids=>array['restaurants_food'],input_person_ids=>array[actor])->'activity')<>1
  then raise exception 'geodesic radius lost antimeridian result'; end if;
  reset role;
  insert into public.blocks(blocker_user_id,blocked_user_id) values(actor,viewer);
  set local role authenticated;
  if public.live_activity_feed('everyone',input_person_ids=>array[actor])->'activity'<>'[]'::jsonb
  then raise exception 'person filter bypassed current hard block'; end if;
  reset role;
end;
$refinements$;

rollback;
