# REC-80 Rating Editing For Multiple Visits

Date: 2026-07-09
Status: Spec + engineering review drafted, implementation not started
Branch reviewed: `codex/rec-80-rating-edit-plan`
Linear: `REC-80`
Reviewer: Codex via `/plan-eng-review` and attempted `/ios-design-review`

## Goal

Rework rating editing so a person can save/visit the same place more than once and edit the rating for each visit independently. The current "edit this place" flow edits one `LocalUserPlace.ratingScore`, so the latest edit overwrites the user's only rating for that place.

## Recommendation

Add explicit visit records as children of the saved place:

```text
public.user_places
  one row per user + place
  status, visibility, current note/category metadata, aggregate own rating
          |
          | 1:N
          v
public.place_visits
  one row per actual visit/memory
  visited_at, rating_score, note, visibility, source_type, deleted_at
          |
          | 1:N
          v
public.place_visit_attributes
  visit-scoped tags, labels, answers, photo references later
```

Keep `user_places` as the "saved place shell" and move per-visit rating/note/tags into `place_visits`. Do not drop `unique (user_id, place_id)` from `user_places` in this pass. That uniqueness keeps map grouping, list membership, collaborator saves, and sync semantics stable while visits become the repeatable memory object.

## Source Evidence

- `supabase/migrations/20260602131500_m3_foundation.sql:104` creates `public.user_places`.
- `supabase/migrations/20260602131500_m3_foundation.sql:122` has `unique (user_id, place_id)`.
- `supabase/migrations/20260703003229_half_step_rating_scores.sql:218` upserts `app.save_own_place` on `(user_id, place_id)`.
- `Wander/Services/WanderLocalStore.swift:1372` updates an existing local save when the current user and place already match.
- `Wander/Features/Map/MapScreen.swift:2349` seeds edit flow from one `visiblePlace.userPlace.ratingScore`.
- `Wander/Features/Map/MapScreen.swift:2697` renders one `PlaceRatingSlider` in the generic details/edit sheet.
- `Wander/Features/Map/MapScreen.swift:4870` already displays per-activity-card rating text, but the activity entry still reads from `userPlace.ratingScore`.
- `Wander/Features/Map/PlaceActivityMockups.swift:290` already sketches the desired "add a visit" editor.

## Step 0 Scope Challenge

What already exists:

- `PlaceRating` already normalizes 1...5 half-step scores and formats display.
- `LocalUserPlace` already carries `visitedAt`, `ratingScore`, `recommendedScore`, and `recommendedCount`.
- `PlaceActivitySection` already has "ALL" and "MY VISITS" sections, activity cards, per-entry ratings, photo affordances, and empty states.
- `PlaceActivityMockups` already shows the intended "add visit" flow and "Existing save - new visit" copy.
- `save_own_place` already validates half-step ratings and syncs the saved-place shell.
- `PlaceProfilePresenter.ownRating` already averages multiple own scores if multiple `PlaceSaveSummary` rows exist.

Minimum complete implementation:

1. Add local `LocalPlaceVisit` and `LocalPlaceVisitAttribute` models plus persistence.
2. Add Supabase `place_visits` and `place_visit_attributes` tables/RLS/RPCs.
3. Create `save_place_visit` and `delete_place_visit` RPCs without changing `save_own_place` uniqueness.
4. Update Map place profile activity to list/edit visits, not just saved-place rows.
5. Remove the rating slider from generic "edit this place" after the place already has at least one visit.
6. Keep first-time "been" save fast by creating the saved-place shell and first visit in one user action.
7. Update rating aggregates to use visit rows for current-user and trusted recommendations.
8. Add SQL, store, repository, presentation, and UI-adjacent tests.

Scope smell:

- This will touch more than eight files and likely add two model classes plus repository DTO/RPC code. The breadth is justified because the current data model cannot represent the product requirement.

Search check:

- Search was not available from this sandbox for current external best practices. Proceeding with in-distribution SwiftUI/Supabase knowledge only. This is a Layer 1, boring-by-default design: use ordinary child tables and RPCs, not an event-sourcing or aggregate-cache system.

TODOS cross-reference:

- `TODOS.md` already says map edit should support saved-place edit/details. REC-80 refines that TODO: generic place edit should remain for place-level metadata, while visit edit owns rating.

Distribution check:

- No new artifact type. Normal app/TestFlight and Supabase migration workflow applies.

## Architecture Review

### Finding 1

`[P1] (confidence: 9/10) supabase/migrations/20260602131500_m3_foundation.sql:122 — Multiple visits cannot be modeled as multiple user_places rows without dropping the unique user/place contract.`

Motivating line:

```sql
unique (user_id, place_id)
```

Recommendation: add child visit records and keep `user_places` unique. This matches the product distinction between "this place is on my map" and "I went here on Tuesday and rated that visit."

Tradeoff:

- Child visits require new models/RPCs, but the blast radius is bounded.
- Dropping `unique (user_id, place_id)` would ripple through grouping, lists, remove-save behavior, sync, profile stats, and visible-place RPCs.

Decision:

```text
DO: user_places = saved place shell
DO: place_visits = repeatable visit memories
DON'T: turn every visit into a separate user_places row
```

### Finding 2

`[P1] (confidence: 9/10) Wander/Services/WanderLocalStore.swift:1372 — Local save currently overwrites the one existing current-user row.`

Motivating lines:

```swift
if let existing = userPlaces.first(where: { $0.userID == currentUser.id && $0.placeID == place.id && $0.deletedAt == nil }) {
    existing.statusRaw = status.rawValue
    existing.ratingScore = savedRatingScore
```

Recommendation: keep this path for saved-place shell edits, but introduce `saveVisit(...)` for repeat visits. First-time "been" save should call both shell save and first-visit creation.

Tradeoff:

- Two write paths are more code than changing one function.
- They prevent future confusion between "edit map save" and "edit visit memory."

### Finding 3

`[P2] (confidence: 8/10) Wander/Features/Map/MapScreen.swift:2697 — The generic edit sheet currently owns the only rating slider.`

Motivating lines:

```swift
if selectedStatus == .been {
    PlaceRatingSlider(score: $selectedRatingScore)
}
```

Recommendation: move rating into a visit editor for existing saved places. On first "save as been", keep a rating slider because that action is creating the first visit.

Tradeoff:

- Slightly more UI state, but the copy becomes honest: "edit this place" is place-level, "edit visit" is memory-level.

## Code Quality Review

### Finding 4

`[P2] (confidence: 8/10) Wander/Features/Map/MapScreen.swift:4820 — Place activity already acts like visits, but it is backed by saved-place rows.`

Motivating lines:

```swift
case myVisits
...
var ratingText: String? {
    guard userPlace.status == .been, let ratingScore = userPlace.ratingScore else {
```

Recommendation: extract visit presentation into a small `PlaceVisitSummary` model and have `PlaceActivityEntry` consume visits. Keep `PlaceSaveSummary` for social saved-place ownership and grouping.

Tradeoff:

- More explicit types now.
- Less accidental reuse of `LocalUserPlace` as both save shell and visit.

### Finding 5

`[P2] (confidence: 8/10) Wander/Models/PlaceProfilePresentation.swift:104 — ownRating already averages multiple own scores if the caller supplies multiple summaries.`

Motivating lines:

```swift
let ownScores = saves
    .filter {
        $0.visiblePlace.owner.id == currentUserID
            && $0.visiblePlace.userPlace.status == .been
    }
    .compactMap(\.visiblePlace.userPlace.ratingScore)
```

Recommendation: preserve that behavior but change the input source from saved rows to visit rows for own ratings. This keeps display semantics stable while making the data source correct.

Tradeoff:

- The presenter may need a new overload or input field for visits.
- Avoids rewriting the rating strip UI.

## Test Review

Test framework: XCTest via `WanderTests`, plus pgTAP SQL tests under `supabase/tests`.

```text
CODE PATHS                                                    USER FLOWS
[+] Supabase schema/RLS                                       [+] First-time been save
  ├── [GAP] create place_visits table + FK to user_places        ├── [GAP] creates shell + first visit
  ├── [GAP] RLS owner can CRUD own visits                        ├── [GAP] rating defaults to 3 then persists
  ├── [GAP] followers can read visible visits only               └── [GAP] place appears once on map
  ├── [GAP] delete saved place tombstones/deletes visits
  └── [GAP] save_own_place security posture unchanged          [+] Existing saved place
                                                                  ├── [GAP] "Edit this place" has no visit rating slider
[+] Swift models/persistence                                      ├── [GAP] "Add visit" creates second independent rating
  ├── [GAP] LocalPlaceVisit encodes/decodes                       ├── [GAP] activity shows two own visit cards
  ├── [GAP] LocalPlaceVisitAttribute encodes/decodes              ├── [GAP] editing first visit does not change second
  ├── [GAP] saveVisit creates new row                             └── [GAP] removing a visit updates averages
  ├── [GAP] updateVisit edits only one row
  └── [GAP] removeSave handles associated visits                [+] Social/trusted place
                                                                  ├── [GAP] trusted aggregate uses visit rows
[+] Remote DTO/repositories                                       └── [GAP] friend's multiple visits do not make duplicate map pins
  ├── [GAP] encode save_place_visit payload
  ├── [GAP] decode visit list for visible/profile place
  ├── [GAP] tolerate older server with no visits during rollout
  └── [GAP] direct sync marks pending visit errors visibly

COVERAGE: 0/24 new paths tested, because implementation has not started.
QUALITY TARGET: every path above should land with behavior + edge + error coverage.
```

Required tests:

- `supabase/tests/place_visits.sql`
  - `place_visits` security metadata, owner CRUD, visible-read policy, hidden/private visit exclusion.
  - `save_place_visit` rejects non-half-step ratings and non-owned user_place IDs.
  - deleting/removing a saved place hides or tombstones associated visits.
- `supabase/tests/visible_place_visits.sql`
  - visible/profile RPCs return one map saved-place row but include visit summaries.
  - recommended aggregates count visible `been` visits, not `wanna_go` shells.
- `WanderTests/WanderStoreTests.swift`
  - first `been` save creates one visit.
  - second visit for same place creates a second visit and does not overwrite the first.
  - editing one visit changes only that visit.
  - deleting a saved place clears visit rows/attributes locally.
  - offline visit save becomes pending and syncs later.
- `WanderTests/RemoteRepositoryTests.swift`
  - encode/decode `save_place_visit`, `delete_place_visit`, and visible place visit arrays.
  - old visible-place payloads with no visit array still decode during rollout.
- `WanderTests/PlaceProfilePresentationTests.swift`
  - own rating averages two visits.
  - trusted rating averages trusted visible visits.
  - no visit ratings hides the rating strip cleanly.
- `WanderTests/NavigationContractTests.swift` or new UI-adjacent tests
  - first save shows rating slider.
  - existing saved place routes rating changes through "Add/Edit visit", not generic place edit.

## Performance Review

### Finding 6

`[P2] (confidence: 8/10) supabase/migrations/20260703003229_half_step_rating_scores.sql:374 — current aggregate scans user_places by place_id; visits will need the same set-based pattern.`

Motivating lines:

```sql
visible_rating_rows as (
  select up.place_id, up.rating_score
  from public.user_places up
```

Recommendation: aggregate visits using one CTE over visible place IDs. Do not fetch visits one place at a time, and do not add an aggregate cache table yet.

Sketch:

```sql
visible_visit_rows as (
  select up.place_id, pv.rating_score
  from visible_rows vr
  join public.user_places up on up.id = vr.user_place_id
  join public.place_visits pv on pv.user_place_id = up.id
  where pv.deleted_at is null
    and pv.rating_score is not null
    and pv.status = 'been'
),
rating_summary as (
  select place_id,
         round(avg(rating_score)::numeric, 1)::double precision as recommended_score,
         count(*)::integer as recommended_count
  from visible_visit_rows
  group by place_id
)
```

## UX / iOS Design Review

Live `/ios-design-review` status: blocked. No `~/.gstack/ios-qa-session.json` cache exists, no `DebugBridge`/`StateServer` wiring is present in the app source, and sandboxed process inspection was not permitted. No real-device screenshots were captured.

Plan-stage design critique:

- Score: 7/10 for information architecture. The app already has `latest activity`, `MY VISITS`, and an "add a visit" mockup, so the right concept exists. It is not yet wired as the source of truth.
- Score: 6/10 for editing hierarchy. "Edit this place" and "rating" are conflated today. The fix should make rating a visit-level action.
- Score: 8/10 for iOS idiom alignment if implemented as a sheet pushed from a visit card/menu. Avoid a hidden long-press-only edit affordance.
- Score: 7/10 for touch/accessibility. Add explicit buttons: "Add visit" at the top of activity and "Edit visit" on own visit cards. Each needs 44pt minimum hit area and VoiceOver labels.

Recommended UI:

```text
Place profile
  ├── primary place action
  │   ├── unsaved: "save this place"
  │   └── saved: "edit place"
  ├── latest activity
  │   ├── [Add visit]  <-- visible only to current user when saved/been capable
  │   ├── own visit card
  │   │   ├── rating chip
  │   │   ├── note/tags/photos
  │   │   └── menu: Edit visit / Delete visit
  │   └── trusted visit cards
  └── place details
```

First-time save:

```text
Save as BEEN
  ├── place-level fields: category, visibility
  ├── first visit fields: rating, note, tags, visited_at
  └── save creates user_places shell + first place_visits row
```

Existing saved place:

```text
Edit this place
  ├── place-level fields: category, visibility/default save metadata
  └── no rating slider

Add/Edit visit
  ├── visit date
  ├── rating slider
  ├── note
  ├── tags/labels/answers
  └── photos later
```

## Failure Modes

| Path | Failure | Test | Handling/User Impact |
|---|---|---|---|
| First save | Shell saved but first visit fails remote sync | Swift + repository test | Keep visit pending; show sync status so rating is not silently lost |
| Add second visit | Existing `saveCandidate` overwrites old rating | Regression test | Route repeat visits through `saveVisit`, not `saveCandidate` |
| RPC security | User creates visit for another user's save | pgTAP test | `save_place_visit` derives owner from `app.current_user_id()` and rejects non-owned shell |
| Visibility | Private visit leaks into trusted aggregate | pgTAP visibility test | Visit visibility/RLS filters feed aggregate CTE |
| Delete saved place | Orphan visits still appear in activity | Store + SQL test | Tombstone/delete visits with parent save |
| Decode rollout | Old server returns no `visits` array | Remote decode test | Treat missing visits as empty and keep existing rating fallback temporarily |
| UI edit | User cannot find where to edit rating | UI-adjacent/manual QA | Add visible "Add visit" and own-card "Edit visit" controls |

Critical silent gaps: second visit overwrite, cross-user visit creation, private visit leakage, and orphan visit display.

## NOT In Scope

- Provider/Yelp/Google ratings.
- Weighted/Bayesian ranking or confidence intervals.
- Full photo backend/storage for visit photos, unless already shipped by another issue.
- Removing saved-place shell rating fields immediately. Keep temporary compatibility until rollout is complete.
- Reworking Lists or list collaborator semantics except to ensure a place still appears once.
- Public web/deep-link place pages.

## Worktree Parallelization

Dependency table:

| Step | Modules touched | Depends on |
|---|---|---|
| Schema/RLS/RPC | `supabase/migrations`, `supabase/tests` | — |
| Swift local models/persistence | `Wander/Models`, `Wander/Services`, `WanderTests` | schema contract |
| Remote DTO/repository | `Wander/Services/Remote`, `WanderTests` | schema contract |
| Map/profile visit UI | `Wander/Features/Map`, `Wander/DesignSystem`, `WanderTests` | local models |
| Presentation/aggregation semantics | `Wander/Models`, `Wander/Features/Profile`, `Wander/Features/Discover`, `WanderTests` | local/remote models |

Parallel lanes:

- Lane A: Schema/RLS/RPC.
- Lane B: Swift local models/persistence and remote DTOs after schema shape is named.
- Lane C: Map/profile visit UI after local models exist.
- Lane D: Presentation/aggregation semantics after visit summaries exist.

Execution order: start A. Once table/RPC names are stable, run B. Then C and D can proceed, but avoid parallel edits to `Wander/Features/Map/MapScreen.swift`.

Conflict flags:

- `MapScreen.swift` is high-conflict and should stay in one lane.
- `WanderLocalStore.swift` is high-conflict and should stay in one lane.
- Supabase migrations are high-conflict and need a single owner.

## Implementation Tasks

- [ ] **T1 (P1, human: ~4h / CC: ~45min)** — Supabase — Add `place_visits` schema, RLS, and RPCs.
  - Surfaced by: Architecture Finding 1.
  - Files: `supabase/migrations/*`, `supabase/tests/place_visits.sql`, `supabase/tests/visible_place_visits.sql`.
  - Verify: `supabase test db` or hosted metadata/smoke checks if Docker is unavailable.

- [ ] **T2 (P1, human: ~3h / CC: ~35min)** — Store — Add local visit models, persistence, and `saveVisit`/`updateVisit`/`deleteVisit`.
  - Surfaced by: Architecture Finding 2.
  - Files: `Wander/Models/LocalModels.swift`, `Wander/Services/WanderLocalStore.swift`, `Wander/Services/WanderStorePersistence.swift`, `WanderTests/WanderStoreTests.swift`.
  - Verify: focused `WanderStoreTests` for multi-visit save/edit/delete/persist.

- [ ] **T3 (P1, human: ~2h / CC: ~25min)** — Remote sync — Encode/decode visit RPC payloads and rollout-safe visible-place responses.
  - Surfaced by: Test Review.
  - Files: `Wander/Services/RepositoryProtocols.swift`, `Wander/Services/Remote/SupabaseDTOs.swift`, `Wander/Services/Remote/SupabaseRepositories.swift`, `WanderTests/RemoteRepositoryTests.swift`.
  - Verify: focused remote repository tests.

- [ ] **T4 (P2, human: ~3h / CC: ~35min)** — Map UI — Split generic place edit from add/edit visit flows.
  - Surfaced by: Architecture Finding 3 and iOS design review.
  - Files: `Wander/Features/Map/MapScreen.swift`, `Wander/Features/Map/PlaceProfileMapSurface.swift`, optional extracted visit editor file.
  - Verify: UI-adjacent tests plus simulator screenshot QA on current iPhone and smaller phone.

- [ ] **T5 (P2, human: ~2h / CC: ~20min)** — Presentation — Drive own/trusted ratings from visit rows and keep map/list grouping one-place-per-person.
  - Surfaced by: Code Quality Finding 5 and Performance Finding 6.
  - Files: `Wander/Models/PlaceProfilePresentation.swift`, `Wander/Services/DiscoverModels.swift`, `WanderTests/PlaceProfilePresentationTests.swift`, `WanderTests/MapHitTestingTests.swift`.
  - Verify: focused presenter/grouping tests.

## Completion Summary

- Step 0: Scope Challenge — complete child-visit model recommended.
- Architecture Review: 3 issues found.
- Code Quality Review: 2 issues found.
- Test Review: diagram produced, 24 gaps identified.
- Performance Review: 1 issue found.
- NOT in scope: written.
- What already exists: written.
- TODOS.md updates: 0 proposed; REC-80 itself tracks the work.
- Failure modes: 4 critical silent gaps flagged.
- Outside voice: skipped.
- Parallelization: 4 lanes, 2 parallel after schema names stabilize, `MapScreen.swift` sequential.
- Lake Score: 6/6 recommendations choose the complete option.
