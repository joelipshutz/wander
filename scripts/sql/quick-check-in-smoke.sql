-- Reserved synthetic identities; called inside the shared smoke transaction.
insert into public.profiles(id,handle,display_name,default_visibility,is_private_profile,deleted_at)
values ('user_codex_supabase_smoke','codex_smoke','Codex Smoke Test','followers',false,null),
       ('user_codex_supabase_smoke_stranger','codex_smoke_stranger','Codex Smoke Stranger','followers',false,null)
on conflict(id) do update set deleted_at=null;

set local role authenticated;
select set_config('request.jwt.claim.sub','user_codex_supabase_smoke',true);
select set_config('request.jwt.claim.role','authenticated',true);
select public.update_notification_preferences('{"push_enabled":true,"check_in_reminders_enabled":true}');
create temporary table quick_check_in_smoke_ids(parent_id uuid,visit_id uuid,second_visit_id uuid);
do $test$
declare
  first_id uuid := gen_random_uuid();
  second_id uuid := gen_random_uuid();
  saved jsonb;
  parent_id uuid;
  place jsonb := '{"canonical_name":"Quick capture fixture","category":"coffee_tea_sweets","primary_category":"coffee_tea_sweets","subcategory":"Coffee shop","category_source":"user","latitude":34,"longitude":-118,"source_provider":"codex_smoke","source_provider_place_id":"quick-capture-contract","confidence":1}';
  visit jsonb;
begin
  visit := jsonb_build_object('id',first_id,'visited_at',now()-interval '1 day','rating_score',null,
    'attribute_answers','[]'::jsonb,'details_pending',true,'reminder_timezone','America/New_York');
  saved := public.save_own_check_in(place,'{"status":"been","visibility":"followers","source_type":"manual"}', '[]',visit,null);
  parent_id := (saved->>'user_place_id')::uuid;
  if saved->>'rating_score' is not null or saved->>'details_pending' <> 'true'
    or (saved->>'visit_id')::uuid <> first_id then raise exception 'Quick capture lost null rating/identity/pending state'; end if;
  -- Retry uses the same identity, including an earlier visit date.
  perform public.save_own_check_in(place,jsonb_build_object('id',parent_id,'status','been','visibility','followers','source_type','manual'), '[]',visit,null);
  if (select count(*) from public.place_visits where user_place_id=parent_id and deleted_at is null) <> 1
    then raise exception 'Retry created a second visit'; end if;
  saved := public.save_own_check_in(place,jsonb_build_object('id',parent_id,'status','been','visibility','followers','source_type','manual'), '[]',
    jsonb_build_object('id',second_id,'visited_at',now(),'rating_score',null,'attribute_answers','[]'::jsonb,'details_pending',true),null);
  if saved->>'rating_score' is not null then raise exception 'Repeat capture inherited a rating'; end if;
  if not exists(select 1 from jsonb_array_elements(public.current_user_calendar_snapshot()->'visits') row
    where row->>'id'=first_id::text and row->>'details_pending'='true' and row->>'created_at' is not null)
    then raise exception 'Cold owner snapshot lost invitation state or capture time'; end if;
  if not exists(select 1 from pg_proc where oid='public.current_user_calendar_snapshot()'::regprocedure
    and not prosecdef and provolatile='s' and 'search_path=public, app'=any(proconfig))
    or has_function_privilege('anon','public.current_user_calendar_snapshot()','execute')
    or not has_function_privilege('authenticated','public.current_user_calendar_snapshot()','execute')
    then raise exception 'Owner calendar snapshot security posture changed'; end if;
  insert into quick_check_in_smoke_ids values(parent_id,first_id,second_id);
end;
$test$;
reset role;

do $test$
declare ids record; first_event public.notification_events; second_event public.notification_events; zone text; token uuid; authorized jsonb;
begin
  select * into ids from quick_check_in_smoke_ids;
  if (select count(*) from public.notification_events where notification_type='check_in_reminder'
    and data->>'visit_id'=ids.visit_id::text) <> 1 then raise exception 'Reminder retry dedupe failed'; end if;
  select * into first_event from public.notification_events where notification_type='check_in_reminder' and data->>'visit_id'=ids.visit_id::text;
  select * into second_event from public.notification_events where notification_type='check_in_reminder' and data->>'visit_id'=ids.second_visit_id::text;
  if first_event.not_before < now()+interval '3 hours' or first_event.latest_at <> first_event.created_at+interval '48 hours'
    or extract(hour from first_event.not_before at time zone first_event.recipient_timezone) not between 9 and 21
    then raise exception 'Reminder delay/quiet hours/expiry contract failed'; end if;
  if not app.notification_source_readable(first_event) then raise exception 'Owned pending visit should be eligible'; end if;
  -- Fix the tested local hour without depending on when CI runs.
  select name into zone from pg_timezone_names where extract(hour from now() at time zone name)=12 limit 1;
  first_event.recipient_timezone := zone;
  second_event.recipient_timezone := zone;
  if not app.reserve_check_in_reminder_day(first_event) or not app.reserve_check_in_reminder_day(first_event)
    or app.reserve_check_in_reminder_day(second_event) then raise exception 'Daily cap or same-event retry failed'; end if;
  select name into zone from pg_timezone_names where extract(hour from now() at time zone name)=2 limit 1;
  first_event.recipient_timezone := zone;
  if app.reserve_check_in_reminder_day(first_event) then raise exception 'Quiet-hour delivery was allowed'; end if;
  -- Positive control through the real public delivery gate, with a persisted
  -- daytime timezone and an unused daily allowance.
  delete from app.check_in_reminder_days where user_id='user_codex_supabase_smoke';
  select name into zone from pg_timezone_names where extract(hour from now() at time zone name)=12 limit 1;
  token := gen_random_uuid();
  update public.notification_events set recipient_timezone=zone,status='claimed',claim_token=token,
    claim_expires_at=now()+interval '10 minutes' where id=first_event.id;
  authorized := public.authorize_push_notification_delivery(first_event.id,token);
  if authorized is null then raise exception 'Eligible claimed reminder failed positive authorization'; end if;
  update public.notification_events set status='pending',claim_token=null,claim_expires_at=null where id=first_event.id;
  delete from app.check_in_reminder_days where user_id='user_codex_supabase_smoke';
end;
$test$;

set local role authenticated;
select set_config('request.jwt.claim.sub','user_codex_supabase_smoke_stranger',true);
do $test$
declare ids record; rejected boolean := false;
begin
  select * into ids from quick_check_in_smoke_ids;
  begin
    perform public.save_own_check_in('{"canonical_name":"Attempt"}',
      jsonb_build_object('id',ids.parent_id,'status','been','visibility','followers'), '[]',
      jsonb_build_object('id',ids.visit_id,'visited_at',now(),'details_pending',false),null);
  exception when others then rejected := true;
  end;
  if not rejected then raise exception 'Stranger could edit another owner visit'; end if;
end;
$test$;
select set_config('request.jwt.claim.sub','user_codex_supabase_smoke',true);
do $test$
declare ids record; saved jsonb;
begin
  select * into ids from quick_check_in_smoke_ids;
  saved := public.save_own_check_in('{"canonical_name":"Quick capture fixture","category":"coffee_tea_sweets","latitude":34,"longitude":-118}',
    jsonb_build_object('id',ids.parent_id,'status','been','visibility','followers','source_type','manual'), '[]',
    jsonb_build_object('id',ids.visit_id,'visited_at',now()-interval '1 day','rating_score',3,'note','Added later','details_pending',false),null);
  if (saved->>'visit_id')::uuid <> ids.visit_id or (saved->>'rating_score')::numeric <> 3
    or saved->>'details_pending' <> 'false' then raise exception 'Enrichment changed identity or explicit midpoint'; end if;
  saved := public.save_own_check_in('{"canonical_name":"Quick capture fixture","category":"coffee_tea_sweets","latitude":34,"longitude":-118}',
    jsonb_build_object('id',ids.parent_id,'status','been','visibility','followers','source_type','manual'), '[]',
    jsonb_build_object('id',ids.visit_id,'visited_at',now()-interval '1 day','rating_score',null,'details_pending',false),null);
  if saved->>'rating_score' is not null then raise exception 'Remove rating did not persist null'; end if;
  saved := public.save_own_check_in('{"canonical_name":"Quick capture fixture","category":"coffee_tea_sweets","latitude":34,"longitude":-118}',
    jsonb_build_object('id',ids.parent_id,'status','been','visibility','followers','source_type','manual'), '[]',
    jsonb_build_object('id',ids.visit_id,'visited_at',now()-interval '1 day','rating_score',null,'details_pending',true),null);
  if saved->>'details_pending' <> 'false' then raise exception 'Stale retry resurrected a resolved invitation'; end if;

  if (select count(*) from public.place_visits where user_place_id=ids.parent_id and deleted_at is null) <> 2
    then raise exception 'Enrichment created another visit'; end if;
end;
$test$;
reset role;
do $test$
declare ids record; event public.notification_events;
begin
  select * into ids from quick_check_in_smoke_ids;
  select * into event from public.notification_events where notification_type='check_in_reminder' and data->>'visit_id'=ids.visit_id::text;
  if event.status <> 'skipped' or app.notification_source_readable(event) then raise exception 'Enrichment did not cancel the reminder'; end if;
  if not exists(select 1 from pg_proc where oid='app.save_own_check_in(jsonb,jsonb,jsonb,jsonb,jsonb)'::regprocedure
    and prosecdef and provolatile='v' and 'search_path=public, app'=any(proconfig)) then raise exception 'Save RPC security posture changed'; end if;
  if has_function_privilege('anon','public.save_own_check_in(jsonb,jsonb,jsonb,jsonb,jsonb)','execute')
    or not has_function_privilege('authenticated','public.save_own_check_in(jsonb,jsonb,jsonb,jsonb,jsonb)','execute')
    or has_function_privilege('authenticated','app.queue_check_in_reminder(uuid,text)','execute')
    or has_function_privilege('authenticated','public.authorize_push_notification_delivery(uuid,uuid)','execute')
    or not has_function_privilege('service_role','public.authorize_push_notification_delivery(uuid,uuid)','execute')
    then raise exception 'Quick capture notification/save grants changed'; end if;
end;
$test$;

-- Exercise the actual final authorization RPC after resolution/opt-out, even if
-- a worker claimed the event immediately before the change.
do $test$
declare ids record; e public.notification_events; token uuid; result jsonb; zone text;
begin
  select * into ids from quick_check_in_smoke_ids;
  select name into zone from pg_timezone_names where extract(hour from now() at time zone name)=12 limit 1;
  delete from app.check_in_reminder_days where user_id='user_codex_supabase_smoke';
  if not (public.get_notification_preferences()).check_in_reminders_enabled then raise exception 'Resolution test requires preference enabled'; end if;
  select * into e from public.notification_events where notification_type='check_in_reminder' and data->>'visit_id'=ids.visit_id::text;
  token := gen_random_uuid();
  update public.notification_events set recipient_timezone=zone,status='claimed',claim_token=token,
    claim_expires_at=now()+interval '10 minutes' where id=e.id;
  result := public.authorize_push_notification_delivery(e.id,token);
  if result is not null then raise exception 'Final delivery ignored resolution while preference was on'; end if;

  -- Independent opt-out test: the second visit remains eligible and has no
  -- daily reservation, so only the preference can close this gate.
  select * into e from public.notification_events where notification_type='check_in_reminder' and data->>'visit_id'=ids.second_visit_id::text;
  if not app.notification_source_readable(e) then raise exception 'Opt-out fixture must remain eligible'; end if;
  perform public.update_notification_preferences('{"check_in_reminders_enabled":false}');
  if (public.get_notification_preferences()).push_enabled is not true then raise exception 'Reminder opt-out disabled other push'; end if;
  token := gen_random_uuid();
  update public.notification_events set recipient_timezone=zone,status='claimed',claim_token=token,
    claim_expires_at=now()+interval '10 minutes' where id=e.id;
  result := public.authorize_push_notification_delivery(e.id,token);
  if result is not null then raise exception 'Final delivery authorization ignored independent opt-out'; end if;
  if not exists(select 1 from pg_proc where oid='public.authorize_push_notification_delivery(uuid,uuid)'::regprocedure
    and prosecdef and provolatile='v' and 'search_path=pg_catalog, public, app'=any(proconfig))
    or not exists(select 1 from pg_proc where oid='app.notification_source_readable(public.notification_events)'::regprocedure
    and prosecdef and provolatile='s' and 'search_path=pg_catalog, public, app'=any(proconfig))
    or not exists(select 1 from pg_proc where oid='public.update_notification_preferences(jsonb)'::regprocedure
    and prosecdef and provolatile='v' and 'search_path=public, app'=any(proconfig))
    then raise exception 'Notification function security metadata changed'; end if;
end;
$test$;

set local role authenticated;
select set_config('request.jwt.claim.sub','user_codex_supabase_smoke',true);
select public.update_notification_preferences('{"check_in_reminders_enabled":true}');
do $test$
declare old_id uuid := gen_random_uuid(); saved jsonb;
begin
  saved := public.save_own_check_in('{"canonical_name":"Delayed capture fixture","category":"coffee_tea_sweets","latitude":34,"longitude":-118,"source_provider":"codex_smoke","source_provider_place_id":"delayed-quick-capture"}',
    '{"status":"been","visibility":"followers","source_type":"manual"}', '[]',
    jsonb_build_object('id',old_id,'visited_at',now()-interval '3 days','captured_at',now()-interval '3 days','details_pending',true),null);
  if (saved->>'created_at')::timestamptz <> now()-interval '3 days' then raise exception 'Capture timestamp was reset during delayed sync'; end if;
  insert into quick_check_in_smoke_ids values((saved->>'user_place_id')::uuid,old_id,null);
end;
$test$;
reset role;
do $test$
begin
  if exists(select 1 from public.notification_events event join quick_check_in_smoke_ids ids
    on event.data->>'visit_id'=ids.visit_id::text where ids.second_visit_id is null and event.notification_type='check_in_reminder')
    then raise exception 'Expired offline capture was enrolled in a new reminder'; end if;
end;
$test$;
