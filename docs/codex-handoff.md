# Codex Handoff

Last updated: 2026-06-01

This is the short durable handoff for a new developer or Codex instance joining rec.me, formerly Wander. It summarizes the repo state, decisions, current work, open questions, and where the real source documents live.

## Current Repo State

Latest pushed main at the time this handoff was written:

```text
962efce feat: build local m2 product loop
7edbea2 docs: complete m2 design gate
3b109ad feat: rebuild audited ios foundation
7f12630 docs: lock reset audit contract
c3ac87f chore: reset low-pass ios implementation
```

What is already built:

- Native SwiftUI shell with four tabs: Map, Add, Discover, Profile.
- Settings opens from Profile gear, not a fifth tab.
- SwiftUI design tokens and shared controls.
- Local seeded data store in `Wander/Services/WanderLocalStore.swift`.
- Real MapKit M2 map surface with seeded pins and filters.
- Add flow for current-location/manual plus honest link/photo unresolved draft shells.
- Discover surface with smart filters, username/profile lookup, and fake contacts.
- Profile/settings surfaces with follow/unfollow/block, graph lists, blocked users, default visibility, and local sync/draft hints.
- Tests for tokens, navigation, visibility, sync state machine, deterministic parser, and local store behavior.

Verification on 2026-06-01:

```text
xcodebuild test ... -> 18 tests, 0 failures
```

Important local caveat: after the push, the local worktree showed an uncommitted `Wander.xcodeproj/project.pbxproj` signing/team diff. Treat it as local Xcode signing churn unless Joe explicitly wants it committed.

## Product Summary

rec.me is a native iOS social map for remembering places worth returning to and discovering places through trusted people.

North Star:

> When I need a place, rec.me shows me where my trusted people have actually been, what they thought, and whether it fits the moment.

Wedge:

> rec.me turns trusted people's place memories into a searchable map you can actually use.

Core loop:

```text
capture a place -> mark been/wanna go -> answer useful questions -> see it on your map -> discover through people you follow
```

Do not turn this into:

- a manual lists app
- a public global feed
- a live-location or check-in game
- a travel-only app
- a restaurant-only ranking app

## Locked Decisions

| Area | Decision |
|---|---|
| Platform | Native iOS, SwiftUI, iPhone-first, iOS 17+. |
| Project | `project.yml`/XcodeGen owns Xcode project generation. |
| Backend | Clerk + Supabase. Clerk owns identity/account; Supabase owns Postgres/RLS/PostGIS/storage/functions. |
| Local data | SwiftData/local-first cache and sync queue. |
| Graph | One-way follows; friends are mutual follows. |
| Visibility | UI: Everyone/Friends/Self. Data: `followers`/`mutuals`/`self`. |
| Profiles | Profile is both personal place memory and public/self profile. |
| Settings | Gear from Profile only, not a tab. |
| People finding | Username search and contacts-shaped UI. Native Contacts later. |
| Places | MapKit-only for v0.1, provider-extensible later. |
| Extraction | Backend extraction jobs later. M2 link/photo are unresolved draft shells. |
| Discover parser | Deterministic parser in M2; cheap swappable LLM parser planned in M5. |
| Share extension | Deferred until in-app loop works. |
| Onboarding | Full onboarding deferred; auth gates appear at save/sync/follow/social-save intent. |
| Testing | Every milestone needs tests. |

Full decision record: `docs/decisions.md`.

## Architecture

Current app shape:

```text
Wander/App
  WanderApp.swift
  WanderRootView.swift

Wander/DesignSystem
  WanderTheme.swift

Wander/Features
  Map/MapScreen.swift
  Add/AddScreen.swift
  Discover/DiscoverScreen.swift
  Profile/ProfileScreen.swift
  Settings/SettingsScreen.swift

Wander/Models
  LocalModels.swift
  WanderEnums.swift
  VisibilityPolicy.swift
  SyncStateMachine.swift

Wander/Services
  WanderFixtures.swift
  WanderLocalStore.swift
  RepositoryProtocols.swift
  ContactProvider.swift
  DeterministicFilterParser.swift
```

Rules:

- Views can use local store/fakes now but should not grow direct network knowledge.
- Backend integration should land behind repository protocols.
- App-side visibility is for local UI behavior only. Supabase RLS must be authoritative.
- Keep fixture behavior deterministic so tests and screenshots are stable.

## Current Task

The immediate active task is visual QA and polish of the M2 native UI.

Failure case from Joe's simulator screenshot on 2026-06-01:

- App content appears undersized/letterboxed inside iPhone 17 Pro simulator.
- Map does not fill/orient correctly to the screen.
- Search, chips, bottom sheet, and tab bar are oversized and crowded.
- Bottom sheet and tab bar compete for space.
- Overall screen does not respect native iPhone full-screen/safe-area expectations.

Recommended next implementation order:

1. Fix Map screen layout first.
2. Confirm root app/window setup and safe-area usage are not causing the letterboxed frame.
3. Re-scale top search, filter chips, selected place sheet, and tab bar for actual device size.
4. Run simulator visual QA on iPhone 17 Pro/current target and one smaller phone.
5. Only then continue to polish Add, Discover, Profile, and Settings.

## Current Roadmap

See `docs/roadmap.md`.

Short version:

- M0/M1/M1.5 are complete enough for implementation.
- M2 local product loop is code-complete and test-green, but not visually accepted.
- M3 is Clerk + Supabase schema/RLS foundation.
- M4 is sync/remote repositories.
- M5 is extraction plus cheap LLM Discover parser.

## Open Questions And Risks

See `docs/open-questions.md`.

Highest risk items right now:

- Native UI quality and safe-area/orientation correctness.
- Exact Clerk claim mapping for Supabase RLS.
- Supabase migration/RLS policy tests.
- Slate extraction evaluation for Instagram/location gaps.
- Funnel font packaging/licensing.
- LLM parser provider/model and data minimization.

## Useful References

- `README.md` - repo overview and primary commands.
- `AGENTS.md` - durable repo instructions for agents.
- `docs/setup.md` - local setup and verification commands.
- `docs/specs/wander-ios-product-spec.md` - product source of truth.
- `docs/plans/2026-06-01-wander-ios-eng-plan.md` - milestone plan.
- `docs/plans/2026-06-01-wander-m1-5-contract-lock.md` - schema/RLS/local contracts.
- `DESIGN.md` - design system and UI rules.
- `preview/follow-profile-settings-mocks/` - approved visual source of truth.
- `preview/follow-profile-settings-mocks/tokens.css` - canonical colors/tokens.
- `docs/reviews/2026-06-01-plan-eng-review.md` - engineering review.
- `docs/reviews/2026-06-01-plan-design-review.md` - design review.
- `docs/agent-log.md` - coordination log for all agents.
- `TODOS.md` - planning backlog.

## Bootstrap Prompt For A New Codex

Use this when a new Codex or developer joins:

> Read `AGENTS.md`, `README.md`, `docs/codex-handoff.md`, `docs/roadmap.md`, `docs/decisions.md`, `docs/open-questions.md`, `docs/setup.md`, `docs/agent-log.md`, and the current repo. Summarize the app, architecture, setup, current priorities, risks, and what to do next. Do not change files yet.
