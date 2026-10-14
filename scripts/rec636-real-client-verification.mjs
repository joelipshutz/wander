#!/usr/bin/env node

import https from "node:https";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const MAX_INPUT_BYTES = 32 * 1024;
const MAX_RESPONSE_BYTES = 256 * 1024;
const REQUEST_TIMEOUT_MS = 20_000;
const READ_RPCS = new Set(["current_profile", "private_message_inbox"]);
const LIMITATIONS = [
  "participant_approval_and_mutual_status_unverified",
  "empty_conversation_absence_unverified",
  "privileged_cleanup_companion_missing",
  "real_delivery_and_concurrency_unverified",
];

class VerificationError extends Error {
  constructor(code) { super(code); this.code = code; }
}
const fail = (code) => { throw new VerificationError(code); };
const object = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const safeHeader = (value) => typeof value === "string" && value.length > 0
  && value.length <= 16_384 && !/[\s\x00-\x1f\x7f]/u.test(value);

function isPublishableKey(value) {
  if (!safeHeader(value)) return false;
  if (/^sb_publishable_[A-Za-z0-9_-]+$/u.test(value)) return true;
  const parts = value.split(".");
  if (parts.length !== 3) return false;
  try { return JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"))?.role === "anon"; }
  catch { return false; }
}

function validateTarget(target, expectedProjectRef) {
  if (!object(target) || !/^[a-z0-9]{20}$/u.test(expectedProjectRef ?? "")
    || target.projectRef !== expectedProjectRef
    || target.url !== `https://${expectedProjectRef}.supabase.co`
    || !isPublishableKey(target.publishableKey)) fail("invalid_target");
}

export function validateInput(input, expectedProjectRef, now = Date.now()) {
  if (!object(input)) fail("invalid_input");
  validateTarget(input.target, expectedProjectRef);
  if (!Array.isArray(input.accounts) || input.accounts.length !== 2) fail("invalid_accounts");
  const accounts = input.accounts.map((account, index) => {
    if (!object(account) || account.label !== ["A", "B"][index]
      || !/^[A-Za-z0-9_-]{1,256}$/u.test(account.accountID ?? "")
      || !safeHeader(account.jwt)) fail("invalid_accounts");
    const parts = account.jwt.split(".");
    if (parts.length !== 3 || parts.some((part) => !/^[A-Za-z0-9_-]+$/u.test(part))) fail("invalid_jwt");
    let claims;
    try { claims = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8")); }
    catch { fail("invalid_jwt"); }
    if (!object(claims) || !Number.isFinite(claims.exp)) fail("invalid_jwt");
    if (claims.role !== undefined && claims.role !== "authenticated") fail("invalid_jwt");
    // Unverified claims can reject a mismatch, but never establish identity.
    // Only current_profile through the real gateway establishes that below.
    const claimedID = claims.canonical_user_id || claims.sub;
    if (claimedID !== account.accountID) fail("jwt_identity_mismatch");
    if (claims.exp * 1000 <= now) fail("expired_jwt");
    return { ...account, expiresAt: claims.exp * 1000 };
  });
  if (accounts[0].accountID === accounts[1].accountID || accounts[0].jwt === accounts[1].jwt) fail("invalid_accounts");
  return { target: input.target, accounts };
}

export function requestJSON(input, { request = https.request } = {}) {
  validateTarget(input.target, input.target?.projectRef);
  if (!READ_RPCS.has(input.rpc)) fail("rpc_not_allowed");
  if (!safeHeader(input.jwt)) fail("invalid_jwt");
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
      if (error) { response?.destroy(); req?.destroy(); reject(error); }
      else resolveResponse(value);
    };
    // A wall-time deadline also bounds a peer that keeps sending small chunks.
    const timer = setTimeout(() => finish(new VerificationError("request_timeout")), timeoutMs);
    try {
      const body = JSON.stringify(input.params);
      req = request(`${input.target.url}/rest/v1/rpc/${input.rpc}`, {
        method: "POST", agent: false, rejectUnauthorized: true,
        headers: {
          apikey: input.target.publishableKey,
          Authorization: `Bearer ${input.jwt}`,
          "Content-Type": "application/json", Accept: "application/json",
          "Cache-Control": "no-store", "Content-Length": Buffer.byteLength(body),
        },
      }, (incoming) => {
        response = incoming;
        if (settled) { incoming.destroy(); return; }
        const status = incoming.statusCode ?? 0;
        if (status >= 300 && status < 400) return finish(new VerificationError("redirect_rejected"));
        if (status < 200 || status >= 300) return finish(new VerificationError(
          status === 401 || status === 403 ? "authorization_rejected" : "rpc_rejected",
        ));
        if (Number(incoming.headers["content-length"]) > MAX_RESPONSE_BYTES) {
          return finish(new VerificationError("response_too_large"));
        }
        let size = 0;
        const chunks = [];
        incoming.on("data", (chunk) => {
          if (settled) return;
          size += Buffer.byteLength(chunk);
          if (size > MAX_RESPONSE_BYTES) return finish(new VerificationError("response_too_large"));
          chunks.push(Buffer.from(chunk));
        });
        incoming.on("end", () => {
          if (settled) return;
          try { finish(null, JSON.parse(Buffer.concat(chunks).toString("utf8"))); }
          catch { finish(new VerificationError("invalid_response")); }
        });
        incoming.on("aborted", () => finish(new VerificationError("transport_failed")));
        incoming.on("error", () => finish(new VerificationError("transport_failed")));
      });
      req.on("error", () => finish(new VerificationError("transport_failed")));
      req.end(body);
    } catch { finish(new VerificationError("transport_failed")); }
  });
}

export async function verify(input, { expectedProjectRef, mode = "dry-run", transport = requestJSON, now = Date.now } = {}) {
  const checks = [];
  const base = { mode: ["dry-run", "preflight", "write"].includes(mode) ? mode : "unsupported",
    writesEnabled: false, step4Complete: false, limitations: LIMITATIONS };
  try {
    if (mode === "write") fail("cleanup_companion_required");
    if (!["dry-run", "preflight"].includes(mode)) fail("invalid_mode");
    const { target, accounts } = validateInput(input, expectedProjectRef, now());
    if (mode === "dry-run") return { ...base, status: "pass", checks: ["input_validated"], plannedReadRequests: 4 };
    const deadline = now() + 60_000;
    const read = async (account, rpc, params) => {
      const timeoutMs = Math.min(REQUEST_TIMEOUT_MS, deadline - now());
      if (timeoutMs <= 0) fail("preflight_timeout");
      if (account.expiresAt <= now() + timeoutMs) fail("jwt_expiring");
      return transport({ target, jwt: account.jwt, rpc, params, timeoutMs });
    };
    // Authenticate both identities before attempting even a private inbox read.
    for (const account of accounts) {
      const profile = await read(account, "current_profile", {});
      if (!Array.isArray(profile) || profile.length !== 1 || profile[0]?.id !== account.accountID) fail("server_identity_mismatch");
      checks.push(`${account.label}.identity`);
    }
    for (const account of accounts) {
      const inbox = await read(account, "private_message_inbox", { input_limit: 1 });
      if (!object(inbox) || !Array.isArray(inbox.items) || !Object.hasOwn(inbox, "nextCursor")) fail("invalid_response");
      if (inbox.items.length !== 0 || inbox.nextCursor !== null) fail("preexisting_visible_messages");
      checks.push(`${account.label}.empty_visible_inbox`);
    }
    // Empty drafts and ineligible conversations are omitted by inbox; this is
    // deliberately not a privileged proof that the account pair has no thread.
    return { ...base, status: "pass", checks, conversationAbsenceVerified: false };
  } catch (error) {
    return { ...base, status: "blocked", checks,
      code: error instanceof VerificationError ? error.code : "verification_failed" };
  }
}

export async function runCLI(args, { stdin = process.stdin, stdout = process.stdout, transport = requestJSON, now = Date.now } = {}) {
  try {
    if (args.length === 1 && args[0] === "--help") {
      stdout.write("Usage: node scripts/rec636-real-client-verification.mjs --project-ref <confirmed-ref> [--preflight]\n"
        + "Default: offline dry-run. --preflight performs four read-only RPCs. --write is blocked.\n"
        + "Supply JSON on stdin: target {projectRef,url,publishableKey}, accounts [{label:A,accountID,jwt},{label:B,accountID,jwt}].\n"
        + "JWTs stay in memory. No credentials, environment values or files are discovered.\n"
        + "A passing preflight is not delivery, participant approval, empty-thread, cleanup or concurrency verification.\n");
      return 0;
    }
    let expectedProjectRef;
    let mode = "dry-run";
    for (let index = 0; index < args.length; index += 1) {
      if (args[index] === "--write") fail("cleanup_companion_required");
      if (args[index] === "--project-ref" && expectedProjectRef === undefined) expectedProjectRef = args[++index];
      else if (args[index] === "--preflight" && mode === "dry-run") mode = "preflight";
      else fail("invalid_arguments");
    }
    if (!/^[a-z0-9]{20}$/u.test(expectedProjectRef ?? "")) fail("invalid_target");
    const chunks = [];
    let bytes = 0;
    for await (const chunk of stdin) {
      bytes += Buffer.byteLength(chunk);
      if (bytes > MAX_INPUT_BYTES) fail("input_too_large");
      chunks.push(Buffer.from(chunk));
    }
    let input;
    try { input = JSON.parse(Buffer.concat(chunks).toString("utf8")); }
    catch { fail("invalid_input"); }
    const result = await verify(input, { expectedProjectRef, mode, transport, now });
    stdout.write(`${JSON.stringify(result)}\n`);
    return result.status === "pass" ? 0 : 2;
  } catch (error) {
    stdout.write(`${JSON.stringify({ status: "blocked", writesEnabled: false, step4Complete: false,
      code: error instanceof VerificationError ? error.code : "verification_failed" })}\n`);
    return 2;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  process.exitCode = await runCLI(process.argv.slice(2));
}
