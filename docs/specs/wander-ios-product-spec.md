# rec.me iOS Product Spec

Public product name: `rec.me`. Internal repo paths and historical product
language may still use `Wander` where changing them would create migration or
coordination risk.

Date: 2026-05-29
Status: Draft v0.1
Review mode: plan-ceo-review / Scope Expansion
Project root: `/Users/joelipshutz/Developer/Wander (nametbd)`

## Sources

- Conversation archive: [docs/source/wander-conversation-2026-05-29.md](../source/wander-conversation-2026-05-29.md)
- Design handoff source: [preview/follow-profile-settings-mocks](../../preview/follow-profile-settings-mocks)
- Canonical design tokens: [preview/follow-profile-settings-mocks/tokens.css](../../preview/follow-profile-settings-mocks/tokens.css)
- Design-system reference: [preview/follow-profile-settings-mocks/index.html](../../preview/follow-profile-settings-mocks/index.html)
- Annotated screen mocks: [preview/follow-profile-settings-mocks/screens.html](../../preview/follow-profile-settings-mocks/screens.html)
- Handoff IA feedback: [preview/follow-profile-settings-mocks/wander-ia-feedback.md](../../preview/follow-profile-settings-mocks/wander-ia-feedback.md)
- Original mock PDF: [docs/source/wander-mocks.pdf](../source/wander-mocks.pdf)
- Original mock page renders: [docs/source/wander-mocks-pages](../source/wander-mocks-pages)
- Deferred work: [TODOS.md](../../TODOS.md)
- Search and Featured retrieval platform: [docs/specs/search-featured-retrieval-platform.md](search-featured-retrieval-platform.md)
- Slate reference app: `/Users/joelipshutz/Developer/Slate`
- Competitive references:
  - Mapstr: https://en.mapstr.com/
  - Swarm check-ins: https://support.foursquare.com/hc/en-us/articles/21181809706012-Swarm-check-ins
  - Beli App Store story: https://apps.apple.com/us/iphone/story/id1847489749

## Executive Summary

rec.me is a native iOS social map for remembering places worth returning to and discovering places through trusted people.

North Star:

> When I need a place, rec.me shows me where my trusted people have actually been, what they thought, and whether it fits the moment.

Sharper wedge:

> rec.me turns trusted people's place memories into a searchable map you can actually use.

Positioning:

> Your people's map of places worth knowing.

The core loop is:

```text
capture a place -> mark been or wanna go -> answer a few useful questions -> see it on your map -> discover through people you follow
```

Primary magic moment:

```text
I am looking for something, and my people's map has the answer.
```

Capture is the supply engine. Discovery is the moment users feel the network value.

This is not a lists app. Lists were explicitly removed from the product direction. The map is the primary memory surface, and "smart filters" replace manual list-making.

The product should feel like a sharp, warm travel buddy: informal, useful, and low-friction, without sounding gimmicky.

## Product Bet

The market already has:
- Mapstr: personal place maps, tags, sharing, imports.
- Swarm: check-ins, private/public check-ins, historical place map.
- Beli: trusted friend recommendations and lightweight structured restaurant memory.
- Wispy-style entrants: real-time social presence around places.

Wander should not compete by being "another map of pins." The product wedge is trusted cross-category place discovery from people the user actually knows, powered by low-friction capture.

Design and engineering should preserve five product constraints:

1. Trusted people are the discovery layer, not anonymous strangers.
2. Cross-category place memory matters more than restaurant-only ranking.
3. Capture must be easy enough that the map actually gets built.
4. Privacy is part of the wedge: no live location sharing, no accidental broadcasting.
5. Extraction is not the wedge by itself. It is the moat around capture, reducing the work required to build useful place memory.

Avoid these crowded frames:
- "Check-in app" because Swarm already owns that mental model.
- "Lists app" because lists were removed and Mapstr already owns that behavior.
- "Travel app" because Wander should work for everyday local discovery, not only trips.

## Stack Baseline

Use Slate's native iOS stack as the baseline:

- Swift 5.9+
- SwiftUI
- iOS 17+
- SwiftData for local persistence and offline-first UX
- MapKit and CoreLocation
- PhotosUI for image/photo import
- App Group/share extension patterns if we add share-sheet capture
- AI extraction service pattern from Slate, revised for Wander

Wander differs from Slate because social is core. The spec assumes a backend sync layer from the start.

## Backend Decision

Decision locked 2026-06-01: use Clerk + Supabase.

Responsibilities:

- Clerk owns identity, sessions, sign-in/sign-up, and account management.
- Supabase owns Postgres data, RLS, PostGIS map queries, storage, functions/RPCs, and realtime if needed.
- SwiftData owns local cache, guest-local drafts/saves, and the app-owned sync queue.
- Clerk users must be mirrored into Supabase `profiles` via webhook or equivalent backend process. Supabase RLS policies should key ownership and visibility to the Clerk user id from the session token.

Rejected alternatives:

- Supabase Auth + Supabase: simpler vendor surface, but Joe selected Clerk for identity/account polish and future web parity.
- Firebase Auth + Firestore: strong offline ergonomics, but more denormalization and Cloud Function work for follow graph, visibility, and map queries.
- Backend-neutral planning: no longer useful; schema, RLS tests, and sync contracts need a real target.

Implementation contracts:

- All social reads must pass through Supabase RLS policies, SQL views, or RPCs that enforce visibility and block rules.
- Client ViewModels should not call Clerk or Supabase directly; use repository/protocol boundaries so fake data and UI tests can run without network.
- Guest-local records cannot appear in social surfaces until a Clerk user signs in and the sync queue claims/migrates those records.
- Supabase profile rows should store handle, display name, avatar, bio, default visibility, and search fields derived from Clerk/user settings.
- v0.1 sync conflicts should use simple `updated_at`/server-wins handling plus a local retry queue. Multi-device field-level merge is out of scope.
- Analytics should be implemented behind a vendor-neutral interface so event names are stable before the provider is chosen.

## Scope

### In Scope For v0.1 Spec

- Map-first iOS app.
- Four bottom-nav surfaces: map, add (+), discover, profile.
- Settings as a required nested surface opened from the Profile gear.
- Multi-select map filters for you/social and been/wanna go.
- Place capture from current location, manual entry, link, and photo.
- Contextual question templates for starter categories.
- User-added custom tags per place.
- Follow graph with mutual follows treated as "friends."
- User profiles with followers/following lists and block controls.
- Privacy-first sharing defaults.
- Follow-based discovery and smart filters.
- LLM-assisted Discover query parsing into structured filters.
- Clerk + Supabase social data model.
- Extraction architecture based on Slate, with explicit improvements.
- Vendor-neutral analytics event interface.

### Not In Scope

- Manual user-created lists.
- Public global community feed.
- Live location sharing.
- Real-time "who is here now" presence.
- Ranking people, mayorships, streaks, badges, or gamified check-ins.
- Fully customizable question-schema builder.
- Full trip itinerary generation.
- Payment or subscription model.
- Share extension in v0.1; track as a later TODO after the in-app add/map/social loop works.
- Native Contacts permission in v0.1; planned later after the core graph loop, backend matching, privacy copy, and App Store disclosure are ready.
- Private profiles or follow requests in v0.1.
- iPad-specific layouts beyond phone-compatible behavior.
- Additional design variant generation as a blocker to engineering.
- Final production onboarding implementation; the planning research flow is in `research/screensdesign/2026-05-30-social-map-onboarding/`.
- Following someone who is not yet on Wander.
- Sending friend graph, place data, or private user context to the LLM Discover parser.

## Information Architecture

Bottom navigation:

```text
map        add (+)        discover        profile
```

No `your world` / `social world` grouping labels. The former `you` surface is folded into Profile. The plus is an inline terracotta-accented `add (+)` tab, not a raised center FAB.

### Map

The map is the default/home surface.

Primary jobs:
- Show places near the user or current viewport.
- Let the user switch between their own places and visible social places.
- Let the user switch between been and wanna go.
- Let the user tap a pin to inspect why it matters.
- Let the user save a visible social place into their own map.

### Add

The capture surface.

Primary jobs:
- Add from current location.
- Paste a link.
- Add manually.
- Add from a photo.
- Confirm the resolved place.
- Answer contextual questions.
- Save as been or wanna go.

### Discover

The social discovery and profile lookup surface.

Primary jobs:
- Search by place, vibe, category, area, contact, or username.
- Browse profiles, followers, and following.
- Use smart filters like "hikes in LA", "coffee eastside", "patio bars", "work-friendly cafes".
- Save visible social places into the user's own map.

### Profile

The merged personal place memory and self-profile surface.

Primary jobs:
- Show the owner's identity header, avatar, handle/city, bio, edit action, and settings gear.
- Review saved places and unresolved drafts.
- Filter by category, city, status, recency, attributes, and custom tags.
- Edit place attributes and change visibility.
- See capture/extraction status for unresolved places.
- View followers and following.
- Show been/wanna/friends stats, monthly recap, and recent check-ins.
- Render role-based content for other viewers: owner sees all; followers see follower-visible places; mutuals also see friend-visible places; non-followers see only the gated shell.

### Settings

The account, privacy, and safety surface. Settings is required, but it should be opened from a gear in Profile rather than taking a fifth bottom-tab slot.

Primary jobs:
- Edit account/profile basics.
- Set default place visibility.
- Manage blocked users.
- Manage Contacts permission/status.
- Manage notification preferences.
- Sign out/delete account later.

## Map Pin System

From mocks:

| Owner | Status | Pin Style |
|---|---|---|
| You | Been | Solid terracotta |
| You | Wanna go | Dashed terracotta |
| Social | Been | Solid sky |
| Social | Wanna go | Dashed sky |

Rules:
- Filters are multi-select.
- Up to four states can show at once.
- If too many pins overlap, cluster by owner/status and expose a breakdown.
- Recency can later become a fifth dimension using opacity or tone.
- Tapping a mixed cluster should open a sheet grouped by "you", "following/friends", "been", and "wanna go".

## Core Objects

### User

```text
User
  id (Clerk user id / subject)
  display_name
  handle
  avatar
  bio optional
  home_area optional
  default_place_visibility: followers | mutuals | self
  created_at
  updated_at
```

Rules:
- Handle is required at auth/profile creation.
- Handle is unique case-insensitive.
- Handle can be edited later, but handle history and redirects are out of scope for v0.1.
- Username/handle search should be exact or near-exact, not broad global people discovery.

### Follow

Follow graph is the baseline. "Friends" means mutual follows.

```text
Follow
  id
  follower_user_id
  followed_user_id
  source: username | contacts | profile | invite_link_future
  created_at
  updated_at
```

Rules:
- Following is one-way.
- Mutual follows are treated as "friends" for visibility and product copy.
- Unfollow revokes future access to follower-visible content.
- If a mutual follow becomes one-way, mutual-only content is no longer visible.
- Block prevents search, follow, profile viewing, and visibility in either direction.
- No follow requests in v0.1 unless private profiles are explicitly added later.

### Block

```text
Block
  id
  blocker_user_id
  blocked_user_id
  created_at
```

Rules:
- Blocked users cannot find each other by username or contacts.
- Blocked users cannot view each other's profiles or visible places.
- Blocked users are removed from follower/following lists from each user's perspective.
- Blocking should also remove any existing follow edges between the two users.

### Place

Canonical place record, potentially shared by many users.

```text
Place
  id
  canonical_name
  category
  address
  locality
  region
  country
  latitude
  longitude
  source_provider
  source_provider_place_id optional
  confidence
  created_at
  updated_at
```

### UserPlace

The user's relationship to a place.

```text
UserPlace
  id
  user_id
  place_id
  status: been | wanna_go
  note
  rating_signal optional
  visibility: followers | mutuals | self
  nearby_confirmed: boolean
  visited_at optional
  saved_at
  source_type: current_location | link | manual | photo | social_save
  source_artifact_id optional
  created_at
  updated_at
```

### PlaceAttribute

Structured answers from contextual questions.

```text
PlaceAttribute
  id
  user_place_id
  question_key
  value_type: scale | boolean | enum | multi_tag | text
  value
  created_at
  updated_at
```

### SourceArtifact

Raw-ish input reference for extraction/debugging.

```text
SourceArtifact
  id
  user_id
  type: url | image | text | current_location
  original_input
  normalized_input
  local_asset_ref optional
  remote_asset_ref optional
  created_at
  deleted_at optional
```

Retention rules:
- If the user deletes a saved place, remove the active `UserPlace`, related active source artifacts, and social visibility from product surfaces.
- Keep only a minimal server tombstone if needed for sync conflict resolution.
- Do not retain raw source artifacts solely for extraction debugging unless the user still has an active draft/place that uses them.

### ExtractionJob

Tracks extraction status and confidence.

```text
ExtractionJob
  id
  source_artifact_id
  status: pending | running | needs_confirmation | complete | failed | no_place_found
  provider_steps_json
  extracted_candidates_json
  selected_place_id optional
  confidence
  error_code optional
  error_message optional
  created_at
  updated_at
```

## Follow Graph, Profiles, And Discovery

Decision locked 2026-06-01: Wander uses a Strava-style follow graph, not a mutual friend-request graph.

Decision refinement locked 2026-06-01:
- Open follow for v0.1. Anyone discoverable through allowed search paths can be followed immediately.
- No private-profile approval flow in v0.1.
- Blocking is the v0.1 safety valve.

Definitions:
- **Following:** people I follow.
- **Followers:** people who follow me.
- **Friends:** mutual follows, meaning people I follow who also follow me back.
- **Everyone visibility:** visible to my followers. This is not a global public feed in v0.1.
- **Friends visibility:** visible only to mutual follows.
- **Self visibility:** only me.

### Follow Discovery

Users can find people only through:
- Contacts, when Contacts integration is enabled.
- Username/handle search.
- Tapping an existing visible attribution/profile link.

Not in v0.1:
- Global people directory.
- Suggested users from strangers.
- Public creator/expert browse.
- Following someone not on Wander. The data model should leave room for contact candidates or invite links later, but production v0.1 should not pretend a non-user can be followed.

### Contact Search Contract

Contacts should be treated as a matching source, not as the graph itself.

Decision locked 2026-06-01: native Contacts is planned, but not in v0.1. v0.1 should build the contacts-first UI against `FakeContactProvider` plus username search, then add native Contacts behind the same provider contract once backend hash matching, privacy copy, App Store disclosure, and contact-import QA are ready.

```text
ContactProvider
  -> returns local contacts with display name + phone/email hashes
  -> backend matches hashes to existing Wander users
  -> UI groups results:
       1. Contacts already on Wander
       2. Contacts not on Wander, disabled or future invite state
       3. Already following / follows you / mutual
```

Rules:
- Never upload raw phone numbers or emails if a salted hash/matching flow can satisfy the backend design.
- Show a pre-prompt before the native Contacts permission: "Find people you know on Wander. We only use contacts to help you connect."
- If Contacts is denied, show username search immediately.
- Contacts import should not be required to complete onboarding or use the map.
- Contact match does not auto-follow or expose anyone's map.
- Inviting/following a non-user is deferred. If shown, it must be a clearly disabled/future state or a plain share action, not a fake follow.
- v0.1 ships with `FakeContactProvider` plus username search. A later planned release should add native Contacts once backend hash matching, privacy copy, and App Store disclosure language are ready.

### Testing Follow Graph Before Native Contacts Ships

If native Contacts is deferred, do not defer the social loop. Test with three layers:

1. Fake contact provider in the app.
   - Inject a deterministic `FakeContactProvider` in debug builds and UI tests.
   - Seed contacts like Ryan, Sofia, Andrew with known matched/unmatched states.
   - Exercise the exact contacts-first UI without requesting real Contacts permission.

2. Seeded backend follow graph.
   - Create test users and one-way/mutual follow edges in local/staging data.
   - Use the same `Follow`, `Block`, and `UserPlace` APIs the production app will use.
   - Validate visible social pins, profile views, follow/unfollow, block, and mutual-only visibility.

3. Username search fallback.
   - Seed handles for internal testing.
   - Validate exact/near-exact handle search, not broad global people discovery.

This lets the product validate social discovery while native Contacts permission, matching, and privacy copy are still being finalized.

### Follow Flow

```text
Contacts, username search, or visible profile link
  -> profile preview
  -> follow
  -> following edge created
  -> viewer can see that user's follower-visible places
  -> if the followed user follows back, both users are friends/mutuals
  -> mutual-only places unlock only when both follow edges exist
```

Profile preview should show:
- Display name.
- Handle.
- Avatar.
- Bio if present.
- Follower and following counts.
- Mutual/friend indicator if applicable.
- Follow/unfollow button.
- Block action.
- Only places visible to the current viewer.

### Profile Surface

Every user should have a profile because follow is now a primary interaction.

Profile jobs:
- See a person's visible places.
- Follow or unfollow.
- See whether they follow me back.
- View followers and following.
- Block if needed.
- Save one of their visible places to my map.

Profile place tabs:
- Been.
- Wanna go.
- Optional later: categories or map/list toggle.

Profile privacy rules:
- A non-follower sees a basic profile shell: name, handle, avatar, bio, and counts. No places are visible until they follow.
- A logged-out viewer sees only basic profile shell if auth allows it; no place data.
- A follower sees `followers` places.
- A mutual follow sees `followers` and `mutuals` places.
- The owner sees all places, including `self`.
- A blocked viewer sees nothing and cannot search the profile.

### Social Map Visibility

Social visibility does not mean live.

Rules:
- Live location is never shared.
- "Nearby confirmed" is a badge on a place, not a realtime presence signal.
- Normal places default to `followers`, with `mutuals` and `self` available before save.
- The UI uses "Everyone", "Friends", and "Self".
- Everyone helper copy: "People who follow you can see this."
- Internally, Everyone maps to `followers`, Friends maps to `mutuals`, and Self maps to `self`.
- `followers` does not mean globally searchable by every Wander user in v0.1.
- Friend/mutual visibility requires both users to follow each other.
- A place can be made `self` in the add flow before saving.
- Saves from another user should preserve attribution, for example "Saved from Ryan", if that attribution remains visible.
- If a user unfollows the owner, future access to follower-visible content is revoked.
- If a mutual relationship becomes one-way, mutual-only content is revoked.
- Existing derived saves remain in the saving user's map, but attribution can degrade to "saved from someone on Wander" if access is gone.

### Product Issues To Flag

1. **"Everyone" is dangerous copy.** If it means followers only, users may still read it as global public. Safer UI label is "Followers"; if we use "Everyone", show helper copy like "People who follow you can see this."
2. **Friends now depends on two follow edges.** Every visibility policy and UI state must compute mutuality, not rely on a separate friendship table.
3. **Profiles become mandatory.** A follow graph without profile pages feels broken because users need somewhere to follow, unfollow, inspect visible places, and block.
4. **Discovery can get spammy if username search is too broad.** Limit v0.1 people discovery to contacts, username/handle search, and visible profile links.
5. **Map pin taxonomy gets harder.** Visible social pins can come from one-way follows or mutual friends. The map should probably keep one social pin color and explain the relationship in the sheet, rather than adding another pin color dimension.

## Place Capture Flow

### Source Picker

From mocks:

```text
ADD A PLACE
where's it from?

1. i'm here right now
   use my location

2. paste a link
   instagram, tiktok, google maps, a blog

3. add manually
   name, address, a note

4. from a photo
   we'll read the location
```

### Confirmation Flow

Every source resolves into the same confirmation model:

```text
Source input
  -> extraction/resolution
  -> candidate place(s)
  -> user confirms or edits
  -> choose been/wanna go
  -> answer contextual questions
  -> save
```

Do not auto-save low-confidence extraction as a complete place. Use `needs_confirmation`.

### Been vs Wanna Go

Status is not proof of presence.

Rules:
- User can mark any place as been or wanna go.
- If the user is physically nearby at capture time, add `nearby_confirmed = true`.
- If not nearby, save without the badge.
- The UI should avoid moralizing. It is a memory tool, not a surveillance product.

## Contextual Questions

Use a template system:

```text
CategoryTemplate
  category
  question_blocks[]

QuestionBlock
  key
  prompt
  type: emoji_scale | single_choice | multi_tag | price_scale | text
  options[]
```

Starter categories:
- Coffee shop
- Restaurant
- Hike
- Bar
- Park/nature
- Wellness
- Work-friendly cafe
- Event/pop-up

Rules:
- Each category ships with defaults.
- Users can add custom tags per place.
- Custom tags should be saved as user-level suggestions for future entries.
- Do not ship a full schema editor in v0.1.

### Template Examples

Coffee shop:
- How's the coffee? Emoji scale
- Good for working? yes / sometimes / nope
- Vibe tags: wifi solid, outlets, quiet, cute, outdoor seats, cash only, food on point, dog friendly

Hike:
- How strenuous? easy / moderate / hard / type 2 fun
- Dog friendly? yes / on leash / no
- What will you see? ocean view, waterfall, shade, wildflowers, scramble, loop trail, exposed, crowded

Restaurant:
- How was the food? Emoji scale
- Best for: date night, group, solo, kid friendly, quick lunch, late night, walk-in, reservation
- Price: $, $$, $$$, $$$$

## Extraction Architecture

Slate already has a useful extraction foundation:
- `ExtractionService`
- `ExtractionSource`
- `PageScrapeExtractor`
- `OEmbedExtractor`
- `TikTokExtractor`
- `LocationResolver`
- `ClaudeService`
- Vision extraction for images
- Whisper transcription for TikTok videos
- Google Maps URL parsing
- MapKit local search resolution

Known Slate weaknesses to fix for Wander:
- Instagram is mostly handled through generic page scrape/noembed, which is not strong enough.
- Instagram CDN images are filtered because they break behind auth.
- Google Maps extraction mainly parses URL/title and then runs text extraction.
- Location resolution is best-effort MapKit search, not a confidence-scored candidate system.
- Confidence exists, but the UX does not appear to use it strongly enough as a confirmation gate.
- Extraction failure states are mostly technical, not user-recoverable.
- Social sharing adds new requirements: attribution, privacy, duplicate canonical places, and social-visible extracted content.

### Wander Extraction Pipeline

```text
Input
  -> NormalizeSource
  -> SourceAdapter
  -> CandidateExtractor
  -> PlaceResolver
  -> ConfidenceScorer
  -> UserConfirmation
  -> UserPlace save
```

Adapters:
- CurrentLocationAdapter: CoreLocation + nearby MapKit search.
- ManualTextAdapter: direct text plus optional area hint.
- GoogleMapsAdapter: follow redirects, parse place id/name/coordinates when available.
- TikTokAdapter: reuse Slate's TikTok SSR/OEmbed/Vision/Whisper shape.
- InstagramAdapter: treat link extraction as unreliable; prefer share extension metadata, screenshot/photo fallback, user confirmation, and later backend enrichment.
- PhotoAdapter: OCR/Vision extraction plus EXIF location if available and permissioned.
- WebPageAdapter: page metadata/body extraction.

### Confidence Gates

| Confidence | Behavior |
|---|---|
| High | Show candidate selected, user can save in one tap. |
| Medium | Show 2-3 candidates and ask user to confirm. |
| Low | Ask for place name or area before saving. |
| None | Save source as unresolved draft, not a map pin. |

### User-Facing Extraction States

```text
pending -> running -> needs_confirmation -> complete
                   -> no_place_found
                   -> failed_retryable
                   -> failed_final
```

Copy examples:
- "I found a couple possibilities."
- "This link did not give me enough to place it."
- "Add a name or area and I can try again."
- "Saved as a draft."

## Social Discovery

Discover should be queryable and browsable.

Supported v0.1 filters:
- Person: one followed profile, multiple followed profiles, mutuals/friends
- Category: coffee, hikes, restaurants, bars, etc.
- Geography: near me, city, map viewport, typed area
- Status: people I follow have been, people I follow wanna go, friends/mutuals have been
- Your relationship: not saved, already saved, been, wanna go
- Attributes: work-friendly, dog friendly, patio, easy hike, etc.

Smart filter examples:
- Hikes in LA
- Coffee eastside
- Noodles near you
- Patio bars
- Weekend getaways
- Work-friendly cafes

Decision locked 2026-06-01: ship lightweight LLM-assisted Discover parsing up front, but keep execution constrained to the structured filter model above.

Rules:
- The LLM turns natural language into filter JSON; it does not directly query user data or create freeform recommendations.
- The LLM receives only the raw search phrase and filter schema. Do not send friend graph, saved places, private notes, contact data, or user profile data.
- Use a cheap/swappable model path first. If using Anthropic, prefer a low-cost model for parse attempts and reserve Sonnet-class fallback only if quality requires it.
- Cache repeated parsed queries and cap tokens tightly.
- Every parsed query should render as visible editable chips, so users understand what the app searched for.
- If parsing fails, fall back to the existing smart filter chips.

## Privacy And Trust

Privacy default selected:
- New places default to `followers`, meaning visible to people who follow the user and eligible for follower-powered Discover.
- The add flow always exposes `followers`, `mutuals`, and `self` options before save.
- `Followers` does not mean globally searchable by every Wander user in v1.
- Live location is never shared.

Recommended defaults:
- First-run onboarding should explain the default clearly: "People who follow you can see saved places unless you choose Friends or Self."
- During add flow, show the visibility pill near been/wanna status, not buried in settings.
- For any current-location add, explain that location is used to find nearby places, not to broadcast the user.
- Per-place visibility control must be visible on the confirmation screen.

Sensitive categories:
- Wellness, medical-adjacent places, home/private addresses, schools, and workplaces should default `self` unless explicitly shared.
- The app should detect likely home/work/private addresses and warn before sharing.

Block/remove behavior:
- Blocking removes profile discoverability.
- Blocking removes or prevents follow edges in both directions.
- Blocking hides profiles, places, followers/following list entries, username search results, Contacts results, and Discover content in both directions.
- Unfollowing revokes the viewer's future access to follower-visible content.
- Losing mutual follow status revokes future access to mutual-only content.
- Deleted places and active source artifacts should disappear from product/social views, with only minimal sync tombstones retained if needed.

## UX And Visual Direction

Carry forward the mock direction:
- Tan Rodeo-like palette.
- Terracotta primary action.
- Sky social pins.
- Funnel Display / Funnel Sans direction if licensing and app embedding are acceptable.
- Rounded but not childish.
- Emoji/category icons are acceptable for fast scanning.
- Copy is informal but not slangy.

Copy tone:
- Good: "worth a detour", "a few quick details", "where's it from?"
- Avoid: "where your friends at?"

UI principle:
- Map is for place memory.
- Discover is for follow-powered search and profile lookup.
- Add is for capture.
- Profile is for the user's identity, personal place memory, followers/following, and owner editing/filtering.
- Settings is a gear from Profile for account, privacy, Contacts, blocking, and notifications.

## Design Plan Review

Review date: 2026-05-30
Skill: `plan-design-review`
Initial design completeness: 6/10
Final design completeness after this pass: 8/10

Refresh date: 2026-06-01
Reviewed commit: 3b109ad
Refreshed design completeness: 8/10 -> 9/10

The refreshed design review keeps `preview/follow-profile-settings-mocks/` as the approved visual baseline and closes the M2 gaps that were not fully mocked: Discover, other-user profiles, followers/following lists, Settings details, auth gates, block states, and stale access-changed states. The detailed review artifact is `docs/reviews/2026-06-01-plan-design-review.md`.

Handoff update: `preview/follow-profile-settings-mocks/` now supersedes the earlier local storyboard and the Lovable PDF as the implementation visual reference. Use `tokens.css` as the literal token source, `index.html` for the component system, and `screens.html` for annotated Map/Add/Profile mocks. The original Lovable PDF remains background reference for breadth only.

### Design System Status

`DESIGN.md` now exists at the project root as a draft design-system contract. The handoff `tokens.css` is the implementation token source and `DESIGN.md` marks architecture-sensitive areas as provisional until plan-eng-review.

### Information Architecture

Rating: 6/10 -> 8/10

The app has four bottom-nav surfaces plus a required nested Settings surface. Each surface needs a strict hierarchy. The first screen should answer "what can my trusted people help me decide right now?"

```text
App Shell
  Map / Home
    1. Search: place, vibe, area, contact, or username
    2. Map viewport with filtered pins
    3. Filter chips: you, social/following, friends, been, wanna go
    4. Selected place sheet
    5. Bottom nav

  Add
    1. Source picker
    2. Candidate confirmation
    3. Been/wanna and visibility
    4. Contextual questions
    5. Save confirmation

  Discover
    1. Search
    2. People row
    3. Smart filters
    4. Follow-powered result cards
    5. Save-to-my-map action

  Profile
    1. Identity header, stats, activity recap, recent check-ins
    2. Saved places and unresolved drafts
    3. Filters, edit controls, visibility controls
    4. Followers/following entry points
    5. Role-based gated viewer state

  Settings
    Entry: gear in Profile, not a bottom tab
    1. Profile/account basics
    2. Privacy defaults and blocked users
    3. Contacts, notifications, data/account controls
```

Constraint rule: each main screen gets at most three primary elements above the fold. Everything else moves into a sheet, secondary row, or edit state.

### Screen Hierarchy Rules

Map:
- First: search and current filter context.
- Second: pins and clusters.
- Third: selected place sheet with social proof and save action.

Place sheet:
- First: place name, category, distance/area, and been/wanna state.
- Second: trusted context, such as "Ryan + 3 people you follow have been" or "Sofia saved this."
- Third: top attributes and one primary action.
- Fourth: source/attribution and visibility details.

Add flow:
- First: current step and source/candidate.
- Second: status, visibility, and nearby confirmation.
- Third: contextual questions.
- Fourth: optional note.

Discover:
- First: search and people.
- Second: smart filters.
- Third: results with social proof and save action.

### Interaction State Coverage

Rating: 5/10 -> 8/10

| Feature | Loading | Empty | Error | Success | Partial |
|---|---|---|---|---|---|
| Map pins | Skeleton pins and disabled filters | "No places here yet" + add place CTA | "Map did not load" + retry | Pins render with active filters | Some social pins hidden due privacy or sync |
| Search | Inline spinner in search field | "Nothing from your people yet" + broaden filters | "Search failed" + retry | Results grouped by you/following/friends | Results from local cache while sync catches up |
| Add current location | "Finding nearby places" | "Nothing obvious nearby" + search manually | Location denied copy + manual fallback | Candidate confirmed | Multiple candidates require choice |
| Add link | "Reading this link" | "This link needs a little help" | Retry or add manually | Candidate ready for details | Low confidence candidate shown as tentative |
| Add photo | "Reading photo" | "I could not find a place in this photo" | Retry or add manually | Candidate ready | EXIF location exists but place name needs user |
| Contextual questions | Questions appear after category | Generic quick tags if category unknown | Save without optional answers | Saved answer chips | Some custom tags local until synced |
| Discover people | Avatar placeholders | "Follow someone to unlock this" + search CTA | Profile data unavailable | People row and counts render | Some profiles hidden by privacy/blocking |
| Follow action | Pending button state | No matching user | Blocked/unavailable state | Followed/unfollowed | Already following or blocked |
| Save from social profile | Button spinner | Not applicable | Place no longer available | Saved to your map | Duplicate merges into existing place |
| Visibility control | Not applicable | Not applicable | Could not update visibility | Followers/friends/self state persists | Local change queued while offline |

Empty states should be warm but short. Do not explain the app. Give context and one obvious action.

### User Journey And Emotional Arc

Rating: 6/10 -> 8/10

```text
STEP | USER DOES | USER FEELS | DESIGN SUPPORT
-----|-----------|------------|----------------
1 | Opens app | Curious but low patience | Map first, no landing page, useful search immediately
2 | Adds first place | Slightly unsure about privacy | Clear visibility pill and no live-location language
3 | Answers contextual taps | "This gets me" | Category-specific questions, not generic review forms
4 | Sees place on map | Rewarded | Pin appears immediately with been/wanna state
5 | Follows someone | Curious but cautious | Profile preview, visible places only, clear follow/block actions
6 | Searches/discovers | Helped | Results explain which trusted people support the recommendation
7 | Saves social place | In control | Save creates user's own UserPlace, not a forced shared list
8 | Comes back months later | Reliant | Search, filters, notes, and social proof still make sense
```

Time horizon:
- First 5 seconds: app reads as a trusted map, not a generic social feed.
- First 5 minutes: user has saved at least one useful place and understands privacy.
- Five-year relationship: the map becomes a durable personal/social memory layer.

### AI Slop Risk Review

Rating: 7/10 -> 9/10

Avoid:
- Generic card grids that make Discover feel like a template marketplace.
- Decorative cards inside cards.
- Public influencer-map patterns.
- Travel-only imagery or copy.
- Overly cute slang.
- Emoji as decoration instead of category shorthand.

Specific UI commitments:
- Map is the visual anchor, not a hero.
- Place cards are functional objects: social proof, attributes, and save action.
- Smart filters are query shortcuts, not marketing cards.
- Privacy controls are compact, visible pills, not buried settings.
- Copy stays useful: "worth a detour", "saved from Ryan", "friends who have been", "private", "friends".

### Design Tokens Draft

Rating: 4/10 -> 8/10

Colors:

| Token | Use |
|---|---|
| Warm canvas | App background, sheets |
| Bone surface | Cards/sheets/forms |
| Terracotta | Your pins, primary action |
| Terracotta dashed | Your wanna-go pins |
| Sky | Social pins |
| Sky dashed | Social wanna-go pins |
| Moss | Outdoors/nature category |
| Sun | Highlight/category warmth |
| Ink | Primary text |
| Muted brown/gray | Secondary text |
| Hairline | Borders/dividers |

Typography:
- Display: Funnel Display direction or equivalent playful grotesque.
- Body: Funnel Sans direction or equivalent legible sans.
- No default system stack as the primary brand typeface unless licensing blocks custom fonts.
- Avoid negative letter spacing.

Shape and spacing:
- Main sheets/cards: 20-28px corner radius only where the app mimics iOS bottom sheets.
- Small chips/buttons: 999px pill radius.
- Repeated place/result cards: 12-16px radius.
- Use an 8px spacing grid.
- Touch targets: 44px minimum.

Components:
- Search field with icon and optional active filter summary.
- Multi-select filter chips.
- Pin and cluster components.
- Place bottom sheet.
- Source picker row.
- Candidate confirmation row.
- Contextual question block.
- Attribute/tag chips.
- Visibility pill.
- Profile avatar row.
- Follow/profile card.
- Followers/following list.
- Settings rows for privacy, contacts, blocked users, notifications, and account.
- Empty state panel.

### Responsive And Accessibility

Rating: 4/10 -> 8/10

iPhone:
- Primary target for v0.1.
- Bottom nav always reachable.
- Add tab should be prominent but must not occlude essential map content.
- Bottom sheets must support collapsed, medium, and expanded states.

iPad:
- Do not simply stretch the phone UI.
- Recommended pattern: map remains primary; details/discover can appear as a side panel.
- If iPad is not built in v0.1, explicitly constrain the target to iPhone and let iPad run phone-compatible.

Accessibility:
- 44px minimum tap targets.
- Body text at least 16pt equivalent where practical.
- Do not rely on color alone for pin states: solid vs dashed/fill pattern must remain.
- VoiceOver labels for pins should include owner/status/category, for example "Social place, been, coffee, Maru Coffee."
- Dynamic Type should not break chips; long tags truncate after sensible limits.
- Visibility controls must be readable by VoiceOver and not represented only by icon.
- Map filters need selected/unselected state labels.
- Reduce Motion should disable decorative motion and keep state changes clear.

### Resolved Design Decisions

Rating: 5/10 -> 7/10

These have been resolved for eng planning:

| Decision Needed | Recommendation | If Deferred |
|---|---|---|
| First-run onboarding shape | Use the onboarding research flow: map promise -> location -> notifications -> category preferences -> add first place -> auth gate at save intent | Engineers may bolt onboarding onto the side instead of making it the activation path |
| Default visibility | Resolved: use `followers`, `mutuals`, and `self`; helper copy must clarify that Everyone means followers | Users may not understand who sees new places |
| Share extension in v0.1 | Defer unless link capture is the top activation bet | Add flow scope may expand before core map works |
| Contact import | Contacts-first UI with invite-link and handle-search fallbacks; native Contacts planned later behind `FakeContactProvider` | Privacy review and App Store copy become larger if native Contacts ships immediately |
| iPad behavior | Phone-first unless explicitly prioritized | Tablet layout may become a stretched phone screen |
| Remaining visual states | Extend the current handoff style to Discover, other-user profiles, followers/following, settings details, and onboarding | Engineers may infer missing states inconsistently |

### Design Review Result

The plan is design-complete enough for the next planning step, with the handoff package as the approved visual reference for tokens and core screens. It is not implementation-complete until the remaining visual states and backend/eng review confirm feasibility.

2026-06-01 update: the missing M2 social/settings states are now specified in `DESIGN.md`, so M2 can proceed against the handoff style. Run simulator visual QA after implementation.

## System Architecture

Clerk + Supabase shape:

```text
iOS App
  |-- SwiftUI Screens
  |-- SwiftData Local Store
  |-- Sync Queue
  |-- Extraction Client
  |-- MapKit/CoreLocation
  |-- Share/Photo Inputs
  |
  v
Clerk
  |-- Auth/session/account
  |
  v
Supabase Backend
  |-- Follow Graph
  |-- Profiles / Blocks
  |-- Place Canonicalization
  |-- User Places
  |-- Visibility Policy
  |-- Extraction Jobs
  |-- Observability Events
  |
  v
External Services
  |-- Anthropic/OpenAI or selected AI provider
  |-- Apple MapKit / optional Places provider
  |-- Social/link metadata sources
```

## Data Flow Diagrams

### Add Current Location

```text
Tap "I'm here right now"
  -> request location permission
  -> get current coordinate
  -> search nearby places
  -> show candidates
  -> user selects place
  -> choose been/wanna
  -> answer contextual questions
  -> save UserPlace locally
  -> enqueue sync
```

Shadow paths:
- Permission denied: allow manual search.
- No nearby places: ask user to search or enter name.
- Wrong candidate: user can change place.
- Offline: save local draft and sync later.

### Add Link

```text
Paste/share URL
  -> normalize URL
  -> select source adapter
  -> extract candidates
  -> resolve canonical place
  -> confidence gate
  -> confirm/edit
  -> save UserPlace
```

Shadow paths:
- Empty URL: disable continue.
- Unsupported URL: use web page adapter.
- Instagram login wall: ask for screenshot/photo or manual confirmation.
- Low confidence: save as draft or ask for place name/area.

### Save From Social Profile

```text
Visible social place in Discover or profile
  -> tap place
  -> inspect profile/social context
  -> save to my map
  -> choose wanna go or been
  -> optional note/tags
  -> create UserPlace with source_type social_save
```

Shadow paths:
- Follow/block/visibility changes mid-flow: show unavailable state.
- Original place deleted: keep local draft only if user already saved it.
- Duplicate: merge into existing UserPlace instead of creating another.

## Error And Rescue Registry

| Codepath | Failure | Rescue | User Sees |
|---|---|---|---|
| Location permission | Denied/restricted | Manual search fallback | "Search for the place instead." |
| Nearby search | No results | Manual add fallback | "Nothing obvious nearby." |
| Link normalization | Invalid URL | Inline validation | "That link does not look right." |
| Instagram extraction | Login wall/no metadata | Ask for screenshot or manual name | "This link needs a little help." |
| TikTok extraction | SSR/OEmbed/video fails | Vision/text fallback, then confirmation | "I found this, confirm?" or draft |
| Photo extraction | No place visible | Save draft or ask for name | "I could not find a place in this photo." |
| AI response | Malformed JSON | Retry once, parse repair, then fail visible | "Extraction failed. Try again or add manually." |
| Place resolution | Ambiguous candidates | User chooses candidate | "Which one did you mean?" |
| Sync | Network down | Local save, queued sync | "Saved on this phone. Syncing later." |
| Follow action | Blocked/already following/unavailable | No-op with state-specific message | "Already following" or unavailable |
| Visibility check | Unauthorized access | Deny and log | "This place is no longer available." |

## Observability

Track these from day one:

- Add flow started by source.
- Add flow completed by source.
- Extraction success rate by source.
- Extraction confidence distribution.
- Needs-confirmation rate.
- Draft/unresolved rate.
- User correction rate after extraction.
- Time to first saved place.
- Time to first follow.
- Follow/unfollow/block.
- Follower and following count changes.
- Social place viewed.
- Social place saved.
- Place visibility changed.
- Sync failures and retries.

Operational logs should include:
- extraction_job_id
- source_type
- adapter
- confidence
- error_code
- user_id hash or internal id
- place_id if resolved
- request trace id

Do not log raw private notes or precise live location beyond what is necessary for debugging and compliant retention.

## Test Plan

### Unit Tests

- URL normalization.
- Source adapter selection.
- Pin style mapping for owner/status.
- Visibility policy.
- Follow/block state transitions.
- Contextual question template rendering.
- Duplicate UserPlace merge.
- Confidence gate behavior.

### Integration Tests

- Add current location with permission granted/denied.
- Add Google Maps link.
- Add TikTok link with partial metadata.
- Add Instagram link with no metadata and screenshot fallback.
- Save from social profile.
- Unfollow/block and verify visibility revocation.
- Offline local save then sync.

### UI Tests

- First add flow.
- Multi-select map filters.
- Place detail from map pin.
- Follow/unfollow from profile.
- Followers/following lists.
- Settings blocked users list.
- Discover smart filter to save.
- Edit visibility.

### Hostile QA Cases

- User taps save twice.
- User backgrounds app mid-extraction.
- Follow/block/visibility changes while place detail is open.
- Extraction returns a generic name like "restaurant".
- User follows 0 people.
- User has 10,000 places in a dense city.
- Two users save the same place with slightly different names.
- A `self` place appears in a social query.
- A `mutuals` place appears for a one-way follower.
- A blocked user appears in username or Contacts search.

## Rollout Plan

Phase 0: Spec and design
- Finish this spec.
- Integrate onboarding research from `research/screensdesign/2026-05-30-social-map-onboarding/`.
- Run office-hours.
- Run plan-design-review.
- Run plan-eng-review. Done 2026-06-01.

Phase 1: Native prototype with local + mocked backend
- Map, add flow, contextual questions, local SwiftData.
- Mock follow data, fake contacts, username search, profiles, settings, and discover filters.
- Extraction prototype using improved local adapters.

Phase 2: Real backend social alpha
- Clerk auth.
- Follow graph.
- Profiles.
- Block list.
- Contact matching contract.
- Native Contacts planned later; keep `FakeContactProvider` and username search while backend matching/privacy copy mature.
- UserPlace sync.
- Visibility enforcement.
- Social save flow.

Phase 3: Extraction hardening
- Backend extraction jobs for alpha.
- Source-specific extraction metrics.
- Instagram fallback UX.
- Place candidate confidence.
- Detailed job architecture and provider pipeline.

## Open Questions

- None blocking. Native Contacts is planned later, after v0.1 fake-contact/username social loop validation.

## CEO Review Notes

Mode selected: Scope Expansion.

Accepted direction:
- Backend-first social spec with Clerk + Supabase contracts.
- Follow graph with mutual follows as friends.
- Privacy-first follower/friend/self visibility.
- "Been / wanna go" as self-report with optional nearby confirmation.
- Contextual category templates with custom per-place tags.
- AI extraction from links/photos/manual notes, improving on Slate.
- Save source conversation and mocks under the project.

Primary CEO-level risk:
- If Wander is only "pins from people," it is too easy to copy and too close to Mapstr/Swarm. The product needs to own the capture loop and the trust/privacy model.

Primary product recommendation:
- Make the first magical moment "I am looking for something, and my people's map has the answer." Capture is the supply engine, but discovery is the network-value moment.

## GSTACK Review Report

| Review | Trigger | Why | Runs | Status | Findings |
|---|---|---|---|---|---|
| CEO Review | `plan-ceo-review` | Scope and strategy | 1 | Draft complete | Scope expansion decisions captured; no implementation yet |
| Design Review | `plan-design-review` | UI/UX gaps | 1 | Clean, handoff-backed | Handoff package now owns tokens/core screens; remaining visual pass needed for Discover, other-user profiles, followers/following, settings details, and onboarding |
| Eng Review | `plan-eng-review` | Architecture and tests | 0 | Required next | Backend and sync architecture still need review |
