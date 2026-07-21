# REC-107 Feed engineering plan

Status: approved design and engineering review, ready to implement.

Linear: [REC-107](https://linear.app/recme/issue/REC-107/revamp-discover-into-a-social-feed)

## Goal

Replace the current Discover Places idle surface with **Feed**: a compact,
trusted-person place-memory feed. The tab remains searchable, but its resting
job changes from a generic recent-place list to catching up on useful activity
from people the viewer follows.

The release is truthful by construction. Every visible activity is a durable
server-side event, not an inference from the latest mutable place or list row.

## Locked decisions

| Decision | Chosen approach |
|---|---|
| Delivery scope | Full Feed: place saved, Been, Want to go, list created, and list add. |
| Activity truth | Immutable activity envelope written in the same transaction as its source mutation. |
| Event boundary | Narrow database trigger functions, not client-side follow-up writes. |
| Read boundary | One RLS-aware, keyset-paginated Feed RPC. |
| Navigation | Preserve Map, Feed, Add, Lists, Profile. Rename only Discover to Feed. |
| SwiftUI boundary | Dedicated `FeedScreen` and feed-specific presentation models. |
| Featured shelf | Deterministic, distinct recent places from followed people that the viewer has not saved; each carries a trust reason. |
| List action | `View list`, not an unimplemented Save/clone-list action. |
| Tests | Hosted pgTAP, Swift unit/store tests, and simulator state coverage. |

## What already exists

| Existing capability | Reuse in REC-107 |
|---|---|
| `DiscoverSearchField` ticker and `store.discover` / `discoverMembers` | Keep the same prompt ticker and query behavior inside Feed search. Do not build a second parser. |
| `MapPlaceSaveFlowSheet` and `saveDiscoverFlowSubmission` | Reuse the canonical place-save flow for Feed place actions. |
| `WanderStore.refreshRemoteSocialSurfaces` | Continue refreshing the social graph; add Feed refresh beside it rather than re-fetching each followed profile to compose activity. |
| `place_lists`, `place_list_items`, `visible_place_lists`, and list detail | Use list activity references to open the existing list detail. Do not create list bookmarks or copies. |
| `VisitPhotoRepository` storage/RLS contract | Resolve only a bounded media preview for a visible event. Never persist signed URLs in activity rows. |
| Discover people recommendations | Use as the no-activity recovery module with existing Follow behavior. |
| pgTAP visibility/photo/list tests and `WanderStoreTests` fakes | Extend these conventions instead of adding a new test framework. |

## Not in scope

- Moving Lists into Profile or reducing navigation to four tabs.
- Likes, comments, shares, challenges, engagement counts, notifications, or a
  generic public social graph.
- A client-side activity merge, fan-out fetch by followed profile, or a second
  save backend.
- List bookmarks, list cloning, or any control labelled `Save list`.
- Personalized ranking beyond the deterministic Featured rule and newest-first
  activity. The future ranker is recorded in `TODOS.md`.
- Realtime streaming. Pull-to-refresh, tab entry, app foreground, and existing
  remote-maintenance refreshes are sufficient for this release.

## Architecture

```text
AUTHENTICATED WRITE                                    AUTHENTICATED READ

Place/List/Visit mutation                              FeedScreen task / refresh
        |                                                       |
        v                                                       v
existing table write                                 public.followed_feed(cursor, limit)
user_places | place_lists | place_list_items                  |
        |                                                       |
        v                                                       v
AFTER trigger with status-transition guards           app.followed_feed(...) SECURITY DEFINER
        |                                                 - current user comes from auth claim
        v                                                 - follows / blocks / profile opt-out
public.feed_events (immutable envelope)                - live source visibility is rechecked
        |                                                 - keyset cursor is validated/clamped
        +-------------------- committed together -------------------+
                                                                  |
                                                                  v
                                                       FeedRepository -> WanderStore cache
                                                                  |
                                                                  v
                                               Featured rail + chronological activity modules
                                               place save -> canonical MapPlaceSaveFlowSheet
                                               list event -> existing visible-list detail
```

### Event envelope

Create `public.feed_events` as an append-only internal activity envelope:

```text
feed_events
  id                  uuid primary key
  actor_user_id       text not null -> profiles
  event_type          place_saved | place_been | place_want_to_go |
                      list_created | list_item_added
  user_place_id       uuid nullable -> user_places
  place_id            uuid nullable -> places
  list_id             uuid nullable -> place_lists
  list_item_id        uuid nullable -> place_list_items
  occurred_at         timestamptz not null (server commit time)
  created_at          timestamptz not null
```

The envelope deliberately stores stable identifiers and type, not signed image
URLs or mutable note/rating snapshots. The Feed projection resolves current
place/list presentation only when that source is currently visible. That lets a
block, private profile, source deletion, or visibility downgrade retract every
related event without a client cleanup race.

### Event emission rules

Use `AFTER` row triggers, so the source mutation has passed constraints and all
final values are available. Trigger functions are narrow `SECURITY DEFINER`
functions with a pinned `search_path`; clients receive no direct `feed_events`
write grants.

| Source transition | Event | Guard against duplicates |
|---|---|---|
| `user_places` insert, `status = wanna_go` | `place_want_to_go` | Insert only; an upsert retry follows the update path and emits nothing if status is unchanged. |
| `user_places` insert, `status = been` | `place_been` | Insert only. |
| `user_places.status` changes `wanna_go -> been` | `place_been` | `OLD.status IS DISTINCT FROM NEW.status`; do not emit on note/rating/visibility edits. |
| `user_places` social-save source where the product marks a generic save | `place_saved` | Mutually exclusive type rule, so one source mutation yields one event. |
| `place_lists` insert | `list_created` | Insert only; list edits never create activity. |
| `place_list_items` insert or soft-delete restore | `list_item_added` | Emit on insert or `OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL`; not on active upsert. |

`place_visits` stays a source for current visible note/rating/media but does not
add a second Feed event for an initial Been save. This avoids the existing
backfill path producing duplicate activity from one user action.

### RLS-aware projection

Expose exactly one authenticated RPC, `public.followed_feed(input_before,
input_limit)`, backed by a narrow `app.followed_feed` implementation.

- The viewer comes only from `app.current_user_id()`; callers cannot select a
  different feed owner.
- Return only actors the viewer follows, excluding self, blocks, mutes, and
  private-mode profiles.
- Re-evaluate the referenced user-place or list visibility at read time using
  the existing visibility/list helpers. Source deletion or denied visibility
  removes the event rather than leaking a title, note, photo, or avatar.
- Clamp page size to 50, use an opaque `(occurred_at, id)` keyset cursor, and
  return `next_cursor` only from the last permitted row.
- Return at most three preview-media descriptors per expanded module. The
  client signs/loads only visible, permitted media through existing photo
  storage boundaries.

This follows the project RLS rule: `SECURITY DEFINER` is acceptable only for a
narrow function, explicit viewer scoping, pinned search path, and
authenticated-only execution. PostgreSQL `AFTER` triggers run in the same
transaction as the source write, so an activity row cannot survive a rolled
back save. [PostgreSQL trigger behavior](https://www.postgresql.org/docs/current/trigger-definition.html)
[Supabase RLS guidance](https://supabase.com/docs/guides/database/postgres/row-level-security)

### Feed response contract

```text
FollowedFeedPage
  activity: [FeedActivity]
  featuredPlaces: [FeaturedPlace]
  nextCursor: FeedCursor?
  fetchedAt: Date

FeedActivity
  id, kind, occurredAt
  actor: ProfileShell
  place: FeedPlace?                 // category, locality, current visibility
  list: FeedList?                   // id, title, itemCount, current visibility
  rating: Double?                   // only on eligible Been/list-add types
  note: String?                     // never on Want-to-go
  media: [FeedMediaPreview]         // 0...3, source currently visible

FeaturedPlace
  visiblePlace: VisiblePlace
  reason: "Saved by <followed person>"
```

The server chooses the deterministic shelf from distinct eligible feed places,
newest first, excluding anything the viewer already saved. This is a selection
rule, not a claimed personalized score.

## iOS data flow and states

```text
FeedScreen appears / retry / pull-to-refresh
                |
                v
WanderStore.refreshFeed(backend)
   | success                       | failure
   v                               v
cache FeedPage + fetchedAt     keep cached page if present
   |                               |
   v                               v
FeedLoadState.loaded            FeedLoadState.stale / failed
   |
   +--> no activity -> People recovery shelf
   +--> no featured -> omit rail
   +--> place event -> MapPlaceSaveFlowSheet
   +--> list event -> existing list detail
```

| UI state | Required behavior |
|---|---|
| First load | Compact search remains usable; render module-shaped skeletons, not a full-screen spinner. |
| Loaded | Optional Featured rail, then newest-first activity. |
| Empty | Keep tabs and search. Explain that following people fills Feed and reuse direct Follow recovery. |
| Error with cache | Keep cached activity, show quiet `Updated earlier` state and retry. |
| Error without cache | Inline retry below `Your feed`; search remains usable. |
| Search | Feed is idle-only. Reuse parser/results, cancel stale searches, and restore prior feed scroll state when query clears. |
| Place action | Present canonical save sheet; pending/success/failure state belongs to the action, never mutates the source event. |
| List action | `View list` routes only to an already visible list. |
| Dynamic Type | Wrap actor/action before the rating/action control; media rails remain horizontal; all taps are 44 pt minimum. |

## Implementation sequence

1. **Database contract**
   - Add the migration, `feed_events`, indexes, trigger functions, event
     triggers, projection RPC, grants, and explicit RLS posture.
   - Add cursor validation and deterministic featured selection to the single
     projection. Seed no production activity.
2. **Hosted contract tests**
   - Add pgTAP for every emission rule, no-op retry, status transition,
     list-item restore, ordering, cursor page boundary, visibility downgrade,
     private profile, block, mute, and denied source media.
   - Assert function metadata: `prosecdef`, pinned `proconfig`, execute grants,
     and no `anon` access.
3. **Typed iOS boundary**
   - Add Feed domain DTOs, repository protocol, Supabase repository, and
     `WanderBackend` wiring for one page response.
   - Add `WanderStore` cached Feed state, refresh/retry handling, and fixture
     payloads with realistic people, places, ratings, notes, lists, and photos.
4. **Feed UI**
   - Add `FeedScreen` and narrowly scoped module views: compact ticker search,
     Featured rail, activity row/expanded block, people recovery, skeleton,
     error/stale row, and action affordances.
   - Reuse existing place-save and list-detail routes. Preserve universal place
     and member search without copying the parser.
   - Rename only the tab label/icon from Discover to Feed; leave Lists as a
     first-class fifth tab.
5. **Verification and visual QA**
   - Add unit tests and launch routes for every required state.
   - Build and run the full test suite. Capture iPhone 16 Plus and iPhone 16e
     populated/empty/error/search screenshots, then run the live design review.

## Test coverage diagram

```text
DATABASE / RPC                                     NATIVE / USER FLOWS

[+] feed_events trigger contract                   [+] Feed idle
  |- [GAP] user_places -> Want event                 |- [GAP] ticker search and featured rail
  |- [GAP] user_places -> Been event                 |- [GAP] newest-first mixed activity
  |- [GAP] status transition -> Been event           |- [GAP] no featured hides rail
  |- [GAP] list insert -> created event              |- [GAP] no activity -> Follow recovery
  |- [GAP] list item insert/restore -> add event     |- [GAP] cached error shows stale content
  `- [GAP] retry/upsert does not duplicate           |- [GAP] no-cache error retries
                                                    |- [GAP] search clear restores Feed
[+] followed_feed RLS projection                    |- [GAP] place save -> pending/check/retry
  |- [GAP] follower reads permitted event            `- [GAP] list event -> visible list detail
  |- [GAP] private/blocked/muted actor excluded
  |- [GAP] source visibility downgrade retracts    [→E2E] signed-in fixture flow across Feed,
  |- [GAP] cursor is stable, bounded, and ordered            canonical save, and list detail
  `- [GAP] metadata/grants remain secure

COVERAGE TARGET: every listed GAP becomes an automated test before merge.
```

### Required test files

| Layer | File | Assertions |
|---|---|---|
| Hosted | `supabase/tests/feed_activity.sql` | Event emission, idempotency guards, RLS, source retraction, cursor, function metadata/grants. |
| Remote smoke | `scripts/supabase-smoke-test.mjs` | Extend the rolled-back linked smoke only after the pgTAP contract is committed. |
| Swift domain/store | `WanderTests/FeedModelsTests.swift`, `WanderTests/WanderStoreTests.swift` | Event mapping, deterministic shelf, mixed chronology, stale/error cache, source-specific action states. |
| Navigation/UI contract | `WanderTests/WanderRootViewTests.swift` or existing root test home | Five tabs, Feed label/icon, discovery route compatibility. |
| Simulator | launch-route or UI state tests | Populated, empty/recovery, error/stale, search, Dynamic Type, iPhone 16 Plus + 16e screenshots. |

## Failure modes

| Failure | Prevention | User-visible recovery |
|---|---|---|
| Offline write retries | Trigger guards emit only on real insert/transition/restore. | Event appears once after sync; no duplicate card. |
| Actor goes private or blocks viewer | Projection verifies current profile/block/source visibility every read. | Module disappears without leaking stale copy/media. |
| List/place becomes inaccessible | Event envelope remains internal, projection suppresses it. | No dead destination; Feed simply reflows. |
| Feed RPC fails | Store preserves latest cache and timestamp. | `Updated earlier` with inline retry; search continues. |
| Cursor is invalid/stale | RPC validates and clamps before querying. | Fresh first page rather than a crash or duplicate loop. |
| Photo signing/loading fails | Preview media is optional and bounded. | Keep event text/action; omit failed image, never the whole module. |
| User double-taps save | Canonical save flow remains source of truth; Feed only reflects its outcome. | Pending action disables, then checkmark or retry. |

## Performance and observability

- One Feed RPC per refresh/page. Do not fetch activity separately for every
  followed profile or media item.
- Use keyset pagination `(occurred_at, id)`, `limit <= 50`, and an index shaped
  for actor/time reads. Offset pagination is excluded because RLS and ordered
  scans amplify its cost. [Supabase RLS performance notes](https://supabase.com/docs/guides/database/postgres/row-level-security)
- Preview only up to three media descriptors per expanded row; lazy-load images
  in SwiftUI horizontal rails. [`ScrollView` is the native scroll container](https://developer.apple.com/documentation/SwiftUI/ScrollView).
- Track: Feed loaded, stale shown, retry tapped, place save opened/succeeded/
  failed, list viewed, featured opened, recovery follow tapped, and RPC failure
  category. Do not log notes, precise coordinates, raw cursors, or media URLs.

## Worktree strategy

| Step | Modules touched | Depends on |
|---|---|---|
| Database event contract | `supabase/migrations`, `supabase/tests` | — |
| Swift Feed models/UI fixtures | `Wander/Features/Feed`, `Wander/Services`, `WanderTests` | response contract agreed |
| Repository/store integration | `Wander/Services/Remote`, `Wander/Services`, `WanderTests` | database + Feed models |
| Root navigation and visual QA | `Wander/App`, `Wander/Features/Feed`, `WanderTests` | integration |

- **Lane A:** database event contract and pgTAP tests.
- **Lane B:** Feed presentation models, fixture data, and pure SwiftUI modules
  against the agreed response contract.
- **Lane C:** repository/store wiring after A and B, then root navigation.

Launch A and B in parallel only if each agent stays out of shared
`Wander/Services`; otherwise this is sequential implementation to avoid a
merge conflict in the store/repository boundary.

## Implementation tasks

- [ ] **T1 (P1, human: ~4h / CC: ~40min)** — Supabase Feed activity contract
  - Surfaced by: Architecture D2/D4. Activity must remain durable, idempotent,
    and RLS-filtered after source edits.
  - Files: `supabase/migrations/<timestamp>_feed_activity.sql`,
    `supabase/tests/feed_activity.sql`.
  - Verify: pgTAP plus linked hosted metadata/RLS smoke.
- [ ] **T2 (P1, human: ~2h / CC: ~25min)** — Typed Feed repository and local
  cache state
  - Surfaced by: Architecture D1 and Performance review. No client fan-out.
  - Files: `Wander/Services/FeedModels.swift`, `RepositoryProtocols.swift`,
    `Remote/SupabaseRepositories.swift`, `Remote/SupabaseDTOs.swift`,
    `WanderBackend.swift`, `WanderLocalStore.swift`.
  - Verify: DTO and store unit tests for cache, ordering, error, and retry.
- [ ] **T3 (P1, human: ~4h / CC: ~40min)** — Dedicated Feed surface
  - Surfaced by: Code quality D5 and approved design contract.
  - Files: `Wander/Features/Feed/FeedScreen.swift` and narrow module views;
    shared search extraction only where existing code can be reused directly.
  - Verify: populated, no-featured, no-activity, stale/error, search, and
    Dynamic Type simulator coverage.
- [ ] **T4 (P2, human: ~45min / CC: ~10min)** — Rename bottom navigation
  - Surfaced by: Architecture D3.
  - Files: `Wander/App/WanderRootView.swift`, root navigation tests.
  - Verify: Map, Feed, Add, Lists, Profile remain routable; no deep-link break.
- [ ] **T5 (P2, human: ~1h / CC: ~15min)** — Feed fixtures and analytics
  - Surfaced by: Test review D6 and Featured D7.
  - Files: `Wander/Services/WanderFixtures.swift`, analytics definitions,
    test fakes.
  - Verify: deterministic rich actors/photos/lists and non-PII analytics tests.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----:|-----:|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | — | — |
| Codex Review | `/codex review` | Independent 2nd opinion | 0 | skipped | No parallel outside voice available in this session. |
| Eng Review | `/plan-eng-review` | Architecture & tests | 1 | CLEAR | 5 decisions locked; 0 critical gaps after full test contract. |
| Design Review | `/plan-design-review` | UI/UX gaps | 1 | CLEAR | Primary Feed mock and all main state contracts approved. |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | — | — |

**VERDICT:** DESIGN + ENG CLEARED — ready to implement.
NO UNRESOLVED DECISIONS
