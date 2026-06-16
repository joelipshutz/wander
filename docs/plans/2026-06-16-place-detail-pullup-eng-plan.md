# Place Detail Pull-Up Engineering Plan

Date: 2026-06-16
Branch: `codex/place-detail-eng-plan`
Status: Eng plan complete, implementation not started

## Summary

Build one full-height map place detail sheet that works for saved places and unsaved MapKit search results. The sheet should feel closer to the Bali screenshot: strong title, place tags, save/edit, share, website, call, reserve/order when trustworthy, directions, personal metadata for saved places, and social notes at the bottom when followed people have saved the same place.

Recommended scope: provider-light v1. Use MapKit and directly captured URLs first. Do not add paid Google/Yelp place metadata or partner ordering APIs in this pass.

## Sources Checked

- Local SDK: `MKMapItem` exposes `phoneNumber`, `url`, `timeZone`, and `pointOfInterestCategory`; it does not expose public rating/review count fields in the installed SDK headers.
- Google Place Details can return phone, ratings, reviews, and website, but requires field masks and bills phone/rating/website at Place Details Enterprise; reviews/review summaries are Enterprise + Atmosphere. See [Google Place Details fields](https://developers.google.com/maps/documentation/places/web-service/place-details) and [Google Places usage/billing](https://developers.google.com/maps/documentation/places/web-service/usage-and-billing).
- Google Maps URLs support keyless search and directions URLs with `api=1`. See [Google Maps URLs](https://developers.google.com/maps/documentation/urls/get-started).
- DoorDash Marketplace APIs are limited-access and "not yet generally available", so they should not be treated as a free structured order integration. See [DoorDash Marketplace overview](https://developer.doordash.com/en-US/docs/marketplace/overview/).
- OpenTable supports consumer discovery/reservation flows through web/app, but not a simple public API in the docs checked. See [OpenTable consumer discovery/reservations](https://www.opentable.com/).

## Product Rules

- Saved and unsaved map places both slide to the same full detail surface.
- Saved places show personal metadata: status, visibility, note, rating signal, and saved answer attributes.
- Unsaved places show all available business metadata from the candidate: name, category, address, website, phone, directions, share, save.
- Social notes live at the bottom of the expanded sheet. For unsaved places, show social notes when the candidate matches a visible saved place from someone followed.
- Do not show empty business fields. Missing data means the action is absent.
- "Order" or "Reserve" can appear only when backed by a direct URL from MapKit, user-captured data, backend extraction, or a verified provider link.
- Provider search fallbacks must be labeled honestly, for example "Find delivery" or "Find reservations", not "Order now" or "Reserve", because the app has not verified availability.

## What Already Exists

- `Wander/Features/Map/MapScreen.swift` already has a saved `PlaceSheet` with compact/expanded states, a drag gesture, sharing, directions, "your save", and "friends' notes".
- `Wander/Features/Map/MapScreen.swift` has a separate `SearchCandidateSheet` for unsaved MapKit results, but it is compact only and cannot expand.
- `Wander/Features/Discover/DiscoverScreen.swift` has another detail sheet with overlapping external action/fact/share logic.
- `Wander/Services/PlaceExternalLinks.swift` already centralizes Google Maps directions/search/share URLs.
- `PlaceCandidate` and `LocalPlace` already carry place name/category/address/locality/coordinates/provider IDs, but not website/phone/action URLs.
- `LocalUserPlace` plus `LocalPlaceAttribute` already store personal metadata and flexible saved answers.

## Not In Scope

- Paid Google Places, Yelp, DoorDash, Resy, or OpenTable API integrations.
- Public Google/Yelp star ratings, review counts, reviews, summaries, hours, price level, photos, or popular dishes.
- Scraping restaurant websites or provider sites for order/reservation links.
- Building an in-app checkout, reservation booking, menu browsing, or delivery availability flow.
- Reworking Discover detail UI, unless implementation decides to extract shared helpers with no extra user-facing scope.
- Supabase schema changes for remote provider metadata in this pass.

## Step 0 Scope Challenge

Minimum complete change:

1. Replace the map-only unsaved `SearchCandidateSheet` with the same expanded-detail capability used for saved places.
2. Add provider-light business metadata fields to `PlaceCandidate` and `LocalPlace`.
3. Populate those fields from MapKit where available.
4. Persist metadata when saving a candidate so the saved sheet does not regress after save.
5. Render a single action row from available actions.
6. Keep social notes at the bottom and allow them for unsaved matching candidates.

Complexity smell:

- A broad implementation could touch 10+ files if it tries to update map, add, discover, Supabase DTOs, migrations, fixtures, and visual tests at once.
- Recommended cut: map sheet and local metadata only in this pass. Leave remote schema/provider APIs and Discover polish for follow-up.

Layer call:

- [Layer 1] Use MapKit `MKMapItem` built-ins for website/phone/time zone rather than adding a metadata provider.
- [Layer 1] Use `tel:` and keyless map/provider web URLs rather than partner APIs.
- [Layer 3] Avoid pretending search fallbacks are exact commerce actions. Trust is more important than a shiny button.

## Architecture

### Data Model

Add lightweight metadata to the existing place models:

```swift
struct PlaceCandidate {
    var websiteURLString: String?
    var phoneNumber: String?
    var timeZoneIdentifier: String?
    var actionLinksJSON: String?
}

final class LocalPlace {
    var websiteURLString: String?
    var phoneNumber: String?
    var timeZoneIdentifier: String?
    var actionLinksJSON: String?
}
```

`actionLinksJSON` stores a small codable array for exact externally captured actions:

```swift
struct PlaceActionLink: Codable, Equatable {
    enum Kind: String, Codable { case website, order, reserve, menu }
    enum Source: String, Codable { case mapkit, userCaptured, backendExtraction, providerSearch }
    enum Confidence: String, Codable { case exact, search }

    var kind: Kind
    var title: String
    var urlString: String
    var source: Source
    var confidence: Confidence
}
```

Rendering rule:

- `confidence == .exact` can render as "Order" or "Reserve".
- `confidence == .search` renders as "Find delivery" or "Find reservations".
- `providerSearch` links are never persisted as if they are exact facts about the place.

### UI Composition

Introduce a map-local `PlaceDetailPresentation` value that normalizes saved and unsaved inputs.

```text
Map selection
  |
  +-- saved VisiblePlace ----------------------+
  |                                            |
  +-- unsaved PlaceCandidate -- match visible? +--> PlaceDetailPresentation
                                               |
                                               v
                                  PlaceDetailSheet
                                   - compact header
                                   - expanded header
                                   - action row
                                   - tags/facts
                                   - your save, if any
                                   - social notes, bottom
```

This avoids rebuilding the same sheet twice. It also lets the unsaved state inherit social notes when `visiblePlace(matching:)` finds a friend/followed save.

### External Actions

Render actions in this order:

1. Save/Edit bookmark
2. Share
3. Website, when `websiteURLString` is valid
4. Call, when `phoneNumber` can form a safe `tel:` URL
5. Order/Reserve, only when an exact action link exists
6. Find delivery/Find reservations, optional restaurant-only search fallback
7. Directions

`PlaceExternalLinks` should own URL creation and filtering:

- `websiteURL(from:)`
- `callURL(phoneNumber:)`
- `googleMapsDirectionsURL(...)`
- `googleMapsSearchURL(...)`
- `providerSearchURL(provider:query:locality:)`
- `visibleActions(for:)`

### Ratings

Do not add Google/Yelp public ratings in v1.

Show Wander-native signals instead:

- Current user's `ratingSignal` in the personal metadata section.
- Friend/followed `ratingSignal` in social notes.
- Optional aggregate copy such as "Saved by 3 people you follow" if already derivable from `saves`.

If public ratings become necessary later, add a separate provider-backed feature flag with server caching, attribution, budget caps, and policy review.

## Review Findings

1. [P1] Saved and unsaved sheets diverge today.
   - Evidence: `SearchCandidateSheet` is compact-only while `PlaceSheet` has expanded content, actions, personal metadata, and social notes.
   - Recommendation: replace `SearchCandidateSheet` with the unified map `PlaceDetailSheet` presentation path.

2. [P1] MapKit already gives some requested metadata, but the app discards it.
   - Evidence: `MapKitPlaceResolver.mapItems` and `MapScreen.mapKitCandidates(from:)` build `PlaceCandidate` without `item.url`, `item.phoneNumber`, or `item.timeZone`.
   - Recommendation: capture MapKit website/phone/time zone into `PlaceCandidate` and persist on save.

3. [P2] External action logic will duplicate unless centralized.
   - Evidence: Map and Discover both compute directions/share URLs separately, while `PlaceExternalLinks` only handles maps links today.
   - Recommendation: put all action URL construction and safety checks in `PlaceExternalLinks`.

4. [P2] Order/reserve labels can mislead if powered by a provider search.
   - Evidence: DoorDash structured marketplace integration is limited-access, and OpenTable/Resy exact availability was not available through a simple public API check.
   - Recommendation: exact URLs get direct commerce labels; generic provider searches get "Find ..." labels.

5. [P2] Saving a candidate can drop newly captured metadata unless the store path is updated.
   - Evidence: `WanderLocalStore.upsertPlace(from:)` currently maps the existing `PlaceCandidate` fields only.
   - Recommendation: update create and update paths so metadata is persisted without overwriting existing non-empty fields with nil.

## Test Coverage Diagram

```text
CODE PATHS                                      USER FLOWS
[+] PlaceCandidate metadata fields              [+] Unsaved map POI detail
  |-- [GAP] map search result has URL/phone        |-- [GAP] sheet opens compact
  |-- [GAP] current/manual resolver maps fields    |-- [GAP] drag expands full detail
  |-- [GAP] nil fields hide actions                |-- [GAP] save CTA remains available
                                                  |-- [GAP] social notes appear at bottom

[+] LocalPlace persistence                       [+] Saved map place detail
  |-- [GAP] new save keeps website/phone           |-- [GAP] personal metadata visible
  |-- [GAP] existing place update preserves data   |-- [GAP] business actions visible only when valid
  |-- [GAP] persistence round-trip keeps fields    |-- [GAP] share/directions still work

[+] PlaceExternalLinks                           [+] Order/reserve link-outs
  |-- [GAP] tel URL sanitizes phone                |-- [GAP] exact order link shows "Order"
  |-- [GAP] invalid URLs are hidden                |-- [GAP] search fallback shows "Find delivery"
  |-- [GAP] exact action vs search label           |-- [GAP] no action shown for non-restaurant/no URL
  |-- [GAP] provider search URL generation

COVERAGE NOW: 0/18 new paths tested
REQUIRED BEFORE IMPLEMENTATION COMPLETE: 18/18 new paths covered by unit tests, store tests, and simulator visual QA.
```

## Test Plan

Unit tests:

- Add tests for `PlaceExternalLinks.callURL(phoneNumber:)`: formatted numbers, punctuation, empty strings, invalid strings.
- Add tests for website URL validation: `https` accepted, invalid/empty hidden.
- Add tests for exact vs search action labeling: exact order/reserve show direct labels; provider search shows "Find ...".
- Add tests for provider search URL generation after each chosen provider URL pattern is manually verified in Safari.

Store tests:

- Saving a `PlaceCandidate` with website/phone/time zone persists those values to `LocalPlace`.
- Re-saving/updating a candidate with nil metadata does not erase existing non-empty `LocalPlace` metadata.
- Persistence snapshot round-trips new fields.
- Existing save metadata and answer attributes still render from `LocalUserPlace` and `LocalPlaceAttribute`.

Resolver tests:

- Extract the MKMapItem-to-PlaceCandidate mapping into a small helper if needed so URL/phone/time zone mapping can be unit tested without driving MapKit search.

UI/manual QA:

- On iPhone 16 Plus simulator, unsaved map search result opens compact, drags to full detail, shows Save, Share, Website/Call when data exists, Directions, and social notes at bottom when matched.
- On one smaller iPhone simulator, verify action chips do not overflow or overlap.
- Saved place still shows personal note, rating signal, answer tags, and friends' notes at the bottom.
- Place with no website/phone/order/reserve data shows no empty placeholders.

Required command:

```bash
xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

## Failure Modes

| Failure | Handling Required | Test Required |
|---|---|---|
| MapKit returns malformed website URL | Hide Website action | URL validation unit test |
| MapKit returns decorative phone text | Hide Call unless safe `tel:` can be formed | Phone sanitizer unit test |
| Provider search resolves to wrong restaurant | Label as "Find", never "Order" or "Reserve" | Action labeling unit test |
| User saves candidate after metadata is shown | Persist metadata and keep actions after save | Store save test |
| Existing saved place receives a nil candidate update | Preserve existing metadata | Store update test |
| Unsaved candidate matches a social saved place | Show social notes at bottom, not above personal/action content | UI QA |
| No business data exists | Render no empty chips/placeholders | Unit plus UI QA |

No critical silent gap remains if these tests land with the implementation.

## Performance

- No network calls on sheet expansion in v1.
- MapKit search already happens upstream; the sheet only renders captured fields.
- Provider search links are generated locally and opened only on tap.
- Avoid precomputing provider search URLs for every map annotation; compute when the selected sheet renders.
- Keep action rows horizontally scrollable with stable button sizes to avoid layout churn.

## Worktree Parallelization

Sequential implementation is preferred. The core changes touch the same map/model/store surface, and parallel worktrees would likely conflict.

Possible order:

1. Data model and persistence.
2. External link helper tests.
3. MapKit mapping.
4. Unified map sheet UI.
5. Simulator QA and visual polish.

## Implementation Tasks

- [ ] T1 (P1, human: ~2h / CC: ~20min) - Models/store - Add provider-light business metadata to `PlaceCandidate`, `LocalPlace`, persistence snapshots, and `upsertPlace(from:)`.
  - Surfaced by: Findings 2 and 5.
  - Files: `Wander/Services/RepositoryProtocols.swift`, `Wander/Models/LocalModels.swift`, `Wander/Services/WanderStorePersistence.swift`, `Wander/Services/WanderLocalStore.swift`, `WanderTests/WanderStoreTests.swift`.
  - Verify: `xcodebuild test ...`

- [ ] T2 (P1, human: ~1h / CC: ~15min) - MapKit mapping - Preserve `MKMapItem.url`, `phoneNumber`, and `timeZone` in every candidate creation path.
  - Surfaced by: Finding 2.
  - Files: `Wander/Services/MapKitPlaceResolver.swift`, `Wander/Features/Map/MapScreen.swift`.
  - Verify: mapper/unit tests and manual MapKit search.

- [ ] T3 (P2, human: ~1.5h / CC: ~20min) - External actions - Expand `PlaceExternalLinks` into the single source for Website, Call, Directions, Share, exact Order/Reserve, and honest provider search fallbacks.
  - Surfaced by: Findings 3 and 4.
  - Files: `Wander/Services/PlaceExternalLinks.swift`, `WanderTests/PlaceExternalLinksTests.swift`.
  - Verify: unit tests for URL generation, validation, and labels.

- [ ] T4 (P1, human: ~3h / CC: ~40min) - Map UI - Replace `SearchCandidateSheet` with unified saved/unsaved `PlaceDetailSheet` presentation.
  - Surfaced by: Finding 1.
  - Files: `Wander/Features/Map/MapScreen.swift`.
  - Verify: simulator screenshots on iPhone 16 Plus and one smaller phone.

- [ ] T5 (P2, human: ~1h / CC: ~15min) - Social notes - Ensure unsaved matched candidates can show followed/friend notes at the bottom without requiring the current user to save first.
  - Surfaced by: Product rule.
  - Files: `Wander/Features/Map/MapScreen.swift`, possible store helper in `Wander/Services/WanderLocalStore.swift`.
  - Verify: fixture-backed UI state or unit test for matching candidate to visible social saves.

## Implementation Defaults

- Ship exact Order/Reserve links when the place has a direct provider/place URL.
- Do not hardcode generic provider search fallbacks until each URL pattern is manually verified in Safari during implementation.
- If verified provider search fallbacks land, include DoorDash/OpenTable/Resy first and label them "Find delivery" or "Find reservations".
- Show "Call" for any category when MapKit provides a safe phone number, because venues, stores, parks, and hotels can all have useful phone contacts.
- Show "Find delivery" only for food/drink categories such as `restaurant`, `coffee`, `bakery`, and `bar`; hide it for hikes, parks, viewpoints, and non-food places.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | not run | Optional; this is a user-facing expansion but within existing product direction. |
| Codex Review | `/codex review` | Independent 2nd opinion | 0 | not run | Not needed until implementation diff exists. |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | issues folded into plan | 5 findings, 0 critical silent gaps after planned tests. |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | recommended after implementation | The change is visual and should get simulator/design review before ship. |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | not needed | No developer-facing product surface. |

- VERDICT: ENG PLAN READY TO IMPLEMENT after branch is updated from latest `origin/main`; design review recommended after the first UI pass.
NO UNRESOLVED DECISIONS
