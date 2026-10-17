#!/usr/bin/env node

// This entry point never discovers credentials or enables Live. Network writes
// require the independently verified companion plus a fresh owned baseline.
import https from "node:https";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { validateInput } from "./rec636-real-client-verification.mjs";
import { isMutationJournalHandle, MutationJournalError } from "./rec636-mutation-journal.mjs";
import { isVerifiedCleanupCompanion, CleanupCompanionError } from "./rec636-cleanup-companion.mjs";

const REQUEST_TIMEOUT_MS = 20_000;
const RUN_TIMEOUT_MS = 180_000;
const MAX_RESPONSE_BYTES = 256 * 1024;
const MAX_REQUESTS = 160;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u;
const object = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const permits = new WeakMap();
const ERROR_CODES = new Set(["private_message_unavailable", "private_message_idempotency_conflict",
  "private_message_rate_limited", "private_message_invalid_body", "private_message_invalid_cursor"]);
const RPC_KEYS = {
  current_profile: [], private_message_inbox: ["input_limit"],
  private_message_conversation: ["input_conversation_id"],
  private_message_start: ["input_recipient_id", "input_context_kind", "input_context_id"],
  private_message_history: ["input_conversation_id", "input_limit"],
  private_message_send: ["input_conversation_id", "input_body", "input_client_id", "input_context_kind", "input_context_id"],
  private_message_mark_read: ["input_conversation_id", "input_through_message_id"],
};
const WRITE_RPCS = new Set(["private_message_start", "private_message_send", "private_message_mark_read"]);
export class WriteVerificationError extends Error {
  constructor(code) { super(code); this.code = code; }
}
const fail = (code) => { throw new WriteVerificationError(code); };
// Only these reviewed enum values may cross the output boundary. Typed
// adapter errors still cannot echo arbitrary safe-looking private strings.
const OUTPUT_ERROR_CODES = new Set([
  "rpc_not_allowed", "invalid_rpc_parameters", "invalid_target", "invalid_jwt", "write_permit_required",
  "invalid_timeout", "request_cancelled", "request_timeout", "redirect_rejected", "response_too_large",
  "invalid_response", "transport_failed", "authorization_rejected", "rpc_rejected", "designated_accounts_required",
  "journal_scope_mismatch", "unexpected_history_page", "conversation_mismatch", "message_mismatch",
  "request_budget_exceeded", "verification_timeout", "jwt_expiring", "unexpected_rejection",
  "revocation_not_enforced", "server_identity_mismatch", "preexisting_visible_messages", "reciprocal_start_duplicated",
  "empty_thread_exposed_in_inbox", "same_id_retry_duplicated", "history_row_count_mismatch", "history_row_mismatch",
  "invalid_read_acknowledgment", "receipt_missing", "opposite_sender_collision", "context_preview_baseline_missing",
  "revoked_context_preview_exposed", "revoked_inbox_exposed", "gateway_authentication_failed",
  "reconciliation_incomplete", "reconciliation_scope_mismatch", "cleanup_not_verified",
  "verified_cleanup_companion_required", "mutation_journal_required", "writable_baseline_not_verified",
  "journal_io_failed", "journal_busy_or_exists", "journal_missing", "journal_already_cleaned", "journal_frozen_for_cleanup",
  "unsafe_journal_file", "invalid_journal", "invalid_journal_path", "journal_too_large", "reconciliation_required",
  "acknowledgment_conflict", "acknowledgment_scope_mismatch", "operator_row_identity_mismatch",
  "operator_receipt_chain_mismatch", "operator_execution_failed", "operator_verification_failed", "baseline_drift",
  "companion_scope_mismatch", "fixture_not_ready", "unclean_or_invalid_baseline", "operator_adapter_required",
  "pristine_journal_required", "operator_failed", "journal_failed", "verification_failed",
]);
const safeCode = (error) => {
  if (![WriteVerificationError, MutationJournalError, CleanupCompanionError].some((kind) => error instanceof kind)) return "verification_failed";
  if (OUTPUT_ERROR_CODES.has(error.code)) return error.code;
  if (error instanceof MutationJournalError) return "journal_failed";
  if (error instanceof CleanupCompanionError) return "operator_failed";
  return "verification_failed";
};
const exactKeys = (value, keys) => object(value) && Object.keys(value).length === keys.length
  && keys.every((key) => Object.hasOwn(value, key));

export function validateRPC(rpc, params) {
  if (!Object.hasOwn(RPC_KEYS, rpc) || !exactKeys(params, RPC_KEYS[rpc])) fail("rpc_not_allowed");
  for (const key of ["input_conversation_id", "input_client_id", "input_through_message_id"]) {
    if (Object.hasOwn(params, key) && !UUID.test(params[key] ?? "")) fail("invalid_rpc_parameters");
  }
  if (Object.hasOwn(params, "input_limit") && params.input_limit !== 50) fail("invalid_rpc_parameters");
  if (Object.hasOwn(params, "input_context_kind")) {
    if (!(params.input_context_kind === null && params.input_context_id === null)
      && !(["place", "activity"].includes(params.input_context_kind) && UUID.test(params.input_context_id ?? ""))) {
      fail("invalid_rpc_parameters");
    }
    if (rpc === "private_message_start" && params.input_context_kind === null) fail("invalid_rpc_parameters");
  }
  if (rpc === "private_message_start" && !/^[A-Za-z0-9_-]{1,256}$/u.test(params.input_recipient_id ?? "")) fail("invalid_rpc_parameters");
  if (rpc === "private_message_send" && (typeof params.input_body !== "string"
    || [...params.input_body].length < 1 || [...params.input_body].length > 2000
    || params.input_body !== params.input_body.replace(/^[ \t\n\r]+|[ \t\n\r]+$/gu, "")
    || /^\s*$/u.test(params.input_body))) fail("invalid_rpc_parameters");
}

function safeTarget(target) {
  if (!object(target) || !/^[a-z0-9]{20}$/u.test(target.projectRef ?? "")
    || target.url !== `https://${target.projectRef}.supabase.co`
    || typeof target.publishableKey !== "string" || /[\s\x00-\x1f\x7f]/u.test(target.publishableKey)
    || target.publishableKey.length > 16_384) fail("invalid_target");
  if (/^sb_publishable_[A-Za-z0-9_-]+$/u.test(target.publishableKey)) return;
  try {
    const parts = target.publishableKey.split(".");
    if (parts.length === 3 && JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"))?.role === "anon") return;
  } catch { /* Do not report the input or decoded claims. */ }
  fail("invalid_target");
}

// A plain receipt, serialized input or direct adapter call cannot issue writes.
// Only verifyRealClients creates this in-memory capability after its gates pass.
export function requestAuthenticatedRPC(input, { request = https.request } = {}) {
  safeTarget(input.target);
  validateRPC(input.rpc, input.params);
  if (typeof input.jwt !== "string" || !input.jwt || input.jwt.length > 16_384
    || /[\s\x00-\x1f\x7f]/u.test(input.jwt)) fail("invalid_jwt");
  if (WRITE_RPCS.has(input.rpc)) {
    const permit = permits.get(input.writePermit);
    if (!permit || permit.targetRef !== input.target.projectRef || !permit.tokens.has(input.jwt)
      || permit.expiresAt <= performance.now() || ++permit.requests > MAX_REQUESTS) fail("write_permit_required");
  }
  const timeoutMs = Math.min(REQUEST_TIMEOUT_MS, input.timeoutMs ?? REQUEST_TIMEOUT_MS);
  if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) fail("invalid_timeout");
  return new Promise((resolveResponse, reject) => {
    let req;
    let response;
    let settled = false;
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      input.signal?.removeEventListener("abort", aborted);
      if (error) { response?.destroy(); req?.destroy(); reject(error); }
      else resolveResponse(value);
    };
    const aborted = () => finish(new WriteVerificationError("request_cancelled"));
    const timer = setTimeout(() => finish(new WriteVerificationError("request_timeout")), timeoutMs);
    if (input.signal?.aborted) { aborted(); return; }
    input.signal?.addEventListener("abort", aborted, { once: true });
    try {
      const body = JSON.stringify(input.params);
      req = request(`${input.target.url}/rest/v1/rpc/${input.rpc}`, {
        method: "POST", agent: false, rejectUnauthorized: true,
        headers: { apikey: input.target.publishableKey, Authorization: `Bearer ${input.jwt}`,
          "Content-Type": "application/json", Accept: "application/json", "Cache-Control": "no-store",
          "Content-Length": Buffer.byteLength(body) },
      }, (incoming) => {
        response = incoming;
        if (settled) { incoming.destroy(); return; }
        const status = incoming.statusCode ?? 0;
        if (status >= 300 && status < 400) return finish(new WriteVerificationError("redirect_rejected"));
        if (Number(incoming.headers["content-length"]) > MAX_RESPONSE_BYTES) return finish(new WriteVerificationError("response_too_large"));
        let bytes = 0;
        const chunks = [];
        incoming.on("data", (chunk) => {
          if (settled) return;
          bytes += Buffer.byteLength(chunk);
          if (bytes > MAX_RESPONSE_BYTES) return finish(new WriteVerificationError("response_too_large"));
          chunks.push(Buffer.from(chunk));
        });
        incoming.on("end", () => {
          if (settled) return;
          let data;
          try { data = JSON.parse(Buffer.concat(chunks).toString("utf8")); }
          catch { return finish(new WriteVerificationError("invalid_response")); }
          if (status >= 200 && status < 300) return finish(null, { status: "ok", data });
          if (status === 400 && data?.code === "P0001" && ERROR_CODES.has(data.message)) {
            return finish(null, { status: "rejected", code: data.message });
          }
          finish(new WriteVerificationError(status === 401 || status === 403 ? "authorization_rejected" : "rpc_rejected"));
        });
        incoming.on("aborted", () => finish(new WriteVerificationError("transport_failed")));
        incoming.on("error", () => finish(new WriteVerificationError("transport_failed")));
      });
      req.on("error", () => finish(new WriteVerificationError("transport_failed")));
      req.end(body);
    } catch { finish(new WriteVerificationError("transport_failed")); }
  });
}

function assertDesignation(input, designation, snapshot, expectedProjectRef) {
  if (!exactKeys(designation, ["internalAccountsApproved", "targetRef", "accounts", "runID", "context"])
    || designation.internalAccountsApproved !== true || designation.targetRef !== expectedProjectRef
    || !exactKeys(designation.accounts, ["A", "B"]) || !UUID.test(designation.runID ?? "")
    || !exactKeys(designation.context, ["kind", "id"]) || !["place", "activity"].includes(designation.context.kind)
    || !UUID.test(designation.context.id ?? "")) fail("designated_accounts_required");
  for (const account of input.accounts) {
    if (designation.accounts[account.label] !== account.accountID) fail("designated_accounts_required");
  }
  if (snapshot.runID !== designation.runID || snapshot.targetRef !== expectedProjectRef
    || snapshot.accounts?.A !== designation.accounts.A || snapshot.accounts?.B !== designation.accounts.B
    || snapshot.context?.kind !== designation.context.kind || snapshot.context?.id !== designation.context.id) fail("journal_scope_mismatch");
}

const emptyPage = (data) => object(data) && Array.isArray(data.items) && data.items.length === 0 && data.nextCursor === null;
function pageItems(data) {
  if (!object(data) || !Array.isArray(data.items) || data.nextCursor !== null) fail("unexpected_history_page");
  return data.items;
}
function assertConversation(data, recipientID, expectedID) {
  if (!object(data) || !UUID.test(data.id ?? "") || data.participant?.id !== recipientID
    || (expectedID && data.id !== expectedID)) fail("conversation_mismatch");
  return data.id;
}
function assertMessage(data, { conversationID, senderID, clientID, body, context }) {
  if (!object(data) || !UUID.test(data.id ?? "") || data.conversationID !== conversationID
    || data.senderID !== senderID || data.clientID !== clientID || data.body !== body
    || (context ? data.context?.kind !== context.kind || data.context?.id !== context.id : data.context !== null)) fail("message_mismatch");
  return data.id;
}

async function drainConcurrent(operations) {
  const settled = await Promise.allSettled(operations);
  const failures = settled.filter((result) => result.status === "rejected").map((result) => result.reason);
  if (failures.length) {
    // Prefer the uncertainty gate even if a known fast rejection happened first.
    throw failures.find((error) => error?.ambiguousWrite) ?? failures[0];
  }
  return settled.map((result) => result.value);
}

// Shared protocol executor for deterministic adapters. It never creates a
// network write permit. The production entry point below owns all write gates.
export async function executeVerificationScenario({ accounts, target, context, journal, companion,
  transport, writePermit, now = Date.now, monotonic = now, deadline = monotonic() + RUN_TIMEOUT_MS, checks = [] }) {
  let calls = 0;
  const other = (label) => label === "A" ? "B" : "A";
  const byLabel = Object.fromEntries(accounts.map((account) => [account.label, account]));
  const call = async (label, rpc, params) => {
    validateRPC(rpc, params);
    if (++calls > MAX_REQUESTS) fail("request_budget_exceeded");
    const timeoutMs = Math.min(REQUEST_TIMEOUT_MS, deadline - monotonic());
    if (timeoutMs <= 0) fail("verification_timeout");
    const account = byLabel[label];
    if (account.expiresAt <= now() + timeoutMs) fail("jwt_expiring");
    const controller = new AbortController();
    let timer;
    let result;
    try {
      const timedOut = new Promise((_, reject) => {
        timer = setTimeout(() => {
          controller.abort(); reject(new WriteVerificationError("request_timeout"));
        }, timeoutMs);
      });
      result = await Promise.race([transport({ target, jwt: account.jwt, rpc, params, timeoutMs,
        writePermit, signal: controller.signal }), timedOut]);
    } finally { clearTimeout(timer); }
    if (!object(result) || !["ok", "rejected"].includes(result.status)
      || (result.status === "rejected" && !ERROR_CODES.has(result.code))) fail("invalid_response");
    return result;
  };
  const read = async (label, rpc, params) => {
    const response = await call(label, rpc, params);
    if (response.status !== "ok") fail("unexpected_rejection");
    return response.data;
  };
  const mutation = async (intent, rpc, params, { denied = false, discard = false } = {}) => {
    let result;
    try { result = await call(intent.actor, rpc, params); }
    catch (error) {
      // Preserve dispatch uncertainty even if the durable annotation itself
      // fails. The original persisted pending intent still blocks cleanup.
      const uncertain = new WriteVerificationError(safeCode(error));
      uncertain.ambiguousWrite = true;
      try { await journal.markInterrupted(intent.id); }
      catch { uncertain.journalAnnotationFailed = true; }
      throw uncertain;
    }
    if (denied) {
      if (result.status !== "rejected" || result.code !== "private_message_unavailable") {
        await journal.markInterrupted(intent.id); fail("revocation_not_enforced");
      }
      await journal.recordRejection(intent.id, { code: result.code });
      return;
    }
    if (result.status !== "ok") { await journal.recordRejection(intent.id, { code: result.code }); fail("unexpected_rejection"); }
    if (discard) { await journal.markInterrupted(intent.id); return; }
    return result.data;
  };
  const acknowledgment = async (intent, data, extra = {}) => journal.recordAcknowledgment(intent.id,
    { conversationID: data.conversationID ?? data.id, ...extra });

  for (const label of ["A", "B"]) {
    const profile = await read(label, "current_profile", {});
    if (!Array.isArray(profile) || profile.length !== 1 || profile[0]?.id !== byLabel[label].accountID) fail("server_identity_mismatch");
    if (!emptyPage(await read(label, "private_message_inbox", { input_limit: 50 }))) fail("preexisting_visible_messages");
  }
  checks.push("both_gateway_identities", "empty_visible_inboxes");
  const starts = await drainConcurrent(["A", "B"].map(async (actor) => {
    const intent = await journal.recordIntent({ kind: "start", actor, recipient: other(actor), context });
    const data = await mutation(intent, "private_message_start", { input_recipient_id: byLabel[other(actor)].accountID,
      input_context_kind: context.kind, input_context_id: context.id });
    const id = assertConversation(data, byLabel[other(actor)].accountID);
    await acknowledgment(intent, data);
    return id;
  }));
  if (starts[0] !== starts[1]) fail("reciprocal_start_duplicated");
  const conversationID = starts[0];
  checks.push("concurrent_reciprocal_start");
  for (const label of ["A", "B"]) if (!emptyPage(await read(label, "private_message_inbox", { input_limit: 50 }))) fail("empty_thread_exposed_in_inbox");
  checks.push("empty_thread_omitted");

  const messageExpectations = new Map();
  const newSend = async (actor, body, quotedContext = null) => {
    const intent = await journal.recordIntent({ kind: "send", actor, conversationID, context: quotedContext });
    return { intent, expected: { conversationID, senderID: byLabel[actor].accountID,
      clientID: intent.clientID, body, context: quotedContext }, params: { input_conversation_id: conversationID,
      input_body: body, input_client_id: intent.clientID, input_context_kind: quotedContext?.kind ?? null,
      input_context_id: quotedContext?.id ?? null } };
  };
  const send = async (prepared, options) => {
    const data = await mutation(prepared.intent, "private_message_send", prepared.params, options);
    if (options?.discard) return;
    const id = assertMessage(data, prepared.expected);
    await acknowledgment(prepared.intent, data, { messageID: id, senderID: data.senderID, clientID: data.clientID });
    messageExpectations.set(id, prepared.expected);
    return id;
  };
  const initial = await newSend("A", "REC-636 synthetic contextual message.", context);
  // Both requests use the same journaled UUID and exact transient payload.
  const initialRetry = { ...initial, intent: await journal.recordRetry(initial.intent.id) };
  const duplicate = await drainConcurrent([send(initial), send(initialRetry)]);
  if (duplicate[0] !== duplicate[1]) fail("same_id_retry_duplicated");
  const contextualMessageID = duplicate[0];
  const history = async (label) => pageItems(await read(label, "private_message_history", { input_conversation_id: conversationID, input_limit: 50 }));
  const assertHistory = async (label, excludedContext = false) => {
    const items = await history(label);
    const expected = [...messageExpectations].filter(([, value]) => !(excludedContext && value.context));
    if (items.length !== expected.length || new Set(items.map((item) => item.id)).size !== items.length) fail("history_row_count_mismatch");
    for (const [id, value] of expected) {
      const data = items.find((item) => item.id === id);
      if (assertMessage(data, value) !== id) fail("history_row_mismatch");
    }
    return items;
  };
  await assertHistory("B");
  checks.push("same_id_concurrent_send", "recipient_delivery");
  const reply = await newSend("B", "REC-636 synthetic reply.", context);
  const replyID = await send(reply);
  const readIntent = await journal.recordIntent({ kind: "mark_read", actor: "A", conversationID, throughMessageID: replyID });
  const marked = await mutation(readIntent, "private_message_mark_read", { input_conversation_id: conversationID, input_through_message_id: replyID });
  if (!exactKeys(marked, [])) fail("invalid_read_acknowledgment");
  await journal.recordAcknowledgment(readIntent.id, { conversationID, throughMessageID: replyID });
  const afterRead = await assertHistory("B");
  if (typeof afterRead.find((item) => item.id === replyID)?.recipientReadAt !== "string") fail("receipt_missing");
  checks.push("reply_delivery", "recipient_read_receipt");

  const interrupted = await newSend("A", "REC-636 synthetic interrupted acknowledgment.");
  await send(interrupted, { discard: true });
  await reconcileInterrupted(journal, companion);
  const lostAckRetry = { ...interrupted, intent: await journal.recordRetry(interrupted.intent.id) };
  await send(lostAckRetry);
  await assertHistory("B");
  checks.push("completed_response_discard_same_id_retry");
  const concurrent = await drainConcurrent([newSend("A", "REC-636 simultaneous A."), newSend("B", "REC-636 simultaneous B.")]);
  const oppositeIDs = await drainConcurrent(concurrent.map((value) => send(value)));
  if (oppositeIDs[0] === oppositeIDs[1]) fail("opposite_sender_collision");
  await assertHistory("A"); await assertHistory("B");
  checks.push("bounded_opposite_sender_concurrency");
  // Make a contextual message the newest preview before revocation so this
  // trial proves preview suppression as well as history/read suppression.
  const latestContext = await newSend("A", "REC-636 latest synthetic context.", context);
  await send(latestContext);

  for (const trial of [
    { resource: "account_flag", actor: "A" }, { resource: "account_flag", actor: "B" },
    { resource: "follow", actor: "A", targetActor: "B" },
    { resource: "block", actor: "A", targetActor: "B" }, { resource: "block", actor: "B", targetActor: "A" },
    { resource: "context", actor: journal.snapshot().baseline.contextReceipt.ownerID === byLabel.B.accountID ? "B" : "A" },
  ]) {
    if (trial.resource === "context") {
      for (const label of ["A", "B"]) {
        const visible = pageItems(await read(label, "private_message_inbox", { input_limit: 50 }));
        if (visible.length !== 1 || visible[0]?.id !== conversationID
          || visible[0].lastMessagePreview !== latestContext.expected.body) fail("context_preview_baseline_missing");
      }
    }
    const change = await journal.recordIntent({ kind: "operator_transition", actor: trial.actor,
      transition: { ...trial, action: trial.resource === "block" ? "insert" : trial.resource === "follow" ? "remove" : "revoke" } });
    await journal.recordAcknowledgment(change.id, await companion.transitionOwnedFixture(journal.snapshot(), change.id));
    for (const label of ["A", "B"]) {
      const inbox = await read(label, "private_message_inbox", { input_limit: 50 });
      if (trial.resource === "context") {
        await assertHistory(label, true);
        const preview = pageItems(inbox);
        const hiddenBodies = [...messageExpectations.values()].filter((value) => value.context).map((value) => value.body);
        if (preview.length !== 1 || preview[0]?.id !== conversationID
          || preview.some((item) => hiddenBodies.includes(item.lastMessagePreview))) fail("revoked_context_preview_exposed");
      } else {
        if (!emptyPage(inbox)) fail("revoked_inbox_exposed");
        for (const [rpc, params] of [["private_message_conversation", { input_conversation_id: conversationID }],
          ["private_message_history", { input_conversation_id: conversationID, input_limit: 50 }]]) {
          const result = await call(label, rpc, params);
          if (result.status !== "rejected" || result.code !== "private_message_unavailable") fail("revocation_not_enforced");
        }
      }
    }
    for (const label of ["A", "B"]) {
      const deniedStart = await journal.recordIntent({ kind: "start", actor: label, recipient: other(label), context });
      await mutation(deniedStart, "private_message_start", { input_recipient_id: byLabel[other(label)].accountID,
        input_context_kind: context.kind, input_context_id: context.id }, { denied: true });
      const deniedSend = await newSend(label, "REC-636 synthetic denied message.", context);
      await mutation(deniedSend.intent, "private_message_send", deniedSend.params, { denied: true });
      // An existing original acknowledgment is retained when its retry is denied.
      const prior = label === "A" ? initial : reply;
      const deniedRetry = await journal.recordRetry(prior.intent.id);
      await mutation(deniedRetry, "private_message_send", prior.params, { denied: true });
      const deniedRead = await journal.recordIntent({ kind: "mark_read", actor: label, conversationID, throughMessageID: contextualMessageID });
      await mutation(deniedRead, "private_message_mark_read", { input_conversation_id: conversationID,
        input_through_message_id: contextualMessageID }, { denied: true });
    }
    const restore = await journal.recordIntent({ kind: "operator_transition", actor: trial.actor,
      transition: { ...trial, action: trial.resource === "block" ? "remove" : "restore" } });
    await journal.recordAcknowledgment(restore.id, await companion.transitionOwnedFixture(journal.snapshot(), restore.id));
    await assertHistory("A"); await assertHistory("B");
    checks.push(`${trial.resource}_${trial.actor}_revoked_and_restored`);
  }
  // Fresh requests prove durable server state, not a native app relaunch.
  await assertHistory("A"); await assertHistory("B");
  checks.push("fresh_server_history_after_trials");
  return { checks, requestCount: calls, conversationCount: 1, messageCount: messageExpectations.size };
}

async function authenticateGateway({ target, accounts }, transport, now, monotonic) {
  const deadline = monotonic() + 60_000;
  for (const account of accounts) {
    for (const [rpc, params] of [["current_profile", {}], ["private_message_inbox", { input_limit: 50 }]]) {
      const timeoutMs = Math.min(REQUEST_TIMEOUT_MS, deadline - monotonic());
      if (timeoutMs <= 0 || account.expiresAt <= now() + timeoutMs) fail("jwt_expiring");
      const controller = new AbortController(); let timer; let response;
      try {
        const timeout = new Promise((_, reject) => {
          timer = setTimeout(() => { controller.abort(); reject(new WriteVerificationError("request_timeout")); }, timeoutMs);
        });
        response = await Promise.race([transport({ target, jwt: account.jwt, rpc, params, timeoutMs,
          signal: controller.signal }), timeout]);
      } finally { clearTimeout(timer); }
      if (response?.status !== "ok") fail("gateway_authentication_failed");
      if (rpc === "current_profile" && (!Array.isArray(response.data) || response.data.length !== 1
        || response.data[0]?.id !== account.accountID)) fail("server_identity_mismatch");
      if (rpc === "private_message_inbox" && !emptyPage(response.data)) fail("preexisting_visible_messages");
    }
  }
}

async function reconcileInterrupted(journal, companion) {
  const snapshot = journal.snapshot();
  const pending = snapshot.intents.filter((intent) => ["intent", "interrupted"].includes(intent.state));
  if (!pending.length) return;
  const result = await companion.reconcile(snapshot);
  if (!exactKeys(result, ["intents"]) || !Array.isArray(result.intents) || result.intents.length !== pending.length) fail("reconciliation_incomplete");
  const seen = new Set();
  for (const receipt of result.intents) {
    if (!object(receipt) || !["found", "absent"].includes(receipt.status) || seen.has(receipt.intentID)
      || !pending.some((intent) => intent.id === receipt.intentID)) fail("reconciliation_scope_mismatch");
    seen.add(receipt.intentID);
    if (!exactKeys(receipt, receipt.status === "found" ? ["intentID", "status", "ack"] : ["intentID", "status"])) fail("reconciliation_scope_mismatch");
    await journal.reconcile(receipt.intentID, receipt.status === "found" ? { status: "found", ack: receipt.ack } : { status: "absent" });
  }
}

async function finishCleanup(journal, companion) {
  await reconcileInterrupted(journal, companion);
  await journal.beginCleanup();
  const cleanup = await companion.cleanup(journal.snapshot());
  if (cleanup?.verified !== true || cleanup?.globalLiveOff !== true || cleanup?.baselineRestored !== true
    || cleanup.runID !== journal.snapshot().runID || cleanup.conversationCount !== 0 || cleanup.messageCount !== 0
    || cleanup.globalLiveEnabled !== false) fail("cleanup_not_verified");
  await journal.markCleanupVerified({ runID: cleanup.runID, conversationCount: 0, messageCount: 0,
    baselineRestored: true, globalLiveEnabled: false });
  return true;
}

export async function verifyRealClients(input, { expectedProjectRef, designation, journal, companion,
  transport = requestAuthenticatedRPC, now = Date.now, monotonic = () => performance.now() } = {}) {
  const base = { status: "blocked", writesEnabled: false, step4Complete: false, backendDeliveryVerified: false,
    cleanupVerified: false, unresolvedIntentCount: 0, checks: [], limitations: ["native_real_account_journeys_unverified",
      "controlled_database_lock_wait_and_quota_concurrency_unverified", "native_relaunch_offline_and_replay_separate"] };
  let started = false;
  let writePermit;
  try {
    if (!isVerifiedCleanupCompanion(companion)) fail("verified_cleanup_companion_required");
    if (!isMutationJournalHandle(journal)) fail("mutation_journal_required");
    const validated = validateInput(input, expectedProjectRef, now());
    assertDesignation(validated, designation, journal.snapshot(), expectedProjectRef);
    await authenticateGateway(validated, transport, now, monotonic);
    const ready = await companion.assertReady(journal.snapshot());
    if (ready?.globalLiveOff !== true || ready?.pristineBaseline !== true || ready?.fixtureTransitionsVerified !== true) fail("writable_baseline_not_verified");
    writePermit = Object.freeze({});
    permits.set(writePermit, { targetRef: expectedProjectRef, tokens: new Set(validated.accounts.map((account) => account.jwt)),
      expiresAt: performance.now() + RUN_TIMEOUT_MS, requests: 0 });
    started = true;
    const result = await executeVerificationScenario({ ...validated, context: designation.context, journal,
      companion, transport, writePermit, now, monotonic, checks: base.checks });
    await finishCleanup(journal, companion);
    return { ...base, status: "pass", writesEnabled: true, backendDeliveryVerified: true, cleanupVerified: true, ...result };
  } catch (error) {
    const code = safeCode(error);
    if (started) {
      // Aborting HTTP does not prove that a gateway transaction cannot arrive
      // later. An operator must verify quiescence before resolving these intents.
      if (error?.ambiguousWrite) return { ...base, writesEnabled: true, code,
        cleanupCode: "transport_quiescence_unverified",
        ...(error.journalAnnotationFailed ? { journalAnnotationFailed: true } : {}),
        unresolvedIntentCount: journal.snapshot().intents.filter((intent) => ["intent", "interrupted"].includes(intent.state)).length };
      try {
        await finishCleanup(journal, companion);
        return { ...base, writesEnabled: true, code, cleanupVerified: true };
      } catch { return { ...base, writesEnabled: true, code, cleanupCode: "cleanup_requires_operator_review",
        unresolvedIntentCount: journal.snapshot().intents.filter((intent) => ["intent", "interrupted"].includes(intent.state)).length }; }
    }
    return { ...base, code };
  } finally { if (writePermit) permits.delete(writePermit); }
}

export async function runCLI(args, { stdout = process.stdout } = {}) {
  if (args.length === 1 && args[0] === "--help") {
    stdout.write("REC-636 real-client writes require a reviewed programmatic invocation with the verified cleanup companion, durable journal, designated internal accounts and ephemeral signed-in sessions.\n"
      + "No CLI write mode, credential discovery or environment lookup is available. Existing preflight remains read-only.\n");
    return 0;
  }
  stdout.write(`${JSON.stringify({ status: "blocked", writesEnabled: false, step4Complete: false,
    code: "reviewed_companion_invocation_required" })}\n`);
  return 2;
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) process.exitCode = await runCLI(process.argv.slice(2));
