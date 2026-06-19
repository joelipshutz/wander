# Roadmap

Last updated: 2026-06-18

This is the durable milestone view. The detailed source plan is `docs/plans/2026-06-01-wander-ios-eng-plan.md`.

## Current Status

Build `0.1 (29)` is live and approved on public TestFlight. M2 through M6 are accepted enough for alpha iteration: native map/add/discover/profile/settings, Clerk sign-in, Supabase sync, social graph baseline, current-location/manual add, map search/typeahead, rich place sheets, Add-tab search, social map filter, backend extraction worker foundation, and TestFlight release process are in place.

M7 and M8 are the active alpha milestones. M7 is about onboarding/trust clarity: first-time testers should understand save visibility, sign-in, location use, and sync behavior without Joe explaining it. M8 is about social reliability: followed/friend users and their visible places must appear consistently across Discover, Map, Profile, refresh, and relaunch.

Detailed M7/M8 plan: `docs/plans/2026-06-18-m7-m8-alpha-plan.md`.

Coordination note: another agent is actively working on M8 social reliability in `/private/tmp/recme-followed-users-surfaces`, touching Map/Discover/Profile/store/tests. Non-overlapping M7 work should stay in Settings/Auth/docs unless ownership is explicitly handed off.

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
| M6 Backend extraction and alpha readiness | Accepted baseline | End-to-end alpha loop and provider-safe extraction foundation. | Enqueue + worker RPCs + Edge Function are live. Coordinate-backed Google/web/Apple map-link candidates can return to Add confirmation; no low-confidence auto-save. Photo OCR and TikTok/Instagram expansion are deferred into M9 capture expansion unless Joe reprioritizes them. |
| M7 Alpha onboarding and trust | In progress | First-time user loop is understandable without Joe explaining it. | Add trust/privacy Settings surface, tighten auth gate copy, improve empty/first-run state clarity, and keep no demo seed leakage. |
| M8 Social reliability | In progress | Friends/follows and visible places feel dependable across accounts. | Active work targets REC-7/REC-9/REC-10: relationship hydration, remote visible-place refresh, follow state consistency, and blocked-user/stale-cache behavior. |

## Immediate Next Steps

1. Land M7 trust/privacy Settings surface and auth-copy polish from `codex/m7-alpha-trust`.
2. Let the active M8 worktree finish REC-7/REC-9/REC-10, or explicitly take ownership if that branch stalls.
3. Decide whether to ship M7 by itself or batch M7 with M8 into the next TestFlight build.
4. After M8 ships, run a two-account QA pass focused on follow, mutual/friend visibility, unfollow revocation, block hiding, and relaunch refresh.

## Roadmap After M6

| Area | Next Outcome | Notes |
|---|---|---|
| M7 finish | Alpha trust loop is clear. | Settings trust/privacy surface, auth gates, empty states, sign-out/account controls, no demo seed leakage. |
| M8 finish | Social graph feels dependable. | Remote refresh, follower/following/friends QA, blocked-user hiding, social save edge cases, stale-cache handling. |
| M9 Capture expansion | Capture feels useful beyond manual/current-location. | Better link routing, photo OCR if feasible without paid dependencies, TikTok/Instagram fallback expansion, share extension later, custom questions later. |
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
