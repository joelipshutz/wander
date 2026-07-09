#!/usr/bin/env node

import { createRequire } from "node:module";
import { spawnSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";

const DEFAULT_ENV_FILE = `${homedir()}/.openclaw/workspace/.env.keys`;
const DEFAULT_SMOKE_USER_ID = "user_codex_supabase_smoke";
const DEFAULT_SMOKE_COLLABORATOR_ID = "user_codex_supabase_smoke_collab";
const PG_CACHE_DIR = join(tmpdir(), "recme-supabase-smoke-pg");

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

  const smokeUserID = options.userID ?? process.env.WANDER_SUPABASE_SMOKE_USER_ID ?? DEFAULT_SMOKE_USER_ID;
  const collaboratorUserID = options.collaboratorUserID ??
    process.env.WANDER_SUPABASE_SMOKE_COLLABORATOR_ID ??
    DEFAULT_SMOKE_COLLABORATOR_ID;
  const dbURL = options.dbURL ?? process.env.WANDER_SUPABASE_DB_URL ?? buildDirectDatabaseURL();
  const { Client } = await loadPg();

  const client = new Client({
    connectionString: dbURL,
    ssl: { rejectUnauthorized: false },
  });

  try {
    await client.connect();
    await client.query(buildSmokeFixtureSQL(smokeUserID, collaboratorUserID));
    await runPlaceListSmokeChecks(client, smokeUserID, collaboratorUserID);
    console.log("Supabase smoke test passed: authenticated place-list RPCs are callable.");
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
      case "--user-id":
        parsed.userID = requiredValue(args, index, arg);
        index += 1;
        break;
      case "--collaborator-user-id":
        parsed.collaboratorUserID = requiredValue(args, index, arg);
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
  --user-id <clerk-like-id>        Authenticated smoke profile id.
  --collaborator-user-id <id>      Collaborator smoke profile id.

Required env when --db-url is omitted:
  WANDER_SUPABASE_PROJECT_REF
  WANDER_SUPABASE_DB_PASSWORD

Optional env:
  WANDER_SUPABASE_SMOKE_USER_ID
  WANDER_SUPABASE_SMOKE_COLLABORATOR_ID
  npm_config_cache

Notes:
  The script installs pg into ${PG_CACHE_DIR} if it is not already cached.
  It seeds two smoke profiles plus one smoke place/user_place, then rolls back list mutations.
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

    if (!process.env[key]) {
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

async function loadPg() {
  const requireFromCache = createRequire(join(PG_CACHE_DIR, "index.cjs"));
  const pgPackagePath = join(PG_CACHE_DIR, "node_modules", "pg", "package.json");

  if (!existsSync(pgPackagePath)) {
    mkdirSync(PG_CACHE_DIR, { recursive: true });
    writeFileSync(join(PG_CACHE_DIR, "package.json"), JSON.stringify({
      private: true,
      dependencies: { pg: "^8.13.1" },
    }, null, 2));

    console.log(`Installing pg smoke-test dependency into ${PG_CACHE_DIR}...`);
    const install = spawnSync("npm", ["install", "--silent", "--no-audit", "--no-fund"], {
      cwd: PG_CACHE_DIR,
      encoding: "utf8",
      maxBuffer: 1024 * 1024 * 10,
    });

    if (install.status !== 0) {
      if (install.stdout) process.stdout.write(install.stdout);
      if (install.stderr) process.stderr.write(install.stderr);
      throw new Error(`Failed to install pg smoke-test dependency with exit code ${install.status ?? "unknown"}.`);
    }
  }

  return requireFromCache("pg");
}

function buildSmokeFixtureSQL(smokeUserID, collaboratorUserID) {
  const smokeUser = sqlString(smokeUserID);
  const collaboratorUser = sqlString(collaboratorUserID);
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
  (${collaboratorUser}, 'codex_smoke_collab', 'Codex Smoke Collaborator', 'Backend smoke-test collaborator.', 'Test', 'followers', null)
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
  ${smokeUser},
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

async function runPlaceListSmokeChecks(client, smokeUserID, collaboratorUserID) {
  const fixture = await expectQuery(
    client,
    "load smoke place fixture",
    `
      select up.id as user_place_id, up.place_id
      from public.user_places up
      join public.places p on p.id = up.place_id
      where up.user_id = $1
        and p.source_provider = 'codex_smoke'
        and p.source_provider_place_id = 'place-list-rpc-smoke'
        and up.deleted_at is null
      limit 1
    `,
    [smokeUserID],
    (result) => result.rows.length === 1,
  );
  const smokeUserPlaceID = fixture.rows[0].user_place_id;
  const smokePlaceID = fixture.rows[0].place_id;

  await client.query("begin");
  try {
    await client.query("set local role authenticated");
    await client.query("select set_config('request.jwt.claim.sub', $1, true)", [smokeUserID]);
    await client.query("select set_config('request.jwt.claim.role', 'authenticated', true)");

    await expectQuery(
      client,
      "public.visible_place_lists",
      "select count(*)::integer as count from public.visible_place_lists()",
      [],
      (result) => Number.isInteger(result.rows[0]?.count),
    );

    await createSmokeList(client, "Codex smoke grant check");

    const detailListID = await createSmokeList(client, "Codex smoke detail check");
    await expectQuery(
      client,
      "public.place_list_detail",
      "select public.place_list_detail($1::uuid) as detail",
      [detailListID],
      (result) => result.rows[0]?.detail !== null,
    );

    const collaboratorListID = await createSmokeList(client, "Codex smoke collaborator check");
    await expectQuery(
      client,
      "public.set_place_list_collaborators",
      "select public.set_place_list_collaborators($1::uuid, $2::text[]) as result",
      [collaboratorListID, [collaboratorUserID]],
      () => true,
    );

    const addItemListID = await createSmokeList(client, "Codex smoke add item check");
    const addItem = await expectQuery(
      client,
      "public.add_place_list_item",
      "select public.add_place_list_item($1::uuid, $2::uuid, $3::uuid, null::uuid) as item_id",
      [addItemListID, smokePlaceID, smokeUserPlaceID],
      (result) => result.rows[0]?.item_id !== null,
    );

    await expectQuery(
      client,
      "public.remove_place_list_item",
      "select public.remove_place_list_item($1::uuid, $2::uuid) as result",
      [addItemListID, addItem.rows[0].item_id],
      () => true,
    );

    const deleteListID = await createSmokeList(client, "Codex smoke delete check");
    await expectQuery(
      client,
      "public.delete_place_list",
      "select public.delete_place_list($1::uuid) as result",
      [deleteListID],
      () => true,
    );
  } finally {
    await client.query("rollback");
  }
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
