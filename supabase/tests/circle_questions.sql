begin;
-- Reserved fixtures. No production rows are changed and the transaction rolls back.
do $$ begin
 if exists(select 1 from public.profiles where id like 'user_codex_circle_%') then raise exception 'circle fixtures already exist'; end if;
end $$;
insert into public.profiles(id,handle,display_name,home_area) values
 ('user_codex_circle_owner','codex_circle_owner','Question owner','Santa Monica'),
 ('user_codex_circle_tag','codex_circle_tag','Tagged friend','Santa Monica'),
 ('user_codex_circle_follower','codex_circle_follower','Other follower','Los Angeles'),
 ('user_codex_circle_stranger','codex_circle_stranger','Stranger','London');
insert into public.follows(follower_user_id,followed_user_id,source) values
 ('user_codex_circle_tag','user_codex_circle_owner','username'),
 ('user_codex_circle_owner','user_codex_circle_tag','username'),
 ('user_codex_circle_follower','user_codex_circle_owner','username');
select app.ensure_notification_preferences('user_codex_circle_tag');
update public.notification_preferences set push_enabled=true,recommendations_enabled=true where user_id='user_codex_circle_tag';
create temp table circle_test(draft jsonb, normal_id uuid, stealth_id uuid);
grant all on circle_test to authenticated;
insert into circle_test values ('{"id":"eeecc001-0000-4000-8000-000000000001","categories":[],"subcategories":[],"area":{"name":"Santa Monica","detail":"California, US","latitude":34.01,"longitude":-118.49,"city":"Santa Monica"},"note":"A quiet patio","audience":"people","recipientIDs":["user_codex_circle_tag"],"stealth":false,"days":7}',
 'eeecc001-0000-4000-8000-000000000001','eeecc001-0000-4000-8000-000000000002');
set local role authenticated;
select set_config('request.jwt.claim.sub','user_codex_circle_owner',true);
select public.circle_question_publish(draft) is not null as owner_created from circle_test;
select public.circle_question_publish(draft) is not null as retry_recovered from circle_test;
do $$ begin
 begin perform public.circle_question_publish((select draft from circle_test)||'{"note":"Changed after an ambiguous retry"}'::jsonb); raise exception 'changed retry was accepted';
 exception when raise_exception then if sqlerrm<>'idempotency_conflict' then raise; end if; end;
 begin perform public.circle_question_publish((select draft from circle_test)||'{"recipientIDs":["user_codex_circle_follower"]}'::jsonb); raise exception 'changed tags were accepted';
 exception when raise_exception then if sqlerrm<>'idempotency_conflict' then raise; end if; end;
end $$;
select public.circle_question_publish(draft||jsonb_build_object('id',stealth_id,'stealth',true)) is not null as stealth_created from circle_test;
select set_config('request.jwt.claim.sub','user_codex_circle_follower',true);
do $$ begin
 if public.circle_question((select normal_id from circle_test)) is null then raise exception 'follower denied'; end if;
 begin perform public.circle_question((select stealth_id from circle_test)); raise exception 'stealth leaked';
 exception when raise_exception then if sqlerrm<>'question_unavailable' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','user_codex_circle_tag',true);
do $$ declare q jsonb; begin
 q:=public.circle_question((select stealth_id from circle_test));
 if q is null then raise exception 'tagged recipient denied'; end if;
 if jsonb_array_length(public.circle_question_inbox())<>2 then raise exception 'inbox missing tags'; end if;
 perform public.circle_question_like((select stealth_id from circle_test),true);
 q:=public.circle_question_like((select stealth_id from circle_test),true);
 if (q->>'likes')::integer<>1 then raise exception 'like retry duplicated'; end if;
 perform public.circle_question_reply((select stealth_id from circle_test),'eeecc001-0000-4000-8000-000000000003','[{"id":"place1","name":"Cafe","detail":"Main St","latitude":34,"longitude":-118,"note":"Try the patio"}]','A couple favorites');
 q:=public.circle_question_reply((select stealth_id from circle_test),'eeecc001-0000-4000-8000-000000000003','[{"id":"place1","name":"Cafe","detail":"Main St","latitude":34,"longitude":-118,"note":"Try the patio"}]','A couple favorites');
 if jsonb_array_length(q->'replies')<>1 then raise exception 'reply retry duplicated'; end if;
 perform public.circle_question_read((select stealth_id from circle_test));
end $$;
select set_config('request.jwt.claim.sub','user_codex_circle_stranger',true);
do $$ begin
 if jsonb_array_length(public.circle_questions())<>0 then raise exception 'stranger feed leak'; end if;
 begin perform public.circle_question_reply((select stealth_id from circle_test),gen_random_uuid(),'[]','unauthorized'); raise exception 'unauthorized reply allowed';
 exception when raise_exception then if sqlerrm<>'question_unavailable' then raise; end if; end;
end $$;
reset role;
do $$ declare name text; begin
 if (select count(*) from public.circle_questions where author_id='user_codex_circle_owner')<>2 then raise exception 'publish retry duplicated'; end if;
 if (select count(*) from public.notification_events where actor_user_id='user_codex_circle_owner' and notification_type='circle_question_tagged')<>2 then raise exception 'tag push not queued once'; end if;
 if not app.private_message_context_allowed('user_codex_circle_tag','user_codex_circle_owner','question',(select stealth_id from circle_test)) then raise exception 'question context rejected'; end if;
 if app.private_message_context_allowed('user_codex_circle_follower','user_codex_circle_owner','question',(select stealth_id from circle_test)) then raise exception 'private reply context leaked'; end if;
 foreach name in array array['circle_questions','circle_question_tags','circle_question_replies','circle_question_likes'] loop
  if not (select relrowsecurity from pg_class where oid=('public.'||name)::regclass) or has_table_privilege('authenticated','public.'||name,'select') then raise exception 'table security drift %',name; end if;
 end loop;
 if has_function_privilege('anon','public.circle_questions()','execute') or has_function_privilege('authenticated','app.circle_question_json(uuid,text)','execute') then raise exception 'function grant leak'; end if;
 if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname like 'circle_question%' and (not prosecdef or not ('search_path=pg_catalog, public, app'=any(proconfig)))) then raise exception 'definer posture drift'; end if;
end $$;
insert into public.blocks(blocker_user_id,blocked_user_id) values('user_codex_circle_owner','user_codex_circle_tag');
do $$ begin
 if app.can_read_circle_question('user_codex_circle_tag',(select stealth_id from circle_test)) then raise exception 'block did not revoke'; end if;
 if exists(select 1 from public.notification_events e where actor_user_id='user_codex_circle_owner' and app.notification_source_readable(e)) then raise exception 'blocked push remains readable'; end if;
end $$;
-- Expiration affects only pins. The ordinary follower still reads the conversation.
update public.circle_questions set created_at=now()-interval '8 days',expires_at=now()-interval '1 day' where id=(select normal_id from circle_test);
set local role authenticated;
select set_config('request.jwt.claim.sub','user_codex_circle_follower',true);
do $$ begin if public.circle_question((select normal_id from circle_test)) is null then raise exception 'expiration removed feed conversation'; end if; end $$;
reset role;
select 'Circle Question visibility, interactions, idempotency, notification authorization, expiration and grants passed' as result;
rollback;
