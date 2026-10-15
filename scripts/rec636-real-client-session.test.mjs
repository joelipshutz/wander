import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile, chmod } from "node:fs/promises";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { runRealClientSession } from "./rec636-real-client-session.mjs";

// Fictional adapters only: no sockets, hosted operations or credentials.
const REF = "a".repeat(20), NOW = 1_900_000_000_000;
const id = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const pair = { A: "fixture_A", B: "fixture_B" };
const context = { kind: "place", id: id(1) };
const token = (user) => [Buffer.from('{"alg":"RS256"}').toString("base64url"),
  Buffer.from(JSON.stringify({ sub: user, role: "authenticated", exp: NOW / 1000 + 600 })).toString("base64url"), "fictional_signature"].join(".");
const input = () => ({ target: { projectRef: REF, url: `https://${REF}.supabase.co`, publishableKey: "sb_publishable_fictional" },
  accounts: ["A", "B"].map((label) => ({ label, accountID: pair[label], jwt: token(pair[label]) })) });
const designation = () => ({ internalAccountsApproved: true, targetRef: REF, accounts: { ...pair }, runID: id(2), context: { ...context } });
function baseline() {
  const at = "2030-01-01T00:00:00.000Z";
  const flag = (n, enabled) => ({ id: id(n), xmin: "10", enabled, valueType: "boolean", integerValue: null });
  const follow = (n) => ({ id: id(n), xmin: "11", source: "profile", createdAt: at, updatedAt: at });
  return { version: 1, runID: id(2), targetRef: REF, accounts: { ...pair }, context: { ...context }, capturedAt: at,
    profiles: Object.values(pair).map((user) => ({ id: user, xmin: "9", deleted: false })),
    globalFlag: flag(10, false), accountFlags: Object.values(pair).map((userID, i) => ({ userID, row: flag(11 + i, true) })),
    follows: [{ followerID: pair.A, followedID: pair.B, row: follow(13) }, { followerID: pair.B, followedID: pair.A, row: follow(14) }],
    blocks: [{ blockerID: pair.A, blockedID: pair.B, row: null }, { blockerID: pair.B, blockedID: pair.A, row: null }],
    contextReceipt: { ...context, xmin: "12", deleted: false, allowedA: true, allowedB: true,
      ownerID: pair.A, placeID: context.id, visibility: "mutuals", userPlaceID: id(15), sourceXmin: "12" },
    conversationCount: 0, messageCount: 0, sharedVisitCount: 0, sourceSideEffectCount: 0 };
}
async function fixture(t, overrides = {}) {
  const directory = await mkdtemp("/private/tmp/rec636-session-test-");
  t.after(() => rm(directory, { recursive: true, force: true }));
  const path = join(directory, "journal.json"), calls = [], http = [];
  const readJournal = async () => JSON.parse(await readFile(path, "utf8"));
  const options = { expectedProjectRef: REF, designation: designation(), journalPath: path, now: () => NOW,
    executeSQL: async (sql, metadata) => {
      calls.push(metadata.purpose);
      assert.equal(metadata.targetRef, REF); assert.equal(metadata.runID, id(2));
      assert.match(sql, /set local statement_timeout='30s'/u);
      if (metadata.purpose === "baseline") return [{ rec636_result: baseline() }];
      if (metadata.purpose === "verification") {
        await assert.rejects(readFile(path), { code: "ENOENT" });
        return [{ rec636_result: { version: 1, runID: id(2), targetRef: REF, operatorVerified: true,
          globalLiveOff: true, pristineBaseline: true, fixtureTransitionsVerified: true, rolledBack: true, contractChecks: 24 } }];
      }
      if (metadata.purpose === "cleanup") {
        assert.equal((await readJournal()).phase, "cleanup_planned");
        assert.doesNotMatch(sql, /delete from public\.(profiles|user_places|places)\b/iu);
        return [{ rec636_result: { runID: id(2), conversationCount: 0, messageCount: 0,
          baselineRestored: true, globalLiveEnabled: false } }];
      }
      assert.fail("Unexpected privileged operation in fictional session");
    },
    transport: async (request) => {
      http.push(request.rpc);
      assert.equal((await readJournal()).phase, "active");
      const actor = request.jwt === token(pair.A) ? pair.A : pair.B;
      if (request.rpc === "current_profile") return { status: "ok", data: [{ id: actor }] };
      if (request.rpc === "private_message_inbox") return { status: "ok", data: { items: [], nextCursor: null } };
      assert.equal(request.rpc, "private_message_start");
      return { status: "rejected", code: "private_message_unavailable" };
    }, ...overrides };
  return { options, calls, http, path, directory, readJournal };
}

test("missing, unreviewed-shaped or mismatched explicit inputs stop before SQL, HTTP or journal creation", async (t) => {
  const f = await fixture(t);
  for (const change of [
    (o) => { delete o.executeSQL; }, (o) => { o.executeSQL = { verified: true }; },
    (o) => { o.expectedProjectRef = "b".repeat(20); },
    (o) => { o.designation.accounts.B = "foreign"; },
    (o) => { o.designation.internalAccountsApproved = false; },
    (o) => { o.designation.context.id = "invalid"; },
    (o) => { o.credentialsFile = "PRIVATE must not be read"; },
  ]) {
    const options = { ...f.options, designation: designation() }; change(options);
    const result = await runRealClientSession(input(), options);
    assert.equal(result.code, "invalid_session_input"); assert.equal(result.journalCreated, false);
  }
  assert.deepEqual(f.calls, []); assert.deepEqual(f.http, []);
  await assert.rejects(readFile(f.path), { code: "ENOENT" });
});

test("existing journals and nonprivate parent directories fail before the operator, without overwriting", async (t) => {
  const f = await fixture(t); await writeFile(f.path, "PRIVATE existing journal", { mode: 0o600 });
  assert.equal((await runRealClientSession(input(), f.options)).code, "journal_path_unavailable");
  assert.equal(await readFile(f.path, "utf8"), "PRIVATE existing journal");
  await rm(f.path); await chmod(f.directory, 0o755);
  assert.equal((await runRealClientSession(input(), f.options)).code, "journal_path_unavailable");
  assert.deepEqual(f.calls, []); assert.deepEqual(f.http, []);
});

test("malformed or multiple operator result rows cannot create a journal or write permit", async (t) => {
  const f = await fixture(t);
  for (const rows of [[], [{ raw: "PRIVATE" }], [{ rec636_result: baseline(), raw: "PRIVATE" }],
    [{ rec636_result: baseline() }, { rec636_result: baseline() }]]) {
    let calls = 0;
    const result = await runRealClientSession(input(), { ...f.options, executeSQL: async () => { calls++; return rows; } });
    assert.equal(result.code, "operator_setup_failed"); assert.equal(result.journalCreated, false);
    assert.equal(calls, 1);
    assert.doesNotMatch(JSON.stringify(result), /PRIVATE|fixture_A/u);
  }
  await assert.rejects(readFile(f.path), { code: "ENOENT" }); assert.deepEqual(f.http, []);
});

test("baseline and rollback proof precede the durable journal and gateway identity verification", async (t) => {
  const f = await fixture(t);
  const result = await runRealClientSession(input(), { ...f.options, transport: async () => {
    assert.deepEqual(f.calls, ["baseline", "verification"]);
    assert.equal((await f.readJournal()).intents.length, 0);
    return { status: "ok", data: [{ id: "PRIVATE wrong identity" }] };
  } });
  assert.equal(result.code, "server_identity_mismatch"); assert.equal(result.journalPhase, "active");
  assert.equal(result.journalCreated, true); assert.equal(result.writesEnabled, false);
  assert.equal(result.step4Complete, false); assert.doesNotMatch(JSON.stringify(result), /PRIVATE/u);
});

test("operator exceptions are sanitized and cannot expose SQL, tokens or private error strings", async (t) => {
  const f = await fixture(t);
  const result = await runRealClientSession(input(), { ...f.options, executeSQL: async () => {
    throw new Error(`PRIVATE ${token(pair.A)} select secret`);
  } });
  assert.equal(result.code, "operator_setup_failed");
  assert.doesNotMatch(JSON.stringify(result), /PRIVATE|select|fictional_signature/u);
  assert.deepEqual(f.http, []); await assert.rejects(readFile(f.path), { code: "ENOENT" });
});

test("tokens that expire during operator setup are revalidated before HTTP writes", async (t) => {
  let reads = 0; const f = await fixture(t, { now: () => reads++ === 0 ? NOW : NOW + 700_000 });
  const result = await runRealClientSession(input(), f.options);
  assert.equal(result.status, "blocked"); assert.equal(result.writesEnabled, false);
  assert.equal(result.journalCreated, true); assert.equal(result.journalPhase, "active");
  assert.deepEqual(f.http, []); assert.equal((await f.readJournal()).intents.length, 0);
});

test("known denied starts drain through the existing runner and verified cleanup without provisioning fixtures", async (t) => {
  const f = await fixture(t); const result = await runRealClientSession(input(), f.options);
  assert.equal(result.status, "blocked"); assert.equal(result.code, "unexpected_rejection");
  assert.equal(result.cleanupVerified, true); assert.equal(result.journalPhase, "cleaned");
  assert.equal(result.step4Complete, false); assert.equal(result.backendDeliveryVerified, false);
  assert.deepEqual(f.calls, ["baseline", "verification", "baseline", "cleanup"]);
  assert.equal(f.http.filter((rpc) => rpc === "private_message_start").length, 2);
  assert.equal((await f.readJournal()).intents.length, 2);
  const disk = await readFile(f.path, "utf8");
  assert.doesNotMatch(disk, /fictional_signature|publishable|REC-636 synthetic/u);
});

test("ambiguous HTTP writes preserve unresolved intents and never invoke reconciliation or cleanup", async (t) => {
  const f = await fixture(t), original = f.options.transport;
  const result = await runRealClientSession(input(), { ...f.options, transport: async (request) => {
    if (request.rpc === "private_message_start") throw new Error("PRIVATE lost acknowledgment");
    return original(request);
  } });
  assert.equal(result.cleanupCode, "transport_quiescence_unverified");
  assert.equal(result.cleanupVerified, false); assert.equal(result.journalPhase, "active");
  assert.equal(result.unresolvedIntentCount, 2); assert.deepEqual(f.calls, ["baseline", "verification", "baseline"]);
  assert.equal((await f.readJournal()).intents.filter((item) => item.state === "interrupted").length, 2);
});

test("an uncertain operator cleanup stays frozen and a second invocation cannot automatically resume it", async (t) => {
  const f = await fixture(t), original = f.options.executeSQL; let cleanups = 0;
  const options = { ...f.options, executeSQL: async (sql, meta) => {
    if (meta.purpose === "cleanup") { cleanups++; throw new Error("PRIVATE unknown commit outcome"); }
    return original(sql, meta);
  } };
  const result = await runRealClientSession(input(), options);
  assert.equal(result.cleanupCode, "cleanup_requires_operator_review");
  assert.equal(result.journalPhase, "cleanup_planned"); assert.equal(cleanups, 1);
  const count = f.calls.length;
  assert.equal((await runRealClientSession(input(), options)).code, "journal_path_unavailable");
  assert.equal(f.calls.length, count); assert.equal(cleanups, 1);
});

test("direct invocation never reads session input or enables a CLI write mode", () => {
  const result = spawnSync(process.execPath, [new URL("./rec636-real-client-session.mjs", import.meta.url).pathname, "--write", "PRIVATE argument"],
    { encoding: "utf8", input: "PRIVATE stdin", timeout: 5_000, env: { PATH: "/usr/bin:/bin" } });
  assert.equal(result.status, 2); assert.equal(result.stderr, "");
  assert.equal(JSON.parse(result.stdout).code, "programmatic_invocation_required");
  assert.doesNotMatch(result.stdout, /PRIVATE|argument|stdin/u);
});
