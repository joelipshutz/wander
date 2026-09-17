# Astir Events — planned test mapping

**Planning only. No listed Events test has been implemented, executed or passed by this review.**

121/121 acceptance IDs mapped, plus 24 technical risk cases. Mapping completeness is not measured code or runtime coverage.

The source authority trace is retained verbatim. Proposed clauses remain unapproved; planned test paths do not yet exist unless explicitly identified as adjacent existing evidence.

## L01 — Full app installed, recognized confirmed guest; open the canonical link from each listed source.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, full-app XCUITest, controlled-service integration, physical-device integration. Real-device evidence required: yes.

Planned files: `WanderTests/Events/EventLinkRoutingTests.swift`, `WanderUITests/Events/EventLinkEntryUITests.swift`, `docs/testing/astir-events-device-entry.md`.

- Parameterize original invitation, confirmation, reminder, shared link and event-notification sources against the same canonical Event A link; cover cold launch and foreground app.
- A validated confirmed identity opens Event A in the installed app with the original booking ID; no RSVP mutation or Clip/browser detour is initiated.
- Delay session validation and booking retrieval independently; event intent survives, protected state waits, and the final account/event matches the request.
- Exercise actual link taps and delivery surfaces on the intended TestFlight and public distributions separately; record the observed host, build and booking ID. A launch argument is not invocation proof.

Source authority: N1-LINK; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/WanderWidgetIntegrationTests.swift:103` — Adjacent evidence only; not Events coverage. Quick-capture intent waits for session validation and only the matching request is consumed.
- `WanderTests/BuildConfigurationTests.swift:126` — Adjacent evidence only; not Events coverage. Static full-app associated-domain assertions; does not prove hosted AASA, Clip invocation or distribution.

## L02 — No full app, valid recognized Clip session and confirmed RSVP; open each source's link.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, App Clip XCUITest, controlled-service integration, physical-device integration. Real-device evidence required: yes.

Planned files: `WanderTests/Events/EventEntryStateTests.swift`, `AstirEventsClipUITests/EventEntryUITests.swift`, `docs/testing/astir-events-device-entry.md`.

- For each of the five L01 origins with no full app installed, a valid recognized Clip session resolves its existing confirmed booking for Event A.
- Guest list and View or change RSVP remain usable in the Clip; detail has no full-app tabs or required download transition.
- Reopen the Clip after dismissal and a process restart; resolve current server booking instead of trusting a stale confirmation snapshot.
- On physical devices, prove real hosted Clip invocation and recognized-session continuity; simulator fixtures and the full-app Apple entitlement test cannot satisfy this result.

Source authority: N1-LINK, N1-DETAIL, C-NOAPP; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/WanderWidgetIntegrationTests.swift:103` — Adjacent evidence only; not Events coverage. Quick-capture intent waits for session validation and only the matching request is consumed.
- `WanderTests/BuildConfigurationTests.swift:126` — Adjacent evidence only; not Events coverage. Static full-app associated-domain assertions; does not prove hosted AASA, Clip invocation or distribution.

## L03 — No full app and Clip fails; recognized browser guest is confirmed; open each link source.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: guest-web Playwright, controlled-service integration, physical-device integration. Real-device evidence required: yes.

Planned files: `events-web/tests/guest/event-links.spec.ts`, `events-web/tests/guest/reservation-management.spec.ts`, `docs/testing/astir-events-device-entry.md`.

- For each of the five L01 origins, make Clip invocation unavailable and retain a recognized browser session; the permitted event fallback still loads.
- Browser confirmation uses the same canonical identity/event/booking as the service; full guest list and management work without installation or full-app tabs.
- Reload and use browser back/forward around management; preserve Event A and reconcile its current state, never invent a replacement RSVP.
- Prove fallback on an actual device/browser when public Clip invocation fails or is unavailable; a stubbed redirect proves only browser rendering.

Source authority: D14, C-NOAPP; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/BuildConfigurationTests.swift:126` — Adjacent evidence only; not Events coverage. Static full-app associated-domain assertions; does not prove hosted AASA, Clip invocation or distribution.

## L04 — Missing/expired session; a real RSVP exists server-side; open the link.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, full-app XCUITest, App Clip XCUITest, guest-web Playwright, controlled-service integration, physical-device integration. Real-device evidence required: yes.

Planned files: `WanderTests/Events/EventAccountRecoveryTests.swift`, `WanderUITests/Events/EventAccountRecoveryUITests.swift`, `AstirEventsClipUITests/EventAccountRecoveryUITests.swift`, `events-web/tests/guest/account-recovery.spec.ts`, `docs/testing/astir-events-device-entry.md`.

- Run missing, expired and deleted session variants on app, Clip and browser while a confirmed RSVP exists for the original account.
- Before account resolution show only permitted event detail and recovery; never display a successful no-booking result for an unknown identity.
- Original-account Apple/Google authentication retrieves the original booking ID without a new RSVP write, new identity merge or leaked private fields.
- Cancel, fail and retry recovery while preserving event intent; real provider and cross-surface session behavior is a separate physical-device pass.

Source authority: N1-IDENTITY; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/AuthSessionTests.swift:1385` — Adjacent evidence only; not Events coverage. Simulated session validation blocks token issuance until complete.
- `WanderTests/AuthSessionTests.swift:259` — Adjacent evidence only; not Events coverage. Unmatched Apple sign-in requires original-account recovery instead of simulated account creation.
- `WanderTests/AuthSessionTests.swift:973` — Adjacent evidence only; not Events coverage. Native session adoption rejects an unrelated resolved session ID.

## L05 — Recognized identity and successful booking lookup returns no booking; open the link.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, full-app XCUITest, App Clip XCUITest, guest-web Playwright, controlled-service integration. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventEntryStateTests.swift`, `WanderUITests/Events/EventLinkEntryUITests.swift`, `AstirEventsClipUITests/EventEntryUITests.swift`, `events-web/tests/guest/event-states.spec.ts`.

- Only a successful lookup for the currently validated account returning no booking becomes known-not-RSVPed.
- Show permitted detail and conversion hook; no full guest list or ticket; offer the current applicable RSVP action, respecting registration/code/capacity/approval results.
- Keep loading, timeout, denied, unknown response and account switch distinct from no booking; delayed earlier results cannot overwrite the active account.
- Assert lookup performs no reservation creation and hidden protected fields are absent from the authorized payload, not merely visually hidden.

Source authority: N1-IDENTITY, D30; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/AuthSessionTests.swift:1385` — Adjacent evidence only; not Events coverage. Simulated session validation blocks token issuance until complete.
- `WanderTests/RemoteRepositoryTests.swift:1103` — Adjacent evidence only; not Events coverage. A mocked protected-photo response is discarded after the account changes.

## L06 — Recognized pending applicant opens the link.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, full-app XCUITest, App Clip XCUITest, guest-web Playwright, controlled-service integration. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventEntryStateTests.swift`, `WanderUITests/Events/EventLinkEntryUITests.swift`, `AstirEventsClipUITests/EventEntryUITests.swift`, `events-web/tests/guest/event-states.spec.ts`.

- On all three surfaces, a pending applicant sees pending approval rather than confirmed or no booking.
- No entry QR, full guest list or booking-derived exact home address is rendered, announced or returned through the guest projection.
- Refreshing during a pending-to-confirmed or rejected transition uses the authoritative new state; no client-side timer or stale confirmation upgrades access.
- Pending lookup/retry neither holds a seat nor creates another application; corroborate with controlled service state.

Source authority: D22, D30, D13; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/AuthSessionTests.swift:1385` — Adjacent evidence only; not Events coverage. Simulated session validation blocks token issuance until complete.

## L07 — Recognized waitlisted guest opens the link.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, full-app XCUITest, App Clip XCUITest, guest-web Playwright, controlled-service integration. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventEntryStateTests.swift`, `WanderUITests/Events/EventLinkEntryUITests.swift`, `AstirEventsClipUITests/EventEntryUITests.swift`, `events-web/tests/guest/event-states.spec.ts`.

- On app, Clip and browser, a waitlisted account sees waitlist state, no ticket/full guest list and no invented queue rank.
- Reopening, refreshing or repeated link taps do not promote the guest or issue an offer; only authoritative staff selection changes that state.
- A later valid offer changes the action to explicit acceptance; a released seat alone does not confirm the account.
- Hold a response, switch accounts, then release it; waitlist status remains account/event scoped.

Source authority: D21, D23, D30; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/AuthSessionTests.swift:1441` — Adjacent evidence only; not Events coverage. Observed account switch invalidates an older in-flight refresh.
- `WanderTests/RemoteRepositoryTests.swift:1103` — Adjacent evidence only; not Events coverage. A mocked protected-photo response is discarded after the account changes.

## L08 — Recognized current offer holder opens the canonical link.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, full-app XCUITest, App Clip XCUITest, guest-web Playwright, controlled-service integration. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventOfferPresentationTests.swift`, `WanderUITests/Events/EventLinkEntryUITests.swift`, `AstirEventsClipUITests/EventEntryUITests.swift`, `events-web/tests/guest/offers.spec.ts`.

- A current offer is displayed only for its recipient with the service-issued deadline; it is not labeled confirmed and grants no confirmed-only guest list or ticket.
- Explicit acceptance is required; opening/reloading the canonical event link does not mutate the offer.
- Control time immediately before, at and after the deadline; reconcile actual service state at acceptance, including a device clock that disagrees with the server.
- Repeat after another account opens the same link; no offer ownership is transferred and no deadline is extended by authentication or rendering.

Source authority: D23; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/AuthSessionTests.swift:1385` — Adjacent evidence only; not Events coverage. Simulated session validation blocks token issuance until complete.
- `WanderTests/RemoteRepositoryTests.swift:1103` — Adjacent evidence only; not Events coverage. A mocked protected-photo response is discarded after the account changes.

## L09 — Expired offer or canceled booking; open an old message link.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, full-app XCUITest, App Clip XCUITest, guest-web Playwright, controlled-service integration. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventOfferPresentationTests.swift`, `WanderTests/Events/EventEntryStateTests.swift`, `WanderUITests/Events/EventLinkEntryUITests.swift`, `AstirEventsClipUITests/EventEntryUITests.swift`, `events-web/tests/guest/stale-links.spec.ts`.

- Seed confirmed/offer UI, then cancel the booking or expire/decline the offer server-side before opening an old message link.
- All hosts re-evaluate current state; never restore stale confirmation/QR or allow an expired unaccepted offer to confirm.
- An old operation retry returns the current canceled/expired outcome without reviving a booking or emitting another confirmation.
- Keep P11 return-to-waiting wording/status presentation conditional on its reviewed policy. Assert the approved no-confirmation/no-auto-promotion invariant now; do not approve a presentation by hard-coding it into a test.

Source authority: D23–D24; invariant agreed, P11 presentation proposed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/WanderWidgetIntegrationTests.swift:103` — Adjacent evidence only; not Events coverage. Quick-capture intent waits for session validation and only the matching request is consumed.
- `WanderTests/RemoteRepositoryTests.swift:682` — Adjacent evidence only; not Events coverage. A non-idempotent edge function does not blindly replay on auth failure; no Events mutation is tested.

## L10 — Recognized identity but reservation lookup is loading, then fails.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, full-app XCUITest, App Clip XCUITest, guest-web Playwright, controlled-service integration. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventEntryStateTests.swift`, `WanderTests/Events/EventRepositoryOutcomeTests.swift`, `WanderUITests/Events/EventLookupRecoveryUITests.swift`, `AstirEventsClipUITests/EventLookupRecoveryUITests.swift`, `events-web/tests/guest/lookup-recovery.spec.ts`.

- Suspend lookup, then return timeout, offline, 5xx, malformed/unsupported response and signed-in permission-denied variants on each surface.
- Loading/retry retains Event A; no intermediate or persistent no-RSVP/confirmed state is emitted without its authoritative result.
- Retry reconciles booking state without a new RSVP mutation; a successful late response from an obsolete request or previous account is ignored.
- Assert error categories are typed and distinct from missing booking; service denial must not be converted into account-switch advice solely by generic 403 decoding.

Source authority: N1-IDENTITY; derived fidelity requirement

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/RemoteRepositoryTests.swift:1103` — Adjacent evidence only; not Events coverage. A mocked protected-photo response is discarded after the account changes.
- `WanderTests/OnboardingStateTests.swift:751` — Adjacent evidence only; not Events coverage. Suspended foreground refresh retains the ready root.
- `WanderTests/BuildConfigurationTests.swift:602` — Adjacent evidence only; not Events coverage. Legacy transport intentionally treats both 401 and 403 as refreshable; Events distinctions need new tests.

## L11 — A confirmed guest forwards their reminder link to an unknown new viewer.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, full-app XCUITest, App Clip XCUITest, guest-web Playwright, controlled-service integration. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventLinkPrivacyTests.swift`, `WanderUITests/Events/EventAccountRecoveryUITests.swift`, `AstirEventsClipUITests/EventAccountRecoveryUITests.swift`, `events-web/tests/guest/forwarded-links.spec.ts`.

- Forward the exact confirmed sender link to an anonymous recipient, then to a different recognized account, on each surface.
- Resolve the recipient identity and its own booking state only; the URL is event intent, never proof of sender booking ownership.
- Inspect controlled service payload, page/app accessibility tree and retained state: no sender phone, booking/admission, full guest list or protected exact-home details leak.
- Sender and recipient reservation counts/owners remain unchanged; switching identities after a delayed sender response cannot import sender state.

Source authority: N1-LINK; agreed / derived access requirement

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/AuthSessionTests.swift:9` — Adjacent evidence only; not Events coverage. Canonical identity mapping preserves an existing profile identity.
- `WanderTests/RemoteRepositoryTests.swift:1103` — Adjacent evidence only; not Events coverage. A mocked protected-photo response is discarded after the account changes.

## L12 — Open the same event from Events discovery and from a confirmed Events card.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, full-app XCUITest, controlled-service integration. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventsTabRoutingTests.swift`, `WanderUITests/Events/EventsTabNavigationUITests.swift`.

- Tap a discovery card without a booking, then a confirmed Events card for the same event: both open full-app detail with the appropriate current viewer state.
- Tap direct Show ticket from the confirmed Events card: reach app-only QR without an extra detail screen, subject to required name/username and current confirmed state.
- Changing booking state between list fetch and tap is reconciled before protected actions; no Clip/browser shell is inserted.
- Back returns to the originating Events list; repeated taps do not stack duplicate presentations or create an RSVP.

Source authority: R136–R137, N1-DETAIL; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/NavigationContractTests.swift:898` — Adjacent evidence only; not Events coverage. Existing feed place actions use a common place-profile route; Events tab/card routing is absent.

## L13 — Full app installed, but platform leaves the link in a browser; choose Open Astir.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, full-app XCUITest, guest-web Playwright, controlled-service integration, physical-device integration. Real-device evidence required: yes.

Planned files: `WanderTests/Events/EventHandoffTests.swift`, `WanderUITests/Events/EventLinkEntryUITests.swift`, `events-web/tests/guest/app-handoff.spec.ts`, `docs/testing/astir-events-device-entry.md`.

- With the app installed, intentionally leave a canonical event link in the browser; browser detail remains usable before and after a failed Open Astir attempt.
- Explicit Open Astir carries Event A into the app; validate/recover its current account and retrieve that account’s current booking.
- Do not infer app absence or no RSVP from invocation failure; do not copy browser cookies or a booking claim as identity proof.
- Prove actual browser-to-app handoff on physical devices for warm/cold app and matching/different/expired app accounts; web stubs alone cannot pass the case.

Source authority: D14, N1-IDENTITY; derived recovery

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/BuildConfigurationTests.swift:126` — Adjacent evidence only; not Events coverage. Static full-app associated-domain assertions; does not prove hosted AASA, Clip invocation or distribution.
- `WanderTests/WanderWidgetIntegrationTests.swift:103` — Adjacent evidence only; not Events coverage. Quick-capture intent waits for session validation and only the matching request is consumed.
- `WanderTests/AuthSessionTests.swift:1441` — Adjacent evidence only; not Events coverage. Observed account switch invalidates an older in-flight refresh.

## L14 — Guest-list or View/change RSVP opened from each of the three surfaces; navigate back.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, full-app XCUITest, App Clip XCUITest, guest-web Playwright, controlled-service integration. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventHostNavigationTests.swift`, `WanderUITests/Events/EventManagementNavigationUITests.swift`, `AstirEventsClipUITests/EventManagementNavigationUITests.swift`, `events-web/tests/guest/reservation-management.spec.ts`.

- For confirmed guests on each host, open full guest list and View or change RSVP, then use visible Back and the host’s supported back gesture/history.
- Return to the originating event/surface with current account and booking state; no automatic app install, cross-host detour or guest-to-console route.
- After a successful management change, back navigation reflects its authoritative state rather than the cached confirmation.
- Canceling a management dialog or recovering a request error keeps the event and valid reservation intact; full list remains unavailable to nonconfirmed controls.

Source authority: N1-DETAIL, C-NOAPP; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/NavigationContractTests.swift:2708` — Adjacent evidence only; not Events coverage. Existing member-profile paths share back navigation; no event-management host continuity coverage.

## L15 — Event is denied, draft, removed or unknown; open its old link.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, full-app XCUITest, App Clip XCUITest, guest-web Playwright, controlled-service integration. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventRepositoryOutcomeTests.swift`, `WanderUITests/Events/EventUnavailableUITests.swift`, `AstirEventsClipUITests/EventUnavailableUITests.swift`, `events-web/tests/guest/event-unavailable.spec.ts`.

- Open links for denied, draft, removed and unknown events with unknown and recognized viewers; the server returns only the permitted projection.
- No event/booking/private location payload appears in network response, accessibility tree, persisted UI state or stale cached detail after denial.
- Distinguish auth-required, permission-denied, unavailable, transient failure and unsupported response states; none defaults to confirmed/no-booking.
- P19 unavailable wording and precise safe-return interaction remain proposed; test invariant-safe exits and approved identity recovery without freezing an unselected layout.

Source authority: Existing access protections; P19 presentation proposed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/WanderWidgetIntegrationTests.swift:121` — Adjacent evidence only; not Events coverage. Invalid URLs do not replace pending intent; latest valid widget intent wins.
- `WanderTests/BuildConfigurationTests.swift:602` — Adjacent evidence only; not Events coverage. Current generic 401/403 handling is a regression constraint, not Events authorization coverage.

## L16 — No app, RSVP just confirmed; dismiss or ignore download upsell, close, reopen the event link.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, App Clip XCUITest, guest-web Playwright, controlled-service integration, physical-device integration. Real-device evidence required: yes.

Planned files: `WanderTests/Events/EventPostRSVPContinuationTests.swift`, `AstirEventsClipUITests/EventEntryUITests.swift`, `events-web/tests/guest/post-rsvp-continuation.spec.ts`, `docs/testing/astir-events-device-entry.md`.

- Immediately after a real confirmed RSVP without the app, dismiss/ignore the optional download offer and close the Clip/browser.
- Reopen the event: when recognized, the same booking, full guest list and management remain accessible without download; expired identity follows L04 instead of assuming a session.
- Controlled service evidence retains the confirmation and agreed event-message intent; declining installation does not cancel/suppress event texts or add a download deadline.
- Actual Clip/browser lifecycle and reopen behavior require a device pass; no app-only QR/check-in/upload is granted in the no-app host.

Source authority: C-NOAPP, September 14 timing clarification; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/WanderWidgetIntegrationTests.swift:103` — Adjacent evidence only; not Events coverage. Quick-capture intent waits for session validation and only the matching request is consumed.
- `WanderTests/OnboardingStateTests.swift:149` — Adjacent evidence only; not Events coverage. Onboarding progress persistence is isolated per user.

## L17 — App/Clip/browser side-by-side for unknown, known not-RSVPed and confirmed guests.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, full-app XCUITest, App Clip XCUITest, guest-web Playwright. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventContractParityTests.swift`, `WanderUITests/Events/EventSurfaceParityUITests.swift`, `AstirEventsClipUITests/EventSurfaceParityUITests.swift`, `events-web/tests/guest/surface-parity.spec.ts`, `tests/fixtures/events/entry-states.json`.

- Run the explicit nine app/Clip/browser × unknown/known-no-booking/confirmed states against one language-neutral fixture set; compare permitted content, state names and action eligibility.
- Unknown is not a negative lookup; confirmed-only fields/actions do not appear in the other two states.
- App-only actions are explicitly gated by host; Clip/browser show event-specific chrome with no full-app tabs.
- Original invitation, confirmation, reminder, shared-link and event-notification fixtures use consistent View event labeling and the same canonical event identity. This is nine-state parity, not a claim that all platform combinations were exercised.

Source authority: N1-LINK, N1-IDENTITY, N1-DETAIL; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/NavigationContractTests.swift:963` — Adjacent evidence only; not Events coverage. Profile-link parsing tests exist; no shared Events or Swift/web parity fixture exists.

## I01 — New Clip or browser guest chooses Apple, then separately repeat with Google.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, App Clip XCUITest, guest-web Playwright, controlled-service integration, physical-device integration. Real-device evidence required: yes.

Planned files: `WanderTests/Events/EventRSVPIdentityTests.swift`, `AstirEventsClipUITests/EventRSVPUITests.swift`, `events-web/tests/guest/rsvp-identity.spec.ts`, `docs/testing/astir-events-device-entry.md`.

- Independently complete Apple and Google sign-up in the real Clip and browser without installing the full app; verify canonical service identity, event and account survive redirects.
- Collect missing name and phone; phone challenge must bind to the current account and exact current number, and verification precedes successful RSVP.
- Before authoritative verification, zero confirmed reservation and confirmation-message intents exist; after eligible submit exactly one correct booking exists.
- Do not substitute phone-only identity or infer proof from a stored phone string. Record actual provider, phone-proof result and masked test fixture identity without exposing tokens/codes.
- Run installed-app RSVP identity adapter against equivalent controlled fixtures; real Clip provider compatibility is a foundation acceptance gate, not proved by PreviewAuthSessionProvider.

Source authority: D17, inline “3 is unchanged”; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/AuthSessionTests.swift:159` — Adjacent evidence only; not Events coverage. PreviewAuthSessionProvider simulates Apple completion; no provider or Clip integration is exercised.
- `WanderTests/AuthSessionTests.swift:279` — Adjacent evidence only; not Events coverage. PreviewAuthSessionProvider simulates Google completion; no real provider redirect is exercised.
- `Wander/Services/Auth/AuthSessionProviding.swift:48` — Adjacent evidence only; not Events coverage. AuthSession stores a phone string but no verified-current-phone proof.

## I02 — Existing recognized account already has matching verified phone and saved identity; RSVP.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, full-app XCUITest, App Clip XCUITest, guest-web Playwright, controlled-service integration. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventRSVPIdentityTests.swift`, `WanderUITests/Events/EventRSVPUITests.swift`, `AstirEventsClipUITests/EventRSVPUITests.swift`, `events-web/tests/guest/rsvp-identity.spec.ts`.

- Provide service-confirmed proof for the same current account/phone and already-known name; reuse those fields and proof without redundant collection or SMS sends.
- No proof from a different account/old number or a locally populated phone string qualifies; those controls route to verification.
- Even with reusable identity, evaluate current event registration, invitation code, approval and capacity; identity reuse does not imply confirmation.
- A refresh or repeated tap does not create a new challenge, booking or confirmation message for an already-completed operation.
- Explicit missing-name variant: retain current matching verified phone proof, collect only the missing name, and assert zero phone-challenge creation/SMS sends before continuing RSVP. T01 contract field-selection proof alone does not satisfy the provider/UI send-count assertion.

Source authority: D17; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/AuthSessionTests.swift:9` — Adjacent evidence only; not Events coverage. Canonical identity mapping preserves an existing profile identity.
- `WanderTests/ProfileIdentityDraftTests.swift:43` — Adjacent evidence only; not Events coverage. Unchanged original handles avoid redundant availability checks; no phone-verification reuse test exists.

## I03 — Number is only a stored string or was changed; attempt confirmation. For a new unreserved guest, fill the last available spot while verification is in progress, then submit.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, full-app XCUITest, App Clip XCUITest, guest-web Playwright, controlled-service integration. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventPhoneProofTests.swift`, `WanderTests/Events/EventRSVPStateTests.swift`, `WanderUITests/Events/EventRSVPUITests.swift`, `AstirEventsClipUITests/EventRSVPUITests.swift`, `events-web/tests/guest/phone-verification.spec.ts`.

- Stored-only phone, changed number and proof for another account/number cannot confirm an RSVP; verify against authoritative current proof.
- While a new unreserved guest verifies, another eligible guest takes the final seat; the verifying attempt holds no capacity.
- On later submission, preserve successful verification and Event A but return actual full/waitlist-eligible state; offer a choice and do not auto-join or falsely confirm.
- Repeat with available capacity as control and with registration closing during verification; submission uses current rules, not eligibility captured at flow start.

Source authority: D17, engineering D6A; agreed / derived

Adjacent existing evidence (not implemented Events coverage):
- `Wander/Services/Auth/AuthSessionProviding.swift:53` — Adjacent evidence only; not Events coverage. Stored phoneNumber has no verification provenance; new proof and capacity-race coverage are absent.

## I04 — Wrong/expired SMS code, resend, change number, and retry. Repeat recovery with an existing confirmed booking and with a still-valid issued offer.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, full-app XCUITest, App Clip XCUITest, guest-web Playwright, controlled-service integration, physical-device integration. Real-device evidence required: yes.

Planned files: `WanderTests/Events/EventPhoneProofTests.swift`, `WanderUITests/Events/EventPhoneVerificationUITests.swift`, `AstirEventsClipUITests/EventPhoneVerificationUITests.swift`, `events-web/tests/guest/phone-verification.spec.ts`, `docs/testing/astir-events-device-entry.md`.

- Wrong, expired and superseded challenge codes cannot confirm; changing the phone invalidates old-number proof and retains event/account context.
- Resend/error/rate-limit/offline responses remain recoverable without false success; countdown follows the selected provider policy. P02 exact timing is not approved by this mapping.
- For existing confirmed recovery, verification retry neither cancels nor duplicates the booking. For a valid issued offer it neither adds a hold nor changes the original deadline.
- At/after an unaccepted offer deadline, verification success does not confirm that expired offer; recover actual current state.
- Exercise real provider delivery and verification using controlled test phones on devices, including app/Clip/browser return; no messages go to real attendees.

Source authority: D17, engineering D3A/D4A/D6A; invariants agreed, P02 timing proposed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/AuthSessionTests.swift:1385` — Adjacent evidence only; not Events coverage. Simulated session validation blocks token issuance until complete.
- `WanderTests/AuthSessionTests.swift:565` — Adjacent evidence only; not Events coverage. Injected activation-response loss recovers the expected session; this is not a real install/Clip handoff.

## I05 — Cancel Apple/Google authorization or receive additional-verification/auth failure.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, full-app XCUITest, App Clip XCUITest, guest-web Playwright, controlled-service integration, physical-device integration. Real-device evidence required: yes.

Planned files: `WanderTests/Events/EventAccountRecoveryTests.swift`, `WanderUITests/Events/EventAccountRecoveryUITests.swift`, `AstirEventsClipUITests/EventAccountRecoveryUITests.swift`, `events-web/tests/guest/account-recovery.spec.ts`, `docs/testing/astir-events-device-entry.md`.

- For Apple and Google independently, cancel, return provider failure and require an additional verification step; retain Event A and any original booking.
- No unrelated session event or partially completed login establishes ownership, creates a replacement booking or silently merges accounts.
- Retry/recover can retrieve the original account/booking; support exit retains safe context and does not bypass entry.
- P01 exact interrupted-auth presentation remains proposed. Verify real provider cancellation/additional-verification behavior where the provider can produce it; mark unavailable variants unverified rather than simulating a device pass.

Source authority: N1-IDENTITY; invariant derived, P01 interaction proposed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/AuthSessionTests.swift:199` — Adjacent evidence only; not Events coverage. Simulated Apple cancellation retains the auth presentation without a false completion.
- `WanderTests/AuthSessionTests.swift:220` — Adjacent evidence only; not Events coverage. Simulated Apple failure remains recoverable.
- `WanderTests/AuthSessionTests.swift:259` — Adjacent evidence only; not Events coverage. Unmatched Apple sign-in requires original-account recovery instead of simulated account creation.
- `WanderTests/AuthSessionTests.swift:973` — Adjacent evidence only; not Events coverage. Native session adoption rejects an unrelated resolved session ID.

## I06 — Installed guest selects another account after an unmatched lookup.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, full-app XCUITest, controlled-service integration, physical-device integration. Real-device evidence required: yes.

Planned files: `WanderTests/Events/EventAccountRecoveryTests.swift`, `WanderUITests/Events/EventAccountRecoveryUITests.swift`, `docs/testing/astir-events-device-entry.md`.

- Only after successful lookup for the active account with no RSVP show No RSVP found for this account / Already RSVPed? and Find my RSVP / Get help.
- Pending, waitlisted, offered, loading and failed lookup are distinct controls and never display the no-match recovery state.
- Switch to the original Apple/Google account, preserving Event A; retrieve its existing booking and complete only missing entry identity. No replacement RSVP or silent merge occurs.
- Cancel auth, choose another unmatched account, delay the old lookup and switch during token refresh; discard stale/private results and make no claim about who owns another booking.
- Prove different-current-app-account recovery with real provider sessions on a physical device, not only state-injection tests.

Source authority: N1-IDENTITY, engineering D3A; agreed / derived

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/AuthSessionTests.swift:259` — Adjacent evidence only; not Events coverage. Unmatched Apple sign-in requires original-account recovery instead of simulated account creation.
- `WanderTests/AuthSessionTests.swift:1441` — Adjacent evidence only; not Events coverage. Observed account switch invalidates an older in-flight refresh.
- `WanderTests/RemoteRepositoryTests.swift:1103` — Adjacent evidence only; not Events coverage. A mocked protected-photo response is discarded after the account changes.

## I07 — Install from the event link, then open Astir from its icon without reopening the link.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, full-app XCUITest, controlled-service integration, physical-device integration. Real-device evidence required: yes.

Planned files: `WanderTests/Events/EventInstallRecoveryTests.swift`, `WanderUITests/Events/EventInstallRecoveryUITests.swift`, `docs/testing/astir-events-device-entry.md`.

- From confirmed Clip and browser fixtures independently, start full-app installation then launch from its icon without reopening the event link.
- After legitimate session recovery, reach the originating event and original booking; server reservation count/identity stay unchanged.
- Run no transferred session, expired session, different existing app account and relaunch during recovery; preserve intent safely, require original-account proof where needed and never infer ownership from the link.
- Prove the concrete mechanism with intended TestFlight and public installation paths separately. A simulator fixture surviving argument-free relaunch is not install transfer evidence.
- If public distribution or required account handoff cannot be exercised, record the exact blocked variant and do not mark I07 passed.

Source authority: D14, N1-IDENTITY; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/AuthSessionTests.swift:565` — Adjacent evidence only; not Events coverage. Injected activation-response loss recovers the expected session; this is not a real install/Clip handoff.
- `WanderUITests/OnboardingUITests.swift:598` — Adjacent evidence only; not Events coverage. A persisted simulator fixture survives relaunch; explicitly does not establish Clip/browser install handoff.

## I08 — App installed but name missing; then repeat with username missing/both missing; request entry QR.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, full-app XCUITest, controlled-service integration. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventEntrySetupTests.swift`, `WanderUITests/Events/EventEntrySetupUITests.swift`.

- Parameterize missing name, missing username, both missing, whitespace-only name, invalid username and unavailable username.
- QR is withheld until the current account has server-accepted valid name/username; collect only missing/invalid essentials and retain the original confirmed booking.
- A failed profile save or handle becoming taken after an availability check remains incomplete; no optimistic local success unlocks QR.
- Concurrent account switch or delayed validation cannot fill the new account with old values or display the old account’s QR; successful correction continues directly to that booking.

Source authority: N2-SETUP; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/ProfileIdentityDraftTests.swift:13` — Adjacent evidence only; not Events coverage. Missing display name and invalid handle are rejected.
- `WanderTests/RemoteRepositoryTests.swift:1700` — Adjacent evidence only; not Events coverage. RecordingRPC verifies handle-availability request mapping, not concurrent live uniqueness.
- `WanderTests/AuthSessionTests.swift:1441` — Adjacent evidence only; not Events coverage. Observed account switch invalidates an older in-flight refresh.

## I09 — Valid name/username, no profile photo; skip or fail photo upload.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, full-app XCUITest, controlled-service integration. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventEntrySetupTests.swift`, `WanderUITests/Events/EventEntrySetupUITests.swift`.

- With valid name/username and confirmed booking, no photo, explicit Skip, picker cancel, corrupt image and failed upload all leave ticket access available.
- The strong photo prompt stays optional; no endless retry or hidden required-avatar flag blocks QR or the authorized admission flow.
- Failed upload is not labeled saved or persisted as a successful remote avatar; preserve original avatar where applicable.
- Retrying an optional photo must not mutate booking state or issue a second ticket/admission record.

Source authority: D18, N2-SETUP; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/ProfileAvatarStorageTests.swift:24` — Adjacent evidence only; not Events coverage. Invalid image data is rejected; no Events optional-photo gate test exists.
- `WanderTests/ProfileIdentityDraftTests.swift:13` — Adjacent evidence only; not Events coverage. Missing display name and invalid handle are rejected.

## I10 — Valid returning account requests QR with general tour/location/contacts/notification steps incomplete.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, full-app XCUITest, controlled-service integration. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventEntrySetupTests.swift`, `WanderUITests/Events/EventEntrySetupUITests.swift`.

- Use a confirmed returning account with valid name/username and each general tour/location/contacts/notifications step incomplete; request ticket via link and Events card.
- Reach the event QR after the approved entry essentials; do not add location/contact/notification permission or general-tour completion as a gate.
- Denied/restricted/not-determined permission controls and canceled general prompts do not invalidate RSVP or lose event intent.
- Do not mark every unrelated onboarding step complete merely to bypass its UI. P13 exact later resumption/general deferral presentation stays proposed; D3A event-preserving essentials-only recovery is approved.

Source authority: N2-SETUP; agreed essentials, P13 general deferral proposal

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/OnboardingStateTests.swift:196` — Adjacent evidence only; not Events coverage. Current ordinary onboarding resumes optional contacts; Events entry needs a dedicated tested route.
- `WanderTests/OnboardingStateTests.swift:149` — Adjacent evidence only; not Events coverage. Onboarding progress persistence is isolated per user.

## I11 — New guest sees future-event SMS checkbox, leaves it unchecked, finishes RSVP.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, full-app XCUITest, App Clip XCUITest, guest-web Playwright, controlled-service integration. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventRSVPConsentTests.swift`, `WanderUITests/Events/EventRSVPUITests.swift`, `AstirEventsClipUITests/EventRSVPUITests.swift`, `events-web/tests/guest/rsvp-consent.spec.ts`.

- A new guest sees the approved future-event SMS checkbox unchecked by default, with its approved label and no trailing period.
- Leave it unchecked and confirm a valid RSVP; service stores no future-event marketing consent while the agreed event-specific message program remains eligible.
- Toggle on then off before submitting, retry after lost response and reopen the flow; no unchecked final submission fabricates consent.
- Inspect controlled booking/consent records and message outbox, not just checkbox appearance; use only test recipients. Failure to save consent/RSVP is never shown as successful confirmation.

Source authority: D19, inline recording; agreed

## I12 — Attempt repeat RSVP after lost response, app relaunch, and concurrent taps.

Owner: Entry/identity foundation, then Before-event/door; data/rules owner supplies authoritative fixtures and server-state oracle. Layers: native XCTest, full-app XCUITest, App Clip XCUITest, guest-web Playwright, controlled-service integration. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventRSVPRetryTests.swift`, `WanderUITests/Events/EventRSVPRecoveryUITests.swift`, `AstirEventsClipUITests/EventRSVPRecoveryUITests.swift`, `events-web/tests/guest/rsvp-retries.spec.ts`.

- Drop the successful submit response after commit; retry with the same operation identity, relaunch, and resolve the actual pending/offer/confirmed state for the account/event.
- Two concurrent taps/clients and repeated response retries produce one logical booking, one seat/code effect where applicable and one logical confirmation-message intent.
- Cover failure before commit, unknown completion, auth refresh and a booking canceled before an old retry arrives; no blind new mutation, stale confirmation or canceled-booking revival.
- Bind persisted pending operation to account/event and reject delayed previous-account results after switching; transport errors must not be translated into no booking.
- Assert durable server counts and outbox intent deduplication through controlled integration; UI request counts alone do not prove idempotency or delivery behavior.

Source authority: N1-IDENTITY, D22–D23; derived consistency

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/AuthSessionTests.swift:565` — Adjacent evidence only; not Events coverage. Injected activation-response loss recovers the expected session; this is not a real install/Clip handoff.
- `WanderTests/RemoteRepositoryTests.swift:682` — Adjacent evidence only; not Events coverage. A non-idempotent edge function does not blindly replay on auth failure; no Events mutation is tested.
- `WanderTests/RemoteRepositoryTests.swift:1103` — Adjacent evidence only; not Events coverage. A mocked protected-photo response is discarded after the account changes.

## B01 — Codes disabled; guest opens invitation and RSVPs.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment). Real-device evidence required: no.

Planned files: `supabase/tests/events_booking.sql`, `scripts/supabase-smoke-test.mjs`, `events-web/tests/guest/rsvp.spec.ts`.

- With codes disabled, an eligible account can complete the free verified RSVP through the actual API without supplying an invented empty code.
- Assert one confirmed booking and correct capacity allocation; failure/unknown response remains recoverable and never fabricates confirmation.
- Browser UI must not force app installation before confirmation; native/Clip consumers use the same state contract.

Source authority: N2-CODES, D20; agreed

Adjacent existing evidence (not implemented Events coverage):
- `scripts/supabase-smoke-test.mjs:1110` — Existing migration-preview / strict pgTAP rollback-only entry points can host planned Events contract checks. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/clerk_identity_continuity.sql:7` — Existing tests inspect security mode, search_path and authenticated canonical-identity resolution. Adjacent evidence only; no Events test is implemented or passed.

## B02 — Operator generates optional invitation code and includes it with original invitation; recipient uses it.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment). Real-device evidence required: no.

Planned files: `supabase/tests/events_invitation_codes.sql`, `supabase/tests/events_authorization.sql`, `scripts/supabase-smoke-test.mjs`, `events-web/tests/guest/invitation-codes.spec.ts`, `events-web/tests/console/event-controls.spec.ts`.

- An authorized Team admin generates an optional code; an eligible recipient supplies it for the same canonical event.
- Forwarded invitation/code never authenticates its recipient as the sender, transfers an RSVP, or exposes sender phone or private booking data.
- Only an authorized admin can generate/inspect code administration; direct ordinary-user calls fail. Exact code-entry/prefill UI remains P18-proposed.

Source authority: N2-CODES, N1-LINK; agreed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/clerk_identity_continuity.sql:7` — Existing tests inspect security mode, search_path and authenticated canonical-identity resolution. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/rls_visibility.sql:7` — Existing fixtures distinguish owner, follower, mutual, nonfollower and blocked viewers. Adjacent evidence only; no Events test is implemented or passed.

## B03 — Code is valid and unlimited; different eligible guests use it.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment). Real-device evidence required: no.

Planned files: `supabase/tests/events_invitation_codes.sql`, `supabase/tests/events_booking.sql`, `scripts/supabase-smoke-test.mjs`, `events-web/tests/guest/invitation-codes.spec.ts`.

- Multiple distinct verified eligible accounts can use an unlimited code without an artificial usage ceiling.
- Unlimited code never bypasses event capacity, manual approval, account ownership, verification or the later full-app entry gate.
- Known pending/waitlisted/confirmed states return the actual existing request rather than another allocation.

Source authority: N2-CODES; agreed

Adjacent existing evidence (not implemented Events coverage):
- `scripts/supabase-smoke-test.mjs:1110` — Existing migration-preview / strict pgTAP rollback-only entry points can host planned Events contract checks. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/clerk_identity_continuity.sql:7` — Existing tests inspect security mode, search_path and authenticated canonical-identity resolution. Adjacent evidence only; no Events test is implemented or passed.

## B04 — Five-use code with five pending/waitlisted applicants; confirm eligible guests through automatic, manual and offer paths; then exhaust the quota and try another confirmation.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke. Real-device evidence required: no.

Planned files: `supabase/tests/events_invitation_codes.sql`, `supabase/tests/events_booking.sql`, `scripts/supabase-smoke-test.mjs`.

- Five pending/waitlisted requests on a five-use code consume zero uses and reserve zero allowance absent an issued offer.
- Automatic confirmation, manual approval and valid offer acceptance each allocate exactly one consumed use with one confirmed booking/seat in the same transaction.
- A valid offer reserves code allowance without consuming it; unrelated confirmation cannot spend that allowance.
- Invalid, unverified, rejected or transaction-failed confirmations consume no use, create no seat and enqueue no confirmed message. Exhausted quota cannot confirm.

Source authority: N2-CODES, engineering D10A; agreed / derived

Adjacent existing evidence (not implemented Events coverage):
- `scripts/supabase-smoke-test.mjs:1110` — Existing migration-preview / strict pgTAP rollback-only entry points can host planned Events contract checks. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/notifications.sql:6` — Existing notification pgTAP suite provides transactional notification fixture patterns. Adjacent evidence only; no Events test is implemented or passed.

## B05 — Two confirmations contend for the last code use and event spot; separately, one valid offer already reserves that code allowance. Retry a committed confirmation after its response is lost.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Node pg multi-session concurrency (isolated disposable database). Real-device evidence required: no.

Planned files: `supabase/tests/events_invitation_codes.sql`, `supabase/tests/events_booking.sql`, `supabase/tests/events_notifications.sql`, `scripts/supabase-smoke-test.mjs`, `scripts/events-concurrency.test.mjs`.

- Use separate DB sessions and explicit barriers to contend two eligible confirmations for the last seat AND last code use; verify committed totals and final outcomes rather than sequential RPC results.
- Repeat with an issued offer already holding the last allowance, and with manual approval, cancellation/rebooking and offer issuance racing; no allocation spends protected capacity or code allowance.
- Drop the client response after a successful commit, then retry the same operation identity: one current booking, one consumed use, one seat and one logical confirmation message.
- Inspect a fresh session after all commits; assert no orphan allocation, negative counter, duplicate logical message or unhandled deadlock.

Source authority: N2-CODES, D21–D23, D31, engineering D4A/D10A; derived

Adjacent existing evidence (not implemented Events coverage):
- `scripts/package.json:24` — Pinned pg client can support a new Node test harness with independent PostgreSQL connections. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/migrations/20260729123000_web_links_and_place_list_invites.sql:210` — Existing list invitation locks a specific row, not shared event capacity; Events races cannot be assumed solved by reuse. Adjacent evidence only; no Events test is implemented or passed.
- `scripts/supabase-smoke-test.mjs:1110` — Existing migration-preview / strict pgTAP rollback-only entry points can host planned Events contract checks. Adjacent evidence only; no Events test is implemented or passed.

## B06 — Missing/invalid required code; later disable a code with existing pending, waitlisted, offered and confirmed guests. Include an unfinished attempt, a submission racing deactivation, lost-response retry and a canceled guest rebooking.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment), Node pg multi-session concurrency (isolated disposable database). Real-device evidence required: no.

Planned files: `supabase/tests/events_invitation_codes.sql`, `supabase/tests/events_booking.sql`, `supabase/tests/events_authorization.sql`, `scripts/supabase-smoke-test.mjs`, `scripts/events-concurrency.test.mjs`, `events-web/tests/guest/invitation-codes.spec.ts`.

- Missing/invalid required code blocks new submission without losing event/account context; a disabled code blocks new submissions and unfinished attempts.
- Previously committed, account-bound, verified pending/waitlist requests retain code eligibility, but still need available quota/capacity and approval; existing confirmations and valid offers survive.
- Synchronize submission versus code deactivation in two DB sessions to prove commit ordering, then retry a lost committed response; no client timestamp or code precheck manufactures grandfathered eligibility.
- Cancellation followed by deliberate rebooking is a new attempt and receives no inherited eligibility. Other code edits/cap reductions and exact P18 UI are POLICY-GATED, not approved by this test.

Source authority: N2-CODES, engineering D10A–D12A; deactivation agreed / derived; other P18 edits/UI details proposed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/clerk_identity_continuity.sql:7` — Existing tests inspect security mode, search_path and authenticated canonical-identity resolution. Adjacent evidence only; no Events test is implemented or passed.
- `scripts/package.json:24` — Pinned pg client can support a new Node test harness with independent PostgreSQL connections. Adjacent evidence only; no Events test is implemented or passed.
- `scripts/supabase-smoke-test.mjs:1110` — Existing migration-preview / strict pgTAP rollback-only entry points can host planned Events contract checks. Adjacent evidence only; no Events test is implemented or passed.

## B07 — Available unprotected seat, eligible verified guest, automatic approval; include arrival after event start but before end, a console earlier close, verification crossing the cutoff and retry of a pre-close committed request.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment), Node pg multi-session concurrency (isolated disposable database). Real-device evidence required: no.

Planned files: `supabase/tests/events_booking.sql`, `supabase/tests/events_invitation_codes.sql`, `supabase/tests/events_notifications.sql`, `scripts/supabase-smoke-test.mjs`, `scripts/events-concurrency.test.mjs`, `events-web/tests/guest/rsvp.spec.ts`.

- For default registration close at event end, eligible online RSVP succeeds after start but before end; repeat with a configured earlier close and before/at/after boundaries.
- A new unreserved phone-verification attempt holds no seat; if capacity fills meanwhile, retain verified identity and offer the choice to join the event waitlist without automatic enrollment.
- After the cutoff, unfinished attempts cannot submit a new booking. A pre-cutoff committed request with a lost response resolves its current booking, including pending state.
- Include a request blocked on capacity lock until cutoff passes and assert fresh server eligibility at the mutation boundary; no payment, offline signup, self-cancel extension or entry-app waiver.

Source authority: D20, D22, D29–D30, engineering D6A/D14A; agreed / derived

Adjacent existing evidence (not implemented Events coverage):
- `supabase/migrations/20260729123000_web_links_and_place_list_invites.sql:210` — Existing list invitation locks a specific row, not shared event capacity; Events races cannot be assumed solved by reuse. Adjacent evidence only; no Events test is implemented or passed.
- `scripts/package.json:24` — Pinned pg client can support a new Node test harness with independent PostgreSQL connections. Adjacent evidence only; no Events test is implemented or passed.
- `scripts/supabase-smoke-test.mjs:1110` — Existing migration-preview / strict pgTAP rollback-only entry points can host planned Events contract checks. Adjacent evidence only; no Events test is implemented or passed.

## B08 — Manual approval mode; eligible guest requests; operator approves with available capacity. Repeat with no unprotected capacity and with two approvals competing for the last spot.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment), Node pg multi-session concurrency (isolated disposable database). Real-device evidence required: no.

Planned files: `supabase/tests/events_booking.sql`, `supabase/tests/events_notifications.sql`, `scripts/supabase-smoke-test.mjs`, `scripts/events-concurrency.test.mjs`, `events-web/tests/console/event-controls.spec.ts`.

- Pending manual-review application allocates no seat or code use and exposes no confirmed-only rights.
- Approval with unprotected seat/code allowance atomically confirms once and enqueues one logical confirmation; duplicate/lost-response retry reads current state.
- With insufficient capacity or code allowance, applicant remains pending and operator sees the reason; no false success, automatic waitlist move or theft of issued-offer/D31-protected capacity.
- Two independently authenticated admins approve different applicants in separate DB sessions against the last spot; at most one commits.

Source authority: D22, engineering D4A/D5A; agreed / derived

Adjacent existing evidence (not implemented Events coverage):
- `scripts/package.json:24` — Pinned pg client can support a new Node test harness with independent PostgreSQL connections. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/notifications.sql:6` — Existing notification pgTAP suite provides transactional notification fixture patterns. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/clerk_identity_continuity.sql:7` — Existing tests inspect security mode, search_path and authenticated canonical-identity resolution. Adjacent evidence only; no Events test is implemented or passed.

## B09 — Event full, or released space protected for active waitlist; new guest RSVPs.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment). Real-device evidence required: no.

Planned files: `supabase/tests/events_booking.sql`, `scripts/supabase-smoke-test.mjs`, `events-web/tests/guest/rsvp.spec.ts`.

- A full event, or released inventory still protected for active waitlist selection, returns a real event-waitlist option rather than false confirmation.
- Joining an event waitlist requires an explicit guest action; city-interest state remains a distinct record and cannot count as event attendance/confirmation.
- No waitlisted requester gains confirmed guest list, QR or exact-home reveal by reading a client flag or requesting the API directly.

Source authority: D21, D31, N2 waitlist clarification; agreed

Adjacent existing evidence (not implemented Events coverage):
- `scripts/supabase-smoke-test.mjs:1110` — Existing migration-preview / strict pgTAP rollback-only entry points can host planned Events contract checks. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/rls_visibility.sql:7` — Existing fixtures distinguish owner, follower, mutual, nonfollower and blocked viewers. Adjacent evidence only; no Events test is implemented or passed.

## B10 — Operator selects waitlisted person and sends offer; guest opens it but does not accept. Repeat with a required capped invitation code.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment), Node pg multi-session concurrency (isolated disposable database). Real-device evidence required: no.

Planned files: `supabase/tests/events_booking.sql`, `supabase/tests/events_invitation_codes.sql`, `supabase/tests/events_notifications.sql`, `scripts/supabase-smoke-test.mjs`, `scripts/events-concurrency.test.mjs`, `events-web/tests/guest/offers.spec.ts`, `events-web/tests/console/event-controls.spec.ts`.

- Admin selection creates an offer, not confirmation; opening the link never accepts. Authenticated owner sees the actual offer/deadline without confirmed benefits.
- Offer creation atomically holds one seat and, if required, one available code allowance; allowance is held rather than consumed.
- Concurrent offer issuance against the last seat/code allowance cannot overissue; lack of either limit leaves no unusable orphan offer.
- Default offer duration is 24h unless configured. Bounding a new offer by registration close / changing an issued deadline remains POLICY-GATED and must not silently shorten a promised hold.

Source authority: D23, N2 waitlist clarification, engineering D4A/D10A; agreed / derived

Adjacent existing evidence (not implemented Events coverage):
- `scripts/package.json:24` — Pinned pg client can support a new Node test harness with independent PostgreSQL connections. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/migrations/20260729123000_web_links_and_place_list_invites.sql:210` — Existing list invitation locks a specific row, not shared event capacity; Events races cannot be assumed solved by reuse. Adjacent evidence only; no Events test is implemented or passed.
- `scripts/supabase-smoke-test.mjs:1110` — Existing migration-preview / strict pgTAP rollback-only entry points can host planned Events contract checks. Adjacent evidence only; no Events test is implemented or passed.

## B11 — Correct offer owner accepts before expiry, then repeats acceptance; include a lost successful response and retry after the original deadline.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment). Real-device evidence required: no.

Planned files: `supabase/tests/events_booking.sql`, `supabase/tests/events_invitation_codes.sql`, `supabase/tests/events_notifications.sql`, `scripts/supabase-smoke-test.mjs`, `events-web/tests/guest/offers.spec.ts`.

- A correct authenticated owner accepting a valid offer before deadline converts the existing seat/code holds into one confirmed booking and consumed use.
- Repeated acceptance and a lost-success-response retry after the old deadline return the current successful booking without another allocation/message or false expiry.
- After a subsequent cancellation, stale acceptance returns current canceled state and cannot revive the booking or reclaim released allowance.
- No ownership proof is accepted from a name, phone string, forwarded URL or a different signed-in account.

Source authority: D23, engineering D4A; agreed / derived

Adjacent existing evidence (not implemented Events coverage):
- `supabase/migrations/20260729123000_web_links_and_place_list_invites.sql:210` — Existing list invitation locks a specific row, not shared event capacity; Events races cannot be assumed solved by reuse. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/clerk_identity_continuity.sql:7` — Existing tests inspect security mode, search_path and authenticated canonical-identity resolution. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/notifications.sql:6` — Existing notification pgTAP suite provides transactional notification fixture patterns. Adjacent evidence only; no Events test is implemented or passed.

## B12 — Wrong account, expired unaccepted offer, declined offer, or acceptance at deadline; include a delayed expiry worker and an acceptance waiting on the capacity lock past its deadline.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment), Node pg multi-session concurrency (isolated disposable database). Real-device evidence required: no.

Planned files: `supabase/tests/events_booking.sql`, `supabase/tests/events_invitation_codes.sql`, `scripts/supabase-smoke-test.mjs`, `scripts/events-concurrency.test.mjs`, `events-web/tests/guest/offers.spec.ts`.

- Wrong-account, declined, expired-unaccepted and at-deadline acceptance fail without confirmation or confirmed benefits.
- Start the contender transaction before deadline, hold its capacity lock in another DB session until after deadline, then release it: acceptance must use a fresh authoritative server clock AFTER lock acquisition, not transaction-start now() or client time.
- Delay expiry cleanup: expired holds stop allocating seat/code allowance and cannot be accepted; decline/expiry release unconsumed allowance once without a cancellation refund or automatic next promotion.
- D31 still protects released capacity while applicable waitlist exists. Post-expiry display/withdrawal/reselection details remain P11 POLICY-GATED.

Source authority: D21, D23, D31, engineering D4A/D10A/D11A; agreed / derived; post-expiry waitlist-status details remain proposed

Adjacent existing evidence (not implemented Events coverage):
- `scripts/package.json:24` — Pinned pg client can support a new Node test harness with independent PostgreSQL connections. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/migrations/20260729123000_web_links_and_place_list_invites.sql:210` — Existing list invitation locks a specific row, not shared event capacity; Events races cannot be assumed solved by reuse. Adjacent evidence only; no Events test is implemented or passed.
- `scripts/supabase-smoke-test.mjs:1110` — Existing migration-preview / strict pgTAP rollback-only entry points can host planned Events contract checks. Adjacent evidence only; no Events test is implemented or passed.

## B13 — Confirmed guest on app/Clip/browser cancels before start, then retries after a lost response; repeat with a capped code, a code-free booking and competing reuse/rebooking.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment), Node pg multi-session concurrency (isolated disposable database), native XCTest / XCUITest, real iPhone / intended staff-browser device verification. Real-device evidence required: yes.

Planned files: `supabase/tests/events_booking.sql`, `supabase/tests/events_invitation_codes.sql`, `supabase/tests/events_admission.sql`, `supabase/tests/events_notifications.sql`, `supabase/tests/events_private_location.sql`, `scripts/supabase-smoke-test.mjs`, `scripts/events-concurrency.test.mjs`, `events-web/tests/guest/manage-rsvp.spec.ts`, `WanderUITests/EventsAdmissionUITests.swift`, `docs/testing/events/booking-door-real-device.md`.

- Recognized confirmed guest cancels before start on app, App Clip and browser; full-app download is not required for no-app management.
- Successful cancellation releases the seat and refunds a consumed capped-code use once; code-free booking produces no allowance. Old QR and booking-based precise-location entitlement are invalid.
- After commit-response loss, repeat cancellation cannot refund twice; old approval/offer retries cannot revive it. A deliberate rebooking uses current capacity/code/approval/waitlist rules.
- Race cancellation, another guest spending the returned allowance and original guest rebooking in separate DB sessions; no retained claim or lost-generation retry can cancel the new booking.
- Preserve D31-protected released inventory. Cancellation confirmation-copy/extra prompt remains P03-proposed.

Source authority: C-NOAPP, D24, D31, engineering D11A; agreed / derived; confirmation copy P03 proposed

Adjacent existing evidence (not implemented Events coverage):
- `scripts/package.json:24` — Pinned pg client can support a new Node test harness with independent PostgreSQL connections. Adjacent evidence only; no Events test is implemented or passed.
- `project.yml:45` — Existing scheme includes WanderTests and WanderUITests; Events/App Clip and real-device evidence still have to be added. Adjacent evidence only; no Events test is implemented or passed.
- `scripts/supabase-smoke-test.mjs:1110` — Existing migration-preview / strict pgTAP rollback-only entry points can host planned Events contract checks. Adjacent evidence only; no Events test is implemented or passed.

## B14 — Guest attempts self-cancellation at/after event start, then simulate cancellation failure before start with a consumed invitation-code use.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment). Real-device evidence required: no.

Planned files: `supabase/tests/events_booking.sql`, `supabase/tests/events_invitation_codes.sql`, `scripts/supabase-smoke-test.mjs`, `events-web/tests/guest/manage-rsvp.spec.ts`.

- At and after current event start, self-cancellation is blocked; include boundary at the new start after an approved reschedule.
- Failure before start leaves booking, seat, code consumption and entitlement unchanged, with no canceled UI or extra allowance.
- Distinguish rejected mutation from unknown transport completion; unknown UI retries/resolves the same operation, not an untracked second cancellation.

Source authority: D24, engineering D11A; cutoff/refund agreed, failure presentation derived

Adjacent existing evidence (not implemented Events coverage):
- `scripts/supabase-smoke-test.mjs:1110` — Existing migration-preview / strict pgTAP rollback-only entry points can host planned Events contract checks. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/migrations/20260729123000_web_links_and_place_list_invites.sql:210` — Existing list invitation locks a specific row, not shared event capacity; Events races cannot be assumed solved by reuse. Adjacent evidence only; no Events test is implemented or passed.

## B15 — Operator reduces capacity below confirmed guests plus active offer holds; separately test changes to approval mode or offer duration after their policies are approved.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment), Node pg multi-session concurrency (isolated disposable database). Real-device evidence required: no.

Planned files: `supabase/tests/events_booking.sql`, `scripts/supabase-smoke-test.mjs`, `scripts/events-concurrency.test.mjs`, `events-web/tests/console/event-controls.spec.ts`.

- Reducing capacity below confirmed plus active unexpired holds fails without deleting or changing confirmations/offers; equality is allowed if otherwise valid.
- Race capacity reduction against confirmation/offer issuance under the same event lock; final committed commitments never exceed capacity.
- POLICY-GATED: approval-mode edits and changes to issued offer duration must acquire expected assertions only after P04/P11 policy approval; do not default those proposals to passing requirements.

Source authority: Engineering D4A capacity rule agreed; remaining P04/P11 change policies proposed

Adjacent existing evidence (not implemented Events coverage):
- `scripts/package.json:24` — Pinned pg client can support a new Node test harness with independent PostgreSQL connections. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/migrations/20260729123000_web_links_and_place_list_invites.sql:210` — Existing list invitation locks a specific row, not shared event capacity; Events races cannot be assumed solved by reuse. Adjacent evidence only; no Events test is implemented or passed.
- `scripts/supabase-smoke-test.mjs:1110` — Existing migration-preview / strict pgTAP rollback-only entry points can host planned Events contract checks. Adjacent evidence only; no Events test is implemented or passed.

## B16 — Move an upcoming event to a new future date after confirmation; repeat save, fail a save, open old links/ticket, inspect queued reminders, exported calendar and offline roster. Separately test event cancellation once approved.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment), Deno worker with fake clock/provider/network. Real-device evidence required: no.

Planned files: `supabase/tests/events_booking.sql`, `supabase/tests/events_publication.sql`, `supabase/tests/events_notifications.sql`, `supabase/tests/events_private_location.sql`, `scripts/supabase-smoke-test.mjs`, `supabase/functions/event-message-worker/index.test.ts`, `events-web/tests/guest/manage-rsvp.spec.ts`, `events-web/tests/console/event-controls.spec.ts`, `events-web/tests/console/offline-admission.spec.ts`.

- Reschedule an upcoming event to a future date: same event/canonical link, confirmed booking, seat and code use; canceled bookings remain canceled; issued offer deadline does not silently reset.
- Successful revision changes current event/ticket/relative home windows and schedules important-change messaging; allow pre-start cancellation against the current event start.
- Repeat the same revision / fail its transaction: no duplicate logical notice or notice for failed state. An old queued reminder cannot dispatch as current; delivery failure does not undo the edit.
- Old links fetch new state. Exported calendars, previously disclosed addresses and disconnected roster snapshots are explicitly not claimed to update/erase remotely.
- POLICY-GATED: event-wide cancellation, venue changes, completed-event edits, exact calendar payload and issued-offer edits remain separate proposals.

Source authority: Engineering D13A agreed / derived; P05 event cancellation/completed-event edits remain proposed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/notifications.sql:6` — Existing notification pgTAP suite provides transactional notification fixture patterns. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/functions/push-notification-worker/index.test.ts:50` — Existing Deno test injects fetch and records request/collapse IDs and provider acknowledgement. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/notifications.sql:892` — Existing push suite exercises stale claim rejection; Events message dispatch needs its own revision/eligibility checks. Adjacent evidence only; no Events test is implemented or passed.

## M01 — Successful confirmed RSVP without full app.

Owner: shared-messaging-foundation. Layers: local pgTAP, planned hosted rollback smoke, Deno worker with fake clock/provider/network, Playwright stubbed UI, Playwright API-backed integration (isolated test environment). Real-device evidence required: no.

Planned files: `supabase/tests/events_notifications.sql`, `scripts/supabase-smoke-test.mjs`, `supabase/functions/event-message-worker/index.test.ts`, `events-web/tests/guest/message-recovery.spec.ts`.

- Successful confirmed RSVP without full app atomically enqueues exactly one logical confirmation SMS for the verified event phone and canonical View event link.
- No confirmed message on uncommitted/failed RSVP or nonconfirmed state; no push registration/permission/install requirement for confirmation.
- Use an allowlisted fake SMS transport and inspect payload/outbox records; queued/API-accepted is not delivered, read or attended. Never send a real text during these tests.

Source authority: D19, D29, N1-LINK; agreed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/notifications.sql:6` — Existing notification pgTAP suite provides transactional notification fixture patterns. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/functions/push-notification-worker/index.test.ts:50` — Existing Deno test injects fetch and records request/collapse IDs and provider acknowledgement. Adjacent evidence only; no Events test is implemented or passed.

## M02 — Pending, waitlisted or offered state without confirmation.

Owner: shared-messaging-foundation. Layers: local pgTAP, planned hosted rollback smoke, Deno worker with fake clock/provider/network, Playwright stubbed UI, Playwright API-backed integration (isolated test environment). Real-device evidence required: no.

Planned files: `supabase/tests/events_notifications.sql`, `supabase/tests/events_authorization.sql`, `scripts/supabase-smoke-test.mjs`, `supabase/functions/event-message-worker/index.test.ts`, `events-web/tests/guest/message-recovery.spec.ts`.

- Pending, waitlisted and offered fixtures cannot receive a confirmation template, confirmed-only guest list or 24h precise-address entitlement.
- Any configured state-specific message is derived from current committed state; offer message explains acceptance without accepting merely on open.
- Anonymous/wrong-account delivery-link opens do not transfer the recipient entitlement or expose their private phone/booking.

Source authority: D21–D23, D29; agreed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/notifications.sql:6` — Existing notification pgTAP suite provides transactional notification fixture patterns. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/clerk_identity_continuity.sql:7` — Existing tests inspect security mode, search_path and authenticated canonical-identity resolution. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/rls_visibility.sql:7` — Existing fixtures distinguish owner, follower, mutual, nonfollower and blocked viewers. Adjacent evidence only; no Events test is implemented or passed.

## M03 — Confirmed guest reaches event start minus 24h, then minus 2h.

Owner: shared-messaging-foundation. Layers: local pgTAP, planned hosted rollback smoke, Deno worker with fake clock/provider/network. Real-device evidence required: no.

Planned files: `supabase/tests/events_notifications.sql`, `scripts/supabase-smoke-test.mjs`, `supabase/functions/event-message-worker/index.test.ts`.

- Control scheduler time immediately before, at and after start-minus-24h and start-minus-2h; each agreed reminder produces one logical send for the still-confirmed eligible account.
- Repeat scheduler claims with independent workers and verify same message identity/channel uniqueness; use current event revision and canonical link, including a rescheduled event.
- No full-app installation dependency for SMS; future-marketing preference is not reused as the event-message gate.

Source authority: D29; cadence agreed, idempotence derived

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/notifications.sql:6` — Existing notification pgTAP suite provides transactional notification fixture patterns. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/notifications.sql:892` — Existing push suite exercises stale claim rejection; Events message dispatch needs its own revision/eligibility checks. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/functions/push-notification-worker/index.test.ts:50` — Existing Deno test injects fetch and records request/collapse IDs and provider acknowledgement. Adjacent evidence only; no Events test is implemented or passed.

## M04 — Confirm only after one/both reminder times passed.

Owner: shared-messaging-foundation. Layers: local pgTAP, planned hosted rollback smoke, Deno worker with fake clock/provider/network. Real-device evidence required: no.

Planned files: `supabase/tests/events_notifications.sql`, `scripts/supabase-smoke-test.mjs`, `supabase/functions/event-message-worker/index.test.ts`.

- POLICY-GATED P10: once late-reminder policy is reviewed, parameterize RSVP before both, between, and after both scheduled reminders.
- Confirmation remains the approved success trigger; proposed skip-elapsed / only-remaining behavior must be tagged pending policy, not silently implemented as an approved schedule.
- Use fake clock and compare message identities/due times; no wall-clock sleeps or real SMS.

Source authority: P10 proposed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/notifications.sql:6` — Existing notification pgTAP suite provides transactional notification fixture patterns. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/functions/push-notification-worker/index.test.ts:50` — Existing Deno test injects fetch and records request/collapse IDs and provider acknowledgement. Adjacent evidence only; no Events test is implemented or passed.

## M05 — Important event change is published, including an upcoming-event reschedule; retry the same revision and inspect reminders from the prior schedule.

Owner: shared-messaging-foundation. Layers: local pgTAP, planned hosted rollback smoke, Deno worker with fake clock/provider/network, Playwright stubbed UI, Playwright API-backed integration (isolated test environment). Real-device evidence required: no.

Planned files: `supabase/tests/events_notifications.sql`, `supabase/tests/events_publication.sql`, `scripts/supabase-smoke-test.mjs`, `supabase/functions/event-message-worker/index.test.ts`, `events-web/tests/guest/message-recovery.spec.ts`, `events-web/tests/console/event-controls.spec.ts`.

- Publish a reschedule and retry the identical revision: affected confirmed guests get one logical important-change notice and current management/cancellation link without reconfirming.
- Failed publish enqueues no notice. Worker rechecks current revision/recipient eligibility so an obsolete queued reminder cannot falsely report the old schedule as current.
- A provider delivery failure does not roll back the event update or make canonical event details disappear; UI exposes actual current state independently.
- Exact provider retry/fallback cadence remains proposed; test selected mechanics only after contract review.

Source authority: D29, engineering D13A; agreed / derived; provider retry mechanics remain proposed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/notifications.sql:6` — Existing notification pgTAP suite provides transactional notification fixture patterns. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/functions/push-notification-worker/index.ts:149` — Existing worker settles results using event and claim token, providing a seam to assess rather than proof of Events reliability. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/notifications.sql:892` — Existing push suite exercises stale claim rejection; Events message dispatch needs its own revision/eligibility checks. Adjacent evidence only; no Events test is implemented or passed.

## M06 — Event ends but recap is unpublished; later publish succeeds.

Owner: after-event-map. Layers: local pgTAP, planned hosted rollback smoke, Deno worker with fake clock/provider/network. Real-device evidence required: no.

Planned files: `supabase/tests/events_notifications.sql`, `supabase/tests/events_publication.sql`, `supabase/tests/events_admission.sql`, `scripts/supabase-smoke-test.mjs`, `supabase/functions/event-message-worker/index.test.ts`.

- Event end alone or failed/unpublished recap creates no recap-ready invitation.
- Successful publication targets valid server-admitted guests for content/check-in invitation; RSVP-only/no-show or locally queued offline admission does not qualify.
- Repeated publish/reconcile creates one logical owed invitation; full protected recap still requires explicit historical completion, not receipt of the invite.
- Trigger ownership is after-event-map; all delivery uses the shared foundation and its fake-provider tests.

Source authority: D5, D26, D29, N1-PROGRAM; agreed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/notifications.sql:6` — Existing notification pgTAP suite provides transactional notification fixture patterns. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/functions/push-notification-worker/index.test.ts:50` — Existing Deno test injects fetch and records request/collapse IDs and provider acknowledgement. Adjacent evidence only; no Events test is implemented or passed.
- `scripts/supabase-smoke-test.mjs:1110` — Existing migration-preview / strict pgTAP rollback-only entry points can host planned Events contract checks. Adjacent evidence only; no Events test is implemented or passed.

## M07 — Native notifications allowed; repeat with denied/not asked/disabled permission or invalid push token.

Owner: shared-messaging-foundation. Layers: local pgTAP, planned hosted rollback smoke, Deno worker with fake clock/provider/network, native XCTest / XCUITest, real iPhone / intended staff-browser device verification. Real-device evidence required: yes.

Planned files: `supabase/tests/events_notifications.sql`, `scripts/supabase-smoke-test.mjs`, `supabase/functions/push-notification-worker/events.test.ts`, `supabase/functions/event-message-worker/index.test.ts`, `WanderUITests/EventsMessageReturnUITests.swift`, `docs/testing/events/booking-door-real-device.md`.

- On real iPhone exercise allowed, denied, not-yet-asked, later-disabled notification settings and invalid/removed token fixtures.
- Optional value explanation precedes native permission request; denial/unavailable push never blocks RSVP, QR or eligible recap. Event SMS has its own eligibility.
- Invalid-token treatment does not revoke account/booking or disable unrelated valid devices; accepted provider status does not claim delivery/read.
- POLICY-GATED: exact push schedule or additional cross-channel fallback is not chosen by these invariants. App Clip permission is not proof of the full long-lived message program.

Source authority: N1-PROGRAM, R129, D19; agreed invariant, cadence/fallback proposed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/functions/push-notification-worker/index.test.ts:23` — Existing Deno tests classify APNs permanent-token, permanent-event and retryable failures. Adjacent evidence only; no Events test is implemented or passed.
- `project.yml:45` — Existing scheme includes WanderTests and WanderUITests; Events/App Clip and real-device evidence still have to be added. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/notifications.sql:837` — Existing push settlement tests assert one accepted token does not hide another token retry; Events SMS and door queues need their own coverage. Adjacent evidence only; no Events test is implemented or passed.

## M08 — SMS future-event opt-in unchecked; repeat with event-SMS opt-out.

Owner: shared-messaging-foundation. Layers: local pgTAP, planned hosted rollback smoke, Deno worker with fake clock/provider/network, Playwright stubbed UI, Playwright API-backed integration (isolated test environment). Real-device evidence required: no.

Planned files: `supabase/tests/events_notifications.sql`, `supabase/tests/events_authorization.sql`, `scripts/supabase-smoke-test.mjs`, `supabase/functions/event-message-worker/index.test.ts`, `events-web/tests/guest/message-recovery.spec.ts`.

- Unchecked future-event marketing choice prevents marketing enrollment/send while preserving approved event-program enrollment and booking.
- POLICY-GATED P10 opt-out mechanics: after selection, opted-out event messages must stay suppressed without canceling the RSVP; no push-failure fallback silently overrides that choice.
- Recheck channel eligibility at dispatch and reject client attempts to mutate another account consent; no phone/consent data in public event projection or analytics.
- Test an already-queued message versus consent change with fake transport; concrete STOP/provider response semantics remain dependent on selected provider/policy.

Source authority: D19; distinction agreed, P10 opt-out mechanics proposed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/notifications.sql:6` — Existing notification pgTAP suite provides transactional notification fixture patterns. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/functions/push-notification-worker/index.test.ts:119` — Existing analytics test excludes recipient and notification content; Events must add its own sensitive-field fixtures. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/rls_visibility.sql:7` — Existing fixtures distinguish owner, follower, mutual, nonfollower and blocked viewers. Adjacent evidence only; no Events test is implemented or passed.

## M09 — Same trigger replayed, worker retries, delivery callback duplicated, or push failure after SMS already sent.

Owner: shared-messaging-foundation. Layers: local pgTAP, planned hosted rollback smoke, Deno worker with fake clock/provider/network, Node pg multi-session concurrency (isolated disposable database). Real-device evidence required: no.

Planned files: `supabase/tests/events_notifications.sql`, `scripts/supabase-smoke-test.mjs`, `supabase/functions/event-message-worker/index.test.ts`, `supabase/functions/push-notification-worker/events.test.ts`, `scripts/events-concurrency.test.mjs`.

- Replay trigger, concurrent claims, duplicated callbacks, lease expiry and worker crash: retain one intended logical message/channel and reject stale claim settlements.
- Mixed batch includes provider-accepted, retryable, permanently invalid and unknown transport results; persist per-recipient/channel outcome and do not resend accepted successes when retrying failures.
- Provider accepted request but acknowledgement/DB settlement is lost: preserve unknown outcome and resolve using the chosen provider idempotency/status contract; do not claim exactly-once physical delivery or blindly create a second SMS.
- Push failure after planned SMS does not add another SMS. queued, submitted/sent, provider-confirmed-delivered, failed and unknown remain distinct; retry/fallback schedule is POLICY-GATED.

Source authority: D26/D29 consistency; retry/fallback proposed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/notifications.sql:837` — Existing push settlement tests assert one accepted token does not hide another token retry; Events SMS and door queues need their own coverage. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/notifications.sql:892` — Existing push suite exercises stale claim rejection; Events message dispatch needs its own revision/eligibility checks. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/functions/push-notification-worker/index.test.ts:50` — Existing Deno test injects fetch and records request/collapse IDs and provider acknowledgement. Adjacent evidence only; no Events test is implemented or passed.
- `scripts/package.json:24` — Pinned pg client can support a new Node test harness with independent PostgreSQL connections. Adjacent evidence only; no Events test is implemented or passed.

## M10 — SMS delivery fails/no service, notifications unavailable, or recipient never opens messages.

Owner: shared-messaging-foundation. Layers: Deno worker with fake clock/provider/network, Playwright stubbed UI, Playwright API-backed integration (isolated test environment), native XCTest / XCUITest. Real-device evidence required: no.

Planned files: `supabase/functions/event-message-worker/index.test.ts`, `events-web/tests/guest/message-recovery.spec.ts`, `WanderUITests/EventsMessageReturnUITests.swift`.

- Fake SMS outage/permanent failure, no usable push and never-opened messages leave canonical event and existing booking available in browser and Events.
- Required later app/QR and check-in actions remain discoverable without a notification; no message read, delivery or attendance claim follows from queueing or API acceptance.
- Timeout/unknown message status does not create another reservation, require a repeat signup or hide the changed event.

Source authority: N1-PROGRAM; derived resilience

Adjacent existing evidence (not implemented Events coverage):
- `supabase/functions/push-notification-worker/index.test.ts:23` — Existing Deno tests classify APNs permanent-token, permanent-event and retryable failures. Adjacent evidence only; no Events test is implemented or passed.
- `project.yml:45` — Existing scheme includes WanderTests and WanderUITests; Events/App Clip and real-device evidence still have to be added. Adjacent evidence only; no Events test is implemented or passed.

## M11 — Booking canceled/revoked or event canceled before scheduled reminder; clock advances.

Owner: shared-messaging-foundation. Layers: local pgTAP, planned hosted rollback smoke, Deno worker with fake clock/provider/network. Real-device evidence required: no.

Planned files: `supabase/tests/events_notifications.sql`, `supabase/tests/events_admission.sql`, `scripts/supabase-smoke-test.mjs`, `supabase/functions/event-message-worker/index.test.ts`.

- Canceled/revoked booking cannot be rendered in an outgoing message as presently confirmed/ready to enter; verify current state immediately before dispatch.
- POLICY-GATED P05/P10: precise suppression and state-change schedule for event-wide cancellation remain unapproved; add expected sends only after selection.
- Use concurrent cancellation versus worker claim to ensure stale queued claims do not restore booking rights; an already externally delivered message cannot be retracted, so its link must resolve current state.

Source authority: D24, P05/P10; proposed suppression, state accuracy derived

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/notifications.sql:892` — Existing push suite exercises stale claim rejection; Events message dispatch needs its own revision/eligibility checks. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/functions/push-notification-worker/index.ts:149` — Existing worker settles results using event and claim token, providing a seam to assess rather than proof of Events reliability. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/notifications.sql:6` — Existing notification pgTAP suite provides transactional notification fixture patterns. Adjacent evidence only; no Events test is implemented or passed.

## M12 — Operator changes template/timing, previews and publishes; then invalid edit/save failure.

Owner: shared-messaging-foundation. Layers: local pgTAP, planned hosted rollback smoke, Deno worker with fake clock/provider/network, Playwright stubbed UI, Playwright API-backed integration (isolated test environment). Real-device evidence required: no.

Planned files: `supabase/tests/events_notifications.sql`, `supabase/tests/events_authorization.sql`, `supabase/tests/events_private_location.sql`, `scripts/supabase-smoke-test.mjs`, `supabase/functions/event-message-worker/index.test.ts`, `events-web/tests/console/event-controls.spec.ts`.

- Two authorized Team admins can edit content/timing; ordinary, signed-out and revoked callers cannot write templates or inspect private preview recipients via direct API.
- Preview configured recipient states and inspect HTML/accessibility tree/network payload as well as visible copy: no exact home location, private recap content, phone or other guest data outside authorization.
- Successful relevant change affects appropriate future sends; failed save does not show success or dispatch a message.
- POLICY-GATED P09/P19: exact draft/preview/publish procedure and schedule fallback are not adopted by this test mapping.

Source authority: D29, N2-CONSOLE; controls agreed, publish mechanics proposed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/clerk_identity_continuity.sql:7` — Existing tests inspect security mode, search_path and authenticated canonical-identity resolution. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/functions/push-notification-worker/index.test.ts:119` — Existing analytics test excludes recipient and notification content; Events must add its own sensitive-field fixtures. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/rls_visibility.sql:7` — Existing fixtures distinguish owner, follower, mutual, nonfollower and blocked viewers. Adjacent evidence only; no Events test is implemented or passed.

## M13 — App deleted after attendance; recap SMS opened; reinstall completed.

Owner: entry-and-identity. Layers: Playwright stubbed UI, Playwright API-backed integration (isolated test environment), native XCTest / XCUITest, real iPhone / intended staff-browser device verification. Real-device evidence required: yes.

Planned files: `events-web/tests/guest/message-recovery.spec.ts`, `WanderUITests/EventsMessageReturnUITests.swift`, `docs/testing/events/booking-door-real-device.md`.

- On physical iPhone admit guest, remove full app, open canonical recap link from a controlled test-message route, then reinstall/open and authenticate original account.
- Clip/browser shows appropriate event and app handoff for check-in/upload, without claiming push delivery to removed installation or offering browser completion.
- Recover server admission/completion; never duplicate booking or visit. Completed guest returns directly to eligible recap; incomplete guest still needs explicit check-in.
- API-backed web test proves server state; device evidence must separately prove OS link/uninstall/reinstall behavior. No real SMS is sent in this review.

Source authority: N1-POST, D5/D33; agreed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/clerk_identity_continuity.sql:7` — Existing tests inspect security mode, search_path and authenticated canonical-identity resolution. Adjacent evidence only; no Events test is implemented or passed.
- `project.yml:45` — Existing scheme includes WanderTests and WanderUITests; Events/App Clip and real-device evidence still have to be added. Adjacent evidence only; no Events test is implemented or passed.

## M14 — Staff corrects a missed admission after recap publication, then repeats correction.

Owner: after-event-map. Layers: local pgTAP, planned hosted rollback smoke, Deno worker with fake clock/provider/network, Playwright stubbed UI, Playwright API-backed integration (isolated test environment). Real-device evidence required: no.

Planned files: `supabase/tests/events_admission.sql`, `supabase/tests/events_notifications.sql`, `scripts/supabase-smoke-test.mjs`, `supabase/functions/event-message-worker/index.test.ts`, `events-web/tests/console/admission.spec.ts`.

- Authorized correction after recap publication creates canonical admission and correct eligibility without personal post, visit or completion.
- Repeated correction and lost-response retry create no duplicate admission or logical owed invitation; pending offline correction alone does not qualify.
- POLICY-GATED: exact late-invitation send procedure still requires review; test agreed eligibility now and activate its specific delivery assertions only after selection.

Source authority: D5, D26; eligibility agreed, late-send procedure proposed

Adjacent existing evidence (not implemented Events coverage):
- `scripts/supabase-smoke-test.mjs:1110` — Existing migration-preview / strict pgTAP rollback-only entry points can host planned Events contract checks. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/notifications.sql:6` — Existing notification pgTAP suite provides transactional notification fixture patterns. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/functions/push-notification-worker/index.ts:149` — Existing worker settles results using event and claim token, providing a seam to assess rather than proof of Events reliability. Adjacent evidence only; no Events test is implemented or passed.

## A01 — Valid confirmed full-app guest, valid name/username, optional photo absent; staff scans QR.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment), native XCTest / XCUITest, real iPhone / intended staff-browser device verification. Real-device evidence required: yes.

Planned files: `supabase/tests/events_admission.sql`, `supabase/tests/events_authorization.sql`, `scripts/supabase-smoke-test.mjs`, `events-web/tests/console/admission.spec.ts`, `WanderUITests/EventsAdmissionUITests.swift`, `docs/testing/events/booking-door-real-device.md`.

- Scan confirmed full-app guest with valid name/username and no profile photo using authenticated web console on intended staff device.
- Assert exactly one correct event/account canonical admission and actor attribution; no automatic place visit, Been status, personal post or historical completion.
- Shared/native state fixtures and API reject missing setup/confirmation; optional photo absence does not become an entry gate.
- Verify actual camera/QR readability and full-app-to-scanner flow on physical hardware, not only mocked browser camera input.

Source authority: D5, N2-SETUP, N2-CONSOLE; agreed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/clerk_identity_continuity.sql:7` — Existing tests inspect security mode, search_path and authenticated canonical-identity resolution. Adjacent evidence only; no Events test is implemented or passed.
- `project.yml:45` — Existing scheme includes WanderTests and WanderUITests; Events/App Clip and real-device evidence still have to be added. Adjacent evidence only; no Events test is implemented or passed.
- `scripts/supabase-smoke-test.mjs:1110` — Existing migration-preview / strict pgTAP rollback-only entry points can host planned Events contract checks. Adjacent evidence only; no Events test is implemented or passed.

## A02 — Full app absent or phone unsupported; user requests QR/entry.

Owner: before-event-door. Layers: Playwright stubbed UI, Playwright API-backed integration (isolated test environment), native XCTest / XCUITest, real iPhone / intended staff-browser device verification. Real-device evidence required: yes.

Planned files: `events-web/tests/guest/rsvp.spec.ts`, `events-web/tests/console/admission.spec.ts`, `WanderUITests/EventsAdmissionUITests.swift`, `docs/testing/events/booking-door-real-device.md`.

- Full app absent or unsupported guest device shows the supported phone/app entry requirement and correct Open/Get Astir action.
- Browser/Clip RSVP confirmation and same-surface management remain possible where supported, but browser-only admission/QR bypass is not invented.
- Verify real app-installed/not-installed routing separately from test fixture simulation; denial retains the guest event/booking context.

Source authority: D15; agreed

Adjacent existing evidence (not implemented Events coverage):
- `project.yml:45` — Existing scheme includes WanderTests and WanderUITests; Events/App Clip and real-device evidence still have to be added. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/clerk_identity_continuity.sql:7` — Existing tests inspect security mode, search_path and authenticated canonical-identity resolution. Adjacent evidence only; no Events test is implemented or passed.

## A03 — Installed app, valid confirmed booking, QR fails to load; staff performs verified lookup.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment), native XCTest / XCUITest, real iPhone / intended staff-browser device verification. Real-device evidence required: yes.

Planned files: `supabase/tests/events_admission.sql`, `supabase/tests/events_authorization.sql`, `scripts/supabase-smoke-test.mjs`, `events-web/tests/console/admission.spec.ts`, `WanderUITests/EventsAdmissionUITests.swift`, `docs/testing/events/booking-door-real-device.md`.

- With installed app and completed valid account/confirmed booking, force QR-load failure and perform verified staff lookup/admission.
- Fallback authorizes the same canonical booking after account/app checks; QR-load failure itself, name match or phone string does not prove eligibility.
- Pending/waitlisted, wrong account and incomplete setup cannot enter through the fallback. Recovery produces no replacement RSVP or personal visit.
- Physical rehearsal must demonstrate how the approved installed-app/account checks are performed; no new staff role/device exemption.

Source authority: D25, N2-SETUP; agreed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/clerk_identity_continuity.sql:7` — Existing tests inspect security mode, search_path and authenticated canonical-identity resolution. Adjacent evidence only; no Events test is implemented or passed.
- `project.yml:45` — Existing scheme includes WanderTests and WanderUITests; Events/App Clip and real-device evidence still have to be added. Adjacent evidence only; no Events test is implemented or passed.
- `scripts/supabase-smoke-test.mjs:1110` — Existing migration-preview / strict pgTAP rollback-only entry points can host planned Events contract checks. Adjacent evidence only; no Events test is implemented or passed.

## A04 — Online lookup finds wrong-event, canceled, expired/ineligible credential, no-match or ambiguous identity; repeat with a known invalid/missing offline roster entry.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment). Real-device evidence required: no.

Planned files: `supabase/tests/events_admission.sql`, `supabase/tests/events_authorization.sql`, `scripts/supabase-smoke-test.mjs`, `events-web/tests/console/admission.spec.ts`, `events-web/tests/console/offline-admission.spec.ts`.

- Direct online requests for wrong event/account, canceled/ineligible credential, ambiguous/no lookup result cannot create admission or reveal protected data.
- Known invalid or missing downloaded roster entry cannot be fabricated as confirmed during an outage; no offline signup.
- An old snapshot that really contains a matching confirmed entry follows D9 pending reconciliation, not false current server success; test separately from known-invalid state.
- Distinguish permission denial, unauthenticated, lookup failure and genuinely no match; do not reinterpret all as QR-loading fallback.

Source authority: D5/D25, engineering D9B; derived

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/clerk_identity_continuity.sql:7` — Existing tests inspect security mode, search_path and authenticated canonical-identity resolution. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/rls_visibility.sql:7` — Existing fixtures distinguish owner, follower, mutual, nonfollower and blocked viewers. Adjacent evidence only; no Events test is implemented or passed.
- `scripts/supabase-smoke-test.mjs:1110` — Existing migration-preview / strict pgTAP rollback-only entry points can host planned Events contract checks. Adjacent evidence only; no Events test is implemented or passed.

## A05 — Same QR scanned twice or same manual admission replayed.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment), Node pg multi-session concurrency (isolated disposable database). Real-device evidence required: no.

Planned files: `supabase/tests/events_admission.sql`, `supabase/tests/events_notifications.sql`, `scripts/supabase-smoke-test.mjs`, `scripts/events-concurrency.test.mjs`, `events-web/tests/console/admission.spec.ts`.

- Repeat same scan/manual mutation and contend distinct operation IDs for the same guest/event in separate sessions: one canonical admission with existing-result response.
- Lost committed response retry creates no extra admission, attendance-dependent invitation or personal visit.
- Operator sees previous admission without claiming a second unique attendee. Physical reentry treatment remains P15 POLICY-GATED; no staff-lead role is added.

Source authority: D5/D25, engineering D7/D9B; idempotence derived, P15 reentry proposed

Adjacent existing evidence (not implemented Events coverage):
- `scripts/package.json:24` — Pinned pg client can support a new Node test harness with independent PostgreSQL connections. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/notifications.sql:6` — Existing notification pgTAP suite provides transactional notification fixture patterns. Adjacent evidence only; no Events test is implemented or passed.
- `scripts/supabase-smoke-test.mjs:1110` — Existing migration-preview / strict pgTAP rollback-only entry points can host planned Events contract checks. Adjacent evidence only; no Events test is implemented or passed.

## A06 — Staff later corrects missed admission or revokes mistaken admission.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment). Real-device evidence required: no.

Planned files: `supabase/tests/events_admission.sql`, `supabase/tests/events_authorization.sql`, `supabase/tests/events_notifications.sql`, `scripts/supabase-smoke-test.mjs`, `events-web/tests/console/admission.spec.ts`.

- Authorized missed-admission correction changes admission/recap eligibility without creating/deleting the personal check-in, completion or independent place history.
- POLICY-GATED P15: detailed revocation procedure awaits review. Once revoked under a selected procedure, protected recap authorization must not persist through API or stale UI/cache.
- Preserve actor attribution, idempotent correction and distinction among booking, admission and completion.

Source authority: D5, P15; approved correction, revocation details proposed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/rls_visibility.sql:7` — Existing fixtures distinguish owner, follower, mutual, nonfollower and blocked viewers. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/checkin_history_engagement.sql:68` — Existing history repair is tested for idempotence and preservation of historical activity; Events must extend canonical-history regression coverage. Adjacent evidence only; no Events test is implemented or passed.
- `scripts/supabase-smoke-test.mjs:1110` — Existing migration-preview / strict pgTAP rollback-only entry points can host planned Events contract checks. Adjacent evidence only; no Events test is implemented or passed.

## A07 — Unauthorized viewer, expired Team admin session or revoked team membership calls a console API; separately, connection fails during Admit.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment). Real-device evidence required: no.

Planned files: `supabase/tests/events_admission.sql`, `supabase/tests/events_authorization.sql`, `scripts/supabase-smoke-test.mjs`, `events-web/tests/console/admission.spec.ts`, `events-web/tests/console/authorization.spec.ts`.

- Signed-out, expired-session, ordinary-account and revoked Team admin direct API calls fail protected server reads/mutations; both active Team admins can operate all console functions.
- Connection loss after Admit commit leaves an unknown/reconciling state; resolve the same stable operation identity/current admission before attempting another logical admission.
- Prepared offline roster may not know remote revocation while disconnected; on reconnect require current authorized account and preserve unresolved work without bypassing rights.
- Unknown/403 outcomes must not display confirmed success or be flattened into a misleading no-booking state.

Source authority: N2-CONSOLE, engineering D7/D9B; agreed / derived

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/clerk_identity_continuity.sql:7` — Existing tests inspect security mode, search_path and authenticated canonical-identity resolution. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/rls_visibility.sql:7` — Existing fixtures distinguish owner, follower, mutual, nonfollower and blocked viewers. Adjacent evidence only; no Events test is implemented or passed.
- `scripts/supabase-smoke-test.mjs:1110` — Existing migration-preview / strict pgTAP rollback-only entry points can host planned Events contract checks. Adjacent evidence only; no Events test is implemented or passed.

## A08 — Prepare roster online as a Team admin; disconnect, match guest/account/app, record entry, reload the console, then reconnect.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment), native XCTest / XCUITest, real iPhone / intended staff-browser device verification. Real-device evidence required: yes.

Planned files: `supabase/tests/events_admission.sql`, `supabase/tests/events_authorization.sql`, `supabase/tests/events_notifications.sql`, `scripts/supabase-smoke-test.mjs`, `events-web/tests/console/admission.spec.ts`, `events-web/tests/console/offline-admission.spec.ts`, `WanderUITests/EventsAdmissionUITests.swift`, `docs/testing/events/booking-door-real-device.md`.

- Online authorized admin downloads one complete versioned account/event roster with visible last-sync; it contains only required identification/booking data, no unrelated feedback/gallery/exact private-venue fields.
- Disconnect, match valid guest/account/app, persist stable operation and roster version BEFORE showing Admitted offline · awaiting sync; reload preserves queue and local same-device deduplication.
- Before server reconciliation, attendee cannot gain check-in eligibility or protected recap. Reconnect validates current server rules and creates exactly one canonical admission.
- After reconciliation, normal historical-completion gate still applies and no personal visit is created by admission. Verify reload/offline persistence and scanner lifecycle on actual intended staff browsers.

Source authority: Engineering D9B; agreed / derived

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/clerk_identity_continuity.sql:7` — Existing tests inspect security mode, search_path and authenticated canonical-identity resolution. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/notifications.sql:6` — Existing notification pgTAP suite provides transactional notification fixture patterns. Adjacent evidence only; no Events test is implemented or passed.
- `project.yml:45` — Existing scheme includes WanderTests and WanderUITests; Events/App Clip and real-device evidence still have to be added. Adjacent evidence only; no Events test is implemented or passed.

## A09 — After roster download, cancel a guest booking, change the event or revoke the admin; record from the stale offline roster and reconnect.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment), real iPhone / intended staff-browser device verification. Real-device evidence required: yes.

Planned files: `supabase/tests/events_admission.sql`, `supabase/tests/events_authorization.sql`, `scripts/supabase-smoke-test.mjs`, `events-web/tests/console/offline-admission.spec.ts`, `docs/testing/events/booking-door-real-device.md`.

- Download confirmed roster, then change/cancel booking, reschedule event or revoke acting admin in the isolated test backend while device is offline.
- Offline UI identifies snapshot/last-sync and queued status, not current truth. Reconnect rechecks current event/booking/team rights and reports each conflict without restoring old entitlement.
- Invalid or denied queue rows stay unresolved for an authorized Team admin; do not silently discard them or grant recap from client timestamps.
- Do not promise immediate remote cache erasure or schedule updates during total disconnection; no cross-account roster exposure during recovery.

Source authority: Engineering D7/D9B; agreed / derived

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/clerk_identity_continuity.sql:7` — Existing tests inspect security mode, search_path and authenticated canonical-identity resolution. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/rls_visibility.sql:7` — Existing fixtures distinguish owner, follower, mutual, nonfollower and blocked viewers. Adjacent evidence only; no Events test is implemented or passed.
- `scripts/supabase-smoke-test.mjs:1110` — Existing migration-preview / strict pgTAP rollback-only entry points can host planned Events contract checks. Adjacent evidence only; no Events test is implemented or passed.

## A10 — Two offline devices record the same guest; synchronize a mixed batch of valid, duplicate and conflicting rows; lose a response after server commit and retry.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment), Node pg multi-session concurrency (isolated disposable database), real iPhone / intended staff-browser device verification. Real-device evidence required: yes.

Planned files: `supabase/tests/events_admission.sql`, `supabase/tests/events_notifications.sql`, `scripts/supabase-smoke-test.mjs`, `scripts/events-concurrency.test.mjs`, `events-web/tests/console/offline-admission.spec.ts`, `docs/testing/events/booking-door-real-device.md`.

- Use two separate offline browser/device stores to record same guest, plus valid and conflicting other guests; synchronize a mixed batch.
- Stable operation identity plus canonical event/guest uniqueness yields one admission and no duplicate downstream invitation; each response identifies its individual committed/duplicate/conflict/unknown result.
- Drop response after partial or full server commit and repeat the same batch: reconcile successes idempotently, retain unknown/unresolved rows, never mark entire queue synced after partial failure.
- Local device counts stay explicitly local; same-guest multi-device race is checked in separate DB sessions, then exercised on two intended staff devices.

Source authority: Engineering D9B; agreed / derived

Adjacent existing evidence (not implemented Events coverage):
- `scripts/package.json:24` — Pinned pg client can support a new Node test harness with independent PostgreSQL connections. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/notifications.sql:837` — Existing push settlement tests assert one accepted token does not hide another token retry; Events SMS and door queues need their own coverage. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/notifications.sql:6` — Existing notification pgTAP suite provides transactional notification fixture patterns. Adjacent evidence only; no Events test is implemented or passed.

## A11 — Interrupt roster refresh/local queue persistence; evict local data; update/reload the shell; sign out or switch accounts with unsynced entries.

Owner: before-event-door. Layers: Playwright stubbed UI, Playwright API-backed integration (isolated test environment), real iPhone / intended staff-browser device verification. Real-device evidence required: yes.

Planned files: `events-web/tests/console/offline-admission.spec.ts`, `events-web/tests/console/authorization.spec.ts`, `docs/testing/events/booking-door-real-device.md`.

- Interrupt paginated roster refresh and inject failed durable queue write/quota exceeded: previous complete snapshot survives and failed write never produces admitted-offline acknowledgement.
- Reload, close/reopen, update shell/service-worker version and interrupt synchronization: unsynced operations retain original IDs and account/event ownership within verified supported browser behavior.
- Evict local data before reopening offline: show roster/queue unavailable, never empty-success or synced. Document actual browser eviction/lifecycle behavior without claiming storage is guaranteed.
- Sign out/switch accounts with unsynced rows: make pending work/cleanup consequences explicit first, lock/remove protected access, and never expose or reassign the former account queue to the next account.
- Exact persistence technology/retention is implementation validation, not an approved TTL or a promise of remotely erasing an offline device.

Source authority: Engineering D9B; agreed / derived; exact persistence/retention mechanism requires validation

Adjacent existing evidence (not implemented Events coverage):
- `project.yml:45` — Existing scheme includes WanderTests and WanderUITests; Events/App Clip and real-device evidence still have to be added. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/clerk_identity_continuity.sql:7` — Existing tests inspect security mode, search_path and authenticated canonical-identity resolution. Adjacent evidence only; no Events test is implemented or passed.

## P01 — Valid attendee, recap published, no completed check-in, full app; open event.

Owner: After the event and on the map. Layers: XCTest unit/adapter, XCUITest, PostgreSQL pgTAP, hosted rollback pgTAP. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventCheckInTests.swift`, `WanderUITests/Events/EventRecapTests.swift`, `supabase/tests/events_recap_access.sql`.

- Given server-recorded valid admission, published recap and no completion, every app recap entry returns needs-check-in; no protected gallery/comment payload accompanies this state.
- Composer exposes this event’s configured tags, optional note/photos/private feedback and no public-rating input; tags from Event B never appear for Event A.
- Completion remains absent until explicit submit; opening the event or composer is not attendance or completion.

Source authority: D1–D2, N1-POST/TAGS; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/WanderStoreTests.swift:3889` — Ordinary Been save intentionally defaults a missing rating; retain that existing behavior while testing a separate Events path.
- `WanderTests/ActivityEngagementTests.swift:493` — Place-history engagement resolves the explicit visit before the parent conversation; Events recap conversation must stay distinct.

## P02 — Leave note, photos, optional tags, and private feedback empty; submit.

Owner: Events data and rules foundation; after-event shared-history integrator. Layers: XCTest unit/adapter, PostgreSQL pgTAP, hosted rollback pgTAP. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventCheckInTests.swift`, `WanderTests/Events/EventHistoryAdapterTests.swift`, `supabase/tests/events_completion_history.sql`.

- Submit every optional field absent: server commits exactly one historical completion and one event-labeled visit joined to Event A’s canonical place; venue rating remains null for this visit.
- Assert prior ordinary visit IDs, note, rating, audience, explicit save intent and aggregate rating are unchanged; never substitute the ordinary save path’s default rating.
- Server result and app adapter share the same visit ID; navigation resolves to the recap, not map. Inject visit-write failure and assert completion/visit transaction rolls back together.

Source authority: D2/D4/D34; agreed; optional new tag selection derived

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/place_visits_visit_photos.sql:629` — Database permits an explicit unrated visit. Contrast native ordinary Been default-rating behavior; no Events adapter exists.
- `WanderTests/WanderStoreTests.swift:3889` — Ordinary Been save intentionally defaults a missing rating; retain that existing behavior while testing a separate Events path.
- `supabase/tests/checkin_history_engagement.sql:63` — Adjacent regression pattern: idempotent history repair preserves visit timestamp and existing conversation; not Events coverage.

## P03 — Add own photos before submission.

Owner: After the event and on the map. Layers: XCTest unit/adapter, XCUITest, PostgreSQL pgTAP, hosted rollback pgTAP, isolated hosted HTTP/storage integration, physical-device verification. Real-device evidence required: yes.

Planned files: `WanderTests/Events/EventCheckInTests.swift`, `WanderUITests/Events/EventRecapTests.swift`, `supabase/tests/events_recap_access.sql`, `supabase/tests/events_media_references.sql`, `scripts/events/media-access-smoke.mjs`, `docs/testing/astir-events-device-matrix.md`.

- Select own local photos before completion; request protected shared-gallery metadata/bytes before submit and assert denial rather than merely hidden picker controls.
- On successful submit, server media IDs and stored bytes correspond to the selected files and the same event post/visit; no extra visit is created by attachment finalization.
- Exercise real Photos permission denial/cancel/select; canceled selection is not falsely saved. Failure recovery UI follows the reviewed policy, without claiming unuploaded selections succeeded.

Source authority: D6; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/WanderStoreTests.swift:8853` — Adjacent metadata-finalization failure test avoids reuploading already-stored photo bytes.
- `supabase/tests/visible_place_photo_gallery.sql:429` — Adjacent gallery RLS test excludes blocked contributors; does not implement admission/completion access.

## P04 — Add optional private 1–5 stars and/or private comment independently.

Owner: After the event and on the map. Layers: XCTest unit/adapter, PostgreSQL pgTAP, hosted rollback pgTAP. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventCheckInTests.swift`, `supabase/tests/events_completion_history.sql`, `supabase/tests/events_recap_access.sql`.

- Parameterize empty feedback, stars only, comment only and both; no default star is submitted.
- Verify only authorized Team admins can read private feedback; guest recap, personal post, activity, export/preview and ordinary visit responses contain neither private comment nor rating.
- Private stars never modify the event visit rating, prior venue rating, public attribute answers or public note; updating public content does not overwrite private feedback.

Source authority: D34, D2; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/WanderStoreTests.swift:3889` — Ordinary Been save intentionally defaults a missing rating; retain that existing behavior while testing a separate Events path.
- `supabase/tests/rls_visibility.sql:112` — Role/JWT-switched tests verify relationship, blocked-viewer and profile-shell visibility.

## P05 — Submit twice, lose response, force-close, or fail media upload.

Owner: After the event and on the map. Layers: XCTest unit/adapter, PostgreSQL pgTAP, hosted rollback pgTAP, Deno handler/worker tests, isolated hosted HTTP/storage integration, physical-device verification. Real-device evidence required: yes.

Planned files: `WanderTests/Events/EventCheckInTests.swift`, `WanderTests/Events/EventHistoryAdapterTests.swift`, `supabase/tests/events_completion_history.sql`, `supabase/tests/events_media_references.sql`, `supabase/functions/events-media/handler.test.ts`, `supabase/functions/events-media-worker/index.test.ts`, `scripts/events/media-access-smoke.mjs`, `docs/testing/astir-events-device-matrix.md`.

- Repeat the same operation after double tap, lost committed response, process termination and concurrent retry: query one completion and one canonical visit with the same IDs; no duplicate public activity.
- Fail before commit, during upload, after byte storage and before metadata finalization; preserve submitted media intent and distinguish acknowledged content from pending/failed content.
- Retry uses stable operation/source identities; neither upload retries nor restored drafts duplicate attachment rows/bytes or create another visit. Exact retry versus explicit-omission interaction remains a P06 proposal until reviewed.

Source authority: D4; identity consistency derived, P06 proposed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/WanderStoreTests.swift:8853` — Adjacent metadata-finalization failure test avoids reuploading already-stored photo bytes.
- `supabase/tests/checkin_history_engagement.sql:63` — Adjacent regression pattern: idempotent history repair preserves visit timestamp and existing conversation; not Events coverage.

## P06 — Completed attendee opens recap again, including after deleting personal post.

Owner: After the event and on the map. Layers: XCTest unit/adapter, PostgreSQL pgTAP, hosted rollback pgTAP, XCUITest. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventHistoryAdapterTests.swift`, `WanderUITests/Events/EventRecapTests.swift`, `supabase/tests/events_completion_history.sql`, `supabase/tests/events_recap_access.sql`.

- A valid admitted/completed account reopens directly to recap before and after deleting its personal post; absence of a post/visit does not erase historical completion.
- Attempt a second required-completion mutation and assert it does not create a replacement event visit merely because the original post was deleted.
- Revoke admission separately and verify current recap eligibility changes without conflating it with post deletion.

Source authority: D33; agreed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/checkin_history_engagement.sql:99` — Adjacent owner-deletion test verifies history removal and no resurrection through repair; not Events coverage.
- `WanderTests/ActivityEngagementTests.swift:944` — Adjacent failure evicts previously visible activity; Events access must independently revalidate and clear protected projections.

## P07 — Confirmed no-show or unknown admission opens published recap; self-reports attendance.

Owner: After the event and on the map. Layers: PostgreSQL pgTAP, hosted rollback pgTAP, browser E2E (planned Playwright), isolated hosted HTTP/storage integration. Real-device evidence required: no.

Planned files: `supabase/tests/events_recap_access.sql`, `events-web/tests/guest/recap-lock.spec.ts`, `scripts/events/media-access-smoke.mjs`.

- For confirmed no-show, unknown admission, pending/waitlisted and unknown account, requests return only the permitted preview and non-content locked-comment teaser.
- Direct comment listing, full gallery metadata and photo/video byte requests fail; self-reported attendance cannot insert an authoritative admission or grant completion eligibility.
- Authorized Team-admin correction changes eligibility only through the server admission path; correction/retry creates no duplicate admission.

Source authority: D3/D5; agreed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/rls_visibility.sql:112` — Role/JWT-switched tests verify relationship, blocked-viewer and profile-shell visibility.
- `supabase/tests/visible_place_photo_gallery.sql:429` — Adjacent gallery RLS test excludes blocked contributors; does not implement admission/completion access.

## P08 — Eligible guest opens post-event event/notification link without app after uninstall.

Owner: Joined release: before-event/door + after-event/map, with entry/identity foundation. Layers: browser E2E (planned Playwright), physical-device verification, PostgreSQL pgTAP, hosted rollback pgTAP. Real-device evidence required: yes.

Planned files: `events-web/tests/guest/post-event-handoff.spec.ts`, `WanderUITests/Events/EventsIntegratedJourneyTests.swift`, `scripts/events/integrated-journey.mjs`, `docs/testing/astir-events-device-matrix.md`, `supabase/tests/events_recap_access.sql`.

- On a physical device uninstall after admission, then open the actual post-event link in Clip and browser fallback; permitted event detail remains usable but check-in/upload route to full-app installation/opening.
- After real authentication recovery query the same account, booking and admission IDs; installing/reopening never creates a replacement RSVP or admission.
- If historical completion already exists, reopen recap; otherwise show the event composer. Test original account recovery and a wrong-account attempt without revealing the owner.

Source authority: N1-POST, D33; agreed

Adjacent existing evidence (not implemented Events coverage):
- `Wander/Services/Remote/WanderSupabaseClient.swift:230` — Transport validates expected account before and after obtaining a token; exercise it through the real integration too.
- `Wander/App/AppEntryView.swift:214` — Existing universal-link entry seam; Events/Clip route and actual platform invocation still require implementation.

## P09 — View rich recap and interact with comments.

Owner: After the event and on the map. Layers: XCTest unit/adapter, XCUITest, PostgreSQL pgTAP, hosted rollback pgTAP, physical-device verification. Real-device evidence required: yes.

Planned files: `WanderTests/Events/EventRecapPresentationTests.swift`, `WanderUITests/Events/EventRecapTests.swift`, `supabase/tests/events_conversation.sql`, `docs/testing/astir-events-device-matrix.md`.

- Assert event-focused cover, comments near top, working comment/reply/like controls, photos/videos plus, personal check-ins and upper-right Share using UI accessibility identifiers and layout checks.
- Read back stored comment/reply parent and like state under the event recap conversation ID; personal-post activity conversations remain distinct; unauthorized direct mutations fail.
- Actual device playback and accessible navigation work for Astir-provided and attendee-provided gallery content. Exact new editing/reporting controls remain proposed, not acceptance assertions.

Source authority: D1, R132, N1-POST; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/ActivityEngagementTests.swift:493` — Place-history engagement resolves the explicit visit before the parent conversation; Events recap conversation must stay distinct.
- `supabase/tests/visible_place_photo_gallery.sql:429` — Adjacent gallery RLS test excludes blocked contributors; does not implement admission/completion access.

## P10 — Operator configures event tag suggestions; attendee opens composer for this event and another event.

Owner: After the event and on the map. Layers: XCTest unit/adapter, PostgreSQL pgTAP, hosted rollback pgTAP, browser E2E (planned Playwright). Real-device evidence required: no.

Planned files: `WanderTests/Events/EventCheckInTests.swift`, `supabase/tests/events_tags.sql`, `events-web/tests/console/event-tags.spec.ts`.

- A Team admin updates Event A tag suggestions; fetching composers A/B returns each event’s correct configured options, including empty suggestions without blocking submit.
- Submitted optional choices map to canonical existing tag/attribute identities as agreed by the contract; they do not create unrelated venue ratings or another event’s selections.
- A nonadmin cannot alter suggestions; stale fetched choices follow an explicitly defined contract outcome instead of silently claiming a different selection. No fixed tag count is assumed.

Source authority: N1-TAGS; agreed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/place_visits_visit_photos.sql:629` — Database permits an explicit unrated visit. Contrast native ordinary Been default-rating behavior; no Events adapter exists.

## P11 — Eligible completed attendee uses gallery plus from event page.

Owner: After the event and on the map. Layers: XCUITest, PostgreSQL pgTAP, hosted rollback pgTAP, Deno handler/worker tests, isolated hosted HTTP/storage integration, physical-device verification. Real-device evidence required: yes.

Planned files: `WanderUITests/Events/EventRecapTests.swift`, `supabase/tests/events_media_references.sql`, `supabase/functions/events-media/handler.test.ts`, `supabase/functions/events-media-worker/index.test.ts`, `scripts/events/media-access-smoke.mjs`, `docs/testing/astir-events-device-matrix.md`.

- A completed eligible attendee uploads own photo and video through gallery plus; successful finalized content is immediately returned to eligible viewers without a preapproval state.
- Server verifies current admission/completion and ownership at upload/finalize, not only when the picker opened; ineligible and revoked callers cannot publish or retrieve protected bytes.
- Real photo/video selection, orientation, playback and retry leave one media source per successful upload. Gallery upload does not create another event completion/visit.

Source authority: D27, N1-POST; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/WanderStoreTests.swift:8853` — Adjacent metadata-finalization failure test avoids reuploading already-stored photo bytes.
- `supabase/functions/place-photo/handler.test.ts:5` — Existing Deno handler test injects clock and request dependencies; provider-photo cache behavior is not a protected Events-media policy.

## P12 — Eligible completed attendee selects shared gallery photos for their personal check-in.

Owner: After the event and on the map. Layers: XCTest unit/adapter, PostgreSQL pgTAP, hosted rollback pgTAP, isolated hosted HTTP/storage integration. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventHistoryAdapterTests.swift`, `supabase/tests/events_media_references.sql`, `supabase/tests/events_recap_access.sql`, `scripts/events/media-access-smoke.mjs`.

- A completed attendee selects a shared gallery photo: one reference attaches to the same event post/visit and respects that post’s audience; UI retains the small eye indicator.
- An allowed viewer of the selected public-post photo can fetch that authorized selection only; requesting the source’s surrounding gallery/comments/other derivatives does not inherit attendee access.
- No extra approval/reuse disclosure is added. Account switch, source removal or revoked post audience cannot be bypassed with a cached selection/reference.

Source authority: D6/D9/D28 amendment; agreed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/checkin_history_engagement.sql:63` — Adjacent regression pattern: idempotent history repair preserves visit timestamp and existing conversation; not Events coverage.
- `supabase/tests/visible_place_photo_gallery.sql:429` — Adjacent gallery RLS test excludes blocked contributors; does not implement admission/completion access.
- `WanderTests/PlacePhotoDeliveryTests.swift:53` — Ordinary photo cache deliberately ignores signed-URL token churn; Events permission/source version isolation needs new coverage.

## P13 — Uploader or Astir removes a source photo referenced by several posts.

Owner: After the event and on the map. Layers: PostgreSQL pgTAP, hosted rollback pgTAP, Deno handler/worker tests, isolated hosted HTTP/storage integration, XCTest unit/adapter. Real-device evidence required: no.

Planned files: `supabase/tests/events_media_references.sql`, `supabase/functions/events-media-worker/index.test.ts`, `supabase/functions/events-media/handler.test.ts`, `scripts/events/media-access-smoke.mjs`, `WanderTests/Events/EventProtectedCacheTests.swift`.

- Create one source referenced by multiple event posts plus unrelated media; uploader and Team admin removal each retire the source, all references and every generated derivative.
- After acknowledged removal, new full/range/thumbnail requests, including requests with stale signed URLs through the delivered product surface, return no protected source bytes. Revalidated warm edge/client caches must not resurrect it. Invalidate local references when removal is learned and fail closed before protected redisplay when entitlement is uncertain; no claim to erase copies already seen, exported or held on a disconnected device.
- Repeated removal and worker retries are idempotent; cleanup failure remains observable/retryable without making a tombstoned source readable. Assert other photos, notes, post/visit IDs, prior ratings and conversations survive.

Source authority: D32; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/PlacePhotoGalleryTests.swift:107` — Adjacent presenter suppresses locally deleted media from a stale remote page; useful Events tombstone regression pattern.
- `WanderTests/PlacePhotoDeliveryTests.swift:53` — Ordinary photo cache deliberately ignores signed-URL token churn; Events permission/source version isolation needs new coverage.
- `supabase/tests/checkin_history_engagement.sql:99` — Adjacent owner-deletion test verifies history removal and no resurrection through repair; not Events coverage.

## P14 — Attendee deletes own event post with an independent venue visit/rating/save present.

Owner: Events data and rules foundation; after-event shared-history integrator. Layers: XCTest unit/adapter, PostgreSQL pgTAP, hosted rollback pgTAP, XCUITest. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventHistoryAdapterTests.swift`, `supabase/tests/events_completion_history.sql`, `supabase/tests/events_media_references.sql`, `WanderUITests/Events/EventRecapTests.swift`.

- With independent older visit/rating/note/audience and explicit saved-place intent, delete the event personal post: only event-derived post/visit disappears; compare every independent record before and after.
- Admission and historical completion persist and still authorize recap; event-derived attachment references disappear without deleting another uploader’s source or other posts’ references.
- Repeat deletion, relaunch, refresh stale feed/place/history pages and run existing history repair: deleted event activity does not return and no replacement visit is synthesized.

Source authority: D33/D4; agreed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/checkin_history_engagement.sql:99` — Adjacent owner-deletion test verifies history removal and no resurrection through repair; not Events coverage.
- `supabase/tests/checkin_history_engagement.sql:63` — Adjacent regression pattern: idempotent history repair preserves visit timestamp and existing conversation; not Events coverage.
- `WanderTests/PlacePhotoGalleryTests.swift:107` — Adjacent presenter suppresses locally deleted media from a stale remote page; useful Events tombstone regression pattern.

## P15 — Unauthorized/nonattendee requests protected comment/media URL, cached projection, screen-reader output or switches accounts after viewing.

Owner: After the event and on the map. Layers: PostgreSQL pgTAP, hosted rollback pgTAP, isolated hosted HTTP/storage integration, Deno handler/worker tests, XCTest unit/adapter, XCUITest, browser E2E (planned Playwright), physical-device verification. Real-device evidence required: yes.

Planned files: `supabase/tests/events_recap_access.sql`, `supabase/tests/events_media_references.sql`, `supabase/functions/events-media/handler.test.ts`, `scripts/events/media-access-smoke.mjs`, `WanderTests/Events/EventProtectedCacheTests.swift`, `WanderUITests/Events/EventRecapTests.swift`, `events-web/tests/guest/recap-privacy.spec.ts`, `docs/testing/astir-events-device-matrix.md`.

- Parameterize unauthorized/no-show/revoked/blocked viewers: inspect raw API bodies, DOM/accessibility tree, native accessibility output, direct bytes and range responses; blur must not conceal delivered protected comment text or gallery URLs.
- Warm memory/disk/browser/CDN caches while authorized, then revoke access or switch accounts with a request in flight; stale responses do not render, cache under the new account or bypass current server permission.
- Public selected-post media uses its independent audience and grants no wider recap entitlement. A failed permission refresh returns locked/unavailable, never stale private content.

Source authority: D3/D9; derived access boundary

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/ActivityEngagementTests.swift:989` — Suspended-response test rejects a result arriving after an account switch; reuse this test pattern, not as Events coverage.
- `WanderTests/ActivityEngagementTests.swift:944` — Adjacent failure evicts previously visible activity; Events access must independently revalidate and clear protected projections.
- `WanderTests/PlacePhotoDeliveryTests.swift:53` — Ordinary photo cache deliberately ignores signed-URL token churn; Events permission/source version isolation needs new coverage.
- `supabase/tests/visible_place_photo_gallery.sql:429` — Adjacent gallery RLS test excludes blocked contributors; does not implement admission/completion access.

## P16 — Event recap temporarily unavailable then restored or republished without new content.

Owner: After the event and on the map. Layers: XCTest unit/adapter, PostgreSQL pgTAP, hosted rollback pgTAP, Deno handler/worker tests. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventCheckInTests.swift`, `WanderTests/Events/EventProtectedCacheTests.swift`, `supabase/tests/events_recap_access.sql`, `supabase/tests/events_delivery_intents.sql`, `supabase/functions/events-message-worker/index.test.ts`.

- For temporary server failure/unpublication then restoration, historical admission/completion and valid local account-bound draft remain intact; retry cannot create a second completion/visit.
- Republishing the same unchanged recap revision does not enqueue another logical invitation under the delivery identity contract; failed reads never manufacture new publication.
- Exact unavailable copy, republish/no-new-content invitation policy and upload draft recovery remain proposed P14/P06 portions: record as conditional assertions awaiting review, not approved behavior.

Source authority: P14/P06 proposed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/ActivityEngagementTests.swift:944` — Adjacent failure evicts previously visible activity; Events access must independently revalidate and clear protected projections.
- `supabase/functions/push-notification-worker/index.test.ts:23` — Existing Deno tests distinguish APNs permanent and retryable failures; Events delivery/revision guards are new.

## P17 — Share event via upper-right Share, including Instagram if available; cancel share.

Owner: After the event and on the map. Layers: XCTest unit/adapter, XCUITest, physical-device verification. Real-device evidence required: yes.

Planned files: `WanderTests/Events/EventShareTests.swift`, `WanderUITests/Events/EventRecapTests.swift`, `docs/testing/astir-events-device-matrix.md`.

- Upper-right Share resolves the canonical Event A link and only permitted public preview; it contains no booking credentials, exact-home payload or protected recap media.
- Cancel the native share sheet and return to the same event/account/state with no external post or server content mutation.
- On a physical device exercise Instagram availability and absence if supported by the selected share design; exact exported payload/format remains design work and must not be assumed.

Source authority: N1-POST, N1-LINK; share agreed, payload/recovery proposed

Adjacent existing evidence (not implemented Events coverage):
- `Wander/App/AppEntryView.swift:214` — Existing universal-link entry seam; Events/Clip route and actual platform invocation still require implementation.

## V01 — Published eligible event within console's styling window; Featured enabled.

Owner: After the event and on the map. Layers: PostgreSQL pgTAP, hosted rollback pgTAP, XCTest unit/adapter. Real-device evidence required: no.

Planned files: `supabase/tests/events_map_history.sql`, `WanderTests/Events/EventMapPresentationTests.swift`, `supabase/tests/events_home_projections.sql`.

- At controlled styling-window boundaries, Featured on returns the eligible published event pin for permitted attendees and nonattendees; disallowed/draft events remain absent.
- Private-home pin payload supplies approved approximate geometry only for viewers lacking exact rights, regardless of Featured styling.
- Server and native projection preserve a distinct event identity connected to exactly one canonical place, without changing ordinary place permissions.

Source authority: D10–D11, N2-MAP; agreed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/rls_visibility.sql:112` — Role/JWT-switched tests verify relationship, blocked-viewer and profile-shell visibility.
- `WanderTests/MapAnnotationVisibilityTests.swift:65` — Existing pin-selection tests distinguish collision-hidden, detached and visible annotations.

## V02 — You filter; viewer attended, then repeat with viewer did not attend.

Owner: After the event and on the map. Layers: PostgreSQL pgTAP, hosted rollback pgTAP, XCTest unit/adapter. Real-device evidence required: no.

Planned files: `supabase/tests/events_map_history.sql`, `WanderTests/Events/EventMapPresentationTests.swift`.

- You filter includes own qualifying authoritative attendance within current filters/window; confirmed-only, waitlisted, featured-only and no-show records do not become own attendance.
- D9 offline-only admission remains awaiting reconciliation and does not appear as server-validated attendance or unlock recap; after valid reconciliation it can qualify once.
- Changing filters/attendance returns current projection without duplicating ordinary-place or event identity.

Source authority: N2-MAP; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/MapAnnotationVisibilityTests.swift:65` — Existing pin-selection tests distinguish collision-hidden, detached and visible annotations.
- `supabase/tests/rls_visibility.sql:112` — Role/JWT-switched tests verify relationship, blocked-viewer and profile-shell visibility.

## V03 — Friends filter; qualifying friend attended; repeat with no qualifying visible friend activity.

Owner: After the event and on the map. Layers: PostgreSQL pgTAP, hosted rollback pgTAP, XCTest unit/adapter. Real-device evidence required: no.

Planned files: `supabase/tests/events_map_history.sql`, `WanderTests/Events/EventMapPresentationTests.swift`, `supabase/tests/events_recap_access.sql`.

- Friends projection includes events from a qualifying visible friend’s authoritative attendance; no qualifying visible activity means no Friends-derived pin.
- Repeat with block/unblock, restricted/private profile and follow-relationship changes; existing allowed audience semantics govern projection, not Featured eligibility.
- Do not infer new second-degree access from mutual counts or introduce an unapproved social expansion.

Source authority: N2-MAP, D9; agreed; exact second-degree expansion not silently invented

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/rls_visibility.sql:112` — Role/JWT-switched tests verify relationship, blocked-viewer and profile-shell visibility.
- `supabase/tests/visible_place_photo_gallery.sql:429` — Adjacent gallery RLS test excludes blocked contributors; does not implement admission/completion access.

## V04 — Tap distinctive pin, expand its collapsed card, then open place.

Owner: After the event and on the map. Layers: XCTest unit/adapter, XCUITest, physical-device verification. Real-device evidence required: yes.

Planned files: `WanderTests/Events/EventMapPresentationTests.swift`, `WanderUITests/Events/EventMapTests.swift`, `docs/testing/astir-events-device-matrix.md`.

- Tap an event annotation: map stays underneath a collapsed event card; first tap must not navigate directly to full event or unrelated recommendations.
- Card names the event at its canonical place with visually secondary at; expand opens that same event, then place action opens the one canonical place ID.
- Back/collapse preserves normal map state and selection; follow with another event at the same place to detect reused-card identity bugs.

Source authority: N2-MAP, D12; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/MapAnnotationVisibilityTests.swift:65` — Existing pin-selection tests distinguish collision-hidden, detached and visible annotations.

## V05 — Long event/place title, reduced motion, dark mode, large text.

Owner: After the event and on the map. Layers: XCTest unit/adapter, XCUITest, physical-device verification. Real-device evidence required: yes.

Planned files: `WanderTests/Events/EventMapPresentationTests.swift`, `WanderUITests/Events/EventMapTests.swift`, `docs/testing/astir-events-device-matrix.md`.

- Parameterize long event/place titles, dark/light appearance and largest supported Dynamic Type; card identity remains readable, controls reachable and tap targets distinct.
- With Reduce Motion enabled, selected event pin remains distinguishable using the selected static design; animation is not required to understand state.
- Verify VoiceOver label/order and contrast on physical device. Exact square/round/glow/pulse selection is design acceptance, not an approved test baseline until selected.

Source authority: N2-MAP; design acceptance / accessibility derived

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/MapAnnotationVisibilityTests.swift:65` — Existing pin-selection tests distinguish collision-hidden, detached and visible annotations.

## V06 — Console turns Featured styling off or clock crosses display end.

Owner: After the event and on the map. Layers: PostgreSQL pgTAP, hosted rollback pgTAP, XCTest unit/adapter, XCUITest. Real-device evidence required: no.

Planned files: `supabase/tests/events_map_history.sql`, `WanderTests/Events/EventMapPresentationTests.swift`, `WanderUITests/Events/EventMapTests.swift`.

- Turn Featured off and advance controlled clock across styling end: subsequent server/native projection removes temporary treatment at the configured boundary.
- Current visible screen/refresh updates treatment without deleting canonical place, prior visits, admission/completion or persistent event history.
- Open past event through Events/place history after styling ends; current authorized recap remains reachable.

Source authority: D10–D11, N2-MAP; agreed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/checkin_history_engagement.sql:63` — Adjacent regression pattern: idempotent history repair preserves visit timestamp and existing conversation; not Events coverage.
- `WanderTests/MapAnnotationVisibilityTests.swift:65` — Existing pin-selection tests distinguish collision-hidden, detached and visible annotations.

## V07 — One place has multiple events; open place profile and older event.

Owner: Events data and rules foundation; after-event shared-history integrator. Layers: PostgreSQL pgTAP, hosted rollback pgTAP, XCTest unit/adapter, XCUITest. Real-device evidence required: no.

Planned files: `supabase/tests/events_map_history.sql`, `WanderTests/Events/EventHistoryAdapterTests.swift`, `WanderUITests/Events/EventPlaceHistoryTests.swift`.

- Create Events A/B at one canonical place and a second unrelated place: each event has one place association; place history lists both correct events without duplicate place identity.
- Open older event through an inline place-history row, resolve current viewer’s state and preserve normal place-profile actions/layout.
- Assert no replacement floating event CTA, Explore nearby or invented next-place screen; ordinary independent place history remains present.

Source authority: D4, N2-REMOVE; agreed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/checkin_history_engagement.sql:63` — Adjacent regression pattern: idempotent history repair preserves visit timestamp and existing conversation; not Events coverage.
- `WanderTests/ActivityEngagementTests.swift:493` — Place-history engagement resolves the explicit visit before the parent conversation; Events recap conversation must stay distinct.

## V08 — Public event personal post appears in feed/profile/place history.

Owner: Events data and rules foundation; after-event shared-history integrator. Layers: PostgreSQL pgTAP, hosted rollback pgTAP, XCTest unit/adapter, XCUITest. Real-device evidence required: no.

Planned files: `supabase/tests/events_completion_history.sql`, `supabase/tests/events_map_history.sql`, `WanderTests/Events/EventHistoryAdapterTests.swift`, `WanderUITests/Events/EventPlaceHistoryTests.swift`.

- Query feed/profile/place history after completion: each event post leads with event identity/date and points to the single canonical event visit; every personal event post exposes its audience eye control/label.
- Compare older ordinary visits’ notes, ratings, audiences and conversation IDs before/after event completion and feed refresh; a public event post does not broaden earlier records.
- Duplicate server results, UUID normalization and stale snapshot hydration do not synthesize another visit/activity.

Source authority: D4/D9; agreed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/checkin_history_engagement.sql:63` — Adjacent regression pattern: idempotent history repair preserves visit timestamp and existing conversation; not Events coverage.
- `WanderTests/WanderStoreTests.swift:3889` — Ordinary Been save intentionally defaults a missing rating; retain that existing behavior while testing a separate Events path.
- `WanderTests/ActivityEngagementTests.swift:493` — Place-history engagement resolves the explicit visit before the parent conversation; Events recap conversation must stay distinct.

## H01 — Nonconfirmed or unknown viewer opens home event/place/map at any time.

Owner: After the event and on the map. Layers: PostgreSQL pgTAP, hosted rollback pgTAP, XCTest unit/adapter, browser E2E (planned Playwright). Real-device evidence required: no.

Planned files: `supabase/tests/events_home_projections.sql`, `WanderTests/Events/EventHomeProjectionTests.swift`, `events-web/tests/guest/home-privacy.spec.ts`.

- Across unknown/nonconfirmed/pending/waitlisted/offered booking states and all event times, event/place/map read projections exclude exact address, coordinates, nav target and hidden metadata unless independent rights apply. A confirmed no-show is tested separately by its booking/window rights, not mislabeled nonconfirmed.
- Approximate geometry is supplied without shipping exact geometry behind client styling; direct canonical-place lookup cannot bypass the event-location gate.
- Full guest-list and recap gates are independently asserted; approximate location availability grants neither.

Source authority: D8/D13/D35; agreed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/rls_visibility.sql:112` — Role/JWT-switched tests verify relationship, blocked-viewer and profile-shell visibility.
- `WanderTests/ActivityEngagementTests.swift:989` — Suspended-response test rejects a result arriving after an account switch; reuse this test pattern, not as Events coverage.

## H02 — Recognized confirmed guest crosses configured reveal time: immediately before, at, after.

Owner: After the event and on the map. Layers: PostgreSQL pgTAP, hosted rollback pgTAP, XCTest unit/adapter, browser E2E (planned Playwright), physical-device verification. Real-device evidence required: yes.

Planned files: `supabase/tests/events_home_projections.sql`, `WanderTests/Events/EventHomeProjectionTests.swift`, `events-web/tests/guest/home-privacy.spec.ts`, `WanderUITests/Events/EventHomeTests.swift`, `docs/testing/astir-events-device-matrix.md`.

- Using server-controlled time, confirmed guest at start minus 24h minus epsilon receives approximate only; at threshold and after receives exact under current entitlement.
- A later confirmation inside the reveal window gains exact access immediately without replacing booking; unconfirmed viewer at the same time remains approximate.
- Run actual recognized Clip, browser and full app reads; inspect payload/navigation target as well as UI. Client clock/timezone changes cannot reveal early.

Source authority: D13, C-NOAPP; agreed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/rls_visibility.sql:112` — Role/JWT-switched tests verify relationship, blocked-viewer and profile-shell visibility.
- `Wander/Services/Remote/WanderSupabaseClient.swift:230` — Transport validates expected account before and after obtaining a token; exercise it through the real integration too.

## H03 — Recognized confirmed guest crosses expiry: immediately before, at, after event end+24h.

Owner: After the event and on the map. Layers: PostgreSQL pgTAP, hosted rollback pgTAP, XCTest unit/adapter, browser E2E (planned Playwright), physical-device verification. Real-device evidence required: yes.

Planned files: `supabase/tests/events_home_projections.sql`, `WanderTests/Events/EventHomeProjectionTests.swift`, `events-web/tests/guest/home-privacy.spec.ts`, `WanderUITests/Events/EventHomeTests.swift`, `docs/testing/astir-events-device-matrix.md`.

- For exact address expiry at end plus 24h, test before/at/after with authorized guest; event/place/map/nav return approximate at cutoff while valid recap/history persist.
- Warm exact caches then leave screen open/background, advance clock and resume/relaunch; stale screen, accessibility output or delayed response cannot restore expired event-only exact rights.
- Independent location rights remain valid in their own authorized context; event expiry must neither erase them nor invent them.

Source authority: D35; agreed

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/ActivityEngagementTests.swift:989` — Suspended-response test rejects a result arriving after an account switch; reuse this test pattern, not as Events coverage.
- `WanderTests/PlacePhotoDeliveryTests.swift:53` — Ordinary photo cache deliberately ignores signed-URL token churn; Events permission/source version isolation needs new coverage.

## H04 — Operator changes reveal/expiry timing; guests reopen event in all three surfaces.

Owner: After the event and on the map. Layers: PostgreSQL pgTAP, hosted rollback pgTAP, browser E2E (planned Playwright), XCTest unit/adapter, physical-device verification. Real-device evidence required: yes.

Planned files: `supabase/tests/events_home_projections.sql`, `WanderTests/Events/EventHomeProjectionTests.swift`, `events-web/tests/guest/home-privacy.spec.ts`, `events-web/tests/console/home-settings.spec.ts`, `docs/testing/astir-events-device-matrix.md`.

- Team admin changes reveal/expiry; all three surfaces enforce the current server schedule on next read and retire stale exact presentation when rights end.
- Parameterize relative offsets versus explicitly configured absolute overrides; D13 reschedule recomputes only relative boundaries and preserves booking/admission/history.
- Unconfirmed viewer remains approximate even while styling is on; independently established location rights remain separate. Exact console capture interaction is not newly approved here.

Source authority: D13/D35; agreed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/rls_visibility.sql:112` — Role/JWT-switched tests verify relationship, blocked-viewer and profile-shell visibility.
- `WanderTests/ActivityEngagementTests.swift:989` — Suspended-response test rejects a result arriving after an account switch; reuse this test pattern, not as Events coverage.

## H05 — Private home lacks resident/owner/renter consent; operator prepares publication.

Owner: After the event and on the map. Layers: PostgreSQL pgTAP, hosted rollback pgTAP, browser E2E (planned Playwright). Real-device evidence required: no.

Planned files: `supabase/tests/events_home_projections.sql`, `events-web/tests/console/home-consent.spec.ts`.

- Attempt to publish/use a private-home event without the required recorded consent fact: server mutation fails with no public pin or exact-address publication side effect.
- Once the reviewed workflow records valid consent, eligible Team admin can publish under all normal event/location gates; a guest cannot assert consent or bypass publication validation.
- Consent capture procedure/evidence form remains proposed; tests must bind to the approved representation once reviewed rather than inventing a legal document or new policy.

Source authority: D8 original direction; consent agreed, capture procedure proposed

Adjacent existing evidence (not implemented Events coverage):
- `scripts/supabase-smoke-test.mjs:68` — Existing migration-test runner checks pgTAP failures in rollback-only hosted SQL; HTTP/storage journeys require separate committed isolated fixtures.
- `supabase/tests/rls_visibility.sql:112` — Role/JWT-switched tests verify relationship, blocked-viewer and profile-shell visibility.

## H06 — Search, share/notification preview, calendar, media metadata, cached map/place data and direct navigation target for unauthorized home viewer.

Owner: After the event and on the map. Layers: PostgreSQL pgTAP, hosted rollback pgTAP, Deno handler/worker tests, isolated hosted HTTP/storage integration, XCTest unit/adapter, browser E2E (planned Playwright), physical-device verification. Real-device evidence required: yes.

Planned files: `supabase/tests/events_home_projections.sql`, `WanderTests/Events/EventHomeProjectionTests.swift`, `events-web/tests/guest/home-privacy.spec.ts`, `supabase/functions/events-media/handler.test.ts`, `supabase/functions/events-message-worker/index.test.ts`, `supabase/functions/events-share-preview/handler.test.ts`, `scripts/events/media-access-smoke.mjs`, `docs/testing/astir-events-device-matrix.md`.

- For unauthorized/exact-expired viewer, enumerate search, OG/share/SMS/push preview, calendar export, media metadata/EXIF, map/place cache and direct nav requests; none includes exact address/coordinate/navigation target.
- Private originals and derivatives cannot expose exact metadata through a permitted public preview/post; validate actual returned file metadata and bytes, not only database fields.
- Cache warm-up, access loss and old links do not leak alternate projections. Calendar delivery/update mechanics are conditional P20 proposal; no claim to recall copies already exported or seen.

Source authority: D8/D13/D35; derived boundary; P20 calendar mechanics proposed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/functions/place-photo/handler.test.ts:5` — Existing Deno handler test injects clock and request dependencies; provider-photo cache behavior is not a protected Events-media policy.
- `WanderTests/PlacePhotoDeliveryTests.swift:53` — Ordinary photo cache deliberately ignores signed-URL token churn; Events permission/source version isolation needs new coverage.
- `supabase/functions/push-notification-worker/index.test.ts:23` — Existing Deno tests distinguish APNs permanent and retryable failures; Events delivery/revision guards are new.

## H07 — Completed attendee deletes post, has RSVP canceled/revoked, or reaches home expiry.

Owner: After the event and on the map. Layers: PostgreSQL pgTAP, hosted rollback pgTAP, XCTest unit/adapter, isolated hosted HTTP/storage integration. Real-device evidence required: no.

Planned files: `supabase/tests/events_home_projections.sql`, `supabase/tests/events_recap_access.sql`, `supabase/tests/events_completion_history.sql`, `WanderTests/Events/EventProtectedCacheTests.swift`, `scripts/events/media-access-smoke.mjs`.

- Cross product of post present/deleted, admission valid/revoked, completion absent/present, booking confirmed/canceled, window active/expired and independent location right: assert each endpoint’s documented gate independently.
- Deleting personal post retains completion and valid attendee recap; cancellation/expiry removes only event-based exact-location rights as specified; revoked admission removes protected recap even if old post or completion remains.
- Independent earlier visit/rating/audience/save survives every event mutation; permitted selected-post media is evaluated under its own audience and cannot unlock surrounding gallery.

Source authority: D4/D9/D13/D33/D35; agreed / derived

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/checkin_history_engagement.sql:99` — Adjacent owner-deletion test verifies history removal and no resurrection through repair; not Events coverage.
- `supabase/tests/rls_visibility.sql:112` — Role/JWT-switched tests verify relationship, blocked-viewer and profile-shell visibility.
- `WanderTests/ActivityEngagementTests.swift:944` — Adjacent failure evicts previously visible activity; Events access must independently revalidate and clear protected projections.

## C01 — Two individually signed-in Team admins open the web console; compare an ordinary member, a signed-out visitor, revoked membership and direct API requests.

Owner: events-data-and-rules. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment). Real-device evidence required: no.

Planned files: `supabase/tests/events_authorization.sql`, `supabase/tests/events_private_location.sql`, `scripts/supabase-smoke-test.mjs`, `events-web/tests/console/authorization.spec.ts`, `events-web/tests/console/event-controls.spec.ts`.

- Two separately authenticated Team admins can use all Events controls including scanner, content, messages, settings and private feedback; no per-event assignment or organizer/door split.
- Ordinary member, anonymous caller, expired session and revoked membership fail protected API and direct table/storage/RPC access; an already-open page or forged client flag does not grant rights.
- Check grants, RLS, security mode and pinned search_path for new/changed RPCs; service-only worker functions are not callable with guest/admin client credentials.
- Guest preview requests obey guest permissions and cannot inherit console/private feedback/exact-home data into public payloads; record acting admin on writes.

Source authority: N2-CONSOLE, engineering D7 explicit clarification; agreed / derived

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/clerk_identity_continuity.sql:7` — Existing tests inspect security mode, search_path and authenticated canonical-identity resolution. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/rls_visibility.sql:7` — Existing fixtures distinguish owner, follower, mutual, nonfollower and blocked viewers. Adjacent evidence only; no Events test is implemented or passed.
- `scripts/supabase-smoke-test.mjs:1110` — Existing migration-preview / strict pgTAP rollback-only entry points can host planned Events contract checks. Adjacent evidence only; no Events test is implemented or passed.

## C02 — Operator creates event with one linked place, timing, image, description and RSVP controls; previews and publishes.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment). Real-device evidence required: no.

Planned files: `supabase/tests/events_publication.sql`, `supabase/tests/events_authorization.sql`, `scripts/supabase-smoke-test.mjs`, `events-web/tests/console/event-controls.spec.ts`.

- Authorized admin creates and changes an event using the shared backend configuration: exactly one canonical linked place, event timing, image, description and RSVP controls.
- Read from a second authenticated browser/API session to prove persistence and guest-facing result, not merely local form state.
- Reject failed mutations without success UI or publication side effects; direct unauthorized mutation cannot bypass the console.
- POLICY-GATED P19/P09: precise required draft fields, preview/publish sequence and unavailable-draft behavior remain proposals until reviewed.

Source authority: N2-CONSOLE; capability agreed, P19 procedure proposed

Adjacent existing evidence (not implemented Events coverage):
- `scripts/supabase-smoke-test.mjs:1110` — Existing migration-preview / strict pgTAP rollback-only entry points can host planned Events contract checks. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/clerk_identity_continuity.sql:7` — Existing tests inspect security mode, search_path and authenticated canonical-identity resolution. Adjacent evidence only; no Events test is implemented or passed.

## C03 — Set map toggle/window/preset, home reveal/expiry, automatic/manual mode, code mode/cap, offer expiry.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment). Real-device evidence required: no.

Planned files: `supabase/tests/events_booking.sql`, `supabase/tests/events_invitation_codes.sql`, `supabase/tests/events_private_location.sql`, `supabase/tests/events_publication.sql`, `scripts/supabase-smoke-test.mjs`, `events-web/tests/console/event-controls.spec.ts`.

- Exercise each approved control: map style toggle/window/preset, home reveal/expiry, automatic/manual mode, code mode/cap, offer duration and earlier registration close; show saved current value and correct guest result.
- Assert authorized persisted settings across a separate API-backed guest context; invalid input or failed save cannot show success or leak exact-home details in preview.
- Capacity reduction respects confirmed/held commitments; approved deactivation, current cutoff and reveal/expiry behavior remain consistent with B06/B07/B15 and home tests.
- POLICY-GATED: behavior of existing requests after approval-mode edits, issued-deadline edits, quota reductions or whole-event code changes is not selected by the existence of these controls.

Source authority: D11/D13/D22/D23/D35, N2-CODES; agreed

Adjacent existing evidence (not implemented Events coverage):
- `scripts/supabase-smoke-test.mjs:1110` — Existing migration-preview / strict pgTAP rollback-only entry points can host planned Events contract checks. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/rls_visibility.sql:7` — Existing fixtures distinguish owner, follower, mutual, nonfollower and blocked viewers. Adjacent evidence only; no Events test is implemented or passed.

## C04 — Operator adds first-party recap photos/videos and event tags, then publishes recap.

Owner: after-event-map. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment), Deno worker with fake clock/provider/network. Real-device evidence required: no.

Planned files: `supabase/tests/events_publication.sql`, `supabase/tests/events_notifications.sql`, `supabase/tests/events_authorization.sql`, `scripts/supabase-smoke-test.mjs`, `supabase/functions/event-message-worker/index.test.ts`, `events-web/tests/console/recap-publication.spec.ts`.

- Admin assigns correct event first-party photos/videos and suggested tags, then publishes via actual API in an isolated environment.
- Only successfully committed publication may create content/check-in invitation work; failed upload/publication or unauthorized publish creates no false ready state or outgoing invite.
- Other event tags/media cannot appear accidentally; guest projections and protected media stay permission-gated.
- Trigger ownership is after-event-map; use the common messaging enqueue contract, not a second independent delivery system.

Source authority: D26, N1-TAGS, N2-CONSOLE; agreed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/notifications.sql:6` — Existing notification pgTAP suite provides transactional notification fixture patterns. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/clerk_identity_continuity.sql:7` — Existing tests inspect security mode, search_path and authenticated canonical-identity resolution. Adjacent evidence only; no Events test is implemented or passed.
- `scripts/supabase-smoke-test.mjs:1110` — Existing migration-preview / strict pgTAP rollback-only entry points can host planned Events contract checks. Adjacent evidence only; no Events test is implemented or passed.

## C05 — Operator selects waitlist guest, reviews approval, corrects missed scan, removes media.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment). Real-device evidence required: no.

Planned files: `supabase/tests/events_booking.sql`, `supabase/tests/events_invitation_codes.sql`, `supabase/tests/events_admission.sql`, `supabase/tests/events_canonical_history_regression.sql`, `supabase/tests/events_authorization.sql`, `scripts/supabase-smoke-test.mjs`, `events-web/tests/console/event-controls.spec.ts`, `events-web/tests/console/admission.spec.ts`, `events-web/tests/console/recap-publication.spec.ts`.

- Waitlist selection issues held offer and never confirms automatically; eligible approval respects code/capacity/approval rules.
- Missed-scan correction only changes admission; it creates no personal post/completion/Been visit.
- Authorized media removal invalidates the source wherever referenced while preserving remaining posts, notes, visits and independent history; cannot mutate unrelated event media.
- Observe actual database results and a separate guest API context after each console action, plus failure/unknown-response UI.

Source authority: D5/D21/D23/D27/D32; agreed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/checkin_history_engagement.sql:68` — Existing history repair is tested for idempotence and preservation of historical activity; Events must extend canonical-history regression coverage. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/checkin_history_engagement.sql:101` — Existing owner-deletion test ensures repair does not revive a deleted check-in. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/clerk_identity_continuity.sql:7` — Existing tests inspect security mode, search_path and authenticated canonical-identity resolution. Adjacent evidence only; no Events test is implemented or passed.

## C06 — Existing ordinary place check-in, list/save, rating, profile visibility and blocks exercised before/after event flow.

Owner: after-event-map. Layers: local pgTAP, planned hosted rollback smoke, native XCTest / XCUITest. Real-device evidence required: no.

Planned files: `supabase/tests/events_canonical_history_regression.sql`, `supabase/tests/events_authorization.sql`, `scripts/supabase-smoke-test.mjs`, `WanderTests/EventsCanonicalHistoryTests.swift`.

- Create independent ordinary place visit, note, rating, follower-only audience, list membership and explicit save; complete/delete an event visit at the same canonical place.
- Event adds one event-labeled canonical visit with no invented venue rating, parent-rating/note overwrite, audience broadening or second history; deletion retains independent records/intent.
- Repeat with blocked/nonfollower contexts and historical compatibility/backfill repair; older restricted activity must not become visible or deleted activity revived.
- Native adapter and DB projection must agree on distinct admission, historical completion and visit/post deletion. Existing adjacent history tests are prerequisites, not Events coverage.

Source authority: D4/D9/D33; agreed

Adjacent existing evidence (not implemented Events coverage):
- `supabase/tests/checkin_history_engagement.sql:68` — Existing history repair is tested for idempotence and preservation of historical activity; Events must extend canonical-history regression coverage. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/checkin_history_engagement.sql:101` — Existing owner-deletion test ensures repair does not revive a deleted check-in. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/rls_visibility.sql:7` — Existing fixtures distinguish owner, follower, mutual, nonfollower and blocked viewers. Adjacent evidence only; no Events test is implemented or passed.

## C07 — Inspect guest navigation, onboarding, deferred features and build changes for this phase.

Owner: entry-and-identity. Layers: Playwright stubbed UI, Playwright API-backed integration (isolated test environment), native XCTest / XCUITest, real iPhone / intended staff-browser device verification. Real-device evidence required: yes.

Planned files: `WanderUITests/EventsNavigationUITests.swift`, `WanderUITests/EventsAdmissionUITests.swift`, `events-web/tests/guest/rsvp.spec.ts`, `docs/testing/events/booking-door-real-device.md`.

- Native navigation places QR in Events and introduces no separate Tickets tab; actual setup gate collects missing name/username and leaves photo optional.
- Inspect source/feature flags and visible journey for unapproved reconnection or future profile/check-in privacy expansion; retain existing permissions without shipping deferred new controls.
- Browser and Clip stay no-install RSVP/management surfaces until entry; native/App Clip build and physical invocation evidence remain separate from HTML design verification.
- Report each runtime layer as not implemented/not executed until evidence exists; screenshots, mapped acceptance IDs and frontend prototypes cannot count as backend or release passes.

Source authority: R130, D7/D9, N2-EXIT; agreed

Adjacent existing evidence (not implemented Events coverage):
- `project.yml:45` — Existing scheme includes WanderTests and WanderUITests; Events/App Clip and real-device evidence still have to be added. Adjacent evidence only; no Events test is implemented or passed.
- `supabase/tests/clerk_identity_continuity.sql:7` — Existing tests inspect security mode, search_path and authenticated canonical-identity resolution. Adjacent evidence only; no Events test is implemented or passed.

## E01 — Fresh iPhone, no app/account → canonical invitation → Clip RSVP → confirmation/reminders without download → optional guest-list/RSVP management → later install → valid name/username → QR → staff admission → recap invitation → empty check-in.

Owner: Joined release: before-event/door + after-event/map, with entry/identity foundation. Layers: integrated staged journey, browser E2E (planned Playwright), physical-device app/Clip verification, server-state assertions. Real-device evidence required: yes.

Planned files: `events-web/tests/journeys/e01.spec.ts`, `WanderUITests/Events/EventsIntegratedJourneyTests.swift`, `scripts/events/integrated-journey.mjs`, `docs/testing/astir-events-device-matrix.md`, `supabase/tests/events_completion_history.sql`, `supabase/tests/events_map_history.sql`.

- One run ID binds actual surface actions, canonical user/event/booking/admission/completion/visit/media IDs, build versions and delivery intents. Bootstrap only starting fixtures; do not seed later happy states, inject fake session tokens into UI or stitch separate mocked stage results.
- Use isolated committed staging fixtures for HTTP/app/browser/worker interactions, real production-shape APIs and operator console; assert server facts through a read-only verifier after each boundary. SQL rollback tests are complementary, not this journey.
- On a fresh physical iPhone invoke actual canonical invitation into Clip, choose Apple/Google in separate runs, verify controlled phone, confirm without download, consume actual test confirmation/reminder and exercise no-app guest list/manage.
- Install/open real full app, complete only required identity fields, present QR to another authenticated operator surface, publish recap through console, receive test invitation and submit empty check-in.
- Assert one booking/admission/completion/event visit, null event-visit venue rating, retained independent history, unlocked recap and correct temporary pin/persistent place route.

Source authority: L02; I01/I08; M01/M03; A01; P02; V07

Adjacent existing evidence (not implemented Events coverage):
- `Wander/App/AppEntryView.swift:214` — Existing universal-link entry seam; Events/Clip route and actual platform invocation still require implementation.
- `Wander/Services/Remote/WanderSupabaseClient.swift:230` — Transport validates expected account before and after obtaining a token; exercise it through the real integration too.
- `supabase/tests/checkin_history_engagement.sql:63` — Adjacent regression pattern: idempotent history repair preserves visit timestamp and existing conversation; not Events coverage.
- `supabase/functions/push-notification-worker/index.test.ts:23` — Existing Deno tests distinguish APNs permanent and retryable failures; Events delivery/revision guards are new.
- `Wander/App/WanderApp.swift:33` — Verify live auth/backend mode; existing Simulator fixture session is not integrated journey evidence.

## E02 — Same start with Clip unavailable → browser → close session → recover identity/RSVP → install from link or app icon → entry and post-event journey.

Owner: Joined release: before-event/door + after-event/map, with entry/identity foundation. Layers: integrated staged journey, browser E2E (planned Playwright), physical-device app/Clip verification, server-state assertions. Real-device evidence required: yes.

Planned files: `events-web/tests/journeys/e02.spec.ts`, `WanderUITests/Events/EventsIntegratedJourneyTests.swift`, `scripts/events/integrated-journey.mjs`, `docs/testing/astir-events-device-matrix.md`, `supabase/tests/events_completion_history.sql`.

- One run ID binds actual surface actions, canonical user/event/booking/admission/completion/visit/media IDs, build versions and delivery intents. Bootstrap only starting fixtures; do not seed later happy states, inject fake session tokens into UI or stitch separate mocked stage results.
- Use isolated committed staging fixtures for HTTP/app/browser/worker interactions, real production-shape APIs and operator console; assert server facts through a read-only verifier after each boundary. SQL rollback tests are complementary, not this journey.
- Make actual Clip invocation unavailable, complete browser RSVP, close the session and recover the original account/reservation before installation. Run install-to-link and install-to-app-icon branches.
- Continue through real QR/admission/publication/empty completion using the same server IDs; no forced early download, duplicate booking or copied sender/session authority.
- Verify the final record counts and access match E01; capture actual platform fallback/handoff results rather than simulated route flags.

Source authority: L03/L04; I07; D14

Adjacent existing evidence (not implemented Events coverage):
- `Wander/App/AppEntryView.swift:214` — Existing universal-link entry seam; Events/Clip route and actual platform invocation still require implementation.
- `Wander/Services/Remote/WanderSupabaseClient.swift:230` — Transport validates expected account before and after obtaining a token; exercise it through the real integration too.
- `supabase/tests/checkin_history_engagement.sql:63` — Adjacent regression pattern: idempotent history repair preserves visit timestamp and existing conversation; not Events coverage.
- `Wander/App/WanderApp.swift:33` — Verify live auth/backend mode; existing Simulator fixture session is not integrated journey evidence.

## E03 — Installed app, recognized existing member → Events discovery → valid existing identity/phone → confirmed RSVP → notifications/texts → entry → personal content + gallery contribution.

Owner: Joined release: before-event/door + after-event/map, with entry/identity foundation. Layers: integrated staged journey, browser E2E (planned Playwright), physical-device app/Clip verification, server-state assertions, isolated hosted HTTP/storage integration. Real-device evidence required: yes.

Planned files: `events-web/tests/journeys/e03.spec.ts`, `WanderUITests/Events/EventsIntegratedJourneyTests.swift`, `scripts/events/integrated-journey.mjs`, `docs/testing/astir-events-device-matrix.md`, `supabase/tests/events_completion_history.sql`, `supabase/tests/events_media_references.sql`, `scripts/events/media-access-smoke.mjs`.

- One run ID binds actual surface actions, canonical user/event/booking/admission/completion/visit/media IDs, build versions and delivery intents. Bootstrap only starting fixtures; do not seed later happy states, inject fake session tokens into UI or stitch separate mocked stage results.
- Use isolated committed staging fixtures for HTTP/app/browser/worker interactions, real production-shape APIs and operator console; assert server facts through a read-only verifier after each boundary. SQL rollback tests are complementary, not this journey.
- Start with a real installed recognized member and verified phone, navigate Events discovery, RSVP and verify no redundant signup, verification or install gate.
- Receive controlled notifications/texts, use QR at door, publish recap, submit own optional content and independently upload gallery photo/video through the plus.
- Read back one visit/completion and correct source/attachment records; own content and immediate eligible shared-gallery playback obey current permissions.

Source authority: L12; I02; M07; P03/P11

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/WanderStoreTests.swift:8853` — Adjacent metadata-finalization failure test avoids reuploading already-stored photo bytes.
- `Wander/Services/Remote/WanderSupabaseClient.swift:230` — Transport validates expected account before and after obtaining a token; exercise it through the real integration too.
- `supabase/functions/push-notification-worker/index.test.ts:23` — Existing Deno tests distinguish APNs permanent and retryable failures; Events delivery/revision guards are new.
- `Wander/App/WanderApp.swift:33` — Verify live auth/backend mode; existing Simulator fixture session is not integrated journey evidence.

## E04 — Installed app signed out or setup incomplete, existing confirmed RSVP → shared reminder → recover original identity → fill missing name/username, skip photo → entry.

Owner: Joined release: before-event/door + after-event/map, with entry/identity foundation. Layers: integrated staged journey, browser E2E (planned Playwright), physical-device app/Clip verification, server-state assertions. Real-device evidence required: yes.

Planned files: `events-web/tests/journeys/e04.spec.ts`, `WanderUITests/Events/EventsIntegratedJourneyTests.swift`, `scripts/events/integrated-journey.mjs`, `docs/testing/astir-events-device-matrix.md`.

- One run ID binds actual surface actions, canonical user/event/booking/admission/completion/visit/media IDs, build versions and delivery intents. Bootstrap only starting fixtures; do not seed later happy states, inject fake session tokens into UI or stitch separate mocked stage results.
- Use isolated committed staging fixtures for HTTP/app/browser/worker interactions, real production-shape APIs and operator console; assert server facts through a read-only verifier after each boundary. SQL rollback tests are complementary, not this journey.
- With an existing server RSVP, sign out or remove required name/username in isolated fixtures; open real reminder, recover original provider identity and preserve event context.
- Fill only missing valid identity essentials, skip/fail optional photo and reach QR without a general tour or location/contacts/notification gate.
- Scan through actual operator console; query original booking and one admission, with no replacement RSVP or entry under a different account.

Source authority: L04; I06/I08–I10; N2-SETUP

Adjacent existing evidence (not implemented Events coverage):
- `Wander/App/AppEntryView.swift:214` — Existing universal-link entry seam; Events/Clip route and actual platform invocation still require implementation.
- `Wander/Services/Remote/WanderSupabaseClient.swift:230` — Transport validates expected account before and after obtaining a token; exercise it through the real integration too.
- `Wander/App/WanderApp.swift:33` — Verify live auth/backend mode; existing Simulator fixture session is not integrated journey evidence.

## E05 — Unknown recipient of forwarded link → successful no-booking lookup → optional capped code → full event → waitlist → selected offer → accept → install later → entry → recap.

Owner: Joined release: before-event/door + after-event/map, with entry/identity foundation. Layers: integrated staged journey, browser E2E (planned Playwright), physical-device app/Clip verification, server-state assertions. Real-device evidence required: yes.

Planned files: `events-web/tests/journeys/e05.spec.ts`, `WanderUITests/Events/EventsIntegratedJourneyTests.swift`, `scripts/events/integrated-journey.mjs`, `docs/testing/astir-events-device-matrix.md`, `supabase/tests/events_capacity_codes.sql`, `supabase/tests/events_completion_history.sql`.

- One run ID binds actual surface actions, canonical user/event/booking/admission/completion/visit/media IDs, build versions and delivery intents. Bootstrap only starting fixtures; do not seed later happy states, inject fake session tokens into UI or stitch separate mocked stage results.
- Use isolated committed staging fixtures for HTTP/app/browser/worker interactions, real production-shape APIs and operator console; assert server facts through a read-only verifier after each boundary. SQL rollback tests are complementary, not this journey.
- Forward one actual invite to an unknown viewer, authenticate to a genuine no-booking result, use capped code, encounter full capacity and explicitly join waitlist.
- Team admin issues held offer; guest accepts before deadline, then later installs, enters and completes recap path. Include response-loss retry during acceptance.
- Query sender and recipient separately: no inherited privileges; one confirmation consumes one use/seat, valid holds respected, one admission/completion/visit; prior offer identity/deadline recorded.

Source authority: L11; B02/B05/B09–B11; E01

Adjacent existing evidence (not implemented Events coverage):
- `Wander/Services/Remote/WanderSupabaseClient.swift:230` — Transport validates expected account before and after obtaining a token; exercise it through the real integration too.
- `scripts/supabase-smoke-test.mjs:68` — Existing migration-test runner checks pgTAP failures in rollback-only hosted SQL; HTTP/storage journeys require separate committed isolated fixtures.
- `Wander/App/WanderApp.swift:33` — Verify live auth/backend mode; existing Simulator fixture session is not integrated journey evidence.

## E06 — Pending manual applicant → authorized approval with capacity → confirmation; another pending applicant rejected → opens old link.

Owner: Joined release: before-event/door + after-event/map, with entry/identity foundation. Layers: integrated staged journey, browser E2E (planned Playwright), physical-device app/Clip verification, server-state assertions. Real-device evidence required: yes.

Planned files: `events-web/tests/journeys/e06.spec.ts`, `WanderUITests/Events/EventsIntegratedJourneyTests.swift`, `scripts/events/integrated-journey.mjs`, `docs/testing/astir-events-device-matrix.md`, `supabase/tests/events_booking_transitions.sql`, `supabase/tests/events_recap_access.sql`.

- One run ID binds actual surface actions, canonical user/event/booking/admission/completion/visit/media IDs, build versions and delivery intents. Bootstrap only starting fixtures; do not seed later happy states, inject fake session tokens into UI or stitch separate mocked stage results.
- Use isolated committed staging fixtures for HTTP/app/browser/worker interactions, real production-shape APIs and operator console; assert server facts through a read-only verifier after each boundary. SQL rollback tests are complementary, not this journey.
- Create two real verified pending applications without seat holds; approve one through Team-admin console with available capacity and reject the other.
- Approved guest traverses install/identity/QR/server admission; rejected guest opens the old canonical link in browser/Clip and receives current rejected/unconfirmed state.
- Query capacity and booking transition records plus actual guest-list, ticket and private-address API responses: no privileges for rejected applicant, one booking/admission for approved guest.

Source authority: L06; B08; D22/D30

Adjacent existing evidence (not implemented Events coverage):
- `Wander/Services/Remote/WanderSupabaseClient.swift:230` — Transport validates expected account before and after obtaining a token; exercise it through the real integration too.
- `supabase/tests/rls_visibility.sql:112` — Role/JWT-switched tests verify relationship, blocked-viewer and profile-shell visibility.
- `Wander/App/WanderApp.swift:33` — Verify live auth/backend mode; existing Simulator fixture session is not integrated journey evidence.

## E07 — Confirmed no-app guest → View/change RSVP → cancel before start → another newcomer races staff offer for released spot.

Owner: Joined release: before-event/door + after-event/map, with entry/identity foundation. Layers: integrated staged journey, browser E2E (planned Playwright), physical-device app/Clip verification, server-state assertions. Real-device evidence required: yes.

Planned files: `events-web/tests/journeys/e07.spec.ts`, `WanderUITests/Events/EventsIntegratedJourneyTests.swift`, `scripts/events/integrated-journey.mjs`, `docs/testing/astir-events-device-matrix.md`, `supabase/tests/events_capacity_codes.sql`.

- One run ID binds actual surface actions, canonical user/event/booking/admission/completion/visit/media IDs, build versions and delivery intents. Bootstrap only starting fixtures; do not seed later happy states, inject fake session tokens into UI or stitch separate mocked stage results.
- Use isolated committed staging fixtures for HTTP/app/browser/worker interactions, real production-shape APIs and operator console; assert server facts through a read-only verifier after each boundary. SQL rollback tests are complementary, not this journey.
- Confirmed guest uses Clip/browser View or change RSVP before start to cancel without installing; query canceled booking and exactly-once seat/code release.
- Coordinate separate real clients for new request versus Team-admin issuance/acceptance of a held waitlist offer at the released capacity; assert serializable inventory outcome.
- Old ticket/booking cannot admit, stale cancellation/RSVP retries do not resurrect it, and delivery intents describe committed outcomes only; complete the successful guest’s door flow.

Source authority: B13; B05/B09; M11

Adjacent existing evidence (not implemented Events coverage):
- `scripts/supabase-smoke-test.mjs:68` — Existing migration-test runner checks pgTAP failures in rollback-only hosted SQL; HTTP/storage journeys require separate committed isolated fixtures.
- `supabase/functions/push-notification-worker/index.test.ts:23` — Existing Deno tests distinguish APNs permanent and retryable failures; Events delivery/revision guards are new.
- `Wander/App/WanderApp.swift:33` — Verify live auth/backend mode; existing Simulator fixture session is not integrated journey evidence.

## E08 — Private-home confirmed guest → pre-reveal Clip detail → exact reveal → installed QR/admission → recap → address expiry → delete personal post.

Owner: Joined release: before-event/door + after-event/map, with entry/identity foundation. Layers: integrated staged journey, browser E2E (planned Playwright), physical-device app/Clip verification, server-state assertions, isolated hosted HTTP/storage integration. Real-device evidence required: yes.

Planned files: `events-web/tests/journeys/e08.spec.ts`, `WanderUITests/Events/EventsIntegratedJourneyTests.swift`, `scripts/events/integrated-journey.mjs`, `docs/testing/astir-events-device-matrix.md`, `supabase/tests/events_home_projections.sql`, `supabase/tests/events_completion_history.sql`, `scripts/events/media-access-smoke.mjs`.

- One run ID binds actual surface actions, canonical user/event/booking/admission/completion/visit/media IDs, build versions and delivery intents. Bootstrap only starting fixtures; do not seed later happy states, inject fake session tokens into UI or stitch separate mocked stage results.
- Use isolated committed staging fixtures for HTTP/app/browser/worker interactions, real production-shape APIs and operator console; assert server facts through a read-only verifier after each boundary. SQL rollback tests are complementary, not this journey.
- Use consented private-home event, recognized confirmed Clip guest and controlled server time: capture approximate before reveal, exact at reveal, then actual installed QR/admission and recap completion.
- Cross expiry while app/browser has warm private data, verify approximate data/nav, then delete own event post and refresh actual place/feed/history routes.
- Read server and delivered payloads: valid admission/completion/recap and independent visit/rating/save remain; exact event-only address cannot return from caches or old links.

Source authority: H01–H04; P14

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/PlacePhotoDeliveryTests.swift:53` — Ordinary photo cache deliberately ignores signed-URL token churn; Events permission/source version isolation needs new coverage.
- `supabase/tests/checkin_history_engagement.sql:99` — Adjacent owner-deletion test verifies history removal and no resurrection through repair; not Events coverage.
- `supabase/tests/rls_visibility.sql:112` — Role/JWT-switched tests verify relationship, blocked-viewer and profile-shell visibility.
- `Wander/App/WanderApp.swift:33` — Verify live auth/backend mode; existing Simulator fixture session is not integrated journey evidence.

## E09 — Admitted guest uninstalls before recap → SMS link in Clip/browser → app handoff → recover → check-in/upload → uninstall/reinstall again.

Owner: Joined release: before-event/door + after-event/map, with entry/identity foundation. Layers: integrated staged journey, browser E2E (planned Playwright), physical-device app/Clip verification, server-state assertions. Real-device evidence required: yes.

Planned files: `events-web/tests/journeys/e09.spec.ts`, `WanderUITests/Events/EventsIntegratedJourneyTests.swift`, `scripts/events/integrated-journey.mjs`, `docs/testing/astir-events-device-matrix.md`, `supabase/tests/events_completion_history.sql`, `supabase/tests/events_media_references.sql`.

- One run ID binds actual surface actions, canonical user/event/booking/admission/completion/visit/media IDs, build versions and delivery intents. Bootstrap only starting fixtures; do not seed later happy states, inject fake session tokens into UI or stitch separate mocked stage results.
- Use isolated committed staging fixtures for HTTP/app/browser/worker interactions, real production-shape APIs and operator console; assert server facts through a read-only verifier after each boundary. SQL rollback tests are complementary, not this journey.
- After real admission uninstall app; consume post-event test SMS link via Clip/browser, reinstall/open, authenticate original account and submit check-in/upload.
- Uninstall/reinstall again, reopen same canonical event and obtain existing completed recap without a second required check-in or restored deleted post.
- Compare server booking/admission/completion/visit/media IDs across both reinstall boundaries; first successful uploads remain accessible only under current permissions.

Source authority: M13; P06/P08/P11

Adjacent existing evidence (not implemented Events coverage):
- `Wander/Services/Remote/WanderSupabaseClient.swift:230` — Transport validates expected account before and after obtaining a token; exercise it through the real integration too.
- `Wander/App/AppEntryView.swift:214` — Existing universal-link entry seam; Events/Clip route and actual platform invocation still require implementation.
- `WanderTests/WanderStoreTests.swift:8853` — Adjacent metadata-finalization failure test avoids reuploading already-stored photo bytes.
- `Wander/App/WanderApp.swift:33` — Verify live auth/backend mode; existing Simulator fixture session is not integrated journey evidence.

## E10 — Confirmed guest's QR load fails → staff lookup/admission; repeat staff action; later source media reused in multiple posts then removed.

Owner: Joined release: before-event/door + after-event/map, with entry/identity foundation. Layers: integrated staged journey, browser E2E (planned Playwright), physical-device app/Clip verification, server-state assertions, isolated hosted HTTP/storage integration. Real-device evidence required: yes.

Planned files: `events-web/tests/journeys/e10.spec.ts`, `WanderUITests/Events/EventsIntegratedJourneyTests.swift`, `scripts/events/integrated-journey.mjs`, `docs/testing/astir-events-device-matrix.md`, `supabase/tests/events_media_references.sql`, `supabase/tests/events_completion_history.sql`, `supabase/functions/events-media-worker/index.test.ts`, `scripts/events/media-access-smoke.mjs`.

- One run ID binds actual surface actions, canonical user/event/booking/admission/completion/visit/media IDs, build versions and delivery intents. Bootstrap only starting fixtures; do not seed later happy states, inject fake session tokens into UI or stitch separate mocked stage results.
- Use isolated committed staging fixtures for HTTP/app/browser/worker interactions, real production-shape APIs and operator console; assert server facts through a read-only verifier after each boundary. SQL rollback tests are complementary, not this journey.
- Induce actual QR retrieval failure for a confirmed full-app guest with valid name/username; Team admin verifies through lookup and repeats manual admission with stable operation identity.
- Publish recap, complete once, reuse a source across multiple real personal posts, then remove it through uploader/admin controls.
- Assert one admission/visit per participating guest, no waiver of installed-account gate, all source references/derivatives inaccessible after removal, and other notes/media/history preserved. Exercise approved offline variant separately in TP03.

Source authority: A03/A05; P12/P13

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/PlacePhotoGalleryTests.swift:107` — Adjacent presenter suppresses locally deleted media from a stale remote page; useful Events tombstone regression pattern.
- `WanderTests/WanderStoreTests.swift:8853` — Adjacent metadata-finalization failure test avoids reuploading already-stored photo bytes.
- `supabase/tests/checkin_history_engagement.sql:99` — Adjacent owner-deletion test verifies history removal and no resurrection through repair; not Events coverage.
- `Wander/App/WanderApp.swift:33` — Verify live auth/backend mode; existing Simulator fixture session is not integrated journey evidence.

## E11 — Confirmed no-show and mistaken/revoked attendance attempt every recap entry route; another user has blocked/restricted content.

Owner: Joined release: before-event/door + after-event/map, with entry/identity foundation. Layers: integrated staged journey, browser E2E (planned Playwright), physical-device app/Clip verification, server-state assertions, isolated hosted HTTP/storage integration. Real-device evidence required: yes.

Planned files: `events-web/tests/journeys/e11.spec.ts`, `WanderUITests/Events/EventsIntegratedJourneyTests.swift`, `scripts/events/integrated-journey.mjs`, `docs/testing/astir-events-device-matrix.md`, `supabase/tests/events_recap_access.sql`, `supabase/tests/events_home_projections.sql`, `supabase/tests/events_media_references.sql`, `scripts/events/media-access-smoke.mjs`.

- One run ID binds actual surface actions, canonical user/event/booking/admission/completion/visit/media IDs, build versions and delivery intents. Bootstrap only starting fixtures; do not seed later happy states, inject fake session tokens into UI or stitch separate mocked stage results.
- Use isolated committed staging fixtures for HTTP/app/browser/worker interactions, real production-shape APIs and operator console; assert server facts through a read-only verifier after each boundary. SQL rollback tests are complementary, not this journey.
- Drive no-show and corrected-then-revoked attendance through actual link, Events, map, place, notification and direct-media paths; try self-report and stale cached/page responses.
- Create real restricted/blocked relation after permitted view; protected gallery/comments/range bytes and exact-home data must follow current independent gates on every entry route.
- Read server permission outcomes and delivered payloads/accessibility content; retained historical completion or public selected photo never becomes a recap entitlement bypass.

Source authority: P07/P15; A06; V08; H07

Adjacent existing evidence (not implemented Events coverage):
- `WanderTests/ActivityEngagementTests.swift:944` — Adjacent failure evicts previously visible activity; Events access must independently revalidate and clear protected projections.
- `WanderTests/ActivityEngagementTests.swift:989` — Suspended-response test rejects a result arriving after an account switch; reuse this test pattern, not as Events coverage.
- `supabase/tests/visible_place_photo_gallery.sql:429` — Adjacent gallery RLS test excludes blocked contributors; does not implement admission/completion access.
- `Wander/App/WanderApp.swift:33` — Verify live auth/backend mode; existing Simulator fixture session is not integrated journey evidence.

## E12 — Notification denied + event SMS opted out + later failed delivery; guest independently opens Events/canonical link through event change and recap publication.

Owner: Joined release: before-event/door + after-event/map, with entry/identity foundation. Layers: integrated staged journey, browser E2E (planned Playwright), physical-device app/Clip verification, server-state assertions. Real-device evidence required: yes.

Planned files: `events-web/tests/journeys/e12.spec.ts`, `WanderUITests/Events/EventsIntegratedJourneyTests.swift`, `scripts/events/integrated-journey.mjs`, `docs/testing/astir-events-device-matrix.md`, `supabase/tests/events_delivery_intents.sql`, `supabase/functions/events-message-worker/index.test.ts`.

- One run ID binds actual surface actions, canonical user/event/booking/admission/completion/visit/media IDs, build versions and delivery intents. Bootstrap only starting fixtures; do not seed later happy states, inject fake session tokens into UI or stitch separate mocked stage results.
- Use isolated committed staging fixtures for HTTP/app/browser/worker interactions, real production-shape APIs and operator console; assert server facts through a read-only verifier after each boundary. SQL rollback tests are complementary, not this journey.
- Physically deny notifications, record actual event-SMS opt-out, and exercise controlled failed delivery separately; then reschedule through console and publish recap.
- Open Events/canonical link directly at each stage and recover current schedule/booking/eligible recap actions without depending on any delivery.
- Assert obsolete schedule jobs do not dispatch, opt-out is respected, delivery state distinguishes queued/sent/failed, and recap invitation is not generated before publication plus valid admission.

Source authority: M05–M11; L01–L10

Adjacent existing evidence (not implemented Events coverage):
- `supabase/functions/push-notification-worker/index.test.ts:23` — Existing Deno tests distinguish APNs permanent and retryable failures; Events delivery/revision guards are new.
- `Wander/App/AppEntryView.swift:214` — Existing universal-link entry seam; Events/Clip route and actual platform invocation still require implementation.
- `Wander/App/WanderApp.swift:33` — Verify live auth/backend mode; existing Simulator fixture session is not integrated journey evidence.

## TB01 — transactional rollback smoke cannot prove concurrent allocation or booking-generation isolation.

Owner: events-data-and-rules. Layers: local pgTAP, planned hosted rollback smoke, Node pg multi-session concurrency (isolated disposable database). Real-device evidence required: no.

Planned files: `scripts/events-concurrency.test.mjs`, `supabase/tests/events_booking.sql`, `supabase/tests/events_invitation_codes.sql`, `supabase/tests/events_admission.sql`, `supabase/tests/events_notifications.sql`.

- Use at least two independent DB clients, committed isolated fixtures, explicit lock/barrier coordination and a third observation session; never substitute sequential requests inside one smoke transaction.
- Cover confirmation/offer/approval/cancellation/cap edit/code deactivation cross-races; verify limits, exactly-once logical effects, protected inventory, no orphan code redemption and bounded outcomes.
- An old cancellation/acceptance retry after cancel-and-rebook targets its original operation/generation and cannot mutate the new booking.
- Run only in disposable local/test database with fake delivery and isolated fixture teardown; not the hosted rollback-smoke path or production.

## TB02 — transaction-start time can accept an offer or new RSVP after its cutoff when lock acquisition is delayed.

Owner: events-data-and-rules. Layers: local pgTAP, planned hosted rollback smoke, Node pg multi-session concurrency (isolated disposable database). Real-device evidence required: no.

Planned files: `scripts/events-concurrency.test.mjs`, `supabase/tests/events_booking.sql`, `supabase/tests/events_invitation_codes.sql`.

- Hold event lock across deadline in session A while session B begins beforehand and waits; after release, B uses fresh authoritative server time and fails expired acceptance.
- Repeat for new registration cutoff and self-cancel start boundary; previously committed successful operation retry still returns current result.
- No fake client clock or cleanup-job execution substitutes for server-side after-lock check.

## TB03 — provider acceptance with a lost acknowledgement can yield duplicate physical SMS or a false delivered state.

Owner: shared-messaging-foundation. Layers: local pgTAP, planned hosted rollback smoke, Deno worker with fake clock/provider/network. Real-device evidence required: no.

Planned files: `supabase/tests/events_notifications.sql`, `supabase/functions/event-message-worker/index.test.ts`, `supabase/functions/push-notification-worker/events.test.ts`.

- Fake provider accepts then drops response; separately accept response then fail DB settlement. Preserve unknown outcome and stable logical identity.
- Validate chosen provider dedupe/status/callback capability before selecting retry mechanics; do not promise exactly-once external delivery from a DB uniqueness constraint.
- No fallback creates an extra SMS after planned SMS success or overrides opted-out channel; keep queued/submitted/delivered/read/attendance meanings separate.
- Concrete resend schedule and provider-specific fallback remain proposed; no real outbound communication during harness execution.

## TB04 — a partial door-batch response or expired authorization can silently discard unsynced admissions.

Owner: before-event-door. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment), Node pg multi-session concurrency (isolated disposable database). Real-device evidence required: no.

Planned files: `supabase/tests/events_admission.sql`, `supabase/tests/events_authorization.sql`, `supabase/tests/events_notifications.sql`, `scripts/events-concurrency.test.mjs`, `events-web/tests/console/offline-admission.spec.ts`.

- Mix committed, duplicate, conflicting and unprocessed rows; fail transport and/or permission mid-reconciliation, then replay original operation IDs.
- Only authoritative individual acknowledgements clear queued entries; unknown/conflict rows remain recoverable and recap remains locked until valid server admission.
- Re-authentication uses an authorized Team admin without changing acting-record attribution or exposing another account roster; do not claim all-success from HTTP success alone.

## TB05 — browser storage loss, account changes and shell updates can invalidate the claimed offline door capability.

Owner: before-event-door. Layers: Playwright stubbed UI, Playwright API-backed integration (isolated test environment), real iPhone / intended staff-browser device verification. Real-device evidence required: yes.

Planned files: `events-web/tests/console/offline-admission.spec.ts`, `events-web/tests/console/authorization.spec.ts`, `docs/testing/events/booking-door-real-device.md`.

- Inject failed IndexedDB/selected persistence commits and partial roster downloads; acknowledge only durable operations and atomically promote complete snapshots.
- On intended Safari/other staff devices test offline reload/close/background/update, quota denial, simulated/actual storage eviction, account switch and unsynced-work warning.
- No protected feedback/gallery/precise-home data in shared shell cache; no cross-account roster. If storage is absent, report unavailable, not empty synced queue.
- Persisting locally cannot guarantee immunity from OS eviction or immediate remote erasure; record supported behavior and product impact explicitly.

## TB06 — stale message work can leak location or claim obsolete booking/schedule state after cancellation, reschedule or consent change.

Owner: shared-messaging-foundation. Layers: local pgTAP, planned hosted rollback smoke, Deno worker with fake clock/provider/network, Node pg multi-session concurrency (isolated disposable database). Real-device evidence required: no.

Planned files: `supabase/tests/events_notifications.sql`, `supabase/tests/events_private_location.sql`, `supabase/tests/events_authorization.sql`, `supabase/functions/event-message-worker/index.test.ts`, `scripts/events-concurrency.test.mjs`.

- Claim message then alter event revision, booking eligibility, home reveal/expiry or channel consent before dispatch; revalidate relevant rights/current revision against authoritative state.
- Use payload spies to inspect all outbound fields, provider metadata, analytics and logs, not only template display; no unauthorized exact home coordinates/address/private comments/phone list.
- Unavoidable change after provider submission is not claimed retractable; canonical link always returns current viewer-owned state.
- P10 exact suppression/fallback policy remains unselected; confidentiality and current-state accuracy are release-blocking invariants.

## TB07 — UI-only Team admin checks or service-role testing can hide missing RLS and unsafe RPC grants.

Owner: events-data-and-rules. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment). Real-device evidence required: no.

Planned files: `supabase/tests/events_authorization.sql`, `supabase/tests/events_private_location.sql`, `supabase/tests/events_admission.sql`, `scripts/supabase-smoke-test.mjs`, `events-web/tests/console/authorization.spec.ts`.

- Run anonymous, ordinary, active/revoked Team admin and wrong-account requests using genuine client roles; no service-role-only API pass counts as guest authorization coverage.
- Inspect function signatures/security mode/search_path/grants and direct table/storage access; service-only claim/settlement hooks must reject public client roles.
- Guest-preview APIs cannot inherit console privileges; already-open page and stale auth cannot create current server access. Offline authorization caveat is tested separately, not used to waive server checks.

## TB08 — mocked browser screens alone cannot prove the no-install-to-native door or actual offline scanner flow.

Owner: entry-and-identity. Layers: Playwright stubbed UI, Playwright API-backed integration (isolated test environment), native XCTest / XCUITest, real iPhone / intended staff-browser device verification. Real-device evidence required: yes.

Planned files: `events-web/tests/guest/rsvp.spec.ts`, `events-web/tests/guest/manage-rsvp.spec.ts`, `events-web/tests/console/admission.spec.ts`, `events-web/tests/console/offline-admission.spec.ts`, `WanderUITests/EventsAdmissionUITests.swift`, `WanderUITests/EventsMessageReturnUITests.swift`, `docs/testing/events/booking-door-real-device.md`.

- API-backed guest and console runs use seeded isolated backend, real role tokens and persisted operations while SMS/APNs transport remains fake.
- Separately perform physical iPhone App Clip/web/app identity recovery, account completion before QR, real scanner camera and uninstall/reinstall after-event return with original account.
- Record actual host/build/device/browser/commit and outcomes; no Playwright browser fixture claims App Clip, OS universal-link selection, app-installed detection or device storage durability.

## TB09 — worker claim and settlement retry can turn a mixed delivery batch into whole-batch success.

Owner: shared-messaging-foundation. Layers: local pgTAP, planned hosted rollback smoke, Deno worker with fake clock/provider/network. Real-device evidence required: no.

Planned files: `supabase/tests/events_notifications.sql`, `supabase/functions/event-message-worker/index.test.ts`, `supabase/functions/push-notification-worker/events.test.ts`.

- Create multiple logical messages and multiple device tokens with accepted, retryable, permanent-token, permanent-event, unknown and failed-settlement outcomes.
- Accepted successes are not resent; valid devices survive another token permanent failure; stale lease cannot overwrite a newer claim or resurrect a terminal message.
- Authenticated provider callback adapter, once selected, rejects invalid signatures, binds provider ID to intended message and handles duplicate/out-of-order callbacks without granting guest rights.
- Analytics failure cannot roll back settled delivery or leak recipient content. Provider callback and retry details remain implementation/provider-contract checks, not newly approved cadence.

## TB10 — malformed or stale cross-surface result can flatten unknown/denied into success or another account state.

Owner: entry-and-identity. Layers: local pgTAP, planned hosted rollback smoke, Playwright stubbed UI, Playwright API-backed integration (isolated test environment), native XCTest / XCUITest. Real-device evidence required: no.

Planned files: `events-contracts/fixtures/booking-door.json`, `supabase/tests/events_authorization.sql`, `events-web/tests/guest/rsvp.spec.ts`, `events-web/tests/guest/manage-rsvp.spec.ts`, `events-web/tests/console/admission.spec.ts`, `WanderUITests/EventsAdmissionUITests.swift`.

- Feed shared fixtures for lookup loading/failure/no-match, pending/waitlist/offer/confirmed/canceled, unsupported enum and malformed response into Swift and web consumers.
- No missing/unknown state defaults to confirmed; 401/session-expired differs from authenticated 403 and expected capacity/code/expiry outcomes.
- Switch accounts while lookup/mutation completes: stale response cannot attach booking, phone, QR or protected roster to new account; resolve unknown committed mutation by original operation identity.

## TN01 — D16 shared boundary is not proven by folder naming or full-app-only tests.

Owner: Entry/identity foundation; one shared project/auth owner. Layers: native XCTest, App Clip build/test target integration. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventsSourceBoundaryTests.swift`, `AstirEventsClipTests/EventsSharedCompositionTests.swift`, `project.yml`.

- Build the actual thin Clip with its selected sources/resources and test host, without WanderStore/WanderBackend/root/map/history source membership.
- Shared presentation composes with host-provided auth/navigation and small contract values; retain common fixtures without target-local copied policy.
- Treat generated-project/source-set assertions as supporting checks; a successful full Clip build is the dependency-boundary evidence.

## TN02 — Generic transport errors can collapse denied, absent and uncertain operation states.

Owner: Entry/identity foundation with Events data/rules contract owner. Layers: native XCTest, guest-web Playwright, controlled-service integration. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventRepositoryOutcomeTests.swift`, `events-web/tests/guest/lookup-recovery.spec.ts`, `tests/fixtures/events/entry-states.json`.

- Use typed outcomes for no booking, auth required, signed-in denial, expired/canceled/capacity result, transient failure and unknown completion; malformed/unknown values fail closed.
- Exercise 401 refresh, signed-in 403 denial, refresh failure, stale-token replacement and a response crossing account switch; retain existing non-Events refresh behavior.
- A mutation timeout after commit uses the same operation identity/current-state lookup; never infer replay safety from a human-readable error string.

## TN03 — Public invocation/distribution and real provider continuity cannot be proved by fixtures.

Owner: Entry/identity foundation; release integrator validates distribution. Layers: physical-device integration, controlled-service integration. Real-device evidence required: yes.

Planned files: `docs/testing/astir-events-device-entry.md`.

- Record actual public Clip invocation, associated-domain behavior, Apple and Google Clip/browser authentication, verified-current-phone proof, and full-app install/icon-launch recovery using controlled accounts.
- Repeat relevant installed/not-installed/wrong-account/expired-session paths on intended TestFlight and public builds; a TestFlight result is not public App Clip publication proof.
- Capture build/distribution, OS/device, link source, identity/booking continuity and safe failed-invocation recovery; identify unavailable variants as blocked, never passed.

## TN04 — Cold launch and account changes can adopt stale pending intent, request or protected presentation.

Owner: Entry/identity foundation; Before-event/door continuation owner. Layers: native XCTest, full-app XCUITest, App Clip XCUITest, guest-web Playwright, controlled-service integration. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventAccountRecoveryTests.swift`, `WanderUITests/Events/EventAccountRecoveryUITests.swift`, `AstirEventsClipUITests/EventAccountRecoveryUITests.swift`, `events-web/tests/guest/account-recovery.spec.ts`.

- Suspend token refresh, booking lookup or a mutation response, then sign out/switch accounts/terminate; releasing old work cannot publish protected state for the new account.
- Keep safe event intent separate from account-owned booking/draft/operation identity; re-resolve the booking after legitimate recovery.
- Control rapid valid links for different events and an invalid URL between them; the active intent and corresponding result remain correlated, without inventing a new product multi-event selection policy.

## TN05 — Nine-state visual parity can hide unusable identity/recovery controls or inaccessible protected text.

Owner: Before-event/door with entry foundation integration. Layers: full-app XCUITest, App Clip XCUITest, guest-web Playwright, physical-device integration. Real-device evidence required: yes.

Planned files: `WanderUITests/Events/EventEntryAccessibilityUITests.swift`, `AstirEventsClipUITests/EventEntryAccessibilityUITests.swift`, `events-web/tests/guest/entry-accessibility.spec.ts`, `docs/testing/astir-events-device-entry.md`.

- Exercise large text, long event/person names, keyboard-visible phone/code/username fields and a small supported phone; primary/retry/back actions remain reachable.
- VoiceOver and web accessible names distinguish unknown/loading/failed/no-booking/confirmed without announcing protected guest-list/address data in ineligible states.
- Perform a physical VoiceOver pass for real provider return and recovery focus; screenshots alone do not establish accessibility.

## TP01 — Protected media must enforce current permission/source version for bytes, derivatives and video ranges despite signed URLs and warm caches.

Owner: After the event and on the map. Layers: PostgreSQL pgTAP, hosted rollback pgTAP, Deno handler/worker tests, isolated hosted HTTP/storage integration, XCTest unit/adapter. Real-device evidence required: yes.

Planned files: `supabase/tests/events_recap_access.sql`, `supabase/tests/events_media_references.sql`, `supabase/functions/events-media/handler.test.ts`, `supabase/functions/events-media-worker/index.test.ts`, `scripts/events/media-access-smoke.mjs`, `WanderTests/Events/EventProtectedCacheTests.swift`.

- Test GET, HEAD and single/multi-range or explicitly rejected unsupported Range requests; every successful 200/206 carries only authorized bytes, and 304/cache validation cannot reuse a forbidden representation.
- Warm CDN, browser, memory and disk caches; revoke admission, block/limit post audience, remove source and switch accounts while a download/derivative job is suspended. Recheck authorization at delivery/finalization and reject stale results.
- Simulate object-deletion/worker failure and retry: acknowledged tombstone immediately prevents product-surface delivery while cleanup retries; derivative completion after removal cannot resurrect the source. No promise to recall previously copied bytes.

## TP02 — D13 rescheduling can move home reveal/expiry backward while exact data is already cached; relative and absolute rules need boundary regression.

Owner: After the event and on the map; before-event schedule contract owner. Layers: PostgreSQL pgTAP, hosted rollback pgTAP, XCTest unit/adapter, browser E2E (planned Playwright), physical-device verification. Real-device evidence required: yes.

Planned files: `supabase/tests/events_home_projections.sql`, `WanderTests/Events/EventHomeProjectionTests.swift`, `events-web/tests/guest/home-privacy.spec.ts`, `docs/testing/astir-events-device-matrix.md`.

- Change event revision after home reveal; move relative reveal later and confirm exact event-only projection retires until eligible again, while explicit absolute overrides are not reinterpreted.
- A delayed response from the prior schedule/version cannot restore exact address/nav; before/at/after boundaries use authoritative time including time-zone and daylight-saving cases.
- Booking/admission/completion, independent location rights and ordinary place history remain unchanged; already exported calendar/address copies are not claimed recalled.

## TP03 — D9 offline admission must not prematurely grant completion/recap or corrupt history when reconciliation rejects or duplicates an operation.

Owner: Joined release: before-event/door + after-event/map, with entry/identity foundation. Layers: PostgreSQL pgTAP, hosted rollback pgTAP, browser E2E (planned Playwright), physical-device verification. Real-device evidence required: yes.

Planned files: `supabase/tests/events_offline_admission_reconciliation.sql`, `supabase/tests/events_recap_access.sql`, `supabase/tests/events_completion_history.sql`, `events-web/tests/console/offline-admission-recap.spec.ts`, `scripts/events/integrated-journey.mjs`, `docs/testing/astir-events-device-matrix.md`.

- Admit offline using a previously authorized roster, reopen operator browser and retain same durable operation ID; guest recap remains locked until actual server validation.
- Reconnect with duplicate operation, canceled booking, removed admin, rescheduled event and conflicting second-device admission; valid result records once, conflicts remain visible without phantom admission/completion/visit.
- After valid reconciliation continue into actual check-in; one visit preserves prior rating/note/audience/save. Offline queue belongs to original account/event and is not reassigned or silently deleted on account change.

## TR01 — Cross-client schema and permission compatibility

Owner: shared-contract. Layers: native-unit, web-unit, api-integration. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventWireContractTests.swift`, `events-web/tests/contracts/event-wire-contract.spec.ts`, `supabase/tests/events_contract_compatibility.sql`.

- Decode the same controlled response fixtures in Swift and web; compare canonical IDs, states, timestamps and permitted fields.
- Unknown or missing security-relevant states/capabilities cannot default to confirmed or expose protected fields; distinguish optional additions from incompatible payloads.
- Exercise older/newer contract fixtures and a failed decode without dropping event/account recovery context.

## TR02 — Migration and older-client regression boundary

Owner: shared-integration. Layers: database-integration, native-regression, release-integration. Real-device evidence required: yes.

Planned files: `supabase/tests/events_migration_compatibility.sql`, `WanderTests/Events/EventSnapshotCompatibilityTests.swift`, `docs/testing/astir-events-release-compatibility.md`.

- Load existing ordinary place/visit/engagement data and older local snapshots, migrate and run ordinary saves/reads plus Events; retain ratings, audiences, notes, IDs and explicit save intent.
- Test additive rollout with older app/new backend and newer app/preactivation configuration; fail safely when Events capability is unavailable.
- Verify a rollback/feature-disable path does not erase confirmed bookings, queued door work or preexisting place history.
- Against current REC-494 display grouping, preserve the canonical event visit/activity and original engagement route for comments, likes, sharing and deletion; grouping never merges distinct visits or replaces their IDs with the group container.

## TR03 — Analytics and error evidence excludes protected content

Owner: shared-contract. Layers: native-unit, worker-unit, web-unit. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventAnalyticsPrivacyTests.swift`, `supabase/functions/events-notification-worker/privacy.test.ts`, `events-web/tests/contracts/event-telemetry.spec.ts`.

- Inject phone/address/private feedback/media/token-bearing failures and assert logs, analytics and user-visible generic errors contain none of those values.
- Export delivery/frequency aggregates only; no recipient/event/actor/APNs IDs, message body, tokens or deep links in PostHog delivery analytics.
- State transition metrics follow committed logical actions, not duplicate taps, failed writes, callbacks or resend retries.

## TR04 — Launch configuration and independent authorization

Owner: shared-integration. Layers: native-unit, api-integration, web-e2e, release-integration. Real-device evidence required: yes.

Planned files: `WanderTests/Events/EventFeatureConfigurationTests.swift`, `supabase/tests/events_launch_permissions.sql`, `events-web/tests/console/launch-configuration.spec.ts`, `docs/testing/astir-events-release-compatibility.md`.

- Guest feature visibility or console preview flags cannot grant Team admin, recap, admission or exact-home permission through direct API requests.
- Compatible app/Clip/browser/backend configuration is checked before public Events activation; main-app release alone is not a Clip release.
- A normal app restart/account switch follows the existing typed flag behavior without revealing another account state; missing configuration is an explicit unavailable state.

## TR05 — Physical-clock and scheduler discontinuities

Owner: shared-contract. Layers: native-unit, database-integration, worker-integration, web-unit. Real-device evidence required: no.

Planned files: `WanderTests/Events/EventTimeBoundaryTests.swift`, `supabase/tests/events_time_boundaries.sql`, `supabase/functions/events-notification-worker/time.test.ts`, `events-web/tests/contracts/event-time.spec.ts`.

- Test before/at/after each deadline, fractional precision, event-local formatting and daylight-saving boundaries using absolute server instants.
- Change event date/time or configured reveal/expiry/registration override and reject obsolete scheduled work without silently extending an offer.
- Include a transaction blocked until after offer expiry; enforce current authoritative time after lock acquisition rather than client or transaction-start time.

## TR06 — Independent host build and source boundaries

Owner: entry-identity. Layers: build-contract, native-unit, release-integration. Real-device evidence required: yes.

Planned files: `WanderTests/Events/EventTargetBoundaryTests.swift`, `AstirEventsClipUITests/EventClipLaunchTests.swift`, `docs/testing/astir-events-release-compatibility.md`.

- Build the full app and Clip with their real selected sources, signed dependencies and resources; Clip cannot obtain its auth helper by pulling in full-app store/map/root.
- Check app/Clip association, entitlements, environment, supported OS and contract compatibility on exact release artifacts.
- Shared source inclusion does not accidentally ship Team admin/service credentials or debug fixture bypasses.
