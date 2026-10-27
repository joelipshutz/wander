import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { createHash } from "node:crypto";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const metadata = read("supabase/tests/rec636_dormant_metadata.sql");
const baseline = read("supabase/tests/rec636_preinstall_baseline.sql");
const migrations = [
  "supabase/migrations/20261014020218_private_contextual_messages.sql",
  "supabase/migrations/20261014020238_live_activity_feed.sql",
];
const unquote = (source) => [...source.matchAll(/'([^']*)'/g)].map((match) => match[1]);
const withoutComments = (source) => source.replace(/--[^\n]*/g, "");
const contractRows = [...metadata.matchAll(
  /^\s*\('((?:app|public)\.[^']+)', '([^']+)', (true|false), '([svi])', '([^']+)', (true|false), (\d+), array\[([^\]]*)\], '([^']+)', '([^']+)'\)/gm,
)];
const expectedFunctions = contractRows.map((match) => ({
  signature: match[1], returnType: match[2], definer: match[3] === "true",
  volatility: match[4], path: match[5], authenticated: match[6] === "true",
  defaults: Number(match[7]), argumentNames: unquote(match[8]), language: match[9],
}));

function declaredFunctions(source) {
  return [...source.matchAll(/create function ((?:app|public)\.\w+)\(([\s\S]*?)\)\s*returns (\w+)([\s\S]*?)\bas \$\$/g)].map((match) => {
    const args = match[2].split(",").map((arg) => arg.trim());
    const parsed = args.map((arg) => arg.match(/^(\w+)\s+(.*?)(?:\s+default\s+(.+))?$/i));
    assert.ok(parsed.every(Boolean), `Unparsed declaration in ${match[1]}`);
    const declaration = match[4];
    return {
      signature: `${match[1]}(${parsed.map((arg) => arg[2]).join(",")})`,
      returnType: match[3], definer: /security definer/.test(declaration),
      volatility: /immutable/.test(declaration) ? "i" : /volatile/.test(declaration) ? "v" : "s",
      path: declaration.match(/set search_path = ([^\n]*)/)[1].trim(),
      authenticated: match[1].startsWith("public."),
      defaults: parsed.filter((arg) => arg[3] !== undefined).length,
      argumentNames: parsed.map((arg) => arg[1]),
      language: declaration.match(/language (sql|plpgsql)/)[1],
    };
  });
}

test("reviewed definition fingerprints are complete and tied to the current migration source", () => {
  const hashes = contractRows.map((row) => row[10]);
  assert.equal(hashes.length, 14);
  assert.equal(new Set(hashes).size, 14);
  for (const hash of hashes) assert.match(hash, /^[0-9a-f]{32}$/);
  const anchors = [...metadata.matchAll(/^-- Reviewed migration SHA256 (\S+): ([0-9a-f]{64})$/gm)];
  assert.deepEqual(anchors.map((row) => row[1]), migrations);
  for (const [, path, expected] of anchors) {
    assert.equal(createHash("sha256").update(read(path)).digest("hex"), expected,
      `Migration changed after the reviewed definition fingerprints: ${path}`);
  }
  assert.match(metadata, /md5\(pg_get_functiondef\(fn\)\) is distinct from expected\.definition_md5/);
});

function exportSQL(testPath, previews = []) {
  const args = [new URL("./supabase-smoke-test.mjs", import.meta.url).pathname, "--print-sql"];
  for (const preview of previews) args.push("--migration-preview", new URL(`../${preview}`, import.meta.url).pathname);
  args.push("--migration-test", new URL(`../${testPath}`, import.meta.url).pathname);
  const result = spawnSync(process.execPath, args, {
    encoding: "utf8", timeout: 10_000,
    env: { ...process.env, WANDER_SUPABASE_ENV_FILE: "/rec636-nonexistent-env-must-not-be-read" },
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, "");
  return result.stdout;
}

test("all 14 verifier identities and ABI expectations match the reviewed declarations", () => {
  assert.equal(expectedFunctions.length, 14);
  assert.equal(new Set(expectedFunctions.map((fn) => fn.signature)).size, 14);
  const actual = migrations.flatMap((path) => declaredFunctions(read(path)));
  assert.deepEqual(expectedFunctions, actual);
  assert.match(metadata, /to_regprocedure\(expected\.signature\)/);
  assert.match(metadata, /not \(p\.oid=any\(expected_oids\)\)/);
});

test("nine flag keys agree with the app registry and migration", () => {
  const keys = unquote(metadata.match(/flag_keys text\[\] := array\[([\s\S]*?)\];/)[1]).sort();
  const swiftEnum = read("Wander/App/FeatureFlags.swift").match(/enum FeatureFlagKey:[\s\S]*?\n    var definition:/)[0];
  const swiftKeys = [...swiftEnum.matchAll(/case \w+ = "([^"]+)"/g)].map((match) => match[1]).sort();
  const migrationKeys = unquote(read(migrations[0]).match(/add constraint feature_flags_registered_key_check check \(key in \(([\s\S]*?)\)\)/)[1]).sort();
  assert.equal(keys.length, 9);
  assert.deepEqual(keys, swiftKeys);
  assert.deepEqual(keys, migrationKeys);
});

test("type/range matrix includes null, both integer bounds and valid/invalid endpoints", () => {
  const values = metadata.match(/foreach flag_integer in array array\[([\s\S]*?)\]/)[1]
    .split(",").map((value) => value.trim() === "null::integer" ? null : Number(value.trim()));
  assert.equal(values.length, 22);
  assert.equal(new Set(values).size, 22);
  for (const boundary of [null, -2147483648, -1, 0, 1, 5, 6, 999999, 1000000, 1000001, 2147483647]) {
    assert.ok(values.includes(boundary), `Missing flag boundary ${boundary}`);
  }
  assert.equal(10 * 3 * values.length, 660);
  assert.match(metadata, /actual_contract is distinct from expected_contract/);
  assert.match(metadata, /actual_registered is distinct from expected_registered/);
  assert.match(metadata, /safe_expression ~\*.*key\|value_type\|integer_value/);
  assert.match(metadata, /safe_expression <> ''/);
});

test("catalog checks retain complete client grant, RLS and dormant global flag requirements", () => {
  assert.match(metadata, /has_function_privilege\('anon', fn, 'execute'\)/);
  assert.match(metadata, /grantee=0 and privilege_type='EXECUTE'/);
  assert.match(metadata, /array\['public','anon','authenticated'\]/);
  assert.match(metadata, /select,insert,update,delete,truncate,references,trigger/);
  assert.match(metadata, /has_any_column_privilege/);
  assert.match(metadata, /relkind='r' and relrowsecurity/);
  assert.match(metadata, /exists\(select 1 from pg_policy where polrelid=private_table\)/);
  assert.match(metadata, /and user_id is null and not enabled and value_type='boolean' and integer_value is null/);
});

test("baseline covers precisely the 64 reserved identities from the two behavior suites", () => {
  const expected = new Set([
    ...unquote(read("supabase/tests/private_contextual_messages.sql")),
    ...unquote(read("supabase/tests/live_activity_feed.sql")),
  ].filter((value) => value.startsWith("user_codex_") && value !== "user_codex_pm_quota_peer_"));
  const actual = new Set(unquote(baseline).filter((value) => value.startsWith("user_codex_") && value !== "user_codex_pm_quota_peer_"));
  assert.deepEqual(actual, expected);
  assert.equal(actual.size, 13);
  assert.match(baseline, /generate_series\(1,51\)/);
  assert.equal(actual.size + 51, 64);
  assert.match(baseline, /id in\(select id from reserved_profiles\)/);
});

test("both standalone exports remain bounded rollback-only catalog reads without loading credentials", () => {
  for (const [path, source] of [
    ["supabase/tests/rec636_dormant_metadata.sql", metadata],
    ["supabase/tests/rec636_preinstall_baseline.sql", baseline],
  ]) {
    const sql = withoutComments(exportSQL(path));
    assert.match(sql, /^begin;\s/);
    assert.match(sql, /rollback;\s*$/);
    assert.equal([...sql.matchAll(/^begin;/gm)].length, 1);
    assert.equal([...sql.matchAll(/^rollback;/gm)].length, 1);
    assert.doesNotMatch(sql, /^\s*(?:create|alter|drop|insert|update|delete|truncate|grant|revoke|commit|perform|call|set\s+(?:local\s+)?role)\b/im);
    assert.match(source, /lock_timeout = '5s'/);
    assert.match(source, /statement_timeout = '60s'/);
    if (path.includes("dormant")) {
      assert.equal([...sql.matchAll(/execute format\('select /g)].length, 2);
    } else assert.doesNotMatch(sql, /\bexecute\b/i);
  }
});

test("offline migration preview embeds both reviewed contracts and strict metadata assertions", () => {
  const sql = withoutComments(exportSQL("supabase/tests/rec636_dormant_metadata.sql", migrations));
  assert.match(sql, /create table public\.private_conversations/);
  assert.match(sql, /create function public\.live_activity_feed/);
  assert.match(sql, /REC-636 global Live must remain Boolean Off/);
  assert.equal([...sql.matchAll(/^begin;/gm)].length, 1);
  assert.equal([...sql.matchAll(/^commit;/gm)].length, 0);
  assert.equal([...sql.matchAll(/^rollback;/gm)].length, 1);
});
