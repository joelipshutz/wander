begin;

alter table public.profiles
  add column if not exists is_private_profile boolean not null default false;

alter table public.notification_preferences
  add column if not exists shared_visits_enabled boolean not null default true;

alter table public.notification_preferences
  alter column push_enabled set default false,
  alter column social_graph_enabled set default false,
  alter column shared_lists_enabled set default false,
  alter column shared_visits_enabled set default false,
  alter column recommendations_enabled set default false,
  alter column capture_enabled set default false,
  alter column discovery_digest_enabled set default false,
  alter column followed_activity_enabled set default false;

alter table public.notification_events
  drop constraint if exists notification_events_notification_type_check;
alter table public.notification_events
  add constraint notification_events_notification_type_check check (
    notification_type in (
      'followed_you', 'mutual_follow', 'list_collaborator_added',
      'list_place_added', 'place_saved_from_your_map', 'capture_ready',
      'followed_activity_digest', 'followed_place_visit', 'shared_visit'
    )
  );

create table public.shared_visit_groups (
  id uuid primary key default gen_random_uuid(),
  source_visit_id uuid not null unique references public.place_visits(id) on delete cascade,
  place_id uuid not null references public.places(id) on delete cascade,
  owner_user_id text not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  cancelled_at timestamptz
);

create table public.shared_visit_participants (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.shared_visit_groups(id) on delete cascade,
  user_id text not null references public.profiles(id) on delete cascade,
  invited_by_user_id text not null references public.profiles(id) on delete cascade,
  status text not null check (status in ('owner', 'pending', 'accepted', 'declined', 'cancelled', 'expired', 'removed')),
  invitation_generation integer not null default 1 check (invitation_generation > 0),
  snapshot_revision integer not null default 1 check (snapshot_revision > 0),
  invitation_snapshot jsonb check (
    invitation_snapshot is null or jsonb_typeof(invitation_snapshot) = 'object'
  ),
  visit_id uuid references public.place_visits(id) on delete set null,
  invited_at timestamptz not null default now(),
  responded_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (group_id, user_id),
  check ((status = 'owner' and visit_id is not null) or status <> 'owner')
);

create table public.shared_visit_operations (
  id uuid primary key,
  participant_id uuid not null references public.shared_visit_participants(id) on delete cascade,
  user_id text not null references public.profiles(id) on delete cascade,
  invitation_generation integer not null check (invitation_generation > 0),
  operation_type text not null check (operation_type in ('accept')),
  status text not null default 'started' check (status in ('started', 'completed')),
  result jsonb check (result is null or jsonb_typeof(result) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (participant_id, invitation_generation, operation_type)
);

create unique index shared_visit_participants_visit_idx
  on public.shared_visit_participants(visit_id)
  where visit_id is not null;

create index shared_visit_participants_inbox_idx
  on public.shared_visit_participants(user_id, status, invited_at desc);

create index shared_visit_participants_group_status_idx
  on public.shared_visit_participants(group_id, status, invited_at);

create index shared_visit_groups_owner_idx
  on public.shared_visit_groups(owner_user_id, created_at desc)
  where cancelled_at is null;

drop trigger if exists shared_visit_groups_set_updated_at on public.shared_visit_groups;
create trigger shared_visit_groups_set_updated_at
  before update on public.shared_visit_groups
  for each row execute function app.set_updated_at();

drop trigger if exists shared_visit_participants_set_updated_at on public.shared_visit_participants;
create trigger shared_visit_participants_set_updated_at
  before update on public.shared_visit_participants
  for each row execute function app.set_updated_at();

drop trigger if exists shared_visit_operations_set_updated_at on public.shared_visit_operations;
create trigger shared_visit_operations_set_updated_at
  before update on public.shared_visit_operations
  for each row execute function app.set_updated_at();

alter table public.shared_visit_groups enable row level security;
alter table public.shared_visit_participants enable row level security;
alter table public.shared_visit_operations enable row level security;

-- No direct client policies are intentional. All reads and writes cross narrow,
-- authenticated RPCs so terminal invitation snapshots cannot leak through RLS.

create or replace function app.notification_type_enabled(
  input_preferences public.notification_preferences,
  input_notification_type text
)
returns boolean
language sql
stable
security definer
set search_path = public, app
as $$
  select coalesce(input_preferences.push_enabled, false)
    and case
      when input_notification_type in ('followed_you', 'mutual_follow') then input_preferences.social_graph_enabled
      when input_notification_type in ('list_collaborator_added', 'list_place_added') then input_preferences.shared_lists_enabled
      when input_notification_type = 'shared_visit' then input_preferences.shared_visits_enabled
      when input_notification_type = 'place_saved_from_your_map' then input_preferences.recommendations_enabled
      when input_notification_type = 'capture_ready' then input_preferences.capture_enabled
      when input_notification_type = 'followed_activity_digest' then input_preferences.discovery_digest_enabled
      when input_notification_type = 'followed_place_visit' then input_preferences.followed_activity_enabled
      else false
    end
$$;

create or replace function app.queue_notification_event(
  input_recipient_user_id text,
  input_actor_user_id text,
  input_notification_type text,
  input_title text,
  input_body text,
  input_deeplink_url text default null,
  input_data jsonb default '{}'::jsonb,
  input_dedupe_key text default null,
  input_not_before timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public, app
as $$
declare
  recipient_preferences public.notification_preferences;
  output_event_id uuid;
  actor_is_muted boolean := false;
begin
  if input_recipient_user_id is null or input_recipient_user_id = '' then return null; end if;
  if input_actor_user_id is not null and input_actor_user_id = input_recipient_user_id then return null; end if;
  if input_notification_type not in (
    'followed_you', 'mutual_follow', 'list_collaborator_added',
    'list_place_added', 'place_saved_from_your_map', 'capture_ready',
    'followed_activity_digest', 'followed_place_visit', 'shared_visit'
  ) then raise exception 'invalid_notification_type'; end if;
  if coalesce(jsonb_typeof(coalesce(input_data, '{}'::jsonb)), '') <> 'object' then
    raise exception 'invalid_notification_data';
  end if;
  if not exists (
    select 1 from public.profiles profile
    where profile.id = input_recipient_user_id and profile.deleted_at is null
  ) then return null; end if;
  if input_actor_user_id is not null then
    if not exists (
      select 1 from public.profiles profile
      where profile.id = input_actor_user_id and profile.deleted_at is null
    ) then return null; end if;
    if app.is_blocked(input_recipient_user_id, input_actor_user_id) then return null; end if;
    if to_regclass('public.profile_mutes') is not null then
      execute
        'select exists (
           select 1 from public.profile_mutes
           where muter_user_id = $1 and muted_user_id = $2
         )'
      into actor_is_muted
      using input_recipient_user_id, input_actor_user_id;
      if actor_is_muted then return null; end if;
    end if;
  end if;
  if not exists (
    select 1 from public.notification_device_tokens token
    where token.user_id = input_recipient_user_id and token.is_active
  ) then return null; end if;

  recipient_preferences := app.ensure_notification_preferences(input_recipient_user_id);
  if not app.notification_type_enabled(recipient_preferences, input_notification_type) then return null; end if;

  if input_dedupe_key is not null then
    select id into output_event_id from public.notification_events
    where dedupe_key = input_dedupe_key and status in ('pending', 'claimed')
    order by created_at desc limit 1;
    if output_event_id is not null then return output_event_id; end if;
  end if;

  insert into public.notification_events(
    recipient_user_id, actor_user_id, notification_type, title, body,
    deeplink_url, data, dedupe_key, not_before
  ) values (
    input_recipient_user_id, input_actor_user_id, input_notification_type,
    left(trim(input_title), 120), left(trim(input_body), 240),
    nullif(trim(coalesce(input_deeplink_url, '')), ''), coalesce(input_data, '{}'::jsonb),
    nullif(trim(coalesce(input_dedupe_key, '')), ''), coalesce(input_not_before, now())
  ) returning id into output_event_id;
  return output_event_id;
end;
$$;

create or replace function public.update_notification_preferences(input_preferences jsonb)
returns public.notification_preferences
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  output_preferences public.notification_preferences;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  if coalesce(jsonb_typeof(input_preferences), '') <> 'object' then
    raise exception 'invalid_notification_preferences_payload';
  end if;

  perform app.ensure_notification_preferences(viewer_id);
  update public.notification_preferences set
    push_enabled = coalesce((input_preferences->>'push_enabled')::boolean, push_enabled),
    social_graph_enabled = coalesce((input_preferences->>'social_graph_enabled')::boolean, social_graph_enabled),
    shared_lists_enabled = coalesce((input_preferences->>'shared_lists_enabled')::boolean, shared_lists_enabled),
    shared_visits_enabled = coalesce((input_preferences->>'shared_visits_enabled')::boolean, shared_visits_enabled),
    recommendations_enabled = coalesce((input_preferences->>'recommendations_enabled')::boolean, recommendations_enabled),
    capture_enabled = coalesce((input_preferences->>'capture_enabled')::boolean, capture_enabled),
    discovery_digest_enabled = coalesce((input_preferences->>'discovery_digest_enabled')::boolean, discovery_digest_enabled),
    followed_activity_enabled = coalesce((input_preferences->>'followed_activity_enabled')::boolean, followed_activity_enabled)
  where user_id = viewer_id
  returning * into output_preferences;
  return output_preferences;
end;
$$;

with ranked_tokens as (
  select
    id,
    row_number() over (
      partition by environment, app_bundle_id, token_hash
      order by is_active desc, last_registered_at desc, created_at desc, id desc
    ) as token_rank
  from public.notification_device_tokens
)
update public.notification_device_tokens token
set is_active = false, updated_at = now()
from ranked_tokens ranked
where token.id = ranked.id
  and ranked.token_rank > 1
  and token.is_active;

create unique index if not exists notification_device_tokens_active_device_idx
  on public.notification_device_tokens(environment, app_bundle_id, token_hash)
  where is_active;

create or replace function public.register_push_token(
  input_device_token text,
  input_environment text default 'production',
  input_app_bundle_id text default 'com.grayline.wander'
)
returns uuid
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  normalized_token text := lower(trim(coalesce(input_device_token, '')));
  normalized_environment text := lower(trim(coalesce(input_environment, 'production')));
  normalized_bundle_id text := coalesce(nullif(trim(input_app_bundle_id), ''), 'com.grayline.wander');
  normalized_token_hash text;
  output_id uuid;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  if normalized_environment not in ('sandbox', 'production') then raise exception 'invalid_push_environment'; end if;
  if length(normalized_token) not between 32 and 512 or normalized_token !~ '^[a-f0-9]+$' then
    raise exception 'invalid_push_token';
  end if;

  normalized_token_hash := encode(extensions.digest(normalized_token, 'sha256'), 'hex');
  perform app.ensure_notification_preferences(viewer_id);

  update public.notification_device_tokens
  set is_active = false, updated_at = now()
  where environment = normalized_environment
    and app_bundle_id = normalized_bundle_id
    and token_hash = normalized_token_hash
    and user_id <> viewer_id
    and is_active;

  insert into public.notification_device_tokens(
    user_id, platform, environment, app_bundle_id, device_token,
    is_active, last_registered_at, last_seen_at
  ) values (
    viewer_id, 'ios', normalized_environment, normalized_bundle_id,
    normalized_token, true, now(), now()
  )
  on conflict (user_id, platform, environment, token_hash)
  do update set
    app_bundle_id = excluded.app_bundle_id,
    device_token = excluded.device_token,
    is_active = true,
    last_registered_at = now(),
    last_seen_at = now()
  returning id into output_id;

  return output_id;
end;
$$;

create or replace function app.shared_visit_source_snapshot(input_source_visit_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, app
as $$
  select jsonb_build_object(
    'visited_at', source_visit.visited_at,
    'note', source_visit.note,
    'rating_score', source_visit.rating_score,
    'attribute_answers', source_visit.attribute_answers,
    'tags', to_jsonb(source_visit.tags),
    'photos', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'photo_id', photo.id,
          'storage_bucket', photo.storage_bucket,
          'storage_path', photo.storage_path,
          'content_type', photo.content_type,
          'byte_size', photo.byte_size,
          'width', photo.width,
          'height', photo.height,
          'captured_at', photo.captured_at,
          'sort_order', photo.sort_order
        ) order by photo.sort_order, photo.created_at
      )
      from public.visit_photos photo
      where photo.visit_id = source_visit.id
        and photo.deleted_at is null
        and photo.upload_state = 'uploaded'
    ), '[]'::jsonb)
  )
  from public.place_visits source_visit
  where source_visit.id = input_source_visit_id
    and source_visit.deleted_at is null
$$;

create or replace function public.create_shared_visit_invites(
  input_source_visit_id uuid,
  input_invitee_user_ids text[]
)
returns table (
  participant_id uuid,
  invitee_user_id text,
  participant_status text,
  invitation_generation integer
)
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  source_row record;
  shared_group public.shared_visit_groups;
  invitee_id text;
  participant_row public.shared_visit_participants;
  prior_status text;
  normalized_invitee_ids text[];
  invalid_invitee_ids text[];
  projected_participant_count integer;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;

  select array_agg(distinct invitee order by invitee)
  into normalized_invitee_ids
  from unnest(coalesce(input_invitee_user_ids, array[]::text[])) invitee
  where nullif(btrim(invitee), '') is not null;

  if coalesce(cardinality(normalized_invitee_ids), 0) = 0 then
    raise exception 'shared_visit_invitees_required';
  end if;
  if cardinality(normalized_invitee_ids) > 19 then
    raise exception 'shared_visit_participant_limit';
  end if;

  select
    source_visit.id as source_visit_id,
    user_place.place_id,
    user_place.visibility,
    place.canonical_name,
    owner.display_name as owner_display_name
  into source_row
  from public.place_visits source_visit
  join public.user_places user_place on user_place.id = source_visit.user_place_id
  join public.places place on place.id = user_place.place_id
  join public.profiles owner on owner.id = user_place.user_id
  where source_visit.id = input_source_visit_id
    and source_visit.deleted_at is null
    and user_place.deleted_at is null
    and user_place.user_id = viewer_id
    and user_place.status = 'been'
    and user_place.visibility <> 'self'
    and owner.deleted_at is null
    and not owner.is_private_profile;

  if source_row.source_visit_id is null then
    raise exception 'shared_visit_source_unavailable';
  end if;

  select array_agg(invitee)
  into invalid_invitee_ids
  from unnest(normalized_invitee_ids) invitee
  where invitee = viewer_id
    or not exists (
      select 1 from public.profiles profile
      where profile.id = invitee
        and profile.deleted_at is null
        and not profile.is_private_profile
    )
    or not app.is_mutual(viewer_id, invitee)
    or app.is_blocked(viewer_id, invitee);

  if coalesce(cardinality(invalid_invitee_ids), 0) > 0 then
    raise exception 'invalid_shared_visit_invitees';
  end if;

  insert into public.shared_visit_groups(
    source_visit_id, place_id, owner_user_id, cancelled_at
  ) values (
    source_row.source_visit_id,
    source_row.place_id,
    viewer_id,
    null
  )
  on conflict (source_visit_id) do update set
    cancelled_at = null,
    updated_at = now()
  returning * into shared_group;

  insert into public.shared_visit_participants(
    group_id, user_id, invited_by_user_id, status, snapshot_revision,
    invitation_snapshot, visit_id, responded_at
  ) values (
    shared_group.id, viewer_id, viewer_id, 'owner', 1,
    null, source_row.source_visit_id, now()
  )
  on conflict (group_id, user_id) do update set
    status = 'owner',
    visit_id = excluded.visit_id,
    responded_at = coalesce(public.shared_visit_participants.responded_at, now()),
    cancelled_at = null,
    updated_at = now();

  select count(distinct participant_user_id)
  into projected_participant_count
  from (
    select participant.user_id as participant_user_id
    from public.shared_visit_participants participant
    where participant.group_id = shared_group.id
      and participant.status in ('owner', 'pending', 'accepted')
    union
    select unnest(normalized_invitee_ids)
  ) projected;

  if projected_participant_count > 20 then
    raise exception 'shared_visit_participant_limit';
  end if;

  foreach invitee_id in array normalized_invitee_ids loop
    select participant.status
    into prior_status
    from public.shared_visit_participants participant
    where participant.group_id = shared_group.id
      and participant.user_id = invitee_id
    for update;

    insert into public.shared_visit_participants(
      group_id, user_id, invited_by_user_id, status, invitation_generation,
      snapshot_revision, invitation_snapshot, visit_id, invited_at, responded_at, cancelled_at
    ) values (
      shared_group.id, invitee_id, viewer_id, 'pending', 1,
      1, app.shared_visit_source_snapshot(source_row.source_visit_id), null, now(), null, null
    )
    on conflict (group_id, user_id) do update set
      invited_by_user_id = excluded.invited_by_user_id,
      status = case
        when public.shared_visit_participants.status in ('declined', 'cancelled', 'expired', 'removed') then 'pending'
        else public.shared_visit_participants.status
      end,
      invitation_generation = case
        when public.shared_visit_participants.status in ('declined', 'cancelled', 'expired', 'removed')
          then public.shared_visit_participants.invitation_generation + 1
        else public.shared_visit_participants.invitation_generation
      end,
      snapshot_revision = case
        when public.shared_visit_participants.status in ('declined', 'cancelled', 'expired', 'removed')
          then public.shared_visit_participants.snapshot_revision + 1
        else public.shared_visit_participants.snapshot_revision
      end,
      invitation_snapshot = case
        when public.shared_visit_participants.status in ('declined', 'cancelled', 'expired', 'removed')
          then app.shared_visit_source_snapshot(source_row.source_visit_id)
        else public.shared_visit_participants.invitation_snapshot
      end,
      visit_id = case
        when public.shared_visit_participants.status in ('declined', 'cancelled', 'expired', 'removed') then null
        else public.shared_visit_participants.visit_id
      end,
      invited_at = case
        when public.shared_visit_participants.status in ('declined', 'cancelled', 'expired', 'removed') then now()
        else public.shared_visit_participants.invited_at
      end,
      responded_at = case
        when public.shared_visit_participants.status in ('declined', 'cancelled', 'expired', 'removed') then null
        else public.shared_visit_participants.responded_at
      end,
      cancelled_at = null,
      updated_at = now()
    returning * into participant_row;

    if prior_status is null or prior_status in ('declined', 'cancelled', 'expired', 'removed') then
      update public.notification_events
      set status = 'skipped',
          skip_reason = 'shared_visit_superseded',
          updated_at = now()
      where recipient_user_id = invitee_id
        and actor_user_id = viewer_id
        and notification_type = 'followed_place_visit'
        and data->>'visit_id' = source_row.source_visit_id::text
        and status = 'pending';

      perform app.queue_notification_event(
        input_recipient_user_id := invitee_id,
        input_actor_user_id := viewer_id,
        input_notification_type := 'shared_visit',
        input_title := 'Shared visit',
        input_body := source_row.owner_display_name || ' saved ' || source_row.canonical_name || ' with you. Add your version of the visit.',
        input_deeplink_url := 'recme://shared-visits/' || participant_row.id || '?generation=' || participant_row.invitation_generation,
        input_data := jsonb_build_object(
          'participant_id', participant_row.id,
          'invitation_generation', participant_row.invitation_generation,
          'group_id', shared_group.id,
          'source_visit_id', source_row.source_visit_id,
          'place_id', source_row.place_id,
          'actor_user_id', viewer_id
        ),
        input_dedupe_key := 'shared_visit:' || participant_row.id || ':' || participant_row.invitation_generation
      );
    end if;
  end loop;

  return query
  select participant.id, participant.user_id, participant.status, participant.invitation_generation
  from public.shared_visit_participants participant
  where participant.group_id = shared_group.id
    and participant.user_id = any(normalized_invitee_ids)
  order by participant.invited_at, participant.user_id;
end;
$$;

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
    participant.invitation_snapshot
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
    and (input_before is null or participant.invited_at < input_before)
  order by participant.invited_at desc, participant.id
  limit greatest(1, least(coalesce(input_limit, 50), 50))
$$;

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
    participant.invitation_snapshot
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
$$;

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
    return operation_row.result;
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
    return coalesce(operation_result, jsonb_build_object(
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
    return operation_row.result;
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

create or replace function public.decline_shared_visit(
  input_participant_id uuid,
  input_generation integer
)
returns boolean
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;

  update public.shared_visit_participants
  set status = 'declined', invitation_snapshot = null, responded_at = now(), updated_at = now()
  where id = input_participant_id
    and user_id = viewer_id
    and invitation_generation = input_generation
    and status = 'pending';

  if found then return true; end if;
  if exists (
    select 1 from public.shared_visit_participants
    where id = input_participant_id
      and user_id = viewer_id
      and invitation_generation = input_generation
      and status = 'declined'
  ) then return true; end if;

  raise exception 'shared_visit_invitation_unavailable';
end;
$$;

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
        and shared_group.cancelled_at is null then 'pending'
      when participant.status = 'accepted' and participant.visit_id is not null then 'accepted'
      else participant.status
    end,
    shared_group.place_id,
    participant.visit_id,
    shared_group.source_visit_id
  from public.shared_visit_participants participant
  join public.shared_visit_groups shared_group on shared_group.id = participant.group_id
  where participant.id = input_participant_id
    and participant.user_id = app.current_user_id()
$$;

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
    select visit.id
    from public.place_visits visit
    join public.user_places user_place on user_place.id = visit.user_place_id
    where visit.id = any(coalesce(input_visit_ids, array[]::uuid[]))
      and visit.deleted_at is null
      and user_place.deleted_at is null
      and user_place.user_id = app.current_user_id()
    limit 50
  ), resolved_groups as (
    select requested.id as requested_visit_id, shared_group.id as group_id
    from requested_visits requested
    join public.shared_visit_groups shared_group on shared_group.source_visit_id = requested.id
    where shared_group.cancelled_at is null
    union all
    select requested.id, participant.group_id
    from requested_visits requested
    join public.shared_visit_participants participant on participant.visit_id = requested.id
    join public.shared_visit_groups shared_group on shared_group.id = participant.group_id
    where participant.status = 'accepted' and shared_group.cancelled_at is null
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
  where companion.status in ('owner', 'accepted')
    and companion.user_id <> app.current_user_id()
    and not app.is_blocked(app.current_user_id(), companion.user_id)
    and profile.deleted_at is null
    and not profile.is_private_profile
    and (
      companion.status = 'owner'
      or (
        companion_visit.deleted_at is null
        and companion_place.deleted_at is null
        and companion_place.visibility <> 'self'
        and app.can_read_user_place(app.current_user_id(), companion.user_id, companion_place.visibility)
      )
    )
  order by resolved.requested_visit_id, profile.display_name, profile.id
$$;

create or replace function app.cancel_shared_visit_groups_for_user_place(input_user_place_id uuid)
returns void
language plpgsql
security definer
set search_path = public, app
as $$
begin
  update public.shared_visit_groups shared_group
  set cancelled_at = coalesce(shared_group.cancelled_at, now()), updated_at = now()
  where shared_group.source_visit_id in (
    select visit.id from public.place_visits visit where visit.user_place_id = input_user_place_id
  );

  update public.shared_visit_participants participant
  set status = 'cancelled', invitation_snapshot = null,
      cancelled_at = coalesce(participant.cancelled_at, now()), updated_at = now()
  where participant.group_id in (
    select shared_group.id
    from public.shared_visit_groups shared_group
    where shared_group.source_visit_id in (
      select visit.id from public.place_visits visit where visit.user_place_id = input_user_place_id
    )
  )
    and participant.status in ('pending', 'accepted');
end;
$$;

create or replace function app.cancel_shared_visits_after_user_place_change()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
begin
  if new.deleted_at is not null or new.status <> 'been' or new.visibility = 'self' then
    perform app.cancel_shared_visit_groups_for_user_place(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists user_places_cancel_shared_visits on public.user_places;
create trigger user_places_cancel_shared_visits
  after update of status, visibility, deleted_at on public.user_places
  for each row execute function app.cancel_shared_visits_after_user_place_change();

create or replace function app.cancel_shared_visits_after_block()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
begin
  with cancelled_participants as (
    update public.shared_visit_participants participant
    set status = 'cancelled', invitation_snapshot = null,
        cancelled_at = coalesce(participant.cancelled_at, now()), updated_at = now()
    from public.shared_visit_groups shared_group
    where participant.group_id = shared_group.id
      and participant.status in ('pending', 'accepted')
      and (
        (shared_group.owner_user_id = new.blocker_user_id and participant.user_id = new.blocked_user_id)
        or
        (shared_group.owner_user_id = new.blocked_user_id and participant.user_id = new.blocker_user_id)
      )
    returning participant.id
  )
  update public.notification_events event
  set status = 'skipped', skip_reason = 'blocked', claim_expires_at = null, updated_at = now()
  where event.notification_type = 'shared_visit'
    and event.status in ('pending', 'claimed')
    and event.data->>'participant_id' in (
      select cancelled.id::text from cancelled_participants cancelled
    );

  return new;
end;
$$;

drop trigger if exists blocks_cancel_shared_visits on public.blocks;
create trigger blocks_cancel_shared_visits
  after insert on public.blocks
  for each row execute function app.cancel_shared_visits_after_block();

create or replace function app.apply_private_profile_shared_visit_rules()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
begin
  if new.is_private_profile and not old.is_private_profile then
    update public.user_places
    set visibility = 'self', updated_at = now()
    where user_id = new.id and deleted_at is null and visibility <> 'self';

    update public.shared_visit_groups
    set cancelled_at = coalesce(cancelled_at, now()), updated_at = now()
    where owner_user_id = new.id and cancelled_at is null;

    update public.shared_visit_participants
    set status = 'cancelled', invitation_snapshot = null,
        cancelled_at = coalesce(cancelled_at, now()), updated_at = now()
    where (user_id = new.id or invited_by_user_id = new.id)
      and status in ('pending', 'accepted');
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_apply_private_shared_visit_rules on public.profiles;
create trigger profiles_apply_private_shared_visit_rules
  after update of is_private_profile on public.profiles
  for each row execute function app.apply_private_profile_shared_visit_rules();

create or replace function public.update_profile_privacy(
  input_is_private_profile boolean,
  input_default_visibility text default null
)
returns public.profiles
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  updated_profile public.profiles;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  if input_default_visibility is not null and input_default_visibility not in ('followers', 'mutuals', 'self') then
    raise exception 'invalid_default_visibility';
  end if;

  update public.profiles
  set is_private_profile = input_is_private_profile,
      default_visibility = coalesce(input_default_visibility, default_visibility),
      updated_at = now()
  where id = viewer_id and deleted_at is null
  returning * into updated_profile;

  if updated_profile.id is null then raise exception 'profile_not_found'; end if;
  return updated_profile;
end;
$$;

drop function if exists public.current_profile();
drop function if exists app.current_profile();

create function app.current_profile()
returns table (
  id text,
  handle text,
  display_name text,
  avatar_url text,
  bio text,
  home_area text,
  default_visibility text,
  is_private_profile boolean,
  created_at timestamptz
)
language sql
stable
security invoker
set search_path = public, app
as $$
  select
    profile.id,
    profile.handle,
    profile.display_name,
    profile.avatar_url,
    profile.bio,
    profile.home_area,
    profile.default_visibility,
    profile.is_private_profile,
    profile.created_at
  from public.profiles profile
  where profile.id = app.current_user_id()
    and profile.deleted_at is null
$$;

create function public.current_profile()
returns table (
  id text,
  handle text,
  display_name text,
  avatar_url text,
  bio text,
  home_area text,
  default_visibility text,
  is_private_profile boolean,
  created_at timestamptz
)
language sql
stable
security invoker
set search_path = app, public
as $$
  select * from app.current_profile()
$$;

-- Delay generic followed-place pushes long enough for the save flow to replace
-- one with the more specific shared-visit notification.
create or replace function app.notify_followed_place_visit_insert()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
declare
  activity record;
  follower record;
  actor_name text;
begin
  if new.deleted_at is not null then return new; end if;

  select up.user_id, up.place_id, up.visibility, place.canonical_name,
         profile.display_name, profile.handle
  into activity
  from public.user_places up
  join public.places place on place.id = up.place_id
  join public.profiles profile on profile.id = up.user_id and profile.deleted_at is null
  where up.id = new.user_place_id
    and up.deleted_at is null
    and up.status = 'been';

  if activity.user_id is null then return new; end if;
  actor_name := coalesce(nullif(btrim(activity.display_name), ''), '@' || activity.handle);

  for follower in
    select follow.follower_user_id
    from public.follows follow
    where follow.followed_user_id = activity.user_id
      and app.can_read_user_place(follow.follower_user_id, activity.user_id, activity.visibility)
  loop
    perform app.queue_notification_event(
      input_recipient_user_id := follower.follower_user_id,
      input_actor_user_id := activity.user_id,
      input_notification_type := 'followed_place_visit',
      input_title := actor_name || ' saved a place',
      input_body := activity.canonical_name,
      input_deeplink_url := 'recme://places/' || activity.place_id,
      input_data := jsonb_build_object(
        'visit_id', new.id,
        'user_place_id', new.user_place_id,
        'place_id', activity.place_id,
        'actor_user_id', activity.user_id
      ),
      input_dedupe_key := 'followed_place_visit:' || new.id || ':' || follower.follower_user_id,
      input_not_before := now() + interval '2 minutes'
    );
  end loop;
  return new;
end;
$$;

revoke all on public.shared_visit_groups from public, anon, authenticated;
revoke all on public.shared_visit_participants from public, anon, authenticated;
revoke all on public.shared_visit_operations from public, anon, authenticated;

revoke all on function app.shared_visit_source_snapshot(uuid) from public, anon, authenticated;
revoke all on function app.cancel_shared_visit_groups_for_user_place(uuid) from public, anon, authenticated;
revoke all on function app.cancel_shared_visits_after_user_place_change() from public, anon, authenticated;
revoke all on function app.cancel_shared_visits_after_block() from public, anon, authenticated;
revoke all on function app.apply_private_profile_shared_visit_rules() from public, anon, authenticated;
revoke all on function app.current_profile() from public, anon;
revoke all on function public.current_profile() from public, anon;
revoke all on function public.create_shared_visit_invites(uuid, text[]) from public, anon;
revoke all on function public.list_shared_visit_inbox(timestamptz, integer) from public, anon;
revoke all on function public.get_shared_visit_context(uuid, integer) from public, anon;
revoke all on function public.accept_shared_visit(uuid, integer, integer, uuid, uuid, uuid, jsonb, jsonb, jsonb, uuid[]) from public, anon;
revoke all on function public.decline_shared_visit(uuid, integer) from public, anon;
revoke all on function public.resolve_shared_visit_destination(uuid, integer) from public, anon;
revoke all on function public.get_shared_visit_companion_context(uuid[]) from public, anon;
revoke all on function public.update_profile_privacy(boolean, text) from public, anon;

grant execute on function app.current_profile() to authenticated;
grant execute on function public.current_profile() to authenticated;
grant execute on function public.create_shared_visit_invites(uuid, text[]) to authenticated;
grant execute on function public.list_shared_visit_inbox(timestamptz, integer) to authenticated;
grant execute on function public.get_shared_visit_context(uuid, integer) to authenticated;
grant execute on function public.accept_shared_visit(uuid, integer, integer, uuid, uuid, uuid, jsonb, jsonb, jsonb, uuid[]) to authenticated;
grant execute on function public.decline_shared_visit(uuid, integer) to authenticated;
grant execute on function public.resolve_shared_visit_destination(uuid, integer) to authenticated;
grant execute on function public.get_shared_visit_companion_context(uuid[]) to authenticated;
grant execute on function public.update_profile_privacy(boolean, text) to authenticated;

comment on table public.shared_visit_groups is
  'One real-world shared occasion rooted in one persisted source visit; private snapshots live only on pending participant generations.';
comment on table public.shared_visit_participants is
  'Per-user invitation state and independently owned accepted visit link for a shared occasion.';
comment on table public.shared_visit_operations is
  'Exactly-once acceptance ledger keyed by participant generation and client operation identity.';
comment on function public.create_shared_visit_invites(uuid, text[]) is
  'Creates idempotent mutual-friend invitations for the authenticated owner of a visible Been visit.';
comment on function public.accept_shared_visit(uuid, integer, integer, uuid, uuid, uuid, jsonb, jsonb, jsonb, uuid[]) is
  'Atomically creates one recipient-owned save/visit and copy plan for the exact invitation snapshot generation.';

commit;
