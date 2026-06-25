# Rating System Plan Engineering Review

Date: 2026-06-24
Status: Reviewed, ready for implementation
Branch reviewed: `main`
Reviewer: Codex via `/plan-eng-review`

## Goal

Replace the current four-bucket `rating_signal` model with a 1-5 numeric rating system, intentionally reset dummy saved-place data, and show Recommended averages on profile/place surfaces.

## Locked Decisions

1. Recommended scores only count `been` saves. `wanna_go` saves do not affect the average.
2. Add `user_places.rating_score smallint` as the active source of truth, constrained to `1...5`.
3. Wipe dummy saved-place data instead of preserving/backfilling old ratings.
4. Compute `recommended_score` and `recommended_count` in Supabase visible-place/profile RPCs.
5. Make rating a first-class save/edit field, not a generic `PlaceAttributeDraft`.
6. Add a tiny `PlaceRating` helper/model for validation and display formatting.
7. Rename pre-visit `wanna_go` excitement to `interest_signal`; do not share the rating key.
8. Use a visible-row CTE in RPC SQL to aggregate ratings by `place_id`, then join aggregates back to returned rows.
9. Preserve profiles, follows, blocks, and auth/session state; reset only saved-place data, place metadata, attributes, drafts, artifacts, and extraction jobs.
10. Add a one-time local saved-place reset marker so updating to the new TestFlight build clears stale on-device dummy places without sign-out or reinstall.

## What Already Exists

- Add and Map save flows already share category-aware questions through `AddQuestionTemplates`.
- Local `LocalUserPlace.ratingSignal` and `UserPlaceDraft.ratingSignal` carry old string ratings through local save, persistence, sync, and DTOs; these become removable compatibility surfaces rather than migration inputs.
- Supabase already has `user_places.rating_signal text` and flexible `place_attributes`.
- `visible_places_in_view` and `profile_visible_places` already return place rows used by Map, Discover, and Profile.
- `ProfileStats` already feeds the top profile stat tiles and can add a Recommended stat without a new store.

## Scope Challenge

Minimum complete implementation:

1. Schema migration and saved-place reset.
2. Swift model/DTO/repository updates.
3. Add and Map save/edit slider UI for `been` saves.
4. `interest_signal` rename for `wanna_go`.
5. Profile/place display of `recommended_score` and `recommended_count`.
6. SQL and Swift regression coverage.

This touches more than eight files, but the breadth is inherent: this is a data reset plus UI and API contract change. The reset removes historical backfill work but does not remove the need to update all active save/read/display paths.

## Data Flow

```text
-----------------+       +---------------------+       +--------------------------+
| Add/Map slider | ----> | LocalUserPlace      | ----> | save_own_place RPC       |
| 1...5, default |       | ratingScore: Int?   |       | input_user_place.rating  |
| 3 for been     |       | interestSignal attr |       | _score                   |
+-----------------+       +---------------------+       +--------------------------+
                                                             |
                                                             v
                                                      +------------------+
                                                      | user_places      |
                                                      | rating_score     |
                                                      +------------------+
                                                             |
                                                             v
                                        +----------------------------------------+
                                        | visible/profile RPC visible row CTE    |
                                        | avg(been rating_score), count(*)       |
                                        +----------------------------------------+
                                                             |
                                                             v
                                      +------------------------------------------+
                                      | Profile/place UI: "4.5 recommended"     |
                                      | hidden when no visible scores exist      |
                                      +------------------------------------------+
```

## Migration Plan

Create a new migration after `20260623120000_fix_save_own_place_rls.sql`.

1. Add nullable `rating_score smallint check (rating_score between 1 and 5)` to `public.user_places`.
2. Delete saved-place data while preserving account/social graph data:
   - `place_attributes`
   - `user_places`
   - `extraction_jobs`
   - `source_artifacts`
   - orphaned `places`
   - saved-place `sync_tombstones` if they exist
3. Keep `profiles`, `follows`, `blocks`, and profile/account metadata intact.
4. Update `app.save_own_place` and public wrapper to accept `rating_score`.
5. Update `app.visible_places_in_view`, `public.visible_places_in_view`, `app.profile_visible_places`, and `public.profile_visible_places` to return `rating_score`, `recommended_score`, and `recommended_count`.
6. Stop returning/writing `rating_signal` from active app paths unless keeping it temporarily is needed for old TestFlight compatibility before build rollout.

Deployment order:

```text
1. Deploy Supabase migration:
   - add rating_score
   - reset saved-place tables
   - update RPCs

2. Ship TestFlight build:
   - app writes rating_score
   - app one-time local reset clears stale saved-place cache

3. Testers open app:
   - stay signed in
   - follows/accounts remain
   - saved places are empty
   - new saves use rating_score
```

## Implementation Notes

- Add `PlaceRating` in the model/service layer with:
  - `static func normalized(_ score: Int?) -> Int?`
  - `static func recommendedText(score: Double, count: Int) -> String`
- Add `ratingScore: Int?` and optional aggregate fields to `LocalUserPlace` or a nearby value type used by `VisiblePlace`.
- Add a persistence reset version to `WanderStoreSnapshot`, for example `savedPlaceResetVersion`.
- Existing snapshots without the version decode as needing reset.
- On first launch after the rating reset, strip `places`, `userPlaces`, `placeAttributes`, `unresolvedDrafts`, `sourceArtifacts`, and `extractionJobs`, preserve `currentUser`, `profiles`, `follows`, `blocks`, and `defaultVisibility`, then immediately persist the clean snapshot.
- Update `UserPlaceDraft` and `SaveOwnPlaceUserPlaceParams` to send `rating_score`, not `rating_signal`.
- Remove `rating_signal` from `AddQuestionTemplates.blocks` for `been`; render the slider directly in Add/Map detail forms.
- Keep `interest_signal` as a normal `PlaceAttributeDraft` for `wanna_go` planning saves.
- Profile rows/details should show Recommended only when `recommended_count > 0`.

## Test Coverage Diagram

```text
CODE PATHS                                                   USER FLOWS
[+] Supabase migration                                       [+] Add tab save as been
  ├── [GAP] add rating_score smallint check 1...5              ├── [GAP] default slider starts at 3
  ├── [GAP] delete saved-place data only                       ├── [GAP] moving slider to 5 saves score 5
  ├── [GAP] preserve profiles/follows/blocks                   └── [GAP] score persists after relaunch
  └── [GAP] update/insert interest_signal                    [+] Map edit/save sheet
                                                                 ├── [GAP] existing rated place preloads score
[+] Swift models/local store                                    ├── [GAP] changing score updates saved row
  ├── [GAP] PlaceRating validation/display helper              └── [GAP] wanna_go uses interest_signal, no score
  ├── [GAP] LocalUserPlace.ratingScore persistence
  ├── [GAP] saveCandidate writes ratingScore                 [+] Profile place list
  ├── [GAP] draft sync sends rating_score                      ├── [GAP] one 4 + one 5 displays 4.5 recommended
  ├── [GAP] one-time local reset strips stale saves            ├── [GAP] wanna_go does not lower average
  └── [GAP] reset is not repeated after clean snapshot          └── [GAP] no score hides the score cleanly
                                                                 └── [GAP] no score hides the score cleanly
[+] Remote DTO/RPC
  ├── [GAP] decode rating_score
  ├── [GAP] encode save_own_place rating_score
  ├── [GAP] decode recommended_score/count
  └── [GAP] tolerate optional/missing aggregate fields
```

Required tests:

- `supabase/tests/rating_score_reset.sql`: saved-place tables are cleared; profiles/follows/blocks remain; orphaned places are removed.
- `supabase/tests/save_own_place.sql`: `save_own_place` accepts and persists `rating_score` with `1...5` constraint behavior.
- `supabase/tests/rls_visibility.sql` or a new aggregate test: visible/profile RPC averages only visible `been` rows.
- `WanderTests/PlaceRatingTests.swift`: validation and display formatting.
- `WanderTests/WanderStoreTests.swift`: save/update/persist `ratingScore`; `wanna_go` writes `interest_signal`; one-time local reset strips old saved-place state while preserving profiles/follows/blocks.
- `WanderTests/RemoteRepositoryTests.swift`: DTO decode/encode for `rating_score`, `recommended_score`, and `recommended_count`.
- Existing full simulator test suite before merge.

## Failure Modes

| Path | Failure | Test | Handling/User Impact |
|---|---|---|---|
| Migration | Profiles/follows accidentally deleted | Required SQL test | Explicit reset scope preserves social graph |
| Migration | Old saved rows survive server reset | Required SQL test | Delete saved-place tables in FK-safe order |
| Save RPC | Out-of-range score accepted | Required SQL test | DB check rejects; app normalizes before save |
| Local save | Slider score not persisted after relaunch | Required Swift test | Persistence record carries `ratingScore` |
| Local reset | Old device cache still shows stale places | Required Swift test | One-time reset strips local saved data and persists marker |
| Remote decode | RPC missing score crashes decode | Required Swift test | Nullable decode |
| Profile display | Average depends on client cache order | Required RPC test | Server-side aggregate per visible rows |
| UI | No-score place shows broken placeholder | Required Swift/UI-adjacent test | Hide Recommended when count is zero |

Critical silent gaps if untested: reset scope, local stale-cache reset, `wanna_go` exclusion, and RPC aggregate visibility.

## Performance

Use a CTE in each visible-place RPC:

```text
visible_rows as (...)
rating_aggregates as (
  select place_id,
         avg(rating_score)::numeric(3,2) as recommended_score,
         count(rating_score)::int as recommended_count
  from visible_rows
  where status = 'been' and rating_score is not null
  group by place_id
)
select visible_rows.*, rating_aggregates.*
from visible_rows
left join rating_aggregates using (place_id)
```

Do not use one correlated aggregate query per returned row. Do not add a materialized aggregate table yet.

## NOT In Scope

- Provider/Yelp/Google public ratings: this is first-party rec.me user recommendation data only.
- Weighted scores, Bayesian averages, confidence intervals, or ranking algorithms.
- Preserving existing dummy saved places or historical ratings.
- Deleting profiles, follows, blocks, or account/auth state.
- Realtime aggregate updates; normal refresh after save/profile/map load is enough for alpha.
- Web/deep-link place pages.

## Parallelization

Dependency table:

| Step | Modules touched | Depends on |
|---|---|---|
| Schema + RPC migration | `supabase/migrations`, `supabase/tests` | — |
| Swift model/DTO/store | `Wander/Models`, `Wander/Services`, `WanderTests` | Schema contract |
| Local saved-place reset | `Wander/Services`, `WanderTests` | Swift persistence model |
| Save UI slider | `Wander/Features/Add`, `Wander/Features/Map`, `WanderTests` | Swift model |
| Profile/place display | `Wander/Features/Profile`, `Wander/Features/Map`, `Wander/Features/Discover`, `WanderTests` | Swift model + RPC aggregate |

Parallel lanes:

- Lane A: Schema + RPC migration.
- Lane B: Swift model/DTO/store and local reset after schema contract is sketched.
- Lane C: Save UI slider after model field exists.
- Lane D: Profile/place display after aggregate fields exist.

Execution order: start Lane A first, then B. Run C and D after B. Avoid parallel edits to `MapScreen.swift`; Map save UI and place display both touch it.

## TODO Candidate

No durable TODO is required if implementation removes active `rating_signal` usage now. If implementation keeps any temporary compatibility code for an old TestFlight overlap, add a cleanup TODO before merge.

## Completion Summary

- Step 0: Scope Challenge — scope reduced by user-approved dummy saved-place reset; profiles/social graph preserved.
- Architecture Review: 5 issues resolved.
- Code Quality Review: 2 issues resolved.
- Test Review: diagram produced, 24 gaps identified for implementation coverage.
- Performance Review: 1 issue resolved.
- NOT in scope: written.
- What already exists: written.
- TODOS.md updates: 0 durable TODOs required if no temporary compatibility remains.
- Failure modes: 0 unplanned critical gaps; 4 high-risk paths have required tests.
- Outside voice: skipped.
- Parallelization: 4 lanes, 1 initial lane plus sequential dependencies; Map work should be coordinated.
- Lake Score: 9/9 recommendations chose complete option.
