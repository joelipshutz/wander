begin;

-- REC-566: new joint occasions have one conversation, while every participant
-- retains an independently owned visit/event. Existing rows stay version 1.
--
-- group v2 --- canonical feed event --- shared likes/comments
--    |
--    +--- member --- owned visit --- personal event (survives detach)
--
-- No historical events, invitations or engagement are converted here.
alter table public.shared_visit_groups
  add column model_version smallint not null default 1
    check (model_version in (1, 2)),
  add column revision bigint not null default 1 check (revision > 0),
  add column closed_reason text,
  add constraint shared_visit_groups_closed_reason_check
    check (closed_reason is null or cancelled_at is not null);

alter table public.feed_events
  add column shared_visit_group_id uuid
    references public.shared_visit_groups(id) on delete cascade,
  add column standalone_engagement_started_at timestamptz,
  add constraint feed_events_joint_subject_check check (
    shared_visit_group_id is null
    or (event_type = 'place_been' and visit_id is null
      and user_place_id is not null and place_id is not null)
  );

create unique index feed_events_joint_group_unique_idx
  on public.feed_events(shared_visit_group_id)
  where shared_visit_group_id is not null;

alter table public.shared_visit_participants
  add column retained_visit_id uuid references public.place_visits(id) on delete set null,
  add column consent_version integer check (consent_version > 0);

create index shared_visit_participants_retained_visit_idx
  on public.shared_visit_participants(retained_visit_id)
  where retained_visit_id is not null;

-- Do not extend the v1 ledger: its accept-only operation type and one result
-- per participant generation deliberately retain the old retry semantics.
create table public.joint_check_in_operations (
  actor_user_id text not null references public.profiles(id) on delete cascade,
  request_id uuid not null,
  group_id uuid not null references public.shared_visit_groups(id) on delete cascade,
  operation_kind text not null check (operation_kind in (
    'create', 'set_invitees', 'accept', 'save_privately', 'leave', 'comment_create', 'edit'
  )),
  participant_id uuid references public.shared_visit_participants(id) on delete cascade,
  invitation_generation integer check (invitation_generation > 0),
  expected_revision bigint check (expected_revision > 0),
  payload_hash text not null,
  committed_result jsonb not null check (jsonb_typeof(committed_result) = 'object'),
  created_at timestamptz not null default now(),
  primary key (actor_user_id, request_id)
);

create index joint_check_in_operations_group_idx
  on public.joint_check_in_operations(group_id);

alter table public.joint_check_in_operations enable row level security;
revoke all on public.joint_check_in_operations from public, anon, authenticated;

-- The live-row unique index is a secondary guard. Joint comment receipts in
-- the ledger survive deletion and contain only the comment ID/payload hash,
-- never a second copy of the deleted comment body.
alter table public.activity_comments add column client_request_id uuid;
create unique index activity_comments_client_request_unique_idx
  on public.activity_comments(author_user_id, client_request_id)
  where client_request_id is not null;

create function app.guard_joint_check_in_identity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  source_group public.shared_visit_groups;
  source_parent_id uuid;
begin
  if tg_table_name = 'shared_visit_groups' then
    if new.model_version is distinct from old.model_version then
      raise exception 'joint_check_in_version_immutable';
    end if;
    if old.model_version = 2 then
      if old.cancelled_at is not null and new.cancelled_at is distinct from old.cancelled_at then
        raise exception 'joint_check_in_closed';
      end if;
      if new.source_visit_id is distinct from old.source_visit_id
        or new.owner_user_id is distinct from old.owner_user_id
        or new.place_id is distinct from old.place_id then
        raise exception 'joint_check_in_identity_immutable';
      end if;
      if new.revision < old.revision then
        raise exception 'joint_check_in_revision_regression';
      end if;
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if new.shared_visit_group_id is distinct from old.shared_visit_group_id then
      raise exception 'joint_check_in_event_identity_immutable';
    end if;
    if old.standalone_engagement_started_at is not null
      and new.standalone_engagement_started_at is distinct from old.standalone_engagement_started_at then
      raise exception 'joint_check_in_discussion_identity_immutable';
    end if;
  end if;

  if new.shared_visit_group_id is not null then
    select * into source_group from public.shared_visit_groups
    where id = new.shared_visit_group_id;
    select user_place_id into source_parent_id from public.place_visits
    where id = source_group.source_visit_id;
    if source_group.model_version is distinct from 2
      or new.actor_user_id is distinct from source_group.owner_user_id
      or new.place_id is distinct from source_group.place_id
      or new.user_place_id is distinct from source_parent_id then
      raise exception 'invalid_joint_check_in_event';
    end if;
    if tg_op = 'UPDATE' and (
      new.occurred_at is distinct from old.occurred_at
      or new.actor_user_id is distinct from old.actor_user_id
    ) then
      raise exception 'joint_check_in_event_identity_immutable';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function app.guard_joint_check_in_identity() from public, anon, authenticated;

create trigger shared_visit_groups_guard_joint_identity
  before update on public.shared_visit_groups
  for each row execute function app.guard_joint_check_in_identity();

create trigger feed_events_guard_joint_identity
  before insert or update on public.feed_events
  for each row execute function app.guard_joint_check_in_identity();

alter table public.feature_flags
  drop constraint feature_flags_registered_key_check,
  drop constraint feature_flags_key_value_contract_check;
alter table public.feature_flags
  add constraint feature_flags_registered_key_check check (key in (
    'first_visit_nux', 'debug_settings', 'place_profile_save_tray_v1',
    'semantic_place_search_v1', 'social_import_apify_gemini_v1',
    'place_profile_action_variant', 'profile_feedback_v1', 'joint_check_ins_v2'
  )),
  add constraint feature_flags_key_value_contract_check check (
    (key in ('first_visit_nux', 'debug_settings', 'place_profile_save_tray_v1',
             'semantic_place_search_v1', 'social_import_apify_gemini_v1',
             'profile_feedback_v1', 'joint_check_ins_v2')
      and value_type = 'boolean' and integer_value is null)
    or (key = 'place_profile_action_variant' and value_type = 'integer'
      and integer_value is not null and integer_value between 1 and 5)
  );
insert into public.feature_flags(key, user_id, enabled, value_type, integer_value)
values ('joint_check_ins_v2', null, false, 'boolean', null)
on conflict (key) where user_id is null do nothing;

comment on column public.feed_events.shared_visit_group_id is
  'Canonical v2 conversation identity. Personal visit events keep visit_id and never acquire this binding.';
comment on column public.feed_events.standalone_engagement_started_at is
  'Monotonic proof that a personal v2 discussion was used, surviving deletion of all engagement.';
comment on table public.joint_check_in_operations is
  'Private caller-bound receipts for committed v2 operations. Authorize current lifecycle before replay; comment receipts never retain body text.';

commit;
