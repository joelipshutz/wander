# Recap/history test-review mapping

Planning only. No tests were implemented or run, and no hosted service was changed. The 44 mappings cover exactly P01–P17, V01–V08, H01–H07 and E01–E12 against review checkout `f8d258e869503a28d70518a050dff36a344134c6` (app-code ancestor `a0117cff6ed55a967f4212b45bb28d8c39ca1488`). Existing adjacent tests are reuse evidence, not Events coverage.

## Tests that must prove server facts

- Completion is one atomic event completion plus one canonical event-labeled visit, with a null venue rating. Existing ordinary Been behavior intentionally supplies a default rating; retain that ordinary behavior and test the separate Events adapter. Snapshot the independent visit IDs, ratings, notes, audiences, explicit save intent and conversation IDs before and after completion/deletion/retry.
- Historical completion survives deleting the personal event post/visit; current admission still controls recap access. Personal-post audience, booking-based home address, admission/completion and independent place rights are separate axes, including canceled bookings, revoked admissions and expired address windows.
- Source removal retires every gallery/post reference and derivative without deleting other media or visits. Test actual authenticated bytes and range-video responses, stale signed links, warm CDN/browser/native caches and delayed workers. A storage deletion or URL TTL alone cannot prove revocation. TP01 makes these failure paths explicit.
- Read projections must omit protected comment text, media URLs, address, exact coordinates and navigation targets where unauthorized. A blur or a screenshot cannot prove privacy. Inspect JSON, DOM, accessibility trees, actual file metadata, cached responses and alternate place/search/share/calendar paths.
- D13 rescheduling recomputes relative home boundaries and invalidates old projections while preserving explicit absolute overrides and independent rights (TP02). D9 offline door records never unlock recap until server reconciliation; duplicate/rejected work remains visible without phantom admission or visit (TP03).

## Framework and fixture boundaries

The existing suite uses app-hosted XCTest (`project.yml:265`), pgTAP with role/JWT changes and rollback (`supabase/tests/checkin_history_engagement.sql:1`), injectable Deno worker/handler tests (`supabase/functions/place-photo/handler.test.ts:5`), and a hosted rollback runner (`scripts/supabase-smoke-test.mjs:68`). The existing `WanderUITests` target (`project.yml:293`) is also XCTest-based. Extend the existing native targets; new Events test files, Clip/shared-source wiring and a browser Playwright runner are proposed work. Keep framework additions narrow; no new general cross-platform test framework is required.

Use reserved Event A/public venue, Event B/same venue, Event H/consented home, distinct test users and controlled time. SQL tests should inspect function grants/security/search path as well as data results; role impersonation does not itself validate actual Clerk JWT transport. Retain and run adjacent ordinary-history, visibility, engagement and media suites as regressions during implementation.

Rollback-only hosted SQL is appropriate for relational/RLS contracts. It cannot be used as the whole E2E fixture setup: app, worker and HTTP clients cannot consume another connection's uncommitted fixtures, and stored bytes/provider sends are not reversed by database rollback. Integrated staging runs require committed isolated fixtures, controlled test recipients and cleanup. Record actual cleanup failures rather than labeling them rollback-safe.

## E01–E12: one continuous run each

Each journey carries one run ID and stable canonical account/event/booking/admission/completion/visit/media IDs across real app/Clip/browser/operator actions. Bootstrap only the starting state. Confirmation must be produced by RSVP, admission by QR/operator action and completion by check-in; do not seed later states or concatenate separate mocks. Read-only server verification after each boundary establishes record counts, permissions, delivery revision/intent and identity continuity. Auth UI, invocation, install-from-icon, uninstall/reinstall, QR camera, real media playback, share sheet, push permission and accessibility behavior require physical-device evidence where specified. Existing `docs/setup.md:502–509` makes signed-device Apple credential exchange an explicit release gate. Integrated runs must verify live Clerk/backend mode (`Wander/App/WanderApp.swift:33`), not the persisted Simulator preview account. Existing auth and route tests substitute identity or test local state and cannot prove server continuity.

The planned runner may coordinate browser/native automation and documented human App Store/provider actions, but results must distinguish automated, manual and unverified steps. Record build versions, platform/OS, timestamps/time zone, fixture IDs, actual URL invocation outcome, server assertions, outbox/provider result, and per-step failure. A test inbox with no actual send proves outbox behavior, not SMS or APNs delivery. E12 also proves recovery when delivery never succeeds.

## Product clauses left conditional

P05's exact retry/explicit-omission interaction (P06 proposal), P16's unavailable/republish policy, P17's external share payload and H06's calendar update mechanics stay conditional. Own gallery photo/video upload is approved; own video in the personal check-in composer is still proposed. Pin shape/glow/pulse selection and consent capture procedure remain review inputs. These mappings neither select them nor turn screenshot differences into product failures.

## Ownership

The after-event/map package owns P/V/H implementations with the designated shared-history integrator for atomic canonical-history hooks. Before-event/door contributes admission, schedule and delivery dependencies. The joined release owns every E case and TP03; no lane may claim end-to-end coverage from independently passing mocks. Existing snapshots and native design captures remain design evidence only.
