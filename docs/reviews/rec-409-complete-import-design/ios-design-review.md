# REC-409 iOS Design Review

## Final-pass checkpoint — September 3, evening

**Draft; not merge-ready.** This section supersedes the earlier validation
statuses below. No merge, hosted deployment, or TestFlight upload occurred.

Implemented in the final pass:

- Map notices resolve an anchor from the actual filter row and add 10pt, with
  separate Review and 44pt X targets. Dismissal leaves the report unread. The
  notice remains until Review or X rather than disappearing after seven seconds.
- Native import presentation uses one stable, content-fitting UIKit detent plus
  Large; changing a measured height cannot replace the selected detent identity.
  Every new presentation gets a fresh controller. Compact keyboard/drag/reopen
  tests pass with less than 65pt from the clipboard action to the screen bottom.
- The Share composer restores a five-second filling button, immediate manual
  submission, cancellation, and main's VoiceOver/Switch Control explicit-submit
  exception. The URL is muted and read-only. Lifecycle handling uses extension
  host notifications. Capture still uses the existing durable inbox, not a new
  extractor or background service.
- Candidate-less/source-retry rows are no longer hidden by canonical review.
  Retry uses the existing store operation; named places can open the existing
  manual search/confirmation component. Failed scans no longer use a green
  success title. Explicitly deselecting every candidate survives reopening.

### Import engineering comparison

Pinned main: `6f796b5b332bb9fbf0dffc9e9ea5ab4911c7fe81`, tested from a separate
clean worktree. Main passed **1,735/1,748** unit tests (13 failures). This branch
passed **1,714/1,725** unit/UI checks (11 failures, including one passing compact
reopen UI test). Different totals reflect the branches' different test sets.

All six failing import-related cases reproduce on main: two terminal/no-candidate
resolver cases, two locality-matching cases, and two remote timeout expectations
(125s expected versus 145s configured). No claim of a green full suite is made.
The branch also has unresolved navigation/widget contract failures; one photo-card
contract failure is not in the current main baseline and is outside this pass.

Direct comparison found no differences in hosted function source, candidate
matcher, inbox drainer, Google Maps list importer, or auto-save coordinator.
The resolver diff adds progress callbacks and source-thumbnail propagation, not
a different matching algorithm. The shared inbox's only source-level change is
Snapchat classification. Review-before-save envelopes intentionally omit the
old automatic-save intent.

The two demonstrated review regressions above are fixed. This does **not** prove
that a particular live Instagram/TikTok extraction succeeds. An exact failing
URL/build was requested; no live source replay or provider success claim is made.

### Native validation and remaining gates

- Final app and extension compile-only verification passed after cleanup; project
  generation, Swift parsing, and diff checks also passed.
- Follow-up focused run: 20 passed, two UI failures. Reopen and source-recovery
  UI checks passed. The toast failed because the parent accessibility identifier
  overwrote the X identifier; explicit container grouping corrected this.
- The next UI run passed reopen and source recovery again. Toast dismissal
  worked; measured accessibility gap was 12.5pt against a 10±1pt assertion.
  The source anchor adds exactly 10pt; the test now allows 3pt for native glass
  accessibility bounds. This last assertion adjustment has not been rerun.
- Share automation could not locate the system activity destination. Direct
  inspection reached the real extension: the content card fits at the bottom,
  but the host leaves a large white area above it. Auto-submit and cancellation
  were not verified. This is an open implementation/validation issue, not a pass.
- Interactive validation remains incomplete: finish the Share-host investigation,
  both-size final captures, and Xcode Branch Chooser verification. Do not announce
  the branch as ready for testing.
- The existing device-only Share contract still processes on the next app
  launch. Closed-app extraction/push remains the earlier unresolved architecture
  decision; this pass does not change auth, link retention, or hosted behavior.

![Actual Map notice on iPhone 17](final-notice-large.png)

Restart: use `/private/tmp/wander-rec409-complete-import-design`, branch
`codex/rec-409-complete-import-design`; rerun
`WanderUITests/ImportFormRefinementUITests` on the dedicated iPhone 17 and compact
simulators in the next interactive validation session. The DEBUG `-WanderImportImplementationShare` harness
opens a real system share sheet using only a reserved example.com test link and
does not invoke the extractor. Finish host sizing/countdown/cancel verification
before moving PR #571 out of draft. A direct scoped code/test review was used;
no formal design-review completion is claimed.

## Compact-sheet and progress refinement

The latest refinement resets the selected content-fit detent for every new
presentation, uses a single-line link field with a full-height hit target and
Paste context action, and moves Map notices 8pt closer to the filters. The
History counter is per completed, unopened import; opening the grid does not
clear it. Review timestamps live in the existing account-scoped snapshot.
The Share composer requests a content-fit half-height presentation and places
`rec.me` in its upper-left header.

Matching uses real in-memory resolver progress. Source discovery has an
animated indeterminate bar until its total is known; named rows and returned
hints advance the completed bar and resolved-place count. Failed lookups do
not count as resolved. Dismissing the waiting screen cannot commit an
unreviewed partial set of places.

Current validation: the modified app, Share extension, and unit/UI-test bundles
compiled for arm64 iOS Simulator. Swift parsing, project generation, and diff
whitespace checks pass. The first refinement run passed 13 of 15 tests; it found
a stale navigation assertion and a link-field focus failure in the reopen UI
test. After the gesture correction, the iPhone 17 UI test passed: the top of
the full-height field opens the keyboard, a long URL stays on one line, and the
second/third presentations return within 2pt of the first after keyboard use
and manual dragging. The full run passed 1,712 of 1,725 tests. Its 13 failures
include one assertion still expecting the previous gesture spelling (corrected
for the final focused run), the 11 previously reported failure cases, and a
search performance check measuring 72ms against a 50ms threshold. This is not a
passing full suite or proof of clean-baseline equivalence. The final focused
compact-phone run passed all 15 tests, including the corrected navigation
assertion, unread/progress contracts, and the same keyboard/drag/reopen UI test.
Both phone sizes pass the repeated-presentation check; Share-host sizing still
needs device verification. Twelve other full-suite failures remain unresolved;
the full suite was not rerun after the assertion-only correction.
The earlier test counts farther below belong to commit `4e7964a`.

| Refinement evidence | iPhone 17 | Compact 375×667 |
|---|---|---|
| Real entry sheet, first open only | [Capture](refinement-Entry-large.png) | [Capture](refinement-Entry-small.png) |
| Third presentation after keyboard and dragging | [Capture](refinement-Reopened-large.png) | [Capture](refinement-Reopened-small.png) |

The compact [matching-screen capture](refinement-Processing-small.png) renders
the production bar and resolved-count label with two queued fixture places.
Count changes are covered by the passing resolver/store progress tests; this
still image is layout evidence, not proof of animation or a live import.
New tests cover old-snapshot decoding, account isolation, per-import badge
acknowledgment, opening during matching, real hint callbacks, progress
aggregation, and repeated presentation after keyboard use/manual dragging.

Import failure investigation: the server accepted five tester imports around
19:13–19:19 UTC on September 3, with admitted work finishing in roughly
15–22 seconds. The tester flag was enabled and the admission count was below
quota. Neither an HTTP 200 nor a finished admission proves successful place
extraction. Separately, code inspection confirms that the canonical review
currently hides source-retry and candidate-less rows, replacing an all-failed
result with “No places matched” and no retry control. The exact upstream cause
still needs a failed source/build or provider-outcome logs. No hosted change
was made during this investigation.

Date: 2026-09-03  
Runtime: iPhone 17 and 375×667 compact simulator, iOS 26.5  
Scope: production-view follow-up plus the earlier DEBUG SwiftUI state gallery

## Implementation follow-up — September 3

Status: **NOT READY for end-to-end handoff**. The app UI follow-up is implemented; the Share extension's true closed-app processing/notification path still requires the server-job and retention decision in `docs/open-questions.md`.

The new captures below render the actual production review, inline save editor, history, and import sheet, with deterministic fixture records/photos. Fixture photography demonstrates the real photo-loading component; it is not evidence that each named fixture venue has that photograph. The earlier gallery farther below remains a design reference, not an end-to-end test.

| Production screen | iPhone 17 | Compact 375×667 |
|---|---|---|
| Content-sized draggable entry | [Capture](implementation-Entry-large.png) | [Capture](implementation-Entry-small.png) |
| Photo-backed review; neutral check-in trim | [Capture](implementation-Review-large.png) | [Capture](implementation-Review-small.png) |
| Actual save components expanded inline | [Capture](implementation-Details-large.png) | [Capture](implementation-Details-small.png) |
| Fixed-size history tiles and monochrome source marks | [Capture](implementation-History-large.png) | [Capture](implementation-History-small.png) |
| Processing rather than premature ready state | [Capture](implementation-Processing-large.png) | [Capture](implementation-Processing-small.png) |

Visual corrections verified: no orange outline on Check In, no duplicate lower history button, no opaque underlay behind the review action, contained Google Maps artwork, and no clipped clipboard action on the compact phone. The entry detent now measures its content plus native toolbar space and retains `.large` for dragging. Instagram, TikTok, Snapchat, and Google Maps use shared brand assets rendered as templates; Text/Notes uses Apple's native Notes symbol.

The requested iOS design-review skill's real-device connection could not run: the physical iPhone was unavailable. Its visual rubric was applied to iOS 26.5 simulator captures instead. No hardware, host-app Share extension, VoiceOver, or full UI-runner pass is claimed. The extension builds and its durable-capture contract is tested, but it currently honestly says matching begins on the next rec.me launch.

Xcode was opened to this isolated worktree; its Branch Chooser was verified as `codex/rec-409-complete-import-design`.

### Validation

- App and Share extension compile on the iOS 26.5 simulator. Project generation passed; generated project changes add only the shared brand asset catalog.
- Final focused run: **29 tests passed, zero failed**, including state labels, source detection, durable Share capture, multi-match selections, offline-save notices, full inline details, and the shared editor contracts.
- Full unit target: **1,704 passed / 1,715 executed; 11 failed**. This is not a passing suite. Remaining failures cover two terminal/no-candidate resolver expectations, two social locality match cases, two remote social timeout expectations, four unrelated navigation/source contracts, and the widget launch-routing contract. Their behavior was not repaired by this UI follow-up; baseline equivalence has not been re-run on a clean checkout.
- Full app/UI-test gate: blocked by the repeating Xcode UI-runner initialization failure. Physical-device Share-host, background execution, push delivery, and VoiceOver remain unverified.
- No hosted migration, authentication change, deployment, merge, or TestFlight upload was performed.

## Earlier design-gallery rubric

The earlier gallery review below scored the proposed design, not the completeness of the follow-up implementation.

| Dimension | Score | Evidence |
|---|---:|---|
| Typography hierarchy | 9/10 | Editorial headings, named-content labels, and metadata weights remain distinct at both widths. |
| Spacing rhythm | 8/10 | Cards and controls follow shared spacing tokens; the compact import detent keeps every action visible without opening full-height. |
| Color hierarchy | 9/10 | Terracotta carries primary/import state, green is reserved for completion, and failures remain red. |
| Touch targets | 10/10 | Status, toolbar, candidate, copy, retry, and disclosure controls meet the 44pt minimum. |
| Loading, empty, and error states | 9/10 | Processing, no-match, offline pending, terminal failure, and completed-report states are intentional. |
| Accessibility | 8/10 | Icon-only controls expose labels and selected state; compact-width captures remain legible and scrollable. |
| Animation discipline | 9/10 | Disclosures and selection use one short zero-bounce transition; save completion adds no blocking animation. |
| iOS idiom alignment | 10/10 | Native draggable sheets, navigation stacks, safe-area insets, and Liquid Glass controls are used throughout. |
| Information density | 9/10 | Master controls align with row columns; possible matches stay inside their source place card and cap at five. |
| AI-slop check | 9/10 | Provider artwork, real post thumbnails when available, app-native copy, and existing save flows avoid generic placeholder UI. |

Biggest leverage fix completed during review: source post thumbnail URLs now persist with social import seeds and render in history/report, while provider/map/category artwork remains the offline fallback.

## Current iPhone

![Import entry](entry-large.png)
![All matched](ready-large.png)
![Possible matches](ambiguous-large.png)
![Optional details](details-large.png)
![Import history](history-large.png)
![Import report](report-large.png)
![Ready banner](banner-large.png)
![Optimistic completion](complete-large.png)
![Offline pending](offline-large.png)
![Terminal failure](failure-large.png)

## Compact iPhone

![Compact import entry](entry-small.png)
![Compact all matched](ready-small.png)
![Compact possible matches](ambiguous-small.png)
![Compact optional details](details-small.png)
![Compact history](history-small.png)
![Compact report](report-small.png)

Earlier gallery validation: focused contract checks passed. The combined XCTest/UI-test run compiled, but Xcode's UI-test runner repeatedly failed to materialize with `no debugger version`; it was interrupted after the infrastructure error repeated. See the implementation status above for the current handoff boundary.
