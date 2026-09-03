# REC-409 iOS Design Review

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
