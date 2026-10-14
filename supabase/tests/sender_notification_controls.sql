begin;
-- Reserved smoke identities; every fixture and queue entry is rolled back.
insert into public.profiles(id, handle, display_name) values
 ('user_codex_sender_owner', 'codexsenderowner', 'Sender'),
 ('user_codex_sender_follower', 'codexsenderfollower', 'Follower'),
 ('user_codex_sender_stranger', 'codexsenderstranger', 'Stranger');
insert into public.follows(follower_user_id, followed_user_id, source)
 values ('user_codex_sender_follower', 'user_codex_sender_owner', 'profile'),
 ('user_codex_sender_owner', 'user_codex_sender_follower', 'profile');
create temporary table sender_results(key text primary key, value jsonb) on commit drop;
grant all on sender_results to authenticated, service_role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_codex_sender_follower', true);
select public.update_notification_preferences('{"push_enabled":true,"followed_activity_enabled":true,"recommendations_enabled":true,"shared_lists_enabled":true,"shared_visits_enabled":true}');
select public.register_push_token(repeat('a', 64), 'sandbox', 'com.grayline.wander');
select set_config('request.jwt.claim.sub', 'user_codex_sender_owner', true);
select public.update_notification_preferences('{"push_enabled":true,"recommendations_enabled":true,"shared_visits_enabled":true,"followed_activity_enabled":true,"shared_lists_enabled":true}');

do $$
declare i integer; payload jsonb; saved jsonb; visit uuid; policy jsonb;
begin
 policy := '{"silent":false,"importID":"rec589-notify","importCommitID":"58900000-0000-4000-8000-000000000001"}';
 for i in 1..4 loop
   visit := gen_random_uuid();
   payload := jsonb_build_object(
     'input_place', jsonb_build_object('canonical_name', 'Sender Test ' || i, 'category', 'coffee',
       'latitude', 34.04 + i * 0.001, 'longitude', -118.24, 'source_provider', 'manual',
       'source_provider_place_id', 'codex-sender-place-' || i),
     'input_user_place', jsonb_build_object('status','been','visibility',case when i=4 then 'self' else 'followers' end,
       'source_type','manual','nearby_confirmed',false),
     'input_attributes', '[]'::jsonb,
     'input_visit', jsonb_build_object('id',visit,'visited_at',now(),'attribute_answers','[]'::jsonb));
   saved := public.save_own_check_in_with_sender_policy(payload, policy);
   -- Lost response/retry must keep one explicit visit and its policy.
   perform public.save_own_check_in_with_sender_policy(payload, policy);
   insert into sender_results values (i::text, saved);
 end loop;
end;
$$;
reset role;
do $$
begin
 if exists(select 1 from public.notification_events where actor_user_id='user_codex_sender_owner' and notification_type='followed_place_visit') then
   raise exception 'import per-item announcement escaped';
 end if;
 if (select count(*) from public.place_visits where sender_import_id='rec589-notify' and not backfilled_from_user_place) <> 4 then
   raise exception 'visit replay lost idempotency';
 end if;
 if (select count(*) from public.feed_events where visit_id in (select (value->>'visit_id')::uuid from sender_results)) <> 4 then
   raise exception 'silent imports lost Feed entries';
 end if;
end;
$$;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_codex_sender_owner', true);
select public.finalize_import_notification('rec589-notify','58900000-0000-4000-8000-000000000001',false,
 array(select (value->>'visit_id')::uuid from sender_results));
select public.finalize_import_notification('rec589-notify','58900000-0000-4000-8000-000000000001',false,
 array(select (value->>'visit_id')::uuid from sender_results));
reset role;
do $$
declare e public.notification_events;
begin
 select * into strict e from public.notification_events
   where actor_user_id='user_codex_sender_owner' and notification_type='followed_place_visit';
 if e.recipient_user_id <> 'user_codex_sender_follower' or e.body not like '% and 2 other places'
    or (e.data->>'place_count')::int <> 3 or e.body like '%Test 4%' then
   raise exception 'group copy/count included a private place or was not grouped';
 end if;
 -- Simulate external delivery having completed. The import ledger, not the
 -- queue's pending-only dedupe, must prevent a second event after sent.
 update public.notification_events set status='sent', delivered_at=now() where id=e.id;
end;
$$;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_codex_sender_owner', true);
select public.finalize_import_notification('rec589-notify','58900000-0000-4000-8000-000000000001',false,array[]::uuid[]);
select public.finalize_import_notification('rec589-notify','58900000-0000-4000-8000-000000000002',false,array[]::uuid[]);
-- A silent/no-check-in first selection also permanently consumes the import.
select public.finalize_import_notification('rec589-silent','58900000-0000-4000-8000-000000000003',true,array[]::uuid[]);
select public.finalize_import_notification('rec589-silent','58900000-0000-4000-8000-000000000004',false,array[]::uuid[]);
select public.finalize_import_notification('rec589-empty','58900000-0000-4000-8000-000000000005',false,array[]::uuid[]);
select set_config('request.jwt.claim.sub', 'user_codex_sender_stranger', true);
do $$
begin
 begin
   perform public.finalize_import_notification('rec589-forged','58900000-0000-4000-8000-000000000006',false,
      array(select (value->>'visit_id')::uuid from sender_results));
   raise exception 'forged import unexpectedly succeeded';
 exception when raise_exception then
   if sqlerrm <> 'import_visit_not_owned_or_not_synced' then raise; end if;
 end;
end;
$$;
reset role;
do $$
declare n text;
begin
 if (select count(*) from public.notification_events where actor_user_id='user_codex_sender_owner' and notification_type='followed_place_visit') <> 1 then
   raise exception 'sealed import reannounced';
 end if;
 if has_table_privilege('authenticated','app.import_notification_commits','select')
    or has_table_privilege('authenticated','app.import_notification_commits','insert') then
   raise exception 'private import ledger is exposed';
 end if;
 foreach n in array array['save_own_place','save_own_check_in','save_visible_place','add_place_list_item','accept_shared_visit'] loop
   if not exists(select 1 from pg_proc where oid=('public.'||n||'_with_sender_policy(jsonb,jsonb)')::regprocedure
       and prosecdef=(n='save_visible_place') and provolatile='v' and 'search_path=pg_catalog, public, app'=any(proconfig))
      or has_function_privilege('anon','public.'||n||'_with_sender_policy(jsonb,jsonb)','execute')
      or not has_function_privilege('authenticated','public.'||n||'_with_sender_policy(jsonb,jsonb)','execute') then
     raise exception 'wrapper security posture changed: %', n;
   end if;
 end loop;
 if not exists(select 1 from pg_proc where oid='public.finalize_import_notification(text,uuid,boolean,uuid[])'::regprocedure
     and prosecdef and provolatile='v' and 'search_path=pg_catalog, public, app'=any(proconfig)) then
   raise exception 'finalize security posture changed';
 end if;
 if has_function_privilege('authenticated','public.claim_pending_push_notifications(integer)','execute')
    or not has_function_privilege('service_role','public.claim_pending_push_notifications(integer)','execute') then
   raise exception 'worker grants changed';
 end if;
end;
$$;

-- Prioritize the locked fixture. No external delivery occurs and all claims
-- roll back. Never return queue payloads from this regression test.
create function pg_temp.assert_import_read(expected boolean, checkpoint text) returns void
language plpgsql security invoker as $$
begin
 if exists(select 1 from public.notification_events
   where data->>'sender_import_id'='rec589-notify') <> expected then
   raise exception 'group snapshot read failed at % (expected %)', checkpoint, expected;
 end if;
end;
$$;
do $$ begin
 if not exists(select 1 from pg_policy where polrelid='public.notification_events'::regclass
   and polname='import notification snapshots require current visibility' and not polpermissive) then
   raise exception 'group read policy must be restrictive';
 end if;
 if not exists(select 1 from pg_proc where oid='app.can_read_own_import_notification(uuid)'::regprocedure
   and prosecdef and provolatile='s' and 'search_path=pg_catalog, public, app'=any(proconfig))
   or has_function_privilege('anon','app.can_read_own_import_notification(uuid)','execute') then
   raise exception 'group read helper security posture changed';
 end if;
end; $$;
insert into sender_results values ('event', (select jsonb_build_object('id',id) from public.notification_events where data->>'sender_import_id'='rec589-notify'));
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_codex_sender_follower', true);
select pg_temp.assert_import_read(true, 'fresh snapshot');
select set_config('request.jwt.claim.sub', 'user_codex_sender_stranger', true);
select pg_temp.assert_import_read(false, 'stranger');
do $$ begin
 if app.can_read_own_import_notification((select (value->>'id')::uuid from sender_results where key='event'))
   or app.can_read_own_import_notification('58900000-0000-4000-8000-000000000099') then
   raise exception 'group helper leaked a foreign or nonexistent event';
 end if;
end; $$;
reset role;
-- A block, unfollow, or deleted visit invalidates a cached group immediately,
-- including a previously sent row. Restore only the reserved fixtures.
savepoint before_block;
insert into public.blocks(blocker_user_id,blocked_user_id)
 values('user_codex_sender_follower','user_codex_sender_owner');
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_codex_sender_follower', true);
select pg_temp.assert_import_read(false, 'block');
reset role;
rollback to savepoint before_block;
savepoint before_unfollow;
delete from public.follows where follower_user_id='user_codex_sender_follower' and followed_user_id='user_codex_sender_owner';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_codex_sender_follower', true);
select pg_temp.assert_import_read(false, 'unfollow');
reset role;
rollback to savepoint before_unfollow;
savepoint before_delete;
update public.place_visits set deleted_at=now()
 where id=(select (value->>'visit_id')::uuid from sender_results where key='2');
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_codex_sender_follower', true);
select pg_temp.assert_import_read(false, 'deleted visit');
reset role;
rollback to savepoint before_delete;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_codex_sender_follower', true);
select pg_temp.assert_import_read(true, 'restored visit');
reset role;
update public.notification_events set status='pending', delivered_at=null, not_before=now()-interval '100 years', priority=100
 where actor_user_id='user_codex_sender_owner' and notification_type='followed_place_visit';
update public.user_places set visibility='self'
 where id=(select (value->>'user_place_id')::uuid from sender_results where key='1');
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_codex_sender_follower', true);
select pg_temp.assert_import_read(false, 'partial revoke before claim');
set local role service_role;
insert into sender_results values ('claimed', public.claim_pending_push_notifications(1));
reset role;
do $$
declare e public.notification_events;
begin
 select * into strict e from public.notification_events
  where actor_user_id='user_codex_sender_owner' and notification_type='followed_place_visit';
 if e.body not like '% and 1 other place' or (e.data->>'place_count')::int <> 2 then
   raise exception 'claim did not remove newly private content';
 end if;
end;
$$;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_codex_sender_follower', true);
select pg_temp.assert_import_read(true, 'partial revoke after claim');
reset role;
do $$
declare e public.notification_events;
begin
 select * into strict e from public.notification_events
  where actor_user_id='user_codex_sender_owner' and notification_type='followed_place_visit';
 -- A second claim after all access is revoked must omit/cancel this event.
 update public.user_places set visibility='self' where user_id='user_codex_sender_owner';
 update public.notification_events set claim_expires_at=now()-interval '1 second' where id=e.id;
end;
$$;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_codex_sender_follower', true);
select pg_temp.assert_import_read(false, 'all revoked before claim');
set local role service_role;
insert into sender_results values ('revoked_claim', public.claim_pending_push_notifications(1));
reset role;
do $$
begin
 if not exists(select 1 from public.notification_events where actor_user_id='user_codex_sender_owner'
   and notification_type='followed_place_visit' and status='skipped'
   and skip_reason in ('activity_unavailable', 'source_not_visible')
   and claim_token is null and claim_expires_at is null) then
   raise exception 'inaccessible grouped event was not cancelled';
 end if;
 -- REC-590 can reject the source before REC-589's group renderer runs.
 -- Both paths must remove the claim and omit the event from worker output.
 if exists(select 1 from jsonb_array_elements((select value from sender_results where key='revoked_claim')) item
   where item->>'event_id'=(select value->>'id' from sender_results where key='event')) then
   raise exception 'inaccessible grouped event escaped in worker output';
 end if;
end;
$$;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_codex_sender_follower', true);
select pg_temp.assert_import_read(false, 'all revoked after claim');
reset role;
-- Each shipping iOS wrapper is exercised as authenticated, including ordinary
-- non-import saves and direct invitations that must not be silenced.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_codex_sender_owner', true);
do $$
declare payload jsonb; saved jsonb; i integer; list_id uuid; item_id uuid; invite record;
begin
 for i in 5..7 loop
   payload := jsonb_build_object(
     'input_place',jsonb_build_object('canonical_name','Sender Test '||i,'category','coffee','latitude',34.08+i*0.001,'longitude',-118.24,
       'source_provider','manual','source_provider_place_id','codex-sender-place-'||i),
     'input_user_place',jsonb_build_object('status','been','visibility','followers','source_type','manual','nearby_confirmed',false),
     'input_attributes','[]'::jsonb,'input_visit',jsonb_build_object('id',gen_random_uuid(),'visited_at',now(),'attribute_answers','[]'::jsonb));
   saved := public.save_own_check_in_with_sender_policy(payload,jsonb_build_object('silent',i<>6));
   insert into sender_results values(i::text,saved);
 end loop;
 -- save_own_place preserves Wanna visibility with a captured silent intent.
 payload := jsonb_build_object(
   'input_place',jsonb_build_object('canonical_name','Sender Wanna','category','coffee','latitude',34.09,'longitude',-118.24,
     'source_provider','manual','source_provider_place_id','codex-sender-wanna'),
   'input_user_place','{"status":"wanna_go","visibility":"followers","source_type":"manual","nearby_confirmed":false}'::jsonb,
   'input_attributes','[]'::jsonb);
 insert into sender_results values('wanna',public.save_own_place_with_sender_policy(payload,'{"silent":true}'));
 list_id := public.upsert_place_list('{"name":"Sender test list","visibility":"followers"}');
 perform public.set_place_list_collaborators(list_id,array['user_codex_sender_follower']);
 for i in 5..6 loop
   select value into saved from sender_results where key=i::text;
   item_id := public.add_place_list_item_with_sender_policy(jsonb_build_object('input_list_id',list_id,
     'input_place_id',saved->>'place_id','input_owner_user_place_id',saved->>'user_place_id'),jsonb_build_object('silent',i=5));
   if item_id is null then raise exception 'list wrapper did not save'; end if;
 end loop;
 for invite in select * from public.create_shared_visit_invites(
   (select (value->>'visit_id')::uuid from sender_results where key='5'), array['user_codex_sender_follower']) loop
   insert into sender_results values('invite',jsonb_build_object('participant_id',invite.participant_id,'generation',invite.invitation_generation));
 end loop;
end;
$$;
reset role;
do $$
begin
 if (select count(*) from public.notification_events where actor_user_id='user_codex_sender_owner' and notification_type='followed_place_visit' and data->>'sender_import_id' is null) <> 1 then
   raise exception 'ordinary silent/notify choice did not control check-in producer';
 end if;
 if (select count(*) from public.notification_events where actor_user_id='user_codex_sender_owner' and notification_type='list_place_added') <> 1 then
   raise exception 'silent/notify list wrapper did not control list producer';
 end if;
 if not exists(select 1 from public.notification_events where actor_user_id='user_codex_sender_owner' and notification_type='shared_visit') then
   raise exception 'silent check-in incorrectly suppressed explicit invitation';
 end if;
end;
$$;
update public.user_places set note='Private source fixture', rating_score=4
 where id=(select (value->>'user_place_id')::uuid from sender_results where key='6');
insert into public.place_attributes(user_place_id,question_key,value_type,value)
 values((select (value->>'user_place_id')::uuid from sender_results where key='6'),
        'sender_private_fixture','text','"Private answer fixture"'::jsonb);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_codex_sender_follower', true);
do $$
declare i integer; saved jsonb; accepted jsonb; invite jsonb; context record;
begin
 for i in 6..7 loop
   select value into saved from sender_results where key=i::text;
   perform public.save_visible_place_with_sender_policy(jsonb_build_object('input_place_id',saved->>'place_id',
     'input_source_user_place_id',saved->>'user_place_id'),jsonb_build_object('silent',i=6));
 end loop;
 select value into invite from sender_results where key='invite';
 select * into context from public.get_shared_visit_context((invite->>'participant_id')::uuid,(invite->>'generation')::integer);
 accepted := public.accept_shared_visit_with_sender_policy(jsonb_build_object(
   'input_participant_id',invite->>'participant_id','input_generation',(invite->>'generation')::integer,
   'input_snapshot_revision',context.snapshot_revision,'input_operation_id',gen_random_uuid(),
   'input_user_place_id',gen_random_uuid(),'input_visit_id',gen_random_uuid(),
   'input_user_place','{"visibility":"followers"}'::jsonb,
   'input_visit',jsonb_build_object('visited_at',now(),'attribute_answers','[]'::jsonb),
   'input_attributes','[]'::jsonb,'input_selected_photo_ids','[]'::jsonb),'{"silent":true}');
 if accepted->>'status' <> 'accepted' then raise exception 'silent acceptance failed'; end if;
 insert into sender_results values('accepted',accepted);
end;
$$;
reset role;
do $$
begin
 if (select count(*) from public.notification_events where actor_user_id='user_codex_sender_follower' and notification_type='place_saved_from_your_map') <> 1 then
   raise exception 'silent source attribution emitted an alert or standard lost one';
 end if;
 if not exists(select 1 from public.place_visits where id=(select (value->>'visit_id')::uuid from sender_results where key='accepted') and notification_silent) then
   raise exception 'accepted check-in lost silent policy';
 end if;
end;
$$;

-- Social saves must honor a nonprivate account's Self default.
update public.profiles set is_private_profile=false, default_visibility='self'
 where id='user_codex_sender_follower';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_codex_sender_follower', true);
do $$
declare source jsonb; saved jsonb;
begin
 select value into source from sender_results where key='wanna';
 saved := public.save_visible_place_with_sender_policy(jsonb_build_object('input_place_id',source->>'place_id',
   'input_source_user_place_id',source->>'user_place_id'),'{"silent":true}');
 insert into sender_results values('private-default',saved);
 select value into source from sender_results where key='1';
 begin
   perform public.save_visible_place_with_sender_policy(jsonb_build_object('input_place_id',source->>'place_id',
     'input_source_user_place_id',source->>'user_place_id'),'{"silent":true}');
   raise exception 'private source was saved';
 exception when raise_exception then
   if sqlerrm <> 'source_not_visible' then raise; end if;
 end;
end;
$$;
select set_config('request.jwt.claim.sub', 'user_codex_sender_stranger', true);
do $$
declare source jsonb;
begin
 select value into source from sender_results where key='6';
 begin
   perform public.save_visible_place_with_sender_policy(jsonb_build_object('input_place_id',source->>'place_id',
     'input_source_user_place_id',source->>'user_place_id'),'{"silent":false}');
   raise exception 'stranger saved follower-only content';
 exception when raise_exception then
   if sqlerrm <> 'source_not_visible' then raise; end if;
 end;
end;
$$;
reset role;
do $$
begin
 if not exists(select 1 from public.user_places where id=(select (value->>'user_place_id')::uuid from sender_results where key='private-default') and visibility='self') then
   raise exception 'social save exposed Self-default content';
 end if;
 if exists(select 1 from public.user_places where user_id='user_codex_sender_follower'
   and source_type='social_save' and (note='Private source fixture' or rating_score=4)) then
   raise exception 'social save copied source note or rating';
 end if;
 if exists(select 1 from public.place_attributes a join public.user_places up on up.id=a.user_place_id
   where up.user_id='user_codex_sender_follower' and up.source_type='social_save') then
   raise exception 'social save copied private source attributes';
 end if;
end;
$$;

select 'ok - sender import grouping, retries, visibility, and grants' as result;
rollback;
