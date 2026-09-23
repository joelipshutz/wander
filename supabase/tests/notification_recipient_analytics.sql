begin;
do $test$
declare
  suffix text := replace(gen_random_uuid()::text,'-','');
  user_a text; user_zero text; token_a uuid; token_b uuid; sandbox_token uuid;
  event_a uuid; event_sandbox uuid; event_boundary uuid; event_old uuid;
  snapshot jsonb; recipient jsonb; total_accepted integer;
  boundary_at timestamptz := (((now() at time zone 'UTC')::date-29)::timestamp at time zone 'UTC');
begin
  user_a := 'user_analytics_'||suffix;
  user_zero := 'user_analytics_zero_'||suffix;
  insert into public.profiles(id,handle,display_name) values
    (user_a,'ana'||left(suffix,12),'Analytics Fixture'),
    (user_zero,'zero'||left(suffix,12),'Zero Fixture');
  insert into public.notification_device_tokens(user_id,environment,device_token) values
    (user_a,'production',repeat('a',64)) returning id into token_a;
  insert into public.notification_device_tokens(user_id,environment,device_token) values
    (user_a,'production',repeat('b',64)) returning id into token_b;
  insert into public.notification_device_tokens(user_id,environment,device_token) values
    (user_a,'sandbox',repeat('c',64)) returning id into sandbox_token;
  insert into public.notification_events(recipient_user_id,notification_type,title,body,status)
    values(user_a,'followed_you','Fixture','Fixture','sent') returning id into event_a;
  insert into public.notification_events(recipient_user_id,notification_type,title,body,status)
    values(user_a,'followed_you','Fixture','Fixture','sent') returning id into event_sandbox;
  insert into public.notification_events(recipient_user_id,notification_type,title,body,status)
    values(user_a,'followed_you','Fixture','Fixture','sent') returning id into event_boundary;
  insert into public.notification_events(recipient_user_id,notification_type,title,body,status)
    values(user_a,'followed_you','Fixture','Fixture','sent') returning id into event_old;
  insert into public.notification_push_deliveries(event_id,token_id,status,accepted_at) values
    (event_a,token_a,'accepted',now()),(event_a,token_b,'accepted',now()),
    (event_sandbox,sandbox_token,'accepted',now()),
    (event_boundary,token_a,'accepted',boundary_at),
    (event_old,token_a,'accepted',boundary_at-interval '1 second');
  snapshot := public.notification_recipient_analytics_snapshot(30);
  select value into recipient from jsonb_array_elements(snapshot->'recipients') where value->>'user_id'=user_a;
  select sum((value->>'accepted')::int) into total_accepted from jsonb_array_elements(recipient->'daily_counts');
  if total_accepted <> 2 or jsonb_array_length(recipient->'daily_counts')<>30 then
    raise exception 'Recipient counts must deduplicate devices, exclude sandbox and respect UTC bounds';
  end if;
  if (recipient->>'active_production_tokens')::int<>2 then raise exception 'Sandbox token counted as production'; end if;
  select value into recipient from jsonb_array_elements(snapshot->'recipients') where value->>'user_id'=user_zero;
  if recipient is null or exists(select 1 from jsonb_array_elements(recipient->'daily_counts') where (value->>'accepted')::int<>0)
    then raise exception 'Zero-send recipient lost'; end if;
  if exists(select 1 from jsonb_array_elements(snapshot->'recipients') where value->>'user_id' in (
    'user_3EhATWssjvHxwGiUaoWR5VTgeoy','user_3EsQ6OZGVoIBhjfDUUfDhpa0PLc')) then raise exception 'Staff included'; end if;
  if exists(select 1 from pg_proc where oid='public.notification_recipient_analytics_snapshot(integer)'::regprocedure
    and (not prosecdef or provolatile<>'s' or not proconfig @> array['search_path=public, app']
      or has_function_privilege('anon',oid,'execute') or has_function_privilege('authenticated',oid,'execute')
      or not has_function_privilege('service_role',oid,'execute'))) then raise exception 'Unsafe reporting RPC grants'; end if;
end $test$;
select 'PASS: recipient reporting, zeroes, multi-device deduplication, production-only acceptance, UTC bounds, staff exclusion and RPC security' as result;
rollback;
