begin;
-- REC-590: source authorization and anonymous place-level rating aggregates.

-- Internal explicit-viewer helper: delivery workers have no end-user JWT.
-- Definer is deliberate; clients cannot execute it or select arbitrary viewers.
create function app.can_read_visit_source(input_viewer text, input_visit uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, app
as $$
  select input_viewer is not null and exists (
    select 1 from public.place_visits visit
    join public.user_places saved on saved.id = visit.user_place_id
    join public.profiles owner on owner.id = saved.user_id
    join public.profiles viewer on viewer.id = input_viewer
    where visit.id = input_visit and visit.deleted_at is null and saved.deleted_at is null
      and owner.deleted_at is null and viewer.deleted_at is null
      and (saved.user_id = input_viewer or not owner.is_private_profile)
      and app.can_read_user_place(input_viewer, saved.user_id, saved.visibility)
  );
$$;
revoke all on function app.can_read_visit_source(text, uuid) from public, anon, authenticated;

-- Copied photos retain immutable source identity. Independent notes/ratings and
-- independently uploaded photos on the recipient's visit remain their own.
create table app.visit_photo_sources (
  photo_id uuid primary key references public.visit_photos(id) on delete cascade,
  source_photo_id uuid not null,
  check (photo_id <> source_photo_id)
);
alter table app.visit_photo_sources enable row level security;
revoke all on app.visit_photo_sources from public, anon, authenticated;

-- Completed acceptance operations are exact provenance; timestamps or matching
-- place membership are never used to infer a copy.
insert into app.visit_photo_sources(photo_id, source_photo_id)
select destination.id, (copied->>'source_photo_id')::uuid
from public.shared_visit_operations operation
cross join lateral jsonb_array_elements(coalesce(operation.result->'photo_copies', '[]'::jsonb)) copied
join public.visit_photos destination on destination.id::text = copied->>'destination_photo_id'
where operation.status = 'completed' and operation.operation_type = 'accept'
  and destination.visit_id::text = operation.result->>'visit_id'
  and destination.storage_path = copied->>'destination_path'
  and copied->>'source_photo_id' ~* '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
on conflict do nothing;

create function app.can_read_photo_source(input_viewer text, input_photo uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, app
as $$
  with recursive lineage(id, seen) as (
    select input_photo, array[input_photo]
    union all
    select source.source_photo_id, lineage.seen || source.source_photo_id
    from lineage join app.visit_photo_sources source on source.photo_id = lineage.id
    where cardinality(lineage.seen) < 32 and not source.source_photo_id = any(lineage.seen)
  )
  select coalesce(bool_and(photo.id is not null and photo.deleted_at is null
      and app.can_read_visit_source(input_viewer, photo.visit_id)), false)
    and exists (select 1 from lineage terminal
      where not exists (select 1 from app.visit_photo_sources source where source.photo_id = terminal.id))
  from lineage left join public.visit_photos photo on photo.id = lineage.id;
$$;
revoke all on function app.can_read_photo_source(text,uuid) from public, anon, authenticated;

create function app.can_read_own_photo_request(input_photo uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, app
as $$ select app.can_read_photo_source(app.current_user_id(), input_photo) $$;
revoke all on function app.can_read_own_photo_request(uuid) from public, anon;
grant execute on function app.can_read_own_photo_request(uuid) to authenticated;

-- All direct metadata and authenticated Storage reads enforce the same chain.
drop policy "visit photos readable through visit" on public.visit_photos;
create policy "visit photos readable through visit" on public.visit_photos for select to authenticated
using (app.can_read_own_photo_request(id));

create function public.can_read_visit_photo(input_bucket text, input_path text)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, app
as $$
  select app.current_user_id() is not null and exists (
    select 1 from public.visit_photos photo
    where photo.storage_bucket = input_bucket and photo.storage_path = input_path
      and photo.deleted_at is null and photo.upload_state = 'uploaded'
      and app.can_read_photo_source(app.current_user_id(), photo.id)
  );
$$;
revoke all on function public.can_read_visit_photo(text,text) from public, anon;
grant execute on function public.can_read_visit_photo(text,text) to authenticated;

drop policy "visit photo objects readable through visit" on storage.objects;
create policy "visit photo objects readable through visit" on storage.objects for select to authenticated
using (bucket_id = 'visit-photos'
  and storage.allow_any_operation(array['object.get_authenticated','render.image_authenticated'])
  and public.can_read_visit_photo(bucket_id, name));
-- Owner upload/delete/list metadata access must not also authorize signed URLs.
create policy "visit photo owner management metadata" on storage.objects for select to authenticated
using (bucket_id = 'visit-photos'
  and storage.allow_any_operation(array['object.upload','object.upload_update','object.delete',
    'object.delete_many','object.list','object.list_v2','object.get_authenticated_info','object.head_authenticated_info'])
  and split_part(name, '/', 1) = app.current_user_id()
  and case when split_part(name, '/', 2) ~* '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
    then app.owns_place_visit(split_part(name, '/', 2)::uuid) else false end);

-- Invalid or old notification payloads fail closed instead of aborting a batch.
create function app.privacy_uuid(input_value text)
returns uuid language sql immutable security invoker set search_path = ''
as $$ select case when input_value ~* '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
  then input_value::uuid else null end $$;
revoke all on function app.privacy_uuid(text) from public, anon, authenticated;

create function app.notification_source_readable(event public.notification_events)
returns boolean language plpgsql stable security definer
set search_path = pg_catalog, public, app
as $$
declare viewer text := event.recipient_user_id;
begin
  if not exists (select 1 from public.profiles where id = viewer and deleted_at is null)
    then return false; end if;
  if event.actor_user_id is not null and (
    app.is_blocked(viewer, event.actor_user_id)
    or not exists (select 1 from public.profiles where id = event.actor_user_id and deleted_at is null)
  ) then return false; end if;
  case event.notification_type
    when 'activity_liked', 'activity_commented' then
      return app.can_read_activity_event(viewer, app.privacy_uuid(event.data->>'activity_id'));
    when 'followed_place_visit' then
      return app.can_read_visit_source(viewer, app.privacy_uuid(event.data->>'visit_id'));
    when 'shared_visit' then
      return exists (
        select 1 from public.shared_visit_participants participant
        join public.shared_visit_groups shared_group on shared_group.id = participant.group_id
        where participant.id = app.privacy_uuid(event.data->>'participant_id')
          and participant.user_id = viewer and participant.status = 'pending'
          and participant.invitation_generation::text = event.data->>'invitation_generation'
          and participant.invitation_snapshot is not null and shared_group.cancelled_at is null
          and app.can_read_visit_source(viewer, shared_group.source_visit_id)
      );
    when 'list_collaborator_added' then
      return app.can_read_place_list(app.privacy_uuid(event.data->>'list_id'), viewer);
    when 'list_place_added' then
      return app.can_read_place_list(app.privacy_uuid(event.data->>'list_id'), viewer)
        and exists (select 1 from public.place_list_items item
          where item.list_id = app.privacy_uuid(event.data->>'list_id')
            and item.place_id = app.privacy_uuid(event.data->>'place_id')
            and item.added_by_user_id = event.actor_user_id and item.deleted_at is null);
    when 'place_saved_from_your_map' then
      return exists (select 1 from public.user_places saved
        join public.profiles owner on owner.id = saved.user_id
        where saved.id = app.privacy_uuid(event.data->>'user_place_id')
          and saved.user_id = event.actor_user_id and saved.deleted_at is null
          and owner.deleted_at is null and not owner.is_private_profile
          and app.can_read_user_place(viewer, saved.user_id, saved.visibility));
    when 'followed_you', 'mutual_follow' then
      return exists (select 1 from public.follows
        where follower_user_id = event.actor_user_id and followed_user_id = viewer);
    when 'capture_ready', 'import_finished', 'wanna_go_reminder', 'save_streak_reminder',
         'calendar_reservation_live', 'calendar_reservation_follow_up' then
      -- These producers are authenticated owner-only or internal self-reminders.
      return event.actor_user_id is null or event.actor_user_id = viewer;
    else return false;
  end case;
end;
$$;
revoke all on function app.notification_source_readable(public.notification_events) from public, anon, authenticated;

create function app.can_read_own_notification(input_event_id uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, app
as $$
  select exists (select 1 from public.notification_events event
    where event.id = input_event_id and event.recipient_user_id = app.current_user_id()
      and app.notification_source_readable(event));
$$;
revoke all on function app.can_read_own_notification(uuid) from public, anon;
grant execute on function app.can_read_own_notification(uuid) to authenticated;
drop policy "notification events recipient readable" on public.notification_events;
create policy "notification events recipient readable" on public.notification_events for select to authenticated
using (recipient_user_id = app.current_user_id() and app.can_read_own_notification(id));

-- Re-authorize after claim, immediately before APNs. Return a fresh envelope;
-- never trust the worker's earlier copy. A stale claim cannot send or settle.
create function public.authorize_push_notification_delivery(input_event_id uuid, input_claim_token uuid)
returns jsonb language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare event public.notification_events; allowed boolean;
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
  if not coalesce(allowed, false) then
    update public.notification_events set status = 'skipped', skip_reason = 'source_not_visible',
      claim_token = null, claim_expires_at = null, error_message = null
      where id = event.id;
    return null;
  end if;
  return jsonb_build_object(
    'event_id', event.id, 'claim_token', event.claim_token,
    'recipient_user_id', event.recipient_user_id, 'actor_user_id', event.actor_user_id,
    'notification_type', event.notification_type,
    -- Delivered copy cannot be recalled if access changes after this check.
    'title', case when event.actor_user_id is null then event.title else 'New activity on Astir' end,
    'body', case when event.actor_user_id is null then event.body else 'Open Astir to view.' end,
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


create function app.authorized_shared_snapshot(input_snapshot jsonb, input_viewer text)
returns jsonb language sql stable security definer set search_path = pg_catalog, public, app
as $$ select case when input_snapshot is null then null else
  jsonb_set(app.private_taxonomy_snapshot_projection(input_snapshot), '{photos}',
    (select coalesce(jsonb_agg(photo), '[]'::jsonb)
     from jsonb_array_elements(coalesce(input_snapshot->'photos', '[]'::jsonb)) photo
     where app.can_read_photo_source(input_viewer, app.privacy_uuid(photo->>'photo_id')))) end $$;
revoke all on function app.authorized_shared_snapshot(jsonb,text) from public, anon, authenticated;

create function app.authorized_photo_copy_manifest(input_result jsonb, input_viewer text)
returns jsonb language sql stable security definer set search_path = pg_catalog, public, app
as $$ select case when input_result is null then null else
  jsonb_set(input_result, '{photo_copies}',
    (select coalesce(jsonb_agg(photo), '[]'::jsonb)
     from jsonb_array_elements(coalesce(input_result->'photo_copies', '[]'::jsonb)) photo
     where app.can_read_photo_source(input_viewer, app.privacy_uuid(photo->>'source_photo_id')))) end $$;
revoke all on function app.authorized_photo_copy_manifest(jsonb,text) from public, anon, authenticated;

-- Preserve claim leases, device settlement, deadlines, preference and mute governance.
create or replace function app.claim_pending_push_notifications(input_limit integer default 10)
returns jsonb
language plpgsql
security definer
set search_path = public, app
as $$
declare
  bounded_limit integer := least(greatest(coalesce(input_limit, 10), 1), 20);
  output_payload jsonb;
begin
  update public.notification_events event
  set status = 'skipped', skip_reason = 'source_not_visible', claim_token = null,
      claim_expires_at = null, error_message = null
  where event.status in ('pending', 'claimed') and not app.notification_source_readable(event);
  with disabled_events as (
    update public.notification_events event
    set status = 'skipped', failed_at = now(), claim_expires_at = null,
        claim_token = null, skip_reason = 'notification_preference_disabled', error_message = null
    where event.status in ('pending', 'claimed')
      and exists (
        select 1 from public.notification_preferences preferences
        where preferences.user_id = event.recipient_user_id
          and not app.notification_type_enabled(preferences, event.notification_type)
      )
    returning event.id
  ), unavailable_reservations as (
    update public.notification_events event
    set status = 'skipped', failed_at = now(), claim_expires_at = null,
        claim_token = null, skip_reason = 'calendar_reservation_unavailable', error_message = null
    where event.status in ('pending', 'claimed')
      and event.source = 'calendar_reservation'
      and not exists (
        select 1 from public.calendar_reservations reservation
        where reservation.user_id = event.recipient_user_id
          and reservation.completed_at is null
          and reservation.cancelled_at is null
          and event.conflict_group = 'calendar_reservation:' || reservation.id
      )
    returning event.id
  ), muted_events as (
    update public.notification_events event
    set status = 'skipped', failed_at = now(), claim_expires_at = null,
        claim_token = null, skip_reason = 'actor_muted', error_message = null
    where event.status in ('pending', 'claimed')
      and event.actor_user_id is not null
      and exists (
        select 1 from public.profile_mutes muted
        where muted.muter_user_id = event.recipient_user_id
          and muted.muted_user_id = event.actor_user_id
      )
    returning event.id
  ), expired_events as (
    update public.notification_events event
    set status = 'skipped', failed_at = now(), claim_expires_at = null,
        claim_token = null, skip_reason = 'notification_expired', error_message = null
    where event.status in ('pending', 'claimed')
      and least(event.expires_at, event.latest_at) <= now()
    returning event.id
  ), exhausted_claims as (
    update public.notification_events event
    set status = 'failed', failed_at = now(), claim_expires_at = null,
        claim_token = null,
        error_message = coalesce(nullif(event.error_message, ''), 'push_claim_expired_max_attempts')
    where event.status = 'claimed'
      and event.claim_expires_at <= now()
      and event.attempt_count >= event.max_attempts
    returning event.id
  ), claimable as (
    select event.id
    from public.notification_events event
    where (
        (event.status = 'pending' and event.not_before <= now())
        or (event.status = 'claimed' and event.claim_expires_at <= now())
      )
      and least(event.expires_at, event.latest_at) > now()
      and app.notification_source_readable(event)
      and event.attempt_count < event.max_attempts
      and exists (
        select 1
        from public.notification_device_tokens token
        where token.user_id = event.recipient_user_id
          and token.is_active
          and not exists (
            select 1
            from public.notification_push_deliveries delivery
            where delivery.event_id = event.id
              and delivery.token_id = token.id
              and delivery.status in (
                'accepted', 'permanent_token_failure', 'permanent_event_failure'
              )
          )
      )
      and not exists (
        select 1 from public.profile_mutes muted
        where muted.muter_user_id = event.recipient_user_id
          and muted.muted_user_id = event.actor_user_id
      )
    order by event.priority desc, event.not_before, event.created_at
    for update skip locked
    limit bounded_limit
  ), updated as (
    update public.notification_events event
    set status = 'claimed',
        claimed_at = now(),
        claim_expires_at = now() + interval '10 minutes',
        claim_token = gen_random_uuid(),
        attempt_count = event.attempt_count + 1,
        last_attempted_at = now()
    from claimable
    where event.id = claimable.id
    returning event.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'event_id', updated.id,
    'claim_token', updated.claim_token,
    'recipient_user_id', updated.recipient_user_id,
    'actor_user_id', updated.actor_user_id,
    'notification_type', updated.notification_type,
    'title', updated.title,
    'body', updated.body,
    'deeplink_url', updated.deeplink_url,
    'data', updated.data,
    'attempt_count', updated.attempt_count,
    'max_attempts', updated.max_attempts,
    'claim_expires_at', updated.claim_expires_at,
    'tokens', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', token.id,
        'device_token', token.device_token,
        'environment', token.environment,
        'app_bundle_id', token.app_bundle_id
      ) order by token.last_seen_at desc)
      from public.notification_device_tokens token
      where token.user_id = updated.recipient_user_id
        and token.is_active
        and not exists (
          select 1
          from public.notification_push_deliveries delivery
          where delivery.event_id = updated.id
            and delivery.token_id = token.id
            and delivery.status in (
              'accepted', 'permanent_token_failure', 'permanent_event_failure'
            )
        )
    ), '[]'::jsonb)
  ) order by updated.priority desc, updated.not_before, updated.created_at), '[]'::jsonb)
  into output_payload
  from updated;

  return output_payload;
end;
$$;
revoke all on function app.claim_pending_push_notifications(integer) from public, anon, authenticated;
grant execute on function app.claim_pending_push_notifications(integer) to service_role;

-- Keep the existing authenticated definer ABI and taxonomy redaction.
create or replace function public.list_shared_visit_inbox(
  input_before timestamptz default null,
  input_limit integer default 50
)
returns table (
  participant_id uuid,
  group_id uuid,
  invitation_generation integer,
  snapshot_revision integer,
  participant_status text,
  invited_at timestamptz,
  source_visit_id uuid,
  source_owner_user_id text,
  source_owner_handle text,
  source_owner_display_name text,
  source_owner_avatar_url text,
  place_id uuid,
  canonical_name text,
  category text,
  primary_category text,
  subcategory text,
  address text,
  locality text,
  region text,
  country text,
  latitude double precision,
  longitude double precision,
  source_provider text,
  source_provider_place_id text,
  source_snapshot jsonb
)
language sql
stable
security definer
set search_path = public, app
as $$
  select
    participant.id,
    shared_group.id,
    participant.invitation_generation,
    participant.snapshot_revision,
    participant.status,
    participant.invited_at,
    shared_group.source_visit_id,
    owner.id,
    owner.handle,
    owner.display_name,
    owner.avatar_url,
    place.id,
    place.canonical_name,
    place.category,
    place.primary_category,
    place.subcategory,
    place.address,
    place.locality,
    place.region,
    place.country,
    place.latitude,
    place.longitude,
    place.source_provider,
    place.source_provider_place_id,
    app.authorized_shared_snapshot(participant.invitation_snapshot, app.current_user_id())
  from public.shared_visit_participants participant
  join public.shared_visit_groups shared_group on shared_group.id = participant.group_id
  join public.profiles owner on owner.id = shared_group.owner_user_id
  join public.places place on place.id = shared_group.place_id
  where participant.user_id = app.current_user_id()
    and participant.status = 'pending'
    and participant.invitation_snapshot is not null
    and shared_group.cancelled_at is null
    and owner.deleted_at is null
    and not owner.is_private_profile
    and app.can_read_visit_source(app.current_user_id(), shared_group.source_visit_id)
    and (input_before is null or participant.invited_at < input_before)
  order by participant.invited_at desc, participant.id
  limit greatest(1, least(coalesce(input_limit, 50), 50))
$$;
revoke all on function public.list_shared_visit_inbox(timestamptz,integer) from public, anon;
grant execute on function public.list_shared_visit_inbox(timestamptz,integer) to authenticated;

-- Keep the existing authenticated definer ABI and taxonomy redaction.
create or replace function public.get_shared_visit_context(
  input_participant_id uuid,
  input_generation integer
)
returns table (
  participant_id uuid,
  group_id uuid,
  invitation_generation integer,
  snapshot_revision integer,
  participant_status text,
  invited_at timestamptz,
  source_visit_id uuid,
  source_owner_user_id text,
  source_owner_handle text,
  source_owner_display_name text,
  source_owner_avatar_url text,
  place_id uuid,
  canonical_name text,
  category text,
  primary_category text,
  subcategory text,
  address text,
  locality text,
  region text,
  country text,
  latitude double precision,
  longitude double precision,
  source_provider text,
  source_provider_place_id text,
  source_snapshot jsonb
)
language sql
stable
security definer
set search_path = public, app
as $$
  select
    participant.id,
    shared_group.id,
    participant.invitation_generation,
    participant.snapshot_revision,
    participant.status,
    participant.invited_at,
    shared_group.source_visit_id,
    owner.id,
    owner.handle,
    owner.display_name,
    owner.avatar_url,
    place.id,
    place.canonical_name,
    place.category,
    place.primary_category,
    place.subcategory,
    place.address,
    place.locality,
    place.region,
    place.country,
    place.latitude,
    place.longitude,
    place.source_provider,
    place.source_provider_place_id,
    app.authorized_shared_snapshot(participant.invitation_snapshot, app.current_user_id())
  from public.shared_visit_participants participant
  join public.shared_visit_groups shared_group on shared_group.id = participant.group_id
  join public.profiles owner on owner.id = shared_group.owner_user_id
  join public.places place on place.id = shared_group.place_id
  where participant.id = input_participant_id
    and participant.user_id = app.current_user_id()
    and participant.invitation_generation = input_generation
    and participant.status = 'pending'
    and participant.invitation_snapshot is not null
    and shared_group.cancelled_at is null
    and owner.deleted_at is null
    and not owner.is_private_profile
    and app.can_read_visit_source(app.current_user_id(), shared_group.source_visit_id)
$$;
revoke all on function public.get_shared_visit_context(uuid,integer) from public, anon;
grant execute on function public.get_shared_visit_context(uuid,integer) to authenticated;

create or replace function public.get_shared_visit_companion_context(input_visit_ids uuid[])
returns table (
  visit_id uuid,
  companion_user_id text,
  companion_handle text,
  companion_display_name text,
  companion_avatar_url text
)
language sql
stable
security definer
set search_path = public, app
as $$
  with requested_visits as (
    select
      visit.id,
      user_place.user_id as visit_owner_user_id
    from public.place_visits visit
    join public.user_places user_place on user_place.id = visit.user_place_id
    where visit.id = any(coalesce(input_visit_ids, array[]::uuid[]))
      and visit.deleted_at is null
      and app.can_read_visit_source(app.current_user_id(), visit.id)
      and user_place.deleted_at is null
      and app.can_read_user_place(
        app.current_user_id(),
        user_place.user_id,
        user_place.visibility
      )
    limit 50
  ), resolved_groups as (
    select
      requested.id as requested_visit_id,
      requested.visit_owner_user_id,
      shared_group.id as group_id,
      true as is_source_visit
    from requested_visits requested
    join public.shared_visit_groups shared_group on shared_group.source_visit_id = requested.id
    where shared_group.cancelled_at is null
    union all
    select
      requested.id,
      requested.visit_owner_user_id,
      participant.group_id,
      false
    from requested_visits requested
    join public.shared_visit_participants participant on participant.visit_id = requested.id
    join public.shared_visit_groups shared_group on shared_group.id = participant.group_id
    where participant.status = 'accepted'
      and shared_group.cancelled_at is null
  )
  select
    resolved.requested_visit_id,
    companion.user_id,
    profile.handle,
    profile.display_name,
    profile.avatar_url
  from resolved_groups resolved
  join public.shared_visit_participants companion on companion.group_id = resolved.group_id
  join public.profiles profile on profile.id = companion.user_id
  left join public.place_visits companion_visit on companion_visit.id = companion.visit_id
  left join public.user_places companion_place on companion_place.id = companion_visit.user_place_id
  where (
      (resolved.is_source_visit and companion.status = 'accepted')
      or (
        resolved.is_source_visit
        and resolved.visit_owner_user_id = app.current_user_id()
        and companion.status = 'pending'
      )
      or (not resolved.is_source_visit and companion.status in ('owner', 'accepted'))
    )
    and companion.user_id <> resolved.visit_owner_user_id
    and not app.is_blocked(app.current_user_id(), companion.user_id)
    and profile.deleted_at is null
    and (
      companion.user_id = app.current_user_id()
      or not profile.is_private_profile
    )
    and (
      (
        resolved.is_source_visit
        and resolved.visit_owner_user_id = app.current_user_id()
        and companion.status = 'pending'
      )
      or (companion.status = 'owner'
          and app.can_read_visit_source(app.current_user_id(), companion.visit_id))
      or (
        companion.status = 'accepted'
        and (
          companion.user_id = app.current_user_id()
          or (
            companion_visit.deleted_at is null
            and companion_place.deleted_at is null
            and companion_place.visibility <> 'self'
            and app.can_read_user_place(
              app.current_user_id(),
              companion.user_id,
              companion_place.visibility
            )
          )
        )
      )
    )
  order by
    resolved.requested_visit_id,
    (companion.user_id = app.current_user_id()) desc,
    profile.display_name,
    profile.id
$$;
revoke all on function public.get_shared_visit_companion_context(uuid[]) from public, anon;
grant execute on function public.get_shared_visit_companion_context(uuid[]) to authenticated;

create or replace function public.resolve_shared_visit_destination(
  input_participant_id uuid,
  input_generation integer
)
returns table (
  participant_id uuid,
  requested_generation integer,
  current_generation integer,
  route_status text,
  place_id uuid,
  accepted_visit_id uuid,
  source_visit_id uuid
)
language sql
stable
security definer
set search_path = public, app
as $$
  select
    participant.id,
    input_generation,
    participant.invitation_generation,
    case
      when participant.invitation_generation <> input_generation then 'stale'
      when participant.status = 'pending' and participant.invitation_snapshot is not null
        and shared_group.cancelled_at is null
        and app.can_read_visit_source(app.current_user_id(), shared_group.source_visit_id) then 'pending'
      when participant.status = 'accepted' and participant.visit_id is not null then 'accepted'
      else participant.status
    end,
    shared_group.place_id,
    participant.visit_id,
    case when app.can_read_visit_source(app.current_user_id(), shared_group.source_visit_id)
      then shared_group.source_visit_id else null end
  from public.shared_visit_participants participant
  join public.shared_visit_groups shared_group on shared_group.id = participant.group_id
  where participant.id = input_participant_id
    and participant.user_id = app.current_user_id()
    and (participant.status = 'accepted'
      or app.can_read_visit_source(app.current_user_id(), shared_group.source_visit_id))
$$;
revoke all on function public.resolve_shared_visit_destination(uuid,integer) from public, anon;
grant execute on function public.resolve_shared_visit_destination(uuid,integer) to authenticated;


-- Only this authenticated creation path records provenance. List membership,
-- source_type=manual, and nearby timestamps are not proof of automatic origin.
create table app.private_list_companion_origins (
  user_place_id uuid primary key references public.user_places(id) on delete cascade,
  created_at timestamptz not null default now(),
  audience_changed_at timestamptz
);
alter table app.private_list_companion_origins enable row level security;
revoke all on app.private_list_companion_origins from public, anon, authenticated;

create function app.record_companion_audience_change()
returns trigger language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
begin
  if new.visibility is distinct from old.visibility then
    update app.private_list_companion_origins set audience_changed_at = now()
    where user_place_id = new.id;
  end if;
  return new;
end;
$$;
revoke all on function app.record_companion_audience_change() from public, anon, authenticated;
create trigger user_places_companion_audience_changed after update of visibility on public.user_places
for each row execute function app.record_companion_audience_change();

-- Preserve provider/user locks, Been precedence, taxonomy, attributes, and half-step ratings.
create or replace function app.save_own_place(
  input_place jsonb,
  input_user_place jsonb,
  input_attributes jsonb default '[]'::jsonb
)
returns public.user_places
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  private_companion boolean := input_user_place->'is_private_list_companion' = 'true'::jsonb;
  provider text;
  provider_place_id text;
  existing_place_id uuid;
  place_row public.places;
  saved_row public.user_places;
  input_rating_score numeric;
  input_primary_category text;
  input_subcategory text;
  input_category_source text;
  input_category_confidence double precision;
  input_raw_provider_type text;
  input_provider_food_type text;
  updates_provider_taxonomy boolean;
  stored_category_source text;
  input_category_override text;
  input_subcategory_override text;
  input_category_override_source text;
  input_category_override_confidence double precision;
  attr jsonb;
  attr_question_key text;
  attr_value_type text;
  attr_question_definition_id uuid;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  if private_companion and input_user_place->>'status' is distinct from 'wanna_go' then
    raise exception 'invalid_private_companion_status';
  end if;
  if coalesce(jsonb_typeof(input_place), '') <> 'object' then raise exception 'invalid_place_payload'; end if;
  if coalesce(jsonb_typeof(input_user_place), '') <> 'object' then raise exception 'invalid_user_place_payload'; end if;
  if coalesce(jsonb_typeof(input_attributes), 'array') <> 'array' then raise exception 'invalid_attributes_payload'; end if;

  if nullif(input_user_place->>'rating_score', '') is not null then
    input_rating_score := (input_user_place->>'rating_score')::numeric;
  end if;
  if input_rating_score is not null and (
    input_rating_score < 1 or input_rating_score > 5
    or input_rating_score * 2 <> trunc(input_rating_score * 2)
  ) then
    raise exception 'invalid_rating_score';
  end if;

  provider := coalesce(nullif(input_place->>'source_provider', ''), 'manual');
  provider_place_id := nullif(input_place->>'source_provider_place_id', '');
  if provider_place_id is null then
    provider_place_id := 'generated:' || md5(
      provider || ':' || coalesce(input_place->>'canonical_name', '') || ':' ||
      coalesce(input_place->>'latitude', '') || ':' || coalesce(input_place->>'longitude', '')
    );
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'recme:place-provider:' || viewer_id || ':' || provider || ':' || provider_place_id,
      0
    )
  );

  select place.id into existing_place_id
  from public.places place
  where place.source_provider = provider
    and place.source_provider_place_id = provider_place_id;

  if existing_place_id is not null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('recme:user-place:' || viewer_id || ':' || existing_place_id::text, 0)
    );
  end if;

  if input_user_place->>'status' = 'wanna_go' then
    select own.* into saved_row
    from public.places place
    join public.user_places own
      on own.place_id = place.id
     and own.user_id = viewer_id
     and own.deleted_at is null
    where place.source_provider = provider
      and place.source_provider_place_id = provider_place_id
      and (own.status = 'been' or private_companion)
    limit 1;
    if saved_row.id is not null then return saved_row; end if;
  end if;

  input_raw_provider_type := nullif(input_place->>'raw_provider_type', '');
  input_primary_category := app.place_primary_category(
    coalesce(nullif(input_place->>'primary_category', ''), nullif(input_place->>'category', ''), input_raw_provider_type, 'place')
  );
  input_subcategory := app.place_subcategory(
    coalesce(nullif(input_place->>'subcategory', ''), input_raw_provider_type, input_place->>'category'),
    input_primary_category
  );
  input_category_source := lower(coalesce(nullif(input_place->>'category_source', ''), 'legacy'));
  updates_provider_taxonomy := input_category_source in ('provider', 'deterministic', 'ai', 'legacy', 'unknown');
  stored_category_source := case
    when input_category_source in ('provider', 'deterministic', 'ai', 'legacy', 'unknown') then input_category_source
    else 'legacy'
  end;

  if nullif(input_place->>'category_confidence', '') is not null then
    input_category_confidence := greatest(0, least((input_place->>'category_confidence')::double precision, 1));
  else
    input_category_confidence := nullif(input_place->>'confidence', '')::double precision;
  end if;

  if input_primary_category = 'restaurants_food' then
    input_provider_food_type := app.restaurant_cuisine_guess(
      input_raw_provider_type,
      input_subcategory,
      input_primary_category,
      input_place->>'canonical_name',
      null
    );
  end if;

  input_category_override := nullif(input_user_place->>'category_override', '');
  if input_category_override is not null then
    input_category_override := app.place_primary_category(input_category_override);
    input_subcategory_override := app.place_subcategory(
      coalesce(nullif(input_user_place->>'subcategory_override', ''), input_category_override),
      input_category_override
    );
    input_category_override_source := lower(coalesce(nullif(input_user_place->>'category_override_source', ''), 'user'));
    if input_category_override_source not in ('user', 'ai', 'deterministic', 'unknown') then
      input_category_override_source := 'user';
    end if;
    if nullif(input_user_place->>'category_override_confidence', '') is not null then
      input_category_override_confidence := greatest(0, least((input_user_place->>'category_override_confidence')::double precision, 1));
    end if;
  end if;

  insert into public.places (
    canonical_name, category, primary_category, subcategory, category_source,
    category_confidence, raw_provider_type, provider_food_type, address,
    locality, region, country, latitude, longitude, source_provider,
    source_provider_place_id, confidence
  ) values (
    input_place->>'canonical_name', input_primary_category, input_primary_category,
    input_subcategory, stored_category_source, input_category_confidence,
    coalesce(input_raw_provider_type, nullif(input_place->>'category', '')),
    input_provider_food_type, nullif(input_place->>'address', ''),
    nullif(input_place->>'locality', ''), nullif(input_place->>'region', ''),
    nullif(input_place->>'country', ''), (input_place->>'latitude')::double precision,
    (input_place->>'longitude')::double precision, provider, provider_place_id,
    nullif(input_place->>'confidence', '')::double precision
  )
  on conflict (source_provider, source_provider_place_id)
  do update set
    canonical_name = excluded.canonical_name,
    category = case when updates_provider_taxonomy then excluded.primary_category else public.places.category end,
    primary_category = case when updates_provider_taxonomy then excluded.primary_category else public.places.primary_category end,
    subcategory = case when updates_provider_taxonomy then excluded.subcategory else public.places.subcategory end,
    category_source = case when updates_provider_taxonomy then excluded.category_source else public.places.category_source end,
    category_confidence = case when updates_provider_taxonomy then excluded.category_confidence else public.places.category_confidence end,
    raw_provider_type = case when updates_provider_taxonomy then excluded.raw_provider_type else public.places.raw_provider_type end,
    provider_food_type = case when updates_provider_taxonomy then excluded.provider_food_type else public.places.provider_food_type end,
    address = excluded.address,
    locality = excluded.locality,
    region = excluded.region,
    country = excluded.country,
    latitude = excluded.latitude,
    longitude = excluded.longitude,
    confidence = excluded.confidence,
    updated_at = now()
  returning * into place_row;

  if private_companion then
    input_user_place := jsonb_set(input_user_place, '{visibility}', '"self"'::jsonb);
  end if;

  insert into public.user_places (
    user_id, place_id, status, note, rating_signal, rating_score,
    category_override, subcategory_override, category_override_source,
    category_override_confidence, visibility, nearby_confirmed, source_type
  ) values (
    viewer_id, place_row.id, input_user_place->>'status',
    nullif(input_user_place->>'note', ''), nullif(input_user_place->>'rating_signal', ''),
    case when input_user_place->>'status' = 'been' then input_rating_score else null end,
    input_category_override, input_subcategory_override, input_category_override_source,
    input_category_override_confidence, input_user_place->>'visibility',
    coalesce((input_user_place->>'nearby_confirmed')::boolean, false),
    input_user_place->>'source_type'
  )
  on conflict (user_id, place_id)
  do update set
    status = excluded.status,
    note = excluded.note,
    rating_signal = excluded.rating_signal,
    rating_score = excluded.rating_score,
    category_override = excluded.category_override,
    subcategory_override = excluded.subcategory_override,
    category_override_source = excluded.category_override_source,
    category_override_confidence = excluded.category_override_confidence,
    visibility = excluded.visibility,
    nearby_confirmed = excluded.nearby_confirmed,
    source_type = excluded.source_type,
    deleted_at = null,
    updated_at = now()
  returning * into saved_row;

  if private_companion then
    insert into app.private_list_companion_origins(user_place_id) values(saved_row.id)
    on conflict do nothing;
  end if;

  delete from public.place_attributes existing
  where existing.user_place_id = saved_row.id
    and not exists (
      select 1 from jsonb_array_elements(input_attributes) incoming(attr)
      where incoming.attr->>'question_key' = existing.question_key
    );

  for attr in select value from jsonb_array_elements(input_attributes)
  loop
    attr_question_key := nullif(attr->>'question_key', '');
    attr_value_type := nullif(attr->>'value_type', '');
    if attr_question_key is null or attr_value_type is null
       or not (attr ? 'value') or attr->'value' = 'null'::jsonb then
      continue;
    end if;

    select definition.id into attr_question_definition_id
    from public.question_definitions definition
    where definition.question_key = attr_question_key
      and (definition.owner_user_id = viewer_id or definition.is_system)
    order by (definition.owner_user_id = viewer_id) desc, definition.is_system desc
    limit 1;

    insert into public.place_attributes (
      user_place_id, question_definition_id, question_key, value_type, value
    ) values (
      saved_row.id, attr_question_definition_id, attr_question_key,
      attr_value_type, attr->'value'
    )
    on conflict (user_place_id, question_key)
    do update set
      question_definition_id = excluded.question_definition_id,
      value_type = excluded.value_type,
      value = excluded.value,
      updated_at = now();
  end loop;

  return saved_row;
end;
$$;
revoke all on function app.save_own_place(jsonb,jsonb,jsonb) from public, anon;
grant execute on function app.save_own_place(jsonb,jsonb,jsonb) to authenticated;

create or replace function public.save_own_place(
  input_place jsonb,
  input_user_place jsonb,
  input_attributes jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  saved public.user_places;
  requested_planned_date date;
  planned_date_kind text;
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;

  select *
  into saved
  from app.save_own_place(input_place, input_user_place, input_attributes);

  if input_user_place->'is_private_list_companion' = 'true'::jsonb
     or (saved.status = 'been' and input_user_place->>'status' = 'wanna_go') then
    return jsonb_build_object(
      'user_place_id', saved.id,
      'place_id', saved.place_id
    );
  end if;

  if input_user_place ? 'planned_date' then
    planned_date_kind := jsonb_typeof(input_user_place->'planned_date');
    if planned_date_kind not in ('string', 'null') then
      raise exception 'invalid_planned_date';
    end if;

    if planned_date_kind = 'string' then
      begin
        requested_planned_date := (input_user_place->>'planned_date')::date;
      exception
        when invalid_datetime_format or datetime_field_overflow then
          raise exception 'invalid_planned_date';
      end;
    end if;

    if requested_planned_date is not null
       and input_user_place->>'status' <> 'wanna_go' then
      raise exception 'planned_date_requires_wanna_go';
    end if;

    update public.user_places
    set planned_date = requested_planned_date
    where id = saved.id
      and user_id = viewer_id
    returning * into saved;
  end if;

  return jsonb_build_object(
    'user_place_id', saved.id,
    'place_id', saved.place_id
  );
end;
$$;
revoke all on function public.save_own_place(jsonb,jsonb,jsonb) from public, anon;
grant execute on function public.save_own_place(jsonb,jsonb,jsonb) to authenticated;

-- This repair is intentionally restricted to proven origins with no later
-- explicit audience choice. Legacy saves without provenance remain untouched.
create function app.repair_private_list_companions()
returns integer language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare repaired integer;
begin
  update public.user_places saved set visibility = 'self', updated_at = now()
  from app.private_list_companion_origins origin
  where saved.id = origin.user_place_id and origin.audience_changed_at is null
    and saved.status = 'wanna_go' and saved.deleted_at is null and saved.visibility <> 'self';
  get diagnostics repaired = row_count;
  return repaired;
end;
$$;
revoke all on function app.repair_private_list_companions() from public, anon, authenticated;
select app.repair_private_list_companions();

-- Keep acceptance idempotency, validation, copy manifests, and owner-scoped writes.
create or replace function public.accept_shared_visit(
  input_participant_id uuid,
  input_generation integer,
  input_snapshot_revision integer,
  input_operation_id uuid,
  input_user_place_id uuid,
  input_visit_id uuid,
  input_user_place jsonb,
  input_visit jsonb,
  input_attributes jsonb default '[]'::jsonb,
  input_selected_photo_ids uuid[] default array[]::uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  participant_row public.shared_visit_participants;
  shared_group public.shared_visit_groups;
  operation_row public.shared_visit_operations;
  recipient_user_place public.user_places;
  recipient_visit public.place_visits;
  existing_user_place boolean := false;
  previous_status text;
  resolved_source_user_place_id uuid;
  input_visibility text;
  input_rating numeric;
  input_visited_at timestamptz;
  input_note text;
  input_attribute_answers jsonb;
  attr jsonb;
  attr_question_definition_id uuid;
  selected_photo_id uuid;
  source_photo jsonb;
  destination_photo_id uuid;
  destination_path text;
  destination_extension text;
  photo_copies jsonb := '[]'::jsonb;
  generated_backfill_id uuid;
  operation_result jsonb;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  if input_operation_id is null or input_user_place_id is null or input_visit_id is null then
    raise exception 'invalid_shared_visit_operation_identity';
  end if;
  if coalesce(jsonb_typeof(input_user_place), '') <> 'object'
     or coalesce(jsonb_typeof(input_visit), '') <> 'object'
     or coalesce(jsonb_typeof(input_attributes), '') <> 'array' then
    raise exception 'invalid_shared_visit_acceptance_payload';
  end if;

  select * into operation_row
  from public.shared_visit_operations operation
  where operation.participant_id = input_participant_id
    and operation.invitation_generation = input_generation
    and operation.operation_type = 'accept'
  for update;

  if operation_row.status = 'completed' and operation_row.result is not null then
    return app.authorized_photo_copy_manifest(operation_row.result, viewer_id);
  end if;

  select * into participant_row
  from public.shared_visit_participants participant
  where participant.id = input_participant_id
    and participant.user_id = viewer_id
  for update;

  if participant_row.id is null then raise exception 'shared_visit_invitation_not_found'; end if;
  if participant_row.invitation_generation <> input_generation
     or participant_row.snapshot_revision <> input_snapshot_revision then
    raise exception 'stale_shared_visit_invitation';
  end if;

  if participant_row.status = 'accepted' and participant_row.visit_id is not null then
    select result into operation_result
    from public.shared_visit_operations
    where participant_id = participant_row.id
      and invitation_generation = participant_row.invitation_generation
      and operation_type = 'accept'
      and status = 'completed';
    return coalesce(app.authorized_photo_copy_manifest(operation_result, viewer_id), jsonb_build_object(
      'participant_id', participant_row.id,
      'visit_id', participant_row.visit_id,
      'status', participant_row.status,
      'photo_copies', '[]'::jsonb
    ));
  end if;
  if participant_row.status <> 'pending' or participant_row.invitation_snapshot is null then
    raise exception 'shared_visit_invitation_unavailable';
  end if;

  select * into shared_group
  from public.shared_visit_groups
  where id = participant_row.group_id and cancelled_at is null;
  if shared_group.id is null then raise exception 'shared_visit_invitation_unavailable'; end if;

  if exists (
    select 1 from public.profiles profile
    where profile.id = viewer_id and (profile.deleted_at is not null or profile.is_private_profile)
  ) then
    raise exception 'private_profile_prevents_shared_visit';
  end if;

  select source_visit.user_place_id
  into resolved_source_user_place_id
  from public.place_visits source_visit
  join public.user_places source_place on source_place.id = source_visit.user_place_id
  join public.profiles source_owner on source_owner.id = source_place.user_id
  where source_visit.id = shared_group.source_visit_id
    and source_visit.deleted_at is null
    and source_place.deleted_at is null
    and source_place.status = 'been'
    and source_place.visibility <> 'self'
    and app.can_read_visit_source(viewer_id, source_visit.id)
    and source_owner.deleted_at is null
    and not source_owner.is_private_profile;
  if resolved_source_user_place_id is null then raise exception 'shared_visit_invitation_unavailable'; end if;

  input_visibility := coalesce(nullif(input_user_place->>'visibility', ''), 'followers');
  if input_visibility not in ('followers', 'mutuals', 'self') then
    raise exception 'invalid_shared_visit_visibility';
  end if;
  input_note := nullif(input_visit->>'note', '');
  input_visited_at := coalesce(nullif(input_visit->>'visited_at', '')::timestamptz, now());
  input_attribute_answers := coalesce(input_visit->'attribute_answers', '[]'::jsonb);
  if jsonb_typeof(input_attribute_answers) <> 'array' then
    raise exception 'invalid_visit_attribute_answers_payload';
  end if;
  if nullif(input_visit->>'rating_score', '') is not null then
    input_rating := (input_visit->>'rating_score')::numeric;
  end if;
  if input_rating is not null and (
    input_rating < 1 or input_rating > 5 or input_rating * 2 <> trunc(input_rating * 2)
  ) then
    raise exception 'invalid_rating_score';
  end if;

  if exists (
    select 1
    from unnest(coalesce(input_selected_photo_ids, array[]::uuid[])) selected_id
    where not exists (
      select 1
      from jsonb_array_elements(coalesce(participant_row.invitation_snapshot->'photos', '[]'::jsonb)) photo
      where photo->>'photo_id' = selected_id::text
    )
  ) then
    raise exception 'invalid_shared_visit_photo_selection';
  end if;
  if cardinality(coalesce(input_selected_photo_ids, array[]::uuid[])) > 10 then
    raise exception 'shared_visit_photo_limit';
  end if;

  insert into public.shared_visit_operations(
    id, participant_id, user_id, invitation_generation, operation_type, status
  ) values (
    input_operation_id, participant_row.id, viewer_id, input_generation, 'accept', 'started'
  )
  on conflict (participant_id, invitation_generation, operation_type) do nothing;

  select * into operation_row
  from public.shared_visit_operations operation
  where operation.participant_id = participant_row.id
    and operation.invitation_generation = input_generation
    and operation.operation_type = 'accept'
  for update;
  if operation_row.status = 'completed' and operation_row.result is not null then
    return app.authorized_photo_copy_manifest(operation_row.result, viewer_id);
  end if;

  select * into recipient_user_place
  from public.user_places user_place
  where user_place.user_id = viewer_id
    and user_place.place_id = shared_group.place_id
    and user_place.deleted_at is null
  for update;
  existing_user_place := recipient_user_place.id is not null;
  previous_status := recipient_user_place.status;

  if not existing_user_place then
    if exists (select 1 from public.user_places where id = input_user_place_id) then
      raise exception 'shared_visit_user_place_id_conflict';
    end if;

    insert into public.user_places(
      id, user_id, place_id, status, note, rating_score, visibility,
      nearby_confirmed, visited_at, source_type, source_user_place_id,
      attribution_user_id, deleted_at
    ) values (
      input_user_place_id, viewer_id, shared_group.place_id, 'been', input_note,
      input_rating, input_visibility, false, input_visited_at, 'social_save',
      resolved_source_user_place_id, shared_group.owner_user_id, null
    )
    returning * into recipient_user_place;
  else
    update public.user_places
    set status = 'been',
        note = input_note,
        rating_score = input_rating,
        visibility = input_visibility,
        visited_at = input_visited_at,
        source_type = 'social_save',
        source_user_place_id = resolved_source_user_place_id,
        attribution_user_id = shared_group.owner_user_id,
        deleted_at = null,
        updated_at = now()
    where id = recipient_user_place.id
    returning * into recipient_user_place;
  end if;

  delete from public.place_attributes where user_place_id = recipient_user_place.id;
  for attr in select value from jsonb_array_elements(input_attributes)
  loop
    if nullif(attr->>'question_key', '') is null
       or nullif(attr->>'value_type', '') is null
       or not (attr ? 'value')
       or attr->'value' = 'null'::jsonb then
      continue;
    end if;

    select definition.id into attr_question_definition_id
    from public.question_definitions definition
    where definition.question_key = attr->>'question_key'
      and (definition.owner_user_id = viewer_id or definition.is_system)
    order by (definition.owner_user_id = viewer_id) desc, definition.is_system desc
    limit 1;

    insert into public.place_attributes(
      user_place_id, question_definition_id, question_key, value_type, value
    ) values (
      recipient_user_place.id, attr_question_definition_id,
      attr->>'question_key', attr->>'value_type', attr->'value'
    );
  end loop;

  if not existing_user_place or previous_status = 'wanna_go' then
    select visit.id into generated_backfill_id
    from public.place_visits visit
    where visit.user_place_id = recipient_user_place.id
      and visit.backfilled_from_user_place
      and visit.deleted_at is null
    order by visit.created_at desc
    limit 1
    for update;

    if generated_backfill_id is null then
      raise exception 'shared_visit_backfilled_visit_missing';
    end if;
    if input_visit_id <> generated_backfill_id
       and exists (select 1 from public.place_visits where id = input_visit_id) then
      raise exception 'shared_visit_visit_id_conflict';
    end if;

    update public.place_visits
    set id = input_visit_id,
        visited_at = input_visited_at,
        note = input_note,
        rating_score = input_rating,
        attribute_answers = input_attribute_answers,
        updated_at = now()
    where id = generated_backfill_id
    returning * into recipient_visit;

    update public.notification_events
    set data = jsonb_set(data, '{visit_id}', to_jsonb(input_visit_id::text), true),
        updated_at = now()
    where actor_user_id = viewer_id
      and notification_type = 'followed_place_visit'
      and data->>'visit_id' = generated_backfill_id::text
      and status = 'pending';
  else
    if exists (select 1 from public.place_visits where id = input_visit_id) then
      raise exception 'shared_visit_visit_id_conflict';
    end if;
    insert into public.place_visits(
      id, user_place_id, visited_at, note, rating_score,
      attribute_answers, backfilled_from_user_place
    ) values (
      input_visit_id, recipient_user_place.id, input_visited_at, input_note,
      input_rating, input_attribute_answers, false
    )
    returning * into recipient_visit;
  end if;

  foreach selected_photo_id in array coalesce(input_selected_photo_ids, array[]::uuid[]) loop
    select photo into source_photo
    from jsonb_array_elements(coalesce(participant_row.invitation_snapshot->'photos', '[]'::jsonb)) photo
    where photo->>'photo_id' = selected_photo_id::text;

    if not app.can_read_photo_source(viewer_id, selected_photo_id) then
      raise exception 'shared_visit_photo_unavailable';
    end if;
    destination_photo_id := gen_random_uuid();
    destination_extension := case lower(coalesce(source_photo->>'content_type', 'image/jpeg'))
      when 'image/png' then 'png'
      when 'image/heic' then 'heic'
      when 'image/heif' then 'heif'
      when 'image/webp' then 'webp'
      else 'jpg'
    end;
    destination_path := viewer_id || '/' || recipient_visit.id || '/' || destination_photo_id || '.' || destination_extension;

    insert into public.visit_photos(
      id, visit_id, storage_bucket, storage_path, content_type, byte_size,
      width, height, captured_at, sort_order, upload_state
    ) values (
      destination_photo_id,
      recipient_visit.id,
      'visit-photos',
      destination_path,
      coalesce(source_photo->>'content_type', 'image/jpeg'),
      nullif(source_photo->>'byte_size', '')::integer,
      nullif(source_photo->>'width', '')::integer,
      nullif(source_photo->>'height', '')::integer,
      nullif(source_photo->>'captured_at', '')::timestamptz,
      coalesce(nullif(source_photo->>'sort_order', '')::integer, 0),
      'pending_upload'
    );

    insert into app.visit_photo_sources(photo_id, source_photo_id)
    values(destination_photo_id, selected_photo_id);

    photo_copies := photo_copies || jsonb_build_array(jsonb_build_object(
      'source_photo_id', selected_photo_id,
      'source_bucket', source_photo->>'storage_bucket',
      'source_path', source_photo->>'storage_path',
      'destination_photo_id', destination_photo_id,
      'destination_bucket', 'visit-photos',
      'destination_path', destination_path,
      'content_type', coalesce(source_photo->>'content_type', 'image/jpeg')
    ));
  end loop;

  update public.shared_visit_participants
  set status = 'accepted',
      visit_id = recipient_visit.id,
      invitation_snapshot = null,
      responded_at = now(),
      cancelled_at = null,
      updated_at = now()
  where id = participant_row.id
  returning * into participant_row;

  operation_result := jsonb_build_object(
    'operation_id', operation_row.id,
    'participant_id', participant_row.id,
    'user_place_id', recipient_user_place.id,
    'visit_id', recipient_visit.id,
    'backfilled_from_user_place', recipient_visit.backfilled_from_user_place,
    'status', participant_row.status,
    'photo_copies', photo_copies
  );

  update public.shared_visit_operations
  set status = 'completed', result = operation_result, updated_at = now()
  where id = operation_row.id;

  return operation_result;
end;
$$;
revoke all on function public.accept_shared_visit(uuid,integer,integer,uuid,uuid,uuid,jsonb,jsonb,jsonb,uuid[]) from public, anon;
grant execute on function public.accept_shared_visit(uuid,integer,integer,uuid,uuid,uuid,jsonb,jsonb,jsonb,uuid[]) to authenticated;


create or replace function public.activity_media(input_activity_ids uuid[])
returns table(activity_id uuid, media jsonb)
language sql
stable
security definer
set search_path = pg_catalog, public, app
as $$
  select
    event.id as activity_id,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', photo.id,
            'url', null,
            'storage_bucket', photo.storage_bucket,
            'storage_path', photo.storage_path,
            'accessibility_label', 'Activity photo'
          )
          order by photo.sort_order, photo.created_at, photo.id
        )
        from public.visit_photos photo
        where photo.visit_id = event.visit_id
          and photo.upload_state = 'uploaded'
          and photo.deleted_at is null
          and app.can_read_photo_source(app.current_user_id(), photo.id)
      ),
      '[]'::jsonb
    ) as media
  from public.feed_events event
  where event.id = any(coalesce(input_activity_ids, '{}'::uuid[]))
    and app.can_read_activity_event(app.current_user_id(), event.id)
  order by event.occurred_at desc, event.id desc
$$;
revoke all on function public.activity_media(uuid[]) from public, anon;
grant execute on function public.activity_media(uuid[]) to authenticated;



-- The all-user rating exception returns numbers only; it must never expose contributor IDs or reuse a viewer-filtered average.
-- Definer access is deliberate: hidden ratings belong in Astir, while Friends
-- uses the same authoritative visit-access predicate as the underlying activity.
create function app.place_rating_summaries(
  input_place_id uuid default null,
  input_source_provider text default null,
  input_source_provider_place_id text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  viewer_id text := app.current_user_id();
  resolved_place_id uuid := input_place_id;
  result jsonb;
begin
  if viewer_id is null or not exists (
    select 1 from public.profiles where id = viewer_id and deleted_at is null
  ) then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  -- Search results can have a provider ID without a locally cached server ID.
  -- Resolve public place identity independently of any visible activity rows.
  if resolved_place_id is null and nullif(input_source_provider, '') is not null
      and nullif(input_source_provider_place_id, '') is not null then
    select p.id into resolved_place_id from public.places p
    where p.source_provider = input_source_provider
      and p.source_provider_place_id = input_source_provider_place_id;
  end if;

  with ratings as materialized (
    select pv.id, up.user_id, pv.rating_score, author.is_private_profile
    from public.place_visits pv
    join public.user_places up on up.id = pv.user_place_id
    join public.profiles author on author.id = up.user_id
    where up.place_id = resolved_place_id and up.deleted_at is null
      and pv.deleted_at is null and pv.rating_score is not null
      and author.deleted_at is null
  ), followed_people as (
    select user_id, avg(rating_score) as score
    from ratings
    where user_id <> viewer_id and app.follows(viewer_id, user_id)
      and app.can_read_visit_source(viewer_id, id)
    group by user_id
  )
  select jsonb_build_object(
    'own', (select jsonb_build_object('score', round(avg(rating_score), 1), 'count', count(*))
            from ratings where user_id = viewer_id),
    'friends', (select jsonb_build_object('score', round(avg(score), 1), 'count', count(*))
                from followed_people),
    'astir', (select jsonb_build_object('score', round(avg(rating_score), 1), 'count', count(*))
              from ratings)
  ) into result;
  return result;
end;
$$;

revoke all on function app.place_rating_summaries(uuid,text,text) from public, anon, authenticated, service_role;

-- The narrow public wrapper calls the private helper without granting clients
-- helper execution. Caller identity comes from authenticated claims only.
create function public.place_rating_summaries(
  input_place_id uuid default null,
  input_source_provider text default null,
  input_source_provider_place_id text default null
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, app
as $$
  select app.place_rating_summaries(input_place_id, input_source_provider, input_source_provider_place_id)
$$;

revoke all on function public.place_rating_summaries(uuid,text,text) from public, anon, service_role;
grant execute on function public.place_rating_summaries(uuid,text,text) to authenticated;

comment on function public.place_rating_summaries(uuid,text,text) is
  'Authenticated numeric-only own, visible-followed-person, and all-user rating aggregates. Hidden ratings contribute only to Astir.';

commit;
