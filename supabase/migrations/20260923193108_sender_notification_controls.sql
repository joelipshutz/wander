begin;

-- REC-589: Sender intent is captured before inserts can announce. Existing
-- RPCs and audience policies retain their contracts for installed clients.
alter table public.user_places add column notification_silent boolean not null default false;
alter table public.place_visits add column notification_silent boolean not null default false;
alter table public.place_visits add column sender_import_id text;
alter table public.place_visits add column sender_import_commit_id uuid;
alter table public.place_list_items add column notification_silent boolean not null default false;
create index place_visits_sender_import_idx on public.place_visits(sender_import_id, sender_import_commit_id)
  where sender_import_id is not null;

create table app.import_notification_commits (
  owner_user_id text not null references public.profiles(id) on delete cascade,
  import_id text not null check (length(import_id) between 1 and 200),
  commit_id uuid not null,
  silent boolean not null,
  visit_ids uuid[] not null default array[]::uuid[],
  created_at timestamptz not null default now(),
  sealed_at timestamptz,
  primary key (owner_user_id, import_id)
);
alter table app.import_notification_commits enable row level security;
revoke all on app.import_notification_commits from public, anon, authenticated;

-- Definer is narrowly needed for the private ledger. Actor comes only from
-- authenticated claims; the caller cannot select someone else's ledger.
create function app.set_sender_notification_policy(input_policy jsonb)
returns text language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare
  owner_id text := app.current_user_id();
  import_key text := input_policy->>'importID';
  commit_key uuid := (input_policy->>'importCommitID')::uuid;
  prior text := current_setting('app.sender_notification_policy', true);
  existing app.import_notification_commits;
begin
  if owner_id is null then raise exception 'not_authenticated'; end if;
  if jsonb_typeof(input_policy) is distinct from 'object'
     or jsonb_typeof(input_policy->'silent') is distinct from 'boolean'
     or (import_key is null) <> (commit_key is null)
     or (import_key is not null and length(import_key) not between 1 and 200) then
    raise exception 'invalid_sender_notification_policy';
  end if;
  if import_key is not null then
    insert into app.import_notification_commits(owner_user_id, import_id, commit_id, silent)
    values (owner_id, import_key, commit_key, (input_policy->>'silent')::boolean)
    on conflict (owner_user_id, import_id) do nothing;
    select * into existing from app.import_notification_commits
      where owner_user_id = owner_id and import_id = import_key for update;
    if existing.commit_id = commit_key and existing.silent <> (input_policy->>'silent')::boolean then
      raise exception 'import_notification_choice_is_immutable';
    end if;
  end if;
  perform set_config('app.sender_notification_policy', input_policy::text, true);
  return coalesce(prior, '');
end;
$$;
revoke all on function app.set_sender_notification_policy(jsonb) from public, anon;
grant execute on function app.set_sender_notification_policy(jsonb) to authenticated;

-- BEFORE INSERT is earlier than every existing feed/notification trigger.
-- UPDATE retains the original action's policy; an edit cannot replay it.
create function app.capture_sender_notification_policy()
returns trigger language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare policy jsonb := nullif(current_setting('app.sender_notification_policy', true), '')::jsonb;
begin
  if tg_op = 'UPDATE' then
    new.notification_silent := old.notification_silent;
    if tg_table_name = 'place_visits' then
      new.sender_import_id := old.sender_import_id;
      new.sender_import_commit_id := old.sender_import_commit_id;
    end if;
    return new;
  end if;
  new.notification_silent := new.notification_silent
    or coalesce((policy->>'silent')::boolean, false) or policy->>'importID' is not null;
  if tg_table_name = 'place_visits' then
    new.sender_import_id := coalesce(policy->>'importID', new.sender_import_id);
    new.sender_import_commit_id := coalesce((policy->>'importCommitID')::uuid, new.sender_import_commit_id);
    if (new.sender_import_id is null) <> (new.sender_import_commit_id is null) then
      raise exception 'invalid_sender_import_identity';
    end if;
    if new.sender_import_id is not null then new.notification_silent := true; end if;
  end if;
  return new;
end;
$$;
revoke all on function app.capture_sender_notification_policy() from public, anon, authenticated;
create trigger user_places_sender_policy before insert or update on public.user_places
  for each row execute function app.capture_sender_notification_policy();
create trigger place_visits_sender_policy before insert or update on public.place_visits
  for each row execute function app.capture_sender_notification_policy();
create trigger place_list_items_sender_policy before insert or update on public.place_list_items
  for each row execute function app.capture_sender_notification_policy();

-- Invoker: original save_own_place remains responsible for all write authorization.
create function public.save_own_place_with_sender_policy(input_payload jsonb, input_policy jsonb)
returns jsonb language plpgsql volatile security invoker
set search_path = pg_catalog, public, app
as $$
declare prior text; result jsonb;
begin
  prior := app.set_sender_notification_policy(input_policy);
  result := public.save_own_place(input_payload->'input_place', input_payload->'input_user_place', coalesce(input_payload->'input_attributes', '[]'::jsonb));
  perform set_config('app.sender_notification_policy', prior, true);
  return result;
end;
$$;
revoke all on function public.save_own_place_with_sender_policy(jsonb, jsonb) from public, anon;
grant execute on function public.save_own_place_with_sender_policy(jsonb, jsonb) to authenticated;

-- Invoker: original save_own_check_in remains responsible for all write authorization.
create function public.save_own_check_in_with_sender_policy(input_payload jsonb, input_policy jsonb)
returns jsonb language plpgsql volatile security invoker
set search_path = pg_catalog, public, app
as $$
declare prior text; result jsonb;
begin
  prior := app.set_sender_notification_policy(input_policy);
  result := public.save_own_check_in(input_payload->'input_place', input_payload->'input_user_place', coalesce(input_payload->'input_attributes', '[]'::jsonb), input_payload->'input_visit', input_payload->'input_historical_want');
  perform set_config('app.sender_notification_policy', prior, true);
  return result;
end;
$$;
revoke all on function public.save_own_check_in_with_sender_policy(jsonb, jsonb) from public, anon;
grant execute on function public.save_own_check_in_with_sender_policy(jsonb, jsonb) to authenticated;

-- The legacy invoker social-save RPC relies on table SELECT now revoked by
-- private-taxonomy projections. This narrow definer replacement checks source
-- visibility explicitly and creates only the caller's own blank Wanna. It
-- never copies source notes, ratings, private answers, or taxonomy snapshots.
create function public.save_visible_place_with_sender_policy(input_payload jsonb, input_policy jsonb)
returns jsonb language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare
  prior text;
  viewer_id text := app.current_user_id();
  place_key uuid := (input_payload->>'input_place_id')::uuid;
  source_key uuid := (input_payload->>'input_source_user_place_id')::uuid;
  source_row public.user_places;
  saved_row public.user_places;
  target_visibility text;
begin
  prior := app.set_sender_notification_policy(input_policy);
  select up.* into source_row from public.user_places up
    join public.profiles p on p.id=up.user_id and p.deleted_at is null
    where up.id=source_key and up.place_id=place_key and up.deleted_at is null
      and app.can_read_user_place(viewer_id,up.user_id,up.visibility);
  if source_row.id is null then raise exception 'source_not_visible'; end if;
  select case when is_private_profile or default_visibility='self' then 'self' else 'followers' end into target_visibility
    from public.profiles where id=viewer_id and deleted_at is null;
  if target_visibility is null then raise exception 'not_authenticated'; end if;
  perform pg_advisory_xact_lock(hashtextextended('recme:user-place:'||viewer_id||':'||place_key::text,0));
  select * into saved_row from public.user_places
    where user_id=viewer_id and place_id=place_key and deleted_at is null and status='been';
  if saved_row.id is null then
    insert into public.user_places(user_id,place_id,status,visibility,source_type,source_user_place_id,attribution_user_id)
      values(viewer_id,place_key,'wanna_go',target_visibility,'social_save',source_row.id,source_row.user_id)
      on conflict(user_id,place_id) do update set
        status=excluded.status, source_type=excluded.source_type,
        source_user_place_id=excluded.source_user_place_id, attribution_user_id=excluded.attribution_user_id,
        deleted_at=null, updated_at=now()
      returning * into saved_row;
  end if;
  perform set_config('app.sender_notification_policy', prior, true);
  return jsonb_build_object('user_place_id',saved_row.id);
end;
$$;
revoke all on function public.save_visible_place_with_sender_policy(jsonb, jsonb) from public, anon;
grant execute on function public.save_visible_place_with_sender_policy(jsonb, jsonb) to authenticated;

-- Invoker: original add_place_list_item remains responsible for all write authorization.
create function public.add_place_list_item_with_sender_policy(input_payload jsonb, input_policy jsonb)
returns uuid language plpgsql volatile security invoker
set search_path = pg_catalog, public, app
as $$
declare prior text; result uuid;
begin
  prior := app.set_sender_notification_policy(input_policy);
  result := public.add_place_list_item((input_payload->>'input_list_id')::uuid, (input_payload->>'input_place_id')::uuid, (input_payload->>'input_owner_user_place_id')::uuid, (input_payload->>'input_source_user_place_id')::uuid);
  perform set_config('app.sender_notification_policy', prior, true);
  return result;
end;
$$;
revoke all on function public.add_place_list_item_with_sender_policy(jsonb, jsonb) from public, anon;
grant execute on function public.add_place_list_item_with_sender_policy(jsonb, jsonb) to authenticated;

-- Invoker: original accept_shared_visit remains responsible for all write authorization.
create function public.accept_shared_visit_with_sender_policy(input_payload jsonb, input_policy jsonb)
returns jsonb language plpgsql volatile security invoker
set search_path = pg_catalog, public, app
as $$
declare prior text; result jsonb;
begin
  prior := app.set_sender_notification_policy(input_policy);
  result := public.accept_shared_visit((input_payload->>'input_participant_id')::uuid, (input_payload->>'input_generation')::integer, (input_payload->>'input_snapshot_revision')::integer, (input_payload->>'input_operation_id')::uuid, (input_payload->>'input_user_place_id')::uuid, (input_payload->>'input_visit_id')::uuid, input_payload->'input_user_place', input_payload->'input_visit', coalesce(input_payload->'input_attributes', '[]'::jsonb), array(select jsonb_array_elements_text(coalesce(input_payload->'input_selected_photo_ids', '[]'::jsonb))::uuid));
  perform set_config('app.sender_notification_policy', prior, true);
  return result;
end;
$$;
revoke all on function public.accept_shared_visit_with_sender_policy(jsonb, jsonb) from public, anon;
grant execute on function public.accept_shared_visit_with_sender_policy(jsonb, jsonb) to authenticated;

-- Preserve definer/search_path/volatility/return type and recipient eligibility.
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
  if new.notification_silent then return new; end if;
  if new.deleted_at is not null
    or new.backfilled_from_user_place
    or new.visited_at < date_trunc('day', now())
    or new.visited_at > now() then
    return new;
  end if;

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
      input_title := actor_name || ' checked in',
      input_body := activity.canonical_name,
      input_deeplink_url := 'recme://places/' || activity.place_id,
      input_data := jsonb_build_object(
        'visit_id', new.id,
        'user_place_id', new.user_place_id,
        'place_id', activity.place_id,
        'actor_user_id', activity.user_id
      ),
      input_dedupe_key := 'followed_place_visit:' || new.id || ':' || follower.follower_user_id,
      input_not_before := now() + interval '30 seconds'
    );
  end loop;
  return new;
end;
$$;
revoke all on function app.notify_followed_place_visit_insert() from public, anon, authenticated;

-- Preserve definer/search_path/volatility/return type and recipient eligibility.
create or replace function app.notify_social_save_insert()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
declare
  actor_profile public.profiles;
  saved_place public.places;
begin
  if new.notification_silent then return new; end if;
  if new.source_type <> 'social_save' or new.attribution_user_id is null then
    return new;
  end if;

  select *
    into actor_profile
  from public.profiles
  where id = new.user_id
    and deleted_at is null;

  select *
    into saved_place
  from public.places
  where id = new.place_id;

  if actor_profile.id is null or saved_place.id is null then
    return new;
  end if;

  perform app.queue_notification_event(
    input_recipient_user_id := new.attribution_user_id,
    input_actor_user_id := new.user_id,
    input_notification_type := 'place_saved_from_your_map',
    input_title := 'Your map helped',
    input_body := actor_profile.display_name || ' saved ' || saved_place.canonical_name || ' from your map.',
    input_deeplink_url := 'recme://places/' || new.place_id,
    input_data := jsonb_build_object(
      'place_id', new.place_id,
      'user_place_id', new.id,
      'actor_user_id', new.user_id,
      'actor_handle', actor_profile.handle
    ),
    input_dedupe_key := 'place_saved_from_your_map:' || new.attribution_user_id || ':' || new.user_id || ':' || new.place_id
  );

  return new;
end;
$$;
revoke all on function app.notify_social_save_insert() from public, anon, authenticated;

-- Preserve definer/search_path/volatility/return type and recipient eligibility.
create or replace function app.notify_place_list_item_insert()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
declare
  list_row public.place_lists;
  actor_profile public.profiles;
  place_row public.places;
  recipient_id text;
begin
  if new.notification_silent then return new; end if;
  if new.deleted_at is not null then
    return new;
  end if;

  select *
    into list_row
  from public.place_lists
  where id = new.list_id
    and deleted_at is null;

  select *
    into actor_profile
  from public.profiles
  where id = new.added_by_user_id
    and deleted_at is null;

  select *
    into place_row
  from public.places
  where id = new.place_id;

  if list_row.id is null or actor_profile.id is null or place_row.id is null then
    return new;
  end if;

  for recipient_id in
    select participant.user_id
    from (
      select list_row.owner_user_id as user_id
      union
      select member.user_id
      from public.place_list_members member
      where member.list_id = new.list_id
        and member.deleted_at is null
    ) participant
    where participant.user_id <> new.added_by_user_id
      and app.can_read_place_list(new.list_id, participant.user_id)
  loop
    perform app.queue_notification_event(
      input_recipient_user_id := recipient_id,
      input_actor_user_id := new.added_by_user_id,
      input_notification_type := 'list_place_added',
      input_title := 'New place on a list',
      input_body := actor_profile.display_name || ' added ' || place_row.canonical_name || ' to ' || list_row.name || '.',
      input_deeplink_url := 'recme://lists/' || new.list_id,
      input_data := jsonb_build_object(
        'list_id', new.list_id,
        'list_name', list_row.name,
        'place_id', new.place_id,
        'place_name', place_row.canonical_name,
        'actor_user_id', new.added_by_user_id,
        'actor_handle', actor_profile.handle
      ),
      input_dedupe_key := 'list_place_added:' || new.list_id || ':' || new.place_id || ':' || recipient_id
    );
  end loop;

  return new;
end;
$$;
revoke all on function app.notify_place_list_item_insert() from public, anon, authenticated;

-- Group rendering is private. Count DISTINCT visible places, never hidden
-- imported items. The frozen visit set lives in the ledger, not APNs payloads.
create function app.import_notification_content(input_owner text, input_recipient text, input_import text)
returns jsonb language sql stable security definer
set search_path = pg_catalog, public, app
as $$
  with visible as (
    select distinct p.id, left(p.canonical_name, 180) as name
    from app.import_notification_commits c
    join public.place_visits v on v.id = any(c.visit_ids)
      and v.sender_import_id = c.import_id and v.sender_import_commit_id = c.commit_id
    join public.user_places up on up.id = v.user_place_id and up.user_id = c.owner_user_id
    join public.places p on p.id = up.place_id
    join public.profiles actor on actor.id = c.owner_user_id and actor.deleted_at is null
    where c.owner_user_id = input_owner and c.import_id = input_import and not c.silent
      and v.deleted_at is null and up.deleted_at is null and up.status = 'been'
      and exists (select 1 from public.follows f where f.followed_user_id = input_owner and f.follower_user_id = input_recipient)
      and app.can_read_user_place(input_recipient, input_owner, up.visibility)
  ), summary as (
    select count(*) as n, (array_agg(id order by id))[1] as first_id,
      (array_agg(name order by id))[1] as first_name from visible
  )
  select case when n = 0 then null else jsonb_build_object(
    'body', first_name || case when n = 1 then '' when n = 2 then ' and 1 other place' else ' and ' || (n - 1)::text || ' other places' end,
    'place_id', first_id,
    'place_count', n
  ) end from summary;
$$;
revoke all on function app.import_notification_content(text, text, text) from public, anon, authenticated;

-- Definer permits only the authenticated owner's ledger and own import visits.
-- The row lock and queue inserts share a transaction. Seal even when nobody is
-- eligible, so preferences/new followers/late selections never cause catch-up.
create function public.finalize_import_notification(
  input_import_id text, input_commit_id uuid, input_silent boolean, input_visit_ids uuid[]
)
returns boolean language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare
  owner_id text := app.current_user_id();
  ledger app.import_notification_commits;
  recipient text;
  content jsonb;
  actor_name text;
  ids uuid[];
begin
  if owner_id is null then raise exception 'not_authenticated'; end if;
  if input_import_id is null or length(input_import_id) not between 1 and 200
     or input_commit_id is null or input_silent is null or input_visit_ids is null
     or cardinality(input_visit_ids) > 10000 or array_position(input_visit_ids, null) is not null then
    raise exception 'invalid_import_notification';
  end if;
  insert into app.import_notification_commits(owner_user_id, import_id, commit_id, silent)
  values (owner_id, input_import_id, input_commit_id, input_silent)
  on conflict (owner_user_id, import_id) do nothing;
  select * into ledger from app.import_notification_commits
    where owner_user_id = owner_id and import_id = input_import_id for update;
  if ledger.sealed_at is not null or ledger.commit_id <> input_commit_id then return true; end if;
  if ledger.silent <> input_silent then raise exception 'import_notification_choice_is_immutable'; end if;
  select coalesce(array_agg(distinct id order by id), array[]::uuid[]) into ids from unnest(input_visit_ids) id;
  if exists (
    select 1 from unnest(ids) as requested(visit_id) where not exists (
      select 1 from public.place_visits v join public.user_places up on up.id = v.user_place_id
      where v.id = requested.visit_id and up.user_id = owner_id and v.sender_import_id = input_import_id
        and v.sender_import_commit_id = input_commit_id and v.notification_silent
    )
  ) then raise exception 'import_visit_not_owned_or_not_synced'; end if;
  update app.import_notification_commits set visit_ids = ids
    where owner_user_id = owner_id and import_id = input_import_id;
  if not ledger.silent and ledger.created_at > now() - interval '24 hours' then
    select left(coalesce(nullif(btrim(display_name), ''), '@' || handle), 100) into actor_name
      from public.profiles where id = owner_id and deleted_at is null;
    if actor_name is not null then
      for recipient in select follower_user_id from public.follows where followed_user_id = owner_id loop
        content := app.import_notification_content(owner_id, recipient, input_import_id);
        if content is not null then
          perform app.queue_notification_event(
            input_recipient_user_id := recipient, input_actor_user_id := owner_id,
            input_notification_type := 'followed_place_visit', input_title := actor_name || ' checked in',
            input_body := content->>'body',
            input_deeplink_url := 'recme://places/' || (content->>'place_id'),
            input_data := jsonb_build_object('sender_import_id', input_import_id, 'place_id', content->>'place_id',
              'place_count', content->'place_count', 'actor_user_id', owner_id),
            input_dedupe_key := 'import_check_in:' || owner_id || ':' || input_import_id || ':' || recipient,
            input_not_before := now() + interval '30 seconds');
        end if;
      end loop;
    end if;
  end if;
  update app.import_notification_commits set sealed_at = now()
    where owner_user_id = owner_id and import_id = input_import_id;
  return true;
end;
$$;
revoke all on function public.finalize_import_notification(text, uuid, boolean, uuid[]) from public, anon;
grant execute on function public.finalize_import_notification(text, uuid, boolean, uuid[]) to authenticated;

-- Worker-only wrapper retains the original definer posture, grants and return
-- ABI. Re-render groups on each claim/retry after normal queue governance.
create or replace function public.claim_pending_push_notifications(input_limit integer default 10)
returns jsonb language plpgsql volatile security definer
set search_path = app, public
as $$
declare claimed jsonb; item jsonb; content jsonb; result jsonb := '[]'::jsonb;
begin
  claimed := app.claim_pending_push_notifications(input_limit);
  for item in select value from jsonb_array_elements(claimed) loop
    if item->'data'->>'sender_import_id' is not null then
      content := app.import_notification_content(item->>'actor_user_id', item->>'recipient_user_id', item->'data'->>'sender_import_id');
      if content is null then
        update public.notification_events set status = 'skipped', skip_reason = 'activity_unavailable',
          failed_at = now(), claim_token = null, claim_expires_at = null
          where id = (item->>'event_id')::uuid;
        continue;
      end if;
      item := item || jsonb_build_object('body', content->>'body',
        'deeplink_url', 'recme://places/' || (content->>'place_id'),
        'data', (item->'data') || jsonb_build_object('place_id', content->>'place_id', 'place_count', content->'place_count'));
      update public.notification_events set body = item->>'body', deeplink_url = item->>'deeplink_url', data = item->'data'
        where id = (item->>'event_id')::uuid;
    end if;
    result := result || jsonb_build_array(item);
  end loop;
  return result;
end;
$$;
revoke all on function public.claim_pending_push_notifications(integer) from public, anon, authenticated;
grant execute on function public.claim_pending_push_notifications(integer) to service_role;

commit;
