# REC-409 Complete Import Redesign

Status: design-complete, implementation not started  
Linear: REC-409  
Design branch: `codex/rec-409-complete-import-design`

## Outcome

Import becomes a fast, resumable place-capture workflow with one principle:

> Ready by default; exceptions by attention.

Most people should see that their places are ready, optionally enrich one or two, and add them immediately. Uncertain items remain visible and recoverable without blocking the ready items. Every source link also becomes a durable import report that can be reopened from an image-first history.

This branch contains the workflow decision, state contract, and DEBUG-only SwiftUI mockups. It intentionally does not change production import behavior.

## Product shape

There are two user-facing capabilities and one reliability layer:

1. Core import review: resolve places, focus attention on exceptions, optionally add details, and add the selected places.
2. Import history: retain a report for every source link and reopen the canonical review experience with the original choices visible.
3. Optimistic completion: durably queue saves locally, release the UI immediately, and sync or recover in the background.

History is incremental on top of the core review model. Optimistic completion is shared save infrastructure and should land independently so its reliability can be reviewed separately.

## End-to-end workflow

```text
ADD TAB / SHARE EXTENSION
        |
        v
+---------------------------+
| Import places             |
| source link + History     |
+---------------------------+
        |
        | Start import
        v
+---------------------------+
| Local capture receipt     |  The source link is durable before work begins.
| Processing in background  |
+---------------------------+
        |
        +------------------------- source scan failed / unsupported
        |                                           |
        v                                           v
GLOBAL COMPLETION ROUTING                   RETRY SOURCE / KEEP REPORT
  - in-app banner
  - OS notification when away
  - one reminder if never opened
        |
        v
+---------------------------------------------------+
| Canonical review                                  |
|  1. outcome headline                              |
|  2. exceptions needing attention                  |
|  3. collapsed ready receipt                       |
|  4. optional per-place details                    |
|  5. persistent Add N places action                |
+---------------------------------------------------+
        |
        | Add N places
        v
+---------------------------+
| Durable local save queue  |
+---------------------------+
        |
        +---- local write failed --> stay in review; no success claim
        |
        v
IMMEDIATE CONFIRMATION + RETURN TO MAP
        |
        +---- online --> background sync --> complete
        |
        +---- offline --> neutral saved-on-phone notice --> later sync
        |
        +---- terminal failure --> 10s+ retry banner + report warning
        v
+---------------------------+
| Import history            |
| source thumbnail grid     |
|   -> canonical report     |
+---------------------------+
```

## Information architecture

### Entry points

```text
Add tab
  -> Import places sheet
       -> History (visible trailing toolbar action)
       -> Latest import ready (when present)

Share extension
  -> capture receipt
  -> completion routing
  -> canonical review

Profile
  -> Settings
       -> Data & imports
            -> Import history

In-app completion banner / OS notification / reminder
  -> canonical review for the referenced import
```

Do not add another control to the already crowded Profile header. The frequent history entry is on the Import places sheet; the durable secondary entry is tucked into Settings.

### Review hierarchy

If only three things fit above the fold, they are:

1. What happened: ready, partially ready, or needs help.
2. The first item that needs attention, when one exists.
3. The exact primary outcome: `Add N places`.

Ready results collapse into a receipt when exceptions exist. On the all-ready screen, the receipt leads because it is the outcome. On an exception screen, the exception leads and the receipt follows.

## State contract

Batch, source, place resolution, and save outcome are separate axes. Do not overload a single status enum to represent all four.

### Batch lifecycle

| State | User-visible treatment | Exit |
|---|---|---|
| Captured | Source link appears as a durable local receipt. | Processing begins. |
| Processing | Compact progress with source artwork when available; user may leave. | Ready, source attention, or cancelled. |
| Ready for review | Completion route opens the canonical review. | User adds, defers, or dismisses. |
| Saving locally | Primary action is briefly progress-locked only for the local durable write. | Immediate completion or local-write error. |
| Complete | Import report remains in history; remote sync may still be pending. | Synced, offline pending, or retry needed. |
| Needs retry | Report and global retry surface preserve the source and choices. | Retry or explicit discard. |
| Cancelled | Processing stops; no silent deletion of a completed report. | Restart from source if desired. |

### Source-level outcomes

| Outcome | What the user sees | Action |
|---|---|---|
| Source processing | Provider, artwork/fallback, progress copy, and permission to leave. | None required. |
| Scan incomplete | Places already found remain; source-level warning explains that more may exist. | `Retry scan`. |
| Unsupported source | Honest provider-specific explanation; original link remains copyable/retryable. | `Try another link`. |
| No places found | Warm empty result with source context. | `Search manually` or `Try another link`. |
| Source failed | Inline error, not a blank report. | `Retry`. |

### Place resolution outcomes

| Resolution state | Default presentation | Available action |
|---|---|---|
| Resolving | Skeleton row that retains the extracted clue; never a generic spinner-only screen. | Wait or leave. |
| Resolved, high confidence | Selected by default and included in `Add N places`. | Change status, add details, or remove. |
| Ambiguous, 2–5 candidates | `Possible matches`; best candidate selected by default; at most five total candidates. | Keep the recommendation, choose one alternative, clear it, or search. |
| Needs a match, zero candidates | Extracted clue plus inline search field and recent/map-proximate suggestions. | Choose one place or leave for later. |
| Already saved | Passive duplicate receipt showing existing status; import never overwrites existing rating, note, or status implicitly. | Open the existing place or exclude it from this report. |
| Retryable place failure | Extracted clue plus concise failure reason. | Retry this item or leave for later. |
| Excluded / skipped | Muted receipt retained in the report. | Restore to review. |

### Save outcomes

| Outcome | User-visible treatment |
|---|---|
| Queued locally | Immediate `N places added` confirmation after the durable local write. |
| Pending offline | Neutral `Saved on this phone` notice; no red error semantics. |
| Synced | No interruption; history report quietly becomes complete. |
| Retryable sync failure | Warning remains on the report; automatic retry continues. |
| Terminal sync failure | Red banner/toast remains visible for at least 10 seconds with `Retry`; source link, choices, and local place drafts remain intact. |

### State transitions

```text
resolving
  -> resolved
  -> ambiguous -> resolved | needs match | excluded
  -> needs match -> resolved | excluded
  -> duplicate
  -> retryable failure -> resolving | excluded

resolved | duplicate
  -> queued locally
  -> synced | pending offline | retryable sync failure | terminal sync failure
```

## Matching interaction

- Show candidates in one `Possible matches` subsection for each extracted place.
- Show no more than five candidates: one best candidate plus four alternatives.
- The best candidate is selected by default.
- Selection is zero-or-one, never multi-select. Selecting an alternative moves the checkmark to it.
- Nonselected candidates are visually muted but remain fully tappable and VoiceOver-enabled; they must not look disabled.
- A selected recommendation counts in `Add N places`. If the user clears it, the CTA count decreases and a caption states, for example, `1 place stays here for later`.
- `Search for a different place` follows the candidates and opens inline search without discarding the extracted clue.
- Candidate confidence is expressed as `Best match`, not a numeric score.
- If there is only one high-confidence match, treat it as resolved rather than manufacturing an ambiguity screen.

## Review and optional details

Each selected place has two primary status choices: `Wanna` and `Check In`. Neither status silently generates a rating.

`Add details` expands the selected place inline. Only one place disclosure stays open at a time so the list remains navigable. The expanded order is:

1. Rating — always `Not rated` until the user chooses one.
2. Note — prompt: `Why did you save this?`
3. When — `Today` may be explicit for a new Check In; Wanna has no visit date default.
4. Place type.
5. Category.
6. Subcategory.
7. Friends.
8. Photos.
9. Lists — per-place membership only.
10. More options — visibility, tags, and infrequent metadata.

Lists are deliberately not a third batch-level action. A list assignment belongs to the place disclosure because different imported places may belong to different lists.

The persistent CTA always names the exact operation. Never display `Add 0 places`. If nothing is selected, the primary action becomes `Keep for later`; the nearest resolvable item retains the visual emphasis.

## Import history and report

### History semantics

- Every source link produces one report.
- Starting another import replaces the `current import` pointer used by the main import flow; it never deletes older reports.
- Reports remain until the user deletes them or deletes the account.
- The history grid is two-column and image-only. There are no generated or authored titles.
- A small provider glyph identifies Instagram, Google Maps, TikTok, or another supported source.
- A small attention-count badge appears only when unresolved or failed items remain.
- Missing artwork uses a warm provider fallback rather than an empty gray rectangle.
- Each tile's accessibility label includes provider, date, place count, and attention count even though the visual tile has no title.

### Report behavior

Tapping a thumbnail opens the same canonical review component in report mode:

- Original selections, statuses, optional details, and skipped items are shown as they were at import time.
- Completed membership is a historical snapshot, not a second editor that can silently rewrite the import.
- Tapping a completed place opens its current place detail/edit flow.
- Any unresolved or failed item remains actionable in place.
- The report header shows source artwork, provider, date, imported count, and current attention status.

This reuse is a design constraint: there should not be a separate bespoke history-detail UI that drifts from review.

### Empty, loading, and image failure

- Empty: warm `No imports yet` explanation with one `Import places` action.
- Loading: image-shaped skeletons preserving the two-column rhythm.
- Image failure: provider fallback plus the same accessible metadata.
- Partial: loaded tiles remain interactive while remaining thumbnails resolve.

## Completion, notification, and reminder

There are three completion routes into the same report:

1. While in the app: a top overlay banner appears above the current screen with `Review` and an explicit 44pt close button. It persists until dismissed or opened.
2. While away: an OS notification says the import is ready and deep-links to the report.
3. If never opened: send one reminder 24 hours after completion, shifted to the next reasonable local-time slot when it would land during quiet hours.

Rules:

- Dismissing the in-app banner does not mark the report reviewed.
- Opening the report from any route cancels the reminder.
- At most one reminder is sent per import; reminders may be coalesced if several imports complete close together.
- If notification permission is unavailable, history and the in-app banner remain sufficient; do not nag for permission from this flow.
- Personalized friend-engagement copy is a separate, non-launch feature.

## Optimistic completion and recovery

The UI may leave review only after the app has durably written the complete save intent locally. Remote server success is not required for the immediate completion experience.

```text
User taps Add N places
  -> atomically persist source, selected candidates, statuses, details, and save intents
     -> failure: remain in review; explain local save failure
     -> success: short confirmation/confetti; return to map immediately
        -> background sync
           -> success: silent completion
           -> offline: neutral saved-on-phone notice
           -> repeated/terminal failure: durable warning + Retry
```

This applies to all multi-place saves, not only imported packages. Automatic retry should normally occur within seconds, but the durable queue must survive force quit, app restart, and no-network conditions. Retrying must be idempotent.

## Interaction state coverage

| Surface | Loading | Empty | Error | Success | Partial |
|---|---|---|---|---|---|
| Import entry | Clipboard/source validation appears inline without blocking History. | Blank source field with provider examples. | Invalid link stays editable with a provider-specific reason. | Start import becomes available. | Latest report remains reachable while a new link is entered. |
| Source processing | Artwork/fallback, provider, and progress; user may leave. | `No places found` plus manual search. | Preserved link with Retry. | Completion route announces ready count. | Found places remain visible beside scan warning. |
| Canonical review | Per-place clue skeletons, not a page spinner. | `Nothing selected yet`; nearest exception stays active. | Item-level Retry; ready places remain addable. | Outcome headline, selected count, exact CTA. | Exceptions lead; ready receipt collapses below. |
| Candidate matching | Stable clue card and candidate skeleton rows. | Inline search when no candidates exist. | Retry candidate lookup without losing clue. | One checked candidate, alternatives muted. | Up to five candidates; other import items remain ready. |
| Optional details | Row-local progress for photos/friends/lists. | Explicit values such as `Not rated`, `No note`, `No list`. | Failed subaction stays inside the expanded place. | Saved value appears in the row summary. | One detail can fail without blocking the place selection. |
| Import history | Two-column image skeletons. | Warm `No imports yet` with Import action. | Provider fallback or retry banner; report metadata survives. | Image-only report grid. | Loaded tiles remain usable while artwork resolves. |
| Import report | Header and row skeletons preserve layout. | Honest `No places found` report rather than disappearing. | Unresolved/failed row remains actionable. | Original choices visible; completed place opens current detail. | Completed and unresolved rows coexist. |
| Local save / sync | Only the durable local write briefly locks the CTA. | No `Add 0`; use `Keep for later`. | Local failure stays in review; terminal remote failure offers Retry for 10s+. | Immediate confirmation then map. | Offline pending is neutral; successful local items remain available. |

## User journey and emotional arc

| Step | User does | Intended feeling | Design support |
|---|---|---|---|
| 1 | Pastes or shares a link. | Certain that rec.me has it. | Durable receipt, clear provider context, visible History. |
| 2 | Leaves while processing. | Unburdened. | Background work and global completion routing. |
| 3 | Opens review. | Relieved, not assigned homework. | Outcome-first headline and ready-by-default selection. |
| 4 | Encounters an ambiguity. | Guided, not stuck. | Best match selected, four alternatives maximum, clue retained. |
| 5 | Adds one note or list. | In control. | Inline disclosure with no context switch or random values. |
| 6 | Adds the places. | Instant gratification. | Durable local queue, immediate confirmation, return to map. |
| 7 | Goes offline or sync fails. | Trusting that work is safe. | Neutral offline state; explicit long-lived retry on real failure. |
| 8 | Returns weeks later. | Able to remember why these places mattered. | Image-first history and preserved report snapshot. |

Time horizons:

- Five seconds: `It worked; most places are already handled.`
- Five minutes: `I can fix one match and enrich the places I care about without reviewing everything.`
- Five years: `rec.me still remembers where this group of places came from and what I chose.`

## Visual and component decisions

Classifier: native app UI.

- Reuse the warm canvas, bone surfaces, ink text, terracotta action color, success green, editorial serif titles, 8pt spacing rhythm, and 44pt controls defined by `DESIGN.md`.
- Use one calm canvas and minimal chrome. Cards exist only where the card is the interaction: a place, candidate group, source receipt, or report tile.
- Source imagery is the primary visual anchor in history; do not generate titles to compensate for weak thumbnails.
- Avoid dashboard mosaics, decorative gradients, ornamental icon circles, thick borders, and stacked explanatory cards.
- Status always combines color with icon and copy.
- Candidate and place rows use thin separators inside one semantic group instead of a card per row.
- Primary actions use the existing dark espresso treatment; terracotta remains the selection/action accent.

AI-slop check:

| Check | Result |
|---|---|
| Product unmistakable on first screen | Yes — source artwork, provider, place counts, and rec.me vocabulary. |
| One strong visual anchor | Yes — source artwork or resolution outcome. |
| Understandable by headings alone | Yes — outcome, exceptions, ready receipt, details. |
| One job per section | Yes. |
| Cards necessary | Yes, only for interactive place/source objects. |
| Motion improves hierarchy | Yes, limited to resolution collapse and completion. |
| Premium without shadows | Yes; hierarchy is typography, imagery, spacing, and state. |

## Responsive, accessibility, and motion

### Viewports

- Small iPhone: one-column review; source clue wraps; candidate address truncates after the meaningful street segment; persistent CTA respects the home indicator. History remains two-column because tiles contain no visible text.
- Current iPhone: review uses 16pt side insets and the content order shown in the approved renders.
- Wider iPhone / iPad compatibility: center review at a 620pt maximum content width and history at a 760pt maximum width. Do not stretch the phone composition into a dashboard or invent a side panel in this scope.
- Keyboard: focused fields remain visible above the keyboard; the persistent CTA moves with the keyboard only when its action remains valid.

### Accessibility

- Minimum tap target is 44×44pt, including checkmarks, disclosure rows, close buttons, and history tiles.
- Dynamic Type must be verified at default, Extra Extra Large, and an accessibility size. Editorial headings wrap; no essential row has a fixed text height.
- VoiceOver groups each place/candidate row and announces place name, supporting location, `Best match` when applicable, and selected state.
- History tiles announce provider, date, number of places, and unresolved count.
- Do not communicate disabled, warning, selected, or failed state with opacity/color alone.
- Source thumbnails are decorative when equivalent metadata is announced; meaningful user photos receive their existing place-photo descriptions.
- Full Keyboard Access follows visual order: close/back, headline context, exceptions, ready receipt, place details, primary CTA.

### Motion

- A resolved exception collapses into the ready receipt in one approximately 220ms movement.
- No more than two imported rows animate simultaneously; larger batches settle without cascading spectacle.
- Immediate add confirmation is short and does not block interaction.
- Reduce Motion replaces movement/confetti with an instant state change and the same confirmation copy.

## Copy contract

| Situation | Headline / action | Supporting copy |
|---|---|---|
| All ready | `All 13 places are ready` | `Everything matched. Add details only where you want them.` |
| One ambiguity | `12 ready, 1 quick check` | `We picked the most likely match. Change it only if it looks wrong.` |
| Needs match | `11 ready, 2 need a match` | `Tell us which places these are, or keep them for later.` |
| All selected | `Add 13 places` | No caption. |
| One cleared | `Add 12 places` | `1 place stays here for later.` |
| Nothing selected | `Keep for later` | No fake add count. |
| In-app ready | `Your import is ready` / `Review` | `12 ready · 1 quick check` |
| Immediate completion | `13 places added` | `We’ll finish syncing in the background.` |
| Offline | `Saved on this phone` | `We’ll sync 13 places when you’re back online.` |
| Terminal failure | `3 places still need saving` / `Retry` | `Your link and choices are safe.` |
| History empty | `No imports yet` / `Import places` | `Posts and shared lists you import will stay here.` |

## Analytics contract for implementation

Instrument transitions in the store/domain layer where practical, not from transient view appearance. The implementation must update `docs/analytics.md`, contract/privacy tests, and the managed dashboard script if a metric changes.

Required measurements:

- import captured, processing completed, and review opened;
- resolution-state counts using aggregate counts only;
- suggested candidate kept, alternative selected, cleared, and manual search used;
- optional details expanded and detail type used;
- local save queued, offline pending, sync completed, and retry tapped;
- history opened, report opened, and completion/reminder route used.

Allowed properties are provider enum, aggregate counts, resolution enum, route enum, elapsed-time bucket, retry count bucket, and build. Never emit source URLs, raw search text, place names, notes, list names, coordinates, friend identifiers, notification copy, APNs identifiers, or private payloads. Successful place adds should continue to emit the existing engagement action from the domain transition when applicable.

## Design decisions

1. Use `ready by default; exceptions by attention` as the governing review model.
2. Separate batch, source, place-resolution, and save-outcome states.
3. Lead with exceptions when any exist; otherwise lead with the ready receipt.
4. Cap ambiguous candidates at five and preselect the best candidate.
5. Allow zero or one candidate selection; a default selection counts in the CTA until cleared.
6. Never overwrite an existing place's status, rating, or note because it reappears in an import.
7. Expand optional details inline, one place at a time, and never invent a rating.
8. Put list membership inside per-place details; no batch-wide list control in launch scope.
9. Make the CTA state the exact count and replace `Add 0` with `Keep for later`.
10. Retain one historical report per source link until deletion; a new import changes only the current pointer.
11. Make history a two-column, image-only grid with provider and attention badges but no titles.
12. Reuse the canonical review component for report mode and keep completed membership as a snapshot.
13. Route in-app banners, OS notifications, and one 24-hour reminder to the same report.
14. Declare local durable persistence—not server completion—the gate for optimistic UI success.
15. Treat offline as neutral pending work and terminal failure as an explicit 10-second-plus retry surface.

## What already exists

- `DESIGN.md` defines the warm palette, editorial type hierarchy, spacing, control sizing, and map-first visual language.
- `Wander/Models/PlaceImportModels.swift` already names queued, resolving, ready, ambiguous, needs-help, duplicate, saved, failed, and dismissed concepts that can be migrated into the separated state model.
- `Wander/Services/PlaceImportStore.swift` already persists import batches and receipts; the history/report model should evolve that boundary rather than bypass it.
- `Wander/Features/Profile/ProfileImportViews.swift` contains the current importer and review surfaces; the canonical review should replace or compose these rather than creating parallel production flows.
- `Wander/Features/Add/AddScreen.swift` already owns the Add entry point.
- `Wander/App/WanderRootView.swift` already coordinates root-level presentation and is the natural home for global completion routing.
- Existing place save editors, list pickers, friend pickers, photo controls, and place-detail routing should be composed into inline details rather than reimplemented.

## NOT in scope

- Personalized friend or engagement-flywheel notifications — separate experiment after the private import loop is trustworthy.
- Nightly LLM-written notification copy — unnecessary launch complexity and a separate privacy/product decision.
- Batch-wide assignment of every imported place to one list — conflicts with per-place intent and adds power before the core loop is stable.
- Resolver confidence algorithms and provider extraction quality — this plan designs the outcomes and recovery UI, not ranking internals.
- Public feed or friend-facing import reports — history is private user memory in this scope.
- Generated history titles — the transcript explicitly prefers thumbnails without titles.
- Production implementation — begins only after this design handoff is approved.

## Implementation sequence

### Branch 1 — core resolution and review (REC-409)

Land the separated state model, canonical review composition, exception-first ordering, candidate selection rules, duplicate treatment, exact CTA behavior, inline details, and deep-linkable report route contract. Keep the report persistence interface forward-compatible with history.

### Branch 2 — optimistic save reliability (coordinate with REC-341)

Land the durable local save-intent queue, idempotent background sync, app-restart recovery, neutral offline treatment, terminal retry surface, and migration of bulk save paths. This should be independently testable because a false success claim risks user data.

### Branch 3 — history and completion routing (new incremental issue)

Land report snapshots, source artwork lifecycle, current-report pointer, Import sheet and Settings entry points, image grid, canonical report mode, in-app completion banner, OS deep link, and single reminder. Stack this after the canonical review contract is stable.

## Implementation Tasks

Synthesized from this review's findings. Each task derives from a specific finding above. Run with Codex; checkbox as you ship.

- [ ] **T1 (P1, human: ~1.5d / Codex: ~3h)** — Import domain — Separate batch, source, resolution, and save states
  - Surfaced by: Interaction State Coverage — the current status surface conflates resolution and persistence outcomes.
  - Files: `Wander/Models/PlaceImportModels.swift`, `Wander/Services/PlaceImportStore.swift`, `WanderTests/PlaceImportTests.swift`
  - Verify: focused import model/store tests plus state-transition contract tests.
- [ ] **T2 (P1, human: ~2d / Codex: ~4h)** — Canonical review — Build outcome-first, exception-led review composition
  - Surfaced by: Information Architecture — exception work must precede the collapsed ready receipt when attention is needed.
  - Files: `Wander/Features/Profile/ProfileImportViews.swift`, import view-model/store files, UI tests
  - Verify: all-ready, mixed, all-exception, duplicate, and zero-selection screenshots on current and small iPhones.
- [ ] **T3 (P1, human: ~1d / Codex: ~3h)** — Place matching — Implement zero-or-one candidate selection with five-result cap
  - Surfaced by: Interaction State Coverage — ambiguous and zero-candidate outcomes need distinct, recoverable controls.
  - Files: import review views, resolver adapter/view model, `WanderTests/PlaceImportTests.swift`
  - Verify: best preselection, alternative selection, clear, manual search, and accessibility-state tests.
- [ ] **T4 (P2, human: ~1.5d / Codex: ~4h)** — Inline enrichment — Compose optional place details into one disclosure
  - Surfaced by: User Journey — people need to add a note, list, rating, or visit context without leaving the batch.
  - Files: import review views and existing save-editor/list/friend/photo components
  - Verify: no random rating, correct Check In date default, one disclosure open, draft retention after scroll/relaunch.
- [ ] **T5 (P1, human: ~3d / Codex: ~1d)** — Save reliability — Add durable optimistic queue and idempotent recovery
  - Surfaced by: User Journey and Interaction States — remote latency must not block UI, but success cannot precede a durable local write.
  - Files: place save repository/store, local persistence models, sync coordinator, focused save/sync tests
  - Verify: 30-place save, airplane mode, force quit/relaunch, duplicate retry, partial remote failure, and local-write failure.
- [ ] **T6 (P2, human: ~1d / Codex: ~3h)** — Completion routing — Add banner, notification deep link, and one reminder
  - Surfaced by: Information Architecture — all completion surfaces must return to the same report.
  - Files: `Wander/App/WanderRootView.swift`, notification coordinator, deep-link router, analytics tests
  - Verify: foreground, background, dismissed banner, opened report, 24-hour reminder, quiet-hours shift, and no-permission behavior.
- [ ] **T7 (P2, human: ~2d / Codex: ~5h)** — Import history — Persist and render image-first reports
  - Surfaced by: Unresolved Design Decisions — a new import changes the current pointer but must not erase prior work.
  - Files: import store/repository, Import sheet, Settings, canonical review/report, persistence tests
  - Verify: two entry points, empty/loading/image-failure/partial states, report snapshot, unresolved recovery, deletion, and multiple imports.
- [ ] **T8 (P2, human: ~1d / Codex: ~3h)** — Accessibility and analytics — Complete the nonvisual contract
  - Surfaced by: Responsive & Accessibility and Design System Alignment — state must remain usable without color, standard text size, or private analytics payloads.
  - Files: import accessibility identifiers/labels, analytics contracts, `docs/analytics.md`, managed dashboard script
  - Verify: VoiceOver, Full Keyboard Access, Reduce Motion, accessibility Dynamic Type, `npm --prefix scripts run analytics:check`, and privacy tests.

## Approved Mockups

| Screen / state | Mockup path | Direction | Constraint |
|---|---|---|---|
| Import entry | `docs/reviews/rec-409-complete-import-design/entry-large.png` | Bottom sheet over map with visible History and latest-report entry. | Source must be durable before processing. |
| All ready | `docs/reviews/rec-409-complete-import-design/ready-large.png` | Outcome-led receipt with optional place review. | Do not force item-by-item review. |
| Possible matches | `docs/reviews/rec-409-complete-import-design/ambiguous-large.png` | Exception leads; five candidates maximum; best selected. | Alternatives remain tappable, not disabled. |
| Inline details | `docs/reviews/rec-409-complete-import-design/details-large.png` | Selected place expands into the save-detail rows. | No random rating; one disclosure at a time. |
| History | `docs/reviews/rec-409-complete-import-design/history-large.png` | Two-column source-artwork grid. | No visual titles; provider and attention badges only. |
| Historical report | `docs/reviews/rec-409-complete-import-design/report-large.png` | Canonical report with preserved choices. | Completed membership is snapshot; place opens current detail. |
| In-app ready banner | `docs/reviews/rec-409-complete-import-design/banner-large.png` | Persistent top overlay with Review and explicit close. | Dismissal does not mark report reviewed. |
| Optimistic completion | `docs/reviews/rec-409-complete-import-design/complete-large.png` | Immediate compact success over the map. | Show only after durable local write. |
| Offline pending | `docs/reviews/rec-409-complete-import-design/offline-large.png` | Neutral saved-on-phone notice. | Offline is not an error. |
| Terminal save failure | `docs/reviews/rec-409-complete-import-design/failure-large.png` | Long-lived error with Retry. | Preserve link, choices, and local drafts. |
| Small-phone all ready | `docs/reviews/rec-409-complete-import-design/ready-small.png` | Compact-width validation. | CTA clears home indicator; headings wrap. |
| Small-phone matches | `docs/reviews/rec-409-complete-import-design/ambiguous-small.png` | Exception stays primary on a short viewport. | Candidate group scrolls behind fixed CTA. |
| Small-phone details | `docs/reviews/rec-409-complete-import-design/details-small.png` | Inline editor at compact width. | Values remain legible and reachable by scroll. |
| Small-phone history | `docs/reviews/rec-409-complete-import-design/history-small.png` | Image grid retains two columns. | Accessible metadata supplies the omitted visual text. |

DEBUG launch arguments are defined in `Wander/Features/Profile/ImportWorkflowDesignMockups.swift` as `-WanderImportWorkflowMockup<Page>`.

## Validation record

- `xcodegen generate` completed and registered only the DEBUG mockup source in the app target; unrelated generated project entries were removed from the diff.
- The generic iOS Simulator build completed successfully with only pre-existing warnings.
- All 14 mockups were launched and captured. Review, matching, details, and history were checked on both the current iPhone simulator and the smaller 375×667pt simulator.
- The full test suite compiled, then the UI-test runner stalled while launching the app with repeated `no debugger version` infrastructure errors and was interrupted.
- The unit target ran and reported pre-existing contract failures in importer, map, navigation, remote-repository, metadata, and widget tests. A focused navigation failure was traced to `WanderRootView.swift` expecting a feature-flag call absent from `origin/main`; this branch does not modify that file or production import logic.

## Design review completion summary

```text
+====================================================================+
|         DESIGN PLAN REVIEW — COMPLETION SUMMARY                    |
+====================================================================+
| System Audit         | DESIGN.md present; native iPhone app UI     |
| Step 0               | 6/10; hierarchy, states, history, recovery  |
| Pass 1  (Info Arch)  | 5/10 -> 10/10 after workflow + hierarchy    |
| Pass 2  (States)     | 4/10 -> 10/10 after four-axis state model   |
| Pass 3  (Journey)    | 6/10 -> 10/10 after storyboard + horizons   |
| Pass 4  (AI Slop)    | 6/10 -> 9/10 after exception-first cleanup  |
| Pass 5  (Design Sys) | 7/10 -> 10/10 after token/component mapping |
| Pass 6  (Responsive) | 5/10 -> 9/10 after small-phone + a11y specs |
| Pass 7  (Decisions)  | 15 resolved, 0 deferred                     |
+--------------------------------------------------------------------+
| NOT in scope         | written (7 items)                           |
| What already exists  | written                                    |
| TODOS.md updates     | 0 items proposed                            |
| Approved Mockups     | 14 generated, 14 approved by direction     |
| Decisions made       | 15 added to plan                            |
| Decisions deferred   | 0                                          |
| Overall design score | 6/10 -> 9/10                               |
+====================================================================+
```

Plan is design-complete. Run the iOS design review again after production implementation for live-device visual QA.

## GSTACK REVIEW REPORT

| Runs | Status | Findings |
|---|---|---|
| Scope and system audit | CLEAR | Existing design system and importer boundaries identified; transcript scope selected. |
| Seven design passes | CLEAR | Hierarchy, states, journey, specificity, system alignment, accessibility, and decisions are specified. |
| SwiftUI render validation | CLEAR | DEBUG mockups built and rendered on current and small iPhone simulators. |
| Current-state iOS audit evidence | CLEAR | Same-day physical-device audit findings were incorporated into exception-first direction. |

VERDICT: DESIGN-COMPLETE — production implementation may begin in the sequenced branches after review approval.

NO UNRESOLVED DECISIONS
