# M7/M8 Plan Eng Review

Date: 2026-06-18
Skill: plan-eng-review
Status: DONE_WITH_CONCERNS
Reviewed branch: `codex/m7-alpha-trust`
Reviewed commit: `44565dd`

## Inputs

- Plan: `docs/plans/2026-06-18-m7-m8-alpha-plan.md`
- Roadmap: `docs/roadmap.md`
- Product spec: `docs/specs/wander-ios-product-spec.md`
- Existing eng review: `docs/reviews/2026-06-01-plan-eng-review.md`
- TODOs: `TODOS.md`
- Current M7 diff: `Wander/Features/Settings/SettingsScreen.swift`, `WanderTests/AuthSessionTests.swift`
- Parallel M8 branch: `codex/followed-users-surfaces`

No branch-specific gstack design doc was found. Proceeded with standard plan review because the M7/M8 plan is present and the user explicitly asked for `/plan-eng-review`.

## Summary Verdict

The M7/M8 split is directionally right, but the plan should not be treated as clear until two gaps are resolved:

1. M7 needs a real UI/interaction test path for the trust/privacy surface, not only string assertions against auth-gate copy.
2. M8 needs explicit ownership after the active social branch merges, plus a two-account remote QA matrix that proves visibility revocation and relaunch refresh.

Recommendation: finish M7 as a small Settings/Auth trust PR only after adding UI/visual/a11y QA. Keep M8 in the existing social branch or merge it first, then run a focused two-account QA pass before starting M9.

## Step 0 Scope Challenge

### What Already Exists

| Sub-problem | Existing source | Reuse call |
|---|---|---|
| Visibility labels and helper copy | `PlaceVisibility.displayTitle` / `helperCopy` in `Wander/Models/WanderEnums.swift` | Reuse, but the trust sheet should link back to the exact same semantics. |
| Auth gate copy | `AuthGateIntent.copy` in `Wander/Services/Auth/AuthSessionProviding.swift` | Reuse and extend tests; do not create a second auth-copy model. |
| Settings account/sign-out/blocked users | `SettingsScreen` | Reuse. M7 should stay in Settings/Auth to avoid social-branch conflicts. |
| Remote visible-place cache | `WanderStore.remoteVisiblePlaceCache` and refresh methods | M8 should harden this path, not create another cache. |
| Follow/block local state | `WanderStore.follow`, `unfollow`, `block`, `unblock` | M8 should add regression coverage around existing behavior and remote refresh side effects. |
| Social tests | `WanderStoreTests` already covers remote visible places and social graph hydration | Extend these tests for REC-7/REC-9/REC-10 instead of adding a parallel fixture layer. |

### Minimum Changes

M7 can stay small:

```text
Settings row
  -> Trust/privacy sheet
  -> Copy backed by the same visibility/auth semantics
  -> Unit + UI/visual/a11y QA
```

M8 should stay in the existing social branch:

```text
Follow/unfollow/block
  -> update local relationship state
  -> refresh remote social graph
  -> refresh remote visible places
  -> Discover/Map/Profile all read same store state
```

### Complexity Check

M7 touches 2 app/test files plus docs, which is acceptable. M8 touches 5 high-conflict implementation/test files, which is acceptable only if kept in one coordinated lane because Map, Discover, Profile, and `WanderLocalStore` are tightly coupled.

### Search Check

No new infrastructure, paid service, concurrency primitive, or custom architectural pattern is introduced. This plan stays [Layer 1]: SwiftUI sheets, existing Swift store/repository boundaries, existing Supabase remote repositories, and existing tests.

### TODOs Cross-Reference

Existing TODOs already include:

- Social visibility/follow refresh from Build 17 feedback.
- Native Contacts later.
- Richer share/deep-link later.
- External place actions only when data exists.

No new broad TODO is needed. The only TODO-quality follow-up is to keep M9 capture expansion separate from M7/M8.

## Architecture Review

### Issue 1

`[P1] (confidence: 8/10) docs/plans/2026-06-18-m7-m8-alpha-plan.md:48 — M8 acceptance says REC-7/9/10 are done only after merge/TestFlight, but it does not define the remote two-account proof that makes social reliability real.`

Recommendation: add a two-account QA gate to M8 before marking REC-7/9/10 done.

Options:

- **1A Add explicit two-account QA gate (recommended).** Effort human: ~30 min / CC: ~10 min; risk low; maintenance low. Completeness: 9/10.
- **1B Rely on unit tests and single-account simulator checks.** Effort human: ~0 / CC: ~0; risk medium because social bugs are already showing up only between real accounts. Completeness: 5/10.

User impact: if this is skipped, Joe can follow someone in TestFlight and still not see their places after relaunch.

## Code Quality Review

### Issue 2

`[P2] (confidence: 8/10) Wander/Features/Settings/SettingsScreen.swift:245 — The trust sheet hard-codes six trust facts inside the view. That is fine for one sheet, but it makes copy tests indirect and can drift from enum/helper copy.`

Recommendation: extract the fact list into a tiny static model or computed source that unit tests can inspect without rendering SwiftUI.

Options:

- **2A Extract `TrustFact.alphaDefaults` and unit-test it (recommended).** Effort human: ~20 min / CC: ~5 min; risk low; maintenance low. Completeness: 8/10.
- **2B Leave facts inline and rely on visual QA.** Effort human: ~0 / CC: ~0; risk low now, medium later when visibility copy changes. Completeness: 5/10.

User impact: this avoids a future mismatch where Settings says one thing and the save flow says another.

## Test Review

### Coverage Diagram

```text
CODE PATHS                                             USER FLOWS
[+] Settings trust/privacy                             [+] First-time trust check
  ├── [GAP] Row exists and opens sheet                    ├── [GAP] Open Settings -> Privacy and trust
  ├── [GAP] Sheet renders all trust facts                 ├── [GAP] Read Everyone/Friends/Self meaning
  ├── [GAP] Done dismisses sheet                          ├── [GAP] Dismiss and return to Settings
  └── [GAP] Dynamic Type / small-phone wrapping            └── [GAP] VoiceOver can navigate facts

[+] Auth gate copy                                      [+] Signed-out action gate
  ├── [★★ TESTED] sync copy key phrases                   ├── [GAP] Save while signed out shows gate
  ├── [★★ TESTED] social save phrase                      ├── [GAP] Follow while signed out shows gate
  └── [★★ TESTED] follow phrase                           └── [GAP] Secondary action dismisses gate

[+] M8 remote social graph                              [+] Two-account social loop
  ├── [★★ TESTED] remote visible place hydration          ├── [GAP] A follows B -> A sees B Everyone places
  ├── [★★ TESTED] remote social graph hydration           ├── [GAP] Mutual follow -> Friends places appear
  ├── [GAP] unfollow refresh revokes rows                 ├── [GAP] Unfollow -> access disappears after refresh
  ├── [GAP] block refresh removes stale rows              ├── [GAP] Block -> search/list/map/profile hidden
  └── [GAP] relaunch preserves or refetches state          └── [GAP] Kill/relaunch keeps expected relationship

COVERAGE: 5/21 paths tested (24%)
QUALITY: ★★★:0 ★★:5 ★:0 | GAPS: 16
```

### Issue 3

`[P1] (confidence: 9/10) Wander/Features/Settings/SettingsScreen.swift:207 — The new user-facing Settings row and sheet have no UI or visual regression coverage.`

Recommendation: add a lightweight UI/inspection path plus screenshot/manual QA checklist for Settings on current and smaller iPhone before calling M7 ready.

Options:

- **3A Add UI/inspection coverage and QA checklist (recommended).** Effort human: ~20 min / CC: ~15 min; risk low; maintenance low. Completeness: 8/10.
- **3B Keep only string-copy unit tests.** Effort human: ~0 / CC: ~0; risk medium because this surface can visually fail while tests pass. Completeness: 4/10.

User impact: Settings is where testers learn privacy. If this clips or hides copy, trust breaks.

## Performance Review

No performance issue in M7. The trust sheet is static content and cheap.

M8 has one performance-sensitive edge:

`[P2] (confidence: 7/10) Wander/Services/WanderLocalStore.swift:761 — follow/unfollow/block refreshes remote social graph and visible places immediately after each mutation. That is correct for freshness, but rapid repeated relationship changes can cause redundant remote calls.`

Recommendation: keep this explicit for alpha and test correctness first. Do not debounce yet unless QA shows visible slowness or backend errors.

Options:

- **4A Keep explicit refreshes for alpha (recommended).** Effort human: ~0 / CC: ~0; risk low; maintenance low. Completeness: 8/10.
- **4B Add debounce/coalescing now.** Effort human: ~1 hour / CC: ~30 min; risk medium because it can hide stale-state bugs. Completeness: 7/10.

User impact: correctness matters more than optimizing a low-volume alpha path.

## NOT In Scope

- Full onboarding. It should wait until M7 proves the trust/account copy is right.
- Native Contacts. Already planned later after privacy and backend matching.
- Notification permissions. Not needed for M7/M8 trust or social reliability.
- Private profiles/follow requests. Product direction remains open follow plus hard block.
- M9 capture expansion. Do not mix TikTok/Instagram/photo OCR expansion with social reliability.
- Public share/web fallback. Already tracked as later M10.

## Failure Modes

| Codepath | Failure | Covered? | Handling? | User effect |
|---|---|---|---|---|
| Settings trust sheet | Row does not open sheet | No | No | Tester cannot find privacy explanation. |
| Settings trust sheet | Copy wraps/clips on small phone | No | No | Trust copy is unreadable. |
| Auth gate copy | Copy regresses to global-public implication | Partial | No | User misunderstands visibility. |
| Follow remote mutation | Backend succeeds but visible places do not refresh | Partial in active M8 branch only | Partial | User follows someone and sees no places. |
| Unfollow remote mutation | Stale cache still shows followed user's places | No | Partial | Privacy/access revocation feels broken. |
| Block remote mutation | Stale cache/search still shows blocked user | No | Partial | Safety model feels broken. |

Critical gap: stale social visibility after follow/unfollow/block is the main M8 risk until two-account QA proves it.

## Worktree Parallelization Strategy

| Step | Modules touched | Depends on |
|---|---|---|
| M7 trust/account copy | Settings, Auth, tests, docs | None |
| M8 social reliability | Map, Discover, Profile, Store, tests | None, but should use latest `origin/main` |
| M8 two-account QA | QA docs, TestFlight/Linear | M8 implementation |
| M9 capture expansion | Add, extraction worker, provider adapters, tests | M7/M8 accepted |

Parallel lanes:

- Lane A: M7 trust/account copy.
- Lane B: M8 social reliability.
- Lane C: M8 two-account QA after Lane B.
- Lane D: M9 capture expansion after M7/M8.

Execution order: Lane A and Lane B can run in parallel if they stay out of each other's files. Merge both, then run Lane C. Do not start Lane D until social reliability is accepted.

Conflict flags: Lane B owns Map/Discover/Profile/Store/tests. Lane A must avoid those files except shared docs.

## Completion Summary

- Step 0 Scope Challenge: scope accepted with M7/M8 lanes kept separate.
- Architecture Review: 1 issue found.
- Code Quality Review: 1 issue found.
- Test Review: diagram produced, 16 gaps identified.
- Performance Review: 1 issue found.
- NOT in scope: written.
- What already exists: written.
- TODOS.md updates: 0 new durable TODOs required; existing TODOs cover later share/contacts/M9.
- Failure modes: 1 critical gap flagged.
- Outside voice: skipped.
- Parallelization: 4 lanes, 2 parallel / 2 sequential.
- Lake Score: 3/4 recommendations chose the complete option; performance intentionally favors boring correctness.

## Recommended Decisions

1. Choose **1A**: add the M8 two-account QA gate.
2. Choose **2A**: extract trust facts into a testable static source.
3. Choose **3A**: add UI/inspection coverage and screenshot/manual QA for Settings trust.
4. Choose **4A**: keep explicit refreshes for alpha and avoid premature debounce.

## Review Status

This plan is not blocked, but it is not clean yet. Proceed only after adding the M7 UI/QA coverage and making the M8 two-account QA gate explicit.

## Follow-Up Status

Applied on branch `codex/m7-alpha-trust` after the review:

- Recommendation 1A: added an explicit M8 two-account QA gate in `docs/qa/2026-06-18-m7-m8-alpha-trust-social-checklist.md` and referenced it from the plan acceptance criteria.
- Recommendation 2A: extracted Settings trust copy into `SettingsTrustSurface` and covered it in `AuthSessionTests`.
- Recommendation 3A: added the manual M7 trust-surface QA checklist. No simulator screenshot has been captured yet.
- Recommendation 4A: left social refresh performance unchanged for alpha; M8 implementation remains in the social branch.

Follow-up validation:

- `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-m7-alpha-trust CODE_SIGNING_ALLOWED=NO -jobs 1 -only-testing:WanderTests/AuthSessionTests` passed.
- `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-m7-alpha-trust-full CODE_SIGNING_ALLOWED=NO -jobs 1` passed: 100 tests, 0 failures.
