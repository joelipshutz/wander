#!/usr/bin/env node

import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const DEFAULT_ENV_FILE = `${homedir()}/.openclaw/workspace/.env.keys`;
const DEFAULT_SMOKE_USER_ID = "user_codex_supabase_smoke";
const DEFAULT_SMOKE_COLLABORATOR_ID = "user_codex_supabase_smoke_collab";
const DEFAULT_SMOKE_STRANGER_ID = "user_codex_supabase_smoke_stranger";
const ENV_KEYS = new Set([
  "WANDER_SUPABASE_DB_URL",
  "WANDER_SUPABASE_PROJECT_REF",
  "WANDER_SUPABASE_DB_PASSWORD",
]);

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    printHelp();
    return;
  }

  loadEnvFile(options.envFile ?? process.env.WANDER_SUPABASE_ENV_FILE ?? DEFAULT_ENV_FILE);

  const smokeUserID = DEFAULT_SMOKE_USER_ID;
  const collaboratorUserID = DEFAULT_SMOKE_COLLABORATOR_ID;
  const strangerUserID = DEFAULT_SMOKE_STRANGER_ID;
  if (options.linked) {
    runLinkedSmokeChecks(smokeUserID, collaboratorUserID, strangerUserID);
    return;
  }
  const dbURL = options.dbURL ?? process.env.WANDER_SUPABASE_DB_URL ?? buildDirectDatabaseURL();
  assertSafeDatabaseURL(dbURL);
  const { default: pg } = await import("pg");
  const { Client } = pg;

  const client = new Client({
    connectionString: dbURL,
    ssl: {
      ca: readFileSync(new URL("./certs/prod-ca-2021.crt", import.meta.url), "utf8"),
      rejectUnauthorized: true,
    },
  });

  try {
    await client.connect();
    await client.query("begin");
    try {
      await client.query(buildSmokeFixtureSQL(smokeUserID, collaboratorUserID, strangerUserID));
      await runOwnPlaceSmokeChecks(client, smokeUserID);
      await runProfileRedesignSmokeChecks(client, smokeUserID, collaboratorUserID);
      await runPlaceListSmokeChecks(client, smokeUserID, collaboratorUserID, strangerUserID);
      await runDiscoverProfileRecommendationSmokeChecks(client, smokeUserID);
      console.log("Supabase smoke test passed: profile updates, mutes, profile insights, semantic saves, lists, photo visibility, and Discover profile recommendations are valid.");
    } finally {
      await client.query("rollback");
    }
  } catch (error) {
    throw sanitizeError(error, dbURL);
  } finally {
    await client.end().catch(() => {});
  }
}

function parseArgs(args) {
  const parsed = {};

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    switch (arg) {
      case "--help":
      case "-h":
        parsed.help = true;
        break;
      case "--env-file":
        parsed.envFile = requiredValue(args, index, arg);
        index += 1;
        break;
      case "--db-url":
        parsed.dbURL = requiredValue(args, index, arg);
        index += 1;
        break;
      case "--linked":
        parsed.linked = true;
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return parsed;
}

function requiredValue(args, index, flag) {
  const value = args[index + 1];
  if (!value || value.startsWith("--")) {
    throw new Error(`${flag} requires a value.`);
  }

  return value;
}

function printHelp() {
  console.log(`
Usage:
  node scripts/supabase-smoke-test.mjs
  node scripts/supabase-smoke-test.mjs --linked

Options:
  --env-file <path>               Env file to load. Defaults to ~/.openclaw/workspace/.env.keys.
  --db-url <postgres-url>          Hosted Postgres URL. Defaults to WANDER_SUPABASE_DB_URL or project ref/password env.
  --linked                         Run the preferred-photo hosted checks through the linked Supabase Management API.

Required env when --db-url is omitted:
  WANDER_SUPABASE_PROJECT_REF
  WANDER_SUPABASE_DB_PASSWORD

Notes:
  Run npm --prefix scripts ci --ignore-scripts once to install the pinned pg dependency.
  Every fixture and behavior mutation runs in one transaction and is rolled back.
`);
}

function runLinkedSmokeChecks(smokeUserID, collaboratorUserID, strangerUserID) {
  const directory = mkdtempSync(join(tmpdir(), "recme-supabase-smoke-"));
  const filePath = join(directory, "linked-smoke.sql");
  const discoverSmokeSQL = loadStrictPgTapSQL(
    new URL("../supabase/tests/discover_profile_recommendations.sql", import.meta.url),
  );
  try {
    writeFileSync(filePath, `${buildLinkedSmokeSQL(smokeUserID, collaboratorUserID, strangerUserID)}\n${discoverSmokeSQL}`, {
      encoding: "utf8",
      mode: 0o600,
    });
    const result = spawnSync(
      "pnpm",
      ["dlx", "supabase", "db", "query", "--linked", "--file", filePath],
      { cwd: process.cwd(), encoding: "utf8", env: process.env },
    );
    if (result.status !== 0) {
      const details = [result.stderr, result.stdout]
        .map((value) => value?.trim())
        .filter(Boolean)
        .join("\n");
      throw new Error(details || "linked Supabase query failed");
    }
    console.log("Supabase smoke test passed: linked profile, mute, photo visibility, preferred-photo, provider-quota, Shared Visits, and Discover profile recommendation contracts are valid.");
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

function loadStrictPgTapSQL(fileURL) {
  const source = readFileSync(fileURL, "utf8");
  const finishStatement = "select * from finish();";
  if (!source.includes(finishStatement)) {
    throw new Error(`pgTAP smoke file is missing its finish statement: ${fileURL.pathname}`);
  }

  return source.replace(
    finishStatement,
    `do $strict_pgtap$
declare
  diagnostics text;
begin
  select string_agg(result.message, E'\\n')
  into diagnostics
  from finish() as result(message);

  if diagnostics is not null then
    raise exception 'pgTAP smoke failures: %', diagnostics;
  end if;
end;
$strict_pgtap$;`,
  );
}

function buildLinkedSmokeSQL(smokeUserID, collaboratorUserID, strangerUserID) {
  const smokeUser = sqlString(smokeUserID);
  const collaboratorUser = sqlString(collaboratorUserID);
  const strangerUser = sqlString(strangerUserID);
  const smokeVisitID = "56000000-0000-0000-0000-000000000001";
  const smokePhotoID = "57000000-0000-0000-0000-000000000001";
  const collaboratorVisitID = "56000000-0000-0000-0000-000000000002";
  const collaboratorPhotoID = "57000000-0000-0000-0000-000000000002";

  return `
begin;

${buildSmokeFixtureSQL(smokeUserID, collaboratorUserID, strangerUserID)}

create temporary table smoke_shared_visit_invitation (
  participant_id uuid primary key,
  invitation_generation integer not null,
  snapshot_revision integer not null
) on commit drop;
grant select, insert on smoke_shared_visit_invitation to authenticated;

insert into public.follows (follower_user_id, followed_user_id, source)
values
  (${collaboratorUser}, ${smokeUser}, 'profile'),
  (${smokeUser}, ${collaboratorUser}, 'profile')
on conflict (follower_user_id, followed_user_id) do nothing;

update public.user_places up
set status = 'been', visibility = 'followers', deleted_at = null
from public.places p
where up.place_id = p.id
  and up.user_id in (${smokeUser}, ${collaboratorUser})
  and p.source_provider = 'codex_smoke'
  and p.source_provider_place_id = 'place-list-rpc-smoke';

insert into public.place_visits (id, user_place_id, visited_at, note, backfilled_from_user_place, deleted_at)
select
  '${smokeVisitID}'::uuid,
  up.id,
  now(),
  'Rolled back linked preferred-photo smoke visit',
  false,
  null
from public.user_places up
join public.places p on p.id = up.place_id
where up.user_id = ${smokeUser}
  and p.source_provider = 'codex_smoke'
  and p.source_provider_place_id = 'place-list-rpc-smoke'
on conflict (id) do update set deleted_at = null, updated_at = now();

insert into public.visit_photos (
  id, visit_id, storage_bucket, storage_path, content_type, sort_order, upload_state, deleted_at
)
values (
  '${smokePhotoID}'::uuid,
  '${smokeVisitID}'::uuid,
  'visit-photos',
  ${smokeUser} || '/${smokeVisitID}/${smokePhotoID}.jpg',
  'image/jpeg',
  0,
  'uploaded',
  null
)
on conflict (id) do update set upload_state = 'uploaded', deleted_at = null, updated_at = now();

insert into public.place_visits (id, user_place_id, visited_at, note, backfilled_from_user_place, deleted_at)
select
  '${collaboratorVisitID}'::uuid,
  up.id,
  now(),
  'Rolled back linked collaborator cover-photo smoke visit',
  false,
  null
from public.user_places up
join public.places p on p.id = up.place_id
where up.user_id = ${collaboratorUser}
  and p.source_provider = 'codex_smoke'
  and p.source_provider_place_id = 'place-list-rpc-smoke'
on conflict (id) do update set deleted_at = null, updated_at = now();

insert into public.visit_photos (
  id, visit_id, storage_bucket, storage_path, content_type, sort_order, upload_state, deleted_at
)
values (
  '${collaboratorPhotoID}'::uuid,
  '${collaboratorVisitID}'::uuid,
  'visit-photos',
  ${collaboratorUser} || '/${collaboratorVisitID}/${collaboratorPhotoID}.jpg',
  'image/jpeg',
  0,
  'uploaded',
  null
)
on conflict (id) do update set upload_state = 'uploaded', deleted_at = null, updated_at = now();

do $metadata$
declare
  valid boolean;
begin
  select
    not p.prosecdef
    and 'search_path=public, app' = any(p.proconfig)
    and has_function_privilege('authenticated', p.oid, 'execute')
    and not has_function_privilege('anon', p.oid, 'execute')
  into valid
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'first_visible_place_photo'
    and pg_get_function_identity_arguments(p.oid) = 'input_place_id uuid';
  if valid is distinct from true then
    raise exception 'preferred-place-photo metadata contract failed';
  end if;
end
$metadata$;

do $list_cover_metadata$
declare
  valid boolean;
begin
  select
    not p.prosecdef
    and 'search_path=public, app' = any(p.proconfig)
    and has_function_privilege('authenticated', p.oid, 'execute')
    and not has_function_privilege('anon', p.oid, 'execute')
  into valid
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'first_visible_place_photo_by_users'
    and pg_get_function_identity_arguments(p.oid) = 'input_place_id uuid, input_user_ids text[]';
  if valid is distinct from true then
    raise exception 'list-cover contributor photo metadata contract failed';
  end if;
end
$list_cover_metadata$;

do $quota_metadata$
declare
  valid boolean;
begin
  select
    p.prosecdef
    and 'search_path=public, app' = any(p.proconfig)
    and has_function_privilege('authenticated', p.oid, 'execute')
    and not has_function_privilege('anon', p.oid, 'execute')
    and not has_table_privilege('authenticated', 'app.place_photo_request_counters', 'select')
    and not has_table_privilege('authenticated', 'app.place_photo_request_counters', 'insert')
  into valid
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'consume_place_photo_quota'
    and pg_get_function_identity_arguments(p.oid) = '';
  if valid is distinct from true then
    raise exception 'place-photo quota metadata contract failed';
  end if;
end
$quota_metadata$;

do $profile_metadata$
declare
  valid boolean;
begin
  select
    not p.prosecdef
    and 'search_path=app, public' = any(p.proconfig)
    and has_function_privilege('authenticated', p.oid, 'execute')
    and not has_function_privilege('anon', p.oid, 'execute')
  into valid
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'update_own_profile'
    and pg_get_function_identity_arguments(p.oid) =
      'input_bio text, input_home_area text, input_default_visibility text, input_is_private_profile boolean, input_display_name text, input_handle text';
  if valid is distinct from true then
    raise exception 'profile update metadata contract failed';
  end if;
end
$profile_metadata$;

do $member_profile_metadata$
declare
  valid boolean;
begin
  select
    not p.prosecdef
    and 'search_path=app, public' = any(p.proconfig)
    and has_function_privilege('authenticated', p.oid, 'execute')
    and not has_function_privilege('anon', p.oid, 'execute')
  into valid
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'profile_detail'
    and pg_get_function_identity_arguments(p.oid) = 'input_profile_id text';
  if valid is distinct from true then
    raise exception 'member profile detail metadata contract failed';
  end if;
end
$member_profile_metadata$;

set local role authenticated;
select set_config('request.jwt.claim.sub', ${smokeUser}, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $profile_behavior$
declare updated jsonb; muted_id text; visible_city text; member_home text; member_relationship text;
begin
  updated := public.update_own_profile(
    'Backend smoke-test profile.', 'Test', 'mutuals', true, 'Backend Smoke Tester', 'recme_smoke_profile'
  );
  if updated->>'default_visibility' is distinct from 'mutuals'
     or (updated->>'is_private_profile')::boolean is distinct from true then
    raise exception 'profile preference persistence failed';
  end if;

  perform public.mute_profile(${collaboratorUser});
  select id into muted_id from public.muted_profiles() where id = ${collaboratorUser};
  if muted_id is distinct from ${collaboratorUser} then
    raise exception 'profile mute persistence failed';
  end if;

  select locality into visible_city
  from public.profile_visible_places(${smokeUser}, null, null)
  limit 1;
  if visible_city is distinct from 'Los Angeles' then
    raise exception 'profile geography payload failed';
  end if;

  select home_area, relationship into member_home, member_relationship
  from public.profile_detail(${collaboratorUser});
  if member_home is distinct from 'Test'
     or member_relationship not in ('follower', 'mutual', 'non_follower') then
    raise exception 'member profile detail payload failed';
  end if;

  perform public.unmute_profile(${collaboratorUser});
  perform public.update_own_profile(null, null, null, false, null, null);
  update public.user_places up
  set visibility = 'followers', updated_at = now()
  from public.places p
  where up.place_id = p.id
    and up.user_id = ${smokeUser}
    and p.source_provider = 'codex_smoke'
    and p.source_provider_place_id = 'place-list-rpc-smoke';
end
$profile_behavior$;

set local role authenticated;
select set_config('request.jwt.claim.sub', ${smokeUser}, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $quota_behavior$
begin
  if public.consume_place_photo_quota() is distinct from true then
    raise exception 'place-photo quota rejected an authenticated request below the caps';
  end if;
end
$quota_behavior$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', ${smokeUser}, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $owner$
declare resolved uuid;
begin
  select photo_id into resolved
  from public.first_visible_place_photo((
    select p.id from public.places p
    where p.source_provider = 'codex_smoke' and p.source_provider_place_id = 'place-list-rpc-smoke'
  ));
  if resolved is distinct from '${smokePhotoID}'::uuid then
    raise exception 'owner preferred-place-photo visibility failed';
  end if;
end
$owner$;

do $owner_scoped_photos$
declare owner_photo uuid; collaborator_photo uuid;
begin
  select photo_id into owner_photo
  from public.first_visible_place_photo_by_users((
    select p.id from public.places p
    where p.source_provider = 'codex_smoke' and p.source_provider_place_id = 'place-list-rpc-smoke'
  ), array[${smokeUser}]::text[]);
  if owner_photo is distinct from '${smokePhotoID}'::uuid then
    raise exception 'owner-scoped list-cover photo selection failed';
  end if;

  select photo_id into collaborator_photo
  from public.first_visible_place_photo_by_users((
    select p.id from public.places p
    where p.source_provider = 'codex_smoke' and p.source_provider_place_id = 'place-list-rpc-smoke'
  ), array[${collaboratorUser}]::text[]);
  if collaborator_photo is distinct from '${collaboratorPhotoID}'::uuid then
    raise exception 'collaborator-scoped list-cover photo selection failed';
  end if;
end
$owner_scoped_photos$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', ${collaboratorUser}, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $follower$
declare
  resolved uuid;
  can_read boolean;
  follows_owner boolean;
  blocked boolean;
  visible_user_places integer;
  visible_visits integer;
  visible_photos integer;
  visible_places integer;
begin
  select photo_id into resolved
  from public.first_visible_place_photo((
    select p.id from public.places p
    where p.source_provider = 'codex_smoke' and p.source_provider_place_id = 'place-list-rpc-smoke'
  ));
  if resolved is distinct from '${smokePhotoID}'::uuid then
    select app.follows(${collaboratorUser}, ${smokeUser}),
           app.is_blocked(${collaboratorUser}, ${smokeUser}),
           app.can_read_user_place(${collaboratorUser}, ${smokeUser}, 'followers')
      into follows_owner, blocked, can_read;
    select count(*)::integer into visible_user_places
      from public.user_places where user_id = ${smokeUser} and deleted_at is null;
    select count(*)::integer into visible_visits
      from public.place_visits where id = '${smokeVisitID}'::uuid;
    select count(*)::integer into visible_photos
      from public.visit_photos where id = '${smokePhotoID}'::uuid;
    select count(*)::integer into visible_places
      from public.places
      where source_provider = 'codex_smoke' and source_provider_place_id = 'place-list-rpc-smoke';
    raise exception 'follower preferred-place-photo visibility failed'
      using detail = format(
        'current_user=%s follows=%s blocked=%s can_read=%s user_places=%s visits=%s photos=%s places=%s resolved=%s',
        app.current_user_id(), follows_owner, blocked, can_read, visible_user_places,
        visible_visits, visible_photos, visible_places, resolved
      );
  end if;
end
$follower$;

do $follower_scoped_photo$
declare visible_count integer;
begin
  select count(*)::integer into visible_count
  from public.first_visible_place_photo_by_users((
    select p.id from public.places p
    where p.source_provider = 'codex_smoke' and p.source_provider_place_id = 'place-list-rpc-smoke'
  ), array[${strangerUser}]::text[]);
  if visible_count <> 0 then
    raise exception 'list-cover contributor filter admitted an unrelated user photo';
  end if;
end
$follower_scoped_photo$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', ${strangerUser}, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $stranger$
declare visible_count integer;
begin
  select count(*)::integer into visible_count
  from public.first_visible_place_photo((
    select p.id from public.places p
    where p.source_provider = 'codex_smoke' and p.source_provider_place_id = 'place-list-rpc-smoke'
  ));
  if visible_count <> 0 then
    raise exception 'stranger preferred-place-photo visibility failed';
  end if;
end
$stranger$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', ${smokeUser}, true);
select set_config('request.jwt.claim.role', 'authenticated', true);

insert into smoke_shared_visit_invitation(participant_id, invitation_generation, snapshot_revision)
select invite.participant_id, invite.invitation_generation, 1
from public.create_shared_visit_invites(
  '${smokeVisitID}'::uuid,
  array[${collaboratorUser}]::text[]
) invite;

do $shared_invite$
declare
  notification_body text;
begin
  if (select count(*) from smoke_shared_visit_invitation) <> 1 then
    raise exception 'shared visit invite creation failed';
  end if;

  select event.body into notification_body
  from public.notification_events event
  where event.recipient_user_id = ${collaboratorUser}
    and event.notification_type = 'shared_visit'
  order by event.created_at desc
  limit 1;
  if notification_body not like '% with you. Add your details from this visit'
     or notification_body like '%Add your version of the visit%' then
    raise exception 'shared visit notification copy failed';
  end if;
end
$shared_invite$;

do $shared_owner_pending$
declare
  companion_id text;
  selected_invitee_id text;
begin
  select companion.companion_user_id into companion_id
  from public.get_shared_visit_companion_context(
    array['${smokeVisitID}'::uuid]
  ) companion;
  if companion_id is distinct from ${collaboratorUser} then
    raise exception 'pending shared visit companion attribution failed';
  end if;

  select invitee.invitee_user_id into selected_invitee_id
  from public.list_shared_visit_invitees('${smokeVisitID}'::uuid) invitee;
  if selected_invitee_id is distinct from ${collaboratorUser} then
    raise exception 'shared visit invitee listing failed';
  end if;
end
$shared_owner_pending$;

select set_config('request.jwt.claim.sub', ${collaboratorUser}, true);
do $shared_context$
declare
  smoke_invitation smoke_shared_visit_invitation;
  inbox_count integer;
  context_note text;
begin
  select * into smoke_invitation from smoke_shared_visit_invitation;
  select count(*)::integer into inbox_count
  from public.list_shared_visit_inbox(null, 50) inbox
  where inbox.participant_id = smoke_invitation.participant_id
    and inbox.invitation_generation = smoke_invitation.invitation_generation;
  if inbox_count <> 1 then
    raise exception 'shared visit inbox visibility failed';
  end if;

  select context.source_snapshot->>'note' into context_note
  from public.get_shared_visit_context(
    smoke_invitation.participant_id,
    smoke_invitation.invitation_generation
  ) context;
  if context_note is distinct from 'Rolled back linked preferred-photo smoke visit' then
    raise exception 'shared visit invitation snapshot failed';
  end if;
end
$shared_context$;

do $shared_accept$
declare
  smoke_invitation smoke_shared_visit_invitation;
  accepted jsonb;
  retried jsonb;
begin
  select * into smoke_invitation from smoke_shared_visit_invitation;
  accepted := public.accept_shared_visit(
    smoke_invitation.participant_id,
    smoke_invitation.invitation_generation,
    smoke_invitation.snapshot_revision,
    '58000000-0000-0000-0000-000000000001'::uuid,
    '58000000-0000-0000-0000-000000000002'::uuid,
    '58000000-0000-0000-0000-000000000003'::uuid,
    '{"visibility":"mutuals"}'::jsonb,
    '{"visited_at":"2026-07-13T12:00:00Z","note":"Collaborator smoke version","rating_score":4.5,"attribute_answers":[]}'::jsonb,
    '[]'::jsonb,
    array[]::uuid[]
  );
  if accepted->>'status' is distinct from 'accepted'
     or accepted->>'visit_id' is distinct from '58000000-0000-0000-0000-000000000003' then
    raise exception 'shared visit acceptance failed';
  end if;

  retried := public.accept_shared_visit(
    smoke_invitation.participant_id,
    smoke_invitation.invitation_generation,
    smoke_invitation.snapshot_revision,
    '58000000-0000-0000-0000-000000000001'::uuid,
    '58000000-0000-0000-0000-000000000002'::uuid,
    '58000000-0000-0000-0000-000000000003'::uuid,
    '{"visibility":"mutuals"}'::jsonb,
    '{"visited_at":"2026-07-13T12:00:00Z","note":"Collaborator smoke version","rating_score":4.5,"attribute_answers":[]}'::jsonb,
    '[]'::jsonb,
    array[]::uuid[]
  );
  if retried->>'visit_id' is distinct from accepted->>'visit_id'
     or (select count(*) from public.place_visits where id = '58000000-0000-0000-0000-000000000003'::uuid) <> 1 then
    raise exception 'shared visit exactly-once retry failed';
  end if;
end
$shared_accept$;

do $shared_companion$
declare
  companion_id text;
begin
  select companion.companion_user_id into companion_id
  from public.get_shared_visit_companion_context(
    array['58000000-0000-0000-0000-000000000003'::uuid]
  ) companion;
  if companion_id is distinct from ${smokeUser} then
    raise exception 'shared visit companion attribution failed';
  end if;
end
$shared_companion$;

select set_config('request.jwt.claim.sub', ${smokeUser}, true);
do $shared_owner_remote_companion$
declare
  companion_id text;
begin
  select companion.companion_user_id into companion_id
  from public.get_shared_visit_companion_context(
    array['58000000-0000-0000-0000-000000000003'::uuid]
  ) companion;
  if companion_id is distinct from ${smokeUser} then
    raise exception 'shared visit viewer attribution on a readable remote visit failed';
  end if;
end
$shared_owner_remote_companion$;

do $shared_remove$
declare
  active_count integer;
begin
  select count(*)::integer into active_count
  from public.set_shared_visit_invitees(
    '${smokeVisitID}'::uuid,
    array[]::text[]
  );
  if active_count <> 0 then
    raise exception 'shared visit exact invitee removal failed';
  end if;
end
$shared_remove$;

reset role;
do $shared_remove_persistence$
declare
  participant_status text;
  recipient_visit_count integer;
begin

  select participant.status into participant_status
  from public.shared_visit_participants participant
  where participant.id = (select participant_id from smoke_shared_visit_invitation);
  if participant_status is distinct from 'removed' then
    raise exception 'shared visit removed attribution persisted';
  end if;

  select count(*)::integer into recipient_visit_count
  from public.place_visits visit
  where visit.id = '58000000-0000-0000-0000-000000000003'::uuid
    and visit.deleted_at is null;
  if recipient_visit_count <> 1 then
    raise exception 'shared visit removal deleted the recipient independent visit';
  end if;
end
$shared_remove_persistence$;

reset role;
rollback;
`;
}

function loadEnvFile(filePath) {
  if (!filePath || !existsSync(filePath)) return;

  const lines = readFileSync(filePath, "utf8").split(/\r?\n/);
  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;

    const separatorIndex = line.indexOf("=");
    if (separatorIndex <= 0) continue;

    const key = line.slice(0, separatorIndex).trim();
    let value = line.slice(separatorIndex + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    if (ENV_KEYS.has(key) && !process.env[key]) {
      process.env[key] = value;
    }
  }
}

function buildDirectDatabaseURL() {
  const projectRef = process.env.WANDER_SUPABASE_PROJECT_REF;
  const password = process.env.WANDER_SUPABASE_DB_PASSWORD;

  if (!projectRef || !password) {
    throw new Error(
      "Missing WANDER_SUPABASE_PROJECT_REF or WANDER_SUPABASE_DB_PASSWORD. " +
        "Set WANDER_SUPABASE_DB_URL or provide --db-url.",
    );
  }

  return `postgresql://postgres:${encodeURIComponent(password)}@db.${projectRef}.supabase.co:5432/postgres`;
}

function assertSafeDatabaseURL(dbURL) {
  const parsed = new URL(dbURL);
  const tlsOverrides = ["ssl", "sslmode", "sslrootcert", "sslcert", "sslkey"];
  const suppliedOverrides = tlsOverrides.filter((key) => parsed.searchParams.has(key));
  if (suppliedOverrides.length > 0) {
    throw new Error(`Database URL must not override pinned TLS settings: ${suppliedOverrides.join(", ")}`);
  }
}

function buildSmokeFixtureSQL(smokeUserID, collaboratorUserID, strangerUserID) {
  const smokeUser = sqlString(smokeUserID);
  const collaboratorUser = sqlString(collaboratorUserID);
  const strangerUser = sqlString(strangerUserID);
  const sourceProvider = sqlString("codex_smoke");
  const sourceProviderPlaceID = sqlString("place-list-rpc-smoke");

  return `
insert into public.profiles (
  id,
  handle,
  display_name,
  bio,
  home_area,
  default_visibility,
  is_private_profile,
  deleted_at
)
values
  (${smokeUser}, 'codex_smoke', 'Codex Smoke Test', 'Backend smoke-test profile.', 'Test', 'followers', false, null),
  (${collaboratorUser}, 'codex_smoke_collab', 'Codex Smoke Collaborator', 'Backend smoke-test collaborator.', 'Test', 'followers', false, null),
  (${strangerUser}, 'codex_smoke_stranger', 'Codex Smoke Stranger', 'Backend smoke-test stranger.', 'Test', 'followers', false, null)
on conflict (id) do update
set
  handle = excluded.handle,
  display_name = excluded.display_name,
  bio = excluded.bio,
  home_area = excluded.home_area,
  default_visibility = excluded.default_visibility,
  is_private_profile = false,
  deleted_at = null,
  updated_at = now();

delete from public.blocks
where blocker_user_id in (${smokeUser}, ${collaboratorUser}, ${strangerUser})
  and blocked_user_id in (${smokeUser}, ${collaboratorUser}, ${strangerUser});

delete from public.follows
where follower_user_id in (${smokeUser}, ${collaboratorUser}, ${strangerUser})
  and followed_user_id in (${smokeUser}, ${collaboratorUser}, ${strangerUser});

insert into public.places (
  canonical_name,
  category,
  primary_category,
  subcategory,
  raw_provider_type,
  category_source,
  locality,
  region,
  country,
  latitude,
  longitude,
  source_provider,
  source_provider_place_id,
  confidence
)
values (
  'Codex Smoke Coffee',
  'coffee_tea_sweets',
  'coffee_tea_sweets',
  'Coffee shop',
  'coffee shop',
  'deterministic',
  'Los Angeles',
  'CA',
  'United States',
  34.052235,
  -118.243683,
  ${sourceProvider},
  ${sourceProviderPlaceID},
  1
)
on conflict (source_provider, source_provider_place_id) do update
set
  canonical_name = excluded.canonical_name,
  category = excluded.category,
  primary_category = excluded.primary_category,
  subcategory = excluded.subcategory,
  raw_provider_type = excluded.raw_provider_type,
  category_source = excluded.category_source,
  locality = excluded.locality,
  region = excluded.region,
  country = excluded.country,
  latitude = excluded.latitude,
  longitude = excluded.longitude,
  confidence = excluded.confidence,
  updated_at = now();

insert into public.user_places (
  user_id,
  place_id,
  status,
  note,
  rating_signal,
  visibility,
  nearby_confirmed,
  source_type,
  category_override,
  subcategory_override,
  category_override_source,
  category_override_confidence,
  deleted_at
)
select
  fixture_user.user_id,
  p.id,
  'wanna_go',
  'Smoke test fixture',
  null,
  'followers',
  false,
  'manual',
  null,
  null,
  null,
  null,
  null
from public.places p
cross join (
  values (${smokeUser}), (${collaboratorUser})
) as fixture_user(user_id)
where p.source_provider = ${sourceProvider}
  and p.source_provider_place_id = ${sourceProviderPlaceID}
on conflict (user_id, place_id) do update
set
  status = excluded.status,
  note = excluded.note,
  visibility = excluded.visibility,
  source_type = excluded.source_type,
  deleted_at = null,
  updated_at = now();
`;
}

async function runOwnPlaceSmokeChecks(client, smokeUserID) {
  await assertOwnPlaceRPCMetadata(client);
  await setAuthenticatedUser(client, smokeUserID);

  const place = {
    canonical_name: "Codex Smoke Semantic Save",
    category: "restaurants_food",
    primary_category: "restaurants_food",
    subcategory: "Restaurant",
    category_source: "deterministic",
    category_confidence: 1,
    raw_provider_type: "restaurant",
    latitude: 34.05231,
    longitude: -118.24371,
    source_provider: "codex_smoke",
    source_provider_place_id: "semantic-place-attribute-save",
    confidence: 1,
  };
  const userPlace = {
    status: "been",
    visibility: "followers",
    nearby_confirmed: false,
    source_type: "manual",
    rating_score: 3,
  };
  const attributes = [
    {
      question_key: "personal_labels",
      value_type: "personal_label",
      value: ["date night"],
    },
    {
      question_key: "restaurant_cuisine",
      value_type: "restaurant_cuisine",
      value: "Thai",
    },
  ];

  const saved = await expectQuery(
    client,
    "authenticated public.save_own_place accepts semantic map attributes",
    "select public.save_own_place($1::jsonb, $2::jsonb, $3::jsonb) as saved",
    [JSON.stringify(place), JSON.stringify(userPlace), JSON.stringify(attributes)],
    (result) => Boolean(result.rows[0]?.saved?.user_place_id && result.rows[0]?.saved?.place_id),
  );
  const savedUserPlaceID = saved.rows[0].saved.user_place_id;

  await expectQuery(
    client,
    "semantic map save commits the place and user save atomically",
    `
      select p.canonical_name, up.status, up.rating_score::double precision as rating_score
      from public.user_places up
      join public.places p on p.id = up.place_id
      where up.id = $1::uuid
        and up.user_id = $2
        and up.deleted_at is null
    `,
    [savedUserPlaceID, smokeUserID],
    (result) => result.rows.length === 1
      && result.rows[0].canonical_name === place.canonical_name
      && result.rows[0].status === "been"
      && result.rows[0].rating_score === 3,
  );

  await expectQuery(
    client,
    "semantic map save preserves both attribute types and values",
    `
      select question_key, value_type, value
      from public.place_attributes
      where user_place_id = $1::uuid
      order by question_key
    `,
    [savedUserPlaceID],
    (result) => {
      const byQuestion = new Map(result.rows.map((row) => [row.question_key, row]));
      const labels = byQuestion.get("personal_labels");
      const cuisine = byQuestion.get("restaurant_cuisine");
      return result.rows.length === 2
        && labels?.value_type === "personal_label"
        && Array.isArray(labels.value)
        && labels.value.length === 1
        && labels.value[0] === "date night"
        && cuisine?.value_type === "restaurant_cuisine"
        && cuisine.value === "Thai";
    },
  );

  await client.query("reset role");
}

async function runProfileRedesignSmokeChecks(client, smokeUserID, collaboratorUserID) {
  await expectQuery(
    client,
    "profile update and mute RPC metadata",
    `
      select
        not update_proc.prosecdef as update_invoker,
        'search_path=public, app' = any(update_proc.proconfig) as update_search_path,
        not mute_proc.prosecdef as mute_invoker,
        'search_path=public, app' = any(mute_proc.proconfig) as mute_search_path,
        has_function_privilege(
          'authenticated',
          'public.update_own_profile(text,text,text,boolean,text,text)',
          'execute'
        ) as update_authenticated,
        not has_function_privilege(
          'anon',
          'public.update_own_profile(text,text,text,boolean,text,text)',
          'execute'
        ) as update_anon_denied
      from pg_proc update_proc
      cross join pg_proc mute_proc
      where update_proc.oid = 'app.update_own_profile(text,text,text,boolean,text,text)'::regprocedure
        and mute_proc.oid = 'app.mute_profile(text)'::regprocedure
    `,
    [],
    (result) => {
      const row = result.rows[0];
      return row?.update_invoker === true
        && row?.update_search_path === true
        && row?.mute_invoker === true
        && row?.mute_search_path === true
        && row?.update_authenticated === true
        && row?.update_anon_denied === true;
    },
  );

  await expectQuery(
    client,
    "member profile detail RPC metadata",
    `
      select
        not proc.prosecdef as invoker,
        'search_path=app, public' = any(proc.proconfig) as search_path,
        has_function_privilege('authenticated', proc.oid, 'execute') as authenticated,
        not has_function_privilege('anon', proc.oid, 'execute') as anon_denied
      from pg_proc proc
      where proc.oid = 'public.profile_detail(text)'::regprocedure
    `,
    [],
    (result) => {
      const row = result.rows[0];
      return row?.invoker === true
        && row?.search_path === true
        && row?.authenticated === true
        && row?.anon_denied === true;
    },
  );

  await setAuthenticatedUser(client, smokeUserID);
  await expectQuery(
    client,
    "authenticated profile details and privacy preferences persist",
    `
      select public.update_own_profile(
        'Backend smoke-test profile.',
        'Test',
        'mutuals',
        true,
        'Backend Smoke Tester',
        'recme_smoke_profile'
      ) as profile
    `,
    [],
    (result) => result.rows[0]?.profile?.default_visibility === "mutuals"
      && result.rows[0]?.profile?.is_private_profile === true
      && result.rows[0]?.profile?.display_name === "Backend Smoke Tester"
      && result.rows[0]?.profile?.handle === "recme_smoke_profile"
      && Boolean(result.rows[0]?.profile?.created_at),
  );

  await expectQuery(
    client,
    "authenticated mute is owner-private and listable",
    `
      with muted as (select public.mute_profile($1))
      select profiles.id
      from public.muted_profiles() profiles
      cross join muted
      where profiles.id = $1
    `,
    [collaboratorUserID],
    (result) => result.rows[0]?.id === collaboratorUserID,
  );

  await expectQuery(
    client,
    "authenticated viewer can hydrate another member profile",
    `
      select id, home_area, created_at, relationship
      from public.profile_detail($1)
    `,
    [collaboratorUserID],
    (result) => result.rows[0]?.id === collaboratorUserID
      && result.rows[0]?.home_area === "Test"
      && Boolean(result.rows[0]?.created_at)
      && ["follower", "mutual", "non_follower"].includes(result.rows[0]?.relationship),
  );

  await expectQuery(
    client,
    "profile insight payload includes geography and owner avatar column",
    `
      select locality, region, country, owner_avatar_url,
             visited_at, saved_at, created_at, updated_at
      from public.profile_visible_places($1, null, null)
      limit 1
    `,
    [smokeUserID],
    (result) => result.rows[0]?.locality === "Los Angeles"
      && result.rows[0]?.region === "CA"
      && result.rows[0]?.country === "United States"
      && Object.hasOwn(result.rows[0] ?? {}, "owner_avatar_url")
      && Object.hasOwn(result.rows[0] ?? {}, "visited_at")
      && Boolean(result.rows[0]?.saved_at)
      && Boolean(result.rows[0]?.created_at)
      && Boolean(result.rows[0]?.updated_at),
  );

  await expectQuery(
    client,
    "authenticated user can remove a mute",
    `
      with unmuted as (select public.unmute_profile($1))
      select count(profiles.id)::integer as count
      from unmuted
      left join public.muted_profiles() profiles on profiles.id = $1
    `,
    [collaboratorUserID],
    (result) => result.rows[0]?.count === 0,
  );

  await client.query("reset role");
}

async function runDiscoverProfileRecommendationSmokeChecks(client, smokeUserID) {
  const fixture = {
    viewer: smokeUserID,
    followsViewer: "user_codex_discover_smoke_follows_viewer",
    bridge: "user_codex_discover_smoke_bridge",
    shared: "user_codex_discover_smoke_shared",
    followed: "user_codex_discover_smoke_followed",
    private: "user_codex_discover_smoke_private",
    blocked: "user_codex_discover_smoke_blocked",
    blocker: "user_codex_discover_smoke_blocker",
    fallback: "user_codex_discover_smoke_fallback",
  };
  const fixtureIDs = Object.values(fixture);

  await client.query("reset role");
  await expectQuery(
    client,
    "create rolled-back Discover profile fixtures",
    `
      insert into public.profiles (
        id,
        handle,
        display_name,
        bio,
        home_area,
        default_visibility,
        is_private_profile,
        created_at,
        deleted_at
      )
      values
        ($1, 'codex_discover_viewer', 'Discover Smoke Viewer', null, 'Test', 'followers', false, '2024-01-01T00:00:00Z', null),
        ($2, 'codex_discover_follows', 'Discover Follows Viewer', null, 'Test', 'followers', false, '2024-02-01T00:00:00Z', null),
        ($3, 'codex_discover_bridge', 'Discover Bridge', null, 'Test', 'followers', false, '2024-03-01T00:00:00Z', null),
        ($4, 'codex_discover_shared', 'Discover Shared Follow', null, 'Test', 'followers', false, '2024-04-01T00:00:00Z', null),
        ($5, 'codex_discover_followed', 'Discover Already Followed', null, 'Test', 'followers', false, '2024-05-01T00:00:00Z', null),
        ($6, 'codex_discover_private', 'Discover Private', null, 'Test', 'followers', true, '2100-03-01T00:00:00Z', null),
        ($7, 'codex_discover_blocked', 'Discover Blocked', null, 'Test', 'followers', false, '2100-04-01T00:00:00Z', null),
        ($8, 'codex_discover_blocker', 'Discover Blocker', null, 'Test', 'followers', false, '2100-05-01T00:00:00Z', null),
        ($9, 'codex_discover_fallback', 'Discover Suggested', null, 'Test', 'followers', false, '2100-06-01T00:00:00Z', null)
      on conflict (id) do update
      set
        handle = excluded.handle,
        display_name = excluded.display_name,
        bio = excluded.bio,
        home_area = excluded.home_area,
        default_visibility = excluded.default_visibility,
        is_private_profile = excluded.is_private_profile,
        created_at = excluded.created_at,
        deleted_at = null,
        updated_at = now()
      returning id
    `,
    fixtureIDs,
    (result) => result.rows.length === fixtureIDs.length
      && result.rows.every((row) => fixtureIDs.includes(row.id)),
  );

  await client.query(
    `
      delete from public.follows
      where follower_user_id = any($1::text[])
         or followed_user_id = any($1::text[])
    `,
    [fixtureIDs],
  );
  await client.query(
    `
      delete from public.blocks
      where blocker_user_id = any($1::text[])
         or blocked_user_id = any($1::text[])
    `,
    [fixtureIDs],
  );
  await expectQuery(
    client,
    "create rolled-back Discover follow graph",
    `
      insert into public.follows (follower_user_id, followed_user_id, source)
      values
        ($1, $2, 'profile'),
        ($2, $3, 'profile'),
        ($3, $4, 'profile'),
        ($2, $5, 'profile'),
        ($6, $9, 'profile'),
        ($9, $6, 'profile'),
        ($6, $5, 'profile')
      on conflict (follower_user_id, followed_user_id) do update
      set source = excluded.source, updated_at = now()
      returning follower_user_id, followed_user_id
    `,
    [
      fixture.followsViewer,
      fixture.viewer,
      fixture.bridge,
      fixture.shared,
      fixture.followed,
      fixture.private,
      fixture.blocked,
      fixture.blocker,
      fixture.fallback,
    ],
    (result) => result.rows.length === 7,
  );
  await expectQuery(
    client,
    "create rolled-back Discover block graph",
    `
      insert into public.blocks (blocker_user_id, blocked_user_id)
      values
        ($1, $2),
        ($3, $1)
      on conflict (blocker_user_id, blocked_user_id) do nothing
      returning blocker_user_id, blocked_user_id
    `,
    [fixture.viewer, fixture.blocked, fixture.blocker],
    (result) => result.rows.length === 2,
  );

  const publicSignatures = [
    "public.discover_profile_recommendations(integer)",
    "public.search_profiles_by_handle(text)",
    "public.profile_following(text)",
    "public.profile_followers(text)",
    "public.follow_user(text,text)",
  ];
  const appSignatures = publicSignatures.map((signature) => signature.replace("public.", "app."));

  await expectQuery(
    client,
    "Discover RPC grants match the authenticated iOS boundary",
    `
      select
        count(*)::integer as count,
        bool_and(has_function_privilege('authenticated', signature, 'execute')) as authenticated_execute,
        bool_and(not has_function_privilege('anon', signature, 'execute')) as anon_denied
      from unnest($1::text[]) as rpc_signatures(signature)
    `,
    [publicSignatures.concat(appSignatures)],
    (result) => result.rows[0]?.count === publicSignatures.length + appSignatures.length
      && result.rows[0]?.authenticated_execute === true
      && result.rows[0]?.anon_denied === true,
  );
  await expectQuery(
    client,
    "app Discover RPCs remain security invoker with pinned search paths",
    `
      select count(*)::integer as count
      from unnest($1::text[]) as rpc_signatures(signature)
      join pg_proc proc on proc.oid = to_regprocedure(rpc_signatures.signature)
      where not proc.prosecdef
        and 'search_path=public, app' = any(coalesce(proc.proconfig, array[]::text[]))
    `,
    [appSignatures],
    (result) => result.rows[0]?.count === appSignatures.length,
  );
  await expectQuery(
    client,
    "public Discover RPCs remain security invoker with pinned search paths",
    `
      select count(*)::integer as count
      from unnest($1::text[]) as rpc_signatures(signature)
      join pg_proc proc on proc.oid = to_regprocedure(rpc_signatures.signature)
      where not proc.prosecdef
        and 'search_path=app, public' = any(coalesce(proc.proconfig, array[]::text[]))
    `,
    [publicSignatures],
    (result) => result.rows[0]?.count === publicSignatures.length,
  );

  await setAuthenticatedUser(client, fixture.viewer);
  await expectQuery(
    client,
    "authenticated Discover recommendations enforce eligibility and ranking",
    `
      select id, reason_kind, shared_follow_count, result_rank
      from public.discover_profile_recommendations(50)
      where id = any($1::text[])
      order by result_rank
    `,
    [fixtureIDs],
    (result) => {
      const rows = result.rows;
      return rows.length === 3
        && rows[0]?.id === fixture.followsViewer
        && rows[0]?.reason_kind === "follows_you"
        && rows[0]?.result_rank === 1
        && rows[1]?.id === fixture.shared
        && rows[1]?.reason_kind === "shared_follows"
        && rows[1]?.shared_follow_count === 1
        && rows[1]?.result_rank === 2
        && rows[2]?.id === fixture.fallback
        && rows[2]?.reason_kind === "suggested"
        && rows[2]?.result_rank === 3;
    },
  );
  await expectQuery(
    client,
    "Discover recommendation limits are honored and safely clamped",
    `
      select
        (select count(*)::integer from public.discover_profile_recommendations(2)) as requested_count,
        (select count(*)::integer from public.discover_profile_recommendations(1000)) as clamped_count
    `,
    [],
    (result) => result.rows[0]?.requested_count === 2
      && result.rows[0]?.clamped_count > 0
      && result.rows[0]?.clamped_count <= 50,
  );
  await expectQuery(
    client,
    "member search excludes private profiles and the current viewer",
    `
      select
        (select count(*)::integer
         from public.search_profiles_by_handle('codex_discover_private')
         where id = $1) as private_count,
        (select count(*)::integer
         from public.search_profiles_by_handle('codex_discover_viewer')
         where id = $2) as self_count
    `,
    [fixture.private, fixture.viewer],
    (result) => result.rows[0]?.private_count === 0 && result.rows[0]?.self_count === 0,
  );
  await expectQuery(
    client,
    "social graph RPCs hide private owners and profiles",
    `
      select
        (select count(*)::integer
         from public.profile_following($1)) as private_owner_graph_count,
        (select count(*)::integer
         from public.profile_following($2)
         where id = $1) as private_following_count,
        (select count(*)::integer
         from public.profile_followers($3)
         where id = $1) as private_follower_count
    `,
    [fixture.private, fixture.fallback, fixture.followed],
    (result) => result.rows[0]?.private_owner_graph_count === 0
      && result.rows[0]?.private_following_count === 0
      && result.rows[0]?.private_follower_count === 0,
  );

  await setAuthenticatedUser(client, fixture.private);
  await expectQuery(
    client,
    "private profile owners can still read their own public following graph",
    `
      select array_agg(id order by id) as ids
      from public.profile_following($1)
    `,
    [fixture.private],
    (result) => Array.isArray(result.rows[0]?.ids)
      && result.rows[0].ids.length === 2
      && result.rows[0].ids.includes(fixture.fallback)
      && result.rows[0].ids.includes(fixture.followed),
  );

  await setAuthenticatedUser(client, fixture.viewer);
  await expectQueryFailure(
    client,
    "direct follow rejects a private profile",
    "select public.follow_user($1, 'profile')",
    [fixture.private],
    /profile_not_followable/,
  );
  await expectQueryFailure(
    client,
    "direct follow does not disclose a missing profile",
    "select public.follow_user($1, 'profile')",
    ["user_codex_discover_smoke_missing"],
    /profile_not_followable/,
  );
  await expectQuery(
    client,
    "authenticated direct follow accepts a public profile",
    "select public.follow_user($1, 'profile') as result",
    [fixture.fallback],
    (result) => result.rows.length === 1,
  );
  await expectQuery(
    client,
    "direct follow is caller-scoped and removes the target from recommendations",
    `
      select
        (select count(*)::integer
         from public.follows
         where follower_user_id = $1 and followed_user_id = $2) as follow_count,
        (select count(*)::integer
         from public.discover_profile_recommendations(50)
         where id = $2) as recommendation_count
    `,
    [fixture.viewer, fixture.fallback],
    (result) => result.rows[0]?.follow_count === 1
      && result.rows[0]?.recommendation_count === 0,
  );

  await client.query("set local role anon");
  await expectQueryFailure(
    client,
    "anonymous role cannot call Discover recommendations",
    "select * from public.discover_profile_recommendations(20)",
    [],
    /permission denied/,
  );
  await expectQueryFailure(
    client,
    "anonymous role cannot search profiles",
    "select * from public.search_profiles_by_handle('codex')",
    [],
    /permission denied/,
  );
  await expectQueryFailure(
    client,
    "anonymous role cannot enumerate profile following",
    "select * from public.profile_following($1)",
    [fixture.viewer],
    /permission denied/,
  );
  await expectQueryFailure(
    client,
    "anonymous role cannot enumerate profile followers",
    "select * from public.profile_followers($1)",
    [fixture.viewer],
    /permission denied/,
  );
  await expectQueryFailure(
    client,
    "anonymous role cannot follow profiles",
    "select public.follow_user($1, 'profile')",
    [fixture.fallback],
    /permission denied/,
  );
  await client.query("reset role");
}

async function runPlaceListSmokeChecks(client, smokeUserID, collaboratorUserID, strangerUserID) {
  const fixture = await expectQuery(
    client,
    "load smoke place fixtures",
    `
      select up.user_id, up.id as user_place_id, up.place_id
      from public.user_places up
      join public.places p on p.id = up.place_id
      where up.user_id = any($1::text[])
        and p.source_provider = 'codex_smoke'
        and p.source_provider_place_id = 'place-list-rpc-smoke'
        and up.deleted_at is null
    `,
    [[smokeUserID, collaboratorUserID]],
    (result) => result.rows.length === 2,
  );
  const userPlaceByUserID = new Map(fixture.rows.map((row) => [row.user_id, row.user_place_id]));
  const smokeUserPlaceID = userPlaceByUserID.get(smokeUserID);
  const collaboratorUserPlaceID = userPlaceByUserID.get(collaboratorUserID);
  const smokePlaceID = fixture.rows[0].place_id;

  await assertPlaceListRPCMetadata(client);
  await runFirstVisiblePlacePhotoChecks(
    client,
    smokeUserID,
    collaboratorUserID,
    strangerUserID,
    smokeUserPlaceID,
    collaboratorUserPlaceID,
    smokePlaceID,
  );
  await setAuthenticatedUser(client, smokeUserID);

  await expectQuery(
    client,
    "owner public.visible_place_lists",
    "select count(*)::integer as count from public.visible_place_lists()",
    [],
    (result) => Number.isInteger(result.rows[0]?.count),
  );

  await createSmokeList(client, "Codex smoke grant check");

  const detailListID = await createSmokeList(client, "Codex smoke detail check");
  await expectQuery(
    client,
    "owner public.place_list_detail",
    "select public.place_list_detail($1::uuid) as detail",
    [detailListID],
    (result) => result.rows[0]?.detail !== null,
  );

  const collaboratorListID = await createSmokeList(client, "Codex smoke collaborator check");
  await expectQuery(
    client,
    "owner can update list",
    "select public.upsert_place_list($1::jsonb) as list_id",
    [JSON.stringify({
      id: collaboratorListID,
      name: "Codex smoke collaborator updated",
      description: "Owner update contract",
      visibility: "followers",
    })],
    (result) => result.rows[0]?.list_id === collaboratorListID,
  );
  await expectQuery(
    client,
    "owner update persists",
    "select public.place_list_detail($1::uuid) as detail",
    [collaboratorListID],
    (result) => result.rows[0]?.detail?.list?.name === "Codex smoke collaborator updated",
  );
  await expectQuery(
    client,
    "owner public.set_place_list_collaborators",
    "select public.set_place_list_collaborators($1::uuid, $2::text[]) as result",
    [collaboratorListID, [collaboratorUserID]],
    () => true,
  );

  await setAuthenticatedUser(client, collaboratorUserID);
  await expectQuery(
    client,
    "collaborator can see shared list",
    "select exists(select 1 from public.visible_place_lists() where id = $1::uuid) as visible",
    [collaboratorListID],
    (result) => result.rows[0]?.visible === true,
  );
  await expectQuery(
    client,
    "collaborator can load list detail",
    "select public.place_list_detail($1::uuid) as detail",
    [collaboratorListID],
    (result) => result.rows[0]?.detail !== null,
  );
  const collaboratorItem = await expectQuery(
    client,
    "collaborator can add list item",
    "select public.add_place_list_item($1::uuid, $2::uuid, $3::uuid, null::uuid) as item_id",
    [collaboratorListID, smokePlaceID, collaboratorUserPlaceID],
    (result) => result.rows[0]?.item_id !== null,
  );
  await expectQueryFailure(
    client,
    "collaborator cannot manage collaborators",
    "select public.set_place_list_collaborators($1::uuid, $2::text[]) as result",
    [collaboratorListID, []],
    /place_list_not_found_or_forbidden/,
  );
  await expectQueryFailure(
    client,
    "collaborator cannot update list",
    "select public.upsert_place_list($1::jsonb) as list_id",
    [JSON.stringify({
      id: collaboratorListID,
      name: "Unauthorized collaborator update",
      description: "must fail",
      visibility: "followers",
    })],
    /place_list_not_found_or_forbidden/,
  );
  await expectQuery(
    client,
    "collaborator delete is a no-op",
    "select public.delete_place_list($1::uuid) as result",
    [collaboratorListID],
    () => true,
  );
  await expectQuery(
    client,
    "collaborator delete leaves list visible",
    "select public.place_list_detail($1::uuid) as detail",
    [collaboratorListID],
    (result) => result.rows[0]?.detail !== null,
  );
  await expectQueryFailure(
    client,
    "collaborator cannot remove list item",
    "select public.remove_place_list_item($1::uuid, $2::uuid) as result",
    [collaboratorListID, collaboratorItem.rows[0].item_id],
    /place_list_not_found_or_forbidden/,
  );

  await setAuthenticatedUser(client, strangerUserID);
  await expectQuery(
    client,
    "stranger cannot see shared list",
    "select exists(select 1 from public.visible_place_lists() where id = $1::uuid) as visible",
    [collaboratorListID],
    (result) => result.rows[0]?.visible === false,
  );
  await expectQuery(
    client,
    "stranger cannot load list detail",
    "select public.place_list_detail($1::uuid) as detail",
    [collaboratorListID],
    (result) => result.rows[0]?.detail === null,
  );
  await expectQueryFailure(
    client,
    "stranger cannot add list item",
    "select public.add_place_list_item($1::uuid, $2::uuid, $3::uuid, null::uuid) as item_id",
    [collaboratorListID, smokePlaceID, smokeUserPlaceID],
    /place_list_not_found_or_forbidden/,
  );
  await expectQueryFailure(
    client,
    "stranger cannot update list",
    "select public.upsert_place_list($1::jsonb) as list_id",
    [JSON.stringify({
      id: collaboratorListID,
      name: "Unauthorized stranger update",
      description: "must fail",
      visibility: "followers",
    })],
    /place_list_not_found_or_forbidden/,
  );
  await expectQuery(
    client,
    "stranger delete is a no-op",
    "select public.delete_place_list($1::uuid) as result",
    [collaboratorListID],
    () => true,
  );

  await setAuthenticatedUser(client, smokeUserID);
  await expectQuery(
    client,
    "unauthorized deletes leave owner list active",
    "select public.place_list_detail($1::uuid) as detail",
    [collaboratorListID],
    (result) => result.rows[0]?.detail !== null,
  );
  await expectQuery(
    client,
    "owner can remove collaborator-added item",
    "select public.remove_place_list_item($1::uuid, $2::uuid) as result",
    [collaboratorListID, collaboratorItem.rows[0].item_id],
    () => true,
  );

  const deleteListID = await createSmokeList(client, "Codex smoke delete check");
  await expectQuery(
    client,
    "owner public.delete_place_list",
    "select public.delete_place_list($1::uuid) as result",
    [deleteListID],
    () => true,
  );
  await expectQuery(
    client,
    "owner delete removes list from detail",
    "select public.place_list_detail($1::uuid) as detail",
    [deleteListID],
    (result) => result.rows[0]?.detail === null,
  );

  await client.query("set local role anon");
  await expectQueryFailure(
    client,
    "anonymous role cannot call list RPCs",
    "select count(*) from public.visible_place_lists()",
    [],
    /permission denied/,
  );
}

async function runFirstVisiblePlacePhotoChecks(
  client,
  smokeUserID,
  collaboratorUserID,
  strangerUserID,
  smokeUserPlaceID,
  collaboratorUserPlaceID,
  smokePlaceID,
) {
  await expectQuery(
    client,
    "preferred-place-photo RPC metadata",
    `
      select
        not p.prosecdef as security_invoker,
        'search_path=public, app' = any(p.proconfig) as pinned_search_path,
        has_function_privilege('authenticated', p.oid, 'execute') as authenticated_execute,
        not has_function_privilege('anon', p.oid, 'execute') as anon_denied
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = 'first_visible_place_photo'
        and pg_get_function_identity_arguments(p.oid) = 'input_place_id uuid'
    `,
    [],
    (result) => {
      const row = result.rows[0];
      return row?.security_invoker === true
        && row?.pinned_search_path === true
        && row?.authenticated_execute === true
        && row?.anon_denied === true;
    },
  );

  await expectQuery(
    client,
    "list-cover contributor photo RPC metadata",
    `
      select
        not p.prosecdef as security_invoker,
        'search_path=public, app' = any(p.proconfig) as pinned_search_path,
        has_function_privilege('authenticated', p.oid, 'execute') as authenticated_execute,
        not has_function_privilege('anon', p.oid, 'execute') as anon_denied
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = 'first_visible_place_photo_by_users'
        and pg_get_function_identity_arguments(p.oid) = 'input_place_id uuid, input_user_ids text[]'
    `,
    [],
    (result) => {
      const row = result.rows[0];
      return row?.security_invoker === true
        && row?.pinned_search_path === true
        && row?.authenticated_execute === true
        && row?.anon_denied === true;
    },
  );

  await client.query(
    `
      insert into public.follows (follower_user_id, followed_user_id, source)
      values ($1, $2, 'profile')
      on conflict (follower_user_id, followed_user_id) do nothing
    `,
    [collaboratorUserID, smokeUserID],
  );
  await client.query(
    "update public.user_places set status = 'been', visibility = 'followers' where id = $1::uuid",
    [smokeUserPlaceID],
  );
  const photoFixture = await expectQuery(
    client,
    "create rolled-back preferred place photo fixture",
    `
      with inserted_visit as (
        insert into public.place_visits (user_place_id, visited_at, note, backfilled_from_user_place)
        values ($1::uuid, now(), 'Rolled back preferred-photo smoke visit', false)
        returning id
      ), ids as (
        select inserted_visit.id as visit_id, gen_random_uuid() as photo_id
        from inserted_visit
      )
      insert into public.visit_photos (
        id, visit_id, storage_bucket, storage_path, content_type, sort_order, upload_state
      )
      select
        ids.photo_id,
        ids.visit_id,
        'visit-photos',
        $2 || '/' || ids.visit_id::text || '/' || ids.photo_id::text || '.jpg',
        'image/jpeg',
        0,
        'uploaded'
      from ids
      returning id
    `,
    [smokeUserPlaceID, smokeUserID],
    (result) => result.rows.length === 1,
  );
  const expectedPhotoID = photoFixture.rows[0].id;
  const collaboratorPhotoFixture = await expectQuery(
    client,
    "create rolled-back collaborator list-cover photo fixture",
    `
      with inserted_visit as (
        insert into public.place_visits (user_place_id, visited_at, note, backfilled_from_user_place)
        values ($1::uuid, now(), 'Rolled back collaborator cover-photo smoke visit', false)
        returning id
      ), ids as (
        select inserted_visit.id as visit_id, gen_random_uuid() as photo_id
        from inserted_visit
      )
      insert into public.visit_photos (
        id, visit_id, storage_bucket, storage_path, content_type, sort_order, upload_state
      )
      select
        ids.photo_id,
        ids.visit_id,
        'visit-photos',
        $2 || '/' || ids.visit_id::text || '/' || ids.photo_id::text || '.jpg',
        'image/jpeg',
        0,
        'uploaded'
      from ids
      returning id
    `,
    [collaboratorUserPlaceID, collaboratorUserID],
    (result) => result.rows.length === 1,
  );
  const expectedCollaboratorPhotoID = collaboratorPhotoFixture.rows[0].id;

  await client.query(
    `
      insert into public.follows (follower_user_id, followed_user_id, source)
      values ($1, $2, 'profile')
      on conflict (follower_user_id, followed_user_id) do nothing
    `,
    [smokeUserID, collaboratorUserID],
  );

  await setAuthenticatedUser(client, smokeUserID);
  await expectQuery(
    client,
    "owner can resolve first visible place photo",
    "select * from public.first_visible_place_photo($1::uuid)",
    [smokePlaceID],
    (result) => result.rows[0]?.photo_id === expectedPhotoID,
  );
  await expectQuery(
    client,
    "owner list cover selects only the requested owner photo",
    "select * from public.first_visible_place_photo_by_users($1::uuid, $2::text[])",
    [smokePlaceID, [smokeUserID]],
    (result) => result.rows[0]?.photo_id === expectedPhotoID,
  );
  await expectQuery(
    client,
    "owner list cover can select an eligible collaborator photo",
    "select * from public.first_visible_place_photo_by_users($1::uuid, $2::text[])",
    [smokePlaceID, [collaboratorUserID]],
    (result) => result.rows[0]?.photo_id === expectedCollaboratorPhotoID,
  );

  await setAuthenticatedUser(client, collaboratorUserID);
  await expectQuery(
    client,
    "follower can resolve first visible place photo",
    "select * from public.first_visible_place_photo($1::uuid)",
    [smokePlaceID],
    (result) => result.rows[0]?.photo_id === expectedPhotoID,
  );
  await expectQuery(
    client,
    "follower list cover excludes a visible photo outside the contributor set",
    "select count(*)::integer as count from public.first_visible_place_photo_by_users($1::uuid, $2::text[])",
    [smokePlaceID, [strangerUserID]],
    (result) => result.rows[0]?.count === 0,
  );

  await setAuthenticatedUser(client, strangerUserID);
  await expectQuery(
    client,
    "stranger cannot resolve hidden place photo",
    "select count(*)::integer as count from public.first_visible_place_photo($1::uuid)",
    [smokePlaceID],
    (result) => result.rows[0]?.count === 0,
  );

  await client.query("set local role anon");
  await expectQueryFailure(
    client,
    "anonymous role cannot call preferred-place-photo RPC",
    "select * from public.first_visible_place_photo($1::uuid)",
    [smokePlaceID],
    /permission denied/,
  );
  await expectQueryFailure(
    client,
    "anonymous role cannot call list-cover contributor photo RPC",
    "select * from public.first_visible_place_photo_by_users($1::uuid, $2::text[])",
    [smokePlaceID, [smokeUserID]],
    /permission denied/,
  );
}

async function assertOwnPlaceRPCMetadata(client) {
  await expectQuery(
    client,
    "own-place RPC grants match the iOS auth boundary",
    `
      select
        has_function_privilege('authenticated', 'public.save_own_place(jsonb,jsonb,jsonb)', 'execute') as authenticated_public,
        has_function_privilege('authenticated', 'app.save_own_place(jsonb,jsonb,jsonb)', 'execute') as authenticated_app,
        not has_function_privilege('anon', 'public.save_own_place(jsonb,jsonb,jsonb)', 'execute') as anon_public_denied,
        not has_function_privilege('anon', 'app.save_own_place(jsonb,jsonb,jsonb)', 'execute') as anon_app_denied
    `,
    [],
    (result) => Object.values(result.rows[0] ?? {}).every((value) => value === true),
  );

  await expectQuery(
    client,
    "app.save_own_place keeps its security-definer search path",
    `
      select p.prosecdef, 'search_path=public, app' = any(coalesce(p.proconfig, array[]::text[])) as pinned_search_path
      from pg_proc p
      where p.oid = 'app.save_own_place(jsonb,jsonb,jsonb)'::regprocedure
    `,
    [],
    (result) => result.rows[0]?.prosecdef === true && result.rows[0]?.pinned_search_path === true,
  );
}

async function setAuthenticatedUser(client, userID) {
  await client.query("set local role authenticated");
  await client.query("select set_config('request.jwt.claim.sub', $1, true)", [userID]);
  await client.query("select set_config('request.jwt.claim.role', 'authenticated', true)");
}

async function assertPlaceListRPCMetadata(client) {
  const publicSignatures = [
    "public.visible_place_lists()",
    "public.place_list_detail(uuid)",
    "public.upsert_place_list(jsonb)",
    "public.delete_place_list(uuid)",
    "public.set_place_list_collaborators(uuid,text[])",
    "public.add_place_list_item(uuid,uuid,uuid,uuid)",
    "public.remove_place_list_item(uuid,uuid)",
  ];
  await expectQuery(
    client,
    "authenticated role has every public list RPC grant",
    `
      select bool_and(has_function_privilege('authenticated', signature, 'execute')) as valid
      from unnest($1::text[]) as signature
    `,
    [publicSignatures],
    (result) => result.rows[0]?.valid === true,
  );

  const appSignatures = publicSignatures.map((signature) => signature.replace("public.", "app."));
  await expectQuery(
    client,
    "anonymous role has no app list RPC grants",
    `
      select bool_and(not has_function_privilege('anon', signature, 'execute')) as valid
      from unnest($1::text[]) as signature
    `,
    [appSignatures],
    (result) => result.rows[0]?.valid === true,
  );
  await expectQuery(
    client,
    "anonymous role has no public list RPC grants",
    `
      select bool_and(not has_function_privilege('anon', signature, 'execute')) as valid
      from unnest($1::text[]) as signature
    `,
    [publicSignatures],
    (result) => result.rows[0]?.valid === true,
  );

  const securityDefinerFunctions = [
    "is_place_list_owner",
    "is_place_list_member",
    "can_read_place_list",
    "upsert_place_list",
    "delete_place_list",
    "set_place_list_collaborators",
    "add_place_list_item",
    "remove_place_list_item",
  ];
  await expectQuery(
    client,
    "security-definer list mutations pin search_path",
    `
      select count(*)::integer as count
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'app'
        and p.proname = any($1::text[])
        and p.prosecdef
        and 'search_path=public, app' = any(p.proconfig)
    `,
    [securityDefinerFunctions],
    (result) => result.rows[0]?.count === securityDefinerFunctions.length,
  );
}

async function createSmokeList(client, name) {
  const result = await expectQuery(
    client,
    "public.upsert_place_list",
    "select public.upsert_place_list($1::jsonb) as list_id",
    [JSON.stringify({
      name,
      description: "Rolled back by scripts/supabase-smoke-test.mjs",
      visibility: "followers",
    })],
    (queryResult) => queryResult.rows[0]?.list_id !== null,
  );

  return result.rows[0].list_id;
}

async function expectQuery(client, label, sql, params, validate) {
  try {
    const result = await client.query(sql, params);
    if (!validate(result)) {
      throw new Error(`${label} returned an unexpected result.`);
    }

    console.log(`ok - ${label}`);
    return result;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`${label} failed: ${message}`);
  }
}

async function expectQueryFailure(client, label, sql, params, expectedMessage) {
  await client.query("savepoint expected_failure");
  try {
    await client.query(sql, params);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await client.query("rollback to savepoint expected_failure");
    await client.query("release savepoint expected_failure");
    if (!expectedMessage.test(message)) {
      throw new Error(`${label} failed with unexpected error: ${message}`);
    }
    console.log(`ok - ${label}`);
    return;
  }

  await client.query("release savepoint expected_failure");
  throw new Error(`${label} unexpectedly succeeded.`);
}

function sqlString(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function sanitizeError(error, dbURL) {
  const message = error instanceof Error ? error.message : String(error);
  const password = process.env.WANDER_SUPABASE_DB_PASSWORD;
  let sanitized = message.replaceAll(dbURL, "[REDACTED_DB_URL]");
  if (password) {
    sanitized = sanitized.replaceAll(password, "[REDACTED_DB_PASSWORD]");
  }

  return new Error(`Supabase smoke test failed: ${sanitized}`);
}
