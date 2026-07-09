# REC-XX Multiple Visits And Visit Photos Plan

Date: 2026-07-09
Status: Backend slice ready for implementation
Reviewer: Codex via `/plan-eng-review`

## Goal

Persist multiple real visits and visit photos without wiring new UI in this pass.

The app currently has one `user_places` row per user/place. Recent REC-70/REC-71 UI makes visits/photos visible, but the underlying visit/photo data is still either inferred from one save row or held in SwiftUI view state. This plan adds the durable backend foundation first.

## Step 0 Scope Challenge

What already exists:

- `public.user_places` already stores the current one-save-per-user/place state, `status`, `visibility`, `note`, `visited_at`, and half-step `rating_score`.
- `app.current_user_id()`, `app.can_read_user_place()`, follows, mutuals, and blocks already define the social visibility contract.
- `public.visible_places_in_view` and `public.profile_visible_places` already return `rating_score`, `recommended_score`, and `recommended_count` to the iOS DTOs.
- `profile-avatars` already demonstrates the Supabase Storage pattern: bucket row, `storage.objects` RLS policies, path ownership, and pgTAP policy tests.
- `LocalUserPlace`, `PlaceRating`, and `PlaceProfilePresentation` already hold local rating and presentation concepts, but not durable visits/photos.

Minimum complete backend slice:

1. Add `place_visits` as the child table under `user_places`.
2. Add `visit_photos` metadata under `place_visits`.
3. Add private `visit-photos` storage bucket with RLS on `storage.objects`.
4. Backfill existing `been` saves into one `backfilled_from_user_place` visit.
5. Keep that legacy visit synced by trigger until the app writes explicit multi-visit rows.
6. Add pgTAP tests for schema, RLS, storage policies, grants, backfill trigger behavior, and visit-based rating aggregation.

Scope accepted as phased: the full product plan touches more than eight files, but this PR intentionally touches only docs plus Supabase migration/tests. Swift/UI wiring is a later branch.

Search check:

- [Layer 1] Supabase Storage uses Postgres RLS on `storage.objects`; private buckets plus authenticated select policies are the right fit for visibility-scoped place photos.
- [Layer 1] Supabase public-schema tables created in SQL need explicit RLS and grants.
- [Layer 3] First-principles call: photo privacy follows the visit's `user_place` visibility, not the bucket. The bucket stays private; the row graph decides who can read.

## Data Model

```text
profiles
  |
  v
user_places 1 ---- * place_visits 1 ---- * visit_photos
  |                     |                       |
  |                     |                       +-- storage.objects
  |                     |                           bucket_id = visit-photos
  |                     |                           name = user_id/visit_id/photo_id.ext
  |                     |
  |                     +-- rating_score, note, visited_at
  |
  +-- status, visibility, place_id, legacy rating_score mirror
```

`place_visits`:

- Belongs to `user_places`, not directly to `places`, to avoid duplicating user/place/visibility ownership.
- Stores `visited_at`, `note`, optional half-step `rating_score`, timestamps, soft delete, and `backfilled_from_user_place`.
- Has a partial unique index on `(user_place_id) where backfilled_from_user_place`, so each legacy save maps to exactly one synced first visit while future explicit visits can be many.

`visit_photos`:

- Belongs to a `place_visit`.
- Stores `storage_bucket`, `storage_path`, `content_type`, dimensions, byte size, upload state, sort order, timestamps, and soft delete.
- Uses paths shaped as `owner_user_id/visit_id/photo_id.ext`.

## RLS And Storage

```text
Read visit/photo:
authenticated viewer
  -> place_visits or visit_photos row
  -> parent user_places row
  -> app.can_read_user_place(viewer, owner, visibility)
  -> blocks/follows/mutual/self rules

Write visit/photo metadata:
authenticated owner
  -> parent user_places owner equals app.current_user_id()
  -> parent save is active and status = been

Read storage object:
storage.objects row
  -> matching visit_photos.storage_path
  -> visit visible through same rule

Write storage object:
object path first folder is app.current_user_id()
  -> matching visit_photos metadata already exists
  -> parent visit is owned by current user
```

The storage bucket is private. No anon read policy. Service-role access remains the operational escape hatch for cleanup and admin jobs.

## Backfill Strategy

```text
existing active user_places
  status = been
        |
        v
one place_visits row
  visited_at = coalesce(user_places.visited_at, saved_at, created_at, now())
  note = user_places.note
  rating_score = user_places.rating_score
  backfilled_from_user_place = true
```

Then an `AFTER INSERT OR UPDATE` trigger on `user_places` keeps the legacy visit in sync:

- `been` save creates or updates the backfilled visit.
- `wanna_go` or deleted save soft-deletes the backfilled visit.
- Switching back to `been` resurrects the same backfilled visit.

This keeps current app builds compatible because they still write only `user_places`. Future UI can add explicit non-backfilled `place_visits` rows without changing the legacy row contract first.

## Rating Aggregation

Current app DTOs keep reading the existing RPC fields for now. The backend slice adds `app.place_visit_rating_summary(place_id, viewer_id)` so the next RPC/UI branch can switch from save-level rating aggregation to visit-level aggregation without changing the table contract again.

Visit-based rating semantics:

- Only active visits with non-null `rating_score` count.
- Visibility is still inherited from the parent `user_places` row.
- Multiple visits by one person can contribute multiple ratings. That matches the product copy: "Your rating" is the average of your visits, and Rec.me rating is based on real visit memories.

## Local Swift Follow-Up Plan

No Swift files change in this backend PR. Follow-up model work:

- Add `LocalPlaceVisit` and `LocalVisitPhoto` SwiftData models.
- Add Codable persistence records beside `UserPlaceRecord`.
- Keep `LocalUserPlace.ratingScore` as a compatibility aggregate/mirror until all screens read visit summaries.
- Add repository protocols for visit CRUD, photo metadata allocation, upload, delete, and retry.
- Add DTOs for visit/photo rows and storage paths.

## Sync Behavior Follow-Up

```text
Save/edit current place
  -> upsert user_places compatibility row
  -> append or update place_visits
  -> upload photo object only after metadata path exists
  -> mark visit_photos.upload_state = uploaded
  -> refresh visible places/profile rows
```

Offline behavior:

- Local visit/photo rows can be queued with local IDs.
- Photo binary upload should wait until the server returns a `visit_photos.storage_path`.
- Failed uploads remain `pending_upload` or `failed` and should be retryable from the visit.

Conflict posture:

- Appending a visit is additive.
- Editing a legacy/backfilled visit updates only that visit.
- Deleting a photo soft-deletes metadata, then deletes the storage object.

## UI Impact Follow-Up

- Latest Activity should render real visits, ordered by `visited_at`.
- Add Photo is available only on the current user's active `been` visits.
- `wanna_go` saves show "No visits yet" and do not expose visit photo upload.
- The rating strip should use visit aggregates:
  - Your rating: average of current user's active visit ratings for this place.
  - Rec.me rating: average of visible trusted active visit ratings.
  - Fit Rating: unchanged deterministic presentation helper for now.
- Photo carousel should read `visit_photos` ordered by visit and `sort_order`.

## Test Coverage Diagram

```text
CODE PATHS                                                   USER FLOWS
[+] Supabase migration                                      [+] Existing TestFlight save still works
  |-- [GAP] create place_visits table                         |-- [GAP] saving been creates first visit
  |-- [GAP] create visit_photos table                         |-- [GAP] editing rating updates first visit
  |-- [GAP] create private visit-photos bucket                |-- [GAP] switching to wanna_go hides visits
  |-- [GAP] RLS grants for authenticated users                `-- [GAP] future add-visit can append rows
  `-- [GAP] storage.objects policies

[+] Backfill trigger                                        [+] Photo upload future flow
  |-- [GAP] insert been -> one backfilled visit                |-- [GAP] metadata path must exist first
  |-- [GAP] update been -> same visit updated                  |-- [GAP] owner can upload/delete own object
  |-- [GAP] wanna/deleted -> visit soft-deleted                `-- [GAP] visible followers can read object
  `-- [GAP] explicit visits do not conflict

[+] RLS visibility                                          [+] Rating display future flow
  |-- [GAP] owner reads own visits/photos                      |-- [GAP] own rating averages visits
  |-- [GAP] follower reads followers-visible                   |-- [GAP] trusted rating averages visible visits
  |-- [GAP] mutual reads mutuals-visible                       `-- [GAP] non-visible visits excluded
  |-- [GAP] non-follower blocked
  `-- [GAP] blocked viewer blocked

COVERAGE BEFORE IMPLEMENTATION: 0/22 paths tested
COVERAGE TARGET THIS PR: 22/22 backend paths tested with pgTAP
```

## Failure Modes

| Path | Failure | Test | Handling/User Impact |
|---|---|---|---|
| Backfill | `wanna_go` saves get fake visits | pgTAP trigger test | Only `been` active saves create visits |
| Backfill | Editing old save creates duplicate first visits | pgTAP uniqueness test | Partial unique index and upsert |
| RLS | Follower can read `self` photos | pgTAP visibility test | Read policies route through `app.can_read_user_place` |
| RLS | Blocked user reads stale visit/photo rows | pgTAP blocked viewer test | Existing block helper is reused |
| Storage | User uploads object under another user's path | pgTAP policy existence plus path metadata rules | Path first folder must match current user and metadata owner |
| Photos | Metadata points at unrelated visit path | pgTAP insert rejection | RLS insert checks path owner, visit id, and photo id |
| Rating | Aggregate includes invisible visits | pgTAP aggregate test | Helper filters through parent visibility |
| Sync | Current app saves do not populate visits | pgTAP trigger test through `user_places` writes | Trigger keeps legacy first visit warm |

Critical silent gaps after this PR: none for backend schema/RLS/storage. UI still cannot use the data until Swift/repository work lands.

## Performance Review

- Use indexes on `place_visits(user_place_id, visited_at desc)` and `visit_photos(visit_id, sort_order, created_at)`.
- Do not add a materialized aggregate table yet.
- Rating aggregation should group visible visit rows by place using existing `user_places.place_id` indexes when RPCs switch over.
- Storage policies do one metadata lookup by exact `storage_path`, backed by a unique index.

## NOT In Scope

- SwiftData model changes.
- Repository/DTO wiring.
- PhotosUI/camera upload wiring.
- Replacing visible/profile RPC response shapes.
- Public web photo pages or anon photo access.
- EXIF extraction, OCR, or provider photo import.
- Paid provider place/photo APIs.
- Changing `user_places` uniqueness or removing its compatibility `rating_score`.

## Worktree Parallelization

Sequential implementation for this PR: all backend work touches `supabase/migrations`, `supabase/tests`, and `docs/agent-log.md`.

Future lanes:

| Step | Modules touched | Depends on |
|---|---|---|
| Backend schema/RLS/storage | `supabase/` | - |
| Swift local models/persistence | `Wander/Models`, `Wander/Services`, `WanderTests` | Backend contract |
| Remote DTO/repository sync | `Wander/Services/Remote`, `WanderTests` | Backend contract |
| UI activity/photos wiring | `Wander/Features/Map`, `Wander/Features/Profile`, `WanderTests` | Swift models + repositories |

## Implementation Tasks

- [ ] **T1 (P1, human: ~2h / CC: ~25min)** - Supabase schema - Add visit/photo tables, private storage bucket, RLS, grants, trigger backfill, and aggregate helper.
  - Surfaced by: Architecture review - current UI has no durable multi-visit/photo backend.
  - Files: `supabase/migrations/*place_visits_visit_photos.sql`
  - Verify: `supabase test db` or strongest available SQL test run.
- [ ] **T2 (P1, human: ~2h / CC: ~25min)** - Supabase tests - Add pgTAP coverage for schema, RLS, storage policies, backfill trigger, and rating aggregate visibility.
  - Surfaced by: Test review - backend paths need full regression coverage before UI wiring.
  - Files: `supabase/tests/place_visits_visit_photos.sql`
  - Verify: `supabase test db`
- [ ] **T3 (P2, human: ~30min / CC: ~5min)** - Coordination - Log commands, test results, and hosted-verification gaps.
  - Surfaced by: Repo agent workflow.
  - Files: `docs/agent-log.md`
  - Verify: final agent-log entry is complete.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|---|---|---|---:|---|---|
| Eng Review | `/plan-eng-review` | Architecture and tests | 1 | CLEAR | Backend scope reduced to additive Supabase schema/RLS/storage/tests; Swift/UI deferred |

- **VERDICT:** ENG CLEARED for the backend-only implementation slice.

NO UNRESOLVED DECISIONS
