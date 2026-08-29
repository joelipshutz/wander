begin;

-- REC-357: immutable Wanna moments plus an optional multi-person plan. The
-- existing user_places row remains a compatibility summary for map/profile.
create table public.place_wanna_events (
  id uuid primary key,
  user_id text not null references public.profiles(id) on delete cascade,
  place_id uuid not null references public.places(id) on delete cascade,
  user_place_id uuid not null references public.user_places(id) on delete cascade,
  state text not null default 'active'
    check (state in ('active', 'fulfilled', 'removed')),
  source text not null default 'direct'
    check (source in ('direct', 'plan_acceptance', 'import', 'legacy')),
  was_visited_before boolean not null default false,
  visibility text not null check (visibility in ('followers', 'mutuals', 'self')),
  note_snapshot text,
  planned_date date,
  occurred_at timestamptz not null default now(),
  fulfilled_at timestamptz,
  fulfilled_by_visit_id uuid references public.place_visits(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (state = 'active' and fulfilled_at is null and fulfilled_by_visit_id is null)
    or state in ('fulfilled', 'removed')
  )
);

create table public.place_plans (
  id uuid primary key,
  creator_user_id text not null references public.profiles(id) on delete cascade,
  place_id uuid not null references public.places(id) on delete cascade,
  creator_wanna_event_id uuid not null unique
    references public.place_wanna_events(id) on delete cascade,
  planned_date date,
  sharing text not null check (sharing in ('feed', 'private')),
  status text not null default 'active' check (status in ('active', 'cancelled')),
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (status = 'active' and cancelled_at is null)
    or (status = 'cancelled' and cancelled_at is not null)
  )
);

create table public.place_plan_participants (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.place_plans(id) on delete cascade,
  user_id text not null references public.profiles(id) on delete cascade,
  role text not null check (role in ('creator', 'invitee')),
  state text not null check (
    state in ('pending', 'accepted', 'declined', 'left', 'cancelled', 'removed')
  ),
  invitation_generation integer not null default 1 check (invitation_generation > 0),
  participant_wanna_event_id uuid references public.place_wanna_events(id) on delete set null,
  invited_at timestamptz not null default now(),
  responded_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (plan_id, user_id),
  check ((role = 'creator' and state = 'accepted') or role = 'invitee')
);

create table public.place_plan_operations (
  id uuid primary key,
  participant_id uuid not null references public.place_plan_participants(id) on delete cascade,
  user_id text not null references public.profiles(id) on delete cascade,
  invitation_generation integer not null check (invitation_generation > 0),
  operation_type text not null check (operation_type = 'accept'),
  result jsonb not null check (jsonb_typeof(result) = 'object'),
  created_at timestamptz not null default now(),
  unique (participant_id, invitation_generation, operation_type)
);

create index place_wanna_events_owner_place_state_idx
  on public.place_wanna_events(user_id, place_id, state, occurred_at desc);
create index place_wanna_events_user_place_state_idx
  on public.place_wanna_events(user_place_id, state, occurred_at desc);
create index place_plans_creator_status_idx
  on public.place_plans(creator_user_id, status, created_at desc);
create index place_plan_participants_inbox_idx
  on public.place_plan_participants(user_id, state, invited_at desc);
create index place_plan_participants_plan_state_idx
  on public.place_plan_participants(plan_id, state, invited_at);

drop trigger if exists place_wanna_events_set_updated_at on public.place_wanna_events;
create trigger place_wanna_events_set_updated_at before update on public.place_wanna_events
  for each row execute function app.set_updated_at();
drop trigger if exists place_plans_set_updated_at on public.place_plans;
create trigger place_plans_set_updated_at before update on public.place_plans
  for each row execute function app.set_updated_at();
drop trigger if exists place_plan_participants_set_updated_at on public.place_plan_participants;
create trigger place_plan_participants_set_updated_at before update on public.place_plan_participants
  for each row execute function app.set_updated_at();

alter table public.place_wanna_events enable row level security;
alter table public.place_plans enable row level security;
alter table public.place_plan_participants enable row level security;
alter table public.place_plan_operations enable row level security;
revoke all on table public.place_wanna_events from public, anon, authenticated;
revoke all on table public.place_plans from public, anon, authenticated;
revoke all on table public.place_plan_participants from public, anon, authenticated;
revoke all on table public.place_plan_operations from public, anon, authenticated;

alter table public.feed_events
  add column wanna_event_id uuid references public.place_wanna_events(id) on delete set null,
  add column place_plan_id uuid references public.place_plans(id) on delete set null;
alter table public.feed_events drop constraint if exists feed_events_subject_check;
alter table public.feed_events add constraint feed_events_subject_check check (
  (
    event_type in ('place_saved', 'place_been', 'place_want_to_go')
    and user_place_id is not null and place_id is not null
    and list_id is null and list_item_id is null
    and (event_type = 'place_been' or visit_id is null)
    and (event_type = 'place_want_to_go' or wanna_event_id is null)
    and (place_plan_id is null or wanna_event_id is not null)
  ) or (
    event_type = 'list_created'
    and user_place_id is null and place_id is null and visit_id is null
    and wanna_event_id is null and place_plan_id is null
    and list_id is not null and list_item_id is null
  ) or (
    event_type = 'list_item_added'
    and user_place_id is not null and place_id is not null and visit_id is null
    and wanna_event_id is null and place_plan_id is null
    and list_id is not null and list_item_id is not null
  )
);
create unique index feed_events_wanna_event_unique_idx
  on public.feed_events(wanna_event_id) where wanna_event_id is not null;

-- Keep the explicit check-in behavior and suppress the compatibility Feed
-- trigger while the new atomic Wanna RPC writes its user_places summary.
create or replace function app.record_user_place_feed_event()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
declare resolved_event_type text;
begin
  if new.deleted_at is not null then return new; end if;
  if current_setting('app.explicit_check_in', true) = 'on'
     or current_setting('app.explicit_wanna', true) = 'on' then return new; end if;
  if tg_op = 'UPDATE' and old.deleted_at is null
     and not (old.status = 'wanna_go' and new.status = 'been') then return new; end if;
  resolved_event_type := case
    when new.source_type = 'social_save' then 'place_saved'
    when new.status = 'been' then 'place_been'
    else 'place_want_to_go'
  end;
  perform app.record_feed_event(new.user_id, resolved_event_type, new.id, new.place_id);
  return new;
end;
$$;

create or replace function app.visible_plan_participants(
  input_plan_id uuid,
  input_viewer_id text,
  input_include_pending boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = public, app
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'participant_id', participant.id,
    'user_id', profile.id,
    'handle', profile.handle,
    'display_name', profile.display_name,
    'avatar_url', profile.avatar_url,
    'role', participant.role,
    'state', participant.state
  ) order by case participant.role when 'creator' then 0 else 1 end,
    profile.display_name, profile.id), '[]'::jsonb)
  from public.place_plan_participants participant
  join public.profiles profile on profile.id = participant.user_id
  where participant.plan_id = input_plan_id
    and profile.deleted_at is null
    and not app.is_blocked(input_viewer_id, participant.user_id)
    and (
      participant.role = 'creator' or participant.state = 'accepted'
      or (input_include_pending and participant.state = 'pending' and exists (
        select 1 from public.place_plan_participants viewer_participant
        where viewer_participant.plan_id = input_plan_id
          and viewer_participant.user_id = input_viewer_id
          and viewer_participant.state in ('pending', 'accepted')
      ))
    )
    and (
      participant.user_id = input_viewer_id
      or not coalesce(profile.is_private_profile, false)
      or exists (
        select 1 from public.place_plan_participants viewer_participant
        where viewer_participant.plan_id = input_plan_id
          and viewer_participant.user_id = input_viewer_id
          and viewer_participant.state in ('pending', 'accepted')
      )
    )
$$;

create or replace function public.save_own_wanna(
  input_place jsonb,
  input_user_place jsonb,
  input_attributes jsonb default '[]'::jsonb,
  input_wanna_event jsonb default '{}'::jsonb,
  input_plan jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  viewer_profile public.profiles;
  saved public.user_places;
  event_row public.place_wanna_events;
  plan_row public.place_plans;
  participant_row public.place_plan_participants;
  event_id uuid;
  requested_plan_id uuid;
  requested_planned_date date;
  requested_visibility text;
  requested_sharing text;
  effective_sharing text;
  normalized_invitee_ids text[];
  invitee_id text;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  if coalesce(jsonb_typeof(input_wanna_event), '') <> 'object'
     or (input_plan is not null and jsonb_typeof(input_plan) <> 'object') then
    raise exception 'invalid_wanna_payload';
  end if;
  if input_user_place->>'status' <> 'wanna_go' then
    raise exception 'wanna_event_requires_wanna_status';
  end if;
  begin event_id := (input_wanna_event->>'id')::uuid;
  exception when others then raise exception 'invalid_wanna_event_id'; end;
  if event_id is null then raise exception 'wanna_event_id_required'; end if;
  requested_visibility := input_user_place->>'visibility';
  if requested_visibility not in ('followers', 'mutuals', 'self') then
    raise exception 'invalid_wanna_visibility';
  end if;
  if nullif(input_wanna_event->>'planned_date', '') is not null then
    begin requested_planned_date := (input_wanna_event->>'planned_date')::date;
    exception when others then raise exception 'invalid_planned_date'; end;
  end if;
  select * into viewer_profile from public.profiles profile
  where profile.id = viewer_id and profile.deleted_at is null;
  if viewer_profile.id is null then raise exception 'profile_not_found'; end if;

  perform set_config('app.explicit_wanna', 'on', true);
  select * into saved from app.save_own_place(
    input_place,
    input_user_place || jsonb_build_object('planned_date', requested_planned_date),
    input_attributes
  );
  if saved.user_id <> viewer_id then raise exception 'not_owner'; end if;
  if saved.status = 'wanna_go' then
    update public.user_places
    set planned_date = requested_planned_date, updated_at = now()
    where id = saved.id and user_id = viewer_id
    returning * into saved;
  end if;

  insert into public.place_wanna_events(
    id, user_id, place_id, user_place_id, source, was_visited_before, visibility,
    note_snapshot, planned_date
  ) values (
    event_id, viewer_id, saved.place_id, saved.id, 'direct',
    saved.status = 'been', requested_visibility,
    nullif(input_user_place->>'note', ''), requested_planned_date
  ) on conflict (id) do nothing returning * into event_row;
  if event_row.id is null then
    select * into event_row from public.place_wanna_events row where row.id = event_id;
    if event_row.user_id <> viewer_id or event_row.place_id <> saved.place_id then
      raise exception 'wanna_event_id_conflict';
    end if;
  end if;

  if input_plan is not null then
    begin requested_plan_id := (input_plan->>'id')::uuid;
    exception when others then raise exception 'invalid_place_plan_id'; end;
    if requested_plan_id is null then raise exception 'place_plan_id_required'; end if;
    requested_sharing := coalesce(nullif(input_plan->>'sharing', ''), 'feed');
    if requested_sharing not in ('feed', 'private') then
      raise exception 'invalid_place_plan_sharing';
    end if;
    effective_sharing := case
      when viewer_profile.is_private_profile or requested_visibility = 'self'
        or requested_sharing = 'private' then 'private'
      else 'feed'
    end;
    select coalesce(array_agg(distinct value order by value), array[]::text[])
    into normalized_invitee_ids
    from jsonb_array_elements_text(
      coalesce(input_plan->'invitee_user_ids', '[]'::jsonb)
    ) invitee(value)
    where nullif(btrim(value), '') is not null;
    if cardinality(normalized_invitee_ids) = 0 then
      raise exception 'place_plan_invitees_required';
    end if;
    if cardinality(normalized_invitee_ids) > 19 then
      raise exception 'place_plan_participant_limit';
    end if;
    if exists (
      select 1 from unnest(normalized_invitee_ids) invitee(user_id)
      where invitee.user_id = viewer_id
        or not exists (select 1 from public.profiles profile
          where profile.id = invitee.user_id and profile.deleted_at is null)
        or not app.is_mutual(viewer_id, invitee.user_id)
        or app.is_blocked(viewer_id, invitee.user_id)
    ) then raise exception 'invalid_place_plan_invitees'; end if;

    insert into public.place_plans(
      id, creator_user_id, place_id, creator_wanna_event_id,
      planned_date, sharing
    ) values (
      requested_plan_id, viewer_id, saved.place_id, event_row.id,
      requested_planned_date, effective_sharing
    ) on conflict (id) do nothing returning * into plan_row;
    if plan_row.id is null then
      select * into plan_row from public.place_plans row where row.id = requested_plan_id;
      if plan_row.creator_user_id <> viewer_id
         or plan_row.creator_wanna_event_id <> event_row.id then
        raise exception 'place_plan_id_conflict';
      end if;
    end if;

    insert into public.place_plan_participants(
      plan_id, user_id, role, state, participant_wanna_event_id, responded_at
    ) values (
      plan_row.id, viewer_id, 'creator', 'accepted', event_row.id, now()
    ) on conflict (plan_id, user_id) do update set
      role = 'creator', state = 'accepted',
      participant_wanna_event_id = excluded.participant_wanna_event_id,
      responded_at = coalesce(public.place_plan_participants.responded_at, now()),
      cancelled_at = null, updated_at = now();

    foreach invitee_id in array normalized_invitee_ids loop
      insert into public.place_plan_participants(
        plan_id, user_id, role, state, invitation_generation
      ) values (plan_row.id, invitee_id, 'invitee', 'pending', 1)
      on conflict (plan_id, user_id) do update set
        state = case when public.place_plan_participants.state in
          ('declined', 'left', 'cancelled', 'removed') then 'pending'
          else public.place_plan_participants.state end,
        invitation_generation = case when public.place_plan_participants.state in
          ('declined', 'left', 'cancelled', 'removed')
          then public.place_plan_participants.invitation_generation + 1
          else public.place_plan_participants.invitation_generation end,
        participant_wanna_event_id = case when public.place_plan_participants.state in
          ('declined', 'left', 'cancelled', 'removed') then null
          else public.place_plan_participants.participant_wanna_event_id end,
        invited_at = case when public.place_plan_participants.state in
          ('declined', 'left', 'cancelled', 'removed') then now()
          else public.place_plan_participants.invited_at end,
        responded_at = case when public.place_plan_participants.state in
          ('declined', 'left', 'cancelled', 'removed') then null
          else public.place_plan_participants.responded_at end,
        cancelled_at = null, updated_at = now()
      returning * into participant_row;

      if participant_row.state = 'pending' then
        perform app.queue_notification_event(
          input_recipient_user_id := invitee_id,
          input_actor_user_id := viewer_id,
          input_notification_type := 'shared_visit',
          input_title := 'Wanna go?',
          input_body := viewer_profile.display_name || ' wants to go to ' ||
            (select place.canonical_name from public.places place where place.id = saved.place_id) ||
            ' with you',
          input_deeplink_url := 'recme://wanna-plans/' || participant_row.id ||
            '?generation=' || participant_row.invitation_generation,
          input_data := jsonb_build_object(
            'wanna_plan_participant_id', participant_row.id,
            'invitation_generation', participant_row.invitation_generation,
            'plan_id', plan_row.id, 'place_id', saved.place_id,
            'actor_user_id', viewer_id
          ),
          input_dedupe_key := 'wanna_plan:' || participant_row.id || ':' ||
            participant_row.invitation_generation
        );
      end if;
    end loop;
  end if;

  -- A private plan never produces follower activity. If an existing Been row
  -- has different visibility, fail closed instead of widening this event.
  if requested_visibility <> 'self'
     and not viewer_profile.is_private_profile
     and saved.visibility = requested_visibility
     and (plan_row.id is null or plan_row.sharing = 'feed') then
    insert into public.feed_events(
      actor_user_id, event_type, user_place_id, place_id,
      wanna_event_id, place_plan_id, occurred_at
    ) values (
      viewer_id, 'place_want_to_go', saved.id, saved.place_id,
      event_row.id, plan_row.id, event_row.occurred_at
    ) on conflict (wanna_event_id) where wanna_event_id is not null do nothing;
  end if;

  return jsonb_build_object(
    'user_place_id', saved.id, 'place_id', saved.place_id,
    'wanna_event_id', event_row.id, 'plan_id', plan_row.id,
    'sharing', plan_row.sharing,
    'invitation_count', coalesce(cardinality(normalized_invitee_ids), 0)
  );
end;
$$;

create or replace function public.own_wanna_events()
returns table (
  wanna_event_id uuid,
  user_place_id uuid,
  place_id uuid,
  event_state text,
  event_source text,
  was_visited_before boolean,
  planned_date date,
  occurred_at timestamptz,
  plan_id uuid,
  plan_sharing text,
  plan_status text
)
language sql
stable
security definer
set search_path = public, app
as $$
  select
    event.id, event.user_place_id, event.place_id, event.state, event.source,
    event.was_visited_before,
    coalesce(creator_plan.planned_date, participant_plan.planned_date, event.planned_date),
    event.occurred_at,
    coalesce(creator_plan.id, participant_plan.id),
    coalesce(creator_plan.sharing, participant_plan.sharing),
    coalesce(creator_plan.status, participant_plan.status)
  from public.place_wanna_events event
  left join public.place_plans creator_plan on creator_plan.creator_wanna_event_id = event.id
  left join public.place_plan_participants participant
    on participant.participant_wanna_event_id = event.id and participant.state = 'accepted'
  left join public.place_plans participant_plan on participant_plan.id = participant.plan_id
  where event.user_id = app.current_user_id()
  order by event.occurred_at desc, event.id
$$;

-- followed_feed remains the eligibility boundary. This second RPC decorates
-- only activity ids already visible to the caller.
create or replace function public.feed_wanna_context(input_activity_ids uuid[])
returns table (
  activity_id uuid,
  wanna_event_id uuid,
  note text,
  was_visited_before boolean,
  planned_date date,
  plan_id uuid,
  plan_sharing text,
  plan_status text,
  participants jsonb
)
language sql
stable
security definer
set search_path = public, app
as $$
  select
    feed.id, event.id, event.note_snapshot, event.was_visited_before,
    coalesce(plan.planned_date, event.planned_date),
    plan.id, plan.sharing, plan.status,
    case when plan.id is null then '[]'::jsonb
      else app.visible_plan_participants(plan.id, app.current_user_id(), false) end
  from public.feed_events feed
  join public.place_wanna_events event on event.id = feed.wanna_event_id
  join public.user_places user_place on user_place.id = feed.user_place_id
  join public.profiles actor on actor.id = feed.actor_user_id
  left join public.place_plans plan on plan.id = feed.place_plan_id
  where feed.id = any(coalesce(input_activity_ids, array[]::uuid[]))
    and feed.event_type = 'place_want_to_go'
    and actor.deleted_at is null and not actor.is_private_profile
    and exists (
      select 1 from public.follows follow
      where follow.follower_user_id = app.current_user_id()
        and follow.followed_user_id = feed.actor_user_id
    )
    and not app.is_blocked(app.current_user_id(), feed.actor_user_id)
    and user_place.deleted_at is null
    and app.can_read_user_place(app.current_user_id(), user_place.user_id, user_place.visibility)
    and event.visibility <> 'self'
    and (event.visibility = 'followers' or app.is_mutual(app.current_user_id(), event.user_id))
    and (plan.id is null or (plan.sharing = 'feed' and plan.status = 'active'))
$$;

create or replace function public.list_wanna_plan_inbox(
  input_before timestamptz default null,
  input_limit integer default 50
)
returns table (
  participant_id uuid,
  plan_id uuid,
  invitation_generation integer,
  participant_state text,
  invited_at timestamptz,
  creator_user_id text,
  creator_handle text,
  creator_display_name text,
  creator_avatar_url text,
  place_id uuid,
  place_name text,
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
  planned_date date,
  plan_sharing text,
  plan_status text,
  participants jsonb
)
language sql
stable
security definer
set search_path = public, app
as $$
  select
    participant.id, plan.id, participant.invitation_generation,
    participant.state, participant.invited_at,
    creator.id, creator.handle, creator.display_name, creator.avatar_url,
    place.id, place.canonical_name,
    coalesce(place.primary_category, place.category),
    coalesce(place.primary_category, place.category), place.subcategory,
    place.address, place.locality, place.region, place.country,
    place.latitude, place.longitude, place.source_provider, place.source_provider_place_id,
    plan.planned_date, plan.sharing, plan.status,
    app.visible_plan_participants(plan.id, app.current_user_id(), true)
  from public.place_plan_participants participant
  join public.place_plans plan on plan.id = participant.plan_id
  join public.profiles creator on creator.id = plan.creator_user_id
  join public.places place on place.id = plan.place_id
  where participant.user_id = app.current_user_id()
    and participant.role = 'invitee' and participant.state = 'pending'
    and plan.status = 'active'
    and (input_before is null or participant.invited_at < input_before)
    and creator.deleted_at is null
    and not app.is_blocked(app.current_user_id(), creator.id)
  order by participant.invited_at desc, participant.id desc
  limit least(greatest(coalesce(input_limit, 50), 1), 100)
$$;

create or replace function public.accept_wanna_plan(
  input_participant_id uuid,
  input_generation integer,
  input_wanna_event_id uuid,
  input_operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  participant public.place_plan_participants;
  plan public.place_plans;
  viewer_profile public.profiles;
  saved public.user_places;
  event public.place_wanna_events;
  output jsonb;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  if input_generation is null or input_generation < 1
     or input_wanna_event_id is null or input_operation_id is null then
    raise exception 'invalid_wanna_plan_acceptance_identity';
  end if;
  select operation.result into output from public.place_plan_operations operation
  where operation.id = input_operation_id and operation.user_id = viewer_id;
  if output is not null then return output; end if;
  select * into participant from public.place_plan_participants row
  where row.id = input_participant_id and row.user_id = viewer_id and row.role = 'invitee'
  for update;
  if participant.id is null then raise exception 'wanna_plan_invitation_not_found'; end if;
  if participant.invitation_generation <> input_generation then
    raise exception 'stale_wanna_plan_invitation';
  end if;
  select * into plan from public.place_plans row where row.id = participant.plan_id for update;
  if plan.id is null or plan.status <> 'active'
     or app.is_blocked(viewer_id, plan.creator_user_id) then
    raise exception 'wanna_plan_unavailable';
  end if;
  if participant.state = 'accepted' and participant.participant_wanna_event_id is not null then
    select jsonb_build_object(
      'participant_id', participant.id, 'plan_id', plan.id,
      'participant_state', participant.state,
      'wanna_event_id', participant.participant_wanna_event_id,
      'user_place_id', prior_event.user_place_id, 'place_id', plan.place_id
    ) into output from public.place_wanna_events prior_event
    where prior_event.id = participant.participant_wanna_event_id;
    return output;
  end if;
  if participant.state <> 'pending' then raise exception 'wanna_plan_invitation_unavailable'; end if;
  select * into viewer_profile from public.profiles profile
  where profile.id = viewer_id and profile.deleted_at is null;
  if viewer_profile.id is null then raise exception 'profile_not_found'; end if;

  perform set_config('app.explicit_wanna', 'on', true);
  select * into saved from public.user_places own
  where own.user_id = viewer_id and own.place_id = plan.place_id for update;
  if saved.id is null then
    insert into public.user_places(
      user_id, place_id, status, visibility, source_type,
      source_user_place_id, attribution_user_id, planned_date
    )
    select viewer_id, plan.place_id, 'wanna_go',
      case when viewer_profile.is_private_profile then 'self'
        else viewer_profile.default_visibility end,
      'social_save', creator_event.user_place_id, plan.creator_user_id, plan.planned_date
    from public.place_wanna_events creator_event
    where creator_event.id = plan.creator_wanna_event_id
    returning * into saved;
  elsif saved.deleted_at is not null then
    update public.user_places set
      status = 'wanna_go',
      visibility = case when viewer_profile.is_private_profile then 'self'
        else viewer_profile.default_visibility end,
      source_type = 'social_save', planned_date = plan.planned_date,
      deleted_at = null, updated_at = now()
    where id = saved.id returning * into saved;
  elsif saved.status = 'wanna_go' then
    update public.user_places
    set planned_date = coalesce(plan.planned_date, planned_date), updated_at = now()
    where id = saved.id returning * into saved;
  end if;

  insert into public.place_wanna_events(
    id, user_id, place_id, user_place_id, source, was_visited_before,
    visibility, planned_date
  ) values (
    input_wanna_event_id, viewer_id, plan.place_id, saved.id,
    'plan_acceptance', saved.status = 'been', saved.visibility, plan.planned_date
  ) on conflict (id) do nothing returning * into event;
  if event.id is null then
    select * into event from public.place_wanna_events row where row.id = input_wanna_event_id;
    if event.user_id <> viewer_id or event.place_id <> plan.place_id then
      raise exception 'wanna_event_id_conflict';
    end if;
  end if;
  update public.place_plan_participants set
    state = 'accepted', participant_wanna_event_id = event.id,
    responded_at = now(), cancelled_at = null, updated_at = now()
  where id = participant.id returning * into participant;
  output := jsonb_build_object(
    'participant_id', participant.id, 'plan_id', plan.id,
    'participant_state', participant.state, 'wanna_event_id', event.id,
    'user_place_id', saved.id, 'place_id', plan.place_id
  );
  insert into public.place_plan_operations(
    id, participant_id, user_id, invitation_generation, operation_type, result
  ) values (
    input_operation_id, participant.id, viewer_id, input_generation, 'accept', output
  );
  perform app.queue_notification_event(
    input_recipient_user_id := plan.creator_user_id,
    input_actor_user_id := viewer_id,
    input_notification_type := 'shared_visit',
    input_title := 'Wanna accepted',
    input_body := viewer_profile.display_name || ' wants to go with you',
    input_deeplink_url := 'recme://wanna-plans/' || plan.id,
    input_data := jsonb_build_object(
      'plan_id', plan.id, 'place_id', plan.place_id, 'actor_user_id', viewer_id
    ),
    input_dedupe_key := 'wanna_plan_accepted:' || participant.id || ':' || input_generation
  );
  return output;
end;
$$;

create or replace function public.decline_wanna_plan(
  input_participant_id uuid,
  input_generation integer
)
returns boolean
language plpgsql
security definer
set search_path = public, app
as $$
declare viewer_id text := app.current_user_id(); affected integer;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  update public.place_plan_participants participant
  set state = 'declined', responded_at = now(), updated_at = now()
  from public.place_plans plan
  where participant.id = input_participant_id and participant.plan_id = plan.id
    and participant.user_id = viewer_id and participant.role = 'invitee'
    and participant.state = 'pending'
    and participant.invitation_generation = input_generation
    and plan.status = 'active';
  get diagnostics affected = row_count;
  return affected = 1;
end;
$$;

create or replace function public.resolve_own_active_wannas(
  input_place_id uuid,
  input_resolution text,
  input_visit_id uuid default null
)
returns integer
language plpgsql
security definer
set search_path = public, app
as $$
declare viewer_id text := app.current_user_id(); affected integer := 0;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  if input_resolution not in ('keep', 'remove') then raise exception 'invalid_wanna_resolution'; end if;
  if input_resolution = 'keep' then return 0; end if;
  update public.place_wanna_events set
    state = 'fulfilled', fulfilled_at = now(),
    fulfilled_by_visit_id = input_visit_id, updated_at = now()
  where user_id = viewer_id and place_id = input_place_id and state = 'active';
  get diagnostics affected = row_count;
  return affected;
end;
$$;

-- A first check-in fulfils active intent. Repeat check-ins leave it active for
-- the post-save Keep/Remove speed bump instead of guessing.
create or replace function app.fulfill_wannas_after_first_check_in()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
declare parent public.user_places; prior_visit_count integer;
begin
  if new.deleted_at is not null or new.backfilled_from_user_place then return new; end if;
  select * into parent from public.user_places where id = new.user_place_id;
  if parent.id is null then return new; end if;
  select count(*) into prior_visit_count from public.place_visits visit
  where visit.user_place_id = new.user_place_id and visit.id <> new.id
    and visit.deleted_at is null and not visit.backfilled_from_user_place;
  if prior_visit_count = 0 then
    update public.place_wanna_events set
      state = 'fulfilled', fulfilled_at = now(),
      fulfilled_by_visit_id = new.id, updated_at = now()
    where user_id = parent.user_id and place_id = parent.place_id and state = 'active';
  end if;
  return new;
end;
$$;
drop trigger if exists place_visits_fulfill_first_wanna on public.place_visits;
create trigger place_visits_fulfill_first_wanna after insert on public.place_visits
  for each row execute function app.fulfill_wannas_after_first_check_in();

-- One legacy event preserves every active pre-migration Wanna summary.
insert into public.place_wanna_events(
  id, user_id, place_id, user_place_id, source, was_visited_before, visibility,
  note_snapshot, planned_date, occurred_at
)
select
  gen_random_uuid(), user_place.user_id, user_place.place_id, user_place.id,
  'legacy', false, user_place.visibility, user_place.note, user_place.planned_date,
  coalesce(user_place.saved_at, user_place.created_at, now())
from public.user_places user_place
where user_place.status = 'wanna_go' and user_place.deleted_at is null;

revoke all on function app.record_user_place_feed_event()
  from public, anon, authenticated;
revoke all on function app.visible_plan_participants(uuid, text, boolean)
  from public, anon, authenticated;
revoke all on function app.fulfill_wannas_after_first_check_in()
  from public, anon, authenticated;
revoke all on function public.save_own_wanna(jsonb, jsonb, jsonb, jsonb, jsonb)
  from public, anon;
revoke all on function public.own_wanna_events() from public, anon;
revoke all on function public.feed_wanna_context(uuid[]) from public, anon;
revoke all on function public.list_wanna_plan_inbox(timestamptz, integer)
  from public, anon;
revoke all on function public.accept_wanna_plan(uuid, integer, uuid, uuid)
  from public, anon;
revoke all on function public.decline_wanna_plan(uuid, integer) from public, anon;
revoke all on function public.resolve_own_active_wannas(uuid, text, uuid)
  from public, anon;

grant execute on function public.save_own_wanna(jsonb, jsonb, jsonb, jsonb, jsonb)
  to authenticated;
grant execute on function public.own_wanna_events() to authenticated;
grant execute on function public.feed_wanna_context(uuid[]) to authenticated;
grant execute on function public.list_wanna_plan_inbox(timestamptz, integer)
  to authenticated;
grant execute on function public.accept_wanna_plan(uuid, integer, uuid, uuid)
  to authenticated;
grant execute on function public.decline_wanna_plan(uuid, integer) to authenticated;
grant execute on function public.resolve_own_active_wannas(uuid, text, uuid)
  to authenticated;

comment on table public.place_wanna_events is
  'Immutable Wanna moments with mutable lifecycle state; multiple rows may be active for one user/place.';
comment on table public.place_plans is
  'Optional multi-person coordination attached to a creator-owned Wanna event.';
comment on function public.save_own_wanna(jsonb, jsonb, jsonb, jsonb, jsonb) is
  'Atomic authenticated Wanna event and optional multi-invitee plan creation boundary.';

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'public.save_own_wanna(jsonb,jsonb,jsonb,jsonb,jsonb)'::regprocedure,
    'public.own_wanna_events()'::regprocedure,
    'public.feed_wanna_context(uuid[])'::regprocedure,
    'public.list_wanna_plan_inbox(timestamptz,integer)'::regprocedure,
    'public.accept_wanna_plan(uuid,integer,uuid,uuid)'::regprocedure,
    'public.decline_wanna_plan(uuid,integer)'::regprocedure,
    'public.resolve_own_active_wannas(uuid,text,uuid)'::regprocedure
  ] loop
    if not exists (
      select 1 from pg_proc procedure where procedure.oid = signature
        and procedure.prosecdef
        and 'search_path=public, app' = any(coalesce(procedure.proconfig, array[]::text[]))
    ) then raise exception '% security metadata is invalid', signature; end if;
    if not has_function_privilege('authenticated', signature, 'execute')
       or has_function_privilege('anon', signature, 'execute') then
      raise exception '% execute grants are invalid', signature;
    end if;
  end loop;
  if exists (
    select 1 from pg_policies policy where policy.schemaname = 'public'
      and policy.tablename in (
        'place_wanna_events', 'place_plans',
        'place_plan_participants', 'place_plan_operations'
      )
  ) then raise exception 'Wanna event and plan tables must remain RPC-only'; end if;
end;
$$;

commit;
