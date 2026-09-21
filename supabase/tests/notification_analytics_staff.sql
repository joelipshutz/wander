begin;
-- Read-only assertions work against hosted data and a migrated local database.
do $verify$
declare snapshot jsonb; expected_users integer; expected_notifications integer; actual_histogram integer;
  staff_ids text[] := array['user_3EhATWssjvHxwGiUaoWR5VTgeoy', 'user_3EsQ6OZGVoIBhjfDUUfDhpa0PLc'];
begin
  snapshot := public.notification_operations_snapshot(30);
  if snapshot->>'analytics_audience' is distinct from 'external_recipients_v1' then
    raise exception 'Missing staff-excluded audience contract';
  end if;
  with eligible as (
    select distinct token.user_id
    from public.notification_device_tokens token
    join public.notification_preferences pref on pref.user_id=token.user_id
    join public.profiles profile on profile.id=token.user_id
    where token.is_active and pref.push_enabled and profile.deleted_at is null
      and not (token.user_id = any(staff_ids))
  ) select (select count(*) from eligible), (select count(*) from public.notification_events event
       where event.recipient_user_id in (select user_id from eligible)
         and event.status='sent' and event.accepted_at >= now()-interval '30 days')
    into expected_users, expected_notifications;
  if (snapshot->>'eligible_recipient_count')::int <> expected_users
    or (snapshot->>'accepted_notification_count')::int <> expected_notifications then
    raise exception 'Snapshot includes staff or has inconsistent counts';
  end if;
  select sum((bucket->>'recipient_count')::int) into actual_histogram
    from jsonb_array_elements(snapshot->'histogram') bucket;
  if actual_histogram <> expected_users or jsonb_array_length(snapshot->'histogram') <> 7 then
    raise exception 'Histogram lost zero-count users';
  end if;
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where p.proname='notification_operations_snapshot' and n.nspname in ('app','public')
      and (not p.prosecdef or p.provolatile <> 's' or p.prorettype <> 'jsonb'::regtype
        or not (p.proconfig @> array[case when n.nspname='app' then 'search_path=public, app' else 'search_path=app, public' end])
        or has_function_privilege('anon',p.oid,'execute')
        or has_function_privilege('authenticated',p.oid,'execute')
        or not has_function_privilege('service_role',p.oid,'execute'))) then
    raise exception 'Snapshot RPC security posture changed';
  end if;
end $verify$;
select 'PASS: external recipient counts, histogram, and both RPC security contracts' as result;
rollback;
