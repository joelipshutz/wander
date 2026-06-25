# Place Profile Redesign Eng Review After Ratings Merge

Date: 2026-06-24
Status: Reviewed with changes needed before implementation
Branch reviewed: `codex/place-profile-eng-review`
Main baseline: `fcc7d2f` (`chore: bump testflight build 44`) including `1cdc434` (`feat: add numeric place ratings (#34)`)
Reviewer: Codex via `/plan-eng-review`

## Inputs

- Design direction: `/private/tmp/recme-design-review/place-profile-design-doc.md`
- Mock: `/private/tmp/recme-design-review/place-profile-redesign-mock.html`
- Landed rating plan: `docs/reviews/2026-06-24-rating-system-plan-eng-review.md`
- Landed implementation: PR #34 numeric ratings on `origin/main`

## Step 0: Scope Challenge

### What Already Exists

- Actual rating storage exists: `user_places.rating_score`, `LocalUserPlace.ratingScore`, `UserPlaceDraft.ratingScore`, `RemoteVisiblePlaceDTO.ratingScore`, and `PlaceRating`.
- Save/edit rating UI exists: `PlaceRatingSlider` appears in Add and Map save/edit flows for `been` places only.
- Trusted aggregate exists: `recommended_score` and `recommended_count` return from `visible_places_in_view` and `profile_visible_places`.
- Flexible tags exist: place answers are already represented as `LocalPlaceAttribute` and parsed by `ProfileMetadataTagParser`.
- External actions exist: `PlaceExternalLinks` already builds Directions, Website, Call, Reserve, Order, Menu, and Share URLs when the local place has enough data.
- OpenAI exists only in `supabase/functions/extraction-worker` for category classification. It sends approved place metadata only, uses `store: false`, and is not a fit-scoring system.

### Minimum Complete Change

Do not rebuild ratings. The next implementation should reuse the landed rating contract and add a shared place-profile presentation layer:

```text
VisiblePlace + same-place saves + current user
    |
    v
PlaceProfilePresentation
    |-- place metadata: title, city line, address/details, action availability
    |-- save state: saved by you, unsaved with signal, unsaved thin signal
    |-- actual rating: own rating or trusted aggregate
    |-- fit rating: deterministic v1 only when evidence is strong enough
    |-- common tags: repeated structured answer attributes
    |-- trusted notes: visible same-place saves
    |
    +--> Map preview card
    +--> Full place profile
    +--> Discover/profile entry points
```

Required implementation order:

1. Add/verify remote place metadata fields needed by the profile.
2. Add `PlaceProfilePresentation` and pure helpers for ratings, common tags, and fit evidence.
3. Build map preview and full profile from that presentation.
4. Route Map, Profile, and Discover through the shared presentation instead of maintaining separate detail implementations.
5. Add state-matrix tests and simulator screenshot QA.

### Complexity Check

This will touch more than eight files. That is a smell, but the current duplication means a tiny patch would preserve the problem. The right scope reduction is not "skip shared presentation"; it is "do not add OpenAI fit scoring, provider ratings, or a backend fit-score cache in the same pass."

Recommended scope:

- **PR 1:** data contract + presentation helpers + tests.
- **PR 2:** map preview + full profile UI using the helpers.
- **PR 3:** backend/cached fit score only if deterministic v1 proves valuable.

### Search Check

[Layer 1] Use the existing Supabase/Postgres RLS model. Supabase documents RLS policies as implicit `WHERE` filters on table access, and the rating RPCs use `security invoker`, so the current aggregate is not a security bypass by itself.

[Layer 1] Keep OpenAI out of fit scoring for now. The existing OpenAI integration is intentionally scoped to server-side extraction category classification. Extending it to personal notes, graph, or taste scoring is a new privacy/eval/cost surface.

### TODOS Cross-Reference

`TODOS.md` already has "Add richer place-profile external actions when data exists" and "Build richer share/deep-link surface later." The new profile plan should not pull web share pages into this pass. It should, however, add a concrete place-profile data-contract TODO if the remote metadata fields are deferred.

### Completeness Check

The complete version for this phase is a shared presentation model with all four product states represented. A shortcut that only edits `PlaceSheet` will leave Discover/Profile divergent and will make ratings/tags drift immediately.

### Distribution Check

No new artifact type. This is app and Supabase contract work. If the implementation changes RPC return fields, the migration must be applied before a TestFlight build that depends on those fields.

## Architecture Review

1. `[P1] (confidence: 9/10) Wander/Services/Remote/SupabaseDTOs.swift:34 — Remote visible places do not hydrate address, locality, region, website, phone, or action links.`

   The design needs city-level hero metadata, lower full address, and Website/Call availability. The current RPC and DTO return only name, category, coordinates, status, notes, ratings, and attributes. Any full profile opened from remote social/profile data will lack the metadata needed to avoid generic or wrong subtext.

   Recommendation: extend `visible_places_in_view` and `profile_visible_places` to return `address`, `locality`, `region`, `country`, `website_url`, `phone_number`, `action_links`, and `source_provider`, then decode them into `LocalPlace`.

2. `[P1] (confidence: 9/10) Wander/Features/Map/MapScreen.swift:2523 and Wander/Features/Discover/DiscoverScreen.swift:631 — Place details are duplicated across Map/Profile and Discover.`

   Ratings were added to existing sheets, but the redesign has enough state that duplication will create mismatched behavior. Discover currently has its own sheet, Map/Profile share `PlaceSheet`, and each computes facts/actions differently.

   Recommendation: introduce `PlaceProfilePresentation` plus shared preview/full views. Map/Profile/Discover should pass input data into the same presentation builder.

3. `[P1] (confidence: 8/10) /private/tmp/recme-design-review/place-profile-design-doc.md — Fit rating is specified as a product concept but has no implementation contract.`

   Actual ratings are now solved. Fit ratings are not. The plan should not call OpenAI with notes/social graph by default. A cheap deterministic v1 can use local high-rated saves, category affinity, common tag overlap, and trusted aggregate signal, then hide the numeric score when evidence is thin.

   Recommendation: add a pure `PlaceFitScorer` or equivalent helper with explicit inputs and a confidence threshold. No network, no LLM, no persisted cache in the first UI pass.

4. `[P2] (confidence: 8/10) supabase/migrations/20260624223000_rating_score_reset.sql:309 — Recommended aggregate semantics are broader than the selected row set.`

   The aggregate includes RLS-readable `been` ratings for the same place, not necessarily only the owners shown by the current filter or sheet list. That is acceptable if the UI labels it "trusted rating"; it is misleading if the UI implies the count exactly equals the displayed people row.

   Recommendation: define `actual rating` as "visible trusted `been` rating aggregate" and keep participant names/count text derived from the same-place saves actually loaded into the presentation.

5. `[P2] (confidence: 8/10) Wander/Features/Profile/ProfileScreen.swift:774 — Tag parsing exists, but common-tag aggregation does not.`

   The design needs "enough people are saying this" tags. Current code can parse tags from one save, but it does not count repeated attributes across same-place saves or apply the user's own + trusted threshold.

   Recommendation: add a pure `CommonPlaceTagSummary` helper over `[PlaceSaveSummary]`, using structured attributes only for v1.

## Code Quality Review

1. `[P1] (confidence: 9/10) Wander/Features/Profile/ProfileScreen.swift:995 — Profile rows hardcoded missing locality to "Los Angeles".`

   Remote visible places currently lack locality, so every remote non-locality row can display "Los Angeles" even if the place is elsewhere.

   Adjustment made in this branch: fallback now shows only the save status when locality is unavailable.

2. `[P2] (confidence: 8/10) Wander/Features/Map/MapScreen.swift:2997 and Wander/Features/Discover/DiscoverScreen.swift:873 — "Recommended" is displayed as a per-note fact chip.`

   Recommended is an aggregate rating, not a per-note answer. Repeating it inside each note card makes the rating look like that user specifically wrote "Recommended 4.5."

   Recommendation: move aggregate rating into the top-level rating strip in the new profile and remove it from per-save fact chips when the shared profile replaces these sheets.

3. `[P2] (confidence: 7/10) Wander/Features/Map/MapScreen.swift:2992 and DiscoverScreen.swift:868 — Legacy `rating_signal` display compatibility still leaks into facts.`

   This is acceptable for old local data, but the new profile should not build product language around `rating_signal`. `interest_signal` can appear for `wanna_go`; actual ratings should use numeric rating fields.

   Recommendation: keep legacy compatibility only in old sheets until they are replaced. Do not include `rating_signal` in `PlaceProfilePresentation` except as a backward-compatibility fallback.

## Test Review

```text
CODE PATHS                                                   USER FLOWS
[+] PlaceProfilePresentation                                [+] Map tap preview
  ├── [GAP] saved by current user                             ├── [GAP] unsaved with trusted rating: plus + share only
  ├── [GAP] unsaved with trusted signal                       ├── [GAP] unsaved thin signal: no fabricated ratings
  ├── [GAP] unsaved thin signal                               ├── [GAP] saved: edit + share, no unsaved badge
  ├── [GAP] city line without street address                  └── [GAP] preview tags horizontally scroll/fade
  ├── [GAP] address/details lower section
  └── [GAP] missing metadata fallback                       [+] Full place profile
                                                                 ├── [GAP] full saved state shows Fit + Actual + Your note
[+] Rating summary                                              ├── [GAP] full unsaved trusted state shows plus/share
  ├── [★★ TESTED] rating_score save/decode/persist              ├── [GAP] full unsaved thin state hides unavailable scores
  ├── [★★ TESTED] recommended_score/count decode                ├── [GAP] Directions/Website/Call row above Why it fits
  ├── [GAP] own actual rating vs trusted aggregate              └── [GAP] bottom tabs remain visible
  └── [GAP] aggregate count label semantics

[+] Fit scoring                                               [+] Save/edit rating
  ├── [GAP] high evidence returns 0-10 score                    ├── [★★★ TESTED] Been saves rating 1...5
  ├── [GAP] thin evidence returns nil/no score                  ├── [★★★ TESTED] Wanna go omits rating
  ├── [GAP] category affinity                                  └── [GAP] edited rating updates full profile actual rating
  └── [GAP] tag overlap

[+] Common tags                                               [+] Remote/social data
  ├── [GAP] user + one trusted match includes tag               ├── [GAP] remote row with locality displays city
  ├── [GAP] two trusted matches include tag                     ├── [GAP] remote row without locality does not lie
  ├── [GAP] one isolated tag excluded                           └── [GAP] Website/Call hidden unless hydrated
  └── [GAP] repeated tags sorted by count/relevance

COVERAGE: 6/31 paths tested (19%)
QUALITY: ★★★:2 ★★:2 ★:2 | GAPS: 25
```

Required tests before implementation is called complete:

- `PlaceProfilePresentationTests`: state matrix for saved, unsaved trusted, unsaved thin, metadata fallback, action availability.
- `PlaceFitScorerTests`: deterministic score, nil when thin evidence, category affinity, tag overlap, trusted signal weight.
- `CommonPlaceTagSummaryTests`: user+trusted, two trusted, no singletons, sorted output, malformed attribute JSON ignored.
- `RemoteRepositoryTests`: extended DTO fields decode into `LocalPlace`.
- SQL test: visible/profile RPCs return the place metadata fields needed by the profile.
- UI/simulator QA: iPhone 16 Plus and a smaller iPhone screenshot pass for preview and full profile states.

## Performance Review

1. `[P2] (confidence: 8/10) Fit/common-tag computation can become expensive if it is recomputed ad hoc in views.`

   The current rating aggregate is server-side and uses CTEs, not per-row correlated fetches. Keep the new profile equally boring: compute presentation once per selected place from already-loaded places/saves/attributes, and avoid per-open OpenAI calls or network fetches.

   Recommendation: pure helpers over local arrays for v1; backend cache only after product value is proven.

## Data Contract Recommendation

```swift
struct PlaceProfilePresentation {
    let placeID: String
    let title: String
    let heroMetadata: String?
    let detailsAddress: String?
    let category: String
    let sourceProvider: String?
    let saveState: SaveState
    let actions: [PlaceExternalAction]
    let actualRating: ActualRating?
    let fitRating: FitRating?
    let commonTags: [CommonTag]
    let whyItFits: [FitReason]
    let ownSave: PlaceSaveSummary?
    let trustedSaves: [PlaceSaveSummary]
}
```

```text
ActualRating
  ├── own: user_places.rating_score for saved-by-you
  └── trusted: recommended_score/count for unsaved or social aggregate

FitRating
  ├── score: 0...10, one decimal
  ├── confidence: enoughEvidence | thinEvidence
  └── reasons: tag/category/trusted-signal evidence
```

## State Matrix

| State | Top action | Rating strip | Note section | Tags | Details |
|---|---|---|---|---|---|
| Preview unsaved trusted | plus + share | trusted actual if available; fit if confident | no full note body | truncated horizontal | no full address |
| Full saved by you | edit + share | fit + own actual rating | `Your note`, rating, tags, privacy/status | full horizontal | full address/source |
| Full unsaved trusted | plus + share | fit + trusted actual rating | empty `Your note` prompt | common tags | full address/source |
| Full unsaved thin | plus + share | quiet empty rating state | empty `Your note` prompt | category/location fallback only | full address/source if available |

## NOT In Scope

- OpenAI fit scoring over notes, graph, or taste profile.
- Public Yelp/Google/provider ratings.
- Backend materialized fit-score cache.
- Shareable web/deep-link place pages.
- LLM note parsing for common tags.
- Paid place metadata APIs.

## Decision Batch

1. **Remote metadata contract:** recommended `A` — extend RPC/DTO now before building full profile. `B` is defer and accept degraded/missing city/actions.
2. **Fit rating v1:** recommended `A` — deterministic local score with nil when evidence is thin. `B` is backend cache now. `C` is OpenAI scoring now.
3. **Actual rating semantics:** recommended `A` — actual rating means explicit human ratings; saved shows own rating, unsaved shows RLS-visible trusted aggregate. Do not mix with fit.
4. **Common tags source:** recommended `A` — structured attributes only. Defer note parsing and LLM extraction.

## Failure Modes

| Path | Failure | Test | Handling/User Impact |
|---|---|---|---|
| Remote metadata | Full profile shows wrong city or hides Website/Call forever | Required DTO/RPC tests | Add metadata fields, hide missing actions |
| Shared presentation | Map and Discover show different state/action semantics | Required presentation tests | Single builder feeds both |
| Fit rating | Thin evidence fabricates precision | Required scorer tests | Return nil and show quiet empty state |
| Common tags | One person's random tag appears as common truth | Required tag summary tests | Threshold user+trusted or two trusted |
| Rating labels | Count implies exact visible people but aggregate is broader | Required presentation tests | Separate trusted aggregate from visible save labels |
| OpenAI | Private notes/social graph sent without contract | Not in scope | No LLM call in v1 fit/tag path |

Critical gap: full profile cannot meet the design from remote social/profile rows until place metadata fields are returned and decoded.

## Worktree Parallelization

| Step | Modules touched | Depends on |
|---|---|---|
| Remote metadata contract | `supabase/migrations`, `supabase/tests`, `Wander/Services/Remote`, `Wander/Models` | — |
| Presentation helpers | `Wander/Models` or `Wander/Services`, `WanderTests` | Remote metadata shape |
| Full/preview UI | `Wander/Features/Map`, `Wander/Features/Profile`, `Wander/Features/Discover` | Presentation helpers |
| Fit/common-tag scoring | `Wander/Services`, `WanderTests` | Presentation inputs |

Parallel lanes:

- Lane A: remote metadata contract.
- Lane B: pure fit/common-tag helper design can start after input structs are named.
- Lane C: UI should wait for presentation helpers to avoid duplicating logic.

Execution order: A first, B can overlap lightly, C last. Avoid parallel edits to `MapScreen.swift`.

## Completion Summary

- Step 0: Scope Challenge — scope reduced to reuse landed ratings, add shared presentation, defer OpenAI/provider/cache work.
- Architecture Review: 5 issues found.
- Code Quality Review: 3 issues found, 1 low-risk fix made.
- Test Review: diagram produced, 25 gaps identified.
- Performance Review: 1 issue found.
- NOT in scope: written.
- What already exists: written.
- TODOS.md updates: 1 candidate, remote metadata contract if deferred.
- Failure modes: 1 critical gap flagged.
- Outside voice: skipped.
- Parallelization: 3 lanes, 2 can overlap lightly, UI sequential after presentation.
- Lake Score: 4/4 recommendations chose complete option for this phase.
