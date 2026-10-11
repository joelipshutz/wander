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
    'public.live_activity_feed(text,timestamptz,timestamptz,text,jsonb,text,integer)'::regprocedure,
    'app.live_activity_feed(text,timestamptz,timestamptz,text,jsonb,text,integer)'::regprocedure)
  loop
    if not proc.prosecdef or proc.provolatile<>'s' or proc.prorettype<>'jsonb'::regtype
      or not ('search_path=pg_catalog, public, app, extensions'=any(proc.proconfig))
      or has_function_privilege('anon',proc.oid,'execute')
      or exists(select 1 from aclexplode(coalesce(proc.proacl,acldefault('f',proc.proowner))) where grantee=0 and privilege_type='EXECUTE')
    then raise exception 'Live function security posture changed'; end if;
  end loop;
  if not has_function_privilege('authenticated','public.live_activity_feed(text,timestamptz,timestamptz,text,jsonb,text,integer)','execute')
    or has_function_privilege('authenticated','app.live_activity_feed(text,timestamptz,timestamptz,text,jsonb,text,integer)','execute')
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
  if page->'activity' is distinct from public.activity_feed('everyone',null,25)->'activity'
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

rollback;
