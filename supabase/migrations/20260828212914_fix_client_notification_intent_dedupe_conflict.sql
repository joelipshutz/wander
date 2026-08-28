-- Keep the authenticated client-intent RPC self-scoped while avoiding a
-- PL/pgSQL variable/column collision during dedupe checks and reconciliation.

create or replace function public.reconcile_client_notification_intents(
  input_source text,
  input_intents jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  normalized_source text := lower(trim(coalesce(input_source, '')));
  notification_type text;
  intent jsonb;
  intent_key text;
  intent_data jsonb;
  earliest_at timestamptz;
  latest_at timestamptz;
  queued_ids uuid[] := array[]::uuid[];
  supplied_dedupe_keys text[] := array[]::text[];
  dedupe_key_value text;
  output_event_id uuid;
  event_already_queued boolean;
  created_count integer := 0;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  if coalesce(jsonb_typeof(input_intents), '') <> 'array'
     or jsonb_array_length(input_intents) > 100 then
    raise exception 'invalid_notification_intents_payload';
  end if;

  notification_type := case normalized_source
    when 'wanna_go_reminder' then 'wanna_go_reminder'
    when 'save_streak_reminder' then 'save_streak_reminder'
    when 'import_finished' then 'import_finished'
    else null
  end;
  if notification_type is null then raise exception 'invalid_notification_intent_source'; end if;

  for intent in select value from jsonb_array_elements(input_intents)
  loop
    if coalesce(jsonb_typeof(intent), '') <> 'object' then
      raise exception 'invalid_notification_intent';
    end if;
    intent_key := trim(coalesce(intent->>'intent_key', ''));
    if length(intent_key) not between 1 and 160 then
      raise exception 'invalid_notification_intent_key';
    end if;
    intent_data := coalesce(intent->'data', '{}'::jsonb);
    if coalesce(jsonb_typeof(intent_data), '') <> 'object'
       or pg_column_size(intent_data) > 4096 then
      raise exception 'invalid_notification_intent_data';
    end if;

    if normalized_source = 'wanna_go_reminder' then
      if (intent_data - array['place_id', 'user_place_id', 'planned_date']) <> '{}'::jsonb
         or coalesce(intent->>'deeplink_url', '') not like 'recme://places/%' then
        raise exception 'invalid_wanna_go_notification_intent';
      end if;
    elsif normalized_source = 'save_streak_reminder' then
      if (intent_data - array['streak_count', 'copy_variant', 'scheduled_weekday', 'reminder_kind']) <> '{}'::jsonb
         or coalesce(intent->>'deeplink_url', '') <> 'recme://add/here-now' then
        raise exception 'invalid_save_streak_notification_intent';
      end if;
    elsif normalized_source = 'import_finished' then
      if (intent_data - array['batch_ids']) <> '{}'::jsonb
         or coalesce(jsonb_typeof(intent_data->'batch_ids'), '') <> 'array'
         or jsonb_array_length(intent_data->'batch_ids') > 100
         or nullif(trim(coalesce(intent->>'deeplink_url', '')), '') is not null then
        raise exception 'invalid_import_notification_intent';
      end if;
    end if;

    earliest_at := coalesce((intent->>'earliest_at')::timestamptz, now());
    latest_at := coalesce((intent->>'latest_at')::timestamptz, earliest_at + interval '24 hours');
    if earliest_at > now() + interval '400 days'
       or latest_at < earliest_at
       or latest_at > earliest_at + interval '48 hours' then
      raise exception 'invalid_notification_intent_delivery_window';
    end if;

    dedupe_key_value := 'client:' || viewer_id || ':' || normalized_source || ':' || intent_key;
    supplied_dedupe_keys := array_append(supplied_dedupe_keys, dedupe_key_value);
    select exists (
      select 1
      from public.notification_events event
      where event.recipient_user_id = viewer_id
        and event.dedupe_key = dedupe_key_value
        and event.status in ('pending', 'claimed')
    ) into event_already_queued;
    output_event_id := app.queue_notification_intent(
      input_recipient_user_id := viewer_id,
      input_notification_type := notification_type,
      input_title := intent->>'title',
      input_body := intent->>'body',
      input_deeplink_url := intent->>'deeplink_url',
      input_data := intent_data,
      input_dedupe_key := dedupe_key_value,
      input_earliest_at := earliest_at,
      input_latest_at := latest_at,
      input_source := normalized_source,
      input_priority := coalesce((intent->>'priority')::smallint, 40::smallint),
      input_conflict_group := intent->>'conflict_group',
      input_recipient_timezone := intent->>'recipient_timezone'
    );
    if output_event_id is not null then
      queued_ids := array_append(queued_ids, output_event_id);
      if not event_already_queued then
        created_count := created_count + 1;
      end if;
    end if;
  end loop;

  if normalized_source in ('wanna_go_reminder', 'save_streak_reminder') then
    update public.notification_events event
    set status = 'skipped',
        skip_reason = 'client_intent_reconciled',
        failed_at = now(),
        claim_expires_at = null,
        claim_token = null,
        updated_at = now()
    where event.recipient_user_id = viewer_id
      and event.source = normalized_source
      and event.status in ('pending', 'claimed')
      and not (event.dedupe_key = any(supplied_dedupe_keys));
  end if;

  return jsonb_build_object(
    'queued_event_ids', to_jsonb(queued_ids),
    'queued_count', cardinality(queued_ids),
    'created_count', created_count
  );
end;
$$;

comment on function public.reconcile_client_notification_intents(text, jsonb) is
  'Reconciles authenticated self-reminders into the central push governor with strict per-source payload allowlists.';

revoke all on function public.reconcile_client_notification_intents(text, jsonb)
  from public, anon, authenticated;
grant execute on function public.reconcile_client_notification_intents(text, jsonb)
  to authenticated;
