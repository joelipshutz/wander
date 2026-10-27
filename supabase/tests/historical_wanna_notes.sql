begin;

-- Synthetic fixtures only. The hosted smoke runner rolls back this entire
-- test, including save RPC side effects and session claims.
do $test$
declare
  v_owner text := 'user_codex_historical_wanna_owner';
  v_viewer text := 'user_codex_historical_wanna_viewer';
  v_stranger text := 'user_codex_historical_wanna_stranger';
  v_parent uuid; v_place uuid; v_original uuid; v_visit uuid; v_event uuid;
  v_first_parent uuid; v_first_event uuid; v_date timestamptz;
  v_payload jsonb; v_saved jsonb; v_expected jsonb := '[]'; v_item jsonb;
  v_feeds jsonb; v_page jsonb; v_result jsonb; v_card jsonb;
  v_note text; v_repeat_note text; v_user text; v_proc record; i integer; v_surface integer;
begin
  if exists(select 1 from public.profiles where id=any(array[v_owner,v_viewer,v_stranger])
    or handle like 'codex_historical_wanna_%') then
    raise exception 'reserved historical Wanna fixture identity collision';
  end if;
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claim.canonical_user_id','',true);
  insert into public.profiles(id,handle,display_name,is_private_profile) values
    (v_owner,'codex_historical_wanna_owner','Wanna Owner',false),
    (v_viewer,'codex_historical_wanna_viewer','Wanna Viewer',false),
    (v_stranger,'codex_historical_wanna_stranger','Wanna Stranger',false);
  delete from public.follows where follower_user_id=any(array[v_owner,v_viewer,v_stranger])
    and source='signup_default';
  insert into public.follows(follower_user_id,followed_user_id,source) values(v_viewer,v_owner,'username');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_owner,'role','authenticated')::text,true);

  -- Blank/nonblank originals followed by check-ins, plus a current Wanna.
  for i in 1..3 loop
    -- Separate app requests normally end the transaction-local trigger flag.
    perform set_config('app.explicit_check_in','off',true);
    v_note:=case when i=1 then null else 'Wanna note '||i end;
    v_payload:=jsonb_build_object('canonical_name','Historical Wanna Regression '||i,
      'category','coffee','latitude',0,'longitude',0,'source_provider','codex_smoke',
      'source_provider_place_id','rec650-'||i);
    set local role authenticated;
    v_saved:=public.save_own_place(v_payload,jsonb_build_object('status','wanna_go',
      'visibility','followers','note',v_note,'source_type','manual'),'[]');
    v_parent:=(v_saved->>'user_place_id')::uuid;
    reset role;
    select place_id into strict v_place from public.user_places where id=v_parent;
    select id into strict v_original from public.feed_events
      where user_place_id=v_parent and event_type='place_want_to_go';
    if i=1 then v_first_parent:=v_parent; v_first_event:=v_original; end if;
    v_expected:=v_expected||jsonb_build_array(jsonb_build_object('id',v_original,
      'place_id',v_place,'note',v_note,'wanna',true));
    if i<3 then
      v_visit:=gen_random_uuid();
      set local role authenticated;
      perform public.save_own_check_in(v_payload,jsonb_build_object('id',v_parent,'status','been',
        'visibility','followers','note','Later check-in note','rating_score',4,'source_type','manual'),
        '[]',jsonb_build_object('id',v_visit,'visited_at',now(),'note','Later check-in note',
          'rating_score',4,'attribute_answers','[]'::jsonb));
      reset role;
      if not exists(select 1 from public.user_places where id=v_parent and historical_wanted_at is not null
        and historical_want_note is not distinct from v_note)
      then raise exception 'fixture did not preserve the original Wanna snapshot'; end if;
      select id into strict v_event from public.feed_events where visit_id=v_visit;
      v_expected:=v_expected||jsonb_build_array(jsonb_build_object('id',v_event,
        'place_id',v_place,'note','Later check-in note','wanna',false));
      v_event:=gen_random_uuid();
      -- Repeat content differs from both the historical and current notes.
      -- In particular, an explicit null must override a nonempty snapshot.
      v_repeat_note:=case when i=1 then 'Independent repeat Wanna' else null end;
      set local role authenticated;
      perform public.save_own_place_wanna(v_parent,jsonb_build_object('id',v_event,
        'occurred_at',now(),'visibility','followers','note',v_repeat_note,'attribute_answers','[]'::jsonb));
      reset role;
      v_expected:=v_expected||jsonb_build_array(jsonb_build_object('id',v_event,
        'place_id',v_place,'note',v_repeat_note,'wanna',true));
    end if;
  end loop;

  foreach v_user in array array[v_owner,v_viewer] loop
    perform set_config('request.jwt.claims',jsonb_build_object('sub',v_user,'role','authenticated')::text,true);
    set local role authenticated;
    v_feeds:=jsonb_build_array(public.activity_feed('everyone',null,50),public.live_activity_feed('everyone',input_limit=>50));
    if v_user=v_viewer then
      v_feeds:=v_feeds||jsonb_build_array(public.followed_feed(null,50));
    end if;
    for v_item in select value from jsonb_array_elements(v_expected) loop
      v_result:=public.activity_detail((v_item->>'id')::uuid);
      if v_result is null or v_result->>'note' is distinct from v_item->>'note'
        or v_result->'place'->>'note' is distinct from v_item->>'note'
      then raise exception 'activity detail borrowed another event note (wanna=%, blank=%)',v_item->>'wanna',v_item->>'note' is null; end if;
      if (v_item->>'wanna')::boolean and (v_result->>'rating' is not null or v_result->'place'->>'rating_score' is not null)
      then raise exception 'Wanna borrowed a check-in rating'; end if;
      v_surface:=0;
      for v_page in select value from jsonb_array_elements(v_feeds||jsonb_build_array(
        public.live_place_activity(array[(v_item->>'place_id')::uuid],null,50))) loop
        v_surface:=v_surface+1;
        select value into v_card from jsonb_array_elements(v_page->'activity') where value->>'id'=v_item->>'id';
        if v_card is null or v_card->>'note' is distinct from v_item->>'note'
          or v_card->'place'->>'note' is distinct from v_item->>'note'
        then raise exception 'Feed/Live note mismatch: surface=%, owner=%, wanna=%, missing=%, expected_blank=%',
          v_surface,v_user=v_owner,v_item->>'wanna',v_card is null,v_item->>'note' is null; end if;
      end loop;
    end loop;
    reset role;
  end loop;

  -- A missing snapshot on a Been parent cannot borrow its latest note.
  select historical_wanted_at into v_date from public.user_places where id=v_first_parent;
  update public.user_places set historical_wanted_at=null where id=v_first_parent;
  if app.feed_wanna_place_projection(v_first_parent,null,v_first_event)->>'note' is not null
  then raise exception 'missing historical snapshot borrowed current check-in'; end if;
  update public.user_places set historical_wanted_at=v_date where id=v_first_parent;
  if app.feed_wanna_place_projection(v_first_parent,null,gen_random_uuid()) is distinct from
    app.feed_place_projection(v_first_parent,null)
  then raise exception 'non-Wanna projection changed'; end if;
  update public.user_places set note='Edited later check-in summary' where id=v_first_parent;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_owner,'role','authenticated')::text,true);
  set local role authenticated;
  if public.activity_detail(v_first_event)->>'note' is not null
  then raise exception 'later summary edit changed blank Wanna'; end if;
  reset role;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_stranger,'role','authenticated')::text,true);
  set local role authenticated;
  begin
    perform public.activity_detail(v_first_event);
    raise exception 'stranger read historical Wanna';
  exception when raise_exception then
    if sqlerrm<>'activity_not_visible' then raise; end if;
  end;
  reset role;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_viewer,'role','authenticated')::text,true);
  insert into public.blocks(blocker_user_id,blocked_user_id) values(v_owner,v_viewer);
  set local role authenticated;
  begin
    perform public.activity_detail(v_first_event);
    raise exception 'blocked viewer read historical Wanna';
  exception when raise_exception then
    if sqlerrm<>'activity_not_visible' then raise; end if;
  end;
  reset role;
  delete from public.blocks where blocker_user_id=v_owner and blocked_user_id=v_viewer;
  update public.user_places set visibility='self' where id=v_first_parent;
  set local role authenticated;
  begin
    perform public.activity_detail(v_first_event);
    raise exception 'private Wanna leaked';
  exception when raise_exception then
    if sqlerrm<>'activity_not_visible' then raise; end if;
  end;
  reset role;
  perform set_config('request.jwt.claims','{}',true);
  set local role anon;
  begin
    perform public.activity_detail(v_first_event);
    raise exception 'anonymous activity read allowed';
  exception when insufficient_privilege then null;
  end;
  reset role;

  select * into strict v_proc from pg_proc where oid='app.feed_wanna_place_projection(uuid,uuid,uuid)'::regprocedure;
  if not v_proc.prosecdef or v_proc.provolatile<>'s' or v_proc.prorettype<>'jsonb'::regtype
    or not ('search_path=pg_catalog, public, app'=any(v_proc.proconfig))
    or has_function_privilege('authenticated',v_proc.oid,'execute')
    or has_function_privilege('anon',v_proc.oid,'execute')
    or exists(select 1 from aclexplode(coalesce(v_proc.proacl,acldefault('f',v_proc.proowner))) acl
      where acl.grantee=0 and acl.privilege_type='EXECUTE')
  then raise exception 'Wanna projection security contract changed'; end if;
end;
$test$;
select 'historical Wanna notes, public projections and privacy passed' as result;
rollback;
