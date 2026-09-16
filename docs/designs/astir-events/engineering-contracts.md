# Astir Events — shared engineering contracts

Updated September 15, 2026. **Planning handoff under engineering D19A; no production implementation or completed feasibility proof.** This is the minimum contract for the two implementation lanes to review together before building against it. All entity, field, RPC and error names below are **proposed implementation names**, not existing APIs or new product approvals. Implement inside Astir's existing Supabase/auth/history boundaries; no new platform is selected.

Authority: [engineering decisions](engineering-plan.md), [product specification](product-spec-draft.md), [acceptance scenarios](events-exit-criteria.md) and [test mapping](engineering-test-plan.md). Unprefixed D references in the product source are historical product decisions; engineering D1–D19 use separate numbering. Approved invariants are mandatory. Explicit `POLICY-GATED` clauses remain unapproved; do not turn a sample schema, wire fixture or UI into their default decision.

## 1. Contract conventions

| Item | Proposed wire rule |
| --- | --- |
| IDs | Opaque strings. `account_id` resolves to existing canonical Astir identity, not a new Events account. Event/place/booking/generation/operation/media IDs have distinct types in clients. |
| Time | UTC RFC3339 instants on the wire; event carries its IANA display time zone. Server time governs eligibility. Shared Swift/web fixtures cover timestamp precision and boundary equality. |
| Versions | `contract_version`, entity `revision`, and operation identity are separate. Revision detects stale edits; it never proves permission. Additive version changes must preserve old supported clients. Unknown enums fail safely, not as confirmed/public. |
| Authentication | Actor identity is derived from a verified server session/token and canonical identity mapping. Request-body IDs, phone/name strings, event links, UI role flags and `surface` never establish identity or Team admin membership. |
| Client fencing | Bind in-flight requests, drafts, caches and pending mutations to expected account/event. Check after auth refresh and response delivery; discard/segregate stale-account results. |
| Pagination | Server-bounded `limit`; opaque cursor with complete stable sort/tie-breaker and query scope. Return `items`, `next_cursor`, `has_more`, and relevant projection/version metadata. No full-list fetch prerequisite for detail. |
| Privacy | Separate projection types. Omit unavailable private fields at serialization; null/blur in a rendered screen is not an authorization boundary. No secrets, phone codes, exact private locations or private feedback in public logs/analytics. |
| Naming / physical schema | Tables may be split or combined during implementation if the identities, independent state axes, transactions and authorization below remain intact. No duplicate place, visit, auth or delivery authority. |

Proposed command/result envelope:

```text
Command<T> {
  contract_version, operation_id, event_id,
  target_generation_id?, expected_revision?, payload: T
}

CommandResult<T> {
  contract_version, operation_id, server_time,
  outcome: applied | already_applied | rejected,
  result: T?, current_state: authorized_state?,
  error: { code, retry_class, field_errors?, permitted_actions? }?
}

ClientRequestState<T> = idle | loading | resolved(T)
                      | known_rejection(error)
                      | completion_unknown(operation_id)
```

`completion_unknown` is a transport/local state, never a booking state. Timeout after a possible commit must retain the same operation identity and retrieve/retry its result. `already_applied` returns the historic operation effect **and current authorized state**, including later cancellation/deletion. An operation replay is not authorization to recreate its original state. A genuine rejection has no partial capacity, code, completion or notification effect.

Authorization and permitted projection are rechecked before disclosing even an already-applied result; a revoked admin cannot replay their way back into protected access. Idempotency key scope is authenticated actor + operation kind + `operation_id`; record the event/generation and canonical payload fingerprint. Same key/same command resolves the existing result; same key/different command returns `operation_conflict`. Server uniqueness/invariants additionally protect distinct concurrent operation IDs for the same logical effect. No indefinite reservation follows from merely creating an operation ID.

## 2. Minimal domain records and independent state axes

| Proposed record | Minimum responsibility / fields | Separation that must survive implementation |
| --- | --- | --- |
| `Event` | `event_id`, one existing `place_id`, title/content, start/end/time zone, current revision, event publication, registration close rule, capacity/approval/code configuration, map presentation settings | A place has zero/many events; an event has exactly one place. Moving a future event date retains event/booking identity. Event cancellation/venue/completed-event edits are POLICY-GATED. |
| `EventLocationPolicy` | Event/place association, public/approximate presentation, protected exact-location reference, reveal/expiry configuration, venue-consent evidence | Approximate discovery, event access and exact-home access differ. Do not duplicate the home address into unrestricted ordinary place projections. Consent is required; capture UI/procedure remains proposed. |
| `PhoneVerification` | Canonical account, normalized phone, verified-current status, verified time, trusted provider/provenance reference | A locally stored phone string is not proof. Provider adapter must validate provenance server-side. Exact provider/challenge storage/expiry mechanism needs proof. |
| `EventRequest` / `BookingGeneration` | Stable logical booking reference, generation/attempt identity, account/event, submitted time, state/revision, accepted code-eligibility reference, confirmation/cancellation facts | Rebooking is a new attempt/generation governed by current rules; old operations cannot change it. Physical row strategy is proposed. Pending/verification are not held capacity. |
| `InvitationCode` / `CodeAllocation` | Event association, enabled state, capped or unlimited limit; committed accepted-request eligibility; per-generation consumed/held/released allocation identity | Code allowance and event capacity are separate. Code value never authenticates a guest. Do not store plaintext code values in public projections/logs. |
| `Offer` | `offer_id`, recipient account/event/generation, deadline, state, held seat and required held code allowance, revision | Sent/opened is not confirmed. Offer generation and deadline identify the promise. Decline/expiry releases holds, not a second refund. |
| `Admission` | Canonical event/guest booking reference, valid-recorded status, first/last relevant operation and actor attribution | Admission creates neither a personal place visit nor historical completion. Detailed revocation/reentry procedure remains POLICY-GATED. |
| `OfflineRoster` / `OfflineAdmissionOperation` | Account/event snapshot/version, prepared time/completeness, minimal guest records; stable operation ID, target booking/generation, acting admin, snapshot, device-recorded time and local status | Downloaded snapshot is not current server truth. Local recorded time is review context, not eligibility proof. Queue never establishes server admission. |
| `RecapPublication` | Event, ready/published revision and timestamp, approved content/media/tag configuration | Event end does not publish a recap. Failed publication cannot enqueue a recap-ready invitation. |
| `EventCompletion` | Event/account, historical explicit-completion identity/time, canonical visit reference/status | Durable historical completion survives deletion of its personal post/visit; still needs valid admission for protected recap. |
| `EventPost` / canonical `PlaceVisit` | One event-linked visit, event/date presentation, optional note/photos/tags, ordinary audience semantics | One history, no second event-only visit writer. No event venue rating or overwrite of independent notes/ratings/audiences/save intent. |
| `EventPrivateFeedback` | Completion/account/event reference; nullable 1–5 stars and independently nullable comment | No default star; separate from public note, tags, post and venue rating. Public/attendee projections never receive it. Exact later edit/retention procedure remains proposed. |
| `EventMediaSource` / `PostMediaReference` | Event, source asset identity/version/owner, lifecycle; selected post references and derivatives | Gallery source removal invalidates all Astir references/derivatives without deleting remaining posts/visits. Public selected photo does not expose the gallery. |
| `MessageIntent` / `DeliveryAttempt` | Logical trigger/event revision, recipient/channel, due/config version, eligibility provenance, state; individual provider attempts/acknowledgements | Committed business fact, logical message, channel attempt, provider acceptance and confirmed delivery are distinct. One shared messaging foundation. |

Entity names do not settle one-person/plus-one, quota-edit, map precedence or withdrawal policies that remain proposed. Enforce the approved one-logical-RSVP/retry behavior without deleting history or silently adopting unrelated restrictions.

## 3. Canonical link, identity and authoritative view

One `View event` link identifies the event across invitation, confirmation, reminders and sharing. Campaign attribution or an optional separate invitation code changes neither recipient identity nor event ID. Actual platform routing selects app/Clip/browser; a failed invocation cannot prove app absence.

```text
canonical event link / Events card
                 |
       permitted event projection
                 |
       valid canonical session?
       / no                 \ yes
identity unknown          booking lookup
recover same account        |
       \             success / failure
        \              |         |
         ---------- actual state  retry/unknown; never "no RSVP"
                       |
 none | pending | waitlisted | offered | confirmed | canceled/declined
```

Proposed `event_view(event_id)` returns:

```text
EventView {
  event: permitted metadata + revision + phase,
  identity: anonymous | recognized,
  viewer_state: unknown | { booking: BookingView | none,
                            admission: none | valid | revoked,
                            completion: none | completed,
                            personal_post: absent | present | deleted },
  capabilities: permitted actions with reasons,
  location: ApproximateLocation | AuthorizedExactLocation,
  recap: unpublished | published_locked | published_eligible,
  server_time, permission_version, access_valid_until?
}
```

Only a **successful authenticated lookup** can return `booking: none`. Network failure must not become a success with empty state. Capabilities aid rendering; each command rechecks permission and current state. A recognized confirmed guest receives guest-list and RSVP-management capability in **all three surfaces**. Native-only QR/check-in/upload actions remain distinguished from a download upsell that can be dismissed before entry.

`surface` and `app_installed` are client routing hints, not trusted permission flags. The full-app entry requirement needs the actual native route/credential handling and staff app/account checks. A shared bearer session does not itself prove installation. Do not invent `installed=true` as a server security claim or silently choose a new attestation platform; document/prove the native/door mechanism in the foundation gate.

Phone adapter operations (names proposed): `start_phone_challenge(phone)` → challenge reference/provider-controlled resend information; `verify_phone_challenge(challenge_id, code)` → server-confirmed proof for this account/current number. Authentication remains Apple/Google, not phone-only signup. Reuse authoritative matching proof; changing a number requires verification. Starting/challenging/verifying holds no seat. Recovery preserves an existing confirmation or valid offer without extending its deadline. Exact SMS resend countdown, proof refresh lifecycle and phone-change delivery-retargeting mechanics require the selected provider contract.

Entry setup reads canonical profile state and requires missing valid **name and username** before QR; photo remains optional. Do not add a general tour/location/contacts/notification gate. Use original-account sign-in/help for recovery; do not claim by name/phone/link, silently merge providers or manufacture a replacement RSVP. Actual Clerk App Clip Apple/Google support, session transfer/browser return and install-from-icon recovery remain proof tasks.

## 4. Booking, offer and code state machines

```text
new attempt -- authenticate/name + verified phone + submit --> evaluate now
   no seat/allowance held                                /       |       \
                                    available automatic    manual      full/protected
                                               |              |              |
                                           CONFIRMED       PENDING    offer join-waitlist
                                                              |          (explicit choice)
                           available unprotected quota/seat + approve       |
                                                              |         WAITLISTED
                                                         CONFIRMED          |
                                                            staff select + issue offer
                                                                            |
                                                            OFFERED (seat + code holds)
                                                         /        |           \
                                          valid owner accepts   decline       expiry
                                                 |             release        release
                                             CONFIRMED          holds          holds
                                                 |
                                     self-cancel before current start
                                                 |
                                             CANCELED
                                                 |
                             deliberate rebooking = new attempt/generation
```

The full/manual case returns actual allowed actions; it does not auto-enroll anyone in a waitlist. Approval with no unprotected capacity leaves the request pending. State after declined/expired offer, pending→waitlist movement, request withdrawal/rejection presentation and reselection mechanics remain POLICY-GATED; preserve the terminal offer facts without pretending a promotion or new confirmation occurred.

```text
code allowance: available -- issue valid offer --> HELD
                   |                              /   \
              confirm directly             accept     decline/expire
                   |                          |           |
                CONSUMED <--------------------+       available
                   |
             successful confirmed cancellation, once
                   |
                available
```

For capped codes, `consumed + active unexpired held <= cap`. For event capacity, `confirmed + active unexpired offers <= capacity`. Unlimited code allowance does not bypass capacity/approval/verification. Pending/waitlisted submissions consume and hold nothing unless an offer is actually issued. Failed commands change neither limit.

D12 code deactivation blocks **new submissions**, while already committed, account-bound, verified requests retain recorded code eligibility. Typing/prechecking a code is not submission. Existing confirmations and valid offers survive. Canceled guest rebooking is new and cannot inherit the old exception. Deactivation/submission races are settled by the authoritative transaction ordering.

Required transaction invariants:

1. Coordinate event capacity, required code allowance and target generation in consistent lock order; serialize competing event allocations. No provider/media calls, full-list rendering or user interaction inside a lock.
2. After obtaining the relevant lock, check a fresh server clock for offer expiry, registration close and self-cancel start boundaries. Transaction-start time must not permit an expired action after a lock wait.
3. Successful acceptance converts existing holds; it does not consume another seat. Check replay/current booking before returning misleading expiry for an already successful acceptance. Never revive later cancellation.
4. Expired unaccepted holds stop counting even if cleanup is late. Release/refund identities prevent double release. D31 protects released capacity for staff waitlist selection; no automatic promotion.
5. Reject capacity reduction below current confirmations plus active holds. An offer's original deadline cannot be silently shortened/extended by a reschedule or configuration edit.
6. New online RSVP closes at event end by default or an earlier console close. Starting verification before close grants no later booking. Existing committed attempts resolve truthfully after close. Self-cancellation still closes at event start.
7. Future reschedule keeps booking, allocation and canonical link, increments event revision, recomputes relative windows and invalidates obsolete reminder work. Failed edit emits no notice; repeated same revision emits no duplicate logical notice.

Proposed operations:

| Operation / actor | Inputs beyond common envelope | Success / expected rejection |
| --- | --- | --- |
| `submit_rsvp` / guest | Current attempt reference if recovering; required code if applicable; event-text disclosure version metadata (recorded with submission; no extra required checkbox/action) and separate optional future-marketing choice | Current confirmed/pending state, or capacity/full response with permitted waitlist action; never false success. `phone_verification_required`, `code_required/invalid/disabled`, `code_exhausted` when confirmation needs allowance (pending itself consumes none), `registration_closed`, `capacity_unavailable`, `existing_request` with actual state. |
| `join_event_waitlist` / guest | Explicit intent and current request context | Account-bound waitlist state, no seat/code use. `registration_closed` / ineligible / existing state as applicable. Exact withdrawal lifecycle remains proposed. |
| `approve_request` / Team admin | Target request/generation/revision | One confirmation; no capacity → unchanged pending plus `capacity_unavailable`; no hidden waitlist move. |
| `issue_offer` / Team admin | Target waitlist request/generation, configured duration/deadline input | One offer with seat and required code holds, deadline; unavailable limit → no offer. Conflict with registration cutoff/issued promise → explicit `policy_resolution_required`, not a silently invented rule. |
| `accept_offer` / guest owner | Offer ID/generation/revision | Confirmation from existing holds or current replay result; `offer_expired`, `offer_unavailable`, `not_offer_owner`, `phone_verification_required` if actual proof needed. |
| `decline_offer` / guest owner | Offer ID/generation | Terminal offer fact + release holds; resulting waitlist presentation follows later reviewed policy. |
| `cancel_rsvp` / guest owner | Target confirmed generation/revision | Canceled generation + once-only seat/code release; `cancellation_closed`, stale target/current state, or known failure with unchanged allocation. |
| `set_capacity`, `set_code_enabled` / Team admin | Expected config revision and requested value | Approved constraint-preserving update; `capacity_commitments_conflict` or validation failure. |
| `reschedule_upcoming_event` / Team admin | Expected event revision, future start/end/time zone | Same event/bookings + new revision + delivery intents; detect issued-offer conflicts. Event-wide cancellation/venue/completed edits are not bundled here. |

Exact code-placement UI, approval-mode editing effects, quota reductions, issued-deadline changes and new-offer bounding remain in the policy gate list. This table does not implement them via a fallback default.

## 5. Admission and offline reconciliation

```text
online valid QR / verified manual lookup / authorized missed-scan correction
                         |
                canonical server admission (unique event + guest)
                         |
                  eligible for explicit check-in
                         |
        historical completion + still-valid admission + recap published
                         |
                    protected recap

prepared roster -> local durable operation -> AWAITING_SYNC
                                               |
                          current server auth/booking/event validation
                                /              |                \
                             accepted       duplicate        conflict/denied/unknown
                                \              /                 |
                              canonical admission        retain unresolved; no recap
```

Proposed `entry_credential(event_id)` returns a server-issued opaque/signed credential referencing the correct event/booking/generation and an explicit validity/version contract. Do not embed phone, exact home location, feedback or identity tokens. Possessing it never signs in as the guest or establishes recap completion. Credential format, rotation/lifetime and native delivery proof are engineering design/validation, not selected policy here. Current cancellation/generation state must be checked online; a static old QR cannot restore eligibility.

`record_admission` (Team admin): `{credential? | target_booking_generation, method: scan|verified_manual|correction, operation_id}` → `{admission_id, canonical_status, duplicate?, authorized_current_state}`. Enforce current Team admin, correct event/account/booking and required entry checks; manual fallback is not an unsupported-device exception. Repeated scans return previous admission. No visit/completion/post side effect.

`prepare_roster(event_id, cursor?)` returns `{snapshot_id, version, prepared_at, completeness_manifest, page, permitted_minimal_guest_records}`. Stage pages, then atomically mark ready only after complete download/persistence. Never expose unrelated private feedback/gallery/exact private venue data. Failed refresh retains prior complete snapshot. Snapshot consistency and browser persistence must be proven; do not keep a DB transaction open across browser page fetches.

Local `OfflineAdmissionOperation`:

```text
{ operation_id, account_scope, acting_admin_id, event_id,
  booking_id, generation_id, roster_snapshot_id, roster_version,
  local_recorded_at, entry_method, local_status }

local_status = durable_pending | syncing | acknowledged | conflict | unknown
```

Persist first, then show **Admitted offline · awaiting sync**. Device clock is contextual. Duplicate locally decoded scans reuse the same logical result; disconnected devices cannot share real-time totals. No prepared match/no established identity → no invented booking or offline RSVP. Missing/evicted storage means offline unavailable, not empty-and-synced.

`reconcile_admissions(snapshot_id, operations[])` (currently authorized Team admin) returns a **bounded per-item** result array with operation ID and `accepted|already_recorded|conflict|denied`, canonical admission reference where allowed, typed reason and server time. A lost/partial response leaves unacknowledged operations unknown; retry identical IDs. Server current event/booking/admin state governs, even if roster/client time says otherwise. Verify that the submitted snapshot and recorded actor belong to the authenticated preparation context; client-supplied `acting_admin_id` is not proof. Another admin resolving a rejected queue follows an explicit attributed resolution operation, not silent reassignment. Do not clear the entire batch on HTTP success. No invalid row can revive a canceled booking or grant recap access. Separate row failure from fatal batch authentication/malformed-request errors.

Sign-out/account switch locks/removes protected roster access and makes unsynced work explicit before destructive cleanup. Remote revocation cannot instantly affect a fully disconnected device; recheck upon reconnection. An authorized-resolution workflow must preserve original actor attribution and unresolved rows; exact transfer/reentry/revocation procedure and retention period remain proposed.

## 6. Projection and authorization matrix

All writes use server-verified actor identity; Team admin membership is current backend membership, with one role covering the entire Events console. No per-event staff split. Each RPC/table/storage route must have explicit grants/RLS or narrowly justified definer logic, pinned search path and metadata tests. Service worker claim/settlement APIs are not public guest/admin RPCs. Client capability flags never replace these checks.

| Projection / operation | Allowed viewer / gate | Explicit omissions and expiry behavior |
| --- | --- | --- |
| Event invite/detail preview | Viewer permitted for that published event; anonymous invitation-safe projection where defined | No account/booking inference, guest phone list, unreadable comments payload, protected gallery or exact home fields. Anonymous social-preview/face-pile item policy remains unresolved; omit unapproved fields, do not redefine Astir-member visibility. |
| Viewer booking | Authenticated canonical owner; Team admin through separate console projection | A shared link cannot expose another account's booking. No-match only after successful lookup. |
| Full guest list / RSVP management | Recognized confirmed guest in app/Clip/web; existing profile/block restrictions | Pending/waitlist/offer is insufficient. Phones and private feedback never belong in guest projection. |
| Entry credential | Confirmed owner, valid required name/username, intended full-app route; trusted native/door proof must be demonstrated | Photo optional. No browser-only admission exception or client-installed flag as authority. |
| Approximate home display | Permitted event/place viewer | No exact center/coordinates/address/nav hidden in metadata, image EXIF, public cache, share/calendar or ordinary place query. Approximation shape is still design work. |
| Exact home details | Confirmed booking during per-event reveal/expiry window, or separately established independent place right; Team admin operational access is separate | Default reveal start−24h and expiry end+24h, configurable. Evaluate each current right independently; cancellation/expiry removes booking-derived access. Previously seen/exported information cannot be recalled. |
| Recap invitation/check-in eligibility | Published recap + valid canonical server admission | RSVP/no-show/self-report/offline queued entry insufficient. Invitation does not itself unlock full gallery. |
| Protected recap/comments/gallery bytes | Published recap + valid server admission + historical completion for this event | Personal post deletion does not remove completion. Existing restrictions/source removal still apply. No readable protected comments behind blur. |
| Selected photo in personal post | Existing post audience and restrictions; live permitted source reference | Permission covers that selected item only. Default is everyone **in Astir**, not invented anonymous public-web access. |
| Private feedback / console records | Current Team admin; narrow authenticated write path for the submitting attendee | No guest/recap/profile/feed/map/message projection receives feedback. Later author-read/edit behavior must follow reviewed procedure. |
| Map event projection | Permitted event/location + configured styling/filter rules | Featured general permitted discovery; You valid own attendance; Friends permitted friend attendance. RSVP is not attendance. Second-degree expansion, default window and multi-event precedence remain proposed. |

Home exact data and protected media require account/event/permission/source-version-scoped caches. Revalidate when entitlement is uncertain; denied refresh cannot fall back to stale private bytes/URLs. Enforce direct byte and video range access, not metadata only. The current signed-URL/cache path is not sufficient proof of immediate source-removal/expiry behavior. Use the existing account-bound download boundary and validate how derivatives and caches are invalidated before adopting a concrete storage route.

## 7. Publication, completion, canonical history and media

```text
recap unpublished -- successful authorized publication --> published revision
                       |                                  |
                 failed = unchanged                  invitation intent

valid server admission + published recap + explicit guest submit
                       |
          one atomic historical completion + one canonical event visit
                       |
          post present ------------------- owner deletes post/visit
                       |                              |
             protected recap                  historical completion retained
                                                   (recap still requires valid admission)
```

Proposed operations:

| Operation / actor | Input / result contract | Invariant |
| --- | --- | --- |
| `publish_event_recap` / Team admin | Expected event/recap revision, ready content/media/tag references → published revision + logical invitation intent(s) | No publication success or invite before durable ready content. Repeat revision is idempotent. Exact draft/publish editor procedure is P19/P14 proposed. |
| `complete_event_checkin` / eligible guest, full app | `operation_id`, optional public note, own-ready-photo references, optional event tags, independently nullable private stars/comment → `completion_id`, one canonical `visit_id`, post state, authoritative access/history result | All optional fields empty is valid. No public rating field/default and no private stars→venue rating mapping. Server validates current admission/publication and owned assets. |
| `attach_gallery_photos_to_post` / eligible completed guest | Existing visit/post + expected revision + live selected source-photo IDs → updated same visit/post | No second check-in/visit and no reuse explainer/approval step. Exact editing layout remains proposed. |
| `add_event_gallery_media` / eligible completed attendee or Team admin | Staged ready photo/video source + event → live gallery source | Successful eligible attendee upload appears without Astir preapproval; no public gallery opening. Own-video in the personal composer remains unapproved. |
| `remove_event_media_source` / source uploader or Team admin | Source ID/version → removed source/version + invalidation work | Remove source from all Astir references and generated derivatives, preserving unrelated note/media/visit/rating. No cross-event/source authorization bypass. |
| `delete_event_post` / owner | Target post/visit + expected revision → deleted post/visit and retained completion/admission state | Preserve independent visits, ratings, notes, audiences and explicit save intent; don't revoke valid historical recap completion. |

Upload bytes can be staged outside the transaction; completion/publication atomically references only validated ready assets. A failed selected upload cannot be silently omitted while announcing success. P06 retry-versus-explicit-omission interactions remain proposed. Blob storage is not transactionally rolled back by PostgreSQL: staging, orphan cleanup and permission-safe publication/deletion must be validated, never represented as already atomic across systems.

**Fresh main compatibility:** the handoff baseline is now `f8493c0` (inspected read-only), including REC-494 display grouping and REC-498 profile-header presentation. `Wander/Services/FeedModels.swift:110–121` describes `FeedActivityGroup` as display-only and retains original activity IDs; `:216–219` keeps a second `.placeBeen` in a separate group, with coverage at `WanderTests/FeedModelsTests.swift:27–35`. Event completion must preserve its original canonical visit/activity ID through this grouped presentation. Group/container IDs must never replace the activity target for likes, comments, share, notification links or deletion. Grouping does not merge distinct visits, create another event record or change permissions. This drift adds no backend/schema/auth contract change.

Completion result is the sole input to the full-app canonical-history adapter. Never call the ordinary place save/check-in a second time to “mark Been.” Preserve the existing visit/feed engagement identity and historical conversations. The generic parent-upsert rating/audience behavior must not overwrite independent history. Private feedback uses its own input/storage/projection, not ordinary `PlaceRating` defaults.

Lost successful completion response resolves its existing completion/visit. After later personal-post deletion, retry returns historical completion plus deleted-post state; it cannot recreate the post or force another check-in. A new-post-after-deletion interaction, post editing and private-feedback editing need the reviewed P07 behavior before exposing those actions.

Source deletion first removes authorization/readability across all in-app references; cleanup of stored derivatives cannot leave a publicly reusable live bypass. Already exported external copies are not controllable. Preserve nonremoved assets and post/visit identity. Precise physical deletion/cache invalidation mechanics are implementation proof tasks, not grounds to weaken D32.

## 8. Shared message outbox and dispatch contract

Business transaction commits its small logical intent with the booking/publication/change, not an external SMS request. Event-wide publication may use a durable fan-out intent processed in bounded pages; recipient expansion must be idempotent and recheck current rights. Exactly-once logical intent does not imply exactly-once physical external delivery.

```text
committed business fact -> durable logical intent -> due/eligible recipient work
                                                       |
                                                  lease/claim
                                                       |
                                              provider submission
                                            /       |        \
                                    accepted     unknown     known failure
                                       |            |             |
                              delivered if proven  reconcile    selected retry/terminal

canceled/stale revision/unauthorized/opted-out work -> appropriate suppressed state
(no fabricated "delivered", read, attendance or confirmation)
```

Proposed `MessageIntent` fields: logical trigger type/ID, event/current schedule revision, recipient account, channel, verified phone reference or push token scope, due time, selected template/config revision, consent/eligibility references, dedupe identity and state. Keep provider secrets/phone numbers out of guest metadata and analytics. Dedupe identity follows logical trigger + recipient + channel + applicable event/content revision; reminder reschedule handling must not accidentally replay old/already-sent reminders.

| Trigger | Approved eligibility / timing | Not silently decided |
| --- | --- | --- |
| Confirmed RSVP | After actual confirmation, SMS to verified event phone; no installation requirement | Provider retries, stale phone retargeting details |
| Preparation reminder | 24h and 2h before current event start, confirmed eligible guest | Exact late-RSVP skip rule, push cadence/fallback |
| Important change | Successful relevant published change; D13 reschedule retains RSVPs and includes current management route | Which other edits count, event-wide cancellation program |
| Recap invitation | Successful recap publication and valid server admission; check-in still required for full recap | Exact late-correction send procedure/additional push policy |
| Pending/waitlist/offer updates | Truthful configured state-specific message; offer open ≠ acceptance | Additional cadence/templates not already selected |
| Future-event marketing | Separate affirmative opt-in, unchecked by default | Broader marketing program not part of this contract |

`claim_message_work(limit, time_budget)` and `settle_delivery(claim_token, item_results[])` are service-only. Bounded processing, fresh eligibility/revision checks, per-item settlement and stale-claim fencing. Distinguish `queued`, `claimed`, `provider_accepted`, `delivery_confirmed`, `retryable_failure`, `terminal_failure`, `suppressed`, `unknown`; exact enum naming and channel mappings are proposed. Provider acceptance never means read/attended. Duplicate/out-of-order callbacks must authenticate and bind to actual provider message IDs; selected provider capability remains unproven.

A provider accepted request with lost acknowledgement/DB settlement stays recoverably unknown under that provider's idempotency/status contract; do not blindly create a new message. Failed push does not produce an extra SMS if planned SMS already exists or override opt-out. Future-marketing preference must not suppress event updates. Exact event-SMS opt-out/retry/push fallback mechanics remain P10/protocol review, not defaults selected here.

Current push scheduling/claim limits and row/token fan-out need the bounded-drain changes and measurements proposed in [performance review](performance-review/backend-door.md). This contract does not select a second worker platform or promise unmeasured delivery time.

## 9. Typed failure and recovery catalog

Codes below are proposed stable machine outcomes; clients never parse human text for business state. Return only details the caller is allowed to know. Use HTTP authentication/authorization meanings without collapsing all signed-in denial into signed-out; expected domain outcomes stay typed across Swift/web and fakes.

| Category | Proposed codes | Recovery rule |
| --- | --- | --- |
| Identity | `authentication_required`, `session_expired`, `account_mismatch`, `permission_denied`, `team_access_revoked` | Recover original account; preserve event/unknown operation; don't merge or claim by phone. No private lookup detail for unauthorized caller. |
| Phone/setup | `phone_verification_required`, `phone_challenge_invalid`, `phone_challenge_expired`, `name_required`, `username_required`, `username_unavailable` | Recover actual fields/proof; no new seat hold or photo gate. Provider retry timing comes from selected contract. |
| Event access | `event_unavailable`, `event_access_denied`, `registration_closed`, `native_action_required` | Permitted context only; native routing requirement is not proof of installation from a client flag. |
| Booking/code/offer | `existing_request`, `capacity_unavailable`, `code_required`, `code_invalid`, `code_disabled`, `code_exhausted`, `offer_expired`, `offer_unavailable`, `not_offer_owner`, `cancellation_closed` | Return authorized current state and explicit permitted action; no forced waitlist join, duplicate booking or invented confirmation. |
| Conflict | `stale_revision`, `operation_conflict`, `capacity_commitments_conflict`, `policy_resolution_required` | Refresh/review original command. An unapproved consequential change is not auto-resolved by a default. |
| Admission/offline | `booking_ineligible`, `roster_mismatch`, `already_admitted`, `reconciliation_conflict` | No false canonical admission. Preserve individual unresolved operations; help/correction separate from valid fallback. |
| Content | `recap_unpublished`, `admission_required`, `completion_required`, `source_removed`, `asset_not_ready`, `asset_access_denied`, `completion_exists_post_deleted` | Preserve optional drafts/history; never fetch hidden data or create another visit to recover. |
| Infrastructure | `temporarily_unavailable`, `rate_limited`, plus transport `completion_unknown` | Bounded retry/status recovery according to known commit status. No conversion to “none”, success or delivered. |

## 10. Handoff gates, fixtures and remaining blockers

**Build against these approved invariants first:** same canonical event/account; server-trusted phone proof; distinct booking/admission/completion; generation-safe mutations; event/code transactional accounting; no-install confirmed management; full-app entry/setup; one visit with independent history preserved; account-scoped protected data; one Team admin; durable pending offline reconciliation; publication-driven delivery. Shared fixtures must exercise each state/error before lanes diverge.

Minimum language-neutral fixtures: anonymous/unknown versus successful no-booking; pending/waitlist/valid+expired offer/confirmed/canceled; missing name/username versus skipped photo; another account; admitted-uncompleted; completed-post-present/deleted; public venue/private home before/at/after reveal+expiry; independent place rights/history; active/revoked admin; offline valid/stale/conflicting/unknown batches; failed/unknown message delivery. Include stable IDs, controlled clocks, revisions, sample result envelopes and expected permissions. Compare Swift/web decoding with the same fixtures, then replace stubs with API-backed integration. See the 121-case mapping; fixture completeness is not runtime proof.

| Gate / owner | Concrete unresolved work | Effect on handoff |
| --- | --- | --- |
| **G1 — Identity/entry foundation** | Actual Clerk Apple/Google in Clip and browser, canonical phone verification provenance, session transfer/original-account recovery, install-from-icon link return and native QR/app proof | Must demonstrate with actual SDK/build/devices before declaring the entry contract implemented. A failure requires a concrete alternative review; no phone-only signup/early forced download workaround. |
| **G2 — Data/media foundation** | Final RPC/schema/RLS/grants, existing ordinary place projection protection for homes, source/derivative byte authorization including video/range, completion→canonical-history integration | Must pass isolated integration and legacy regression. Signed URL expiry/client blur alone cannot satisfy the contract. |
| **G3 — Door/browser foundation** | Complete snapshot/version mechanism, real-browser durable queue/eviction/account-switch handling and authorized unresolved-operation recovery | Must demonstrate on intended staff devices; exact retention/reentry/revocation procedure remains proposed. |
| **G4 — Messaging foundation** | Provider selection/proof, status/idempotency/callback semantics, fake-transport reliability tests, burst measurements and delivery objective | Confirmed SMS program exists in approved scope; existing push worker is not proof. Provider/quiet/fallback/retry decisions cannot be inferred from this contract. |
| **G5 — Consolidated product/design review** | P02 resend; P03 copy; P04/P11 existing-mode/offer/cutoff/quota/waitlist edits; P05 cancellation/venue/completed edits; P09/P19 publish procedure; P10 late/push/opt-out/fallback; P15 reentry/revocation; P18 other code changes; P20 calendar/share payload; preview item/anonymous social exposure; multi-event map precedence/default window and second-degree scope; P06/P07 media/edit recovery | Keep conditional actions unimplemented/unsupported or clearly flagged in development until selected; do not silently cut approved full scope or ship an invented policy. Routine mechanical choices need no separate product poll. |
| **G6 — Joined release** | Compatible app/Clip/web/console/backend builds, actual App Store prerequisite/public invocation, linked authoritative E01–E12 results, performance/rollback evidence | No implementation or release is authorized by this planning artifact; parent handoff owns assignments and rollout gates. |

Historical reconnection and expanded privacy controls remain deferred. Own-video in personal check-in, extra Friends scope, separate event bookmark and unselected map styling do not become implemented features through a schema example. Shared-gallery video and the approved complete journey remain in scope.
