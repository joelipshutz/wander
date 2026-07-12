#!/usr/bin/env node

import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import pg from "pg";

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
  const dbURL = options.dbURL ?? process.env.WANDER_SUPABASE_DB_URL ?? buildDirectDatabaseURL();
  assertSafeDatabaseURL(dbURL);
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
      await runPlaceListSmokeChecks(client, smokeUserID, collaboratorUserID, strangerUserID);
      console.log("Supabase smoke test passed: place-list RPC grants and owner/collaborator boundaries are valid.");
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

Options:
  --env-file <path>               Env file to load. Defaults to ~/.openclaw/workspace/.env.keys.
  --db-url <postgres-url>          Hosted Postgres URL. Defaults to WANDER_SUPABASE_DB_URL or project ref/password env.

Required env when --db-url is omitted:
  WANDER_SUPABASE_PROJECT_REF
  WANDER_SUPABASE_DB_PASSWORD

Notes:
  Run npm --prefix scripts ci --ignore-scripts once to install the pinned pg dependency.
  Every fixture and behavior mutation runs in one transaction and is rolled back.
`);
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
  deleted_at
)
values
  (${smokeUser}, 'codex_smoke', 'Codex Smoke Test', 'Backend smoke-test profile.', 'Test', 'followers', null),
  (${collaboratorUser}, 'codex_smoke_collab', 'Codex Smoke Collaborator', 'Backend smoke-test collaborator.', 'Test', 'followers', null),
  (${strangerUser}, 'codex_smoke_stranger', 'Codex Smoke Stranger', 'Backend smoke-test stranger.', 'Test', 'followers', null)
on conflict (id) do update
set
  handle = excluded.handle,
  display_name = excluded.display_name,
  bio = excluded.bio,
  home_area = excluded.home_area,
  default_visibility = excluded.default_visibility,
  deleted_at = null,
  updated_at = now();

insert into public.places (
  canonical_name,
  category,
  primary_category,
  subcategory,
  raw_provider_type,
  category_source,
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
