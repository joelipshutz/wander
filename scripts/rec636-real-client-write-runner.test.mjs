import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { createMutationJournal, MutationJournalError } from "./rec636-mutation-journal.mjs";
import { createCleanupCompanion, CleanupCompanionError } from "./rec636-cleanup-companion.mjs";
import { EventEmitter } from "node:events";
import test from "node:test";
import { executeVerificationScenario, requestAuthenticatedRPC, runCLI, validateRPC, verifyRealClients, WriteVerificationError } from "./rec636-real-client-write-runner.mjs";

// Fictional adapters only. No test opens a socket, queries a hosted project,
// discovers a credential, or treats its output as production verification.
const REF = "a".repeat(20);
const NOW = 1_900_000_000_000;
const uuid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const jwt = (id) => [Buffer.from('{"alg":"RS256"}').toString("base64url"),
  Buffer.from(JSON.stringify({ sub: id, role: "authenticated", exp: NOW / 1000 + 600 })).toString("base64url"), "fictional_signature"].join(".");
const input = () => ({ target: { projectRef: REF, url: `https://${REF}.supabase.co`, publishableKey: "sb_publishable_fictional" },
  accounts: ["A", "B"].map((label) => ({ label, accountID: `fixture_${label}`, jwt: jwt(`fixture_${label}`), expiresAt: NOW + 600_000 })) });
const context = { kind: "place", id: uuid(1) };
function adapters({ failRPC, denialBypass = false, corruptDuplicate = false, leakContextPreview = false, expireAfter = false } = {}) {
  let sequence = 20;
  const state = { approved: { A: true, B: true }, follows: { A: true, B: true }, blocks: { A: false, B: false },
    contextVisible: true, conversationID: null, messages: [], read: {}, requests: [], intents: [], retries: [], concurrent: 0, maxConcurrent: 0, cancelled: false };
  const journal = {
    snapshot: () => ({ runID: uuid(2), targetRef: REF, accounts: { A: "fixture_A", B: "fixture_B" }, context,
      baseline: { contextReceipt: { ownerID: "fixture_A" } }, intents: state.intents }),
    async recordIntent(value) {
      const intent = { ...structuredClone(value), id: uuid(sequence++), state: "intent" };
      if (intent.kind === "send") intent.clientID = uuid(sequence++);
      state.intents.push(intent); return structuredClone(intent);
    },
    async recordAcknowledgment(id, ack) {
      const intent = state.intents.find((value) => value.id === id);
      if (intent.ack) assert.deepEqual(intent.ack, ack);
      intent.ack = structuredClone(ack); intent.state = "acknowledged";
      if (intent.kind === "send_retry") {
        const original = state.intents.find((value) => value.id === intent.originalIntentID);
        if (original.ack) assert.deepEqual(original.ack, ack);
        else { original.ack = structuredClone(ack); original.state = "reconciled"; }
      }
    },
    async recordRejection(id, { code }) {
      const intent = state.intents.find((value) => value.id === id);
      assert.ok(!intent.ack); intent.state = "rejected"; intent.rejectionCode = code;
    },
    async markInterrupted(id) {
      const intent = state.intents.find((value) => value.id === id);
      if (!intent.ack) intent.state = "interrupted";
    },
    async recordRetry(id) {
      const intent = state.intents.find((value) => value.id === id);
      assert.equal(intent.kind, "send"); assert.ok(!["absent", "rejected"].includes(intent.state));
      state.retries.push(id);
      const retry = { ...structuredClone(intent), id: uuid(sequence++), originalIntentID: id, kind: "send_retry", state: "intent" };
      delete retry.ack; delete retry.rejectionCode; state.intents.push(retry); return structuredClone(retry);
    },
    async reconcile(id, result) {
      const intent = state.intents.find((value) => value.id === id);
      if (result.status === "found") { intent.state = "reconciled"; intent.ack = result.ack; }
      else intent.state = "absent";
    },
  };
  const companion = {
    async transitionOwnedFixture(snapshot, intentID) {
      const intent = snapshot.intents.find((value) => value.id === intentID);
      assert.equal(intent.state, "intent");
      const change = intent.transition;
      let before; let after;
      if (change.resource === "account_flag") { before = state.approved[change.actor]; after = change.action === "restore"; state.approved[change.actor] = after; }
      if (change.resource === "follow") { before = state.follows[change.actor]; after = change.action === "restore"; state.follows[change.actor] = after; }
      if (change.resource === "block") { before = state.blocks[change.actor]; after = change.action === "insert"; state.blocks[change.actor] = after; }
      if (change.resource === "context") { assert.equal(change.actor, "A"); before = state.contextVisible; after = change.action === "restore"; state.contextVisible = after; }
      return { before: { fictionalValue: before }, after: { fictionalValue: after } };
    },
    async reconcile(snapshot) {
      return { intents: snapshot.intents.filter((intent) => intent.state === "interrupted").map((intent) => {
        const message = state.messages.find((value) => value.clientID === intent.clientID && value.senderID === snapshot.accounts[intent.actor]);
        return message ? { intentID: intent.id, status: "found", ack: { conversationID: message.conversationID,
          messageID: message.id, senderID: message.senderID, clientID: message.clientID } } : { intentID: intent.id, status: "absent" };
      }) };
    },
  };
  const eligible = () => state.approved.A && state.approved.B && state.follows.A && state.follows.B && !state.blocks.A && !state.blocks.B;
  const messageJSON = (message) => ({ ...message, recipientReadAt: state.read[message.senderID === "fixture_A" ? "B" : "A"] ? "2030-03-17T17:46:40Z" : null });
  const conversation = (label) => ({ id: state.conversationID, participant: { id: `fixture_${label === "A" ? "B" : "A"}` }, unreadCount: 0,
    lastMessagePreview: [...state.messages].reverse().find((value) => !value.context || state.contextVisible || leakContextPreview)?.body ?? null });
  const transport = async (request) => {
    const label = request.jwt === jwt("fixture_A") ? "A" : "B";
    if (expireAfter && state.requests.length > 0) request.timeoutMs = 1;
    state.requests.push({ rpc: request.rpc, params: request.params, label });
    const rpc = request.rpc;
    if (["private_message_start", "private_message_send", "private_message_mark_read"].includes(rpc)) {
      const intent = state.intents.find((value) => value.actor === label && (rpc === "private_message_send" ? ["send", "send_retry"].includes(value.kind) : value.kind === ({ private_message_start: "start", private_message_mark_read: "mark_read" }[rpc]))
        && (rpc !== "private_message_send" || value.clientID === request.params.input_client_id));
      assert.ok(intent, "Every mutation must have a durable intent before transport");
    }
    if (rpc === failRPC) return new Promise((_, reject) => request.signal.addEventListener("abort", () => { state.cancelled = true; reject(new Error("PRIVATE raw transport error")); }, { once: true }));
    state.concurrent += 1; state.maxConcurrent = Math.max(state.maxConcurrent, state.concurrent);
    await Promise.resolve(); state.concurrent -= 1;
    const denied = () => ({ status: "rejected", code: "private_message_unavailable" });
    if (rpc === "current_profile") return { status: "ok", data: [{ id: `fixture_${label}`, display_name: "PRIVATE PROFILE" }] };
    if (rpc === "private_message_inbox") return { status: "ok", data: { items: eligible() && state.messages.some((value) => !value.context || state.contextVisible) ? [conversation(label)] : [], nextCursor: null } };
    if (!eligible() && !denialBypass) return denied();
    if (rpc === "private_message_start") {
      if (!state.contextVisible && !denialBypass) return denied();
      state.conversationID ??= uuid(3);
      return { status: "ok", data: conversation(label) };
    }
    if (rpc === "private_message_conversation") return { status: "ok", data: conversation(label) };
    if (rpc === "private_message_history") return { status: "ok", data: { items: state.messages.filter((value) => !value.context || state.contextVisible).map(messageJSON), nextCursor: null } };
    if (rpc === "private_message_send") {
      const p = request.params;
      if (p.input_context_kind && !state.contextVisible && !denialBypass) return denied();
      const prior = state.messages.find((value) => value.clientID === p.input_client_id && value.senderID === `fixture_${label}`);
      if (prior && !corruptDuplicate) return { status: "ok", data: messageJSON(prior) };
      const message = { id: uuid(sequence++), conversationID: p.input_conversation_id, senderID: `fixture_${label}`,
        clientID: p.input_client_id, body: p.input_body, context: p.input_context_kind ? { kind: p.input_context_kind, id: p.input_context_id, title: "SYNTHETIC CONTEXT" } : null };
      state.messages.push(message); return { status: "ok", data: messageJSON(message) };
    }
    if (rpc === "private_message_mark_read") {
      const target = state.messages.find((value) => value.id === request.params.input_through_message_id);
      if (target.context && !state.contextVisible && !denialBypass) return denied();
      state.read[label] = true; return { status: "ok", data: {} };
    }
    assert.fail("unexpected RPC");
  };
  return { state, journal, companion, transport };
}
const scenario = (fixture, extra = {}) => executeVerificationScenario({ ...input(), context, ...fixture, now: () => NOW, ...extra });

test("strict companion brand blocks serialized approvals and adapter-shaped input before any request", async () => {
  for (const companion of [null, { verified: true, writable: true, assertReady: () => assert.fail("must not trust supplied approval") }]) {
    const result = await verifyRealClients(input(), { expectedProjectRef: REF, companion,
      transport: () => assert.fail("unverified write gate connected") });
    assert.equal(result.code, "verified_cleanup_companion_required");
    assert.equal(result.writesEnabled, false); assert.equal(result.step4Complete, false);
    assert.doesNotMatch(JSON.stringify(result), /fixture_A|fictional_signature|PRIVATE/);
  }
});

test("fictional scenario exercises both identities, delivery, stable UUID retries and all six revocations", async () => {
  const fixture = adapters();
  const result = await scenario(fixture);
  assert.equal(result.conversationCount, 1); assert.equal(result.messageCount, 6);
  assert.ok(result.requestCount <= 160); assert.equal(fixture.state.maxConcurrent, 2);
  for (const check of ["concurrent_reciprocal_start", "same_id_concurrent_send", "recipient_delivery", "reply_delivery",
    "recipient_read_receipt", "completed_response_discard_same_id_retry", "bounded_opposite_sender_concurrency",
    "account_flag_A_revoked_and_restored", "account_flag_B_revoked_and_restored", "follow_A_revoked_and_restored",
    "block_A_revoked_and_restored", "block_B_revoked_and_restored", "context_A_revoked_and_restored"]) assert.ok(result.checks.includes(check));
  assert.equal(fixture.state.messages.length, 6);
  assert.deepEqual(fixture.state.approved, { A: true, B: true }); assert.deepEqual(fixture.state.follows, { A: true, B: true });
  assert.deepEqual(fixture.state.blocks, { A: false, B: false }); assert.equal(fixture.state.contextVisible, true);
  assert.ok(fixture.state.intents.every((value) => ["acknowledged", "rejected", "reconciled"].includes(value.state)));
  assert.doesNotMatch(JSON.stringify(fixture.state.intents), /synthetic|fictional_signature|publishable|PRIVATE PROFILE|input_body/);
  assert.doesNotMatch(JSON.stringify(result), /fixture_A|synthetic|fictional_signature|SYNTHETIC CONTEXT/);
});

test("a duplicate row or mismatched same-ID acknowledgment fails rather than weakening the contract", async () => {
  const fixture = adapters({ corruptDuplicate: true });
  await assert.rejects(scenario(fixture), /same_id_retry_duplicated|deep-equal/);
  assert.equal(fixture.state.messages.length, 2);
});

test("revocation bypass is a concrete failure with the exact acknowledged transition retained for cleanup", async () => {
  const fixture = adapters({ denialBypass: true });
  await assert.rejects(scenario(fixture), { message: "revocation_not_enforced" });
  assert.equal(fixture.state.approved.A, false);
  assert.ok(fixture.state.intents.some((value) => value.kind === "operator_transition" && value.state === "acknowledged"));
});

test("timeout cancels the transport and preserves ambiguous send intent without creating a new UUID", async () => {
  const fixture = adapters({ failRPC: "private_message_send" });
  let time = NOW;
  // Deadline leaves 15 milliseconds for the send after initial reads/start.
  await assert.rejects(scenario(fixture, { deadline: NOW + 15, now: () => time }), { message: "request_timeout" });
  assert.equal(fixture.state.cancelled, true);
  const sends = fixture.state.intents.filter((value) => value.kind === "send");
  assert.equal(sends.length, 1); assert.equal(sends[0].state, "interrupted");
  assert.equal(fixture.state.messages.length, 0);
  const clientID = sends[0].clientID;
  const reconciled = await fixture.companion.reconcile(fixture.journal.snapshot());
  assert.equal(reconciled.intents[0].status, "absent");
  await fixture.journal.reconcile(sends[0].id, { status: reconciled.intents[0].status });
  assert.equal(sends[0].clientID, clientID);
});

test("a lost completed acknowledgment can be reconciled to one exact row before retrying its existing UUID", async () => {
  const fixture = adapters();
  const originalMark = fixture.journal.markInterrupted;
  let found;
  fixture.journal.markInterrupted = async (id) => {
    await originalMark(id);
    const results = await fixture.companion.reconcile(fixture.journal.snapshot());
    found = results.intents.find((value) => value.intentID === id);
    assert.equal(found.status, "found");
    await fixture.journal.reconcile(id, { status: found.status, ack: found.ack });
  };
  await scenario(fixture);
  const row = fixture.state.messages.find((value) => value.id === found.ack.messageID);
  assert.equal(fixture.state.messages.filter((value) => value.clientID === row.clientID && value.senderID === row.senderID).length, 1);
  assert.equal(fixture.state.intents.find((value) => value.clientID === row.clientID).ack.messageID, row.id);
});

test("expiry is checked before transport and no third-party, table or graph RPC is accepted", async () => {
  const fixture = adapters();
  const expired = input(); expired.accounts[0].expiresAt = NOW + 10;
  await assert.rejects(executeVerificationScenario({ ...expired, context, ...fixture, now: () => NOW }), { message: "jwt_expiring" });
  assert.equal(fixture.state.requests.length, 0);
  for (const rpc of ["follow_user", "block_user", "save_own_place", "arbitrary_sql", "private_messages"]) assert.throws(() => validateRPC(rpc, {}), { message: "rpc_not_allowed" });
  assert.throws(() => validateRPC("private_message_send", { input_conversation_id: uuid(3), input_body: "SYNTHETIC", input_client_id: uuid(4),
    input_context_kind: null, input_context_id: null, senderID: "someone_else" }), { message: "rpc_not_allowed" });
});

function fakeRequest({ status = 200, chunks = ["{}"], headers = {}, hang = false } = {}) {
  const calls = [];
  const request = (url, options, callback) => {
    const req = new EventEmitter(); req.destroy = () => { req.destroyed = true; };
    req.end = (body) => {
      calls.push({ url, options, body, req });
      queueMicrotask(() => {
        if (hang) return;
        const incoming = new EventEmitter(); incoming.destroy = () => { incoming.destroyed = true; };
        incoming.statusCode = status; incoming.headers = headers; callback(incoming);
        if (incoming.destroyed) return;
        for (const chunk of chunks) incoming.emit("data", Buffer.from(chunk));
        incoming.emit("end");
      });
    };
    return req;
  };
  return { calls, request };
}
const readInput = () => ({ target: input().target, jwt: input().accounts[0].jwt, rpc: "current_profile", params: {} });
test("production HTTPS adapter refuses direct writes with a forged permit before opening a socket", () => {
  const fake = fakeRequest();
  assert.throws(() => requestAuthenticatedRPC({ ...readInput(), rpc: "private_message_start", writePermit: { approved: true },
    params: { input_recipient_id: "fixture_B", input_context_kind: "place", input_context_id: context.id } }, { request: fake.request }), { message: "write_permit_required" });
  assert.equal(fake.calls.length, 0);
});

test("adapter bounds responses, rejects redirects and returns only allowlisted SQL rejection codes", async () => {
  for (const [config, code] of [[{ status: 307 }, "redirect_rejected"], [{ chunks: ["PRIVATE malformed"] }, "invalid_response"],
    [{ chunks: ["x".repeat(256 * 1024 + 1)] }, "response_too_large"], [{ status: 400, chunks: ['{"code":"P0001","message":"PRIVATE BODY"}'] }, "rpc_rejected"]]) {
    const fake = fakeRequest(config);
    await assert.rejects(requestAuthenticatedRPC(readInput(), { request: fake.request }), { message: code });
    assert.equal(fake.calls[0].req.destroyed, true);
  }
  const allowed = fakeRequest({ status: 400, chunks: ['{"code":"P0001","message":"private_message_unavailable","details":"PRIVATE DETAIL"}'] });
  assert.deepEqual(await requestAuthenticatedRPC(readInput(), { request: allowed.request }), { status: "rejected", code: "private_message_unavailable" });
});

test("adapter honors cancellation and uses ephemeral TLS requests without cookies", async () => {
  const fake = fakeRequest({ hang: true }); const controller = new AbortController();
  const pending = requestAuthenticatedRPC({ ...readInput(), signal: controller.signal }, { request: fake.request });
  controller.abort();
  await assert.rejects(pending, { message: "request_cancelled" });
  assert.equal(fake.calls[0].req.destroyed, true); assert.equal(fake.calls[0].options.agent, false);
  assert.equal(fake.calls[0].options.rejectUnauthorized, true); assert.equal(fake.calls[0].options.headers.Cookie, undefined);
  assert.equal(fake.calls[0].options.headers["Cache-Control"], "no-store");
});

test("CLI never reads credentials or enables writes from arguments and reports remaining phases", async () => {
  let output = "";
  assert.equal(await runCLI(["--write", "PRIVATE ARGUMENT"], { stdout: { write: (value) => { output += value; } } }), 2);
  const result = JSON.parse(output); assert.equal(result.writesEnabled, false); assert.equal(result.step4Complete, false);
  assert.doesNotMatch(output, /PRIVATE ARGUMENT/);
  let help = ""; assert.equal(await runCLI(["--help"], { stdout: { write: (value) => { help += value; } } }), 0);
  assert.match(help, /read-only/);
});

function baselineReceipt() {
  const timestamp = "2030-01-01T00:00:00.000Z";
  const flag = (id, enabled) => ({ id: uuid(id), xmin: "10", enabled, valueType: "boolean", integerValue: null });
  const follow = (id) => ({ id: uuid(id), xmin: "11", source: "profile", createdAt: timestamp, updatedAt: timestamp });
  return { version: 1, runID: uuid(2), targetRef: REF, accounts: { A: "fixture_A", B: "fixture_B" }, context,
    capturedAt: timestamp, profiles: ["fixture_A", "fixture_B"].map((id) => ({ id, xmin: "9", deleted: false })),
    globalFlag: flag(10, false), accountFlags: ["fixture_A", "fixture_B"].map((userID, index) => ({ userID, row: flag(11 + index, true) })),
    follows: [{ followerID: "fixture_A", followedID: "fixture_B", row: follow(13) }, { followerID: "fixture_B", followedID: "fixture_A", row: follow(14) }],
    blocks: [{ blockerID: "fixture_A", blockedID: "fixture_B", row: null }, { blockerID: "fixture_B", blockedID: "fixture_A", row: null }],
    contextReceipt: { ...context, xmin: "12", deleted: false, allowedA: true, allowedB: true, ownerID: "fixture_A",
      placeID: context.id, visibility: "mutuals", userPlaceID: uuid(15), sourceXmin: "12" },
    conversationCount: 0, messageCount: 0, sharedVisitCount: 0, sourceSideEffectCount: 0 };
}

async function brandedFixture(t, { mismatchGateway = false, cleanupFail = false } = {}) {
  const receipt = baselineReceipt(); const model = adapters(); let journal; let version = 40;
  const receipts = new Map([
    ["account_flag:A", receipt.accountFlags[0].row], ["account_flag:B", receipt.accountFlags[1].row],
    ["follow:A", receipt.follows[0].row], ["follow:B", receipt.follows[1].row],
    ["block:A", null], ["block:B", null], ["context:A", receipt.contextReceipt],
  ]);
  const purposes = [];
  const companion = await createCleanupCompanion({ spec: { runID: receipt.runID, targetRef: REF, accounts: receipt.accounts, context },
    executeSQL: async (sql, metadata) => {
      purposes.push(metadata.purpose);
      assert.match(sql, /begin isolation level serializable/u);
      assert.match(sql, /statement_timeout='30s'/u);
      if (metadata.purpose === "baseline") return [{ rec636_result: structuredClone(receipt) }];
      if (metadata.purpose === "verification") return [{ rec636_result: { version: 1, runID: receipt.runID, targetRef: REF,
        operatorVerified: true, globalLiveOff: true, pristineBaseline: true, fixtureTransitionsVerified: true, rolledBack: true, contractChecks: Number(sql.match(/'contractChecks',(\d+)/u)[1]) } }];
      if (metadata.purpose === "reconcile") return [{ rec636_result: await model.companion.reconcile(journal.snapshot()) }];
      if (metadata.purpose === "transition") {
        const intent = journal.snapshot().intents.at(-1); const change = intent.transition;
        await model.companion.transitionOwnedFixture(journal.snapshot(), intent.id);
        const key = `${change.resource}:${change.actor}`; const before = structuredClone(receipts.get(key));
        let after;
        if (change.resource === "account_flag") after = { ...before, xmin: String(version++), enabled: change.action === "restore" };
        if (change.resource === "follow") after = change.action === "remove" ? null : { ...receipt.follows[change.actor === "A" ? 0 : 1].row, xmin: String(version++) };
        if (change.resource === "block") after = change.action === "remove" ? null : { id: intent.id, xmin: String(version++), createdAt: receipt.capturedAt };
        if (change.resource === "context") after = { ...before, xmin: String(version++), sourceXmin: String(version++), allowedA: change.action === "restore", allowedB: change.action === "restore" };
        receipts.set(key, after); return [{ rec636_result: { before, after } }];
      }
      if (metadata.purpose === "cleanup") {
        assert.equal(journal.snapshot().phase, "cleanup_planned");
        if (cleanupFail) throw new Error("PRIVATE cleanup details");
        model.state.messages.length = 0; model.state.conversationID = null;
        return [{ rec636_result: { runID: receipt.runID, conversationCount: 0, messageCount: 0, baselineRestored: true, globalLiveEnabled: false } }];
      }
      assert.fail("unexpected privileged purpose");
    } });
  const directory = await mkdtemp("/private/tmp/rec636-runner-test-");
  t.after(() => rm(directory, { recursive: true, force: true }));
  const path = join(directory, "journal.json");
  journal = await createMutationJournal({ path, targetRef: REF, accounts: receipt.accounts, context, baseline: companion.baseline() });
  const transport = async (request) => {
    model.state.intents = journal.snapshot().intents;
    if (mismatchGateway && request.rpc === "current_profile") return { status: "ok", data: [{ id: "foreign_fixture" }] };
    return model.transport(request);
  };
  const designation = { internalAccountsApproved: true, targetRef: REF, accounts: receipt.accounts, runID: receipt.runID, context };
  return { model, companion, journal, path, designation, transport, purposes };
}

test("full entry point with fictional SQL gateway persists intent/retry/cleanup and reports unresolved native phases", async (t) => {
  const fixture = await brandedFixture(t);
  const result = await verifyRealClients(input(), { expectedProjectRef: REF, now: () => NOW, ...fixture });
  assert.equal(result.status, "pass", JSON.stringify(result)); assert.equal(result.cleanupVerified, true); assert.equal(result.step4Complete, false);
  assert.ok(result.limitations.includes("controlled_database_lock_wait_and_quota_concurrency_unverified"));
  assert.equal(result.unresolvedIntentCount, 0); assert.equal(fixture.journal.snapshot().phase, "cleaned");
  const disk = await readFile(fixture.path, "utf8");
  assert.doesNotMatch(disk, /synthetic|input_body|fictional_signature|publishable/);
  assert.ok(fixture.purposes.includes("reconcile")); assert.equal(fixture.model.state.messages.length, 0);
});

test("mismatched actual gateway identity blocks before write capability or privileged transitions", async (t) => {
  const fixture = await brandedFixture(t, { mismatchGateway: true });
  const result = await verifyRealClients(input(), { expectedProjectRef: REF, now: () => NOW, ...fixture });
  assert.equal(result.code, "server_identity_mismatch"); assert.equal(result.writesEnabled, false);
  assert.equal(fixture.journal.snapshot().intents.length, 0); assert.ok(!fixture.purposes.includes("transition"));
});

test("failed cleanup preserves the frozen journal and reports operator review without false completion", async (t) => {
  const fixture = await brandedFixture(t, { cleanupFail: true });
  const result = await verifyRealClients(input(), { expectedProjectRef: REF, now: () => NOW, ...fixture });
  assert.equal(result.status, "blocked"); assert.equal(result.cleanupVerified, false); assert.equal(result.step4Complete, false);
  assert.equal(result.cleanupCode, "cleanup_requires_operator_review");
  assert.equal(fixture.journal.snapshot().phase, "cleanup_planned", JSON.stringify(result));
  assert.doesNotMatch(JSON.stringify(result), /PRIVATE|fixture_A|fictional_signature|synthetic/);
});

test("a cloned journal handle or changed designation cannot enable write capability", async (t) => {
  const fixture = await brandedFixture(t);
  const forged = { snapshot: fixture.journal.snapshot, recordIntent: fixture.journal.recordIntent };
  const rejected = await verifyRealClients(input(), { expectedProjectRef: REF, now: () => NOW, ...fixture,
    journal: forged, transport: () => assert.fail("forged journal connected") });
  assert.equal(rejected.code, "mutation_journal_required"); assert.equal(rejected.writesEnabled, false);
  const changed = await verifyRealClients(input(), { expectedProjectRef: REF, now: () => NOW, ...fixture,
    designation: { ...fixture.designation, accounts: { A: "foreign_fixture", B: "fixture_B" } },
    transport: () => assert.fail("wrong designated account connected") });
  assert.equal(changed.code, "designated_accounts_required"); assert.equal(changed.writesEnabled, false);
});

test("ambiguous dispatched mutation keeps the durable journal active and never assumes HTTP/database quiescence", async (t) => {
  const fixture = await brandedFixture(t);
  const transport = async (request) => {
    if (request.rpc === "private_message_start") throw new Error("PRIVATE lost transport details");
    return fixture.transport(request);
  };
  const result = await verifyRealClients(input(), { expectedProjectRef: REF, now: () => NOW, ...fixture, transport });
  assert.equal(result.status, "blocked"); assert.equal(result.cleanupCode, "transport_quiescence_unverified");
  assert.equal(result.cleanupVerified, false); assert.equal(result.step4Complete, false);
  assert.equal(fixture.journal.snapshot().phase, "active"); assert.ok(result.unresolvedIntentCount > 0);
  assert.ok(!fixture.purposes.includes("cleanup")); assert.ok(!fixture.purposes.includes("reconcile"));
  assert.doesNotMatch(JSON.stringify(result), /PRIVATE|fixture_A|fictional_signature/);
});

function deferred() {
  let resolve;
  const promise = new Promise((accept) => { resolve = accept; });
  return { promise, resolve };
}

test("a fast known start rejection drains its late sibling acknowledgment before frozen cleanup", async (t) => {
  const fixture = await brandedFixture(t); const ready = deferred(); const release = deferred();
  let siblingCompleted = false;
  const transport = async (request) => {
    if (request.rpc === "private_message_start" && request.jwt === jwt("fixture_A")) {
      return { status: "rejected", code: "private_message_unavailable" };
    }
    if (request.rpc === "private_message_start") { ready.resolve(); await release.promise; siblingCompleted = true; }
    return fixture.transport(request);
  };
  const running = verifyRealClients(input(), { expectedProjectRef: REF, now: () => NOW, ...fixture, transport });
  await ready.promise;
  assert.equal(siblingCompleted, false); assert.equal(fixture.journal.snapshot().phase, "active");
  assert.ok(!fixture.purposes.includes("cleanup")); assert.ok(!fixture.purposes.includes("reconcile"));
  release.resolve(); const result = await running;
  assert.equal(siblingCompleted, true); assert.equal(result.code, "unexpected_rejection");
  assert.equal(result.cleanupVerified, true); assert.equal(fixture.journal.snapshot().phase, "cleaned");
  assert.equal(fixture.journal.snapshot().intents.filter((intent) => intent.kind === "start" && intent.ack).length, 1);
});

test("an ambiguous fast start failure still drains a late successful sibling and preserves the operator gate", async (t) => {
  const fixture = await brandedFixture(t); const ready = deferred(); const release = deferred();
  const transport = async (request) => {
    if (request.rpc === "private_message_start" && request.jwt === jwt("fixture_A")) throw new Error("PRIVATE lost acknowledgment");
    if (request.rpc === "private_message_start") { ready.resolve(); await release.promise; }
    return fixture.transport(request);
  };
  const running = verifyRealClients(input(), { expectedProjectRef: REF, now: () => NOW, ...fixture, transport });
  await ready.promise; assert.ok(!fixture.purposes.includes("cleanup")); release.resolve();
  const result = await running;
  assert.equal(result.cleanupCode, "transport_quiescence_unverified"); assert.equal(result.cleanupVerified, false);
  assert.equal(fixture.journal.snapshot().phase, "active");
  assert.equal(fixture.journal.snapshot().intents.filter((intent) => intent.kind === "start" && intent.ack).length, 1);
  assert.equal(fixture.journal.snapshot().intents.filter((intent) => intent.kind === "start" && intent.state === "interrupted").length, 1);
  assert.ok(!fixture.purposes.includes("cleanup")); assert.ok(!fixture.purposes.includes("reconcile"));
});

test("concurrent same-ID sends drain a late retry acknowledgment after an ambiguous original failure", async (t) => {
  const fixture = await brandedFixture(t); const ready = deferred(); const release = deferred(); let sends = 0;
  const transport = async (request) => {
    if (request.rpc === "private_message_send") {
      sends += 1;
      if (sends === 1) throw new Error("PRIVATE send transport");
      ready.resolve(); await release.promise;
    }
    return fixture.transport(request);
  };
  const running = verifyRealClients(input(), { expectedProjectRef: REF, now: () => NOW, ...fixture, transport });
  await ready.promise; assert.ok(!fixture.purposes.includes("cleanup")); release.resolve();
  const result = await running;
  assert.equal(result.cleanupCode, "transport_quiescence_unverified"); assert.equal(fixture.journal.snapshot().phase, "active");
  const original = fixture.journal.snapshot().intents.find((intent) => intent.kind === "send");
  const retry = fixture.journal.snapshot().intents.find((intent) => intent.kind === "send_retry");
  assert.equal(original.ack.messageID, retry.ack.messageID); assert.equal(original.clientID, retry.clientID);
  assert.equal(fixture.model.state.messages.length, 1); assert.ok(!fixture.purposes.includes("cleanup"));
});

test("a hidden contextual message cannot remain the latest inbox preview while history is correctly filtered", async () => {
  const fixture = adapters({ leakContextPreview: true });
  await assert.rejects(scenario(fixture), { message: "revoked_context_preview_exposed" });
  assert.equal(fixture.state.contextVisible, false);
  const history = await fixture.transport({ target: input().target, jwt: jwt("fixture_A"), rpc: "private_message_history",
    params: { input_conversation_id: uuid(3), input_limit: 50 } });
  assert.ok(history.data.items.every((item) => item.context === null));
});

test("failed interruption annotation preserves dispatch uncertainty through a late backend completion", async (t) => {
  const fixture = await brandedFixture(t);
  const readyB = deferred(); const lockReady = deferred(); const releaseB = deferred();
  const allowLateA = deferred(); const lateAComplete = deferred();
  const transport = async (request) => {
    if (request.rpc === "private_message_start" && request.jwt === jwt("fixture_A")) {
      await readyB.promise;
      // Both durable start intents now exist and both transports dispatched.
      // The lock prevents markInterrupted and the sibling ACK from persisting.
      await writeFile(`${fixture.path}.lock`, "fictional exclusive lock", { flag: "wx", mode: 0o600 });
      lockReady.resolve();
      void allowLateA.promise.then(() => {
        fixture.model.state.conversationID = uuid(3);
        lateAComplete.resolve();
      });
      throw new WriteVerificationError("transport_failed");
    }
    if (request.rpc === "private_message_start") { readyB.resolve(); await releaseB.promise; }
    return fixture.transport(request);
  };
  const running = verifyRealClients(input(), { expectedProjectRef: REF, now: () => NOW, ...fixture, transport });
  await lockReady.promise;
  assert.ok(!fixture.purposes.includes("reconcile")); assert.ok(!fixture.purposes.includes("cleanup"));
  releaseB.resolve(); const result = await running;
  assert.equal(result.code, "transport_failed"); assert.equal(result.cleanupCode, "transport_quiescence_unverified");
  assert.equal(result.journalAnnotationFailed, true); assert.equal(result.cleanupVerified, false);
  assert.equal(fixture.journal.snapshot().phase, "active"); assert.ok(result.unresolvedIntentCount > 0);
  assert.ok(!fixture.purposes.includes("reconcile")); assert.ok(!fixture.purposes.includes("cleanup"));
  allowLateA.resolve(); await lateAComplete.promise;
  assert.equal(fixture.model.state.conversationID, uuid(3));
  assert.equal(fixture.journal.snapshot().phase, "active");
  assert.doesNotMatch(JSON.stringify(result), /fictional exclusive lock|fixture_A|fictional_signature/);
});

test("known error classes cannot echo arbitrary code-shaped private strings", async (t) => {
  const fixture = await brandedFixture(t);
  for (const [error, expected] of [[new WriteVerificationError("private_marker_disclosure"), "verification_failed"],
    [new MutationJournalError("private_marker_disclosure"), "journal_failed"],
    [new CleanupCompanionError("private_marker_disclosure"), "operator_failed"]]) {
    const result = await verifyRealClients(input(), { expectedProjectRef: REF, now: () => NOW, ...fixture,
      transport: () => { throw error; } });
    assert.equal(result.code, expected); assert.equal(result.writesEnabled, false);
    assert.doesNotMatch(JSON.stringify(result), /private_marker_disclosure/);
  }
});
