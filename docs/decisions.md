# Decisions

Last updated: 2026-07-12

Durable product and engineering decisions for Wander. See the product spec and engineering plan for fuller rationale.

## Product Decisions

| Decision | Status | Notes |
|---|---|---|
| Map-first app | Locked | The map is the primary memory and discovery surface. |
| No manual lists | Locked | Lists were explicitly removed from product direction. |
| Trusted people, not strangers | Locked | Discovery should come from people the user follows/knows. |
| Cross-category places | Locked | Not restaurant-only; coffee, hikes, bars, parks, restaurants, etc. |
| No live location | Locked | Current location is for nearby place resolution, not broadcasting. |
| No gamified check-ins | Locked | Avoid mayorships, streaks, leaderboards, and public check-in framing. |
| Four bottom tabs | Locked | Map, Add, Discover, Profile. |
| Settings from Profile gear | Locked | Do not add Settings as a fifth tab. |
| Profile merges self memory and social profile | Locked | Owner and other-user profile states share the same conceptual surface. |
| Follow graph, not friend requests | Locked | One-way follows; mutual follows are friends. |
| Public/private copy | Locked | UI says Everyone/Friends/Self; data stores `followers`/`mutuals`/`self`. |
| Block behavior | Locked | Hard block; remove follow edges and hide profiles/content both ways. |
| People finding | Locked for v0.1 | Username search plus contacts-shaped UI. Native Contacts later. |
| Following not-yet-on-app users | Deferred | Track later; not in v0.1. |

## Technical Decisions

| Decision | Status | Notes |
|---|---|---|
| Native iOS | Locked | SwiftUI, iOS 17+, iPhone-first. |
| XcodeGen | Locked | `project.yml` is source of truth. |
| Clerk + Supabase | Locked | Clerk for identity/account, Supabase for data/RLS/PostGIS/storage/functions. |
| Clerk user id mapping | Locked | Store Clerk user ids as text `profiles.id` / owner fields. Supabase RLS reads the Clerk session token subject through `auth.jwt()->>'sub'`, with a local-test fallback to `request.jwt.claim.sub`. |
| SwiftData local-first | Locked | Local cache, guest-local records, sync queue. |
| MapKit-only v0.1 | Locked | Keep provider-extensible place IDs. |
| Place default photo priority | Locked for REC-82, revised 2026-07-12 | The full place-profile header and collapsed place card use one priority: a Google Places photo when the provider can make a trustworthy place match; otherwise the earliest uploaded visit photo the viewer can see. A newly captured local photo renders immediately for its owner. Shared user photos stay in the private `visit-photos` bucket and are read through authenticated storage plus visit/user-place RLS, so a follower can inherit a dropped pin's first photo without making the object public. |
| Google Places photo enrichment | Locked for REC-82 | Maps/search stay MapKit-first. Representative venue photos are loaded on demand through the authenticated Supabase `place-photo` Edge Function using Google Places within the separate 1,000-event monthly free caps for Text Search Enterprise and Place Details Photos; low quotas must prevent paid overage. The Google key stays server-side. Do not prefetch, persist, or cache Google photo content/references; retain only the existing provider place id where available, show Google Maps plus author attribution, and link each image to its source photo. Yelp is not the fallback because its free tier is evaluation-only and commercial access is paid. When Google has no safe match or is unavailable, use the RLS-backed first visible visit-photo fallback above. |
| Supabase RLS authoritative | Locked | Client policy is for UI behavior only. |
| Repository/protocol boundaries | Locked | Views should not call Clerk/Supabase directly. |
| Profile avatar identity contract | Locked | Any new UI surface that shows a profile photo must be wired from a stable user/profile id through the store's freshest profile/avatar state. Do not copy ad hoc avatar strings from lower-fidelity place, list, search, or graph payloads without preserving richer cached profile metadata. |
| Backend extraction jobs | Locked | Link/photo extraction should run on backend, not fake client-only extraction. |
| M2 extraction shells | Locked | Link/photo create unresolved drafts until backend jobs exist. |
| Discover parser interface early | Locked | Deterministic local parser now; cheap swappable LLM parser in M5. |
| LLM data minimization | Locked | Send raw query phrase + schema only, not graph/place/contact/user data. |
| Share extension | Deferred | Build after in-app add/map/social loop works. |
| Native Contacts | Planned later | Use `FakeContactProvider` in M2/v0.1 baseline. |
| Analytics provider | Locked for alpha | Use PostHog through the vendor-neutral analytics interface. Keep sync/auth diagnostics non-PII: counts, enum metadata, and internal auth user id only; no place names, notes, coordinates, emails, or handles. |
| Sync conflict behavior | Locked v0.1 | Simple `updated_at`/server-wins plus local retry queue. |
| Full onboarding | Deferred | Auth gates at save/sync/follow/social-save intents still required. |
| M3 backend schema/RLS/profile foundation | Project created, migrations applied, webhook verified | New Supabase project `rugmtlgufrhlxwfkumhw` and new Clerk app `app_3Eb3JbpbMDjOA2qKUCqfsZwfct9` are created. Migrations `20260602131500`, `20260602140304`, `20260602143000`, `20260602210000`, and `20260604185000` are applied remotely. Hosted pgTAP tests passed with 29 assertions. Clerk profile mirroring is deployed through Svix -> Supabase Edge Function -> PostgREST RPC, and real create/delete webhook flow was verified. Schema includes custom `question_definitions` plus JSON-backed `place_attributes` so future user-created questions/inputs can be added without answer-column churn. |

## Release Decisions

| Decision | Status | Notes |
|---|---|---|
| Explicit TestFlight releases | Locked | Merging app changes to `main` no longer automatically triggers a build-number bump, archive, upload, TestFlight attachment, or tester Slack note. App-code merges are candidates for the next explicit TestFlight release. Only push a TestFlight/TF build when Joe or Ryan explicitly asks, with wording such as "push the TestFlight build", "upload the TF build", "release this to TestFlight", or "go push in your build". The next explicit release packages latest `main`, includes all eligible app changes since the last completed TestFlight build, and bumps the build number once. |
| Linear completion after merge | Locked | Ordinary product/app issues can move to `Done` once the implementation is merged to `main` and required validation passes. TestFlight remains the `Done` gate only when the issue or user request explicitly requires TestFlight QA, release validation, or a TestFlight push. |

## Design Decisions

| Decision | Status | Notes |
|---|---|---|
| Handoff package is source of truth | Locked | Use `preview/follow-profile-settings-mocks/`. |
| `tokens.css` is canonical | Locked | Promote token values 1:1 into SwiftUI. |
| Warm utility map style | Locked | Cream/sand/espresso/terracotta/sky with useful map-first UI. |
| No competing visual direction | Locked unless Joe asks | Do not generate new variants as implementation blockers. |
| System fonts temporarily | Locked | Funnel Display/Sans direction is tokenized; add font assets when packaging/licensing is clean. |
| SF Symbols/native controls | Locked | Use native symbols instead of mock emoji chrome for structural UI. |
| iPhone-first visual QA | Locked | Verify real simulator screenshots before calling UI accepted. |
| Map filter selected state | Locked | Inactive chips keep the bone/sand fill; active chips add a terracotta ring and terracotta icon, with no checkmark. |
| Map place labels | M2 selected/simple labels | Show place labels on Wander pins in the local prototype, with selected/tapped state made visually explicit. Revisit clutter rules later with real density. |
| Social proof copy | Locked | Place sheets should show who saved a place with avatars/facepile, not "`Name`'s tip" copy. |
| Rich place profile data | Locked v0.1, revised 2026-07-12 | Expanded map place profiles use only data Wander actually has: place name/category/address/locality/coordinates, save status/visibility, notes, flexible answer attributes, social proof, friend saves, share, keyless map directions, MapKit/directly captured website or phone data, and on-demand Google Places representative photos under the REC-82 attribution/no-cache contract. Do not show empty hours/price/cuisine fields. Price can appear only as a user answer attribute. "Order" and "Reserve" are allowed only when backed by a direct provider/place URL; non-authoritative provider searches must be labeled as search/find actions. No other paid place metadata is part of this v0.1 surface. |
| Screen titles | Locked | Main surfaces use plain titles like Discover and Settings; avoid oversized informal slogans as page titles. |
| Discover hierarchy | Locked | People stay near the top under search; Places are the primary Discover content with a segmented `mine` / `friends` / `everyone` scope switch at the top of the Places section. |
| Add question answers | Locked | M2 persists starter contextual answers into flexible `LocalPlaceAttribute` rows using `question_key`, `value_type`, and JSON values. Starter templates are category-aware: coffee = work setup/tags, hike = strenuousness/tags, restaurant = price/occasion/tags, plus a rating/excitement signal. Expanded place sheets read persisted attributes rather than inferred placeholder chips. Future user-created/custom questions should add question-definition metadata, not hardcode new answer columns. |
| Place attribute value-type contract | Locked | iOS `PlaceAttributeDraft.valueType`, `question_definitions.value_type`, and `place_attributes.value_type` are one cross-layer contract. Semantic `personal_label` and `restaurant_cuisine` types are first-class alongside generic input types. Every new type must update both constraints and pass the authenticated hosted `public.save_own_place` smoke transaction before merge/release. |

## Reset Decisions

| Decision | Date | Notes |
|---|---|---|
| Revert low-pass implementation | 2026-06-01 | Joe moved reasoning to very high and requested an audit/reset. |
| Add M1.5 contract lock before M2 | 2026-06-01 | Prevent fixture UI from becoming accidental architecture. |
| Run refreshed design review | 2026-06-01 | Completed clean; score 8/10 to 9/10. |
| M2 local product loop pushed | 2026-06-01 | Commit `962efce`, 18 tests passing, visual QA still pending. |
| Add agent work log protocol | 2026-06-01 | All agents must update `docs/agent-log.md` before, during, and after non-trivial work. |
