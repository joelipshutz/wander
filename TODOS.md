# Wander TODOs

Date: 2026-05-29

## P1

- Build 23 Map tap hit-testing regression.
  - Report: Ryan saw tap-to-select and tap-away get flaky when zoomed out; sometimes selecting or unselecting requires two taps.
  - Likely cause: Build 23 tap-away logic uses a fixed geographic radius (`120m`) to protect marker taps, which is not stable across zoom levels.
  - Recommended fix: replace meter-based marker proximity with screen-space hit testing using MapKit/`MapReader` projection and a visual target radius around the marker.
  - Status 2026-06-10: fixed on `codex/roadmap-1-4` with screen-space marker hit testing and unit coverage.
  - Review need: scoped engineering review only; no design review unless the interaction model changes.

- Build 17 TestFlight feedback batch.
  - Why: Joe/friend testing found alpha-blocking issues in persistence, follow visibility, save completion, and map add/edit semantics.
  - Persistence: replace in-memory preview-only app state with real local persistence/hydration so saved places survive killing/relaunching the app.
  - Following/social visibility: verify follow/unfollow RPC success, relationship refresh, remote visible places refresh, and social rows appearing for followed users.
    - Status 2026-06-10: RLS already covers one-way follower visibility; client now refreshes remote visible-place cache after signed-in own/social saves and when Discover opens or sign-in state changes. Realtime push refresh is still later.
  - Add sync: debug `sync failed` after Add-tab save when the place still appears locally; local-first behavior is correct, but healthy signed-in remote save should not fail silently.
    - Status 2026-06-10: store now refreshes remote visible places after successful remote save, improving post-save consistency. Still needs real-device signed-in QA against Supabase to confirm the original sync-failed report is gone.
  - Map typeahead: selecting a typeahead result should dismiss the keyboard.
    - Status 2026-06-10: already implemented before this pass; keep in QA checklist.
  - Map plus flow: plus on an unsaved/search/social place should route into a lightweight Add confirmation/details flow with status, visibility, category questions, and note, rather than direct-save with no details.
    - Status 2026-06-10: already routed through `MapPlaceSaveFlowSheet`; keep in QA checklist for unsaved search/social results.
  - Edit saved place: pencil/edit should open a real saved-place edit/details flow, including marking `wanna` as `been`, visibility, note, and answer edits.
    - Status 2026-06-10: map saved-place edit already uses the save flow; keep in QA checklist for `wanna` to `been` and answer edits.
  - Save completion: replace the Add full-screen saved state with a lightweight celebratory confirmation/toast, haptic, "place saved", and "add another" option before returning to the standard Add tab.
    - Status 2026-06-10: lightweight toast behavior already exists; old full-screen saved state is no longer the primary path.
  - Map user location: live current-location dot should read as native Apple Maps blue; keep separate from Wander saved-place pin colors unless product decides own saved pins should also change.
    - Status 2026-06-10: already implemented before this pass; keep in visual QA.

- Integrate onboarding spec before eng plan review. Done 2026-05-31.
  - Why: onboarding decides how privacy defaults, first place capture, and first follow are introduced.
  - Result: main spec now references `research/screensdesign/2026-05-30-social-map-onboarding/` and adopts map-first guest onboarding with auth at save intent.

- Run office-hours on the product direction.
  - Why: validate the problem framing before architecture work hardens the direction.
  - Depends on: current product spec.

- Run plan-design-review. Done 2026-05-30 as a mock-backed review using the Lovable PDF mocks.
  - Why: the app has significant UI scope and the mocks need product/design stress testing.
  - Result: design spec now includes information hierarchy, state coverage, journey, tokens, accessibility, and unresolved design decisions.
  - Follow-up: extra visual variants are not blocking; current handoff package is the source of truth.

- Refresh design review / mocks for follow graph, profiles, and settings. Updated 2026-06-01 from `wander.zip` design handoff.
  - Why: the original mocks cover map, discover, and add flow, but the 2026-06-01 graph change adds profile pages, followers/following lists, block controls, settings, and a three-tier visibility picker.
  - Result: `preview/follow-profile-settings-mocks/` now holds the design handoff package. `tokens.css` is the literal source of truth; `index.html` and `screens.html` cover the core design system, Map, Add, saved, and merged Profile surfaces.
  - Result: refreshed plan-design-review completed 2026-06-01 in `docs/reviews/2026-06-01-plan-design-review.md`.
  - Follow-up: run simulator visual QA after M2 screens exist.

- Run plan-eng-review. Done 2026-06-01.
  - Why: backend, sync, privacy rules, extraction, and data model need architecture review before implementation.
  - Result: `docs/reviews/2026-06-01-plan-eng-review.md` captures Clerk + Supabase, guest-local save, followers-only public visibility, backend extraction jobs, deferred share extension, MapKit-only places, hard block, username rules, and delete/source retention.
  - Result: native Contacts is planned later; v0.1 uses fake contacts and username search.
  - Reset audit: low-pass Swift/Xcode implementation was removed on 2026-06-01. Rebuild now requires M1.5 Contract Lock before M2.

- Create iOS engineering implementation plan. Done 2026-06-01.
  - Why: locked product/design decisions need a build sequence before code starts.
  - Result: `docs/plans/2026-06-01-wander-ios-eng-plan.md` defines milestones, modules, schema, RLS, sync, LLM parser, analytics, extraction jobs, and tests.
  - Reset audit result: plan now adds M1.5 Contract Lock, four-tab-only navigation, 1:1 token promotion, XcodeGen source-of-truth, schema/RLS before Clerk UI, real MapKit seeded M2, and milestone test gates.

- Complete M1.5 Contract Lock before rebuilding M2.
  - Why: prevent fixture UI from accidentally becoming architecture again.
  - Depends on: current eng plan, product spec, design handoff.
  - Scope: Supabase schema/RLS matrix, SwiftData parity, repository protocols, sync state machine, deterministic fakes, parser interface, analytics interface, and design review of missing follow/settings/profile states.

## P2

- Add personalized Feed ranking after REC-107 usage data exists.
  - Why: the first Feed release intentionally orders activity newest-first and
    uses a deterministic trusted-place shelf. That keeps the social record
    legible while the product learns what users actually save.
  - Scope: rank the existing Feed module contract using trust, recency,
    proximity, place relevance, and observed save likelihood. Preserve a clear
    provenance reason for every featured result; do not turn it into an opaque
    influencer ranking.
  - Depends on: shipped REC-107 event analytics and enough real Feed sessions
    to evaluate quality against reverse chronology.


- Decide backend/auth stack. Done 2026-06-01.
  - Why: follow graph, geo queries, offline sync, profile/block rules, and visibility policies are core to Wander.
  - Decision: Clerk + Supabase. Clerk owns identity/session/account surfaces; Supabase owns Postgres/RLS/PostGIS/storage/functions; SwiftData owns local cache and sync queue.

- Evaluate Slate extraction code against Wander requirements.
  - Why: Slate has useful extraction pieces, but Instagram and location extraction are known weak spots.
  - Decision so far: backend extraction jobs are the alpha direction; detailed provider/job architecture still needs a focused pass before real social alpha.
  - Status 2026-06-10: in-app link fallback now attempts the backend extraction job path when local link parsing cannot find a place, gated by confidence and coordinates. Richer providers for Instagram/TikTok/photo OCR remain later work.
  - Status 2026-07-15: superseded by Linear REC-97 and `docs/plans/2026-07-15-rec-97-place-imports.md`. REC-97 keeps the current extraction substrate but replaces the deferred provider pass with one normalized adapter contract for Google Maps, Instagram, TikTok, and Text/Notes, Apple Maps Server API resolution, scheduled processing, golden fixtures, and explicit rescue states.

- Decide whether share extension ships in v0.1. Done 2026-06-01.
  - Why: share-sheet capture may be a major activation path, but can slow first implementation.
  - Decision: defer. Track as a later TODO after in-app add, map, and social loop work.
  - Status 2026-07-15: the deferral is superseded by Linear REC-97. The complete four-source import release includes a Share Extension behind `import_places_v1`, with an App Group capture envelope, host-app authenticated drain, idempotency, signing/provisioning, system share-sheet QA, and no provider parsing or long network work inside the extension.

- Build richer share/deep-link surface later.
  - Why: current share uses a generic Google Maps/search URL only. Product direction is that shared Wander places should open in the app when installed, otherwise open a lightweight web page that shows the place/social context and prompts download.
  - Scope later: universal links, shareable place/profile web page, app-open fallback, install CTA, privacy-aware access rules, and no leakage of private/friends-only content.

- Add richer place-profile external actions when data exists.
  - Why: the Beli-style place profile should have useful actions, but alpha must not show dead/empty buttons or depend on paid APIs before billing is approved.
  - Current rule: always support Directions from coordinates; show Website, Call, and Order only when MapKit/provider/user-captured data actually supplies the URL or phone. Hide missing actions.
  - Google Places reviews should not be used in the no-billing alpha path; official Google Places fields put reviews in a paid field tier.

- Decide whether native Contacts integration ships in v0.1. Done 2026-06-01.
  - Why: contacts are a recommended people-finding affordance, but native Contacts adds permission/privacy and App Store disclosure work.
  - Decision: native Contacts is planned later, not in v0.1. Build the contacts-first UI against `FakeContactProvider` plus username search.
  - Later native scope: add pre-permission copy, denied-permission UX, hashed matching, backend privacy rules, App Store disclosure, seeded/contact test fixtures, and contact-import QA.

- Add lightweight LLM Discover query parser up front.
  - Why: Joe wants natural-language/smart query UX early, but execution should stay constrained to structured filters.
  - Implementation path: parse only the raw search phrase plus filter schema into filter JSON via a cheap/swappable model path, render editable chips, cache repeated parses, and fall back to smart filter chips on failure.

- Define v0.1 sync conflict behavior.
  - Why: offline save/edit/delete must be predictable before implementing repositories and sync queue.
  - Decision: simple `updated_at`/server-wins handling plus local retry queue; field-level multi-device merge is out of scope.

- Define analytics events behind a vendor-neutral interface.
  - Why: capture, social graph, Discover parse quality, extraction quality, and sync failures need instrumentation, but provider choice should not block the plan.
  - Decision: name events now; choose PostHog/Amplitude/etc. later.

- Create `DESIGN.md` before implementation. Done 2026-06-01.
  - Why: the design review found no project-level design system, and implementation needs stable tokens/components.
  - Result: root `DESIGN.md` now captures product feel, IA, handoff token source, components, onboarding rules, accessibility, and plan-eng-review dependencies.
  - Follow-up: font package/licensing and architecture-sensitive states still need validation.

- Decide whether to approve gstack designer variant generation. Done 2026-06-01.
  - Why: plan-design-review used the existing mocks but could not generate a new visual comparison board without external-call approval.
  - Decision: do not block eng plan. Current handoff package remains the source of truth.
