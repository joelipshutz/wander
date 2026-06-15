# Roadmap

Last updated: 2026-06-15

This is the durable milestone view. The detailed source plan is `docs/plans/2026-06-01-wander-ios-eng-plan.md`.

## Current Status

Build `0.1 (25)` is live and approved on public TestFlight. M2 through M5 are accepted enough for alpha iteration: native map/add/discover/profile/settings, Clerk sign-in, Supabase sync, social graph baseline, current-location/manual add, map search/typeahead, rich place sheets, and TestFlight release process are in place.

M6 is the active milestone. Signed-in link/photo drafts enqueue durable Supabase extraction jobs, and the backend worker can process coordinate-backed link candidates without auto-saving. The current branch fixes the stale boundary-import test, adds no-billing Apple Maps coordinate link support, improves Google Maps `/maps/search/...` name parsing, and keeps parks categorized as `park` rather than `hike`. The updated `extraction-worker` Edge Function was deployed to Supabase project `rugmtlgufrhlxwfkumhw` on 2026-06-15.

Still not done in M6: photo OCR, TikTok/Instagram extraction beyond manual fallback, analytics, privacy/onboarding gates, production performance sweep, and the final friend-testing QA pass.

## Milestones

| Milestone | Status | Goal | Notes |
|---|---|---|---|
| M0 Repo and project bootstrap | Done | Runnable native iOS foundation. | SwiftUI app shell, four tabs, XcodeGen, token layer, tests. |
| M1 Local data and repository contracts | Done baseline | Model/service boundaries before UI logic spreads. | Local models, repository protocols, parser/provider contracts, sync state tests. |
| M1.5 Contract lock | Done baseline | Freeze schema/RLS/local/UI contracts before M2. | See `docs/plans/2026-06-01-wander-m1-5-contract-lock.md`. |
| M2 Core local product loop | Done baseline | Validate map/add/discover/profile/settings loop before backend. | Native UI has moved into TestFlight iteration. |
| M3 Clerk + Supabase foundation | Done baseline | Real identity, schema, RLS, and policy tests. | Supabase/Clerk projects created, hosted tests passed, profile mirroring and iOS sign-in smoke passed. |
| M4 Sync and remote repositories | Done baseline | Replace local-only store paths with local-first remote sync. | Remote visible places/profile search/follow/block/social-save/direct-own-save paths are wired. Public TestFlight is approved for external testers. |
| M5 Extraction and smart Discover | Accepted baseline | Make Add capture real and add cheap LLM parsing where it helps. | Add UX/navigation, current-location, manual place resolution, and map search scope were cleaned up for TestFlight; provider-backed link/photo extraction moves into M6. |
| M6 Backend extraction and alpha readiness | In progress | End-to-end alpha loop and provider-safe extraction foundation. | Enqueue + worker RPCs + Edge Function are live. Coordinate-backed Google/web/Apple map-link candidates can return to Add confirmation; no low-confidence auto-save. Photo OCR, TikTok/Instagram fallbacks, analytics, privacy copy, onboarding/auth gates, performance, and final QA remain. |

## Immediate Next Steps

1. QA Build `0.1 (25)` using `docs/qa/2026-06-15-build-25-current-qa-and-m6-checklist.md`; capture any fails with device/account/screenshot/repro.
2. Merge the M6 worker patch and keep the deployed function in sync with `main`: boundary test path fix, Apple Maps coordinate-backed links, Google Maps search path parsing, and park category inference.
3. Keep provider expansion no-billing and confidence-gated: Google/Apple map links first, generic coordinate metadata second, manual fallback for unsupported social/photo sources until real OCR/provider proof exists.
4. Add alpha readiness basics: analytics event interface, privacy copy around contacts/location/extraction, onboarding/auth gates for save/follow/social actions, performance pass, and final friend-testing QA checklist.

## Roadmap After M6

| Area | Next Outcome | Notes |
|---|---|---|
| M6 finish | Provider-safe extraction and alpha QA. | Deploy worker, validate map links, keep unsupported sources as drafts/manual rescue, add analytics/privacy/performance basics. |
| M7 Alpha onboarding and trust | First-time user loop is understandable without Joe explaining it. | Auth gates, empty states, privacy copy, sign-out/account controls, no demo seed leakage. |
| M8 Social reliability | Friends/follows and visible places feel dependable across accounts. | Remote refresh, follower/following/friends QA, blocked-user hiding, social save edge cases, stale-cache handling. |
| M9 Capture expansion | Capture feels useful beyond manual/current-location. | Better link routing, photo OCR if feasible without paid dependencies, share extension later, custom questions later. |
| M10 Public share surface | Shared place/profile links have a clean web fallback. | App link if installed, lightweight web page if not, download prompt; later TODO only for now. |
| M11 Native polish | App feels ready for broader tester group. | Accessibility, haptics, loading/error states, simulator/device visual sweep, crash/perf pass. |

## M2 Acceptance Criteria

Functional:

- Guest can save a first place locally.
- Current-location and manual add are real local saves.
- Link/photo create unresolved drafts and do not fake extraction.
- User can follow, unfollow, block, and unblock seeded users.
- Visibility changes affect visible social content.
- Username search and fake contact results work.
- Discover smart filters are deterministic and local.

Visual:

- Map fills the full phone viewport and feels native.
- Top controls, chips, selected place sheet, and tab bar do not crowd each other.
- Safe areas and home indicator are respected.
- Text fits inside controls on current and smaller iPhone targets.
- Warm handoff style from `preview/follow-profile-settings-mocks/` is preserved without oversized mock chrome.

Testing:

- `xcodebuild test` passes.
- Simulator screenshots captured for at least the active target and one smaller phone.

## Later Backlog

- Native Contacts permission and backend hashed matching.
- Share extension.
- Private profiles/follow requests.
- Full onboarding implementation.
- Backend extraction job workers and real photo/link extraction providers.
- Multi-device conflict resolution beyond simple server-wins/retry queue.
- iPad side-panel layout.
