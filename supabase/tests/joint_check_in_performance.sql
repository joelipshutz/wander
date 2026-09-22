-- Rollback-only synthetic load check. Run after all six v2 migration previews.
-- This reports server execution/payload sizes, not mobile network/frame times.
begin;
set local statement_timeout = '90s';
insert into public.profiles(id,handle,display_name)
select 'joint_perf_'||n,'jointperf'||n,'Fictional Person '||n from generate_series(0,10) n;
delete from public.follows where follower_user_id like 'joint_perf_%';
insert into public.follows(follower_user_id,followed_user_id,source)
select 'joint_perf_0','joint_perf_'||n,'profile' from generate_series(1,9) n
union all select 'joint_perf_'||n,'joint_perf_0','profile' from generate_series(1,9) n
union all select 'joint_perf_10','joint_perf_'||n,'profile' from generate_series(0,9) n;
update public.feature_flags set enabled=true where key='joint_check_ins_v2' and user_id is null;
create temporary table joint_perf_samples(iteration integer,elapsed_ms numeric,payload_bytes integer,cards integer,contributors integer,next_cursor text);
grant all on joint_perf_samples to authenticated;
do $$declare result jsonb; member record; target_group_id uuid; venue_id uuid; parent_id uuid; i integer;
begin
 for i in 1..25 loop
  perform set_config('request.jwt.claim.sub','joint_perf_0',true);
  result:=public.save_joint_check_in(
   '{"canonical_name":"Fictional Performance Cafe","category":"coffee_tea_sweets","latitude":34.05,"longitude":-118.25,"source_provider":"codex_joint_perf","source_provider_place_id":"joint-perf-cafe"}',
   '{"status":"been","visibility":"followers","source_type":"manual"}','[]',
   jsonb_build_object('id',gen_random_uuid(),'visited_at',now()-make_interval(mins=>i),'note',repeat('Fictional note. ',40),'rating_score',4.5),
   null,array(select 'joint_perf_'||n from generate_series(1,9) n),gen_random_uuid(),1);
  target_group_id:=(result->>'group_id')::uuid;venue_id:=(result->>'place_id')::uuid;parent_id:=(result->>'user_place_id')::uuid;
  for member in select * from public.shared_visit_participants where shared_visit_participants.group_id=target_group_id and status='pending' loop
   perform set_config('request.jwt.claim.sub',member.user_id,true);
   perform public.accept_joint_check_in(member.id,1,1,gen_random_uuid(),1,gen_random_uuid(),gen_random_uuid(),
     '{"visibility":"followers"}',jsonb_build_object('note',repeat('Fictional contribution. ',30),'rating_score',5));
  end loop;
 end loop;
 -- Older unjoined events stress eligibility work without adding private output.
 insert into public.feed_events(actor_user_id,event_type,user_place_id,place_id,occurred_at)
 select 'joint_perf_0','place_saved',parent_id,venue_id,now()-interval '2 days'-make_interval(secs=>n)
 from generate_series(1,2000) n;
 if (select count(*) from public.shared_visit_groups where owner_user_id='joint_perf_0')<>25
  or (select count(*) from public.place_visits v join public.user_places p on p.id=v.user_place_id where p.user_id like 'joint_perf_%' and v.deleted_at is null and not v.backfilled_from_user_place)<>250 then
  raise exception 'performance fixture failed';
 end if;
 perform set_config('request.jwt.claim.sub','joint_perf_10',true);
end$$;
set local role authenticated;
do $$declare started timestamptz; payload jsonb; n integer; people integer; seen uuid[]:='{}'; page_ids uuid[]; cursor_value text;
begin
 for n in 0..10 loop
  started:=clock_timestamp();payload:=public.followed_feed_v2(false,null,25);
  select sum(jsonb_array_length(value->'joint_check_in'->'contributions')) into people from jsonb_array_elements(payload->'activity');
  insert into joint_perf_samples values(n,extract(epoch from(clock_timestamp()-started))*1000,octet_length(payload::text),jsonb_array_length(payload->'activity'),people,payload->>'next_cursor');
  if people<>250 or jsonb_array_length(payload->'activity')<>25 then raise exception 'performance page omitted or duplicated a group';end if;
 end loop;
 -- Stable keyset paging across canonical and personal event candidates.
 for n in 1..5 loop
  payload:=public.followed_feed_v2(false,cursor_value,5);
  select array_agg((value->>'id')::uuid) into page_ids from jsonb_array_elements(payload->'activity');
  if page_ids && seen or cardinality(page_ids)<>5 then raise exception 'duplicate or missing canonical page';end if;
  seen:=seen||page_ids;cursor_value:=payload->>'next_cursor';
 end loop;
 if cardinality(seen)<>25 then raise exception 'wrong canonical page count';end if;
end$$;
reset role;
select jsonb_build_object('synthetic_groups',25,'accepted_contributors',250,'background_events',2000,
 'measured_samples',count(*),'p50_ms',percentile_cont(0.5) within group(order by elapsed_ms),
 'p95_ms',percentile_cont(0.95) within group(order by elapsed_ms),'max_ms',max(elapsed_ms),
 'max_payload_bytes',max(payload_bytes),'page_cards',max(cards),'page_contributors',max(contributors),
 'five_page_deduplication','passed') as result from joint_perf_samples where iteration>0;
rollback;
