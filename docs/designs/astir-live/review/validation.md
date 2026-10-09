# REC-636 validation record

October 9, 2026 · Standalone product-review package

## Scope and baseline

- Read the supplied strategy document and checked-in Live discussion; preserved product conclusions without copying the private transcript.
- Audited the current shell, Feed, Map, owner/member Profile maps, Patterns, snapshots, invitations, Events, analytics and test contracts. The isolated branch is based on integration commit `d9f827353648bab91a17187721b5ea41e65e1a42`.
- Profile continuity is fixed scope. D1–D11 are review recommendations, including any selective Your Map capability reuse. No full-map relocation is approved.
- Worktree: `/private/tmp/wander-live-review`; branch: `codex/live-experience-review`. The app lives only in `preview/rec-636-live/`. Production source, project membership, schema, hosted resources and build metadata are unchanged.

## Compiler and model checks

- Standalone Swift 6 type check passed for iOS 17+; XcodeGen generation and native `build-for-testing` passed with Xcode 26.6 / iOS Simulator SDK 26.5.
- **40 deterministic model checks passed.** Coverage includes trusted scopes, time/type/search intersections, staged filters, geographic circle membership, owner history/deduplication, Profile and selective-place return restoration, drawing state, future-plan labels and review scenarios.
- Native validation found and fixed a read-only Reduce Motion environment override, generated product-name collision, inherited accessibility identifiers, blank row hit areas, compact keyboard dismissal map attribution occlusion, compact drawer/row gesture competition and duplicate calendar IDs. These were prototype defects, not production app changes.

## Native simulator evidence

The dedicated devices are iPhone 17 Pro and iPhone SE (3rd generation), both iOS 26.5. The 16-case suite covers layout captures, drawer expansion and Map return, Profile → Your Map → Patterns continuity, selective one-place exploration/return, filter Apply/Cancel, local plan/reply flows and geographic radius application. Additional captures exercise dark peek/drawing with reduced motion, sparse/empty/offline states and accessibility text size 2.

**All 16 UI cases are verified on each phone size across the full run and focused reruns.** No case is skipped or accepted as an expected failure.

| Result bundle under `/private/tmp/rec636-evidence/` | Outcome |
|---|---|
| `large-review.xcresult` | 16/16 passed |
| `compact-review.xcresult` | 15/16 passed; drawer swipe exposed an unintended place-detail activation |
| `large-navigation-final.xcresult` | 3/3 passed after the final gesture/calendar corrections |
| `compact-navigation-final.xcresult` | 3/3 passed after the same corrections, including the previously failing drawer case |
| `large-profile-final.xcresult`, `compact-profile-final.xcresult` | 1/1 each after clipping scrolled Profile content to its safe-area bounds |

The focused reruns exercise Profile/calendar capture, drawer swipe → Map return → re-expand, and ordinary Wanna → plan taps. The regression asserts that a drawer swipe must not open an activity underneath it. Keeping half-drawer dragging at higher gesture priority fixes the compact conflict; full Feed content retains ordinary scrolling. Earlier failed runs are diagnostic history, not passing validation.

## Visual inspection and limits

The [capture gallery](captures.md) contains selected native screenshots. Raw result bundles and intermediate captures are retained once in `/private/tmp/rec636-evidence/`, outside the worktree; only small final captures are checked in. See the prototype README for reproducible build and test commands.

Secondary-text tokens measure 5.30:1 for `#625F57` on paper `#F2E9DB`, and 8.66:1 for `#B9B3A7` on ink `#141714`. These ratios apply to those opaque pairs, not every translucent material or basemap pixel.

Simulator automation and visual inspection do not establish spoken VoiceOver focus/order, real hardware gesture physics, performance under production data volume, or production accessibility compliance. Those remain implementation gates. The prototype uses a Reduce Motion override for its capture scenario; real system-setting behavior still requires a device check. Light/dark and large-text captures establish layout evidence only.

## Review and production boundaries

- All people, relationships, notes and coordinates are fictional fixtures. Apple MapKit may fetch public tiles. Plans, saves and replies mutate session-local state; no invitations, notifications or messages are delivered.
- Profile is a structural continuity representation. Production Snapshot enumeration/image creation, advanced map lenses and computed Patterns are not implemented in this fixture app; their existing production entries remain preserved by the proposal.
- The production native suite was not run because this package changes no production app code. SQL/RLS, hosted smoke, route/NUX migration, block/revocation, cache, analytics, delivery, performance and rollout tests are future gates in the engineering plan.
- No retention or production timing improvement was measured. Proposed performance budgets and D1–D11 choices require human review.
- The source recordings mentioned in the written discussion were unavailable; no frame-by-frame visual match is claimed.

## Artifact checks

Local Markdown targets, `git diff --check`, the review-storage budget and the repository manifest parser/file-scope check all passed. The 20 selected captures total less than 3 MiB; every file is below 1 MiB. The complete changed review package stays below 5 MiB. No raw recording, result bundle, user-specific Xcode data or production signing change is staged.

## Handoff

Open `preview/rec-636-live/AstirLiveReview.xcodeproj` in the isolated worktree, select `AstirLiveReview`, and follow the thirty-minute review script. Both the isolated production project and standalone review project were opened in Xcode and their Branch Choosers verified as `codex/live-experience-review`.

The review PR is classified `exclude` for the TestFlight manifest. It delivers the specification and prototype for review, not production implementation or release approval. The next human step is to resolve D1–D11, particularly the shell, circle-control meaning and selected Your Map capabilities, before creating implementation slices.
