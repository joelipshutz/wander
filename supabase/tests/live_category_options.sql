begin;

do $test$
declare
  viewer text := 'user_codex_rec671_viewer'; actor text := 'user_codex_rec671_actor';
  stranger text := 'user_codex_rec671_stranger'; blocked text := 'user_codex_rec671_blocked';
  options jsonb := '{"restaurants_food":["mexican","italian"],"outdoors_nature":["park"]}';
  page jsonb; cursor text; first_cursor text; row jsonb; ids uuid[] := '{}'; proc record;
begin
  for proc in select * from pg_proc where oid in (
    'public.live_activity_feed_category_options(text,timestamptz,timestamptz,text,jsonb,text,integer,double precision,double precision,integer,text[],text[],jsonb)'::regprocedure,
    'app.live_activity_feed_category_options(text,timestamptz,timestamptz,text,jsonb,text,integer,double precision,double precision,integer,text[],text[],jsonb)'::regprocedure)
  loop
    if not proc.prosecdef or proc.provolatile<>'s' or proc.prorettype<>'jsonb'::regtype
      or not ('search_path=pg_catalog, public, app, extensions'=any(proc.proconfig))
      or has_function_privilege('anon',proc.oid,'execute')
      or exists(select 1 from aclexplode(coalesce(proc.proacl,acldefault('f',proc.proowner))) where grantee=0 and privilege_type='EXECUTE')
    then raise exception 'Category-options security posture changed'; end if;
  end loop;
  if not has_function_privilege('authenticated','public.live_activity_feed_category_options(text,timestamptz,timestamptz,text,jsonb,text,integer,double precision,double precision,integer,text[],text[],jsonb)','execute')
    or has_function_privilege('authenticated','app.live_activity_feed_category_options(text,timestamptz,timestamptz,text,jsonb,text,integer,double precision,double precision,integer,text[],text[],jsonb)','execute')
  then raise exception 'Category-options grants changed'; end if;

  insert into public.profiles(id,handle,display_name,is_private_profile) values
    (viewer,'codex_rec671_viewer','Filter Viewer',false),(actor,'codex_rec671_actor','Filter Actor',false),
    (stranger,'codex_rec671_stranger','Filter Stranger',false),(blocked,'codex_rec671_blocked','Filter Blocked',false);
  delete from public.follows where follower_user_id in(viewer,actor,stranger,blocked) and source='signup_default';
  insert into public.follows(follower_user_id,followed_user_id,source) values
    (viewer,actor,'username'),(actor,viewer,'username'),(viewer,blocked,'username');
  insert into public.blocks(blocker_user_id,blocked_user_id) values(blocked,viewer);
  insert into public.places(id,canonical_name,category,primary_category,subcategory,provider_food_type,
    latitude,longitude,source_provider,source_provider_place_id)
  select ('67100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'Filter fixture '||n,
    case when n in(63,64) then 'outdoors_nature' when n=69 then 'coffee_tea_sweets' else 'restaurants_food' end,
    case when n in(63,64) then 'outdoors_nature' when n=69 then 'coffee_tea_sweets' else 'restaurants_food' end,
    case n when 63 then 'Park' when 64 then 'Beach' when 69 then 'Cafe' else 'Restaurant' end,
    case when n<=60 or n=68 then 'French' when n=62 then 'Mexican' else 'Italian' end,
    0,0,'manual','rec671-'||n from generate_series(1,70) n;
  insert into public.user_places(id,user_id,place_id,status,visibility,source_type,category_override,category_override_source)
  select ('67110000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
    case when n=65 then stranger when n=70 then blocked else actor end,
    ('67100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'been',
    case when n=66 then 'self' else 'followers' end,'manual',
    case when n=67 then 'coffee_tea_sweets' end,case when n=67 then 'user' end
  from generate_series(1,70) n;
  insert into public.place_taxonomy_snapshots(user_id,place_id,primary_category,subcategory,food_type,captured_for)
    values(viewer,'67100000-0000-0000-0000-000000000068','restaurants_food','Restaurant','Italian','backfill');
  delete from public.feed_events where actor_user_id in(viewer,actor,stranger,blocked);
  insert into public.feed_events(id,actor_user_id,event_type,user_place_id,place_id,occurred_at)
  select ('67120000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
    case when n=65 then stranger when n=70 then blocked else actor end,'place_been',
    ('67110000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
    ('67100000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
    case when n<=60 then now()-interval '1 hour' else now()-interval '2 days' end
  from generate_series(1,70) n;

  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claim.canonical_user_id','',true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',viewer,'role','authenticated')::text,true);
  set local role authenticated;
  -- Sixty newer French events cannot consume the child-filter page limit.
  page:=public.live_activity_feed_category_options('everyone',input_limit=>2,input_category_options=>options);
  first_cursor:=page->>'next_cursor';
  if jsonb_array_length(page->'activity')<>2 or first_cursor is null then raise exception 'child options filtered after limit'; end if;
  loop
    for row in select value from jsonb_array_elements(page->'activity') loop
      if (row->>'id')::uuid=any(ids) then raise exception 'duplicate child-filter page'; end if;
      ids:=array_append(ids,(row->>'id')::uuid);
      if not exists(select 1 from jsonb_array_elements(row->'place'->'attributes') a
        where a->>'question_key' in ('__viewer_taxonomy_subcategory','__viewer_taxonomy_food_type') and a->>'value' in ('Park','Italian','Mexican'))
      then raise exception 'viewer child taxonomy missing from projection'; end if;
    end loop;
    cursor:=page->>'next_cursor'; exit when cursor is null;
    if cardinality(ids)>10 then raise exception 'unbounded child pagination'; end if;
    page:=public.live_activity_feed_category_options('everyone',input_limit=>2,input_before=>cursor,
      input_category_options=>'{"outdoors_nature":["Park"],"restaurants_food":["Italian","Mexican","Italian"]}');
  end loop;
  if cardinality(ids)<>5 then raise exception 'child filters lost viewer matches or widened privacy: %',cardinality(ids); end if;
  if not ('67120000-0000-0000-0000-000000000067'::uuid=any(ids))
    or not ('67120000-0000-0000-0000-000000000068'::uuid=any(ids)) then raise exception 'actor override or global cuisine overrode viewer taxonomy'; end if;
  page:=public.live_activity_feed_category_options('everyone',input_limit=>50,
    input_category_ids=>array['coffee_tea_sweets'],input_category_options=>'{"restaurants_food":["italian"]}');
  if jsonb_array_length(page->'activity')<>4 then raise exception 'parent and child OR composition failed'; end if;
  page:=public.live_activity_feed_category_options('everyone',input_category_options=>'{"outdoors_nature":["park","beach"]}');
  if jsonb_array_length(page->'activity')<>2 then raise exception 'multiple subcategories failed'; end if;
  if public.live_activity_feed_category_options('everyone',input_person_ids=>array[stranger],input_category_options=>options)->'activity'<>'[]'::jsonb
  then raise exception 'child filter widened stranger access'; end if;
  if public.live_activity_feed_category_options('everyone',input_category_options=>'{"coffee_tea_sweets":["italian"]}')->'activity'<>'[]'::jsonb
  then raise exception 'child choice crossed primary categories'; end if;
  begin
    perform public.live_activity_feed_category_options('everyone',input_before=>first_cursor,input_category_options=>'{"restaurants_food":["french"]}');
    raise exception 'cross-child cursor accepted';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.live_activity_feed_category_options('everyone',input_category_options=>'{"restaurants_food":[]}');
    raise exception 'empty child group accepted';
  exception when invalid_parameter_value then null; end;
  perform set_config('request.jwt.claims','{"role":"authenticated"}',true);
  if public.live_activity_feed_category_options('everyone',input_category_options=>options)->'activity'<>'[]'::jsonb
  then raise exception 'missing viewer received activity'; end if;
  reset role;
  set local role anon;
  begin
    perform public.live_activity_feed_category_options('everyone',input_category_options=>options);
    raise exception 'anonymous caller reached category endpoint';
  exception when insufficient_privilege then null; end;
  reset role;
end;
$test$;

rollback;
