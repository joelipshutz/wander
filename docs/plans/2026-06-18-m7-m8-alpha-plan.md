# M7/M8 Alpha Plan

Date: 2026-06-18
Status: Active planning baseline

## Current State

Build `0.1 (29)` is live on public TestFlight. M2 through M6 have enough baseline coverage for alpha iteration: map/add/discover/profile/settings, Clerk sign-in, Supabase sync, link extraction worker foundation, Add-tab search, social map filter, and TestFlight release automation are in place.

M7 and M8 did not previously have a detailed plan. `docs/roadmap.md` only listed high-level outcomes:

- M7: first-time user loop is understandable without Joe explaining it.
- M8: friends/follows and visible places feel dependable across accounts.

## Coordination

Another agent is actively working on M8 social reliability in `/private/tmp/recme-followed-users-surfaces` on branch `codex/followed-users-surfaces`. That branch currently edits Map, Discover, Profile, `WanderLocalStore`, and `WanderStoreTests`.

This branch should avoid those surfaces unless ownership is explicitly handed off. M7 work can proceed in Settings/Auth/docs without conflicting with the M8 worktree.

## M7: Alpha Onboarding And Trust

Goal: a first-time tester understands what rec.me does, who can see saved places, and why sign-in/location/social permissions are requested.

### Scope

1. Trust/privacy copy in Settings.
   - Explain that rec.me never shares live location.
   - Explain that `Everyone` means people who follow you, not the public internet.
   - Explain that `Friends` means mutual follows.
   - Explain that `Self` is private to the current account/local save.
   - Explain that link/photo extraction never auto-saves low-confidence results.

2. Auth gate polish.
   - Save/sync/follow/social-save gates should say what happens if the user skips sign-in.
   - No gate should imply a place will be globally public.
   - Gate copy should preserve the existing warm/direct tone.

3. Empty and first-run states.
   - Signed-out users should not see demo seed leakage.
   - Empty map/add/discover/profile states should point to the next useful action without marketing copy.
   - Follow/social value should be introduced only when the user reaches people/search/profile surfaces.

4. Account and data controls.
   - Sign out stays in Settings.
   - Blocked users remain visible in Settings.
   - Sync/pending-local-items status should be understandable and not scary.

### Out Of Scope For M7

- Full multi-screen onboarding.
- Native Contacts permission.
- Notification permission.
- Private profiles/follow requests.
- Production account deletion/export flows.

### Acceptance

- Settings has an inspectable trust/privacy surface.
- Auth gates and settings copy make visibility/location/sync behavior clear.
- Trust/privacy copy is backed by a testable static source so Settings and tests cannot silently drift.
- M7 QA uses `docs/qa/2026-06-18-m7-m8-alpha-trust-social-checklist.md` for small-phone text wrapping and sheet interaction checks.
- Existing auth/session tests pass, with at least one focused copy/contract regression where practical.
- No changes to Map/Discover/Profile/store social code unless coordinated with the M8 branch.

## M8: Social Reliability

Goal: follows, friends, and visible places behave consistently across real accounts, refreshes, and app relaunches.

### Current Linear Issues

- `REC-7`: Friends' saved places not showing in Discover or map filter.
- `REC-9`: People follow state is inconsistent across search, profile, and Discover.
- `REC-10`: Followed users do not appear in Discover or on map.
- `REC-8`: Profile name display and saved-place navigation is queued after core social visibility.

### Scope

1. Relationship hydration.
   - Follow/unfollow should immediately update local relationship state.
   - Discover people, profile people lists, and map social filters should all read the same relationship source.
   - Relaunch should preserve or refetch follow state.

2. Visible place refresh.
   - After follow/unfollow, refresh remote visible places.
   - After save/social-save, refresh remote visible places.
   - Discover and map should not require exact-name search to reveal followed users or their places.

3. Block behavior.
   - Blocked users should disappear from search, lists, profiles, map pins, and stale visible-place cache.
   - Block/unblock should refresh relationship and visible-place caches.

4. QA matrix.
   - Two-account follower visibility.
   - Mutual follow unlocks `Friends`/mutual rows.
   - Unfollow revokes follower-visible access after refresh.
   - Block hides both directions.

### Acceptance

- REC-7, REC-9, and REC-10 are fixed and moved to `Done` only after the changes are merged to `main` and available in TestFlight.
- Two-account QA from `docs/qa/2026-06-18-m7-m8-alpha-trust-social-checklist.md` passes before social issues are marked `Done`.
- The two-account QA must cover one-way follow visibility, mutual/friend visibility, unfollow revocation, block hiding, unblock non-refollow behavior, and kill/relaunch refresh.
- Full `xcodebuild test` passes or any Xcode finalization hang is clearly logged with focused regression evidence.
- TestFlight note tells testers exactly which social cases to verify.

## Recommended Order

1. Land M7 trust/privacy Settings surface and copy polish from this branch.
2. Let the active M8 worktree finish REC-7/9/10, or explicitly take over that branch if it stalls.
3. Merge and TestFlight M7 only if it adds user-visible copy worth testing immediately; otherwise batch with M8.
4. After M8 ships, run a two-account QA pass before starting M9 capture expansion.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | not run | optional for M7/M8 because direction is already locked |
| Codex Review | `/codex review` | Independent 2nd opinion | 0 | not run | not required before this plan review |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | DONE_WITH_CONCERNS, follow-up applied | 3 review issues, 16 test gaps, 1 critical social QA gap |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 for this branch | potentially stale | M7 adds a Settings trust sheet not covered by branch-specific design review |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | not run | not needed for this scope |

- **FOLLOW-UP APPLIED:** This branch added a testable M7 trust surface, copy contract tests, and the explicit M8 two-account social QA gate.
- **REMAINING:** M7 still needs a manual visual QA pass for the new Settings sheet before a TestFlight release note calls it ready; M8 implementation remains in the separate social reliability branch.
- **VERDICT:** ENG REVIEW DONE_WITH_CONCERNS, with the actionable M7 coverage and M8 QA-gate concerns addressed in this branch.
