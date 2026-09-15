# Native and entry test mapping — planned only

This maps **exactly 29 cases: L01–L17 and I01–I12**, plus five technical risks (TN01–TN05), against checkout `f8d258e869503a28d70518a050dff36a344134c6`. Engineering D3A and D16A govern recovery and component boundaries; the parent reported D17A approval to begin test review. All tests remain **NOT IMPLEMENTED / NOT EXECUTED**. No application, service, simulator or device work occurred.

The machine-readable mapping is [native-entry.json](native-entry.json). It records concrete future files, layers, assertions, ownership and adjacent evidence for every case. Future path names are planning conventions, not newly created test files or an implementation approval.

## Layer split

- Native XCTest covers shared state mapping, typed outcomes, expected-account fencing, identity essentials, verification proof and retry operation identity. Existing app-host tests are useful, but TN01 separately requires compiling the actual Clip with selected shared sources so an accidental full-app dependency cannot hide behind `@testable import Wander`.
- Full-app and new Clip XCUITests cover actual host presentation, Events navigation, recovery, no-app management and entry setup. Existing fixture launch flags may support deterministic UI tests; they cannot establish real auth or transfer.
- New guest-web Playwright cases run both deterministic response fixtures and a separate controlled-service integration mode. There is no guest-web Playwright harness in the inspected source; `scripts/package.json` currently declares Node helper tests. Web and Swift compare the same language-neutral contract fixtures.
- Service assertions verify identity/booking ownership, one reservation/operation result, current phone proof, capacity races, and one logical confirmation outbox intent. Those depend on the data/rules test oracle; a fake response or client request count never satisfies them.
- Physical-device integration proves real Apple/Google Clip and browser auth, actual SMS verification, public Clip invocation, failed invocation fallback, optional-install continuation, wrong-account recovery, and install followed by icon launch. TestFlight and public distribution outcomes are recorded separately. Public deployment or provider conditions that cannot be exercised stay blocked/unverified.

## Highest-priority gaps

1. **Phone proof is new.** `AuthSessionProviding.swift:48–53` carries a phone string, not verification provenance. I01–I04 require authoritative proof tied to the current account and current number. Changed/old-number proof, wrong/expired/superseded challenges, provider failures, capacity filled during verification and offer expiry are explicit variants.
2. **Existing social-auth tests are simulated.** `AuthSessionTests.swift:159,279` use `PreviewAuthSessionProvider`; `:565` injects lost activation response. They support regression testing but do not prove Clerk 1.5.0 in a real Clip, public invocation or Clip/browser-to-app identity continuity.
3. **Current transport collapses outcomes.** `BuildConfigurationTests.swift:602` intentionally treats both 401 and 403 as refreshable. TN02 and L10/L15 require the Events contract to preserve signed-in denial, auth-required, absence, expected booking outcomes and unknown completion without parsing human error text or changing unrelated legacy behavior.
4. **Install recovery is an acceptance gate.** I07 must prove the originating event and original booking after installation and icon launch. `OnboardingUITests.swift:598` proves only that a simulator fixture survives relaunch. It cannot stand in for a missing transfer mechanism.
5. **Preserve actual account fencing.** `AuthSessionTests.swift:1441` and `RemoteRepositoryTests.swift:1103` exercise stale work rejection. New Events tests must extend that protection to booking state, operations, drafts, protected projections and host return, including sign-out/switch during delayed work.

## Authority boundaries

The mapping keeps unknown identity, loading/failure, successful no-booking, pending, waitlisted, offered and confirmed separate. It preserves no-app full guest list/management for confirmed guests; install is not an early RSVP gate. D3A requires original-account recovery rather than another RSVP or silent merge. Missing valid name/username gates entry; profile photo does not. Event-specific texts do not imply future-event marketing consent.

P01 auth-interruption interaction, P02 exact SMS timing, P11 post-expiry presentation, P13 general onboarding resumption and P19 unavailable presentation remain proposals where the source labels them so. Their approved invariants are mapped, but this test plan does not approve their exact UI or operating policy. D3A’s essentials-only event recovery is already approved even though the later general-onboarding presentation remains proposed.

L01–L03 have the five named link origins. L04–L11 cover each applicable host. L17 is the explicit nine-state parity matrix. This is an auditable inventory, not a claim to have exercised an unlimited Cartesian product.

## Ownership and evidence

Entry/identity foundation owns host integration, auth/transport and invocation proof; Before-event/door owns the continuing guest journey. Data/rules supplies authoritative fixtures and assertions. One active editor owns shared contracts/project/auth/root seams under D8/D16. The test file convention uses `WanderTests/Events`, `WanderUITests/Events`, new `AstirEventsClipTests`/`AstirEventsClipUITests`, `events-web/tests/guest`, and `docs/testing/astir-events-device-entry.md`; only this mapping and JSON were created.

Each eventual run must capture case/variant, fixture IDs, exact build and distribution, host/OS/device, clock/timezone, observed result, server-state assertions and message outbox evidence when relevant. No tokens, SMS codes, private phone values, real attendee messages or live-event mutations belong in the evidence. Source-level supporting tests must be labeled adjacent and never counted as completed Events coverage.
