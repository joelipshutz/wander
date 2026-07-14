# REC-93 List Place Photos Design Review

Date: 2026-07-13
Status: Recommended direction ready for product confirmation
Reviewer: Codex via `plan-design-review`
Linear: [REC-93](https://linear.app/recme/issue/REC-93/design-adaptive-list-covers-using-place-photos)

## Executive Recommendation

Use automatic, adaptive list covers built from visit photos the current viewer is allowed to see. Preserve the existing 0/1/2/3/4+ collage geometry, replace category tiles with real visit photos when available, and keep the current category tile as the fallback for each missing image.

Do not add a list-level photo upload or manual cover picker in v1. The list should visually explain its contents, not become a second photo-management product.

Do not invoke Google Places photo enrichment from list covers, list rows, or the list map rail. Google remains the deliberate place-open enrichment path. A Lists grid would otherwise prefetch several provider photos at once, consume the existing 900/month global quota, and make required per-photo attribution illegible in small collage cells. Google states that author attribution must appear wherever an attributed photo is displayed, and its photo resource names cannot be cached: [Place Photos (New)](https://developers.google.com/maps/documentation/places/web-service/place-photos).

The v1 source order for compact Lists media should be:

1. A newly added local visit photo owned by the current user, while upload is pending.
2. The first uploaded visit photo for that place that the current viewer can read through existing RLS.
3. The existing category-color tile and symbol.

The same source contract should power the Lists home cover, the place row in list detail, and the place tile in the full-screen list map rail.

## What Already Exists

- `ListPreviewMosaic` already implements useful adaptive geometry: one full tile, two equal columns, three as one large plus two stacked, and four as a 2x2 mosaic.
- `ListPlaceRow` and `ListMapPlaceTile` already reserve stable square media frames with category fallbacks.
- `PlaceProfilePhotoImage` already renders local or remote `PlacePhoto` bytes, crossfades success, and reports load failure.
- `first_visible_place_photo(place_id)` already returns the earliest uploaded visit photo permitted by visit/user-place RLS.
- Visit photos already live in the private `visit-photos` bucket and inherit the parent save's visibility.
- Lists already preserve item order by `place_list_items.created_at`.
- The list detail hierarchy is already correct: title and collaborators, map preview, places, then suggestions.

The implementation should extract and reuse those contracts rather than copy the map card's state machine into each Lists component.

## Current Design Review

The current screen is structurally sound but visually generic. Repeated category glyphs make several lists look interchangeable even when their places are different. A coffee list and a mixed neighborhood list can both read as the same beige icon board.

What works:

- Two-column density is appropriate for scanning several lists.
- Covers have stable square dimensions.
- The current 1/2/3/4 geometry already handles partial lists without fake `+` slots.
- Names, privacy, collaboration, and place count sit outside the cover, so photos will not compete with important text.
- The map remains the visual anchor inside list detail.

What does not work:

- Category symbols communicate type, not place identity or memory.
- The same muted tile repeated across a grid produces a one-note beige surface.
- There is no loading, remote failure, offline, permission-change, or photo-deletion behavior.
- Loading full uploaded originals for several covers could download many megabytes on one screen.
- Reusing Google photo resolution literally would create provider cost, no-cache, and attribution problems.
- The list summary contract has only item counts; there is no batched cover-media contract.

## Screen Hierarchy

Lists home keeps its current order:

```text
lists                                      (+)
save places into a plan you can actually use

[ My lists | Friends | Collabs ]

[ adaptive cover ]  [ adaptive cover ]
  List title           List title
  2 places             3 places

[ adaptive cover ]  [ adaptive cover ]
  List title           List title
  4 places             8 places

[ Map | Discover | Add | Lists | Profile ]
```

List detail keeps its current map-first order:

```text
<  List name                                  (+) (edit)
   Description
   [face pile] collaborators                 N places

[ map preview - primary visual anchor ]

places
[photo] Place name       Category - City       (remove)
[icon ] Place name       Category - City       (remove)

suggested places
[existing suggestion rows]
```

There is no list hero image above the map. The cover is a compact preview on Lists home; the map is the useful representation after the list opens.

## Adaptive Cover Specification

| Active places | Cover layout | Media behavior |
|---|---|---|
| 0 | One quiet full square | Sand/sage surface with the list initial. No fake photo, no four `+` cells, and no CTA inside the cover. |
| 1 | One full-bleed slot | Visit photo if visible; otherwise the place's category tile. |
| 2 | Equal vertical split | One stable slot per represented place with a 2pt internal gutter. |
| 3 | First slot 50% left; slots 2 and 3 stacked right | Matches the current implementation and gives the first represented place hierarchy. |
| 4+ | 2x2 | Show exactly four represented places. Place count remains below the cover; do not add a `+N` photo overlay. |

Cover candidate selection:

1. Scan active list items in stable list order.
2. Select up to four photo-bearing places in that order.
3. If fewer than four have visible photos, fill remaining slots with the earliest unrepresented places using category fallbacks.
4. Resolve the slot manifest before image bytes load so tiles never reorder while the user watches.
5. Recompute only when list membership, list order, photo availability, photo visibility, or the signed-in viewer changes.

Cropping and treatment:

- `scaledToFill`, center crop by default.
- Stable 1:1 outer aspect ratio at every Dynamic Type size.
- 2pt internal gutters; no border around each photo.
- One subtle outer hairline is enough.
- No text, status, gradients, or actions over the image.
- List lock and collaboration icons stay beside the title below the cover.
- Category fallback tiles retain the existing palette and symbol vocabulary.

## Photo Behavior By Surface

| Surface | Recommendation | Why |
|---|---|---|
| Lists home cover | Up to four viewer-visible visit photos with per-slot category fallback | Makes lists specific while keeping automatic scan density. |
| List detail header | No new cover or hero | The map already does the useful orientation work. |
| List detail place row | 56pt square compact visit-photo thumbnail, category fallback | Connects each row to the same place memory shown elsewhere. |
| Full-screen list map rail | 62pt square compact visit-photo thumbnail, category fallback | Preserves the current tile dimensions and tap behavior. |
| Suggested/add-place rows | Keep current category thumbnails in this slice | Candidate search can contain unsaved provider results and should not trigger automatic photo enrichment. |
| Opened place profile | Keep current full place-photo behavior, including Google enrichment and attribution | This is a deliberate user action with enough room for credits and fallback. |

## Interaction State Coverage

| Feature | Loading | Empty | Error | Success | Partial/offline |
|---|---|---|---|---|---|
| List cover manifest | Render existing category/initial cover without shimmer or geometry change | Initial cover for 0 places | Keep fallback cover; no warning copy | Crossfade photos into fixed slots | Show any locally cached/available visit photos and category fallbacks for the rest |
| Cover image bytes | Keep the slot's category fallback visible | Not applicable | Leave fallback in place; do not retry visibly in a loop | 180-240ms opacity crossfade | A mix of photos and category slots is an intended state |
| List membership change | Keep current cover until new manifest is available | Transition to initial cover after final place removal | Keep prior cover until next successful refresh | Replace manifest once, then crossfade changed slots | Pending local add/remove updates immediately from local store |
| Photo upload | Show the local photo immediately to its owner | No change for viewers who cannot access it | Fall back after upload failure; owner still sees upload failure in the visit flow, not on Lists home | Remote descriptor replaces local reference without layout movement | Other viewers see it only after upload and RLS visibility allow it |
| Photo deleted/hidden | Keep current frame until refresh resolves | Fall back to category or next candidate | Never expose stale bytes after access failure | Recompute candidate set | Different viewers can legitimately see different covers |
| List detail row/rail | Category tile is the loading placeholder | Existing no-places state | Category tile remains | Crossfade photo in place | Rows can mix photos and category fallbacks |

No skeleton grid is recommended. The category cover is already a complete, honest fallback and avoids a second visual state that flashes on every Lists open.

## Privacy And Social Semantics

List covers are viewer-scoped, not canonical public artwork.

- A viewer can use any visit photo that existing RLS says they may read, regardless of whether the photographer owns or collaborates on the list.
- The same shared list can show different cover photos to two viewers. This is acceptable and preferable to copying a private social photo into list-owned public storage.
- A block, unfollow, visibility change, deleted visit, or deleted photo must remove that media on the next manifest refresh.
- Do not persist a resolved private URL, signed URL, or storage object path onto `place_lists`.
- Do not create a public list-cover bucket in v1.
- Local pending photos are owner-only until upload succeeds.

If identical, shareable list artwork becomes a product requirement later, it needs a separate consented `list_cover_asset` model owned by the list. It should not be inferred from social photos.

## Data And Request Contract

Do not issue `first_visible_place_photo` once per tile and do not call `place-photo` from `ForEach` cells.

Recommended backend contract:

```text
visible_place_lists()
        |
        +--> one batch RPC: place_list_cover_media(input_list_ids uuid[])
                 returns <= 4 stable viewer-scoped slots per list

slot:
  list_id
  list_item_id
  place_id
  place_position
  place_name
  category
  photo_id?              // visit photo only
  storage_bucket?
  storage_path?
  width?
  height?
  photo_updated_at?
```

The new RPC should be `security invoker`, pin `search_path`, grant execute only to `authenticated`, enforce `app.can_read_place_list`, and rely on current visit/photo/user-place RLS for photo visibility. It should have hosted regression coverage for owner, follower, mutual, self-only, block, deleted photo, and non-member list access.

Keep this as a separate batch RPC instead of changing the existing table return shape of `visible_place_lists()`. That limits migration risk and lets list summaries remain useful even when media resolution fails.

Client contract:

- Add a shared compact media resolver rather than embedding `@State` photo logic in each Lists view.
- Key in-memory results by viewer id, place id, photo id, and photo update timestamp.
- Cancel work when a LazyVGrid cell leaves the viewport.
- Limit concurrent remote thumbnail downloads to four.
- Never retry a failed object repeatedly during one screen session.
- Clear viewer-scoped caches on account change and auth loss.

## Thumbnail Delivery

Current visit uploads may be up to 10MB, while list tiles need roughly 160-320 physical pixels. Lists must not download original images for every cell.

Preferred implementation if the Supabase project is Pro or above:

- Use authenticated Supabase Storage image transformations for private objects.
- Request approximately 320x320, `cover`, quality 70-75 for list covers.
- Request approximately 128x128 for 56/62pt row thumbnails at 2x scale.
- Keep the original private object and its RLS contract unchanged.

Supabase documents private signed transformations and notes that image resizing is available on Pro and above: [Storage Image Transformations](https://supabase.com/docs/guides/storage/serving/image-transformations).

Fallback if transformations are unavailable:

- Generate a 320px JPEG derivative during the existing visit-photo upload.
- Store `thumbnail_storage_path` on `visit_photos` and protect it with the same parent visibility rules.
- Backfill derivatives lazily only for photos selected into visible covers.

The implementation plan must verify the project's current Supabase plan before choosing between these paths.

## Accessibility And Device Behavior

- The full list card remains one accessibility element: `Open <list name>, <N> places`, plus collaborative/locked status as applicable.
- Individual collage photos are decorative and hidden from VoiceOver; reading four photo descriptions before the list name would be noise.
- Place-row thumbnails are decorative because the adjacent place name labels the row.
- Do not encode category or photo presence by color alone; category symbols remain in fallback tiles.
- Preserve 44pt minimum targets for list cards, remove buttons, and add actions.
- Do not let Dynamic Type resize the square cover. Text below can grow and the two-column grid can become one column at accessibility sizes if either card falls below 150pt wide.
- Verify at the current iPhone target and a smaller phone, in light mode, with Reduce Motion, and at an accessibility Dynamic Type size.
- Crossfade only; no parallax, collage rearrangement, or animated crop.

## User Journey

| Horizon | User experience | Design response |
|---|---|---|
| First 5 seconds | Lists feel like real plans made from real places rather than repeated symbols | Authentic network photos create immediate specificity while title/count remain easy to scan. |
| First 5 minutes | Adding a place or photo should visibly improve the list without requiring cover management | Covers update automatically from membership and visit-photo state. |
| Long term | Shared lists accumulate trusted memories without quietly weakening privacy | Viewer-scoped RLS media can change as relationships and visibility change; no public copied cover asset is created. |

## Design System Alignment

- Preserve `WanderTheme` surface, text, terracotta, sky, sage, sun, radius, spacing, and hairline tokens.
- Keep the existing `ListPreviewMosaic` geometry and existing list-card text hierarchy.
- Reuse a generalized form of `PlaceProfilePhotoImage` for local/remote decoding and load failure.
- Keep category fallback behavior from `WanderPlaceCategory`.
- Do not copy the generated mock's alternative fonts, tabs, nav icons, or face-pile styling; the mock is a composition reference only.
- Avoid another nested card layer. The list card is already the interaction; the cover needs no floating controls.

## Visual Reference

Recommended adaptive direction:

`/Users/joelipshutz/.gstack/projects/wander-nametbd/designs/list-place-photos-20260713/recommended-adaptive-list-photos.png`

The mock is illustrative, not pixel-spec source. Correct these generator artifacts during implementation:

- Keep production typography, segmented control, bottom navigation, toolbar, and face pile.
- The right-hand header count must match the actual row count.
- The zero-place cover must remain a flat tokenized fallback, not a photographic texture.
- Suggested places stay out of the photo-loading scope for this slice.

## Seven-Pass Review

| Design dimension | Before | After spec | Remaining gap |
|---|---:|---:|---|
| Information architecture | 7/10 | 9/10 | Visual QA must confirm photos do not overpower titles. |
| Interaction states | 3/10 | 9/10 | Exact retry telemetry belongs in engineering review. |
| User journey and emotional arc | 6/10 | 9/10 | Needs real-user validation with sparse photo networks. |
| AI slop risk | 5/10 | 9/10 | Keep production UI; do not copy generated nav/type drift. |
| Design system alignment | 8/10 | 9/10 | Shared media component still needs native implementation. |
| Responsive and accessibility | 5/10 | 9/10 | One-column accessibility breakpoint needs simulator validation. |
| Unresolved decisions | 3/10 | 8/10 | Product should confirm viewer-scoped, visit-photo-only automatic covers. |

Overall: 5/10 before review, 9/10 after this specification.

## Recommended Decisions

| Decision | Recommendation | Rationale |
|---|---|---|
| Automatic vs manual cover | Automatic only in v1 | Removes management work and keeps covers tied to list content. |
| Photo network | Any viewer-visible visit photo | Uses the trusted network while preserving RLS. |
| Identical cover for every viewer | No | Privacy correctness matters more than canonical artwork. |
| Google photos in Lists | No | Quota, no-prefetch/no-cache, and attribution make compact grids the wrong surface. |
| Empty list cover | Initial on a quiet tokenized surface | Honest, stable, and not a ghost grid of plus signs. |
| Detail hero | No | The map is the more useful visual for a list. |
| Suggested-place photos | Defer | Avoid provider enrichment and keep this slice focused on saved list content. |
| Thumbnail delivery | Authenticated transforms if current plan supports them; otherwise stored derivative | Prevents multi-megabyte grid loads without changing photo privacy. |

## Not In Scope

- Manual list-cover selection or reordering.
- Uploading an image directly to a list.
- Public/canonical cover URLs for sharing outside the app.
- Google or Yelp photo enrichment in compact list surfaces.
- A place-photo carousel inside Lists.
- Photo editing, crop controls, filters, or focal-point selection.
- Redesigning Lists navigation, detail layout, suggestions, or list collaboration.
- Reordering list places. The cover follows the current stable item order.

## Implementation Tasks

- [ ] **T1 (P1, human: ~1d / Codex: ~2h)** - Backend media manifest - Add one viewer-scoped batch RPC for up to four cover slots per visible list.
  - Surfaced by: Interaction state and performance review; the current summary has only item count and per-tile RPCs would create N+1 work.
  - Files: `supabase/migrations/`, `supabase/tests/`, `Wander/Services/Remote/SupabaseDTOs.swift`, `Wander/Services/Remote/SupabaseRepositories.swift`, `Wander/Services/RepositoryProtocols.swift`.
  - Verify: pgTAP plus hosted metadata/smoke checks for owner/follower/mutual/self/block/delete access.
- [ ] **T2 (P1, human: ~1d / Codex: ~2h)** - Compact photo delivery - Add transformed or derivative thumbnail reads for private visit photos.
  - Surfaced by: Performance review; current uploads can be 10MB and current image loading downloads the full object.
  - Files: `Wander/Services/Remote/SupabaseClient.swift`, `Wander/Services/Remote/SupabaseRepositories.swift`, visit photo upload/storage code, and possibly `supabase/migrations/`.
  - Verify: network payload size, private RLS behavior, offline fallback, and account-switch cache isolation.
- [ ] **T3 (P1, human: ~1d / Codex: ~2h)** - Shared compact media resolver - Extract local/visible-photo/category fallback and cancellation from the map-specific view state.
  - Surfaced by: Design-system review; three Lists components need one source of truth.
  - Files: `Wander/Features/Map/PlaceProfileMapSurface.swift`, a shared DesignSystem or media component, `Wander/App/WanderBackend.swift`, tests.
  - Verify: local pending photo, remote success, decode failure, deleted photo, cancellation, and no provider function call.
- [ ] **T4 (P1, human: ~1d / Codex: ~2h)** - Lists UI integration - Render adaptive cover media and compact thumbnails without changing current layout hierarchy.
  - Surfaced by: Information architecture and AI-slop review.
  - Files: `Wander/Features/Lists/ListsScreen.swift`, presentation tests, screenshots.
  - Verify: 0/1/2/3/4+ places, mixed photo/fallback slots, My/Friends/Collabs, list detail, map rail, small phone, accessibility text.
- [ ] **T5 (P2, human: ~4h / Codex: ~45m)** - Observability and regression protection - Log manifest/image failures without private paths and assert Lists never invokes Google photo enrichment.
  - Surfaced by: Trust and provider-contract review.
  - Files: debug logging, repository spies, Lists tests.
  - Verify: no photo path/note/coordinates in logs; one batch manifest request; zero `place-photo` calls from Lists home/detail/rail.

## GSTACK REVIEW REPORT

| Run | Status | Findings |
|---|---|---|
| Current production code and screenshot audit | Issues found | Strong adaptive geometry; generic category content; no media states or batched contract. |
| gstack visual variants | Completed with one timed-out generation | Adaptive collage retained the strongest scan behavior. Single hero reduced list specificity; map/photo hybrid duplicated the detail map's job. |
| gstack visual quality check | Pass | Recommended board supports the chosen hierarchy; human review added generator caveats above. |
| Official provider-policy check | Issues found and absorbed | Google attribution, no-cache, quota, and on-demand rules make provider photos unsuitable for automatic compact list media. |
| Seven design passes | Completed | Overall design completeness improved from 5/10 to 9/10. |

VERDICT: Proceed to engineering review after product confirms the recommended automatic, viewer-scoped, visit-photo-only cover contract.

**UNRESOLVED DECISIONS:**
- Product confirmation requested: use automatic viewer-scoped visit photos only, no Google photos or manual list-cover selection in v1.
