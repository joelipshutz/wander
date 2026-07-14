# REC-89 Profile Redesign Engineering Plan

Date: 2026-07-13
Branch: `codex/rec-89-profile-redesign`
Linear: `REC-89`
Status: design-first; production implementation is gated on mockup approval

## Problem

The current Profile surface is an operational dashboard. Identity is compressed into a small card while This Month, Drafts, Recent, and People compete for attention. The requested redesign makes the member and their place history the organizing idea: identity and social graph first, Been/Wanna next, then a visit calendar and geographic/category summaries.

Settings also needs a clearer ownership model. Account security belongs to Clerk, profile/social data belongs to the rec.me backend, privacy controls belong on a dedicated page, and blocked/muted management needs its own destination.

## Scope Challenge

The complete request spans UI, app navigation, identity, social graph, a new mute contract, profile editing, account deletion, notification filtering, storage cleanup, analytics aggregation, and backend security. Shipping that as one PR would touch well over eight files and several high-conflict modules.

The user already set the correct scope gate: show every SwiftUI mockup before production functionality or wiring. REC-89 therefore has two explicit stages:

1. This branch: deterministic debug-only mockups, review artifacts, screenshots, and launch-contract tests.
2. After visual approval: multiple production PRs, each with a narrow contract and complete tests.

This is a scope reduction for the current branch, not a feature cut.

## What Already Exists

| Requirement | Existing code | Reuse decision |
|---|---|---|
| Owner identity and member date | `LocalProfile` already stores display name, handle, avatar URL, bio, home area, and `createdAt`. | Reuse directly; no new profile model for the owner header. |
| Profile photo persistence | Existing avatar upload/delete flow and `WanderAvatar` / `EditableProfileAvatar`. | Reuse production flow and shared avatar renderer. Mockups use deterministic initials. |
| Followers and following | `WanderStore.followers(of:)`, `following(of:)`, remote graph repositories. | Reuse. |
| Friends | Existing code already defines friends as following entries whose relationship is `.mutual`. | Add one shared `friends(of:)` store helper later to remove duplicate filtering. |
| Been/Wanna tiles and pages | `StatTile`, `SavedPlacesListScreen`, and current navigation. | Preserve destination pages unchanged. Restyle/reposition only the profile entry tiles if approved. |
| Visit dates | `LocalPlaceVisit.visitedAt`, `WanderStore.visits(for:)`, persisted visit rows. | Calendar uses active owner visits, not generic save timestamps. |
| Geographic data | `LocalPlace` already stores locality, region, country, latitude, and longitude. | Map and city/country summaries reuse canonical place rows. |
| Place categories | `WanderPlaceCategory` canonical primary categories and saved effective category. | Places summary uses canonical primary category, not cuisine labels copied from Beli. |
| Privacy controls | Private Profile and default stealth mode already exist in Settings. | Move unchanged behavior to the top of Privacy & Trust. |
| Blocked accounts | `LocalBlock`, `blockedProfiles()`, repository and persistence exist. | Move management into a dedicated destination. |
| Account security | ClerkKitUI 1.1.4 already ships email, phone, password, and delete-account flows. | Reuse Clerk APIs; preserve rec.me navigation and copy. |
| Standard share UI | Existing place surfaces use SwiftUI `ShareLink`. | Reuse for profile sharing once a real profile URL route exists. |
| Design-only review harness | `PlaceActivityMockups` and `CategoryTaxonomyMockups` use debug launch arguments. | Add REC-89 pages to the same harness. |

## Missing Contracts

1. **Permanent account deletion:** current Clerk webhook soft-deletes `profiles`; it does not hard-delete all database and storage data. The requested copy cannot be wired until an idempotent service-role purge removes owned storage objects and hard-deletes the profile so foreign-key cascades run.
2. **Muted accounts:** no local model, Supabase table/RLS, repository, or notification filter exists. The mockup must not imply mute is functional.
3. **Profile edits beyond avatar:** name/username are Clerk-owned; bio/home city are Supabase profile fields. There is no current update-own-profile contract.
4. **Shareable profile route:** notification payloads use `recme://profiles/<id>`, but the app bundle and root do not currently expose a complete profile URL route for sharing.
5. **Find Friends routing:** Root owns selected tab while Discover owns a private member/places mode. A small explicit route is needed to open Discover > Members.

## Architecture Review

### A1. Profile Presentation Boundary

Add a pure `ProfileInsightsPresenter` during production implementation. It accepts owner profile, owner-visible Been saves, visits, place rows, and a calendar/time-zone context; it returns display-ready counts, visit days, map points, and grouped summaries.

```text
LocalProfile ───────────────────────────────┐
LocalUserPlace (owner + Been only) ─────────┤
LocalPlaceVisit (active, visitedAt) ─────────┤
LocalPlace (category + geo fields) ──────────┤
                                             v
                                  ProfileInsightsPresenter
                                             |
               ┌─────────────────────────────┼──────────────────────────┐
               v                             v                          v
       Calendar month model            Map points             Places/Cities/Countries
```

Views do not perform nested store scans. The presenter is deterministic and unit-testable.

Production failure: a visit references a deleted/missing user-place or place row. The presenter drops that orphan from summaries, logs a non-PII diagnostic count, and keeps the rest of Profile usable.

### A2. Calendar Semantics

- Highlight `LocalPlaceVisit.visitedAt`, not `LocalUserPlace.savedAt`.
- Include only active Been visits owned by the current user.
- Multiple visits on one date render one dining underlay plus a numeric count.
- Month statistics are distinct spots, distinct canonical categories, and distinct cities.
- Calendar grouping uses the visit/place time zone when available, otherwise the user's current calendar/time zone.
- Wanna saves never mark a calendar day or map point.

Production failure: a timezone change moves a late-night visit across dates. Tests pin the calendar/time zone so the conversion is explicit rather than device-dependent.

### A3. Social Graph Page

Replace the one-mode `GraphListScreen` with one screen that owns a `Followers / Following / Friends` segmented selection, `.searchable`, a Find Friends row, and explicit loading/error/empty states.

Add `WanderStore.friends(of:)` as the single mutual-follow definition. Both counts and rows call that helper.

Find Friends uses an explicit callback from `WanderRootView` to set the selected tab to Discover and its selected mode to Members. This is smaller and more explicit than introducing a global router for one route.

Production failure: a graph refresh finishes after the member switches tabs. The refreshed store data is shared; the selected tab remains local UI state and is not overwritten.

### A4. Profile Editing Ownership

```text
EditProfileForm
   |
   +-- name + username ----------> Clerk User.update
   |
   +-- home city + bio ----------> authenticated update_own_profile RPC
   |
   +-- profile photo ------------> existing avatar upload/delete contract
   v
optimistic local profile shell -> refresh Clerk session + current_profile
```

The form reports partial failure explicitly and retries only the failed owner. Do not hide a split Clerk/Supabase failure behind a generic success toast.

Production failure: Clerk accepts a username while Supabase bio update fails. The UI keeps the accepted identity fields, marks profile details unsaved, and offers retry without replaying the username mutation.

### A5. Account Security And Deletion

Email, optional phone, and password use ClerkKit/ClerkKitUI capabilities. The rec.me Settings home shows the requested rows, but verification/re-authentication remains Clerk-owned.

Account deletion uses two native confirmations, then an explicit deletion workflow:

```text
Delete account row
   -> Alert 1: "You are deleting your account"
   -> Alert 2: permanent deletion warning
   -> unregister push token
   -> Clerk user.delete()
   -> signed Clerk user.deleted webhook
   -> delete owned Storage objects (avatar + visit photos)
   -> hard-delete public.profiles row
   -> FK cascades remove follows, blocks, saves, visits, lists, notifications
   -> webhook returns 2xx only after cleanup succeeds
```

The webhook purge is idempotent so Svix retries are safe. A Clerk-only delete that merely soft-deletes `profiles` does not satisfy the product requirement.

Production failure: storage deletion succeeds but database deletion fails. The webhook returns non-2xx and retries; the second run treats missing storage objects as success and retries the database purge.

### A6. Muted Accounts

Muted is separate from blocking:

- New `profile_mutes(muter_user_id, muted_user_id, created_at)` table.
- RLS allows only the muter to list/create/delete their rows.
- Add `mute_profile`, `unmute_profile`, and `muted_profiles` app/public RPC contracts with metadata and hosted smoke coverage.
- Local model/persistence/repository mirrors the existing block pattern.
- Notification queue checks mutes before enqueue/delivery.
- Future activity/newsfeed queries exclude muted actors; no current Map/Profile visibility changes.

Production failure: a mute exists but a queued notification predates it. Delivery must re-check mute state, not only enqueue time.

### A7. Profile Sharing

Use `ShareLink` with a stable profile URL only after URL routing is complete. Share copy may include display name and handle, but the item must resolve to the member profile in an installed app and have a reasonable web/App Store fallback later.

Production failure: recipient has no app or the shared member is blocked/private. Routing opens an unavailable/private profile state rather than a blank sheet.

## Code Quality Review

- `ProfileScreen.swift` is currently 1,774 lines and `SettingsScreen.swift` is 890 lines. Production work should first extract new screens/presenters into focused files; do not add another thousand lines to either file.
- Friends filtering is duplicated in `ProfileScreen.people(for:)` and `GraphListScreen.profiles`. Replace both with one store helper.
- Keep the mockup implementation in one debug-only file with small private views and deterministic fixture structs. Production types must not depend on mock data.
- Existing nearby ASCII diagrams must be reviewed when production services are changed. Add the profile aggregation diagram near `ProfileInsightsPresenter` only if the data joins remain non-obvious after naming.

## Test Review

Test framework: XCTest through `WanderTests`, with simulator integration/build verification.

```text
CODE PATHS                                           USER FLOWS
[+] Debug mockup launch contract                     [+] Review every requested surface
  ├── [GAP] resolve every REC-89 page                   ├── [GAP] owner profile top + lower sections
  ├── [GAP] invalid page falls back safely              ├── [GAP] social graph populated + empty
  └── [GAP] release build excludes mockups               ├── [GAP] edit profile
                                                       ├── [GAP] settings + privacy
[+] ProfileInsightsPresenter [future]                   ├── [GAP] blocked + muted populated/empty
  ├── [GAP] owner Been visits only                       └── [GAP] both delete confirmations
  ├── [GAP] multiple visits on one day
  ├── [GAP] timezone date boundary                    [+] Production destructive flow [future] [->E2E]
  ├── [GAP] missing geo/city/country                    ├── [GAP] Clerk deletion -> webhook purge
  └── [GAP] canonical category grouping                 └── [GAP] retry after partial cleanup

[+] Social graph [future]                             [+] Find Friends [future] [->E2E]
  ├── [★★ TESTED] follower/following graph edges         ├── [GAP] Profile -> Discover > Members
  ├── [GAP] shared mutual-friends helper                 └── [GAP] back navigation preserves state
  └── [GAP] search + empty + refresh error

[+] Mutes [future] [->E2E]
  ├── [GAP] RLS ownership and RPC metadata
  ├── [GAP] local persistence/sync
  └── [GAP] queued notification re-check

COVERAGE NOW: existing graph/block/avatar contracts are covered; all REC-89 mockup
launch cases and all new production contracts are gaps by design before implementation.
```

Legend: `★★★` behavior + edge + error, `★★` happy path, `★` smoke, `[->E2E]` integration required.

### Required Mockup Tests

- `NavigationContractTests`: every `ProfileRedesignMockupPage` raw value resolves from launch arguments; missing/invalid values fall back to owner profile.
- Build the app in Debug and verify all mockup cases compile.
- Capture every page on the current simulator and one smaller iPhone.
- Manual accessibility pass: XXL Dynamic Type, VoiceOver labels, 44pt controls, Reduce Motion direction, and no clipping.

### Required Production Tests

- `ProfileInsightsPresenterTests`: owner-only Been filtering, visit-day grouping, duplicate visits, timezone boundaries, statistics, invalid/missing geography, canonical category grouping, and deterministic sorting.
- `WanderStoreTests`: single mutual-friends helper, mute persistence, block/mute separation, and profile-update optimistic/partial-failure behavior.
- `NavigationContractTests`: Find Friends routes to Discover > Members and profile URLs route to a member detail.
- `RemoteRepositoryTests`: update-own-profile, mute/unmute/list, and exact production encoders.
- pgTAP and hosted smoke tests: profile updates, mute RLS/RPC grants, notification suppression, account purge metadata, ownership, and idempotent deletion.
- Clerk integration tests: email/phone/password route availability and user deletion failure/retry behavior.

## Performance Review

- Build profile insights once per relevant store snapshot. Do not scan all visits once per calendar cell or once per segmented-summary row.
- Use dictionaries keyed by start-of-day, canonical category, locality, and country for O(n) aggregation followed by deterministic sorting.
- Use a non-interactive SwiftUI `Map` with fixed world framing and grouped coordinate points for the first production pass. Measure before introducing `MKMapSnapshotter` or a custom cache.
- Search graph rows locally after one remote refresh; debounce only if server-side member search is later added.
- Calendar renders one or a small bounded set of months at a time. Do not materialize an unbounded multi-year grid.

No current-scale bottleneck requires new infrastructure.

## Failure Modes

| Path | Realistic failure | Test | Handling | User-visible result |
|---|---|---|---|---|
| Profile insights | Orphan visit/place relation | Presenter unit test | Drop orphan and log count | Remaining profile still renders |
| Calendar | Device timezone changes date | Fixed-calendar unit test | Explicit calendar/time-zone conversion | Correct local visit date |
| Map | Missing or invalid coordinate | Presenter unit test | Exclude point, retain summary row | Map renders without bad dot |
| Social graph | Refresh/network failure | Store/UI state test | Preserve cached rows and show retry | Recoverable inline error |
| Edit profile | Clerk succeeds, Supabase fails | Coordinator unit test | Persist accepted fields; retry failed subset | Partial-save message and retry |
| Share profile | Invalid/private/blocked route | Navigation tests | Route to unavailable/private state | Clear destination state |
| Mute | Old notification already queued | Hosted integration test | Re-check at delivery | No muted notification |
| Delete account | Storage cleanup partially succeeds | Webhook integration test | Idempotent retry, no 2xx early | Progress/failure state; no false success |

Critical gaps before production: account hard purge and muted notification enforcement. Both would otherwise fail silently relative to the requested UI promise.

## Implementation Sequence

| Step | Modules touched | Depends on |
|---|---|---|
| M0. Debug mockups and screenshots | `Wander/App`, `Wander/Features/Profile`, `WanderTests`, `docs` | - |
| P1. Profile insights and owner profile UI | `Wander/Features/Profile`, `Wander/Services`, `WanderTests` | M0 approval |
| P2. Social graph and Discover routing | `Wander/App`, `Wander/Features/Profile`, `Wander/Features/Discover`, `WanderTests` | M0 approval |
| P3. Edit profile and account security | `Wander/Features/Profile`, `Wander/Features/Settings`, `Wander/Services/Auth`, `Wander/Services/Remote`, `WanderTests` | M0 approval |
| P4. Privacy, blocks, and mutes | `Wander/Features/Settings`, `Wander/Models`, `Wander/Services`, `supabase`, `WanderTests` | M0 approval |
| P5. Permanent account purge | `Wander/Features/Settings`, `Wander/Services/Auth`, `supabase/functions`, `supabase/migrations`, `supabase/tests` | P3 |

Parallel lanes after mockup approval:

- Lane A: P1
- Lane B: P2
- Lane C: P3 -> P5
- Lane D: P4

Launch P1, P2, P3, and P4 in isolated worktrees only after the mockup decision is durable. P5 waits for P3. Lanes touch high-conflict Profile/Settings/store/docs modules, so merge one lane at a time and rebase each remaining lane after every merge.

## NOT in Scope For This Branch

- Production Profile replacement: deferred until screenshot approval.
- Store/repository/backend wiring: the mockups use deterministic data only.
- Clerk email, phone, password, profile update, or deletion calls: deferred to P3/P5.
- Supabase migrations, RLS, RPCs, storage deletion, or hosted changes: deferred to P4/P5.
- Contacts permission/import: Find Friends routes to Discover > Members only.
- Newsfeed implementation: mute enforcement will cover notifications now and future activity queries when a newsfeed exists.
- Changes to Been/Wanna destination pages: explicitly preserved.
- Other-user profile redesign: owner Profile is the approved target; shared components may be reused later without silently changing social visibility.
- TestFlight release: no release requested.

## Implementation Tasks

- [ ] **T1 (P1, human: ~1 day / CC: ~45 min)** - Mockups - Build every REC-89 debug-only SwiftUI review page.
  - Surfaced by: design review acceptance bar and design-first scope gate.
  - Files: `Wander/App/WanderApp.swift`, `Wander/Features/Profile/ProfileRedesignMockups.swift`, `WanderTests/NavigationContractTests.swift`.
  - Verify: Debug build, launch-argument tests, and simulator screenshots on two phone sizes.
- [ ] **T2 (P1, human: ~2 days / CC: ~90 min)** - Profile - Extract and test `ProfileInsightsPresenter`, then replace owner Profile composition.
  - Surfaced by: Architecture A1/A2 and the 1,774-line ProfileScreen hotspot.
  - Files: focused Profile presenter/view files, store helper, tests.
  - Verify: presenter suite, full XCTest suite, screenshots, accessibility pass.
- [ ] **T3 (P1, human: ~1 day / CC: ~60 min)** - Social graph - Consolidate mutual friends, tabs, search, states, and Find Friends routing.
  - Surfaced by: Architecture A3 and duplicated friends filtering.
  - Files: Profile, Root/Discover route state, store helper, tests.
  - Verify: graph/navigation tests and cross-account manual QA.
- [ ] **T4 (P1, human: ~3 days / CC: ~2 h)** - Profile/account editing - Add explicit Clerk/Supabase ownership and partial-failure recovery.
  - Surfaced by: Architecture A4/A5.
  - Files: Profile/Settings forms, auth/remote contracts, tests, one reviewed migration if needed.
  - Verify: unit/repository tests, hosted metadata/smoke verification, account-change manual QA.
- [ ] **T5 (P1, human: ~3 days / CC: ~2 h)** - Mutes - Add the full mute contract and notification enforcement.
  - Surfaced by: Missing Contract 2 and Architecture A6.
  - Files: Settings, models/store/repositories, migrations/tests, notification SQL.
  - Verify: XCTest, pgTAP, hosted smoke, queued-notification integration test.
- [ ] **T6 (P1, human: ~3 days / CC: ~2 h)** - Account deletion - Replace soft delete with idempotent storage and database purge.
  - Surfaced by: critical Architecture A5 mismatch with the requested permanent-deletion promise.
  - Files: Settings/Auth, Clerk webhook, migrations/tests, storage cleanup.
  - Verify: destructive-flow integration tests in a disposable account and hosted security metadata checks.

## Review Completion Summary

- Step 0: Scope Challenge - scope reduced to mockups on this branch per the user's explicit design-first gate.
- Architecture Review: 7 findings, all folded into the phased plan.
- Code Quality Review: 3 findings, including two oversized files and duplicated friends logic.
- Test Review: diagram produced, 18 grouped gaps identified across mockup and future production contracts.
- Performance Review: 4 recommendations, no new infrastructure.
- NOT in scope: written.
- What already exists: written.
- TODOS.md updates: 0 proposed; REC-89 and this plan retain the deferred production work with full context.
- Failure modes: 2 critical production gaps flagged (permanent purge and mute enforcement).
- Outside voice: skipped; no independent model was requested and this phase is design-only.
- Parallelization: 4 post-approval lanes, with sequential merges due shared Profile/Settings/store modules.
- Lake Score: complete paths chosen for 6/6 actionable recommendations.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | - | Not run |
| Codex Review | `/codex review` | Independent 2nd opinion | 0 | - | Not run |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | CLEAR FOR MOCKUPS | 7 architecture findings, 2 critical production gates |
| Design Review | `/ios-design-review` | UI/UX gaps | 1 | STATIC COMPLETE | Source and six references reviewed; live device unavailable |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | - | Not run |

**VERDICT:** DESIGN + ENG CLEARED FOR DEBUG MOCKUPS. Production implementation remains gated on screenshot approval and the explicit contracts above.

NO UNRESOLVED DECISIONS
