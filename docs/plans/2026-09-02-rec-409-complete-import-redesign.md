# REC-409 Complete Import Redesign

Status: revised SwiftUI mockups ready for review, implementation not started
Linear: REC-409  
Design branch: `codex/rec-409-complete-import-design`

## Outcome

Import becomes a fast, resumable place-capture workflow with one principle:

> Show every matched place; keep uncertainty inside the place that owns it.

Most people should see one scannable list of matched places, apply Wanna or Check In to all, adjust individual rows, optionally enrich one or two, and add them immediately. A lower-confidence place stays in that same list with its best candidate selected and its alternatives inside a `Possible matches` disclosure. Every source link also becomes a durable import report that reopens the same editable review UI from image-first history.

This branch contains the workflow decision, state contract, and DEBUG-only SwiftUI mockups. It intentionally does not change production import behavior.

## Product shape

There are two user-facing capabilities and one reliability layer:

1. Core import review: show every matched place, provide batch and row-level status controls, resolve lower-confidence identity inline, optionally add details, and add the selected places.
2. Import history: retain a report for every source link and reopen the canonical review experience with the original choices visible.
3. Optimistic completion: durably queue saves locally, release the UI immediately, and sync or recover in the background.

History is incremental on top of the core review model. Optimistic completion is shared save infrastructure and should land independently so its reliability can be reviewed separately.

## End-to-end workflow

```text
ADD TAB / SHARE EXTENSION
        |
        v
+---------------------------+
| Import places system sheet|
| source link + icon actions|
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
|  1. N places matched and ready                    |
|  2. Ready to add + master status controls         |
|  3. every matched place row                       |
|  4. inline Possible matches when applicable       |
|  5. inline optional details                       |
|  6. persistent Add N places action                |
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
IMMEDIATE RETURN TO THE EXISTING MAP SAVE EXPERIENCE
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
       -> History (Liquid Glass clock icon in the top action cluster)
       -> Help (Liquid Glass question-mark icon)
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

1. What happened: `N places matched and ready`.
2. `Ready to add` with master Wanna and Check In controls aligned to the row controls.
3. The exact primary outcome: `Add N places`.

Every matched place remains visible in one scrollable list. Lower confidence does not create another page or a separate exception section: that place row gains a `Possible matches` disclosure above `Add details`. This keeps the user oriented and prevents the importer state model from taking over the page hierarchy.

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
| No places found | Warm empty result with source context. | `Try another link`. |
| Source failed | Inline error, not a blank report. | `Retry`. |

### Place resolution outcomes

| Resolution state | Default presentation | Available action |
|---|---|---|
| Resolving | Skeleton row that retains the extracted clue; never a generic spinner-only screen. | Wait or leave. |
| Resolved, high confidence | Visible row, selected by the current master default, and included in `Add N places`. | Switch Wanna/Check In, clear both, or add details. |
| Ambiguous, 2–5 candidates | Same visible row with the best candidate selected and a collapsed `Possible matches` disclosure. | Keep the recommendation or choose one of at most four alternatives. |
| Needs a match, zero candidates | No interactive row in the launch review. The source report retains an aggregate resolver outcome for diagnostics/reprocessing, but the user is not sent into a guessing flow. | None in launch scope. |
| Already saved | Visible row using the existing personal status and details; no implicit overwrite. | Leave as-is or make an explicit status/detail change. |
| Retryable place failure | Source-level retry remains available when the whole source failed; a single zero-result place is omitted from launch review. | Retry the source when applicable. |
| Excluded | Row remains visible with both status icons off during the active review. | Re-select Wanna or Check In. |

### Save outcomes

| Outcome | User-visible treatment |
|---|---|
| Queued locally | Immediate return to the existing map save experience after the durable local write. |
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

- Keep `Possible matches` inside the relevant place card, directly above `Add details`; never create a separate exception page or top-level section.
- Show no more than five candidates: one best candidate plus four alternatives.
- The best candidate is selected by default.
- Selection is zero-or-one, never multi-select. Selecting an alternative moves the checkmark to it.
- Nonselected candidates are visually muted but remain fully tappable and VoiceOver-enabled; they must not look disabled.
- A selected recommendation counts in `Add N places`. Clearing both status icons on its parent place row removes it from the add count without removing the row.
- Candidate confidence is expressed as `Best match`, not a numeric score.
- If there is only one high-confidence match, treat it as resolved rather than manufacturing an ambiguity screen.
- The current resolver ranking remains authoritative for launch. Name match is expected to carry strong weight, but ranking-algorithm work is not part of this UI branch.

## Review and optional details

Each place row has two icon-only status choices aligned on its right edge: bookmark for `Wanna` and checked circle for `Check In`. Only one may be active, and tapping the active icon again clears both. There is no third green selection checkmark.

The `Ready to add` header repeats those two icons as master column controls. Tapping master Wanna applies Wanna to every row; tapping master Check In applies Check In to every row. The user may then override or clear any row. The master state reflects all, mixed, or neither without blocking row-level edits.

`Add details` expands the selected place inline. Only one place disclosure stays open at a time so the list remains navigable. The expanded order is:

1. Rating — always `Not rated` with no thumb or fabricated value until the first touch. After the first choice it reuses the existing liquid rating reaction and motion.
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

List membership is independent from Wanna/Check In, so valid combinations include Wanna only, Check In only, Wanna + list, and Check In + list.

The persistent CTA always names the exact operation. Never display `Add 0 places`. If nothing is selected, the primary action becomes `Keep for later`.

## Import history and report

### History semantics

- Every source link produces one report.
- Starting another import replaces the `current import` pointer used by the main import flow; it never deletes older reports.
- Reports remain until the user deletes them or deletes the account.
- The history grid is two-column and image-only. There are no titles outside the image. Any words visible in a tile are part of the source post thumbnail itself.
- A small provider glyph identifies Instagram, Google Maps, TikTok, or another supported source.
- A small attention-count badge appears only when unresolved or failed items remain.
- Missing artwork uses a warm provider fallback rather than an empty gray rectangle.
- Each tile's accessibility label includes provider, date, place count, and attention count even though the visual tile has no title.

### Report behavior

Tapping a thumbnail opens the same canonical review component in report mode:

- The original source thumbnail leads the page and the original link is visible with a copy-to-clipboard control.
- Original selections, statuses, optional details, and list memberships initialize the rows.
- The rows are live editors. Switching Wanna to Check In, Check In to Wanna, or clearing both updates that specific current place save.
- List membership remains independent and editable through the same per-place details disclosure.
- Completed, unresolved, and failed rows use the same card anatomy as the active review so the two surfaces cannot drift.

This reuse is a design constraint: there should not be a separate bespoke history-detail UI that drifts from review.

### Empty, loading, and image failure

- Empty: warm `No imports yet` explanation with one `Import places` action.
- Loading: image-shaped skeletons preserving the two-column rhythm.
- Image failure: provider fallback plus the same accessible metadata.
- Partial: loaded tiles remain interactive while remaining thumbnails resolve.

## Completion, notification, and reminder

There are three completion routes into the same report:

1. While in the app: a top overlay banner appears immediately below any existing header, search, or filter controls with `Review` and an explicit 44pt close button. When no chrome exists, it sits as high as the safe area allows. It persists until dismissed or opened.
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
     -> success: return immediately to the existing map save experience
        -> background sync
           -> success: silent completion
           -> offline: neutral saved-on-phone notice
           -> repeated/terminal failure: durable warning + Retry
```

This applies to all multi-place saves, not only imported packages. Optimistic completion adds no new dedicated success card or screen; the user sees the same successful place-save feel already used by rec.me, only without server latency. Automatic retry should normally occur within seconds, but the durable queue must survive force quit, app restart, and no-network conditions. Retrying must be idempotent.

## Interaction state coverage

| Surface | Loading | Empty | Error | Success | Partial |
|---|---|---|---|---|---|
| Import entry | Clipboard/source validation appears inline without blocking History. | Blank source field with provider examples. | Invalid link stays editable with a provider-specific reason. | Start import becomes available. | Latest report remains reachable while a new link is entered. |
| Source processing | Artwork/fallback, provider, and progress; user may leave. | `No places found` plus `Try another link`. | Preserved link with Retry. | Completion route announces ready count. | Found places remain visible beside scan warning. |
| Canonical review | Per-place clue skeletons, not a page spinner. | `Nothing selected yet`; all rows remain available. | Source-level Retry when the source failed; matched rows remain addable. | Outcome headline, selected count, exact CTA. | Every matched row stays visible; lower confidence expands in its owning card. |
| Candidate matching | Stable parent place card and candidate skeleton rows. | Zero-result places are omitted from launch review rather than forcing a guessing flow. | Retry only when the source-level extraction/resolution job failed. | Best candidate selected; alternatives muted but active. | Up to five candidates inside one place card. |
| Optional details | Row-local progress for photos/friends/lists. | Explicit values such as `Not rated`, `No note`, `No list`. | Failed subaction stays inside the expanded place. | Saved value appears in the row summary. | One detail can fail without blocking the place selection. |
| Import history | Two-column image skeletons. | Warm `No imports yet` with Import action. | Provider fallback or retry banner; report metadata survives. | Image-only report grid. | Loaded tiles remain usable while artwork resolves. |
| Import report | Source thumbnail, copy-link control, and row skeletons preserve layout. | Honest `No places found` report rather than disappearing. | Failed source or save remains retryable. | Original choices initialize live editable rows. | Status and list changes affect only the specific place. |
| Local save / sync | Only the durable local write briefly locks the CTA. | No `Add 0`; use `Keep for later`. | Local failure stays in review; terminal remote failure offers Retry for 10s+. | Immediate return to the existing map save experience. | Offline pending is neutral; successful local items remain available. |

## User journey and emotional arc

| Step | User does | Intended feeling | Design support |
|---|---|---|---|
| 1 | Pastes or shares a link. | Certain that rec.me has it. | Durable receipt, clear provider context, visible History. |
| 2 | Leaves while processing. | Unburdened. | Background work and global completion routing. |
| 3 | Opens review. | In control without hunting through importer states. | Every match is visible in one list with master and row-level status controls. |
| 4 | Encounters lower confidence. | Guided, not diverted. | Best match selected and alternatives disclosed inside that place card. |
| 5 | Adds one note or list. | In control. | Inline disclosure with no context switch or random values. |
| 6 | Adds the places. | Instant gratification. | Durable local queue and immediate return to the familiar map save state. |
| 7 | Goes offline or sync fails. | Trusting that work is safe. | Neutral offline state; explicit long-lived retry on real failure. |
| 8 | Returns weeks later. | Able to remember why these places mattered. | Image-first history, original source link, and live editable place rows. |

Time horizons:

- Five seconds: `It worked; most places are already handled.`
- Five minutes: `I can scan every result, fix one match, and enrich the places I care about without leaving the list.`
- Five years: `rec.me still remembers where this group of places came from and what I chose.`

## Visual and component decisions

Classifier: native app UI.

- Reuse the warm canvas, bone surfaces, ink text, terracotta action color, success green, 8pt spacing rhythm, and 44pt controls defined by `DESIGN.md`.
- Present import entry as a real draggable iOS system sheet with `.medium` and `.large` detents, a visible drag indicator, and the same warm map context as Add.
- Use true iOS 26 Liquid Glass for the close/help/history cluster, text field, Start import, clipboard, latest-report row, status controls, copy-link control, banners, and sticky CTA. Keep content cards opaque enough for text and imagery.
- Use one calm canvas and minimal chrome. A card represents one matched place; candidate rows and details expand inside it rather than adding nested cards or separate pages.
- Source imagery is the primary visual anchor in history; do not generate titles outside the image to compensate for weak thumbnails.
- Avoid dashboard mosaics, decorative gradients, ornamental icon circles, thick borders, and stacked explanatory cards.
- Status controls use outline icons when inactive and filled icons plus terracotta tint/border when active, so selection is not communicated by color alone.
- The master controls and every row use the same two fixed-width icon columns on the right edge.
- Primary actions use the existing dark espresso treatment; terracotta remains the selection/action accent.

AI-slop check:

| Check | Result |
|---|---|
| Product unmistakable on first screen | Yes — source artwork, provider, place counts, and rec.me vocabulary. |
| One strong visual anchor | Yes — source artwork or resolution outcome. |
| Understandable by headings alone | Yes — matched count, Ready to add, Possible matches, Add details. |
| One job per section | Yes. |
| Cards necessary | Yes, only for interactive place/source objects. |
| Motion improves hierarchy | Yes, limited to resolution collapse and completion. |
| Premium without shadows | Yes; hierarchy is typography, imagery, spacing, and state. |

## Responsive, accessibility, and motion

### Viewports

- Small iPhone: one-column review; entry headline and provider list wrap inside the system sheet; candidate address wraps after the meaningful street segment; persistent CTA respects the home indicator. History remains two-column because tile text comes from the visual source thumbnail.
- Current iPhone: review uses 16pt side insets and the content order shown in the approved renders.
- Wider iPhone / iPad compatibility: center review at a 620pt maximum content width and history at a 760pt maximum width. Do not stretch the phone composition into a dashboard or invent a side panel in this scope.
- Keyboard: focused fields remain visible above the keyboard; the persistent CTA moves with the keyboard only when its action remains valid.

### Accessibility

- Minimum tap target is 44×44pt, including status icons, disclosure rows, close buttons, and history tiles.
- Dynamic Type must be verified at default, Extra Extra Large, and an accessibility size. Editorial headings wrap; no essential row has a fixed text height.
- VoiceOver groups each place/candidate row and announces place name, supporting location, `Best match` when applicable, and selected state.
- History tiles announce provider, date, number of places, and unresolved count.
- Do not communicate disabled, warning, selected, or failed state with opacity/color alone.
- Source thumbnails are decorative when equivalent metadata is announced; meaningful user photos receive their existing place-photo descriptions.
- Full Keyboard Access follows visual order: close/back, headline, master controls, each place's Wanna/Check In controls, Possible matches, details, and primary CTA.

### Motion

- Possible matches and Add details expand in one approximately 200ms movement; opening details closes any other details disclosure.
- Master status changes update visible rows together without a staggered cascade.
- Successful optimistic completion uses the existing place-save feedback and does not add a second animation layer.
- Reduce Motion replaces disclosure movement with an instant state change; optimistic completion adds no new motion.

## Copy contract

| Situation | Headline / action | Supporting copy |
|---|---|---|
| Review | `13 places matched and ready` | `Instagram · 11 new · 2 already saved` |
| Matched section | `Ready to add` | Selected count plus icon-only `Apply to all` controls. |
| Lower confidence | `Possible matches` | Candidate count; `Best match` appears only on the first recommendation. |
| All selected | `Add 13 places` | No caption. |
| One cleared | `Add 12 places` | No extra warning; the cleared row remains visibly unselected. |
| Nothing selected | `Keep for later` | No fake add count. |
| In-app ready | `Your import is ready` / `Review` | `13 places matched` |
| Immediate completion | No new dedicated copy | Return to the existing map save experience. |
| Offline | `Saved on this phone` | `13 places will sync when you’re back online.` |
| Terminal failure | `3 places still need saving` / `Retry` | `Your link and choices are safe.` |
| History empty | `No imports yet` / `Import places` | `Posts and shared lists you import will stay here.` |

## Analytics contract for implementation

Instrument transitions in the store/domain layer where practical, not from transient view appearance. The implementation must update `docs/analytics.md`, contract/privacy tests, and the managed dashboard script if a metric changes.

Required measurements:

- import captured, processing completed, and review opened;
- resolution-state counts using aggregate counts only;
- suggested candidate kept or alternative selected; master and row status changes;
- optional details expanded and detail type used;
- local save queued, offline pending, sync completed, and retry tapped;
- history opened, report opened, and completion/reminder route used.

Allowed properties are provider enum, aggregate counts, resolution enum, route enum, elapsed-time bucket, retry count bucket, and build. Never emit source URLs, raw search text, place names, notes, list names, coordinates, friend identifiers, notification copy, APNs identifiers, or private payloads. Successful place adds should continue to emit the existing engagement action from the domain transition when applicable.

## Design decisions

1. Use `show every matched place; keep uncertainty inside the place that owns it` as the governing review model.
2. Separate batch, source, place-resolution, and save-outcome states.
3. Present import entry in a draggable `.medium`/`.large` system sheet and restore icon-based help/history actions.
4. Show every matched place in one `Ready to add` list; remove the collapsed ready receipt and separate exception section.
5. Give the section and every row the same Wanna/Check In icon columns; allow exactly one or neither per row.
6. Make the master controls apply a status to all while preserving later row overrides and clear states.
7. Keep `Possible matches` inside the owning place card, cap candidates at five, and preselect the best candidate.
8. Omit zero-result places from the launch review instead of forcing manual search; preserve aggregate resolver diagnostics privately.
9. Never overwrite an existing place's status, rating, or note because it reappears in an import without an explicit user edit.
10. Expand optional details inline, one place at a time, and keep Rating visibly `Not rated` until the first touch.
11. Put list membership inside per-place details and keep it independent from Wanna/Check In.
12. Make the CTA state the exact count and replace `Add 0` with `Keep for later`.
13. Retain one historical report per source link until deletion; a new import changes only the current pointer.
14. Make history a two-column source-thumbnail grid with accurate provider and attention badges but no labels outside the image.
15. Reuse the canonical place cards for report mode, expose a copy-link control, and make status/list edits update only that current place save.
16. Route in-app banners, OS notifications, and one 24-hour reminder to the same report; place banners below existing chrome.
17. Declare local durable persistence, not server completion, as the gate for optimistic UI success, with no new success surface.
18. Treat offline as neutral pending work and terminal failure as an explicit 10-second-plus retry surface.

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

Land the separated state model, one-list review composition, master and row status controls, inline candidate disclosure, duplicate treatment, exact CTA behavior, inline details, and deep-linkable report route contract. Keep the report persistence interface forward-compatible with history.

### Branch 2 — optimistic save reliability (coordinate with REC-341)

Land the durable local save-intent queue, idempotent background sync, app-restart recovery, neutral offline treatment, terminal retry surface, and migration of bulk save paths. This should be independently testable because a false success claim risks user data.

### Branch 3 — history and completion routing (new incremental issue)

Land persisted report state, source artwork lifecycle, current-report pointer, Import sheet and Settings entry points, image grid, canonical live-edit report mode, in-app completion banner, OS deep link, and single reminder. Stack this after the canonical review contract is stable.

## Implementation Tasks

Synthesized from this review's findings. Each task derives from a specific finding above. Run with Codex; checkbox as you ship.

- [ ] **T1 (P1, human: ~1.5d / Codex: ~3h)** — Import domain — Separate batch, source, resolution, and save states
  - Surfaced by: Interaction State Coverage — the current status surface conflates resolution and persistence outcomes.
  - Files: `Wander/Models/PlaceImportModels.swift`, `Wander/Services/PlaceImportStore.swift`, `WanderTests/PlaceImportTests.swift`
  - Verify: focused import model/store tests plus state-transition contract tests.
- [ ] **T2 (P1, human: ~2d / Codex: ~4h)** — Canonical review — Build the one-list review with master and row status columns
  - Surfaced by: Information Architecture — every match must remain scannable without exposing a separate importer-state dashboard.
  - Files: `Wander/Features/Profile/ProfileImportViews.swift`, import view-model/store files, UI tests
  - Verify: all-matched, mixed-confidence, duplicate, row override, and zero-selection screenshots on current and small iPhones.
- [ ] **T3 (P1, human: ~1d / Codex: ~3h)** — Place matching — Put zero-or-one candidate selection inside the parent place card
  - Surfaced by: Interaction State Coverage — lower confidence must not send the user to a separate review page.
  - Files: import review views, resolver adapter/view model, `WanderTests/PlaceImportTests.swift`
  - Verify: best preselection, alternative selection, five-result cap, zero-result omission, and accessibility-state tests.
- [ ] **T4 (P2, human: ~1.5d / Codex: ~4h)** — Inline enrichment — Compose optional place details into one disclosure
  - Surfaced by: User Journey — people need to add a note, list, rating, or visit context without leaving the batch.
  - Files: import review views and existing save-editor/list/friend/photo components
  - Verify: no rating thumb/value before first touch, existing liquid reaction after selection, correct Check In date default, one disclosure open, and draft retention after scroll/relaunch.
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
  - Verify: two entry points, empty/loading/image-failure/partial states, source-link copy, live row edits, deletion, and multiple imports.
- [ ] **T8 (P2, human: ~1d / Codex: ~3h)** — Accessibility and analytics — Complete the nonvisual contract
  - Surfaced by: Responsive & Accessibility and Design System Alignment — state must remain usable without color, standard text size, or private analytics payloads.
  - Files: import accessibility identifiers/labels, analytics contracts, `docs/analytics.md`, managed dashboard script
  - Verify: VoiceOver, Full Keyboard Access, Reduce Motion, accessibility Dynamic Type, `npm --prefix scripts run analytics:check`, and privacy tests.

## Review Mockups

| Screen / state | Mockup path | Direction | Constraint |
|---|---|---|---|
| Import entry | `docs/reviews/rec-409-complete-import-design/entry-large.png` | Real draggable iOS system sheet over the map, with Liquid Glass close/help/history, paste, start, and ready-report actions. | `.medium` and `.large` detents; source must be durable before processing. |
| All matched | `docs/reviews/rec-409-complete-import-design/ready-large.png` | One visible `Ready to add` list with aligned master and row-level status icons. | One or neither status per row; no extra green selection check. |
| Possible matches | `docs/reviews/rec-409-complete-import-design/ambiguous-large.png` | Five candidates expanded inside the McDonald's card, best selected. | No separate exception page or section. |
| Inline details | `docs/reviews/rec-409-complete-import-design/details-large.png` | Place card expands into unrated rating, note, When, category, friends, photos, lists, type, and more. | Rating has no fabricated default; one disclosure at a time. |
| History | `docs/reviews/rec-409-complete-import-design/history-large.png` | Two-column source-thumbnail grid using post/map cover imagery. | Provider and attention badges only outside source artwork. |
| Historical report | `docs/reviews/rec-409-complete-import-design/report-large.png` | Source thumbnail, copy-link control, and the same editable place cards as review. | A status/list change updates only that place save. |
| In-app ready banner | `docs/reviews/rec-409-complete-import-design/banner-large.png` | Liquid Glass overlay below existing map filters with Review and explicit close. | Dismissal does not mark report reviewed. |
| Optimistic completion | `docs/reviews/rec-409-complete-import-design/complete-large.png` | Immediate return to the existing map save experience with the saved place visible. | No new success card or blocking animation. |
| Offline pending | `docs/reviews/rec-409-complete-import-design/offline-large.png` | Neutral saved-on-phone notice. | Offline is not an error. |
| Terminal save failure | `docs/reviews/rec-409-complete-import-design/failure-large.png` | Long-lived error with Retry. | Preserve link, choices, and local drafts. |
| Small-phone import entry | `docs/reviews/rec-409-complete-import-design/entry-small.png` | System-sheet compact-height validation. | Starts at the large detent below 750pt height; remains draggable and keeps all four actions available. |
| Small-phone all matched | `docs/reviews/rec-409-complete-import-design/ready-small.png` | Compact-width one-list validation. | CTA clears home indicator; headings wrap. |
| Small-phone matches | `docs/reviews/rec-409-complete-import-design/ambiguous-small.png` | Candidate disclosure stays inside its parent row on a short viewport. | Candidate group scrolls behind fixed CTA. |
| Small-phone details | `docs/reviews/rec-409-complete-import-design/details-small.png` | Inline editor at compact width. | Values remain legible and reachable by scroll. |
| Small-phone history | `docs/reviews/rec-409-complete-import-design/history-small.png` | Image grid retains two columns. | Accessible metadata supplies the omitted visual text. |
| Small-phone report | `docs/reviews/rec-409-complete-import-design/report-small.png` | Source link and live place editors fit the compact width. | Place status icons and list summary remain legible. |

DEBUG launch arguments are defined in `Wander/Features/Profile/ImportWorkflowDesignMockups.swift` as `-WanderImportWorkflowMockup<Page>`.

## Validation record

- `xcodegen generate` completed and registered only the DEBUG mockup source in the app target; unrelated generated project entries were removed from the diff.
- The generic iOS Simulator build completed on Xcode 26.6, and native captures ran on iOS 26.5, with only pre-existing warnings.
- All 16 mockups were launched and captured. Entry, review, matching, details, history, and report were checked on both the iPhone 17 simulator running iOS 26.5 and the smaller 375×667pt simulator.
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
| Pass 4  (AI Slop)    | 6/10 -> 9/10 after native one-list cleanup  |
| Pass 5  (Design Sys) | 7/10 -> 10/10 after token/component mapping |
| Pass 6  (Responsive) | 5/10 -> 9/10 after small-phone + a11y specs |
| Pass 7  (Decisions)  | 18 resolved, 0 deferred                     |
+--------------------------------------------------------------------+
| NOT in scope         | written (7 items)                           |
| What already exists  | written                                    |
| TODOS.md updates     | 0 items proposed                            |
| Review Mockups       | 16 generated and ready for review           |
| Decisions made       | 18 added to plan                            |
| Decisions deferred   | 0                                          |
| Overall design score | 6/10 -> 9/10                               |
+====================================================================+
```

Plan is review-ready. Production implementation remains blocked until the revised direction is approved; run the iOS design review again after implementation for live-device visual QA.

## GSTACK REVIEW REPORT

| Runs | Status | Findings |
|---|---|---|
| Scope and system audit | CLEAR | Existing design system and importer boundaries identified; transcript scope selected. |
| Seven design passes | CLEAR | Hierarchy, states, journey, specificity, system alignment, accessibility, and decisions are specified. |
| SwiftUI render validation | CLEAR | DEBUG mockups built and rendered on current and small iPhone simulators. |
| Current-state iOS audit evidence | CLEAR | Same-day physical-device findings informed the baseline; the user's one-list direction supersedes the earlier exception-first recommendation. |

VERDICT: DESIGN-REVIEW-READY — production implementation has not started.

NO UNRESOLVED DECISIONS
