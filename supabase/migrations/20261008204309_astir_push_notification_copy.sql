begin;

-- REC-635: replace only app-authored notification copy, preserving the deployed
-- function definitions and their authorization contracts. Calendar sync remains
-- a volatile JSONB SECURITY DEFINER RPC scoped by app.current_user_id(), with
-- search_path public, app and authenticated-only client access. Extraction
-- completion remains a volatile JSONB SECURITY DEFINER helper, with search_path
-- app, public and service_role-only access. No routing or scheduling changes.
do $migration$
declare
  target record;
  original pg_proc;
  updated pg_proc;
  definition text;
begin
  for target in
    select * from (values
      (
        'public.sync_calendar_reservations(jsonb,timestamptz,timestamptz)',
        'Your take helps friends know if it fits. Check in on rec.me.',
        'Your take helps friends know if it fits. Check in on Astir.'
      ),
      (
        'app.complete_extraction_job(uuid,text,jsonb,double precision,jsonb,text,text)',
        'Open rec.me to confirm the match.',
        'Open Astir to confirm the match.'
      )
    ) as replacements(signature, old_copy, new_copy)
  loop
    select * into strict original
    from pg_proc where oid = target.signature::regprocedure;
    definition := pg_get_functiondef(original.oid);

    if position(quote_literal(target.old_copy) in definition) > 0 then
      execute replace(definition, quote_literal(target.old_copy), quote_literal(target.new_copy));
    elsif position(quote_literal(target.new_copy) in definition) = 0 then
      raise exception 'unexpected_notification_copy_in_%', target.signature;
    end if;

    select * into strict updated from pg_proc where oid = original.oid;
    if updated.prosecdef is distinct from original.prosecdef
       or updated.proconfig is distinct from original.proconfig
       or updated.proacl is distinct from original.proacl
       or updated.provolatile is distinct from original.provolatile
       or updated.prorettype is distinct from original.prorettype then
      raise exception 'notification_copy_changed_function_contract_%', target.signature;
    end if;
  end loop;
end;
$migration$;

-- Refresh only unsent system templates. Preserve user text, deep links, payloads,
-- deadlines, dedupe keys, and the historical copy of already delivered events.
update public.notification_events
set body = case notification_type
      when 'calendar_reservation_live'
        then 'Your take helps friends know if it fits. Check in on Astir.'
      when 'capture_ready'
        then 'Open Astir to confirm the match.'
    end,
    updated_at = now()
where status in ('pending', 'claimed')
  and (
    (notification_type = 'calendar_reservation_live'
      and body = 'Your take helps friends know if it fits. Check in on rec.me.')
    or (notification_type = 'capture_ready'
      and body = 'Open rec.me to confirm the match.')
  );

commit;
