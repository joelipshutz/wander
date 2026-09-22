-- Local-only lock harness, never applied to a linked/production database.
-- Narrow table shapes plus metadata/notification adapters. The mutation and
-- lifecycle functions are loaded verbatim from migrations by the Python runner.
-- Full-schema/RLS/content contracts are covered separately by rollback pgTAP.
create schema app;
do $$begin create role anon; exception when duplicate_object then null; end$$;
do $$begin create role authenticated; exception when duplicate_object then null; end$$;
create table profiles(id text primary key, is_private_profile boolean not null default false, deleted_at timestamptz);
create table places(id uuid primary key, source_provider text default 'fixture', source_provider_place_id text default 'venue');
create table user_places(id uuid primary key, user_id text references profiles, place_id uuid references places,
 status text default 'been', visibility text default 'followers', source_type text default 'manual', deleted_at timestamptz,
 note text, rating_score numeric, visited_at timestamptz, created_at timestamptz default now(), updated_at timestamptz default now(),
 saved_at timestamptz default now(), planned_date date, historical_want_note text, historical_want_attribute_answers jsonb,
 historical_want_tags text[], historical_wanted_at timestamptz, unique(user_id,place_id));
create table place_visits(id uuid primary key, user_place_id uuid references user_places, visited_at timestamptz,
 note text, rating_score numeric, attribute_answers jsonb default '[]', tags text[] default '{}',
 backfilled_from_user_place boolean default false, created_at timestamptz default now(), updated_at timestamptz default now(), deleted_at timestamptz);
create table shared_visit_groups(id uuid primary key default gen_random_uuid(), source_visit_id uuid references place_visits,
 owner_user_id text references profiles, place_id uuid references places, model_version int default 2, revision bigint default 1,
 cancelled_at timestamptz, closed_reason text);
create table shared_visit_participants(id uuid primary key default gen_random_uuid(), group_id uuid references shared_visit_groups,
 user_id text references profiles, invited_by_user_id text, status text, visit_id uuid references place_visits,
 retained_visit_id uuid references place_visits, invitation_generation int default 1, snapshot_revision int default 1,
 invitation_snapshot jsonb, consent_version int, invited_at timestamptz default now(), responded_at timestamptz,
 cancelled_at timestamptz, updated_at timestamptz default now(), unique(group_id,user_id));
create table feed_events(id uuid primary key default gen_random_uuid(), shared_visit_group_id uuid unique references shared_visit_groups,
 visit_id uuid unique references place_visits);
create table joint_check_in_operations(actor_user_id text references profiles, request_id uuid, group_id uuid references shared_visit_groups,
 operation_kind text, participant_id uuid, invitation_generation int, expected_revision bigint, payload_hash text,
 committed_result jsonb, primary key(actor_user_id,request_id));
create table notification_events(id uuid primary key default gen_random_uuid(), recipient_user_id text, actor_user_id text,
 notification_type text, status text default 'pending', data jsonb, skip_reason text, claim_expires_at timestamptz,
 updated_at timestamptz default now(), dedupe_key text unique);
create table follows(follower text, followed text, primary key(follower,followed));
create table blocks(blocker text, blocked text, primary key(blocker,blocked));
create function app.current_user_id() returns text language sql stable as $$select nullif(current_setting('test.user_id',true),'')$$;
create function app.is_mutual(a text,b text) returns boolean language sql stable as $$
 select exists(select 1 from follows where follower=a and followed=b) and exists(select 1 from follows where follower=b and followed=a)$$;
create function app.is_blocked(a text,b text) returns boolean language sql stable as $$
 select exists(select 1 from blocks where (blocker=a and blocked=b) or (blocker=b and blocked=a))$$;
-- Metadata-only adapters, intentionally outside the race assertions.
create function app.user_place_attribute_answers(uuid) returns jsonb language sql stable as $$select '[]'::jsonb$$;
create function app.visit_tags_from_attribute_answers(jsonb) returns text[] language sql immutable as $$select '{}'::text[]$$;
create function app.shared_visit_source_snapshot(uuid) returns jsonb language sql stable as $$select '{}'::jsonb$$;
create function app.queue_notification_event(input_recipient_user_id text,input_actor_user_id text,input_notification_type text,
 input_title text,input_body text,input_deeplink_url text,input_data jsonb,input_dedupe_key text)
 returns uuid language sql volatile as $$
 insert into notification_events(recipient_user_id,actor_user_id,notification_type,data,dedupe_key)
 values(input_recipient_user_id,input_actor_user_id,input_notification_type,input_data,input_dedupe_key)
 on conflict(dedupe_key) do update set dedupe_key=excluded.dedupe_key returning id$$;
alter table profiles add column handle text, add column display_name text, add column avatar_url text,
 add column bio text, add column home_area text, add column created_at timestamptz default now();
alter table feed_events add column standalone_engagement_started_at timestamptz;
create table activity_likes(activity_id uuid references feed_events,user_id text references profiles, primary key(activity_id,user_id));
create table activity_comments(id uuid primary key default gen_random_uuid(),activity_id uuid references feed_events,
 author_user_id text references profiles,body text,client_request_id uuid,created_at timestamptz default now(),unique(author_user_id,client_request_id));
create function app.follows(a text,b text) returns boolean language sql stable as $$select exists(select 1 from follows where follower=a and followed=b)$$;
-- The legacy adapter covers only the visit event shape present in this fixture.
create function app.can_read_legacy_activity_event(viewer text,event_id uuid) returns boolean language sql stable as $$
 select exists(select 1 from feed_events e join place_visits v on v.id=e.visit_id join user_places p on p.id=v.user_place_id
 where e.id=event_id and v.deleted_at is null and p.deleted_at is null and not app.is_blocked(viewer,p.user_id)
 and (p.user_id=viewer or (p.visibility='followers' and app.follows(viewer,p.user_id))))$$;
