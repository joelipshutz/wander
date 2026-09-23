begin;
do $test$
declare u text:='user_audit_'||replace(gen_random_uuid()::text,'-',''); t uuid; e uuid; batch jsonb; aid uuid; n integer;
begin
 insert into public.profiles(id,handle,display_name) values(u,'audit'||left(md5(u),12),'Audit Fixture');
 insert into public.notification_device_tokens(user_id,environment,device_token) values(u,'production',repeat('d',64)) returning id into t;
 insert into public.notification_events(recipient_user_id,notification_type,title,body) values(u,'followed_you','Fictional title','Fictional body') returning id into e;
 update public.notification_events set status='claimed',attempt_count=1 where id=e;
 insert into public.notification_push_deliveries(event_id,token_id,status,last_http_status,last_apns_reason) values(e,t,'retryable_failure',503,'ServiceUnavailable');
 update public.notification_push_deliveries set status='accepted',attempt_count=2,last_http_status=200,last_apns_reason=null,accepted_at=now() where event_id=e and token_id=t;
 update public.notification_events set status='sent',attempt_count=2 where id=e;
 select count(*) into n from public.notification_delivery_audit where event_id=e;
 if n<>5 then raise exception 'Expected all five transitions, got %',n; end if;
 update public.notification_events set updated_at=now() where id=e;
 if (select count(*) from public.notification_delivery_audit where event_id=e)<>5 then raise exception 'Metadata-only update created duplicate history'; end if;
 if not exists(select 1 from public.notification_delivery_audit where event_id=e and status='retryable_failure' and reason='ServiceUnavailable') then raise exception 'Retry failure overwritten'; end if;
 if not exists(select 1 from public.notification_delivery_audit where event_id=e and status='accepted' and attempt_count=2 and environment='production') then raise exception 'Successful retry missing'; end if;
 if app.notification_audit_reason('opaquePrivateToken')<>'transport_or_other_error' or app.notification_audit_reason('request to https://example.invalid/token123 failed')<>'transport_or_other_error' then raise exception 'Raw transport error leaked'; end if;
 -- Isolate the export fixture transaction without changing persistent rows.
 update public.notification_delivery_audit set exported_at=now() where event_id<>e;
 batch:=public.notification_audit_export_batch(200);
 if jsonb_array_length(batch)<>5 or batch::text like '%device_token%' or batch::text like '%actor_user_id%' or batch::text like '%deeplink%' then raise exception 'Unsafe or incomplete batch'; end if;
 if not exists(select 1 from jsonb_array_elements(batch) x where x->>'title'='Fictional title' and x->>'body'='Fictional body' and x->>'user_id'=u) then raise exception 'Requested recipient/text missing'; end if;
 aid:=(batch->0->>'audit_id')::uuid;
 perform public.ack_notification_audit_export(array[aid]);
 if jsonb_array_length(public.notification_audit_export_batch(200))<>4 then raise exception 'Acknowledgement failed'; end if;
 perform public.ack_notification_audit_export(array[aid]);
 if jsonb_array_length(public.notification_audit_export_batch(200))<>4 then raise exception 'Acknowledgement not idempotent'; end if;
 if has_table_privilege('authenticated','public.notification_delivery_audit','select') or has_table_privilege('anon','public.notification_delivery_audit','select') then raise exception 'Audit table exposed'; end if;
 if has_function_privilege('authenticated','public.notification_audit_export_batch(integer)','execute') or has_function_privilege('anon','public.ack_notification_audit_export(uuid[])','execute') then raise exception 'RPC exposed'; end if;
 if exists(select 1 from public.notification_delivery_audit where recipient_user_id in('user_3EhATWssjvHxwGiUaoWR5VTgeoy','user_3EsQ6OZGVoIBhjfDUUfDhpa0PLc')) then raise exception 'Staff backfill leaked'; end if;
end $test$;
select 'PASS: immutable failures/retries, title/body/recipient, metadata dedup, safe reasons, outbox acknowledgement, staff and ACLs' as result;
rollback;
