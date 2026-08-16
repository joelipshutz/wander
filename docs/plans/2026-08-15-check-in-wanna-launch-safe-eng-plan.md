# Check-in and Wanna Launch-Safe Engineering Plan

Date: 2026-08-15
Status: Recommended implementation sequence
Design source: `docs/plans/2026-08-15-check-in-wanna-floating-actions-design.md`
Code audited against: `origin/main` at `6085eb24`
Tracking: dedicated Linear issue creation is blocked by the recme workspace's
free-issue limit; attach each implementation PR to the issue once capacity is
available

## Recommendation

Do not ship the full place-profile action redesign as one pre-launch change.

Use two independent trains:

1. **Launch polish train:** typography, the Add candidate CTA, and the
   `Add 1 place` / `Add N places` confirmation family. Each is a small,
   independently releasable PR with no navigation, save-state, persistence,
   auth, backend, or schema change.
2. **Behavior train:** floating place actions and the attached editor. Start
   after the 1.0 candidate is locked, keep the current sheet as the fallback,
   and roll the new path out behind the existing account-scoped Supabase flag
   platform.

If launch timing tightens, stop after any launch-polish slice. Nothing in the
behavior train is required to submit 1.0.

Joe's phrase "the buttons from Add 1" is interpreted as both the Add tab's
single-candidate action and the count-aware `Add 1 place` / `Add N places`
import confirmation. They are split into separate PRs because they live in
different modules and have different progress-state behavior.

## Non-Negotiable Launch Rules

- One behavioral concern per PR. No big-bang place-profile/save-flow PR.
- Start every implementation worktree from current `origin/main`; do not stack
  on this planning branch or on another unmerged implementation PR.
- Merge and validate one slice before the next slice rebases.
- Keep `MapPlaceSaveFlowSheet` available until the new path has completed an
  internal-cohort TestFlight soak and at least one release with the flag enabled.
- The remote flag fails closed to the legacy sheet. A failed or unresolved flag
  lookup must never hide the ability to save a place.
- Snapshot the resolved experience when a place profile opens. Never swap an
  open form between legacy and new UI after a foreground flag refresh.
- Do not change `MapPlaceSaveSubmission`, store mutations, sync identities,
  Supabase RPCs, RLS, visit history, Wanna history, photo upload, shared-invite,
  or streak semantics as part of the presentation work.
- Every slice can be reverted without reverting a later data migration or
  repairing user data.
- A release remains explicit. Merging a slice does not bump a build, upload to
  TestFlight, or announce to testers.

## What Already Exists

| Existing foundation | Current location | Plan use |
|---|---|---|
| Native editorial/sans type roles | `Wander/DesignSystem/WanderTheme.swift` | Reuse. The merged REC-161 work already supplies `WanderTypography`; do not introduce a font dependency or a second typography system. |
| Large terracotta capsule button | `WanderPrimaryButton` in `WanderTheme.swift` | Reuse. It is already 52 points tall, full width, terracotta, and capsule-shaped. Do not create `WanderConfirmationButton` before launch. |
| Central save editor and submission contract | `MapPlaceSaveFlowSheet` in `MapScreen.swift` | Preserve as the legacy path and later extract only the minimum reusable editor boundary. |
| Save context/state semantics | `MapPlaceSaveContext`, `MapPlaceSaveMode`, `PlaceSheetAction` | Reuse. Existing tests cover first save, Wanna, conversion, repeat check-in, edit, delete, and shared invite behavior. |
| Local durable drafts | `PlaceSaveDraftStore` | Reuse for attached-tray collapse, profile dismissal, auth, and retry. |
| Full-screen candidate/place profile | `PlaceProfileFullScreen` | Reuse. It already hides the tab bar and is used from Map, Discover, Feed, Profile, Lists, and import candidate selection. |
| Safe-area bottom actions | Add and import screens use `.safeAreaInset(edge: .bottom)` | Reuse the platform pattern instead of a custom overlay coordinate system. |
| Account-scoped remote flags | `FeatureFlagKey`, `WanderBackend.featureFlag`, `public.feature_flags` | Reuse only for the behavior train. Existing resolution is one request per validated signed-in session and fails closed. |
| Save/import contract tests | `WanderStoreTests`, `PlaceImportTests`, `PlaceSaveDraftStoreTests`, `NavigationContractTests`, `PlaceProfilePresentationTests` | Extend. Do not replace existing semantic coverage with screenshot-only tests. |

Prior learning applied: `recme-place-profile-current-user-primary`
(confidence 8/10). The action state must derive from the current user's save
inside the grouped physical place, not whichever visible save happens to be the
selected representative.

Prior learning applied: `foreground_validation_must_not_unmount_drafts`
(confidence 9/10). The new presentation must not disappear or reset when Clerk
validates a previously ready session in the foreground.

Prior learning applied: `adaptive-import-route-on-total-and-exceptions`
(confidence 10/10). The import button change is visual only; it must not alter
the current total/ready/help routing policy.

## Scope Challenge Result

The approved design document names roughly ten high-conflict files and five new
component concepts. Shipping that as one change would be overbuilt and unsafe
for 1.0.

The minimum useful launch scope is three small visual slices:

- Apply the existing typography contract to the current save flow.
- Rename the Add candidate action from `Save` to `Use this place` while keeping
  the current destination and save logic.
- Make the count-aware import commit action use the existing terracotta capsule
  family while preserving its current count, disable, and progress behavior.

Everything that changes navigation or form ownership is deferred to the
flagged behavior train.

## Release Trains

```text
                         1.0 LAUNCH POLISH TRAIN

 latest main
     |
     +--> S1 typography only ----------> validate ----------> merge or omit
     |
     +--> S2 Add candidate CTA --------> validate ----------> merge or omit
     |
     +--> S3 import confirmation CTA --> validate ----------> merge or omit
     |
     +==================== 1.0 candidate cutoff ====================+

                         POST-CANDIDATE BEHAVIOR TRAIN

 latest main
     |
     +--> S4 off-by-default flag + policy
              |
              +--> S5 floating rail, legacy editor behind it
                        |
                        +--> S6 new Check-in attached tray
                                  |
                                  +--> S7 Wanna + existing-save states
                                            |
                                            +--> S8 remaining entry points
                                                      |
                                                      +--> S9 default on
                                                                |
                                                                +--> S10 remove legacy later
```

Implementation can happen in parallel worktrees, but integration stays
sequential. A failed slice is omitted or rolled back; it never blocks the next
TestFlight or App Store release.

## Slice Plan

### S0 - Freeze the baseline and record rollback points

**Purpose:** make every visual change comparable to an exact current build.

- Start from latest `origin/main` and record the last accepted TestFlight build
  and commit.
- Capture the current Check in/Wanna sheet, Add candidate state, single-import
  confirmation, and multi-import confirmation on iPhone 16 Plus and iPhone 16e.
- Run focused baseline tests before editing. If a baseline test is already
  failing, reproduce it on unmodified `main`; do not attribute it to the slice.
- Do not change source in this step.

**Exit:** named baseline commit, screenshots, focused test receipts, and a
one-command revert target for each later PR.

### S1 - Check-in typography only

**Priority:** first; launch-compatible

**Files:**

- `Wander/DesignSystem/WanderTheme.swift`
- `Wander/Features/Map/MapScreen.swift`
- `WanderTests/NavigationContractTests.swift`

**Change:**

- Add only any missing semantic system-sans role needed for an action-screen
  title. Do not alter existing token values used elsewhere.
- In `MapPlaceSaveFlowSheet`, render the place name with the existing
  size-appropriate editorial named-content role.
- Keep `Check in`, `Wanna`, Back, More options, metadata, fields, and CTA labels
  system sans through semantic roles.
- Replace raw `.black`/`.bold` hierarchy inside this flow where a matching
  semantic role already exists.
- Do not change text, spacing, geometry, navigation, status selection, form
  order, state, callbacks, or persistence.

**Why safe:** the typography foundation already shipped in merged PR #256.
This slice applies it to one existing view without touching save behavior.

**Acceptance:**

- Source-contract test proves named content is serif and every control remains
  sans.
- Existing save-flow, date, rating, draft, and store tests remain unchanged and
  pass.
- Screenshot comparison at standard and accessibility Dynamic Type on both
  target phone sizes shows no clipping, collision, or changed control geometry.
- Revert is one PR with no data consequence.

### S2 - Add candidate CTA vocabulary

**Priority:** second; launch-compatible

**Files:**

- `Wander/Features/Add/AddScreen.swift`
- `WanderTests/NavigationContractTests.swift`

**Change:**

- Change the single selected-candidate action from `Save` to `Use this place`.
- Keep the current shared `candidateSaveAction`, safe-area behavior, and
  `openSharedSaveFlow()` destination exactly as they are.
- Keep `WanderPrimaryButton`; do not add a new button abstraction.

**Why safe:** the button does not commit a place today. The new label describes
the existing transition more honestly without changing the transition.

**Acceptance:**

- The same shared action renders in the in-flow and floating current-location
  layouts.
- One tap opens exactly one current save flow; rapid taps cannot stack sheets.
- Walkthrough targeting and accessibility label use the new copy.
- Manual smoke covers manual search, Here Now, link/photo candidate, Back, and
  Close.

### S3 - `Add 1 place` / `Add N places` confirmation family

**Priority:** third; launch-compatible

**Files:**

- `Wander/Features/Profile/ProfileImportViews.swift`
- `WanderTests/NavigationContractTests.swift`
- `WanderTests/PlaceImportTests.swift` only if behavior assertions need a
  clearer boundary; count-copy expectations should not change

**Change:**

- Preserve `PlaceImportReviewPlan.primaryActionTitle` exactly, including
  `Add 1 place`, `Add N places`, and `Add N of T places`.
- Replace the remaining custom dark rectangular bulk commit control with the
  existing `WanderPrimaryButton` terracotta capsule.
- Express progress in the title, for example `Adding 2 of 3…`, instead of
  creating a second button component solely for a progress badge.
- Preserve `isBulkSaveRunning`, disabled duplicate submission, per-row status,
  selected counts, exception routing, and receipt behavior.

**Why safe:** this changes only the renderer around the existing import plan and
commit action. It does not touch extraction, selection, routing, or saving.

**Acceptance:**

- Existing one/many/partial-count unit tests pass unchanged.
- Rapid taps start one bulk save task.
- Progress and error recovery remain readable at accessibility Dynamic Type.
- Single, partial, multi, duplicate, needs-help, and completion screenshots
  match the same CTA family without changing which rows commit.

### Launch cutoff

S1-S3 may ship independently. A failure in one does not hold the release:

- Revert or omit only that PR.
- Do not merge S4-S10 into the 1.0 candidate unless Joe explicitly moves the
  cutoff.
- Do not delay an otherwise releasable build to complete the floating tray.

### S4 - Off-by-default behavior gate and pure action policy

**Priority:** first behavior-train slice; off by default

**Files:**

- `Wander/App/WanderBackend.swift`
- one focused action-policy source file under `Wander/Features/Map/`
- `WanderTests/RemoteRepositoryTests.swift`
- `WanderTests/PlaceProfilePresentationTests.swift`
- one additive Supabase migration and its focused pgTAP test

**Change:**

- Add `place_profile_save_tray_v1` to the existing flag key set.
- Insert a global default of false. Do not change flag-table shape, grants, or
  RLS.
- Add a DEBUG-only launch override for signed-out/internal simulator testing.
- Introduce a pure `PlaceProfileSaveActionPolicy` that maps grouped current-user
  state to collapsed actions and destination mode:
  - unsaved: Check in + Wanna;
  - current Wanna: Check in + selected Wanna;
  - check-in history: Check in again + Edit/history;
  - shared invite: Check in only;
  - walkthrough/read-only: no mutation.
- Snapshot the resolved path when the profile opens.

**Guest rule:** while the account-scoped flag is in rollout, production guests
stay on the legacy path because anonymous clients cannot read feature flags.
Do not weaken flag-table RLS for this UI rollout. At general availability, make
the new experience the compiled default for everyone and then retire the flag.

**Acceptance:**

- Unresolved, failed, off, signed-out, and wrong-account flag states use legacy.
- Own override beats global default, matching the existing resolver contract.
- Every place-state matrix branch has a pure unit test.
- Hosted migration history aligns and focused pgTAP proves the new row without
  changing grants/RLS.

### S5 - Floating action rail canary, legacy editor retained

**Priority:** internal cohort only

**Files:**

- `Wander/Features/Map/PlaceProfileMapSurface.swift`
- `Wander/Features/Map/MapScreen.swift`
- `WanderTests/PlaceProfilePresentationTests.swift`
- `WanderTests/NavigationContractTests.swift`

**Change:**

- Add the bone safe-area action rail to `PlaceProfileFullScreen` under the flag.
- Remove the existing in-scroll primary action only in the flagged path.
- Derive buttons from `PlaceProfileSaveActionPolicy`.
- In this slice, tapping a floating action still opens the current
  `MapPlaceSaveFlowSheet`, preselected to the chosen status when valid.
- Flag-off rendering remains byte-for-byte equivalent to the legacy profile.

**Why this intermediate slice exists:** it validates the highest-risk geometry
and routing change without changing form ownership or persistence.

**Acceptance:**

- The rail remains above the home indicator at the top and bottom of profile
  scrolling.
- Final content is never covered.
- Tab bar remains hidden only inside the profile.
- Button labels and availability match all policy states.
- Flag off instantly restores the old in-scroll action plus old sheet on the
  next profile open.

### S6 - Attached tray for first-time Map Check in

**Priority:** first complete new vertical slice

**Change:**

- Extract the minimum reusable stateful editor boundary from
  `MapPlaceSaveFlowSheet`; keep the existing sheet as a wrapper around the same
  editor.
- Add the attached presentation shell for only a first-time Map Check in.
- Reuse the same `MapPlaceSaveContext`, draft callbacks, submission builder,
  `onSave`, loading lock, errors, and local-first result.
- Keep Wanna, repeat check-in, edit, shared invite, Add, Discover, Feed, Profile,
  Lists, and imports on the legacy sheet.

**Do not:** split persistence into a new service, rewrite the submission model,
or move save ownership into `PlaceProfileFullScreen`.

**Acceptance:**

- New Check in opens attached; every unsupported mode still routes legacy.
- Date/rating defaults, More options, photos, friends, tags, visibility, draft,
  signed-out local save, retry, and streak handoff match legacy behavior.
- Keyboard keeps the CTA and active field visible.
- Dismissing or backgrounding never loses a dirty draft or duplicates a local
  visit.

### S7 - Wanna and existing-save modes

Land one mode per PR in this order:

1. New Wanna.
2. Edit existing Wanna.
3. Wanna-to-first-check-in conversion.
4. Repeat check-in.
5. Edit/delete visit and historical-Wanna restoration.
6. Shared-visit invitation.

Each PR adds one policy branch, one attached-editor path, focused tests, and
screenshots. Unsupported modes continue to use the legacy sheet.

### S8 - Entry-point convergence

Move entry points only after the corresponding state modes are proven on Map:

1. Discover, Feed, Profile, and Lists destinations that already open
   `PlaceProfileFullScreen`.
2. Add single candidate.
3. Single-candidate import and candidate picker.
4. Activity/shared-invite destinations.

Batch import keeps per-row inline Check in/Wanna controls permanently. Only its
large commit action joins the shared confirmation family.

Each entry-point PR must update only that surface plus focused tests. Do not
change nine sheet call sites in one merge.

### S9 - General availability

**Gate:** at least one internal-cohort TestFlight soak with no regression in
save completion, duplicate visits, draft restoration, auth continuity, or
offline save behavior.

- Enable the remote global value for signed-in accounts in measured steps.
- Monitor privacy-safe counts for presentation, action selected, local save
  completed, failure/retry, and legacy fallback. Never log place data, notes,
  coordinates, emails, handles, or contact data.
- If healthy, ship a compiled new default for guests and signed-in users.
- Keep the legacy code path for one more release.

### S10 - Legacy removal

**Priority:** post-launch cleanup; never block 1.0

- Remove the standalone confirm/status-choice screen only after all supported
  modes and entry points use the attached editor.
- Remove the flag only after the compiled default has shipped and the previous
  release can no longer require a remote rollback.
- Delete dead sheet-only code and obsolete navigation/source-contract tests in
  a separate cleanup PR.
- Preserve the editor, context, drafts, submission builder, and save semantics.

## Architecture and Data Flow

```text
PLACE OPEN
  |
  +--> group saves for one physical place
  |      |
  |      +--> current user's save/history
  |             |
  |             +--> PlaceProfileSaveActionPolicy (pure)
  |
  +--> snapshot experience for this profile presentation
         |
         +--> flag absent/off/failed/guest rollout
         |      |
         |      +--> legacy in-scroll action -> MapPlaceSaveFlowSheet
         |
         +--> flag on/supported mode
                |
                +--> floating action rail
                       |
                       +--> unsupported mode -> legacy sheet fallback
                       |
                       +--> supported mode -> attached editor shell
                                                  |
                                                  +--> existing context/draft
                                                  +--> existing submission
                                                  +--> existing onSave
                                                  +--> existing local-first store
                                                  +--> existing sync/retry
```

The presentation layer changes. The data path does not.

## Attached-Tray State Machine

```text
COLLAPSED
  | tap Check in / Wanna
  v
EDITING <-------------------------------+
  |                                     |
  +-- collapse with dirty form --> DRAFT SAVED
  |                                     |
  +-- submit -----------------> SAVING  |
                                  |     |
                     local error  +-----+  inline Retry, fields retained
                                  |
                     local commit v
                               SAVED LOCALLY
                                  |
                    remote ok ----+---- remote pending/failure
                        |                     |
                        v                     v
                    COLLAPSED           COLLAPSED + sync status
                        |
                        +--> refreshed policy state
                             Check in again / Edit/history / selected Wanna
```

Remote sync never owns whether the tray can close after a successful local
write. The local durable record is the user-visible commit point.

## Architecture Review

No open architecture issues after applying the user-requested staged scope.

- The typography and CTA slices reuse merged foundations.
- The high-risk behavior stays behind a fail-closed flag with the legacy sheet
  retained.
- Presentation state is sticky for one profile session.
- The save data path remains unchanged.
- The guest rollout limitation is explicit and does not weaken feature-flag
  security.

## Code Quality Review

No open code-quality issues in the proposed sequence.

- Do not add a second confirmation-button component before launch.
- Do not duplicate form state between the sheet and tray.
- Extract only the reusable editor boundary when S6 needs it.
- Keep the pure action-state policy separate from view layout.
- Do not mix structural extraction and new save behavior in one PR.

The `MapPlaceSaveFlowSheet` implementation is large and state-heavy, but a
pre-launch rewrite would be riskier than preserving it. Cleanup occurs only
after the attached path proves parity.

## Test Coverage Diagram

```text
CODE PATHS                                         USER FLOWS

[+] Typography roles                              [+] Current sheet
  +-- [★★ existing] semantic token foundation       +-- [GAP -> S1] standard type
  +-- [GAP -> S1] save-flow role boundaries         +-- [GAP -> S1] accessibility type

[+] Add candidate CTA                            [+] Add candidate
  +-- [★★ existing] one shared action renderer      +-- [GAP -> S2] manual candidate
  +-- [GAP -> S2] Use this place copy                +-- [GAP -> S2] Here Now candidate
                                                     +-- [GAP -> S2] rapid tap

[+] Import commit                                [+] Import review
  +-- [★★★ existing] 1/N/partial copy               +-- [★★★ existing] status/count routing
  +-- [★★ existing] disabled while saving           +-- [GAP -> S3] progress visual
  +-- [GAP -> S3] shared primary renderer            +-- [GAP -> S3] rapid tap

[+] Flag/policy                                  [+] Rollout
  +-- [★★★ existing] account flag resolution        +-- [GAP -> S4] guest legacy fallback
  +-- [GAP -> S4] new key fail-closed                +-- [GAP -> S4] sticky open profile
  +-- [GAP -> S4] every place-state branch           +-- [GAP -> S4] debug override

[+] Floating rail                               [+] Place profile
  +-- [GAP -> S5] safe-area inset                    +-- [GAP -> S5] top/deep scroll
  +-- [GAP -> S5] legacy fallback routing            +-- [GAP -> S5] Dynamic Type stack
  +-- [GAP -> S5] unsupported-mode fallback          +-- [GAP -> S5] VoiceOver order

[+] Attached editor                             [+] Save journey [-> integration]
  +-- [★★★ existing] submission/store semantics      +-- [GAP -> S6] first Check in
  +-- [★★★ existing] draft evidence matching         +-- [GAP -> S6] offline local success
  +-- [★★★ existing] Wanna/history semantics         +-- [GAP -> S6] auth refresh mid-draft
  +-- [GAP -> S6] presentation lifecycle             +-- [GAP -> S6] keyboard/retry/dismiss
  +-- [GAP -> S7] every remaining mode               +-- [GAP -> S7] conversion/edit/delete

[+] Entry-point routing                         [+] Cross-surface journey [-> integration]
  +-- [★★ existing] profile destinations             +-- [GAP -> S8] Map
  +-- [GAP -> S8] one rollout at a time               +-- [GAP -> S8] Discover/Feed/Profile
                                                     +-- [GAP -> S8] Add/import/invite
```

Legend: ★★★ behavior plus error/edge coverage; ★★ happy path or structural
contract. Every marked gap is assigned to the slice that introduces it.

### Required test commands per implementation PR

Run the smallest focused set first, then the complete suite before handoff:

```bash
xcodebuild test -project Wander.xcodeproj -scheme Wander \
  -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' \
  -derivedDataPath DerivedData-focused CODE_SIGNING_ALLOWED=NO -jobs 1 \
  -only-testing:WanderTests/NavigationContractTests \
  -only-testing:WanderTests/PlaceProfilePresentationTests

xcodebuild test -project Wander.xcodeproj -scheme Wander \
  -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

Add `PlaceImportTests`, `PlaceSaveDraftStoreTests`, `WanderStoreTests`,
`RemoteRepositoryTests`, or hosted feature-flag pgTAP only in the slices that
touch those paths. A sandbox/CoreSimulator failure must be rerun with approved
access. It is not a test failure or a pass.

For visual slices, also capture iPhone 16 Plus and iPhone 16e at standard and
accessibility Dynamic Type. For S5-S8, capture collapsed, expanded, deep-scroll,
keyboard, loading, error, offline result, and post-save state.

## Production Failure Modes

| Failure | Prevented or handled by | Test and user result |
|---|---|---|
| Typography clips the close/back controls | S1 changes roles without geometry; accessibility screenshots | Focused source contract plus two-device visual QA; omit S1 if it clips |
| `Use this place` fires twice | Preserve one shared action and sheet identity | Rapid-tap integration check; user sees one save flow |
| Import visual rewrite commits the wrong count | Leave `PlaceImportReviewPlan` untouched | Existing 1/N/partial tests plus progress smoke; user sees the same count |
| Remote flag is missing, slow, or failed | Existing fail-closed resolver | Unit test; user receives the legacy path with no lost capability |
| Foreground auth refresh changes UI mid-form | Snapshot the presentation route for the open profile | Lifecycle test; current tray/sheet and draft remain mounted |
| Guest cannot read the remote flag | Explicit legacy rollout for guests | Test signed-out path; guest can still save using legacy |
| Floating rail covers profile content | `.safeAreaInset` plus measured bottom content inset | Top/deep-scroll screenshots; all content stays reachable |
| Keyboard covers the confirmation action | Tray owns internal scroll and keyboard-safe pinned footer | UI integration check; active field and CTA remain visible |
| Profile closes while save is in flight | Existing local-first callback and submission lock; draft remains durable | Dismiss/background tests; no duplicate visit and recoverable state |
| Local write succeeds but remote sync fails | Preserve current sync identity and offline result | Existing store tests plus attached-path integration; profile updates and shows retry status |
| Current-user state is derived from a social representative | Pure policy receives grouped current-user save/history | Unit tests with duplicate current/social place rows |
| An unsupported state reaches unfinished tray UI | Explicit supported-mode gate routes legacy | One policy test per mode; user gets the proven sheet |
| Flag is disabled during an incident | Legacy code remains in the shipped binary | Next profile open routes legacy; no App Store binary required |

No failure above is silent with neither a test nor a fallback.

## Performance Review

No new server query or persistence hot path is required.

- The action policy derives from saves already passed to the place profile.
- Feature flags retain the existing one-fetch-per-validated-session behavior;
  there is no polling and no app-launch dependency.
- Do not load photos, contacts, question blocks, or remote invitees until the
  corresponding attached editor mode expands, matching current lazy behavior.
- Do not recompute grouped place state on scroll. Resolve it from stable inputs
  and update only when the save collection changes.
- Animations must be interruptible and respect Reduce Motion. No timer or
  animation may gate save completion.

## Rollout and Rollback Gates

| Gate | Required evidence | Failure action |
|---|---|---|
| Merge S1 | focused tests plus two-device/type screenshots | Revert/omit typography PR only |
| Merge S2 | focused tests plus one-flow rapid-tap smoke | Revert/omit copy PR only |
| Merge S3 | import tests plus single/multi/partial screenshots | Revert/omit import CTA PR only |
| Enable internal S5 | flag tests, policy tests, legacy fallback proof | Keep global false |
| Enable internal S6-S7 | attached-flow parity suite and TestFlight checklist | Turn flag off; legacy remains |
| Expand S8 | per-entry-point integration receipt | Disable flag for affected accounts or globally |
| Default on S9 | internal soak with no save/draft/auth/offline regression | Global off, then revert isolated PR if needed |
| Remove legacy S10 | one later release has shipped with new compiled default | Defer cleanup; no user impact |

## Worktree and Merge Strategy

| Step | Modules touched | Depends on |
|---|---|---|
| S1 typography | DesignSystem, Map, Tests | S0 |
| S2 Add candidate copy | Add, Tests | S0 |
| S3 import CTA | Profile import, Tests | S0 |
| S4 flag and policy | App/backend, Map policy, Supabase, Tests | 1.0 cutoff |
| S5 floating rail | Map profile, Map routing, Tests | S4 |
| S6 first attached flow | Map save editor/profile, Drafts, Tests | S5 |
| S7 remaining modes | Map save editor/store integration, Tests | S6 |
| S8 entry points | Discover, Feed, Profile, Add, import/activity, Tests | relevant S7 modes |
| S9 rollout | Supabase operational flag, analytics/QA | S8 |
| S10 removal | Map save editor/routing, Tests | S9 plus later release |

Parallel lanes:

- Lane A: S1 typography.
- Lane B: S2 Add candidate copy.
- Lane C: S3 import CTA.
- Lane D after the 1.0 cutoff: S4 flag/policy.
- Lane E: S5 -> S6 -> S7 -> S8 -> S9 -> S10, sequential because the same Map
  presentation and editor modules are involved.

Develop A, B, and C in parallel isolated worktrees if useful, but merge them one
at a time. Rebase and rerun focused validation after each preceding merge.

Conflict warning: S1, S5, S6, and S7 touch `MapScreen.swift` and/or
`PlaceProfileMapSurface.swift`, which are already high-conflict launch files.
Never run those steps in parallel. Current `origin/main` has changed both files
since this design branch was created.

## NOT in Scope

- New save/check-in/Wanna data models. Presentation must preserve current
  current-status and historical-Wanna contracts.
- Supabase save RPC, RLS, grant, or schema changes.
- Anonymous read access to feature flags. Guests use legacy during rollout.
- Batch-import navigation redesign or extraction changes.
- New lists, tabs, live location, ranking, streak rules, rating semantics, or
  place-profile content redesign.
- A second confirmation-button design system.
- Removing the legacy sheet before a proven rollout.
- Automatic TestFlight release, build-number bump, upload, Slack announcement,
  or App Store submission.

## Implementation Tasks

- [ ] **T1 (P1, human: ~1h / Codex: ~15m)** - QA baseline - Capture exact pre-change UI and focused test receipts.
  - Surfaced by: launch safety - independent rollback needs a trusted baseline.
  - Files: no production files.
  - Verify: screenshots plus focused tests on current `main`.
- [ ] **T2 (P1, human: ~3h / Codex: ~45m)** - Save UI - Apply semantic Editorial Fold typography without layout or behavior changes.
  - Surfaced by: S1 and the approved typography contract.
  - Files: `WanderTheme.swift`, `MapScreen.swift`, `NavigationContractTests.swift`.
  - Verify: focused tests, Dynamic Type, iPhone 16 Plus and iPhone 16e screenshots.
- [ ] **T3 (P1, human: ~1h / Codex: ~20m)** - Add - Rename the candidate transition to `Use this place` without changing routing.
  - Surfaced by: S2; current `Save` label precedes the actual commit.
  - Files: `AddScreen.swift`, `NavigationContractTests.swift`.
  - Verify: focused test and rapid-tap/manual-source smoke.
- [ ] **T4 (P1, human: ~2h / Codex: ~30m)** - Import UI - Move count-aware commit to the existing terracotta capsule family.
  - Surfaced by: S3; one active import path still renders a custom dark rectangle.
  - Files: `ProfileImportViews.swift`, navigation/import tests.
  - Verify: 1/N/partial/progress/duplicate-tap tests and screenshots.
- [ ] **T5 (P2, human: ~4h / Codex: ~1h)** - Rollout - Add the off-by-default key and pure current-user action policy.
  - Surfaced by: architecture review; behavioral rollout needs a remote kill switch and deterministic state matrix.
  - Files: backend flag key, focused Map policy, migration, pgTAP, unit tests.
  - Verify: hosted flag checks plus fail-closed/account-isolation/policy tests.
- [ ] **T6 (P2, human: ~1d / Codex: ~2h)** - Place profile - Add the floating rail while routing to the legacy editor.
  - Surfaced by: S5 geometry canary.
  - Files: place profile, Map routing, focused tests.
  - Verify: flag fallback, top/deep scroll, safe area, Dynamic Type, VoiceOver.
- [ ] **T7 (P2, human: ~2d / Codex: ~4h)** - Save editor - Reuse one editor in the sheet and first-time Check-in tray.
  - Surfaced by: code-quality review; duplicated form state would create parity bugs.
  - Files: Map save editor/profile, draft integration, tests.
  - Verify: full first-check-in parity including offline/auth/draft/keyboard/retry.
- [ ] **T8 (P2, human: ~3d / Codex: ~6h)** - Save modes - Add Wanna, conversion, repeat, edit/delete, and shared invite one PR at a time.
  - Surfaced by: state and test review.
  - Files: Map save editor/policy plus focused tests per mode.
  - Verify: existing store semantics plus one integration flow per mode.
- [ ] **T9 (P2, human: ~3d / Codex: ~6h)** - Entry points - Converge existing profile destinations one surface at a time.
  - Surfaced by: nine current `MapPlaceSaveFlowSheet` callers cannot be safely cut over together.
  - Files: one feature module plus tests per PR.
  - Verify: destination, save, back, retry, and flag fallback per surface.
- [ ] **T10 (P3, human: ~1d / Codex: ~2h)** - Cleanup - Remove legacy status-choice/presentation code only after a later proven release.
  - Surfaced by: rollout review; early deletion removes the remote rollback path.
  - Files: Map save editor/routing and obsolete tests.
  - Verify: full suite and no production call sites for the legacy presentation.

## Completion Summary

- Step 0 Scope Challenge: scope reduced from a ten-file redesign to three
  independent launch-polish PRs plus a post-candidate flagged behavior train.
- Architecture Review: 0 unresolved issues after staged fallback and guest
  rules were made explicit.
- Code Quality Review: 0 unresolved issues; one editor and existing shared CTA
  are required, with no pre-launch rewrite.
- Test Review: coverage diagram produced; 25 planned gaps are assigned to the
  slice that introduces them.
- Performance Review: 0 issues; no new query, polling, persistence, or launch
  dependency is introduced.
- NOT in scope: written.
- What already exists: written.
- TODOS.md updates: 0. S10 is already captured as an implementation task rather
  than a vague future TODO.
- Failure modes: 0 silent critical gaps after tests and legacy fallback.
- Outside voice: skipped. The remote Codex pass was blocked before
  transmission because the plan had not received separate export approval.
- Parallelization: 5 lanes; 3 launch-polish lanes may develop in parallel but
  merge sequentially, and the Map behavior lane is sequential.
- Lake Score: complete behavior is retained, but it is delivered in reversible
  slices rather than as a launch-blocking rewrite.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | not run | Optional; product direction was already selected in the design pass |
| Codex Review | `/codex review` | Independent second opinion | 0 | skipped | Remote plan export was not separately approved; no plan content was sent |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | clear | Scope reduced, 25 test gaps assigned, 0 critical gaps |
| Design Review | `/plan-design-review` | UI/UX gaps | 1 | clear | Approved Editorial Fold direction and expanded flow boards |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | not required | No tooling or developer-facing workflow introduced |

**VERDICT:** ENG + DESIGN CLEARED. Implement S1-S3 independently; hold S4-S10
behind the 1.0 cutoff and then the off-by-default rollout gate.

NO UNRESOLVED DECISIONS
