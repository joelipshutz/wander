# Lists Collaboration / REC-59 / REC-60 Plan Eng Review

Date: 2026-07-08
Branch: `codex/lists-fixes`
Reviewer: Codex

## Scope

Review the Lists collaboration feature after TestFlight feedback:

- Top navigation controls are clipped on the list detail view.
- After adding places to a list, the My Lists tile can still show `0 places`.
- `REC-59`: lists are not saving right now.
- `REC-60`: push notifications for follower and list activity.

## Step 0: Scope Challenge

### What Already Exists

- `Wander/Models/LocalListModels.swift` has local list, member, and item models.
- `Wander/Services/WanderLocalStore.swift` has local list read, create, update, delete, collaborator, suggestion, add-place, and remove-place methods.
- `Wander/Services/WanderStorePersistence.swift` persists `placeLists`, `placeListMembers`, `placeListItems`, and `autoSaveListAddsToWant`.
- `Wander/Features/Lists/ListsScreen.swift` has the shipped Lists tab, list detail, add flow, map preview/fullscreen map, collaborator sheets, and local UI state.
- `supabase/migrations/20260628112000_place_lists.sql` defines list tables, RLS, visible/detail/save/update/delete/add/remove RPCs.
- `supabase/functions/suggest-list-places` exists as the LLM suggestion endpoint.
- `REC-60` PR #60 defines push preferences, token registration, notification queueing, worker delivery, and list notification producers.

### Minimum Complete Change

Do not rebuild Lists. The complete fix is:

1. Fix list-detail toolbar clipping with compact native toolbar buttons or a safe custom top row.
2. Fix local list count/rendering by making list item projection deterministic after add, sync, and relaunch.
3. Add a real `PlaceListRepository` boundary and Supabase implementation for list create/update/delete/detail/collaborators/items.
4. Wire local-first list mutations through that repository when signed in, with failed/pending sync states preserved.
5. Add regression tests for the exact `REC-59` paths and keep `REC-60` list notifications dependent on server-backed writes.

### Complexity Check

This touches more than 8 files if done completely, but the complexity is real, not invented. The app already has Supabase list RPCs; the missing piece is the client repository/sync bridge. A local-only UI patch would make TestFlight look better on one device while leaving the product broken across reinstall, device, account, and notification flows.

Recommendation: accept the larger but bounded diff. This is not a rewrite; it is connecting already-designed layers.

### Search Check

Search unavailable inside the skill context. Proceeding with in-distribution SwiftUI/Supabase knowledge only.

Layer 1 recommendation: use the existing repository pattern already used for profile, follow, block, save, extraction, and list suggestions. Do not invent a parallel list sync architecture.

### TODOS Cross-Reference

`TODOS.md` does not currently contain the specific Lists persistence bug. It does contain older app-wide persistence/sync items, but `REC-59` should be the active tracker for this pass rather than adding another loose TODO.

## Architecture Review

### Finding 1

`[P1] (confidence: 10/10) Wander/App/WanderBackend.swift:20 — The live backend wires only SupabaseListSuggestionRepository; there is no list repository for create/update/delete/detail/item writes.`

`Wander/Services/RepositoryProtocols.swift:646` only has `ListSuggestionRepository`. Supabase list RPCs exist, but iOS cannot call them. This explains why a collaborative list can be local/mock-functional while not actually saving to backend.

Recommendation: add a `PlaceListRepository` and wire it through `WanderBackend`, matching existing repository style.

```
UI action
  |
  v
WanderStore local mutation
  |
  +-- persist local snapshot
  |
  +-- if signed in/backend available
        |
        v
      PlaceListRepository
        |
        v
      Supabase RPCs from 20260628112000_place_lists.sql
        |
        v
      update local server IDs / sync state / refresh detail
```

Decision: implement the complete repository bridge in `REC-59`. A local-only polish pass is not enough.

### Finding 2

`[P1] (confidence: 8/10) Wander/Services/WanderLocalStore.swift:310 — List rendering depends on visiblePlaces() projection, not the list item table itself.`

`visiblePlaces(in:)` walks `placeListItems`, then tries to find matching candidates from `visiblePlaces()`. If the candidate disappears from the current visible-place cache, has a local/server ID transition, or is not hydrated yet, the list can own an item but render zero places. `PlaceListMock.subtitle` then reports `0 places` from `places.count` at `Wander/Features/Lists/ListsScreen.swift:2438`.

Recommendation: make list item projection list-owned and deterministic. For local state, resolve by `placeID` from `places` and best matching user-place metadata from `ownerUserPlaceID` / `sourceUserPlaceID`; do not drop the item just because `visiblePlaces()` cannot currently see it. For remote state, the list detail RPC should return enough denormalized place/item data for list rendering.

Decision: fix as part of `REC-59`, with regression tests for add, relaunch, and local/server ID transitions.

### Finding 3

`[P2] (confidence: 9/10) Wander/Features/Lists/ListsScreen.swift:589 — List detail uses custom 40pt circular controls inside the native top toolbar, which is likely causing top/bottom clipping.`

Native toolbar height is tight. The current top-right plus and pencil buttons are custom `40x40` circles in a `ToolbarItemGroup`. On real devices this can clip vertically.

Recommendation: keep the native navigation push/back behavior, but replace the toolbar buttons with compact 34-36pt top-bar icon controls using one shared `ListToolbarIconButton`. If clipping persists, move actions into the list header row under the nav bar.

Decision: start with compact native toolbar controls. It is the smallest diff and preserves iOS navigation standards.

### Finding 4

`[P1] (confidence: 9/10) PR #60 / supabase/migrations/20260701190000_push_notifications.sql — List notifications depend on server list writes that current iOS main does not perform.`

REC-60's SQL trigger shape is mostly sound. The branch already guards collaborator removal and already-active rows:

- `new.deleted_at is not null` returns early.
- update from active to active returns early.
- SQL tests cover collaborator added, place added, and collaborator removal no-push.

The architectural issue is sequencing: `list_collaborator_added` and `list_place_added` only fire for Supabase table writes. Current iOS list mutations are local-only.

Recommendation: keep REC-60 separate, but document that list notification scenarios become live only after REC-59 repository sync lands and the list migration is deployed.

Decision: do not fold push delivery into REC-59. Only ensure REC-59 calls the server RPCs that trigger REC-60.

## Code Quality Review

### Finding 5

`[P2] (confidence: 8/10) Wander/Features/Lists/ListsScreen.swift:2415 — PlaceListMock is doing double duty as static mock data and live store-backed view model.`

This is understandable from the mockup phase, but it increases stale-view risk. The live initializer at line 2467 rebuilds from store, while static fallbacks still exist in the same type.

Recommendation: keep the type for this pass, but rename/refactor later to `PlaceListViewModel` and isolate static preview fixtures behind `#if DEBUG` or preview-only helpers. Do not block REC-59 on the rename.

Decision: defer the rename; fix the projection/persistence bug first.

### Finding 6

`[P2] (confidence: 8/10) Wander/Features/Lists/ListsScreen.swift:1079 — Add flow does not expose non-added outcomes to users.`

`store.addVisiblePlace` can return `.alreadyInList` or `.permissionDenied`, but `ListAddPlacesScreen.add` only reloads suggestions/search and shows the auto-save toast when applicable. Users may tap plus and see no meaningful feedback.

Recommendation: add lightweight inline/toast copy for already-in-list and permission-denied outcomes while fixing REC-59.

Decision: include this if it stays small; it improves debuggability and reduces silent failures.

## Test Review

Test framework: XCTest via `xcodebuild test`.

```
CODE PATHS                                                USER FLOWS
[+] List detail toolbar                                   [+] Open list detail
  ├── [GAP] compact toolbar buttons fit safe area           ├── [GAP] visual/device check: top nav not clipped
  └── [GAP] owner-only add/edit visibility                  └── [GAP] owner sees plus/edit, non-owner does not

[+] Local list add/render                                 [+] Add place to owned list
  ├── [★★ TESTED] owner can add network place               ├── [GAP] added place increments My Lists tile count
  ├── [★★ TESTED] collaborator cannot add                   ├── [GAP] detail count/rows update after returning back
  ├── [GAP] add then relaunch preserves count               ├── [GAP] add unsaved/social place with auto-save enabled
  ├── [GAP] local/server userPlace ID transition            └── [GAP] add failure shows visible feedback
  └── [GAP] item renders when visible cache is empty

[+] Remote list sync                                      [+] Signed-in list create/edit/add
  ├── [GAP] create list RPC success                         ├── [GAP] created collaborative list appears after refresh
  ├── [GAP] update collaborators RPC success                ├── [GAP] added collaborator sees list remotely
  ├── [GAP] add item RPC success                            ├── [GAP] place add triggers server list item write
  ├── [GAP] RPC failure marks local list/item failed         └── [GAP] relaunch after server refresh preserves state
  └── [GAP] remove/delete RPC success

[+] REC-60 notification coupling                          [+] List notification scenarios
  ├── [★★ TESTED in PR #60] collaborator added queues push  ├── [GAP] REC-59 server write triggers existing PR #60 SQL
  ├── [★★ TESTED in PR #60] place added queues push         └── [GAP] no push when local-only mutation has not synced
  └── [★★ TESTED in PR #60] removal does not push

COVERAGE: 6/26 paths tested (23%)
QUALITY: ★★★:0 ★★:6 ★:0 | GAPS: 20
```

Required tests for REC-59:

- `WanderStoreTests`: add a place to a newly-created list and assert `visiblePlaces(in:)`, tile count equivalent, persistence snapshot, and relaunch all retain the place.
- `WanderStoreTests`: add a place where the local user-place ID becomes a server ID, then assert the list item still resolves.
- `WanderStoreTests`: list item renders from `placeID` even when current `remoteVisiblePlaceCache` does not contain the source visible place.
- `RemoteRepositoryTests`: `SupabasePlaceListRepository` calls `save_place_list`, `set_place_list_collaborators`, `add_place_list_item`, `remove_place_list_item`, `delete_place_list`, `visible_place_lists`, and `place_list_detail` with expected snake_case params.
- Existing PR #60 SQL test should remain the notification producer coverage; add one integration note that REC-59 server writes are the producer path.

## Performance Review

### Finding 7

`[P2] (confidence: 7/10) Wander/Services/WanderLocalStore.swift:310 — visiblePlaces(in:) does a nested scan over list items and all visible places.`

This is fine for alpha seed data, but if list detail and My Lists tiles repeatedly build view models, the nested scan can become avoidable churn.

Recommendation: while fixing projection, build dictionaries keyed by place ID and user-place ID inside the resolver. This is a small code-quality/performance win and makes the behavior explicit.

Decision: include this in the resolver fix.

## Failure Modes

| Flow | Failure | Covered? | Handling? | User Impact |
|---|---|---:|---:|---|
| Create collaborative list | Server not called | No | Local-only only | List disappears on other devices and no notification fires |
| Add place to list | Item exists but resolver drops it | Partial | No | Tile/detail show `0 places` |
| Add collaborator | Local member exists but server not called | Partial | No | Collaborator does not actually get access |
| Toolbar actions | 40pt custom controls clip in nav bar | No | No | Top buttons look broken/cut off |
| REC-60 list notifications | Server triggers never fire | Partial | No | Push feature appears implemented but list events are silent |
| Push collaborator removal | Incorrect removal push | Yes in PR #60 | Yes in PR #60 | No current blocker in fetched PR |

Critical gaps: 3

## NOT In Scope

- Reworking Lists visual design beyond toolbar clipping and count rendering.
- Adding SMS/deep-link invite links from `REC-52`.
- Shipping full notification delivery as part of REC-59.
- Changing the product rule that only owners can add/manage list places and collaborators.
- Replacing the LLM suggestion function.

## Parallelization Strategy

Sequential implementation is safer for the core REC-59 fix because UI, store projection, repository sync, and tests all touch the same Lists/store modules.

Possible lanes if split across worktrees:

| Step | Modules touched | Depends on |
|---|---|---|
| A. Local UI/projection fix | `Wander/Features/Lists`, `Wander/Services`, `WanderTests` | — |
| B. Supabase repository bridge | `Wander/App`, `Wander/Services/Remote`, `Wander/Services`, `WanderTests` | — |
| C. REC-60 coupling validation | `supabase/tests`, PR #60 branch | B |

Recommended order: do A and B in one worktree because both must agree on list item identity. Then validate C against PR #60 before merge/release.

## Opinionated Recommendations

1. Use `REC-59` as the active implementation ticket.
2. Fix the toolbar clipping first because it is small and visible.
3. Fix the list item resolver and add relaunch/ID-transition tests before touching Supabase.
4. Add `PlaceListRepository` and wire the existing Supabase list RPCs.
5. Keep `REC-60` as a separate PR, but require a note/test that its list events depend on server-backed REC-59 writes.

## Completion Summary

- Step 0: Scope Challenge — scope accepted as a bounded complete fix, not a local-only patch.
- Architecture Review: 4 issues found.
- Code Quality Review: 2 issues found.
- Test Review: diagram produced, 20 gaps identified.
- Performance Review: 1 issue found.
- NOT in scope: written.
- What already exists: written.
- TODOS.md updates: no new TODO recommended; use Linear `REC-59` and `REC-60`.
- Failure modes: 3 critical gaps flagged.
- Outside voice: skipped.
- Parallelization: sequential recommended; optional 2-lane split with careful coordination.
- Lake Score: 5/5 recommendations choose complete option.
