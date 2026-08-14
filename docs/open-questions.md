# Open Questions

Last updated: 2026-07-25

These are the known unresolved questions and risks. Some are intentionally deferred; do not reopen locked decisions unless Joe asks.

## Needs Answer Before M2 Is Accepted

| Question | Recommendation | Notes |
|---|---|---|
| What exact native layout should replace the oversized/letterboxed Map screen? | Fix in SwiftUI against simulator screenshots, using the handoff as visual direction but native scale/safe areas. | Active bug from 2026-06-01 screenshot. |
| Which iPhone sizes are required for visual QA? | Current simulator target plus one smaller iPhone. | Current failing screenshot is iPhone 17 Pro/iOS 26.2 simulator. |
| Should Add/Discover/Profile/Settings be visually reworked in the same pass as Map? | Start with Map/root layout, then sweep other screens after the root scale is fixed. | Map exposes the worst layout/orientation failure. |

## M3 Remaining Questions

| Question | Recommendation | Notes |
|---|---|---|
| Where does profile mirroring happen? | Resolved: backend webhook from Clerk/Svix into Supabase `profiles`. | Edge Function `clerk-profile-webhook` handles `user.created`, `user.updated`, and `user.deleted`. Real create/delete webhook path verified on 2026-06-02. |
| How are Supabase RLS policies tested going forward? | Keep repo SQL tests and run them through standard Supabase CLI once Docker is installed. Until then, use hosted Postgres plus a temporary `pg` runner. | Current hosted SQL tests passed: 29 pgTAP assertions, 0 failures. |
| Do we create Supabase migrations in this repo? | Yes. | New Supabase project exists and is linked; migrations through `20260609211700_social_graph_rpcs.sql` are applied remotely. |
| Do hosted Supabase auth settings need review before alpha? | Yes. | `npx supabase config push` pushed generated local auth defaults plus Clerk config to the new dev project. Fine for M3, but review before alpha. |
| Does Clerk's default iOS token work for Supabase RLS? | Resolved: use native Clerk third-party auth, no deprecated JWT template. | 2026-06-04 API smoke passed after adding the Clerk provider connection in Supabase Dashboard with domain `https://growing-pheasant-22.clerk.accounts.dev`. Default Clerk session tokens are accepted by Supabase and authenticated RPCs passed for profile search, follow, visible places, social save, block, unblock, and unfollow. |
| How should remote row attributes hydrate local UI? | Resolved: hydrate backend `attributes` into local `placeAttributes` on remote place refresh. | Implemented in Build 20. |
| How should remote relationship/filter metadata hydrate local UI? | Resolved for alpha: backend graph RPCs return followers/following/relationship and the iOS store hydrates remote follow edges. | Implemented in Build 21. |
| Which analytics provider? | Resolved for alpha: PostHog behind the vendor-neutral analytics interface. | The dedicated `Grayline Studio` / `rec.me` project is active (ID `557259`) and its managed dashboard is ID `1994904`. Runtime capture requires the rec.me-only `WANDER_POSTHOG_PROJECT_TOKEN` in the signed app; never reuse another app's token. |

## Rich Place Profile Follow-Ups

| Question | Recommendation | Notes |
|---|---|---|
| Should Wander store website, phone, hours, cuisine, order, menu, or reservation metadata? | Add optional, source-provenanced fields later only when populated by a free/source-owned path. | Do not show placeholders or blank rows. No paid place metadata provider is selected. |
| How should private notes work? | Add a separate private-note model field later if product decides it is needed. | Current `LocalUserPlace.note` is a single note field, so UI should label it as the user's note rather than pretending public/private notes both exist. |
| How do remote attributes reach expanded place profiles? | Resolved: `RemotePlaceAttributeDTO` passes through `VisiblePlace.attributes` and is upserted into local `placeAttributes`. | Implemented in Build 20; future work is richer question-definition metadata for custom questions. |

## Needs Answer Before M5

| Question | Recommendation | Notes |
|---|---|---|
| Which cheap LLM path parses Discover queries? | Resolved for REC-150: extend the existing authenticated `parse-discover-query` Edge Function and shared swappable structured-JSON provider. | Submit-only, one call per uncached normalized query. Keep raw phrase + allowed schema as the entire model payload; deterministic code resolves people and proves result metadata. The configured model snapshot remains an eval-time operational choice. |
| What extraction providers are used for link/photo/social saves? | Evaluate Slate extraction first, then implement backend job lanes. | Known gaps: Instagram and location extraction are weak in Slate today. |
| What confidence and fallback UX should extraction use? | Keep candidate confirmation and manual rescue mandatory. | Never pretend extraction worked if confidence is low. |

## M5 Add Capture Notes

| Issue | Recommendation | Notes |
|---|---|---|
| Add flow navigation | Add an explicit back button/escape path after the user starts adding. | Current TestFlight build can strand the user in the Add flow. |
| Add flow copy | Use title `add a place`; remove `where's it from` and `pick a source`. | Source selection can remain structurally, but copy should feel like "we'll fill in what we can." |
| Current location add | Ask for location permission and resolve nearby candidates from real location. | Do not show deterministic `Maru Coffee` as the default "I'm here now" result. If permission is denied/unavailable, fall back to manual search. |
| Manual add resolution | Use MapKit/place-provider search for canonical place identity. | LLM can parse messy user text into query/category/area hints, but it should not invent the canonical place or coordinates. |
| Paste link extraction | Create real source artifact + extraction job lane. | Google Maps/link sources should return candidates; low-confidence extraction must route to manual rescue. |
| Photo add extraction | Add real photo import/capture plus backend extraction lane. | Photos are not working until PhotosUI/import and extraction jobs exist. |

## Deferred Product Questions

| Question | Recommendation | Notes |
|---|---|---|
| Share extension timing? | Later, after in-app add/map/social loop works. | Share extension can be a capture booster but should not block v0.1. |
| Private profiles/follow requests? | Defer. | v0.1 follow graph is open one-way follows with visibility per place. |
| Following users not on Wander yet? | Defer. | Needs invite/link/contact matching model. |
| iPad layout? | Defer. | Later use map + side panel, not stretched iPhone UI. |

## Operational Risks

- Visual quality can regress if implementation copies HTML mock dimensions literally instead of adapting to native iPhone screens.
- Xcode project signing settings may churn when opened locally. Keep `project.yml` source-of-truth and avoid committing incidental signing changes.
- RLS mistakes are high-risk because privacy is part of the product wedge.
- Fake local visibility must not be treated as security. Supabase policy tests are required.
- App-facing Supabase RPCs must stay available through `public.*` wrappers unless `app` is explicitly added to exposed PostgREST schemas.
- Link/photo/social extraction is a moat only if it reduces capture work; it is not the first product wedge by itself.
- The Clerk CLI disposable-user test stored `username` differently than the flag passed in that command. The current webhook mirrors Clerk's stored `username`; product username claim/edit UX still needs to be explicit later.
