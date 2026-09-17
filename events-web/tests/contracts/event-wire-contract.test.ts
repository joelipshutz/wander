import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { decodeEventRead, acceptResponse, missingRSVPFields, missingEntryFields, nativeAction, decodeCommand, decodeCommandResult, decodePage, decodeConsoleAccess, decodeDeliveryStatus, acceptOfflineAdmission, decodeBookingEffect, decodeAdmissionEffect, decodeCompletionEffect, decodeAnalyticsDimensions } from "../../src/events/contracts.ts";
import type { EventRequestContext, EventCommand, EventID, AccountID, OperationID, GenerationID } from "../../src/events/contracts.ts";

const fixtures = JSON.parse(readFileSync(new URL("../../../tests/fixtures/events/event-contracts.json", import.meta.url), "utf8"));
const fixture = (name: string) => structuredClone(fixtures.find((f: { name: string }) => f.name === name).response);
const view = (name: string) => { const r = decodeEventRead(fixture(name)); assert.equal(r.payload.status, "available"); if (r.payload.status !== "available") throw Error(); return r.payload.view; };
const context: EventRequestContext = { event_id: "evt_fixture_vinyl" as EventID, account_id: "acct_fixture_rachel" as AccountID, session_epoch: "epoch-1" };

assert.equal(fixtures.length, 61);
for (const f of fixtures) {
  test(`shared wire: ${f.name}`, () => {
    if (f.valid) {
      const decoded = decodeEventRead(f.response);
      assert.deepEqual(decodeEventRead(JSON.parse(JSON.stringify(decoded))), decoded);
    } else assert.throws(() => decodeEventRead(f.response));
  });
}
test("missing name reuses current verified phone", () => {
  const v = view("missing_name_verified_phone").viewer;
  assert.equal(v.status, "resolved");
  if (v.status !== "resolved") throw Error();
  assert.deepEqual(missingRSVPFields(v.value.profile), ["name"]);
  assert.deepEqual(missingEntryFields(v.value.profile), ["name"]);
});
test("confirmed management remains available in browser/Clip; installation only changes native action route", () => {
  assert.ok(view("confirmed").capabilities.includes("manage_rsvp"));
  assert.ok(view("confirmed").capabilities.includes("view_guest_list"));
  for (const surface of ["browser", "clip"] as const) {
    assert.equal(nativeAction(surface, "installed"), "open_app");
    assert.equal(nativeAction(surface, "unknown"), "offer_open_or_install");
    assert.equal(nativeAction(surface, "absent"), "offer_install");
  }
  assert.equal(nativeAction("app", "unknown"), "show_native");
});
test("account, event and same-account session replacement fences", () => {
  assert.doesNotThrow(() => acceptResponse(fixture("confirmed"), context, context));
  assert.throws(() => acceptResponse(fixture("different_account"), context, context));
  assert.throws(() => acceptResponse(fixture("confirmed"), context, { ...context, session_epoch: "epoch-2" }));
  assert.throws(() => acceptResponse(fixture("confirmed"), context, { ...context, account_id: null }));
  assert.throws(() => acceptResponse(fixture("confirmed"), { ...context, account_id: null }, { ...context, account_id: null }));
  const wrong = fixture("confirmed"); wrong.event_id = "evt_other"; wrong.payload.view.event.event_id = "evt_other";
  assert.throws(() => acceptResponse(wrong, context, context));
});
test("deleting post preserves completion; revoked admission still locks recap", () => {
  const deleted = view("completed_post_deleted");
  assert.ok(deleted.capabilities.includes("view_recap"));
  assert.ok(!deleted.capabilities.includes("complete_checkin"));
  assert.equal(view("completed_admission_revoked").recap, "published_locked");
  assert.ok(!view("completed_admission_revoked").capabilities.includes("view_recap"));
});
test("unknown fields are stripped at nested projection boundaries", () => {
  const raw = fixture("approximate_home");
  raw.payload.view.private_feedback = "MUST_NOT_SURVIVE";
  raw.payload.view.location.value.exact_address = "MUST_NOT_SURVIVE";
  assert.ok(!JSON.stringify(decodeEventRead(raw)).includes("MUST_NOT_SURVIVE"));
  const denied = fixture("event_access_denied"); denied.payload.view = raw.payload.view;
  assert.ok(!JSON.stringify(decodeEventRead(denied)).includes("Vinyl"));
});
test("old operation replay returns cancellation, cannot correlate to deliberate new generation", () => {
  const command: EventCommand<Record<string, never>> = { contract_version: 1, operation_id: "op_fixture_1" as OperationID, kind: "submit_rsvp", event_id: context.event_id, target_generation_id: "generation_fixture_1" as GenerationID, expected_revision: null, payload: {} };
  const raw = { contract_version: 1, operation_id: "op_fixture_1", kind: "submit_rsvp", outcome: "already_applied", effect: { booking_id: "booking_fixture_rachel" }, current_state: fixture("canceled"), error: null };
  const result = decodeCommandResult(raw, value => { assert.deepEqual(value, { booking_id: "booking_fixture_rachel" }); return value; }, command, context, context);
  assert.equal(result.current_state.payload.status, "available");
  if (result.current_state.payload.status !== "available") throw Error();
  assert.ok(result.current_state.payload.view.capabilities.includes("submit_rsvp"));
  assert.throws(() => decodeCommandResult(raw, v => v, { ...command, operation_id: "op_new_attempt" as OperationID }, context, context));
  assert.throws(() => decodeCommandResult({ ...raw, outcome: "rejected" }, v => v, command, context, context));
});
test("cursor and bounded page validation", () => {
  const raw = { items: ["guest1"], next_cursor: "opaque:scope:tie-breaker", has_more: true, permission_version: "v1" };
  assert.doesNotThrow(() => decodePage(raw, v => v, 10));
  assert.throws(() => decodePage(raw, v => v, 101));
  assert.throws(() => decodePage({ ...raw, has_more: false }, v => v, 10));
});

const pages = JSON.parse(readFileSync(new URL("../../../tests/fixtures/events/event-pages.json", import.meta.url), "utf8"));
for (const f of pages) {
  test(`shared page: ${f.name}`, () => {
    if (f.valid) assert.doesNotThrow(() => decodePage(f.page, v => v, f.limit));
    else assert.throws(() => decodePage(f.page, v => v, f.limit));
  });
}
test("operational states and minimal effects stay separate from guest permissions", () => {
  const f = JSON.parse(readFileSync(new URL("../../../tests/fixtures/events/event-operations.json", import.meta.url), "utf8"));
  assert.deepEqual(f.console_access.map(decodeConsoleAccess), ["team_admin", "denied", "revoked"]);
  assert.notEqual(f.delivery_statuses.map(decodeDeliveryStatus)[2], "delivery_confirmed");
  const operation = acceptOfflineAdmission(f.offline_operation, context);
  assert.equal(operation.local_status, "durable_pending");
  assert.throws(() => acceptOfflineAdmission(f.offline_operation, { ...context, account_id: "other" as AccountID }));
  assert.throws(() => acceptOfflineAdmission({ ...f.offline_operation, roster_version: 0 }, context));
  for (const local_status of f.offline_statuses) assert.doesNotThrow(() => acceptOfflineAdmission({ ...f.offline_operation, local_status }, context));
  assert.doesNotThrow(() => decodeBookingEffect(f.booking_effect));
  assert.doesNotThrow(() => decodeAdmissionEffect(f.admission_effect));
  assert.doesNotThrow(() => decodeCompletionEffect(f.completion_effect));
  assert.ok(!JSON.stringify(decodeAnalyticsDimensions(f.analytics)).includes("MUST_NOT_SURVIVE"));
});

const commands = JSON.parse(readFileSync(new URL("../../../tests/fixtures/events/event-commands.json", import.meta.url), "utf8"));
for (const f of commands) {
  test(`shared command: ${f.name}`, () => {
    const validate = () => {
      const command = decodeCommand(f.request, v => { assert.deepEqual(v, {}); return {}; });
      const raw = { ...f.result, current_state: fixture(f.current_state_fixture) };
      const decodeEffect = (v: unknown) => command.kind === "complete_event_checkin" ? decodeCompletionEffect(v) : decodeBookingEffect(v);
      const result = decodeCommandResult(raw, decodeEffect, command, context, context);
      const replay = decodeCommandResult(JSON.parse(JSON.stringify(result)), decodeEffect, decodeCommand(JSON.parse(JSON.stringify(command)), v => v), context, context);
      assert.deepEqual(replay, result);
      assert.ok(Object.hasOwn(command, "target_generation_id"));
      assert.ok(Object.hasOwn(command, "expected_revision"));
      assert.ok(Object.hasOwn(result, "effect"));
      assert.ok(Object.hasOwn(result, "error"));
    };
    if (f.valid) assert.doesNotThrow(validate);
    else assert.throws(validate);
  });
}
