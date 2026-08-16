# Check-in and Wanna Floating Actions

Date: 2026-08-15
Status: Approved design direction; implementation not started
Branch: `codex/checkin-cta-exploration`
Linear: creation blocked by the recme workspace free-issue limit

## Decision

Use the approved Editorial Fold direction for the Check in and Wanna system.

- A place profile stays full screen and hides the app tab bar.
- Check in and Wanna live in a floating action tray pinned above the home
  indicator. The tray remains visible while the place profile scrolls.
- Selecting either action expands an editor attached to that tray. The place
  remains the visual parent; there is no separate status-choice or generic
  action-titled save screen.
- Large confirmation actions use one shared 52–56 point terracotta capsule
  family across save, add, import, and completion surfaces.
- Compact contextual actions use labeled controls with 44-point minimum targets.
- Place names and editorial headings use the approved native serif boundary.
  Navigation, controls, metadata, body copy, fields, and CTAs stay system sans.

Design artifacts:

- `/Users/joelipshutz/.gstack/projects/joelipshutz-wander/designs/checkin-cta-system-20260815/variant-A.png`
- `/Users/joelipshutz/.gstack/projects/joelipshutz-wander/designs/checkin-cta-system-20260815/editorial-flow-01-floating-actions.png`
- `/Users/joelipshutz/.gstack/projects/joelipshutz-wander/designs/checkin-cta-system-20260815/editorial-flow-02-checkin.png`
- `/Users/joelipshutz/.gstack/projects/joelipshutz-wander/designs/checkin-cta-system-20260815/editorial-flow-03-wanna-edit.png`
- `/Users/joelipshutz/.gstack/projects/joelipshutz-wander/designs/checkin-cta-system-20260815/editorial-flow-04-entry-points.png`

The PNGs are visual direction, not pixel-perfect implementation contracts. This
document overrides any generated-image inconsistency. In particular, primary
actions are always terracotta, and the bottom app shell always has exactly four
tabs: Map, Add, Discover, and Profile.

## Why This Replaces the Current Flow

The current implementation presents `MapPlaceSaveFlowSheet` from Map, Feed,
Discover, Profile, Add, import, and other entry points. A new place can first
show a status-choice step, then a second details step. The full place profile
also carries a single scrolling primary action and a toolbar plus/edit action.

This creates three problems:

1. The user loses the place context just as they are deciding what the place
   means to them.
2. Check in and Wanna do not feel like stable place actions because their
   presentation changes by entry point and current save state.
3. Compact status choices and large final confirmations share inconsistent
   geometry, typography, color, and placement across the app.

The new contract makes the place profile the stable home for single-place
actions and reserves full-width bottom CTAs for committing a prepared action.

## CTA Families

### Contextual place actions

Use these for reversible intent selection or entry into an editor.

- Minimum height: 44 points; target 48 points at standard Dynamic Type.
- Always labeled. Icons may support the label but never replace it.
- Primary choice: terracotta fill with on-action text.
- Secondary choice: bone/raised surface, espresso label, hairline outline.
- Selected Wanna: quiet terracotta tint or outline plus a checkmark. It must not
  compete with the primary Check in action.
- The pair lives inside one floating bone tray with a hairline border and a
  restrained upward shadow. It is not a translucent glass dock.

### Confirmation actions

Use these only when a tap commits data or confirms a selected candidate.

- Height: 52–56 points.
- Full available width inside 16-point horizontal margins.
- Capsule geometry matching the approved Editorial Fold mock.
- Terracotta fill, high-contrast on-action text, system-sans semibold/bold label.
- Progress changes the label in place and locks duplicate submission; it does
  not resize or shift the layout.
- Destructive actions never sit beside or visually equal the primary CTA.

## Floating Tray Geometry

- Implement as a bottom safe-area inset in `PlaceProfileFullScreen`, not as a
  child of the profile's scrolling stack.
- Keep at least the tray height plus safe-area padding below the final scroll
  item so Place details and activity are never covered.
- Collapsed tray: two contextual actions when both are valid.
- Compact expanded tray: selector, essential fields, More options, and pinned
  confirmation CTA.
- Tall expanded tray: attached to the same bottom edge, capped below the top
  navigation/header, with its own internal scroll. The place name or header
  remains visible above it.
- Keyboard state: the confirmation CTA remains pinned above the keyboard and
  the active field scrolls into view inside the tray.
- Accessibility sizes: allow the selector to stack vertically before shrinking
  or truncating labels. Preserve 44-point targets and full VoiceOver labels.
- Motion: use a short attached expansion/collapse. Reduce Motion replaces the
  spatial expansion with a fade/size transition without spring travel.

## Place State Matrix

| Current state | Collapsed floating actions | Selecting the primary action | Secondary behavior |
|---|---|---|---|
| No current-user save | `Check in` + `Wanna` | Opens a new check-in editor | Wanna opens a new Wanna editor |
| Existing Wanna | `Check in` + selected `Wanna` | Converts the current state to checked in and creates the first visit | Selected Wanna reopens its editor |
| Existing check-in history | `Check in again` + `Edit / history` | Creates a new visit; never overwrites an old check-in | Opens the current user's visit history and edit controls |
| Shared-visit invitation | `Check in` only with inviter cue | Creates the recipient's independent visit | No Wanna choice in this invitation flow |
| Read-only/walkthrough place | Hide or use the walkthrough-owned action contract | No accidental save mutation | Preserve walkthrough navigation |

A checked-in place does not expose current Wanna as a peer state. The data model
supports a current Been/check-in status with a historical Wanna snapshot, not two
simultaneous current statuses.

## Flow Contracts

### New check-in

1. The place profile opens with Check in and Wanna floating at the bottom.
2. Tapping Check in selects it and expands the attached tray.
3. Essentials appear first: date and rating. Date defaults to today but remains
   editable through the existing date-only disclosure.
4. More options expands friends, photos, note, contextual questions/tags, and
   privacy inside the same tray.
5. The pinned confirmation CTA says `Check in`.
6. During submission it says `Checking in…` and ignores duplicate taps.
7. Success collapses the tray, refreshes the profile/history, and changes the
   floating state to `Check in again` + `Edit / history`.
8. The existing once-daily streak celebration may then take over. Same-day saves
   use the existing compact confirmation/confetti behavior.

### New Wanna

1. Tapping Wanna selects it and expands a shorter attached tray.
2. Show optional planned date and a short future-you note first.
3. More options contains place type, fit/tags, and privacy as currently allowed.
4. The confirmation CTA says `Add to Wanna`.
5. Success collapses the editor and leaves Wanna visibly selected in the
   floating bar.

### Edit existing Wanna

- Tapping the selected Wanna action reopens the attached editor with planned
  date, note, tags, cuisine/type, and visibility restored.
- The CTA says `Update Wanna`.
- `Remove from Wanna` lives inside More options as a quiet destructive action
  and requires the existing confirmation.
- Switching the selector to Check in converts through the existing
  Wanna-to-first-check-in data contract. The historical Wanna date remains in
  history; the current state becomes checked in.

### Repeat check-in

- The collapsed primary action says `Check in again`.
- A repeat starts a fresh `LocalPlaceVisit`; it never edits the prior visit.
- The latest rating may be suggested, matching current behavior.
- Note, question/tag answers, companions, and photos start blank for the new
  visit. Cuisine/place classification may remain inherited where the existing
  contract already does so.

### Edit or delete a check-in

- `Edit / history` enters the current user's activity section and exposes the
  existing visit ticket controls.
- Editing a ticket opens the same attached editor grammar with that visit's
  date, rating, note, tags, companions, and photos.
- `Update check-in` is the large confirmation CTA.
- `Delete check-in` remains inside the edit tray, confirms photo deletion, and
  follows the existing last-visit rule: restore historical Wanna when present,
  otherwise unsave the place.

## Entry-Point Matrix

| Entry point | Destination | Status selection | Confirmation CTA |
|---|---|---|---|
| Map pin/search result | Full-screen place profile | Floating profile actions | Attached `Check in` / `Add to Wanna` |
| Feed place | Same full-screen place profile | Same floating actions | Same attached confirmation |
| Discover place | Same full-screen place profile | Same floating actions | Same attached confirmation |
| Profile/list collection place | Same full-screen place profile | Same floating actions; activity deep links can start at history | Same attached confirmation |
| Add current location/manual/link/photo, single candidate | Candidate confirmation first, then place profile | Floating actions after `Use this place` | `Use this place`, then attached save CTA |
| Import, one new candidate | Inline review card or candidate confirmation, then shared editor grammar | Labeled inline Check In/Wanna | `Add as Wanna`, `Check in`, or count-aware commit |
| Import, multiple candidates | Batch review remains the parent surface | Per-row labeled Check In/Wanna; bulk default may remain | `Add N places` / `Add N of T places` |
| Shared visit invitation | Full-screen place profile with inviter cue | Check-in-only attached editor | `Check in` |
| Existing activity ticket | Full-screen place profile starting at activity | Edit selected visit | `Update check-in` |

Feed and list-related surfaces are entry points, not new bottom tabs. The app
shell remains Map, Add, Discover, Profile.

## System States

### Draft and dismissal

- Any entered field persists through the existing local draft mechanism.
- Collapsing the tray does not silently discard a dirty form. Keep the draft and
  show a compact `Draft saved`/restore affordance on return.
- A restored draft reopens the correct status and expansion level.

### Signed out

- Preserve the current local-first contract: the save completes locally.
- Prompt for sign-in only when sync is needed; do not erase or reset the tray.
- After authentication, retry the same durable save identity rather than
  creating another check-in.

### Offline or sync failure

- A successful local write collapses the tray and updates the profile
  immediately, with a compact `Saved offline. We'll sync later.` result.
- Remote retry remains background work using the same save/visit identity.
- A failure before the local write leaves the tray open, keeps all fields, shows
  one inline error directly above the CTA, and changes the action to `Retry`.

### Photos and shared invites

- A failed photo upload does not fail the check-in; the saved visit shows the
  existing photo retry state.
- A failed shared-visit invitation does not fail the check-in; the invite outbox
  retries independently.

## Typography Contract

- Place names: `WanderTypography.editorialDisplay` or the existing size-appropriate
  editorial token.
- Editorial section headings: existing semantic editorial section tokens.
- Control labels, status selectors, confirmation CTAs, metadata, timestamps,
  fields, filters, and navigation: system sans semantic tokens.
- Avoid new raw `.black` weights for ordinary body or control hierarchy. Use
  weight, size, color, and spacing only where the semantic token calls for it.
- Long place names wrap to two or three lines before scaling. Floating action
  labels never shrink below legibility; they stack at accessibility sizes.

## Implementation Shape

The implementation should extract the reusable form/controller from
`MapPlaceSaveFlowSheet` rather than duplicate its state and persistence logic.

Suggested component boundaries:

- `PlaceProfileFloatingActions`: collapsed state and state-aware action labels.
- `PlaceSaveAttachedTray`: presentation shell, safe-area/keyboard behavior, and
  compact/tall expansion.
- `PlaceSaveEditorContent`: reusable status-specific form content backed by the
  existing save context, draft update, submission, and removal logic.
- `WanderConfirmationButton`: the shared large bottom confirmation family,
  replacing visual one-offs while retaining semantic labels and loading states.
- `WanderContextualAction`: the shared 44-point labeled selector family.

Likely high-conflict files include:

- `Wander/Features/Map/PlaceProfileMapSurface.swift`
- `Wander/Features/Map/MapScreen.swift`
- `Wander/Features/Add/AddScreen.swift`
- `Wander/Features/Feed/FeedScreen.swift`
- `Wander/Features/Discover/DiscoverScreen.swift`
- `Wander/Features/Profile/ProfileScreen.swift`
- `Wander/Features/Profile/ProfileImportViews.swift`
- `Wander/Features/Lists/ListsScreen.swift`
- `Wander/DesignSystem/WanderComponents.swift`
- `Wander/DesignSystem/WanderTheme.swift`

Do not begin production edits across these files without rebasing the isolated
worktree onto current `origin/main` and rechecking active worktrees/log entries.

## Validation Contract

### Functional

- Every single-place entry point opens one place-profile action contract.
- No new single-place path shows the old standalone status-choice step.
- New Wanna, edit Wanna, Wanna-to-check-in, first check-in, repeat check-in,
  edit visit, delete visit, shared invite, draft restore, auth, and offline retry
  preserve their existing data semantics.
- Rapid taps create at most one submission.
- The first and every repeat check-in remain distinct visit records.

### Visual and interaction

- Capture the top and deep-scroll place-profile states on the current iPhone
  target and one smaller phone.
- Verify collapsed, compact expanded, tall expanded, keyboard, loading, error,
  offline success, and post-save states.
- Confirm the tab bar is hidden only inside the place profile; the four-tab app
  shell remains unchanged elsewhere.
- Confirm final scroll content is never covered by the floating tray.
- Verify dark text contrast, 44-point targets, VoiceOver order/labels, Reduce
  Motion, and accessibility Dynamic Type with stacked actions.

### Regression coverage

- Update navigation/source-contract tests that currently require
  `MapPlaceSaveFlowSheet` at each entry point.
- Add pure tests for the floating action state matrix and CTA labels.
- Add tests for tray restoration from each draft step/status.
- Preserve existing store, sync, import, check-in date, rating, photo, shared
  visit, historical Wanna, and last-check-in deletion tests.
- Run the full iPhone 16 Plus / iOS 18.6 test suite and visual QA on a smaller
  simulator before implementation is ready for review.

## Explicit Non-Goals

- No new tab or navigation model.
- No live-location check-in or proximity broadcasting.
- No new data model for simultaneous current Been and Wanna states.
- No backend/RLS/RPC change unless implementation uncovers a real contract gap.
- No redesign of ticket history, streak celebration, ratings semantics, or
  import extraction.
- No generic global bottom dock outside the place/save context.
