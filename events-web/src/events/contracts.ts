// Shared wire v1. Decoders return a new whitelisted projection, never the raw transport object.
// Server commands remain authoritative; these checks detect incompatible or contradictory responses.
export class EventContractError extends Error {}
type Parser<T> = (value: unknown) => T;
type Shape = Record<string, Parser<unknown>>;
type Parsed<S extends Shape> = { [K in keyof S]: ReturnType<S[K]> };
function fail(message: string): never { throw new EventContractError(message); }
function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail("expected object");
  return value as Record<string, unknown>;
}
function object<S extends Shape>(shape: S): Parser<Parsed<S>> {
  return value => {
    const input = record(value);
    return Object.fromEntries(Object.entries(shape).map(([key, parse]) => [key, parse(input[key])])) as Parsed<S>;
  };
}
function choice<const T extends readonly string[]>(values: T): Parser<T[number]> {
  return value => typeof value === "string" && values.includes(value) ? value : fail("unsupported enum");
}
const string: Parser<string> = v => typeof v === "string" ? v : fail("expected string");
const nonempty: Parser<string> = v => { const s = string(v); return s.length && s.trim() === s ? s : fail("empty or padded value"); };
const boolean: Parser<boolean> = v => typeof v === "boolean" ? v : fail("expected boolean");
const number: Parser<number> = v => typeof v === "number" && Number.isFinite(v) ? v : fail("expected finite number");
const positiveInt: Parser<number> = v => { const n = number(v); return Number.isSafeInteger(n) && n > 0 ? n : fail("expected positive integer"); };
const nullable = <T>(parse: Parser<T>): Parser<T | null> => v => v === null ? null : parse(v);
const array = <T>(parse: Parser<T>): Parser<T[]> => v => Array.isArray(v) ? v.map(parse) : fail("expected array");
export type EventIdentifier<K extends string> = string & { readonly __eventIdentifier: K };
const id = <K extends string>(): Parser<EventIdentifier<K>> => v => nonempty(v) as EventIdentifier<K>;
export type EventID = EventIdentifier<"event">;
export type AccountID = EventIdentifier<"account">;
export type PlaceID = EventIdentifier<"place">;
export type BookingID = EventIdentifier<"booking">;
export type GenerationID = EventIdentifier<"generation">;
export type AdmissionID = EventIdentifier<"admission">;
export type CompletionID = EventIdentifier<"completion">;
export type VisitID = EventIdentifier<"visit">;
export type SourceID = EventIdentifier<"source">;
export type OperationID = EventIdentifier<"operation">;
export type OfferID = EventIdentifier<"offer">;
export type EventInstant = string & { readonly __utcInstant: true };
export const instant: Parser<EventInstant> = v => {
  const value = nonempty(v);
  if (!/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,6})?Z$/.test(value) || value.startsWith("0000")) fail("invalid UTC instant");
  const date = new Date(value);
  if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 19) !== value.slice(0, 19)) fail("invalid date");
  return value as EventInstant;
};
// Compare all six wire fractional digits without Date's millisecond truncation.
function micros(value: EventInstant): bigint {
  const [seconds, fraction = ""] = value.slice(0, -1).split(".");
  return BigInt(Date.parse(seconds + "Z")) * 1000n + BigInt(fraction.padEnd(6, "0"));
}
export const capabilities = ["submit_rsvp", "join_waitlist", "accept_offer", "cancel_rsvp", "view_guest_list", "manage_rsvp", "request_entry_credential", "complete_checkin", "view_recap"] as const;
export type EventCapability = typeof capabilities[number];
export const errorCodes = [
  "authentication_required", "session_expired", "account_mismatch", "permission_denied", "team_access_revoked",
  "phone_verification_required", "phone_challenge_invalid", "phone_challenge_expired", "name_required", "username_required", "username_unavailable",
  "event_unavailable", "event_access_denied", "registration_closed", "native_action_required",
  "existing_request", "capacity_unavailable", "code_required", "code_invalid", "code_disabled", "code_exhausted", "offer_expired", "offer_unavailable", "not_offer_owner", "cancellation_closed",
  "stale_revision", "operation_conflict", "capacity_commitments_conflict", "policy_resolution_required",
  "booking_ineligible", "roster_mismatch", "already_admitted", "reconciliation_conflict",
  "recap_unpublished", "admission_required", "completion_required", "source_removed", "asset_not_ready", "asset_access_denied", "completion_exists_post_deleted",
  "temporarily_unavailable", "rate_limited"
] as const;
const failure = object({ code: choice(errorCodes), retry_class: choice(["none", "authenticate", "refresh", "same_operation", "retry_later", "user_input"]) });
export type EventFailure = ReturnType<typeof failure>;
const profile = object({ has_name: boolean, has_username: boolean, phone_verified: boolean });
export type EventProfileReadiness = ReturnType<typeof profile>;
export function missingRSVPFields(p: EventProfileReadiness): string[] {
  return [...(p.has_name ? [] : ["name"]), ...(p.phone_verified ? [] : ["phone_verification"])];
}
export function missingEntryFields(p: EventProfileReadiness): string[] {
  return [...(p.has_name ? [] : ["name"]), ...(p.has_username ? [] : ["username"])];
}
const booking = object({
  booking_id: id<"booking">(), generation_id: id<"generation">(), revision: positiveInt,
  status: choice(["pending", "waitlisted", "offered", "confirmed", "canceled", "declined"]),
  offer: nullable(object({ offer_id: id<"offer">(), deadline: instant }))
});
export type EventBooking = ReturnType<typeof booking>;
const resolvedViewer = object({
  account_id: id<"account">(), booking: nullable(booking),
  admission: choice(["none", "valid", "revoked"]), completion: choice(["none", "completed"]),
  personal_post: choice(["absent", "present", "deleted"]), profile
});
export type EventViewer = { status: "unknown" } | { status: "failed"; failure: EventFailure } | { status: "resolved"; value: ReturnType<typeof resolvedViewer> };
const viewer: Parser<EventViewer> = v => {
  const input = record(v);
  switch (input.status) {
    case "unknown": return { status: "unknown" };
    case "failed": return { status: "failed", failure: failure(input.failure) };
    case "resolved": return { status: "resolved", value: resolvedViewer(input.value) };
    default: return fail("unsupported viewer state");
  }
};
const point = object({ latitude: number, longitude: number });
const publicVenue = object({ label: string, point });
const approximate = object({ label: string, area_center: point, radius_meters: number });
const exact = object({ address: string, point, access_valid_until: instant });
export type EventLocation = { kind: "hidden" } | { kind: "public_venue"; value: ReturnType<typeof publicVenue> } | { kind: "approximate"; value: ReturnType<typeof approximate> } | { kind: "authorized_exact"; value: ReturnType<typeof exact> };
const location: Parser<EventLocation> = v => {
  const input = record(v);
  switch (input.kind) {
    case "hidden": return { kind: "hidden" };
    case "public_venue": return { kind: "public_venue", value: publicVenue(input.value) };
    case "approximate": return { kind: "approximate", value: approximate(input.value) };
    case "authorized_exact": return { kind: "authorized_exact", value: exact(input.value) };
    default: return fail("unsupported location projection");
  }
};
const event = object({ event_id: id<"event">(), place_id: id<"place">(), revision: positiveInt, title: string, starts_at: instant, ends_at: instant, time_zone: nonempty });
const view = object({ event, viewer, capabilities: array(choice(capabilities)), location, recap: choice(["unpublished", "published_locked", "published_eligible"]), permission_version: nonempty });
export type EventView = ReturnType<typeof view>;
export type EventReadPayload = { status: "available"; view: EventView } | { status: "unavailable"; failure: EventFailure };
const payload: Parser<EventReadPayload> = v => {
  const input = record(v);
  switch (input.status) {
    case "available": return { status: "available", view: view(input.view) };
    case "unavailable": return { status: "unavailable", failure: failure(input.failure) };
    default: return fail("unsupported event read state");
  }
};
const response = object({ contract_version: positiveInt, event_id: id<"event">(), server_time: instant, payload });
export type EventReadResponse = ReturnType<typeof response>;

export function decodeEventRead(value: unknown): EventReadResponse {
  const result = response(value);
  if (result.contract_version !== 1) fail("unsupported version");
  if (result.payload.status === "unavailable") {
    if (!["event_unavailable", "event_access_denied", "permission_denied", "authentication_required", "session_expired", "temporarily_unavailable", "rate_limited"].includes(result.payload.failure.code)) fail("invalid unavailable reason");
    return result;
  }
  const v = result.payload.view;
  if (v.event.event_id !== result.event_id || micros(v.event.ends_at) <= micros(v.event.starts_at)) fail("event metadata");
  if (v.event.time_zone !== "UTC" && !/^[A-Za-z_]+(\/[A-Za-z0-9_+-]+)+$/.test(v.event.time_zone)) fail("expected IANA zone name");
  try { new Intl.DateTimeFormat("en", { timeZone: v.event.time_zone }); } catch { fail("invalid time zone"); }
  const rights = new Set(v.capabilities);
  if (rights.size !== v.capabilities.length) fail("duplicate rights");
  if (v.location.kind !== "hidden") {
    const p = v.location.kind === "approximate" ? v.location.value.area_center : v.location.value.point;
    if (Math.abs(p.latitude) > 90 || Math.abs(p.longitude) > 180) fail("invalid coordinate");
  }
  if (v.location.kind === "approximate" && v.location.value.radius_meters <= 0) fail("approximation radius");
  if (v.location.kind === "authorized_exact" && (v.viewer.status !== "resolved" || micros(v.location.value.access_valid_until) <= micros(result.server_time))) fail("unauthorized or expired exact location");
  if (v.viewer.status !== "resolved") {
    if (rights.size || v.recap === "published_eligible") fail("unresolved private rights");
    return result;
  }
  const viewer = v.viewer.value;
  const b = viewer.booking;
  if (b && (b.status === "offered") !== (b.offer !== null)) fail("booking offer state");
  if ((viewer.completion === "none") !== (viewer.personal_post === "absent")) fail("completion post state");
  if (b?.status !== "confirmed" && ["view_guest_list", "manage_rsvp", "cancel_rsvp", "request_entry_credential"].some(c => rights.has(c as EventCapability))) fail("confirmed guest rights without confirmation");
  if (rights.has("accept_offer") && (b?.status !== "offered" || !b.offer || micros(b.offer.deadline) <= micros(result.server_time))) fail("acceptance without current offer");
  if (rights.has("submit_rsvp") && b && !["canceled", "declined"].includes(b.status)) fail("new attempt with active booking");
  if (rights.has("request_entry_credential") && missingEntryFields(viewer.profile).length) fail("entry setup missing");
  const recapEligible = viewer.admission === "valid" && viewer.completion === "completed" && v.recap !== "unpublished";
  if ((v.recap === "published_eligible") !== recapEligible || (rights.has("view_recap") && !recapEligible)) fail("recap rights");
  if (rights.has("complete_checkin") && (viewer.admission !== "valid" || viewer.completion !== "none" || v.recap === "unpublished")) fail("completion eligibility");
  return result;
}

export interface EventRequestContext { event_id: EventID; account_id: AccountID | null; session_epoch: string }
export function acceptResponse(value: unknown, captured: EventRequestContext, current: EventRequestContext): EventReadResponse {
  if (captured.event_id !== current.event_id || captured.account_id !== current.account_id || captured.session_epoch !== current.session_epoch) fail("stale context");
  const result = decodeEventRead(value);
  if (result.event_id !== captured.event_id) fail("wrong event");
  if (result.payload.status === "available" && result.payload.view.viewer.status === "resolved" && result.payload.view.viewer.value.account_id !== captured.account_id) fail("wrong account");
  return result;
}
export type EventRequestState<T> = { status: "idle" } | { status: "loading"; context: EventRequestContext } | { status: "resolved"; value: T } | { status: "known_rejection"; error: EventFailure } | { status: "completion_unknown"; operation_id: OperationID; context: EventRequestContext };
export const operationKinds = ["submit_rsvp", "join_event_waitlist", "accept_offer", "decline_offer", "cancel_rsvp", "complete_event_checkin", "record_admission", "delete_event_post"] as const;
export type EventOperationKind = typeof operationKinds[number];
export interface EventCommand<P> { contract_version: 1; operation_id: OperationID; kind: EventOperationKind; event_id: EventID; target_generation_id: GenerationID | null; expected_revision: number | null; payload: P }
export function decodeCommand<P>(value: unknown, parsePayload: Parser<P>): EventCommand<P> {
  const c = object({ contract_version: positiveInt, operation_id: id<"operation">(), kind: choice(operationKinds), event_id: id<"event">(), target_generation_id: nullable(id<"generation">()), expected_revision: nullable(positiveInt), payload: parsePayload })(value);
  if (c.contract_version !== 1) fail("unsupported version");
  return { ...c, contract_version: 1 };
}
export interface EventCommandResult<E> { contract_version: 1; operation_id: OperationID; kind: EventOperationKind; outcome: "applied" | "already_applied" | "rejected"; effect: E | null; current_state: EventReadResponse; error: EventFailure | null }
export function decodeCommandResult<E, P>(value: unknown, parseEffect: Parser<E>, command: EventCommand<P>, captured: EventRequestContext, current: EventRequestContext): EventCommandResult<E> {
  const r = object({ contract_version: positiveInt, operation_id: id<"operation">(), kind: choice(operationKinds), outcome: choice(["applied", "already_applied", "rejected"]), effect: nullable(parseEffect), current_state: decodeEventRead, error: nullable(failure) })(value);
  if (r.contract_version !== 1 || r.operation_id !== command.operation_id || r.kind !== command.kind || r.current_state.event_id !== command.event_id || command.event_id !== captured.event_id) fail("uncorrelated result");
  acceptResponse(r.current_state, captured, current);
  if (r.outcome === "rejected" ? r.effect !== null || r.error === null : r.effect === null || r.error !== null) fail("command outcome envelope");
  if (r.outcome !== "rejected" && (r.current_state.payload.status !== "available" || r.current_state.payload.view.viewer.status !== "resolved")) fail("success without current authorized owner state");
  return { ...r, contract_version: 1 };
}
export interface EventPage<T> { items: T[]; next_cursor: string | null; has_more: boolean; permission_version: string }
export function decodePage<T>(value: unknown, parseItem: Parser<T>, limit: number): EventPage<T> {
  const page = object({ items: array(parseItem), next_cursor: nullable(nonempty), has_more: boolean, permission_version: nonempty })(value);
  if (!Number.isInteger(limit) || limit < 1 || limit > 100 || page.items.length > limit || page.has_more !== (page.next_cursor !== null)) fail("page boundary");
  return page;
}
export function nativeAction(surface: "app" | "clip" | "browser", installation: "installed" | "absent" | "unknown"): "show_native" | "open_app" | "offer_install" | "offer_open_or_install" {
  return surface === "app" ? "show_native" : installation === "installed" ? "open_app" : installation === "absent" ? "offer_install" : "offer_open_or_install";
}

export const decodeBookingEffect = object({ booking_id: id<"booking">(), generation_id: id<"generation">() });
export const decodeAdmissionEffect = object({ admission_id: id<"admission">(), booking_id: id<"booking">(), generation_id: id<"generation">() });
export const decodeCompletionEffect = object({ completion_id: id<"completion">(), visit_id: id<"visit">() });
// These are separate console/operational contracts, never guest permissions.
export const decodeConsoleAccess = choice(["team_admin", "denied", "revoked"]);
export const decodeOfflineAdmission = object({
  operation_id: id<"operation">(), acting_admin_id: id<"account">(), event_id: id<"event">(),
  booking_id: id<"booking">(), generation_id: id<"generation">(), roster_snapshot_id: nonempty,
  roster_version: positiveInt, local_recorded_at: instant,
  local_status: choice(["durable_pending", "syncing", "acknowledged", "conflict", "unknown"])
});
export function acceptOfflineAdmission(value: unknown, context: EventRequestContext): ReturnType<typeof decodeOfflineAdmission> {
  const operation = decodeOfflineAdmission(value);
  if (operation.event_id !== context.event_id || operation.acting_admin_id !== context.account_id) fail("offline operation scope");
  return operation;
}
export const decodeDeliveryStatus = choice(["queued", "claimed", "provider_accepted", "delivery_confirmed", "retryable_failure", "terminal_failure", "suppressed", "unknown"]);
// No free-form metadata: a future analytics adapter can forward only this projection.
export const decodeAnalyticsDimensions = object({ surface: choice(["app", "clip", "browser"]), action: choice(["view", "rsvp", "entry", "checkin", "recap"]), outcome: choice(["started", "succeeded", "rejected", "unknown"]) });
