begin;

-- REC-589: preserve useful social push copy after final source authorization.
-- This replaces the REC-590 blanket actor-based redaction, not its access checks.
-- Worker-only SECURITY DEFINER is retained to lock the private delivery claim,
-- read source authorization/active tokens, and suppress stale or revoked work.
-- No client-supplied actor/recipient is accepted. Preserve volatile/jsonb ABI,
-- pinned search_path, service_role-only EXECUTE, and payload key allowlist.
-- No history rewrite or re-enqueue: existing delivered pushes are untouched.

create or replace function public.authorize_push_notification_delivery(input_event_id uuid, input_claim_token uuid)
returns jsonb language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare event public.notification_events; allowed boolean; import_content jsonb;
begin
  select * into event from public.notification_events
  where id = input_event_id and status = 'claimed' and claim_token = input_claim_token
    and claim_expires_at > now() for update;
  if not found then return null; end if;
  allowed := app.notification_source_readable(event)
    and (event.source <> 'calendar_reservation' or exists (
      select 1 from public.calendar_reservations reservation
      where reservation.user_id = event.recipient_user_id
        and reservation.completed_at is null and reservation.cancelled_at is null
        and event.conflict_group = 'calendar_reservation:' || reservation.id))
    and least(event.expires_at, event.latest_at) > now()
    and exists (select 1 from public.notification_preferences preferences
      where preferences.user_id = event.recipient_user_id
        and app.notification_type_enabled(preferences, event.notification_type))
    and not exists (select 1 from public.profile_mutes
      where muter_user_id = event.recipient_user_id and muted_user_id = event.actor_user_id);
  -- A source can become hidden after queue claim. Re-render only the frozen
  -- import manifest at final authorization so detailed copy cannot name/count
  -- a revoked place. The ledger never expands to later import saves.
  if event.notification_type = 'followed_place_visit'
      and event.data->>'sender_import_id' is not null then
    import_content := app.import_notification_content(event.actor_user_id,
      event.recipient_user_id, event.data->>'sender_import_id');
    allowed := allowed and import_content is not null;
  end if;
  if not coalesce(allowed, false) then
    update public.notification_events set status = 'skipped', skip_reason = 'source_not_visible',
      claim_token = null, claim_expires_at = null, error_message = null
      where id = event.id;
    return null;
  end if;
  if import_content is not null then
    update public.notification_events
      set body = import_content->>'body',
          deeplink_url = 'recme://places/' || (import_content->>'place_id'),
          data = data || jsonb_build_object('place_id', import_content->>'place_id',
            'place_count', import_content->'place_count')
      where id = event.id
      returning * into event;
  end if;
  return jsonb_build_object(
    'event_id', event.id, 'claim_token', event.claim_token,
    'recipient_user_id', event.recipient_user_id, 'actor_user_id', event.actor_user_id,
    'notification_type', event.notification_type,
    -- Eligibility, not the presence of an actor, controls delivery. Friends and
    -- other authorized recipients receive the producer's personalized copy.
    'title', event.title,
    'body', event.body,
    'deeplink_url', event.deeplink_url,
    'data', (select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
      from jsonb_each(event.data) where key in ('activity_id','visit_id','user_place_id','place_id',
        'list_id','participant_id','invitation_generation','group_id','source_visit_id',
        'actor_user_id','event_type','reservation_id','job_id')),
    'attempt_count', event.attempt_count, 'max_attempts', event.max_attempts,
    'claim_expires_at', event.claim_expires_at,
    'tokens', (select coalesce(jsonb_agg(jsonb_build_object('id', token.id,
      'device_token', token.device_token, 'environment', token.environment,
      'app_bundle_id', token.app_bundle_id)), '[]'::jsonb)
      from public.notification_device_tokens token
      where token.user_id = event.recipient_user_id and token.is_active
        and not exists (select 1 from public.notification_push_deliveries delivery
          where delivery.event_id = event.id and delivery.token_id = token.id
            and delivery.status in ('accepted','permanent_token_failure','permanent_event_failure')))
  );
end;
$$;
revoke all on function public.authorize_push_notification_delivery(uuid,uuid) from public, anon, authenticated;
grant execute on function public.authorize_push_notification_delivery(uuid,uuid) to service_role;

commit;
