import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { Readable } from "node:stream";
import test from "node:test";
import { requestJSON, runCLI, validateInput, verify } from "./rec636-real-client-verification.mjs";

// Fictional offline inputs only. No test opens a socket or discovers credentials.
const REF = "a".repeat(20);
const NOW = 1_900_000_000_000;
const jwt = (id, extra = {}) => [
  Buffer.from(JSON.stringify({ alg: "RS256" })).toString("base64url"),
  Buffer.from(JSON.stringify({ sub: id, exp: NOW / 1000 + 600, ...extra })).toString("base64url"),
  "fictional_signature",
].join(".");
const fixture = () => ({
  target: { projectRef: REF, url: `https://${REF}.supabase.co`, publishableKey: "sb_publishable_fictional" },
  accounts: ["A", "B"].map((label) => ({ label, accountID: `fixture_${label}`, jwt: jwt(`fixture_${label}`) })),
});
const options = (transport, mode = "preflight") => ({ expectedProjectRef: REF, mode, transport, now: () => NOW });
const authorizedResponse = (input) => input.rpc === "current_profile"
  ? [{ id: input.jwt === jwt("fixture_A") ? "fixture_A" : "fixture_B", display_name: "PRIVATE PROFILE" }]
  : { items: [], nextCursor: null };

test("default dry-run validates explicit inputs without any transport call", async () => {
  const result = await verify(fixture(), { expectedProjectRef: REF, now: () => NOW,
    transport: () => assert.fail("dry-run must not connect") });
  assert.equal(result.status, "pass");
  assert.equal(result.mode, "dry-run");
  assert.equal(result.plannedReadRequests, 4);
  assert.equal(result.writesEnabled, false);
  assert.equal(result.step4Complete, false);
});

test("preflight authenticates both identities before private reads and uses only read RPCs", async () => {
  const calls = [];
  const result = await verify(fixture(), options(async (input) => { calls.push(input); return authorizedResponse(input); }));
  assert.equal(result.status, "pass");
  assert.deepEqual(calls.map(({ rpc, params }) => [rpc, params]), [
    ["current_profile", {}], ["current_profile", {}],
    ["private_message_inbox", { input_limit: 1 }], ["private_message_inbox", { input_limit: 1 }],
  ]);
  assert.equal(result.conversationAbsenceVerified, false);
  assert.ok(result.limitations.includes("participant_approval_and_mutual_status_unverified"));
  assert.ok(result.limitations.includes("privileged_cleanup_companion_missing"));
  const output = JSON.stringify(result);
  for (const secret of [REF, "fixture_A", fixture().accounts[0].jwt, "PRIVATE PROFILE"]) assert.ok(!output.includes(secret));
});

test("target mismatch, lookalike hosts, credentials, ports and paths fail before requests", async () => {
  for (const url of ["http://" + REF + ".supabase.co", "https://" + REF + ".supabase.co.evil.invalid",
    "https://secret@" + REF + ".supabase.co", "https://" + REF + ".supabase.co:443",
    "https://" + REF + ".supabase.co/path", "https://" + REF + ".supabase.co/"]) {
    const input = fixture(); input.target.url = url;
    const result = await verify(input, options(() => assert.fail("invalid target connected")));
    assert.equal(result.code, "invalid_target");
  }
  const result = await verify(fixture(), { ...options(() => assert.fail("wrong target connected")), expectedProjectRef: "b".repeat(20) });
  assert.equal(result.code, "invalid_target");
});

test("JWT claims reject wrong identity, expiry and privileged roles but never replace server identity", async () => {
  for (const [token, code] of [[jwt("someone_else"), "jwt_identity_mismatch"],
    [jwt("fixture_A", { exp: NOW / 1000 }), "expired_jwt"],
    [jwt("fixture_A", { role: "service_role" }), "invalid_jwt"], ["malformed", "invalid_jwt"]]) {
    const input = fixture(); input.accounts[0].jwt = token;
    const result = await verify(input, options(() => assert.fail("rejected token connected")));
    assert.equal(result.code, code);
  }
  let calls = 0;
  const result = await verify(fixture(), options(async () => { calls += 1; return [{ id: "different_account" }]; }));
  assert.equal(result.code, "server_identity_mismatch");
  assert.equal(calls, 1);
});

test("signed canonical claim is supported and distinct accounts remain mandatory", () => {
  const input = fixture();
  input.accounts[0].jwt = jwt("clerk_subject", { canonical_user_id: "fixture_A" });
  assert.equal(validateInput(input, REF, NOW).accounts[0].accountID, "fixture_A");
  input.accounts[1] = { ...input.accounts[0], label: "B" };
  assert.throws(() => validateInput(input, REF, NOW), { message: "invalid_accounts" });
});

test("only publishable or legacy anon API keys are accepted", () => {
  const input = fixture();
  input.target.publishableKey = jwt("legacy_public_key", { role: "anon" });
  assert.equal(validateInput(input, REF, NOW).accounts.length, 2);
  for (const key of ["sb_secret_DO_NOT_SEND", jwt("admin", { role: "service_role" }), "raw-secret"] ) {
    input.target.publishableKey = key;
    assert.throws(() => validateInput(input, REF, NOW), { message: "invalid_target" });
  }
});

test("preexisting visible messages or incomplete inbox shape block without emitting their content", async () => {
  for (const inbox of [{ items: [{ body: "PRIVATE MESSAGE", id: "PRIVATE ID" }], nextCursor: null },
    { items: [], nextCursor: { id: "PRIVATE ID" } }, { items: [] }]) {
    const result = await verify(fixture(), options(async (input) => input.rpc === "current_profile" ? authorizedResponse(input) : inbox));
    assert.equal(result.status, "blocked");
    assert.ok(["preexisting_visible_messages", "invalid_response"].includes(result.code));
    assert.doesNotMatch(JSON.stringify(result), /PRIVATE MESSAGE|PRIVATE ID/);
  }
});

test("expiry is rechecked before subsequent requests", async () => {
  let time = NOW;
  let calls = 0;
  const input = fixture(); input.accounts[0].jwt = jwt("fixture_A", { exp: NOW / 1000 + 30 });
  const result = await verify(input, { expectedProjectRef: REF, mode: "preflight", now: () => time,
    transport: async () => { calls += 1; time += 6_000; return [{ id: calls === 1 ? "fixture_A" : "fixture_B" }]; } });
  assert.equal(result.status, "blocked");
  assert.equal(result.code, "jwt_expiring");
  assert.equal(calls, 2);
});

test("write requests cannot be enabled by a supplied receipt or adapter-shaped input", async () => {
  const input = { ...fixture(), cleanupReceipt: { approved: true }, cleanupAdapter: "pretend" };
  const result = await verify(input, options(() => assert.fail("write mode connected"), "write"));
  assert.equal(result.code, "cleanup_companion_required");
  assert.equal(result.writesEnabled, false);
});

function fakeRequest({ status = 200, headers = {}, chunks = ["{}"], hang = false, error, abort = false } = {}) {
  const calls = [];
  const factory = (url, options, callback) => {
    const req = new EventEmitter();
    req.destroy = () => { req.destroyed = true; };
    req.end = (body) => {
      calls.push({ url, options, body, req });
      queueMicrotask(() => {
        if (error) { req.emit("error", new Error(error)); return; }
        if (hang) return;
        const response = new EventEmitter();
        response.statusCode = status; response.headers = headers;
        response.destroy = () => { response.destroyed = true; };
        callback(response);
        if (response.destroyed) return;
        if (abort) { response.emit("aborted"); return; }
        for (const chunk of chunks) response.emit("data", Buffer.from(chunk));
        response.emit("end");
      });
    };
    return req;
  };
  return { factory, calls };
}
const requestInput = () => ({ target: fixture().target, jwt: fixture().accounts[0].jwt, rpc: "current_profile", params: {} });

test("HTTPS adapter sends exact read payload and token headers without shared agent/cookies", async () => {
  const mock = fakeRequest({ chunks: ['[{"id":"fixture_A"}]'] });
  assert.deepEqual(await requestJSON(requestInput(), { request: mock.factory }), [{ id: "fixture_A" }]);
  assert.equal(mock.calls[0].url, `https://${REF}.supabase.co/rest/v1/rpc/current_profile`);
  assert.equal(mock.calls[0].options.method, "POST");
  assert.equal(mock.calls[0].options.agent, false);
  assert.equal(mock.calls[0].options.rejectUnauthorized, true);
  assert.equal(mock.calls[0].options.headers.Authorization, `Bearer ${fixture().accounts[0].jwt}`);
  assert.equal(mock.calls[0].options.headers["Cache-Control"], "no-store");
  assert.equal(mock.calls[0].options.headers.Cookie, undefined);
  assert.equal(mock.calls[0].body, "{}");
});

test("HTTPS adapter never follows redirects or permits a write RPC", async () => {
  const mock = fakeRequest({ status: 307, headers: { location: "https://evil.invalid/credential-sink" } });
  await assert.rejects(requestJSON(requestInput(), { request: mock.factory }), { message: "redirect_rejected" });
  assert.equal(mock.calls.length, 1);
  assert.equal(mock.calls[0].req.destroyed, true);
  assert.throws(() => requestJSON({ ...requestInput(), rpc: "private_message_send" }, { request: mock.factory }), { message: "rpc_not_allowed" });
  assert.equal(mock.calls.length, 1);
});

test("HTTPS adapter bounds advertised and chunked response bodies", async () => {
  for (const config of [{ headers: { "content-length": String(256 * 1024 + 1) } },
    { chunks: ["x".repeat(128 * 1024), "x".repeat(128 * 1024 + 1)] }]) {
    const mock = fakeRequest(config);
    await assert.rejects(requestJSON(requestInput(), { request: mock.factory }), { message: "response_too_large" });
    assert.equal(mock.calls[0].req.destroyed, true);
  }
});

test("HTTPS adapter has a wall deadline and sanitizes malformed, interrupted and rejected responses", async () => {
  for (const [config, code] of [[{ hang: true }, "request_timeout"], [{ chunks: ["SECRET bad JSON"] }, "invalid_response"],
    [{ abort: true }, "transport_failed"], [{ error: "SECRET bearer value" }, "transport_failed"],
    [{ status: 401, chunks: ["SECRET"] }, "authorization_rejected"], [{ status: 500 }, "rpc_rejected"]]) {
    const mock = fakeRequest(config);
    await assert.rejects(requestJSON({ ...requestInput(), timeoutMs: 10 }, { request: mock.factory }), { message: code });
  }
});

async function cli(args, input, transport = () => assert.fail("unexpected network")) {
  let output = "";
  const code = await runCLI(args, { stdin: Readable.from([input]), stdout: { write: (value) => { output += value; } },
    transport, now: () => NOW });
  return { code, output };
}

test("CLI defaults to offline validation and explicit preflight is read-only", async () => {
  const dry = await cli(["--project-ref", REF], JSON.stringify(fixture()));
  assert.equal(dry.code, 0);
  assert.equal(JSON.parse(dry.output).mode, "dry-run");
  const live = await cli(["--project-ref", REF, "--preflight"], JSON.stringify(fixture()), authorizedResponse);
  assert.equal(live.code, 0);
  assert.equal(JSON.parse(live.output).step4Complete, false);
});

test("CLI blocks write flags before reading input and never echoes invalid arguments", async () => {
  let output = "";
  const code = await runCLI(["--write"], { stdin: { [Symbol.asyncIterator]() { assert.fail("must not read credentials"); } },
    stdout: { write: (value) => { output += value; } } });
  assert.equal(code, 2);
  assert.equal(JSON.parse(output).code, "cleanup_companion_required");
  const bad = await cli(["--SECRET_TOKEN"], "PRIVATE_INPUT");
  assert.equal(bad.code, 2);
  assert.doesNotMatch(bad.output, /SECRET_TOKEN|PRIVATE_INPUT/);
});

test("CLI bounds input and sanitizes parser and unexpected transport errors", async () => {
  const oversized = await cli(["--project-ref", REF], "x".repeat(32 * 1024 + 1));
  assert.equal(JSON.parse(oversized.output).code, "input_too_large");
  const malformed = await cli(["--project-ref", REF], "PRIVATE_INPUT not JSON");
  assert.equal(JSON.parse(malformed.output).code, "invalid_input");
  const failed = await cli(["--project-ref", REF, "--preflight"], JSON.stringify(fixture()),
    () => { throw new Error(`SECRET ${fixture().accounts[0].jwt}`); });
  assert.equal(failed.code, 2);
  assert.equal(JSON.parse(failed.output).code, "verification_failed");
  assert.doesNotMatch(failed.output + malformed.output, /SECRET|PRIVATE_INPUT|fictional_signature/);
});
