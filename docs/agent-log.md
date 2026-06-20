# Agent Log

This is the shared work log for all agents and developers working in this repo.

Rules:

- Add an entry before non-trivial work starts.
- Add checkpoints during long work or when direction changes.
- Add a completion/handoff entry with tests, commits, known issues, and next steps.
- Mention dirty worktree changes you did not make. Do not revert them without explicit instruction.
- Keep entries concrete enough that another agent can resume without reading the whole chat.

## 2026-06-01 - Codex - Morning Reset, M2 Local Loop, Handoff Docs

Agent: Codex
Branch: `main`
Status at start of this log entry: local `main` matched `origin/main` at `962efce`, with one uncommitted Xcode project signing/team diff in `Wander.xcodeproj/project.pbxproj`.

### What Happened

- Joe asked to audit/reset earlier low-pass implementation work and redo from a stronger plan.
- Low-pass native implementation was reset in commit `c3ac87f`.
- Audited plan/docs were locked in:
  - `7f12630 docs: lock reset audit contract`
  - `7edbea2 docs: complete m2 design gate`
- Rebuilt the native foundation and M2 local product loop:
  - `3b109ad feat: rebuild audited ios foundation`
  - `962efce feat: build local m2 product loop`
- Pushed `962efce` to GitHub `main`.
- Verified with `xcodebuild test`; latest successful run had 18 tests and 0 failures.

### M2 Implementation Summary

Built locally with deterministic fixtures:

- Four tabs: Map, Add, Discover, Profile.
- Settings from Profile gear only.
- MapKit map with seeded own/social pins and filters.
- Add flow with current-location/manual save, visibility picker, contextual questions, and honest link/photo unresolved drafts.
- Discover with smart filters, username/profile lookup, contacts-shaped UI, and social save.
- Profile/settings with follow/unfollow/block, followers/following lists, default visibility, blocked users, drafts, and local sync hints.
- `WanderStore` manages seeded local state, visibility filtering, follow/block behavior, discover parsing, drafts, and saves.

### Tests Run

Known successful command:

```bash
xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

Result:

```text
18 tests, 0 failures
```

Coverage includes token values, tab navigation, visibility policy, sync state transitions, deterministic Discover parser, save merge behavior, drafts, profile search, block behavior, current-location metadata, and graph edge lists.

### Current Known Issue

Joe shared a simulator screenshot showing the M2 Map screen looks bad:

- App content is undersized/letterboxed inside the iPhone simulator.
- Map does not fill and orient naturally to the device screen.
- Search, chips, selected place sheet, and tab bar are too large/crowded.
- Bottom sheet and tab bar compete for vertical space.

Next implementation task: fix root/Map layout sizing and safe areas first, then sweep Add/Discover/Profile/Settings.

### Dirty Worktree Caveat

There is an uncommitted generated Xcode project diff:

- `Wander.xcodeproj/project.pbxproj`

Observed contents look like local Xcode signing/team churn, including `DEVELOPMENT_TEAM = Y7TVK75RZ8` and an `explicitFileType` change for `Wander.app`.

Do not include this in docs or UI commits unless Joe explicitly wants local signing settings committed.

### Token/Usage Sketch For The Morning

Exact token/billing usage is not visible inside the repo or terminal. Qualitatively, the morning spent a lot of context on:

- Reconstructing product decisions from the long thread.
- Running plan/design/engineering review workflows and writing durable specs.
- Rebuilding the native SwiftUI app foundation.
- Implementing the M2 local product loop across Map, Add, Discover, Profile, Settings, models, services, and tests.
- Iterating through Xcode build/test failures and long compiler logs.
- Verifying GitHub `main` and pushing commits.
- Diagnosing the simulator screenshot and creating this catch-up/handoff package.

The highest-token sinks were likely long repository/document reads, Swift/Xcode build output, multi-file diffs, and the large planning/spec context.

### Disk Space Note

While creating this handoff, the machine had only about 100 MB free on `/System/Volumes/Data`. Clearing generated Xcode build artifacts freed enough space:

- Removed repo-local `DerivedData`.
- Cleared global Xcode DerivedData cache under `/Users/joelipshutz/Library/Developer/Xcode/DerivedData`.

These were generated build caches, not source files.

### Next Steps

1. Commit the handoff docs and agent log rules.
2. Fix M2 native UI sizing/layout, starting with Map/root safe-area behavior.
3. Run build/tests.
4. Capture simulator screenshots if possible.
5. Commit and push the visual fix.

## 2026-06-01 - Codex - M2 Native UI Sizing Fix

Agent: Codex
Branch: `main`
Starting commit: `c452297`
Starting status: local `main` matches `origin/main`; `Wander.xcodeproj/project.pbxproj` has an unstaged local signing/team diff that should remain untouched unless Joe asks.

Goal: fix the simulator screenshot failure where the M2 Map UI is letterboxed/undersized and controls are crowded. Start by inspecting app/root launch configuration, safe-area handling, and Map screen layout. Then patch the smallest stable surface, run tests, capture screenshots if possible, commit, and push.

Expected files to inspect/touch:

- `Wander/Resources/Info.plist`
- `Wander/App/WanderRootView.swift`
- `Wander/Features/Map/MapScreen.swift`
- `Wander/DesignSystem/WanderTheme.swift`
- `docs/agent-log.md`

Checkpoint:

- `Wander/Resources/Info.plist` had no launch-screen declaration. Added `UILaunchScreen` and portrait orientation, which should remove iOS compatibility letterboxing on modern simulators.
- `Wander/Features/Map/MapScreen.swift` was tightened for native scale: full-screen map ignores safe areas, smaller search bar, smaller map filter chips, smaller pins, and a more compact selected place sheet.

Completion checkpoint, 2026-06-01 11:28 PDT:

- Ran the full test suite after the sizing patch:

```bash
xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

- Result: 18 tests, 0 failures.
- Captured simulator screenshots:
  - `DerivedData/wander-map-after-final-iphone16plus.png`
  - `DerivedData/wander-map-after-final-iphone16e.png`
- Visual result: the iOS letterboxing/undersized app frame is fixed on both targets. Map now fills the screen. Search, chips, pins, and selected-place sheet are materially more compact. On smaller phones the filter chips remain horizontally scrollable by design.
- Remaining local caveat: `Wander.xcodeproj/project.pbxproj` still has an unstaged local signing/team diff that was not part of this work and should remain uncommitted unless Joe explicitly wants it.

## 2026-06-01 - Codex - M2.1 Visual QA Sweep

Agent: Codex
Branch: `main`
Starting commit: `32e3edc`
Starting status: local `main` matches `origin/main`; `Wander.xcodeproj/project.pbxproj` has the same unstaged local signing/team diff and should remain untouched.

Goal: sweep the remaining M2 native screens after the Map letterboxing fix. Capture/navigate Add, Discover, Profile, Settings, and related profile/list/draft states where practical; patch obvious sizing, safe-area, truncation, and density issues; run tests; commit and push.

Expected files to inspect/touch:

- `Wander/App/WanderRootView.swift`
- `Wander/Features/Add/AddScreen.swift`
- `Wander/Features/Discover/DiscoverScreen.swift`
- `Wander/Features/Profile/ProfileScreen.swift`
- `Wander/Features/Settings/SettingsScreen.swift`
- `Wander/DesignSystem/WanderTheme.swift`
- `docs/agent-log.md`

Completion checkpoint, 2026-06-01 15:28 PDT:

- Added QA launch arguments in `WanderRootView`:
  - `-WanderInitialTab add|discover|profile`
  - `-WanderOpenSettings`
- Compact visual sweep:
  - Add: reduced row/card height, icon size, header/subtitle scale, and draft/saved state bulk.
  - Discover: reduced header/search density, people card height, smart-filter height, and place-row padding.
  - Profile: reduced owner card, stat tiles, month card, empty rows, and recent rows.
  - Settings: reduced row/card density and fixed visibility/blocked cards shrinking to content width.
- Captured screenshots under `DerivedData/visual-sweep/`:
  - iPhone 16 Plus: Add, Discover, Profile, Settings.
  - iPhone 16e: Add, Discover, Profile, Settings.
- Visual result: no iOS letterboxing, no obvious clipping, no tab-bar overlap on reviewed first-view screens. Discover remains the densest screen but now shows the first result fully and the second result partially on iPhone 16e.
- Ran full test suite:

```bash
xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

- Result: 20 tests, 0 failures.
- Latest passing result bundle: `DerivedData/Logs/Test/Test-Wander-2026.06.01_15-29-13--0700.xcresult`.
- Remaining local caveat: `Wander.xcodeproj/project.pbxproj` still has the unrelated unstaged local signing/team diff and should remain uncommitted unless Joe asks.

## 2026-06-02 - Codex - M2 Interaction Punch List

Agent: Codex
Branch: `main`
Starting commit: `0d861f0`
Starting status: local `main` matches `origin/main`; `Wander.xcodeproj/project.pbxproj` has the same unrelated unstaged local signing/team diff and should remain untouched.

Goal: finish the M2 acceptance punch list Joe approved: Discover keyboard swipe dismissal, basic Map search, Discover places section with an embedded 3-stage `my`/`friends`/`everyone` switch, and Profile people section with the same 3-stage switch for `following`/`followers`/`friends`.

Expected files to touch:

- `Wander/DesignSystem/WanderTheme.swift`
- `Wander/Features/Discover/DiscoverScreen.swift`
- `Wander/Features/Map/MapScreen.swift`
- `Wander/Features/Profile/ProfileScreen.swift`
- `Wander/Services/DiscoverModels.swift`
- `Wander/Services/WanderLocalStore.swift`
- `WanderTests/WanderStoreTests.swift`
- `docs/decisions.md`
- `docs/agent-log.md`

Checkpoint:

- Joe added Map selected-place details feedback mid-pass.
- Discover:
  - Added `.scrollDismissesKeyboard(.interactively)`.
  - Moved source scope into the Places section as a 3-way `mine` / `friends` / `everyone` segmented switch.
  - Default Discover scope is now `everyone` under current follow/privacy visibility rules.
- Profile:
  - Reworked the people section into a 3-way `following` / `followers` / `friends` switch with inline rows.
- Map:
  - Added local search over visible place name/category/locality/owner/note/rating.
  - Removed the custom marker title pill so MapKit's outside annotation title is the only place label.
  - Changed selected place sheet expansion from tap-on-handle to vertical swipe/drag.
  - Added expanded sheet answer/detail chips from current local fixture fields because M2 does not yet persist Add-flow `LocalPlaceAttribute` answers.
- During final verification, found a transient dirty typo in `Wander/App/WanderRootView.swift` (`_initialPresentation` name mangled). Restored it to committed content; no RootView diff remains.
- Tests:
  - Initial sandboxed `xcodebuild test` could not access CoreSimulator; reran with approved elevated simulator access.
  - Final command: `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
  - Result: 22 tests, 0 failures.
  - Latest passing result bundle: `DerivedData/Logs/Test/Test-Wander-2026.06.02_12-56-11--0700.xcresult`.
- No screenshots captured for this pass; Joe said he would test and wanted push/merge first.

## 2026-06-02 - Codex - Persist Add Question Answers

Agent: Codex
Branch: `main`
Starting commit: `eba2c70`
Starting status: local `main` matches `origin/main`; `Wander.xcodeproj/project.pbxproj` has the same unrelated unstaged local signing/team diff and should remain untouched.

Goal: wire Add-flow contextual question answers into `LocalPlaceAttribute`, show those persisted answers in the expanded Map place sheet, commit/push, then continue into M3 backend foundation.

Current question source:

- Code currently has starter blocks: `how's the vibe?`, `good for working?`, and `tags`.
- Spec defines category templates but does not enumerate all options. Implementing starter category-aware templates now:
  - Coffee: rating, work setup, coffee tags.
  - Hike: rating, strenuousness, hike tags.
  - Restaurant: rating, price, occasion, restaurant tags.
  - Bar/park/default: rating plus lightweight category tags.

Expected files to touch:

- `Wander/Features/Add/AddScreen.swift`
- `Wander/Features/Map/MapScreen.swift`
- `Wander/Models/LocalModels.swift`
- `Wander/Services/RepositoryProtocols.swift`
- `Wander/Services/WanderFixtures.swift`
- `Wander/Services/WanderLocalStore.swift`
- `WanderTests/WanderStoreTests.swift`
- `docs/decisions.md`
- `docs/agent-log.md`

Completion checkpoint:

- Added category-aware Add question templates while keeping answer persistence open-ended for future custom/user-created questions.
  - Coffee: rating/excitement, work setup, tags.
  - Hike: rating/excitement, strenuousness, tags.
  - Restaurant: rating/excitement, price, occasion, tags.
  - Bar/park/default: rating/excitement plus lightweight category tags.
- Added `PlaceAttributeDraft` and store-level `placeAttributes` state.
- `saveCandidate` now accepts optional answer attributes:
  - Add details passes attributes and persists them.
  - Existing callers that omit attributes preserve existing answers instead of wiping them.
  - Explicitly provided attributes replace the old answer set for that saved place.
- Seeded Woodcat, Griffith, and Larchmont with real `LocalPlaceAttribute` rows.
- Expanded Map place sheet now reads persisted attributes instead of category-derived placeholder chips.
- Social saves copy source place attributes into the saved place.
- `pendingSyncCount` now includes unsynced attributes.
- Locked the flexible-answer/custom-question decision in `docs/decisions.md`.
- Tests:
  - First run failed on a missing `return` in `saveVisiblePlace` after adding copied attributes; fixed.
  - Final command: `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
  - Result: 24 tests, 0 failures.
  - Latest passing result bundle: `DerivedData/Logs/Test/Test-Wander-2026.06.02_13-12-47--0700.xcresult`.
- No screenshots captured for this pass.

## 2026-06-02 - Codex - M3 Supabase Foundation

Agent: Codex
Branch: `main`
Starting commit: `d0f624c`
Starting status: local `main` matches `origin/main`; `Wander.xcodeproj/project.pbxproj` has the same unrelated unstaged local signing/team diff and should remain untouched.

Goal: start M3 backend foundation with Supabase schema/RLS/RPC contract artifacts before wiring iOS Clerk UI. Include question-definition support so future user-created/custom questions can be added without changing answer columns.

Environment note:

- `supabase` CLI is not installed locally.
- `psql` is not installed locally.
- I can write migration and SQL policy test files, but cannot execute them in this environment until a Supabase/Postgres runner is available.

Expected files to touch:

- `supabase/migrations/20260602131500_m3_foundation.sql`
- `supabase/tests/rls_visibility.sql`
- `docs/backend/m3-supabase-foundation.md`
- `docs/agent-log.md`
- `docs/decisions.md` if M3 backend decisions need to be locked.

Checkpoint:

- Added first M3 migration under `supabase/migrations/`.
- Added pgTAP-style RLS visibility tests under `supabase/tests/`.
- Verified current official Clerk/Supabase docs: native Clerk Supabase integration uses Clerk session tokens, `role=authenticated`, and RLS can read the Clerk user id from `auth.jwt()->>'sub'`.
- Added explicit `question_definitions` support for future user-created questions/inputs:
  - System starter prompts are global.
  - User custom prompts are owner-authored.
  - Attached custom prompt metadata becomes readable only through visible place attributes.
  - Answers stay JSON-backed in `place_attributes`; do not add hardcoded answer columns for new prompts.
- Tightened profile/map RPCs so they return joined place rows with attributes, not raw `user_places` rows.
- Removed authenticated client update access for canonical `places`; future reconciliation should use service-role backend code.
- Added `docs/backend/m3-supabase-foundation.md`.
- Updated `docs/decisions.md` and `docs/open-questions.md` for Clerk `sub` mapping and M3 test-runner status.

## 2026-06-02 - Codex - M3 Project Setup And Verification

Agent: Codex plus sub-agents `Godel` and `Epicurus`
Branch: `main`
Starting commit: `08b7aca`
Starting status: local `main` matches `origin/main`; `Wander.xcodeproj/project.pbxproj` has the same unrelated unstaged local signing/team diff and should remain untouched.

Goal: proceed with M3 setup using new Supabase and Clerk projects, verify the Supabase migration/RLS tests, and document any account/credential blockers.

Coordination:

- Spawned Supabase setup explorer sub-agent `Godel`.
- Spawned Clerk setup explorer sub-agent `Epicurus`.
- Mission Control create-task attempt to `http://localhost:4000/api/tasks` failed because localhost:4000 was not reachable.

Expected files to touch:

- `docs/agent-log.md`
- `docs/backend/m3-supabase-foundation.md`
- `docs/setup.md` if local Supabase/Clerk setup commands are confirmed
- Supabase config files if CLI initialization succeeds

Initial local findings:

- `brew`, `npm`, and `npx` are available.
- `supabase`, `psql`, and `clerk` CLIs are not currently installed.
- Existing `supabase/` folder contains the M3 migration/test artifacts only.

Checkpoint:

- Supabase sub-agent `Godel` confirmed no existing Wander Supabase project was linked, no local Docker, no `psql`, no Supabase access token before login, and noted generated config expected missing `supabase/seed.sql`.
- Clerk sub-agent `Epicurus` confirmed no existing Wander Clerk app/config and found iOS bundle id `com.grayline.wander` in `project.yml`.
- Logged into Supabase CLI with Joe's browser verification.
- Created new Supabase hosted project:
  - Name: `wander`
  - Ref: `rugmtlgufrhlxwfkumhw`
  - Region: `us-west-2`
- Stored Supabase project ref, DB password, URL, anon key, and service role key in `/Users/joelipshutz/.openclaw/workspace/.env.keys`.
- Ran `npx supabase init` and normalized `supabase/config.toml` project id to `wander`.
- Disabled Supabase seed because generated config referenced missing `supabase/seed.sql`.
- Linked the repo to the new Supabase project.
- Ran migration dry-run: one migration detected, `20260602131500_m3_foundation.sql`.
- Pushed migration to hosted Supabase. PostGIS metadata privilege warnings appeared but migration completed successfully.
- Verified remote migration list: local and remote both have `20260602131500`.
- `npx supabase test db --linked supabase/tests/rls_visibility.sql` failed because the CLI still tried to use Docker.
- Installed temporary Node `pg` client under `/private/tmp/wander-pg-runner` and ran `supabase/tests/rls_visibility.sql` against hosted Postgres.
- Hosted RLS test result: 15 pgTAP assertions, 0 failures.
- Logged into Clerk CLI as `joe@bondaiapp.com`.
- Existing Clerk apps were TheEssayPress and Signal; no Wander app existed.
- Created new Clerk app:
  - Name: `Wander`
  - App id: `app_3Eb3JbpbMDjOA2qKUCqfsZwfct9`
  - Development instance: `ins_3Eb3Je6FO3qfUDIt5n3aTHMxYN1`
  - Development domain: `growing-pheasant-22.clerk.accounts.dev`
- Linked repo to new Clerk app.
- Patched Clerk development session token claims to include `role: authenticated`.
- Pulled Clerk env values into `/private/tmp/wander-clerk.env` and appended them to `.env.keys`.
- Added local Supabase Clerk third-party auth config in `supabase/config.toml`.
- Ran `npx supabase config push`; it pushed generated local auth defaults plus the Clerk config to the new hosted project. Review hosted auth settings before alpha.
- Spawned Edge Function review sub-agent `Fermat`, which flagged handle collision, replay/stale event, delete-event typing, and runtime secret issues before finalizing the webhook.
- Added Clerk profile mirroring migration `20260602140304_clerk_profile_mirroring.sql`:
  - Adds `clerk_updated_at` and `last_clerk_event_id` to `profiles`.
  - Adds `clerk_webhook_events` and `clerk_profile_mirror_state`.
  - Adds `app.mirror_clerk_profile` for duplicate, stale-event, handle-collision, delete-before-create, and soft-delete handling.
- Added public service-role wrapper migration `20260602143000_public_clerk_profile_mirror_rpc.sql` after direct PostgREST testing showed `/rest/v1/rpc/...` only searched the `public` schema.
- Added `supabase/tests/clerk_profile_mirroring.sql`; hosted pgTAP result is 14 assertions, 0 failures.
- Deployed Supabase Edge Function `clerk-profile-webhook`.
- Created Clerk/Svix endpoint `ep_3Eb5WlmjQlDav83RHa3hWxp07wd` pointing to `https://rugmtlgufrhlxwfkumhw.supabase.co/functions/v1/clerk-profile-webhook`.
- Stored the Svix signing secret local-only and set Supabase Edge Function secrets:
  - `CLERK_WEBHOOK_SIGNING_SECRET`
  - `WANDER_SUPABASE_URL`
  - `WANDER_SUPABASE_SERVICE_ROLE_KEY`
- Direct signed Edge Function test passed: Svix-style signature verification, RPC call, and `profiles` lookup all succeeded.
- Real Clerk/Svix create webhook test passed with disposable Clerk dev user `user_3Eb6hVABCXRiZ3tcbdvlu2NAh2j`.
- Real Clerk/Svix delete webhook test passed; the mirrored profile received `deleted_at`.
- Hosted SQL tests rerun through temporary Node `pg` runner:
  - `supabase/tests/rls_visibility.sql`: 15 assertions, 0 failures.
  - `supabase/tests/clerk_profile_mirroring.sql`: 14 assertions, 0 failures.
  - Total: 29 assertions, 0 failures.
- Redeployed the final formatted Edge Function and reran a signed smoke test against the deployed URL; `codex_redeploy_test` profile was created successfully.
- Updated `docs/setup.md`, `docs/backend/m3-supabase-foundation.md`, `docs/open-questions.md`, `docs/decisions.md`, and this log.

Known remaining M3 setup work:

- Add iOS Clerk/Supabase SDK dependencies and repository-boundary wiring.
- Add remote repository tests and auth-gated UI tests.
- Install Docker/OrbStack/Colima if we want the standard local Supabase stack and CLI pgTAP runner.
- Review hosted Supabase Auth settings before alpha because `npx supabase config push` pushed generated local auth defaults plus Clerk config.

## 2026-06-02 14:27 PDT - Codex - M3 iOS Clerk/Supabase Wiring

Agent: Codex plus parallel explorers `Socrates`, `Euclid`, and `Ohm`
Branch: `main`
Starting commit: `b8de80d`
Starting status: local `main` matches `origin/main`; `Wander.xcodeproj/project.pbxproj` has the same unrelated local signing/file-type diff and should remain unstaged unless Joe explicitly asks.

Goal: execute the next slice of the existing engineering plan, not create a new plan: add iOS Clerk/Supabase SDK wiring behind repository/auth boundaries, introduce auth gates at save/sync/follow/social-save intent points, and keep views from calling Clerk/Supabase directly.

Coordination:

- Source plan: `docs/plans/2026-06-01-wander-ios-eng-plan.md`, especially M3 Clerk + Supabase Foundation and D14 auth gates.
- Mission Control task creation to `http://localhost:4000/api/tasks` failed because localhost:4000 is not reachable.
- GBrain search for Wander Clerk/Supabase context timed out on a PGLite lock; proceeding from repo docs and this agent log.
- Spawned parallel explorers:
  - `Socrates`: project.yml/SwiftPM dependency mechanics.
  - `Euclid`: service/repository boundary recommendations.
  - `Ohm`: UI auth-gate insertion points.

Expected files to touch:

- `project.yml`
- `Wander/App/*`
- `Wander/Services/Auth/*`
- `Wander/Services/Remote/*`
- `Wander/Services/RepositoryProtocols.swift`
- Feature files only where auth gates are wired.
- `WanderTests/*` for auth/repository contract coverage.
- `docs/agent-log.md`, and docs/decisions/open-questions only if new durable decisions appear.

Initial implementation checklist:

- Add Clerk/Supabase SwiftPM packages through XcodeGen.
- Add auth session provider and minimal auth gate state.
- Add Supabase client factory using local non-secret config and Clerk session token boundary.
- Add remote repository shells/DTOs behind protocols.
- Gate save/sync/follow/social-save intents without implementing full onboarding.
- Regenerate Xcode project and run the full `xcodebuild test` command before committing.

## 2026-06-01 - Codex - Discover People Rail Fix

Agent: Codex
Branch: `main`
Starting commit: `89988a0`
Starting status: local `main` matches `origin/main`; `Wander.xcodeproj/project.pbxproj` has an unstaged local signing/team diff containing `DEVELOPMENT_TEAM = Y7TVK75RZ8`, generated app file type churn, and target-attribute cleanup. Treat as unrelated unless Joe explicitly wants signing metadata committed.

Goal: update Discover's people rail so it starts with an add-person affordance and only shows users who are actually on Wander. Non-Wander contact rows should not appear in the people rail.

Expected files to touch:

- `Wander/Features/Discover/DiscoverScreen.swift`
- `WanderTests/WanderStoreTests.swift` or related tests if store behavior needs coverage
- `docs/agent-log.md`

Completion checkpoint:

- Changed `WanderStore.contactMatches()` to exclude contacts without a matched Wander `userID`, so non-Wander contacts are not shown in social rails.
- Updated Discover people rail to show a fixed add-person card to the left of the horizontal people scroll. Tapping it seeds username search with `@` and focuses the search field.
- Deduplicated Discover profile search results against matched contact user IDs, so Maya does not appear twice when also returned from username search.
- Visual QA screenshots:
  - `DerivedData/visual-sweep/after-discover-add-rail-iphone16plus.png`
  - `DerivedData/visual-sweep/after-discover-add-rail-iphone16e.png`
- Tests: `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Result: 21 tests, 0 failures.
- Latest passing result bundle: `DerivedData/Logs/Test/Test-Wander-2026.06.01_17-06-34--0700.xcresult`.
- Remaining local caveat: `Wander.xcodeproj/project.pbxproj` still has the unrelated unstaged local signing/team diff and should remain uncommitted unless Joe asks.

## 2026-06-02 - Codex - Map Filter Label Alternatives

Agent: Codex
Branch: `main`
Starting commit: `7d58068`
Starting status: local `main` matches `origin/main`; `Wander.xcodeproj/project.pbxproj` has the same unrelated unstaged local signing/team diff and should remain untouched.

Goal: quickly mock alternate active/inactive treatments for the Map filter/label chips because the current selected state is not clear enough. Produce a reviewable HTML/PNG artifact, not production SwiftUI changes yet.

Expected files to touch:

- `preview/map-filter-label-alts/index.html`
- `preview/map-filter-label-alts/map-filter-label-alts.png` if rendering succeeds
- `docs/agent-log.md`

Checkpoint:

- Joe clarified this should be a focused color/border state study, not full phone mocks.
- Added focused artifact: `preview/map-filter-label-alts/states.html`.
- Rendered PNG: `preview/map-filter-label-alts/map-filter-state-options.png`.
- Recommendation in the mock: Option 2, active = white fill + terracotta ring/check, inactive = faded bone fill + muted border/hollow icon.

## 2026-06-02 - Codex - M2 Visual Acceptance Pass

Agent: Codex
Branch: `main`
Starting commit: `7d58068`
Starting status: local `main` matches `origin/main`; `Wander.xcodeproj/project.pbxproj` has the same unrelated unstaged local signing/team diff. Existing uncommitted work includes the map filter state mock artifacts and this log.

Goal: implement Joe's approved M2 visual feedback before M3: map filter active ring states, place labels on map, selected/tapped pin state, selected place expanded screen for Larchmont Noodles, facepile/social proof instead of "`Name`'s tip", simpler screen titles, Profile organization cleanup, and Discover hierarchy with places above filters plus my/friends place toggle.

Expected files to touch:

- `Wander/Features/Map/MapScreen.swift`
- `Wander/Features/Discover/DiscoverScreen.swift`
- `Wander/Features/Profile/ProfileScreen.swift`
- `Wander/Features/Settings/SettingsScreen.swift`
- `Wander/Services/WanderLocalStore.swift`
- `Wander/Services/DiscoverModels.swift`
- `Wander/App/WanderRootView.swift` only if QA launch support needs a selected map state
- `docs/decisions.md`
- `docs/agent-log.md`

Completion checkpoint:

- Locked M2 visual decisions in `docs/decisions.md`.
- Map:
  - Active filters now keep the bone/sand chip fill and add a terracotta ring/icon.
  - Removed the `friends` map filter chip per Joe; map scope now shows `you`, `social`, `been`, `wanna`.
  - Added vertical padding to the chip rail so active outlines do not clip.
  - Added map place labels and selected/tapped pin styling.
  - Added expandable selected place sheet and QA launch args for Larchmont Noodles.
  - Replaced "`Name`'s tip" with facepile/social proof copy like "Ryan saved it".
- Discover:
  - Simplified title to `discover`.
  - People section stays near the top under search.
  - Places are the primary content above filters.
  - Added `my places` / `friends' places` toggle and matching store scope.
- Profile:
  - Simplified title to `profile`.
  - Removed bio quote from the owner header.
  - Moved following/followers/friends into a lower `people` section.
- Settings:
  - Simplified title to `settings`.
- Tests: `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Result: 22 tests, 0 failures.
- Latest passing result bundle: `DerivedData/Logs/Test/Test-Wander-2026.06.02_11-08-03--0700.xcresult`.
- Visual screenshots captured before final Joe stop:
  - `DerivedData/visual-sweep/m2-visual-acceptance-map-larchmont-expanded-iphone16plus.png`
  - `DerivedData/visual-sweep/m2-visual-acceptance-discover-iphone16plus.png`
  - `DerivedData/visual-sweep/m2-visual-acceptance-profile-iphone16plus.png`
  - `DerivedData/visual-sweep/m2-visual-acceptance-settings-iphone16plus.png`
- Remaining local caveat: `Wander.xcodeproj/project.pbxproj` still has the unrelated unstaged local signing/team diff and should remain uncommitted unless Joe asks.

## 2026-06-02 - Codex - M3 iOS Wiring Checkpoint

Agent: Codex
Branch: `main`
Starting commit: `b8de80d`
Starting status: local `main` matched `origin/main`; `Wander.xcodeproj/project.pbxproj` already had unrelated local generated/signing churn and should not be committed unless intentional.

Goal: continue the existing engineering plan's M3 iOS work, not create a new plan. Wire Clerk/Supabase behind service boundaries, gate account-required UI actions, add contract tests, then regenerate/build/test.

Checkpoint:

- Confirmed Mission Control was not reachable locally and GBrain was locked earlier; continued from repo docs and existing eng plan.
- Closed completed subagents after folding in their findings.
- Added Clerk/Supabase package/config entries in `project.yml`, app Info.plist keys, and associated-domain entitlements.
- Added `AuthSessionProviding`, `ClerkAuthService`, `AuthGateSheet`, `WanderSupabaseClient`, Supabase DTOs, and Supabase repository conformers.
- Wired auth gate state at `WanderApp` / `WanderRootView`.
- Gated Add sync intent, Discover follow/social save, Map social save, Profile follow/unfollow/block, graph-list follow/unfollow, Settings unblock/data-sync.
- Replaced the placeholder Supabase RPC shell with a REST RPC transport that attaches the Clerk/Supabase JWT through `Authorization`.
- Added tests:
  - `WanderTests/AuthSessionTests.swift`
  - `WanderTests/RemoteRepositoryTests.swift`
  - `WanderTests/BoundaryImportTests.swift`

Next: run `xcodegen generate`, inspect generated project churn carefully, then build/test and fix compile/API issues.

Completion checkpoint:

- Ran `xcodegen generate` successfully and confirmed the project churn is the intentional SwiftPM/package/entitlements wiring for Clerk and Supabase.
- SwiftPM resolved:
  - Clerk iOS at `1.1.4`
  - Supabase Swift at `2.46.0`
- Fixed the first full test failure by removing `convertFromSnakeCase` from the remote DTO decoder, since the DTOs already use explicit snake_case `CodingKeys`.
- Full test command:
  `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Result: 32 tests, 0 failures.
- Latest passing result bundle: `DerivedData/Logs/Test/Test-Wander-2026.06.02_14-47-32--0700.xcresult`.
- Files changed for the commit include `project.yml`, generated `Wander.xcodeproj` package references/SwiftPM lockfile, backend config/auth/remote service files, auth gates across M2 UI surfaces, and the three new test files.
- Known caveat: project signing/team settings are local-machine state and should remain uncommitted if Xcode reintroduces them.

## 2026-06-02 18:54 PDT - Codex - M3 Remote Wiring Continuation

Agent: Codex
Branch: `main`
Starting commit: `1051878`
Starting status: local `main` matches `origin/main`; `Wander.xcodeproj/project.pbxproj` has only the expected uncommitted local `DEVELOPMENT_TEAM = Y7TVK75RZ8` signing diff and should remain uncommitted.

Goal: continue the existing M3 plan by moving from service-boundary scaffolding toward live app behavior. Add a backend container/fallback path so signed-in social actions can attempt Supabase RPCs without views importing Clerk/Supabase, keep local-first behavior when signed out/offline, and document local secret setup for the smoke test.

Expected files to touch:

- `Wander/App/WanderApp.swift`
- `Wander/App/WanderRootView.swift`
- `Wander/App/WanderBackend.swift`
- `Wander/Services/WanderLocalStore.swift`
- `Wander/Services/Remote/SupabaseRepositories.swift`
- `WanderTests/RemoteRepositoryTests.swift`
- `WanderTests/AuthSessionTests.swift` if auth store behavior needs a regression test
- `docs/setup.md`
- `docs/agent-log.md`

Initial findings:

- Mission Control is still unavailable on `localhost:4000`.
- GBrain timed out waiting for the PGLite lock, so this pass is using checked-in Wander docs as source of truth.
- The M3 exit criteria still missing in-app are: sign-in smoke test with local publishable keys, profile mirror confirmation from the app, local saved-place sync, and visible social pin fetch.

Completion checkpoint:

- Added `WanderBackend` as the app-level remote repository container.
- `AuthSessionStore` now conforms to `AuthSessionProviding`, so Supabase RPC transport can get Clerk-issued Supabase tokens without views importing Clerk/Supabase.
- Wired Map/Discover/Profile/Settings social actions through remote-aware `WanderStore` methods:
  - remote profile search can merge into Discover username results
  - remote visible places can refresh into a cache for the Map surface
  - follow/unfollow/block/unblock attempt remote calls when signed in/configured
  - social save attempts `save_visible_place` and marks local copy `synced` on success or `failed` on remote failure
- Preserved local-first behavior for signed-out/offline flows and left full retry/claim queue for M4.
- Updated `docs/setup.md` with the local-only build setting injection pattern for live Clerk/Supabase smoke tests.
- Ran `xcodegen generate`.
- Full test command:
  `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Result: 35 tests, 0 failures.
- Latest passing result bundle: `DerivedData/Logs/Test/Test-Wander-2026.06.02_19-03-34--0700.xcresult`.
- Remaining known gap: live sign-in/profile-mirror smoke test still needs to be run with local publishable keys injected into the simulator build.

## 2026-06-02 20:54 PDT - Codex - M3 Extra-High Audit

Agent: Codex
Branch: `main`
Starting commit: `89bca2f`
Starting status: local `main` matches `origin/main`; `Wander.xcodeproj/project.pbxproj` has only the expected uncommitted local `DEVELOPMENT_TEAM = Y7TVK75RZ8` signing diff and should remain uncommitted.

Goal: audit the M3 auth/remote wiring before live Clerk/Supabase smoke testing or deeper M4 sync work. Focus on code/SQL contract shape, Clerk token assumptions, local-first sync transitions, UI state/error gaps, and test coverage.

Parallel audit helpers:

- Backend contract audit: compare Swift RPC names/params/DTOs to Supabase migrations/functions.
- iOS app wiring audit: inspect environment object injection, auth/session behavior, async social actions, local-first state, and test gaps.

Expected files to touch:

- `docs/agent-log.md`
- Potentially `docs/open-questions.md` or implementation files only if the audit finds a clear mismatch that is safer to fix immediately.

Initial findings:

- Mission Control remains unavailable on `localhost:4000`.
- GBrain lookup is slow/locked again; this audit is using repo docs and code as source of truth.

Completion checkpoint:

- Parallel backend audit found:
  - app RPCs lived only under private `app.*`, while PostgREST exposes `public` by default.
  - `save_visible_place` returned `public.user_places` but Swift expected `{ "user_place_id": ... }`.
  - `unblock_user` had an app surface but no SQL/RPC implementation.
  - `block_user` likely could not delete reciprocal follow rows under the existing delete RLS policy.
  - Clerk default token path still needs live verification.
- Parallel iOS audit found:
  - social-save could call remote with local fixture IDs instead of backend UUIDs.
  - remote profile search shells were not cached, so tapping a remote-only search result could open a blank profile sheet.
  - failed unfollow/unblock removed local state even if remote mutation failed.
  - remote attributes, remote relationship filtering, and visible error/retry UI need later cleanup.
- Fixes made:
  - Added migration `20260602210000_public_app_rpc_wrappers.sql`.
  - Added public PostgREST wrappers for app-facing RPCs and a JSON response shape for `public.save_visible_place`.
  - Added `app.unblock_user` / `public.unblock_user`.
  - Redefined `app.block_user` as a guarded `security definer` so hard block cleanup can remove both follow directions.
  - Wired `SupabaseBlockRepository.unblock`.
  - Changed remote social-save to require real UUID `serverID`s and pass server IDs, not fixture IDs.
  - Cached remote profile shells from Discover search.
  - Changed remote unfollow/unblock failures to keep local rows marked `failed` instead of deleting them.
- Applied the new migration to hosted Supabase with `npx supabase db push --linked`; migration `20260602210000_public_app_rpc_wrappers.sql` completed successfully.
- Full test command:
  `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Result: 39 tests, 0 failures.
- Latest passing result bundle: `DerivedData/Logs/Test/Test-Wander-2026.06.02_20-59-22--0700.xcresult`.
- Remaining known gaps before expanding M4:
  - live Clerk token/Supabase RLS smoke test
  - remote attributes hydration
  - remote relationship/filter hydration
  - explicit user-visible sync error/retry UI for failed follow/block/social-save

## 2026-06-02 21:08 PDT - Codex - M3 Live Smoke

Agent: Codex
Branch: `main`
Starting commit: `4b57c3e`
Starting status: local `main` matches `origin/main`; `Wander.xcodeproj/project.pbxproj` still has only the expected uncommitted local signing/team diff and should remain uncommitted.

Goal: run the M3 live Clerk + Supabase smoke path before adding more M4 sync work. Verify whether the current iOS token path can satisfy Supabase RLS/RPCs, then test the app/backend paths for profile/search/follow/block/social-save as far as local credentials and simulator access allow.

Expected files to touch:

- `docs/agent-log.md`
- Potentially `Wander/Services/Auth/ClerkAuthService.swift`, setup docs, or tests if the smoke exposes a fixable token/RPC/config mismatch.

Initial findings:

- Mission Control is unavailable on `localhost:4000`.
- GBrain lookup is still slow/locked; proceeding from repo docs and checked-in setup state.
- The app currently requests `Clerk.shared.auth.getToken()` without an explicit template, so the first smoke target is token acceptance by Supabase RLS/RPCs.

Checkpoint:

- Created temporary smoke runner at `/private/tmp/wander-m3-live-smoke.mjs` to avoid committing secrets or test-only code.
- The first run failed in the sandbox with `getaddrinfo ENOTFOUND api.clerk.com`; reran with approved network access.
- Hosted smoke results:
  - Clerk disposable user creation passed.
  - Clerk -> Svix -> Supabase Edge Function profile mirroring passed.
  - Clerk default session token minted successfully and decoded locally with:
    - `sub=<viewer Clerk user id>`
    - `role=authenticated`
    - `iss=https://growing-pheasant-22.clerk.accounts.dev`
    - `alg=RS256`
    - `kid=ins_3Eb3Je6FO3qfUDIt5n3aTHMxYN1`
  - Clerk JWKS at `https://growing-pheasant-22.clerk.accounts.dev/.well-known/jwks.json` returned HTTP 200 and contains that `kid`.
  - Supabase service-role seed setup passed.
  - First authenticated public RPC call with the Clerk token failed before RLS with `401 PGRST301 No suitable key was found to decode the JWT`.
  - Reran `supabase config push`; CLI reported remote API/DB/Auth/Storage config all up to date.
  - Reran the smoke after config push; same `PGRST301` Clerk token decode failure.
  - Control request using Supabase anon JWT against the same public RPC reached `42501 permission denied for function search_profiles_by_handle`, confirming PostgREST/RPC exposure is live and Supabase can decode its own JWT.
- Conclusion: do not proceed to M4 sync or simulator remote-action debugging yet. The current blocker is hosted Supabase Clerk third-party auth verification/key registration, not Swift app code or public RPC wrapper exposure.

## 2026-06-04 - Codex - M3 Auth Provider Follow-Up

Agent: Codex
Branch: `main`
Starting commit: `ce1c316`
Starting status: local `main` matches `origin/main`; `Wander.xcodeproj/project.pbxproj` still has only the expected local signing/team diff and should remain uncommitted.

Goal: answer whether the Clerk/Supabase verifier blocker can be fixed through CLI, and clarify whether Supabase OAuth Server must be enabled.

Checkpoint:

- Verified current docs: the relevant hosted Supabase path is **Authentication -> Sign In / Providers -> Add provider -> Clerk**, not the OAuth Server page.
- OAuth Server being enabled is unrelated to accepting Clerk third-party JWTs.
- Re-ran `supabase config push --project-ref rugmtlgufrhlxwfkumhw`; CLI reported remote Auth config up to date.
- Re-ran the hosted Clerk-token smoke after explicit config push; Supabase still returned `401 PGRST301 No suitable key was found to decode the JWT`.
- Ran `npx supabase@latest config push --project-ref rugmtlgufrhlxwfkumhw` using Supabase CLI `2.105.0`; it also reported remote Auth config up to date.
- Re-ran the hosted Clerk-token smoke again after latest CLI push; same `PGRST301` failure.
- Checked Clerk OIDC discovery and JWKS:
  - OIDC issuer: `https://growing-pheasant-22.clerk.accounts.dev`
  - JWKS URI: `https://growing-pheasant-22.clerk.accounts.dev/.well-known/jwks.json`
  - JWKS contains `kid=ins_3Eb3Je6FO3qfUDIt5n3aTHMxYN1`
- Conclusion: CLI config push is not resolving hosted PostgREST's Clerk verifier. Next action is to add/verify the Clerk provider row in Supabase Dashboard under Authentication -> Sign In / Providers, or use the authenticated browser to do that UI step.

## 2026-06-04 08:27 PDT - Codex - M3 Auth Provider Retest

Agent: Codex
Branch: `main`
Starting commit: `8517e08`
Starting status: local `main` matches `origin/main`; `Wander.xcodeproj/project.pbxproj` still has only the expected local signing/team diff and should remain uncommitted.

Goal: rerun the hosted Clerk-to-Supabase smoke after Joe added the Clerk provider connection in the Supabase dashboard using the `https://growing-pheasant-22.clerk.accounts.dev` domain.

Expected files to touch:

- `docs/agent-log.md`
- Potentially setup/open-question docs if the smoke result changes M3 status.

Completion checkpoint:

- Created temporary smoke runner at `/private/tmp/wander-m3-live-smoke.mjs`; no secrets or runner code committed.
- Hosted smoke passed after the Supabase Clerk connection was added:
  - Clerk disposable user creation passed.
  - Clerk profile mirroring passed.
  - Default Clerk session token had `alg=RS256`, `kid=ins_3Eb3Je6FO3qfUDIt5n3aTHMxYN1`, `iss=https://growing-pheasant-22.clerk.accounts.dev`, `role=authenticated`, and `sub` matched the viewer Clerk user id.
  - Supabase accepted the Clerk token.
  - Authenticated RPCs passed: `search_profiles_by_handle`, `follow_user`, `visible_places_in_view`, `save_visible_place`, `block_user`, `unblock_user`, and `unfollow_user`.
- Updated `docs/open-questions.md`, `docs/backend/m3-supabase-foundation.md`, and `docs/setup.md` from blocked to passed.
- Ran simulator build with local public Clerk/Supabase keys injected:
  `xcodebuild build -project Wander.xcodeproj -scheme Wander -destination "platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6" -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO ...`
- Result: build succeeded.
- Next: app-level simulator smoke for actual Clerk sign-in UI and remote-backed social actions.

## 2026-06-04 10:18 PDT - Codex - Settings Sign Out

Agent: Codex
Branch: `main`
Starting commit: `7c30e20`
Starting status: local `main` matches `origin/main`; `Wander.xcodeproj/project.pbxproj` still has only the expected local signing/team diff and should remain uncommitted.

Goal: add a real sign-out path so simulator/device testing can leave Joe's restored Clerk session and exercise signed-out/sign-in flows.

Expected files to touch:

- `Wander/Services/Auth/AuthSessionProviding.swift`
- `Wander/Services/Auth/ClerkAuthService.swift`
- `Wander/Features/Settings/SettingsScreen.swift`
- `WanderTests/AuthSessionTests.swift`
- `docs/agent-log.md`

Initial findings:

- Current app has sign-in gates but no sign-out or account-switch surface.
- Clerk iOS SDK exposes `try await Clerk.shared.auth.signOut()`.

Completion checkpoint:

- Added `signOut()` to the auth session boundary and implemented it through `Clerk.shared.auth.signOut()`.
- Added Settings account state UI: signed-in identity summary, sign-out action with loading/error state, signed-out sign-in action, and loading/unavailable fallbacks.
- Added auth session tests for successful sign-out clearing the session and failed sign-out preserving the active session while surfacing an error.
- First test compile failed because Settings referenced a non-existent `WanderTheme.sky` token; fixed to use the existing social-pin token.
- Ran full test suite:
  `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Result: passed, 41 tests, 0 failures. Result bundle: `DerivedData/Logs/Test/Test-Wander-2026.06.04_10-21-43--0700.xcresult`.
- Known remaining local diff: `Wander.xcodeproj/project.pbxproj` signing/team settings, intentionally uncommitted.

## 2026-06-04 10:24 PDT - Codex - TestFlight Readiness Check

Agent: Codex
Branch: `main`
Starting commit: `1517a4b`
Starting status: local `main` matches `origin/main`; `Wander.xcodeproj/project.pbxproj` still has only the expected local `DEVELOPMENT_TEAM = Y7TVK75RZ8` diff.

Goal: answer whether the current Wander repo can be pushed to TestFlight from this machine.

Findings:

- The app target bundle id is `com.grayline.wander`.
- `project.yml` intentionally has no committed `DEVELOPMENT_TEAM`; local generated project state has team `Y7TVK75RZ8`, still uncommitted.
- Local code-signing identity check returned `0 valid identities found`, so this machine cannot currently produce a signed App Store/TestFlight archive from CLI.
- Existing local App Store Connect env key `ASC_BUNDLE_ID` is not `com.grayline.wander`, so the current ASC env appears to be for another app/workflow and should not be reused blindly for Wander uploads.
- No repo TestFlight lane exists yet: no `ExportOptions.plist`, `Fastfile`, `.ipa`, or `.xcarchive` was found.
- Release hygiene issue: `project.yml` says `MARKETING_VERSION = 0.1`, but `Wander/Resources/Info.plist` hardcodes `CFBundleShortVersionString` to `1.0`; fix before first TestFlight upload so versioning is predictable.
- Sandbox-only `xcodebuild -list`/`-showBuildSettings` checks failed on cache/CoreSimulator permissions; this does not change the signing conclusion.

Conclusion:

- Not ready to upload to TestFlight from CLI yet.
- Next setup steps: add/use a Wander-specific App Store Connect app/bundle config, install or create an Apple Distribution signing identity/provisioning path for `com.grayline.wander`, add a release export/upload lane, fix Info.plist version build settings, then archive/upload.

## 2026-06-04 10:32 PDT - Codex - Simulator Auth Config And Sign-Out Visibility

Agent: Codex
Branch: `main`
Starting commit: `e01ca73`
Starting status: local `main` is ahead of `origin/main` by the TestFlight readiness log commit; `Wander.xcodeproj/project.pbxproj` still has the local signing/team diff.

Goal: fix Joe's simulator screenshot showing `Missing Clerk publishable key.` in Settings, then continue TestFlight setup.

Findings:

- The Settings sign-out implementation exists, but the simulator app was built without `WANDER_CLERK_PUBLISHABLE_KEY`.
- With missing Clerk config, `ClerkAuthService` sets auth state to `.unavailable("Missing Clerk publishable key.")`, so the account card cannot show the signed-in state or sign-out control.
- Immediate fix path: rebuild/install the simulator app with the local-only public Clerk/Supabase client keys injected via an xcconfig so the values are not printed in command output.
- UI improvement path: make Settings show a full-width account action button instead of relying on the small trailing `sign out` button.

Completion checkpoint:

- Updated Settings account UI so signed-in state shows a full-width `sign out` button and signed-out state shows a matching full-width `sign in` button.
- Added unavailable-state helper copy so missing auth config points to the local auth-config rebuild issue.
- Created temporary local auth xcconfig at `/private/tmp/wander-live-auth.xcconfig` from local env values; do not commit this file.
- First sandboxed configured test run failed due Xcode cache/CoreSimulator permissions and printed build settings; reran quietly with elevated Xcode access for subsequent runs.
- Fixed one compile issue from the UI tweak (`WanderTheme.cream` -> `WanderTheme.textOnAction`).
- Ran configured full test suite:
  `xcodebuild -quiet test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData -xcconfig /private/tmp/wander-live-auth.xcconfig CODE_SIGNING_ALLOWED=NO`
- Result: passed.
- Built configured simulator app and installed/launched it on iPhone 17 Pro simulator `066417CD-C3D5-4209-BA1F-46152B1A6AAC` into Settings.
- Verification screenshot: `/private/tmp/wander-settings-auth.png`; Settings now shows `Signed out` and a large `sign in` button instead of `Missing Clerk publishable key.`
- Expected behavior: after sign-in, the same account card shows the large `sign out` button.

## 2026-06-04 10:41 PDT - Codex - TestFlight Archive Attempt

Agent: Codex
Branch: `main`
Starting commit: `1a9887b`
Starting status: local `main` matches `origin/main`; `Wander.xcodeproj/project.pbxproj` still has the local signing/team diff.

Goal: attempt to prepare and upload a Wander TestFlight build after fixing the simulator auth configuration issue.

Expected files to touch:

- `Wander/Resources/Info.plist`
- `docs/agent-log.md`

Initial findings:

- Release metadata hygiene issue: `Info.plist` hardcoded `CFBundleShortVersionString` to `1.0` while `project.yml` uses `MARKETING_VERSION = 0.1`.
- Fixed `Info.plist` to read `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)` so archives use project build settings.
- Next step is a signed `xcodebuild archive` with local public auth config injected through `/private/tmp/wander-live-auth.xcconfig`, automatic signing, and team `Y7TVK75RZ8`.

Checkpoint:

- Signed archive succeeded at `/private/tmp/Wander-0.1.xcarchive`.
- Export/upload attempt failed before package upload with `IDEDistribution.DistributionAppRecordProviderError.missingApp(bundleId: "com.grayline.wander")`.
- Distribution logs showed App Store Connect auth worked and queried provider `7f20b667-afd3-456b-b2bc-ca94ab295484`, but returned zero apps for `com.grayline.wander`.
- Conclusion: signing is now good enough to archive; the current blocker is that no App Store Connect app record exists for `com.grayline.wander`.
- Added release prep for the next attempt:
  - `TARGETED_DEVICE_FAMILY = 1`
  - `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`
  - `UIRequiresFullScreen = true`
  - generated a temporary/simple AppIcon asset catalog for validation unblock; replace with final brand icon later.

Completion checkpoint:

- Added tracked `Wander/Config/Auth.xcconfig`, ignored `Wander/Config/LocalAuth.xcconfig`, and project wiring so normal Xcode builds can use local public Clerk/Supabase client keys without committing key values.
- Created local ignored `Wander/Config/LocalAuth.xcconfig` from `/Users/joelipshutz/.openclaw/workspace/.env.keys`.
- Regenerated `Wander.xcodeproj` from `project.yml`; `DEVELOPMENT_TEAM = Y7TVK75RZ8` is now intentional project configuration.
- Verified no local public client key values are present in tracked files.
- Ran regenerated-project tests:
  `xcodebuild -quiet test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Result: passed.
- Fresh signed archive succeeded at `/private/tmp/Wander-0.1.xcarchive` after the icon/full-screen/project config changes.
- Updated `docs/setup.md` with local auth config setup and the App Store Connect app-record blocker.
- Exact remaining TestFlight step: create an App Store Connect iOS app record for `com.grayline.wander` (suggested name `Wander`, SKU `wander-ios`). Then rerun upload.
- Follow-up correction: XcodeGen rewrites `Wander/Resources/Info.plist`, so version/full-screen keys now live in `project.yml` `info.properties`.
- Reran `xcodegen generate`.
- Reran tests after the final generated project/plist changes: passed.
- Rebuilt the final signed archive at `/private/tmp/Wander-0.1.xcarchive`: passed.

## 2026-06-04 11:03 PDT - Codex - TestFlight Upload Retry

Agent: Codex
Branch: `main`
Starting commit: `5cee10c`
Starting status: local `main` matches `origin/main`.

Goal: rerun App Store Connect upload after Joe created the `com.grayline.wander` app record.

Expected files to touch:

- `docs/agent-log.md`

Plan:

- Reuse `/private/tmp/Wander-0.1.xcarchive` from the successful signed archive.
- Recreate upload export options if needed.
- Run `xcodebuild -exportArchive` with `destination=upload`.
- Log the upload result or the next exact Apple validation blocker.

Completion checkpoint:

- Recreated `/private/tmp/WanderExportUpload.plist`.
- Ran:
  `xcodebuild -quiet -exportArchive -archivePath /private/tmp/Wander-0.1.xcarchive -exportPath /private/tmp/WanderTestFlightUpload -exportOptionsPlist /private/tmp/WanderExportUpload.plist -allowProvisioningUpdates`
- App Store Connect found the newly-created `com.grayline.wander` app record.
- Apple package analysis passed.
- Upload reached 100% and completed successfully.
- Final Xcode output: `Uploaded Wander`.
- Current state: build uploaded to App Store Connect and is processing before it can be used in TestFlight.

## 2026-06-04 17:49 PDT - Codex - M4 Fixture Opt-In Start

Agent: Codex
Branch: `main`
Starting commit: `ac9850d`
Starting status: local `main` matches `origin/main`.

Goal: start M4 by removing seeded demo people/places from default app launches. Joe confirmed TestFlight sign-in works, but external testers should not see Joe/Maya/Ryan/Woodcat fixture data unless a demo/test mode is explicitly requested.

Expected files to touch:

- `Wander/Services/WanderFixtures.swift`
- `Wander/Services/WanderLocalStore.swift`
- `Wander/Services/Auth/AuthSessionProviding.swift`
- `Wander/Services/Auth/ClerkAuthService.swift`
- `Wander/App/WanderRootView.swift`
- `WanderTests/NavigationContractTests.swift`
- `WanderTests/WanderStoreTests.swift`
- `docs/agent-log.md`

Plan:

- Add an empty/default fixture set with a generic local profile.
- Keep the existing seeded fixture set for tests and screenshots.
- Make `WanderRootView` choose fixtures from a launch argument; default to empty.
- Add a launch flag for seeded demo fixtures.
- Sync the local current profile shell from the authenticated Clerk session when present.

Completion checkpoint:

- Added `WanderFixtures.empty()` and changed `WanderRootView` to use empty fixtures by default.
- Preserved seeded Joe/Maya/Ryan fixture data behind the explicit `-WanderUseDemoFixtures` launch argument for screenshots/local demos/tests, and prevented auth refresh from overwriting seeded demo mode.
- Added session email to `AuthSession` and mapped Clerk `primaryEmailAddress` into the local profile shell.
- Added `WanderStore.apply(authState:)` so signed-in users see a local profile derived from the Clerk session instead of fixture Joe, and signed-out/default launches stay generic.
- Added tests for default-empty fixture mode, explicit demo-fixture mode, empty local stores, and signed-in profile-shell hydration.
- First sandboxed test run failed on CoreSimulator/SwiftPM cache permissions only.
- Elevated test run found one test compile issue (`VisiblePlace` is not `Equatable`); changed that assertion to `isEmpty`.
- Reran full test suite:
  `xcodebuild -quiet test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Result: passed.
- Bumped `CURRENT_PROJECT_VERSION` from `1` to `2` in `project.yml` and regenerated `Wander.xcodeproj` with `xcodegen generate`.
- Reran the full test suite after regeneration; result: passed.
- Built signed archive:
  `/private/tmp/Wander-0.1-build2.xcarchive`
- Result: archive succeeded.
- First `xcodebuild -exportArchive` upload attempt failed before packaging with `Failed to Use Accounts`; distribution logs said Xcode could not find App Store Connect access for team `Y7TVK75RZ8`.
- Retried export/upload with the local App Store Connect API key via `-authenticationKeyPath`, `-authenticationKeyID`, and `-authenticationKeyIssuerID`.
- Result: App Store Connect analysis passed, upload reached 100%, and Xcode output ended with `Uploaded Wander`.
- Made one follow-up root-flow correction so demo fixture mode stays stable after signed-out auth refresh.
- Bumped `CURRENT_PROJECT_VERSION` from `2` to `3`, regenerated `Wander.xcodeproj`, and reran the full test suite; result: passed.
- Built signed archive:
  `/private/tmp/Wander-0.1-build3.xcarchive`
- Uploaded build `0.1 (3)` through `xcodebuild -exportArchive` with the App Store Connect API key.
- Result: App Store Connect analysis passed, upload reached 100%, and Xcode output ended with `Uploaded Wander`.
- Current state: build `0.1 (3)` is uploaded and processing in App Store Connect. This build should remove fake seeded people/places from default/TestFlight launches while keeping sign-in available.

## 2026-06-04 18:19 PDT - Codex - M4 QA Pass Start

Agent: Codex
Branch: `main`
Starting commit: `2261cd4`
Starting status: local `main` matches `origin/main`.

Goal: run the M4 QA pass after Joe confirmed the first TestFlight smoke and M4 remote-sync slice are done.

Mission Control: `http://localhost:4000/api/tasks` is unreachable from this session, so this log is the active coordination record.

Expected files to touch:

- `docs/agent-log.md`
- `docs/roadmap.md`
- `Wander/Features/Map/MapScreen.swift`
- `project.yml`
- `Wander.xcodeproj/project.pbxproj`
- `docs/setup.md`
- possible small QA fixes if checks expose a concrete bug

QA scope:

- Fresh signed-out install behavior.
- New signed-in account behavior.
- Existing signed-in account behavior.
- Sign out and sign back in behavior.
- Build/test status and whether a new TestFlight upload is needed.

Checkpoint:

- Ran full Xcode test suite. First sandboxed run failed on CoreSimulator/SwiftPM cache permissions only. Elevated run passed:
  `xcodebuild -quiet test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Installed and launched the debug build on the previously-used iPhone 17 Pro simulator. It showed `JL`, but that simulator had a prior Clerk/keychain session, so it represented an existing-session path rather than true first-run.
- Created a temporary clean simulator `Wander-M4-QA` (`4252EC90-35A5-4018-82AA-4BFEBAD0289B`) to verify true first-run behavior.
- Clean first-run initially showed `JL` in the map search avatar even with no session. Root cause: `Wander/Features/Map/MapScreen.swift` hardcoded `WanderAvatar(initials: "JL", ...)`.
- Fixed the map search avatar to use `store.currentUser.initials`. On clean first-run it now shows generic `Y` from the default `You` profile and no seeded Joe/Maya/Ryan/Woodcat place content.
- Reran the full Xcode test suite after the avatar fix; result: passed.
- QA blocker found: direct signed-in own-place remote save is still not implemented in `SupabaseUserPlaceRepository.save(_:)` (`notImplemented("direct user place save RPC")`). Current remote wiring covers visible places, profile search, follow/unfollow, block/unblock, and social save, but not direct add/save to Supabase.

Completion checkpoint:

- Updated `docs/roadmap.md` to mark M3 as done baseline and M4 as in QA/blocked on direct signed-in own-place save.
- Bumped `CURRENT_PROJECT_VERSION` from `3` to `4` and regenerated `Wander.xcodeproj`.
- Reran full Xcode test suite after regeneration:
  `xcodebuild -quiet test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Result: passed.
- Built signed archive:
  `/private/tmp/Wander-0.1-build4.xcarchive`
- Uploaded build `0.1 (4)` through `xcodebuild -exportArchive` with the App Store Connect API key.
- Result: App Store Connect analysis passed, upload reached 100%, and Xcode output ended with `Uploaded Wander`.
- Current state: build `0.1 (4)` is uploaded and processing in App Store Connect. It includes the clean first-run avatar fix, but M4 QA is not green until direct signed-in own-place save is implemented and retested.

## 2026-06-04 18:49 PDT - Codex - M4 Direct Own-Place Save Start

Agent: Codex
Branch: `main`
Starting commit: `436488d`
Starting status: local `main` matches `origin/main`.

Goal: close the M4 QA blocker by implementing direct signed-in own-place save to Supabase for current-location/manual add.

Mission Control: `http://localhost:4000/api/tasks` is still unreachable from this session, so this log is the active coordination record.

Expected files to touch:

- `supabase/migrations/*_save_own_place.sql`
- `Wander/Services/RepositoryProtocols.swift`
- `Wander/Services/Remote/SupabaseRepositories.swift`
- `Wander/Services/WanderLocalStore.swift`
- `Wander/Features/Add/AddScreen.swift`
- `WanderTests/RemoteRepositoryTests.swift`
- `WanderTests/WanderStoreTests.swift`
- `docs/agent-log.md`
- `docs/roadmap.md`
- `docs/setup.md`
- `project.yml`
- `Wander.xcodeproj/project.pbxproj`

Plan:

- Add a Supabase RPC for upserting a canonical place, current user's user_place row, and flexible question attributes.
- Add the public PostgREST wrapper and grants.
- Implement `SupabaseUserPlaceRepository.save(_:)`.
- Wire signed-in Add flow to local-first save, then remote save with synced/failed local state.
- Add contract tests for request shape and local success/failure fallback.
- Run full tests, apply hosted migration if possible, then upload a new TestFlight build.

Checkpoint:

- Added migration `20260604185000_save_own_place.sql` with `app.save_own_place` plus public PostgREST wrapper.
- Wired signed-in current-location/manual Add saves through local-first store save, `WanderBackend.saveUserPlace`, and `SupabaseUserPlaceRepository.save(_:)`.
- Added tests for `save_own_place` RPC body shape and local success/failure sync marking.
- Applied the hosted Supabase migration with `npx supabase db push --linked`; Supabase finished the migration successfully.
- Ran the full Xcode test suite after the direct-save changes:
  `xcodebuild -quiet test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Result: passed.
- Updated M4 docs to show direct-save is no longer the blocker; build `0.1 (5)` is the next TestFlight QA candidate.

Completion checkpoint:

- Bumped `CURRENT_PROJECT_VERSION` from `4` to `5` in `project.yml` and regenerated `Wander.xcodeproj` with `xcodegen generate`.
- Reran the full Xcode test suite after regeneration:
  `xcodebuild -quiet test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Result: passed.
- Built signed archive:
  `/private/tmp/Wander-0.1-build5.xcarchive`
- Uploaded build `0.1 (5)` through `xcodebuild -exportArchive` with the App Store Connect API key.
- Result: App Store Connect analysis passed, upload reached 90%, and Xcode output ended with `Uploaded Wander`.
- Current state: build `0.1 (5)` is uploaded and processing in App Store Connect. Next step is Joe device-smoke testing direct current-location/manual save on TestFlight after processing completes.

## 2026-06-05 09:47 PDT - Codex - Public TestFlight Link Setup

Agent: Codex
Branch: `main`
Starting commit: `89e22bd`
Starting status: local `main` matches `origin/main`.

Goal: create/find the public TestFlight share link for Wander.

Actions:

- Queried App Store Connect for app bundle `com.grayline.wander`; app id is `6776850787`, name is `Wander: Find Places`.
- Initial TestFlight beta group query returned no groups.
- Created external beta group `Wander Alpha` with public link enabled, feedback enabled, and 100-tester cap.
- Public link created: `https://testflight.apple.com/join/knEhRa6t`.
- Attempted to attach build `0.1 (5)` (`7fdc7c41-12e6-40ff-88cd-3348e2942c88`) to the group.
- App Store Connect rejected the build attach with `Build is not assignable` / `Build is not in an externally assignable state.`
- Follow-up query showed build `0.1 (5)` is `VALID`, but `usesNonExemptEncryption` is still null and beta app review contact fields are empty.

Current state:

- Public link exists, but it may show no available build until App Store Connect beta review/export compliance is completed and build `0.1 (5)` is attached to `Wander Alpha`.

## 2026-06-05 09:54 PDT - Codex - Attach Build 5 To Public TestFlight

Agent: Codex
Branch: `main`
Starting commit: `638e99a`
Starting status: local `main` matches `origin/main`.

Goal: get the latest build onto the public TestFlight link and handle export compliance if possible.

Actions:

- Attempted to patch build `0.1 (5)` export compliance to `usesNonExemptEncryption=false`; Apple returned that the value was already set and cannot be updated.
- Re-queried build `0.1 (5)` and confirmed `usesNonExemptEncryption=false`.
- Retried attaching build `0.1 (5)` (`7fdc7c41-12e6-40ff-88cd-3348e2942c88`) to external group `Wander Alpha`.
- App Store Connect accepted the attach.
- Final read-back showed public link enabled, cap 100, feedback enabled, and build `0.1 (5)` attached.
- Verified `https://testflight.apple.com/join/knEhRa6t` responds with HTTP 200.

Current state:

- Public TestFlight link is live: `https://testflight.apple.com/join/knEhRa6t`
- Attached build: `0.1 (5)`
- Export compliance: `usesNonExemptEncryption=false`

## 2026-06-05 15:03 PDT - Codex - TestFlight Link Not Accepting Testers

Agent: Codex
Branch: `main`
Starting commit: `4bf3c3f`
Starting status: local `main` matches `origin/main`.

Goal: investigate Joe seeing "not accepting new testers" on the public TestFlight link and open the link to anyone if App Store Connect allows it.

Plan:

- Query current `Wander Alpha` beta group settings, cap, public link state, and attached builds.
- Remove or raise the public-link cap if it is limiting joins.
- If group settings are already open, identify whether Apple beta review or build external availability is the remaining blocker.

Actions:

- Queried `Wander Alpha`; public link was enabled, build `0.1 (5)` was attached, export compliance was `usesNonExemptEncryption=false`, and the group still had `publicLinkLimitEnabled=true` with limit 100.
- Queried beta review submission for build `0.1 (5)`; Apple reports `betaReviewState=WAITING_FOR_REVIEW`, submitted `2026-06-05T09:53:38-07:00`.
- Patched `Wander Alpha` to keep public link enabled, keep feedback enabled, and set `publicLinkLimitEnabled=false`.
- App Store Connect accepted the patch. Read-back confirms `publicLinkLimitEnabled=false`, public link still `https://testflight.apple.com/join/knEhRa6t`, and build `0.1 (5)` remains attached.

Current state:

- Anyone with the link can join once Apple approves external TestFlight review.
- The remaining blocker is not group settings; it is Apple beta review pending for build `0.1 (5)`.

## 2026-06-05 20:49 PDT - Codex - M5 Add Capture Feedback Logged

Agent: Codex
Branch: `main`
Starting commit: `783c765`
Starting status: local `main` matches `origin/main`.

Goal: log Joe's TestFlight feedback and transition from M4 into M5.

Context:

- Joe confirmed sign-in is working and said to move to M5.
- Add flow feedback from TestFlight:
  - No back button once the user starts adding a place.
  - Title should be `add a place`.
  - Remove `where's it from` and `pick a source`; the app should feel like it will fill in what it can.
  - `I'm here now` needs a real location permission ask and nearby-place resolution.
  - Current build still returns deterministic `Maru Coffee`, which is not acceptable for M5.
  - Manual add should resolve real place candidates.
  - Paste link and photo add are still not real extraction.
  - Need clarity that LLM is for parsing/extraction hints, while canonical place identity/coordinates should come from MapKit/place-provider search.

Actions:

- Updated `docs/roadmap.md` to mark M4 as done baseline and M5 as in progress.
- Updated `docs/open-questions.md` with explicit M5 Add capture notes for navigation, copy, location, manual resolution, link extraction, and photo extraction.

## 2026-06-05 20:57 PDT - Codex - M5 Add UX And Place Resolution Start

Agent: Codex
Branch: `main`
Starting commit: `3d0c59a`
Starting status: local `main` matches `origin/main`.

Goal: implement the first M5 Add slice: clean Add copy/navigation, remove fake current-location/manual place candidates, and resolve candidates through real iOS location/place search services.

Expected files to touch:

- `Wander/Features/Add/AddScreen.swift`
- `Wander/Services/WanderLocalStore.swift`
- `Wander/Services/RepositoryProtocols.swift`
- new service files under `Wander/Services/`
- `project.yml`
- `Wander.xcodeproj/project.pbxproj`
- focused tests under `WanderTests/`
- `docs/agent-log.md`

Plan:

- Add back navigation/escape behavior inside Add after leaving the source state.
- Update Add title/copy to `add a place` and remove the confusing source-picker wording.
- Replace store-level fake candidate methods with async resolution through a place resolver.
- Implement current-location permission + nearby MapKit search for `I'm here now`.
- Implement manual MapKit search using name, area hint, and category hints.
- Keep link/photo as honest unresolved-draft shells until backend extraction jobs are built.

Checkpoint:

- Added `PlaceCandidateResolving` and `MapKitPlaceResolver`.
- `MapKitPlaceResolver` uses CoreLocation one-shot permission/location plus MapKit nearby POI search for `I'm here right now`.
- Manual add now resolves candidates through MapKit local search instead of fabricating a downtown LA candidate.
- `PlaceCandidate` now carries address/locality/region/country/provider metadata; local save preserves those fields.
- Add UI now uses stable title `add a place`, has an in-flow back button, removes `where's it from`/`pick a source` copy, and shows async resolving/error states.
- Added `NSLocationWhenInUseUsageDescription` through `project.yml` and regenerated `Wander.xcodeproj`.
- Added resolver-boundary tests and updated current-location save metadata coverage.
- Full Xcode test suite passed:
  `xcodebuild -quiet test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Bumped `CURRENT_PROJECT_VERSION` from `5` to `6`; build `0.1 (6)` is the next TestFlight candidate for this M5 Add slice.

Completion checkpoint:

- Regenerated `Wander.xcodeproj` after the build-number bump.
- Reran the full Xcode test suite after regeneration:
  `xcodebuild -quiet test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Result: passed.
- Built signed archive:
  `/private/tmp/Wander-0.1-build6.xcarchive`
- Uploaded build `0.1 (6)` through `xcodebuild -exportArchive` with the App Store Connect API key.
- Result: App Store Connect analysis passed, upload succeeded, and Xcode output ended with `Uploaded Wander`.
- App Store Connect build id for `0.1 (6)`: `7c34953e-f7ca-444b-93e2-413572c9b4c1`.
- Set export compliance to `usesNonExemptEncryption=false`.
- Attached build `0.1 (6)` to external group `Wander Alpha`.
- Submitted build `0.1 (6)` for external TestFlight review; Apple reports `betaReviewState=WAITING_FOR_REVIEW`.

Handoff checkpoint, 2026-06-05 21:12 PDT:

- Mission Control task update attempted with `curl -s http://localhost:4000/api/tasks`; local server was not reachable (`curl` exit 7), so this repo log is the active coordination surface for this work.
- Cleanup after review: Add source actions now clear stale resolution messages when switching to link/manual/photo.
- Current remaining M5 scope after this commit: real link extraction, photo extraction/capture, richer detail questions, and backend job plumbing. This slice only replaces fake current-location/manual candidates and cleans the first Add surface/navigation.

Final checkpoint, 2026-06-05 21:16 PDT:

- Implementation commit: `e082b63 feat: resolve add place candidates`; pushed to `origin/main`.
- Verified local `main` and `origin/main` matched `e082b63d022a04b6e3567acb5fd78efda04c8457` after push.
- Rechecked App Store Connect after upload: build `0.1 (6)` external TestFlight review is `APPROVED`.

## 2026-06-05 22:41 PDT - Codex - M5 Link Capture Candidate Flow

Agent: Codex
Branch: `main`
Starting commit: `d563730`
Starting status: local `main` matches `origin/main`; worktree clean.

Goal: continue M5 by turning paste-link Add from an immediate draft shell into a real candidate-resolution flow for map/location links, while preserving draft fallback for opaque or low-confidence links.

Expected files to touch:

- `Wander/Features/Add/AddScreen.swift`
- `Wander/Services/RepositoryProtocols.swift`
- `Wander/Services/WanderLocalStore.swift`
- new service/parser files under `Wander/Services/`
- focused tests under `WanderTests/`
- `project.yml` / `Wander.xcodeproj/project.pbxproj` if new source files require regeneration
- `docs/agent-log.md`

Plan:

- Add a link-entry step in Add instead of creating a draft immediately.
- Parse obvious place hints from Google Maps, Apple Maps, and Instagram location URLs.
- Resolve parsed hints through MapKit candidate search and require confirmation before save.
- If parsing/resolution fails, keep a draft and offer manual rescue.
- Leave backend extraction jobs and photo import/extraction as the next M5 slices.

Notes:

- Mission Control was checked with `curl -s http://localhost:4000/api/tasks`; it is still unreachable locally (`curl` exit 7), so this repo log remains the coordination record.

Checkpoint:

- Added `LinkPlaceInput` and `PlaceCandidateResolving.resolveLink`.
- Added `LinkPlaceParser` for deterministic local hints from Google Maps place paths, Apple Maps query links, Instagram location slugs, and plain text.
- Added Add `link` step with paste field, `find from link`, and explicit `save as draft` fallback.
- Link candidates now flow through MapKit search and reuse the existing confirm/details/save path with `sourceType = link`.
- Opaque/short links still become drafts instead of fake candidates.
- Added parser tests and store boundary tests.
- Ran full test suite after new files and again after build-number regeneration:
  `xcodebuild -quiet test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Result: passed both runs.
- Bumped `CURRENT_PROJECT_VERSION` to `7`, archived `/private/tmp/Wander-0.1-build7.xcarchive`, and uploaded build `0.1 (7)` with `xcodebuild -exportArchive`.
- Upload succeeded and App Store Connect reported `Uploaded Wander`; immediate API polls had not yet surfaced build `7`, so export compliance/public-group attachment remains pending until Apple indexes the build.
- Follow-up App Store Connect poll surfaced build `0.1 (7)` as build id `e7e0991e-bf35-4004-8a80-7bc6eef6e1e2`, processing state `VALID`.
- Set export compliance to `usesNonExemptEncryption=false`, attached build `0.1 (7)` to public group `Wander Alpha`, and submitted it for external TestFlight review.
- Apple reports build `0.1 (7)` beta review state `WAITING_FOR_REVIEW`.
- Final App Store Connect check after push: build `0.1 (7)` is `VALID`, `usesNonExemptEncryption=false`, and external beta review state is `APPROVED`.

## 2026-06-05 23:06 PDT - Codex - M5 Shared Test Checkpoint

Agent: Codex
Branch: `main`
Starting commit: `0bbc43b`
Starting status: local `main` matches `origin/main`; worktree clean.

Goal: continue through the remaining M5 work until there is a strong TestFlight checkpoint for Joe and external testers.

Plan:

- Keep backend extraction workers out of this slice because the eng plan marks backend extraction as M6.
- Add a real Add-photo import path using PhotosUI that creates local source-artifact/extraction-job state and a visible draft, instead of a dead source row.
- Add visible parsed Discover filter chips and strengthen the cheap/swappable parser boundary without sending user graph/place/contact data to an external model from the client.
- Add an analytics/event interface and cover it with focused tests/mocks, not a vendor SDK.
- Run full Xcode tests, upload a new TestFlight build, and provide a focused tester script.

Notes:

- Mission Control is still unreachable on `localhost:4000` (`curl` exit 7), so this repo log remains the coordination surface.

Checkpoint:

- Added local source-artifact and extraction-job creation for link/photo unresolved drafts. Backend execution remains M6; this M5 slice creates durable local artifact/job state and keeps draft/manual rescue visible.
- Added PhotosUI photo import in Add. Imported photos create a photo draft plus local image source artifact and pending extraction job; no fake AI candidate is shown.
- Added visible parsed Discover filter chips below the search field.
- Strengthened deterministic parser coverage for category aliases, tags, area, status, relationships, cache, and parser failure fallback behind the existing `LLMFilterParser` protocol.
- Wired parser analytics through the existing `AnalyticsClient` abstraction for `discover_query_parsed`, `discover_parse_failed`, `place_saved`, and `extraction_job_started`.
- Added tests for photo/link draft artifacts, idempotent artifact/job creation, Discover chips, parser cache, parser failure, and analytics events.
- Ran full test suite before and after the build number bump:
  `xcodebuild -quiet test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Result: passed both runs.
- Bumped `CURRENT_PROJECT_VERSION` to `8`, archived `/private/tmp/Wander-0.1-build8.xcarchive`, and uploaded build `0.1 (8)` with `xcodebuild -exportArchive`.
- App Store Connect build id for `0.1 (8)`: `0c4f9998-4f74-4491-9811-5a2e885c2677`; processing state `VALID`.
- Set export compliance to `usesNonExemptEncryption=false`, attached build `0.1 (8)` to public group `Wander Alpha`, and submitted it for external TestFlight review.
- Apple currently reports build `0.1 (8)` beta review state `WAITING_FOR_REVIEW`.
- Final App Store Connect check after push: build `0.1 (8)` is `VALID`, `usesNonExemptEncryption=false`, and external beta review state is `APPROVED`.

## 2026-06-06 12:57 PDT - Codex - M5 Build 9 Friend Test Batch

Agent: Codex
Branch: `main`
Starting commit: `1af695e`
Starting status: local `main` matches `origin/main`; worktree clean.

Goal: fix confusing short Google Maps link behavior and prepare a clearer Build 9 friend-test batch.

Plan:

- Try to resolve Google Maps short links by following their HTTPS redirect before falling back.
- If a short link still does not expose a place name, show honest copy that short links need extraction and can be saved as drafts.
- Polish Add link copy so testers understand what works now versus what is queued for backend extraction.
- Keep backend extraction workers out of this batch; M6 owns real extraction execution.
- Run full tests, upload a new TestFlight build, and provide a friend-ready testing message.

Checkpoint:

- Added short-map-link detection for `maps.app.goo.gl`, `goo.gl`, and `g.co`.
- `MapKitPlaceResolver.resolveLink` now follows known short-link HTTPS redirects, reparses the final URL, and then runs MapKit candidate search.
- Checked Joe's screenshot link with `curl -sIL`; it redirects to a full `maps.google.com/maps?q=Tahoe+Waterman's+Landing...` URL, which the parser now covers.
- Added specific short-link fallback copy: "Short map links need extraction. Save this as a draft for now or add it manually."
- Updated Add link helper/button/draft copy so the feature reads as partial support, not broken extraction.
- Added tests for short-link classification, expanded Google Maps redirect destinations, and short-link fallback copy.
- Ran full Xcode tests before and after the build number bump:
  `xcodebuild -quiet test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Result: passed both runs.
- Bumped `CURRENT_PROJECT_VERSION` to `9`, archived `/private/tmp/Wander-0.1-build9.xcarchive`, and uploaded build `0.1 (9)`.
- App Store Connect build id for `0.1 (9)`: `c0f30e62-bda5-457b-82f8-a960635f60c7`; processing state `VALID`.
- Set export compliance to `usesNonExemptEncryption=false`, attached build `0.1 (9)` to public group `Wander Alpha`, and submitted it for external TestFlight review.
- Apple currently reports build `0.1 (9)` beta review state `WAITING_FOR_REVIEW`.
- Final App Store Connect check after push: build `0.1 (9)` is `VALID`, `usesNonExemptEncryption=false`, and external beta review state is `APPROVED`.

## 2026-06-06 13:20 PDT - Codex - M6 Backend Extraction Plan Eng Review

Agent: Codex
Branch: `main`
Starting commit: `efc5033`
Starting status: local `main` matches `origin/main`; worktree clean before this log entry.

Goal: run `/plan-eng-review` against the next M6 backend extraction step before implementation.

Expected files to inspect/touch:

- `docs/plans/2026-06-01-wander-ios-eng-plan.md`
- `docs/specs/wander-ios-product-spec.md`
- `docs/backend/m3-supabase-foundation.md`
- `docs/plans/2026-06-01-wander-m1-5-contract-lock.md`
- `Wander/Models/LocalModels.swift`
- `Wander/Services/RepositoryProtocols.swift`
- `Wander/Services/WanderLocalStore.swift`
- `Wander/Services/Remote/SupabaseRepositories.swift`
- `supabase/migrations/*`
- `docs/agent-log.md`

Notes:

- Mission Control remains unreachable on `localhost:4000` (`curl` exit 7), so this repo log is the coordination record.
- gstack preamble reported `UPGRADE_AVAILABLE 1.26.0.0 1.56.0.0`; upgrade was snoozed for this review so the toolchain does not change mid-task.
- gstack design-doc check found no branch-specific design artifact; using the existing Wander product spec, M1.5 contract, M3 backend doc, decisions doc, and current code as review inputs.

Checkpoint:

- Joe paused the M6 review to triage friend TestFlight feedback from Build 9.
- Decision: Build 10 cleanup should happen before M6 because the findings are current-test blockers: Dark Mode contrast, Map search behavior, Add flow escape hatches, and chip/sheet readability.

## 2026-06-06 19:19 PDT - Codex - Build 10 Friend Test Cleanup

Agent: Codex
Branch: `main`
Starting commit: `efc5033`
Starting status: local `main` matched `origin/main`; `docs/agent-log.md` already had the in-progress M6 review entry above from this session.

Goal: implement the pre-M6 Build 10 cleanup from friend screenshots, then provide a QA checklist for Joe/friend testing.

Expected files to touch:

- `Wander/App/WanderRootView.swift`
- `Wander/Features/Add/AddScreen.swift`
- `Wander/Features/Map/MapScreen.swift`
- `docs/qa/2026-06-08-build-11-pre-m6-test-checklist.md`
- `docs/agent-log.md`

Plan:

- Force the alpha UI into the approved light theme so Dark Mode cannot make cream surfaces unreadable.
- Make Map search text readable and make keyboard Search run real MapKit candidate search.
- Add visible Add-flow recovery actions: change/search again and back to Add home.
- Reset Add to the home/source picker after leaving the Add tab.
- Replace quick-detail question grid spacing with a wrapping chip layout.
- Add a friend-test QA checklist doc before shipping.

Checkpoint:

- Forced the app into the approved light theme at the root so iOS Dark Mode no longer turns cream-surface text white.
- Wired Map search submit to `store.manualCandidates(...)` so pressing keyboard Search can find unsaved place candidates, show transient pins/sheets, and allow saving them to the user's map.
- Added Map search loading/error state and made search/candidate/sheet text explicitly readable against the warm map and cream surfaces.
- Added Add-flow recovery actions on confirmation/details screens: search/change place and back to Add home.
- Reset Add to source picker when the user leaves the Add tab and returns.
- Replaced Add quick-details `LazyVGrid` chips with a custom wrapping layout to remove spacing holes.
- Added QA checklist, now carried forward at `docs/qa/2026-06-08-build-11-pre-m6-test-checklist.md`.
- Ran full tests:
  `xcodebuild -quiet test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Result: passed before and after the build-number bump/project regeneration.
- Simulator smoke screenshots captured:
  `DerivedData/build10-map-smoke.png`
  `DerivedData/build10-add-smoke.png`
- Bumped `CURRENT_PROJECT_VERSION` to `10`, regenerated `Wander.xcodeproj` with `xcodegen generate`, archived `/private/tmp/Wander-0.1-build10.xcarchive`, and uploaded build `0.1 (10)`.
- App Store Connect build id for `0.1 (10)`: `128f2b2b-3523-4620-beb5-72bef23ceaa6`; processing state `VALID`.
- Set export compliance to `usesNonExemptEncryption=false`, attached build `0.1 (10)` to public group `Wander Alpha`, and submitted it for external TestFlight review.
- Final App Store Connect check: build `0.1 (10)` is `VALID`, `usesNonExemptEncryption=false`, and external beta review state is `APPROVED`.

## 2026-06-08 00:00 PDT - Codex - Build 11 Map Search Scope Fix

Agent: Codex
Branch: `main`
Starting commit: `3f32589`
Starting status: local `main` matched `origin/main`; worktree clean before this log entry.

Goal: fix Joe's Build 10 TestFlight finding that logged-out Map search behaves like global Apple Maps search and shows unsaved candidates as saveable/saved.

Expected files to touch:

- `Wander/Features/Map/MapScreen.swift`
- `docs/qa/2026-06-08-build-11-pre-m6-test-checklist.md`
- `docs/setup.md`
- `docs/agent-log.md`
- `project.yml`
- `Wander.xcodeproj/project.pbxproj`

Decision:

- Map search must only search places already visible in the user's map graph: own saved places plus visible network places.
- Global place lookup/search belongs in Add, not Map.
- Map may still allow saving a social/network place someone else saved, but it should not create transient global candidates from arbitrary map search text.

Checkpoint:

- Removed the Build 10 transient global Map search candidate path from `MapScreen`.
- Map search now filters only `store.visiblePlaces(filters:)`, covering saved own places and visible network/social places.
- Removed `store.manualCandidates(...)` from Map; that global lookup remains in Add.
- Updated Map search placeholder to `search your map or people...`.
- Updated the QA checklist and renamed it to `docs/qa/2026-06-08-build-11-pre-m6-test-checklist.md`.
- Bumped `CURRENT_PROJECT_VERSION` to `11` and regenerated `Wander.xcodeproj` with `xcodegen generate`.
- First sandboxed test attempt failed from Xcode/CoreSimulator cache permission denial, not code.
- Reran full tests with normal Xcode access:
  `xcodebuild -quiet test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Result: passed.
- Archived `/private/tmp/Wander-0.1-build11.xcarchive` and uploaded build `0.1 (11)`.
- App Store Connect build id for `0.1 (11)`: `3d9db598-6cdb-4d49-8cb5-4892de6ff55d`; processing state `VALID`.
- Set export compliance to `usesNonExemptEncryption=false`, attached build `0.1 (11)` to public group `Wander Alpha`, and submitted it for external TestFlight review.
- Final App Store Connect check: build `0.1 (11)` is `VALID`, `usesNonExemptEncryption=false`, and external beta review state is `APPROVED`.

## 2026-06-08 17:39 PDT - Codex - Build 12 Add Navigation Cleanup

Agent: Codex
Branch: `main`
Starting commit: `8d1e758`
Starting status: local `main` matched `origin/main`; worktree clean before this log entry.

Goal: remove redundant Add-flow recovery buttons because the upper-left back control is the intended navigation escape.

Expected files to touch:

- `Wander/Features/Add/AddScreen.swift`
- `docs/qa/2026-06-08-build-11-pre-m6-test-checklist.md`
- `docs/agent-log.md`

Decision:

- Remove the `try a different link` / `back to add` recovery row from Add confirmation.
- Remove the `change place` / `back to add` recovery row from Add details.
- Keep the upper-left back button as the single back affordance inside Add.

Checkpoint:

- Removed both `RecoveryActionsRow` usages from Add confirmation/details.
- Removed the now-unused `RecoveryActionsRow` view, `AddSourceType.searchAgainTitle`, and `returnToSearchForCurrentSource()`.
- Updated the QA checklist to verify the extra buttons are absent and the upper-left back control handles navigation.
- Ran full tests:
  `xcodebuild -quiet test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Result: passed.
- No separate TestFlight upload for this micro-cleanup yet; include it in the next M6/TestFlight build unless Joe asks for an immediate build.

## 2026-06-08 17:44 PDT - Codex - M6 Extraction Job Enqueue And Nearby Ranking

Agent: Codex
Branch: `main`
Starting commit: `a39e3ed`
Starting status: local `main` matched `origin/main`; worktree clean before this log entry.

Goal: start M6 by making extraction drafts enqueue real remote jobs when signed in, and fix the current-location candidate quality issue Joe saw in TestFlight.

Expected files to touch:

- `Wander/Services/MapKitPlaceResolver.swift`
- `Wander/Services/RepositoryProtocols.swift`
- `Wander/App/WanderBackend.swift`
- `Wander/Services/Remote/SupabaseRepositories.swift`
- `Wander/Services/WanderLocalStore.swift`
- `Wander/Features/Add/AddScreen.swift`
- `supabase/migrations/*`
- `supabase/tests/*`
- `WanderTests/*`
- `docs/*`

Plan:

- Add a Supabase RPC to idempotently upsert `source_artifacts` and `extraction_jobs`.
- Add an iOS extraction repository around that RPC.
- Keep link/photo drafts local-first, then mark artifact/job synced or failed after remote enqueue.
- Improve current-location candidate ranking with closer radius first and distance/category-aware sorting.
- Keep extraction execution itself queued/pending; do not fake AI extraction or auto-save low confidence.

Checkpoint:

- Mission Control task creation failed because `http://localhost:4000` was unreachable from this session. Continuing with `docs/agent-log.md` as the coordination surface.
- Added `supabase/migrations/20260608174400_enqueue_extraction_job.sql` for the public/app `enqueue_extraction_job` RPC.
- Hosted pgTAP caught an ambiguous PL/pgSQL variable/column reference in the first function body.
- Added `supabase/migrations/20260608175500_fix_enqueue_extraction_job_variable.sql` with `v_` variable names and repushed.
- Added `supabase/tests/extraction_jobs.sql`; hosted pgTAP now passes `15 + 14 + 9 = 38` assertions across RLS, Clerk mirroring, and extraction enqueue tests.
- Added iOS `ExtractionRepository` contract plus `SupabaseExtractionRepository`.
- Signed-in link/photo unresolved drafts now enqueue remote extraction jobs and mark local source/job rows synced or failed.
- Improved `I'm here now` MapKit candidate ranking by searching a tight radius first and sorting by POI/category/distance.
- Important scope note: extraction job execution is still not implemented. Build 12 queues jobs only.

Completion:

- `git diff --check`: passed.
- Swift tests passed before and after XcodeGen/build bump:
  `xcodebuild -quiet test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Build number bumped to `0.1 (12)` in `project.yml` and regenerated `Wander.xcodeproj`.
- Archived and uploaded `/private/tmp/Wander-0.1-build12.xcarchive`.
- App Store Connect build id: `b2ae0178-8d35-40a8-a4be-80c31cd1ce3b`.
- Build `0.1 (12)` is `VALID`, export compliance is `usesNonExemptEncryption=false`, attached to `Wander Alpha`, and external TestFlight review is `APPROVED`.
- Public TestFlight link remains `https://testflight.apple.com/join/knEhRa6t`.
- Next M6 work: implement the backend worker/provider adapters that consume queued `extraction_jobs` and write candidate results without auto-saving low-confidence places.

## 2026-06-08 19:31 PDT - Codex - M6 Extraction Worker And Result Polling

Agent: Codex
Branch: `main`
Starting commit: `bb74fac`
Starting status: local `main` matched `origin/main`; worktree clean before this log entry.

Goal: continue M6 by adding the worker/result path after Build 12's extraction enqueue foundation.

Expected files to touch:

- `supabase/functions/*`
- `supabase/migrations/*`
- `supabase/tests/*`
- `Wander/Services/RepositoryProtocols.swift`
- `Wander/Services/Remote/SupabaseRepositories.swift`
- `Wander/App/WanderBackend.swift`
- `Wander/Services/WanderLocalStore.swift`
- `Wander/Features/Add/AddScreen.swift`
- `WanderTests/*`
- `docs/*`

Plan:

- Add service-role RPCs for safely claiming pending extraction jobs and completing/failing them.
- Add a Supabase Edge Function worker with conservative adapters: Google Maps/link/web text metadata first; photo remains a no-place/manual fallback until OCR storage is wired.
- Expose an authenticated app RPC to fetch extraction job results.
- Add iOS repository/store polling so a draft can become confirmable candidates without auto-saving.
- Keep low-confidence/no-place results as drafts with manual rescue.

Note:

- Mission Control task creation failed again because `http://localhost:4000` is unreachable in this session.

Checkpoint:

- Added `supabase/migrations/20260608193200_extraction_worker_rpcs.sql` with authenticated claim/get RPCs and service-role claim-next/complete RPCs.
- Hosted pgTAP initially caught missing execute grants for authenticated helper payload functions.
- Added `supabase/migrations/20260608194600_fix_extraction_worker_helper_grants.sql`.
- Hosted pgTAP now passes `15 + 14 + 16 = 45` assertions across RLS, Clerk mirroring, and extraction jobs.
- Added `supabase/functions/extraction-worker/index.ts` plus its import map and deployed it to project `rugmtlgufrhlxwfkumhw`.
- Live endpoint smoke without auth returns `401 missing_authorization`, confirming the deployed function is reachable and enforcing the app-triggered auth path.
- Added iOS Edge Function invocation support, extraction process/result repository methods, store result application, and Add-flow transition from processed coordinate-backed link results into the existing confirmation screen.
- Guardrail: extracted candidates without coordinates are not shown as saveable candidates in Add; unsupported/photo sources remain drafts.

Completion:

- Attempted to set explicit `WANDER_SUPABASE_ANON_KEY` fallback secret, but the CLI command hung and was terminated. The deployed worker still reads standard `SUPABASE_ANON_KEY` first, so this is not blocking Build 13.
- `git diff --check`: passed.
- Swift tests passed:
  `xcodebuild -quiet test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Hosted pgTAP passed:
  - `supabase/tests/rls_visibility.sql`: 15 assertions
  - `supabase/tests/clerk_profile_mirroring.sql`: 14 assertions
  - `supabase/tests/extraction_jobs.sql`: 16 assertions
- Supabase migrations applied to hosted project:
  - `20260608193200_extraction_worker_rpcs.sql`
  - `20260608194600_fix_extraction_worker_helper_grants.sql`
- Deployed Edge Function `extraction-worker`; unauthenticated smoke returns `401 missing_authorization`.
- Build number bumped to `0.1 (13)` and regenerated `Wander.xcodeproj`.
- Archived and uploaded `/private/tmp/Wander-0.1-build13.xcarchive`.
- App Store Connect build id: `727d0ab0-be96-4d81-8840-385c81f438bb`.
- Build `0.1 (13)` is `VALID`, export compliance is `usesNonExemptEncryption=false`, attached to `Wander Alpha`, and external TestFlight review is `APPROVED`.
- Public TestFlight link remains `https://testflight.apple.com/join/knEhRa6t`.
- Remaining M6 work: improve Google Maps/short-link robustness after real test results, add photo OCR/Vision, add TikTok/Instagram fallback adapters, add scheduled/background worker run, and finish alpha analytics/privacy/performance.

## 2026-06-08 20:15 PDT - Codex - Map User Location And Search Result Pins

Agent: Codex
Branch: `main`
Starting commit: `a80ab94`
Starting status: local `main` matched `origin/main`; worktree clean before this log entry.

Goal: fix Map behavior from Joe's feedback: show the user's location, add recenter control, allow Map search to surface unsaved MapKit POI results distinctly, hide plus on already-saved own places, and provide an edit/mark-been affordance for saved own places.

Expected files to touch:

- `Wander/Features/Map/MapScreen.swift`
- `Wander/Services/WanderLocalStore.swift`
- `WanderTests/*`
- `docs/*`
- `project.yml`
- `Wander.xcodeproj/project.pbxproj`

Decisions:

- MapKit supports POI search via `MKLocalSearch`; use that for explicit Map search result pins.
- Do not rely on tapping Apple's built-in POI labels in SwiftUI Map for this pass.
- Search result pins are temporary unsaved candidates and must look different from saved/social pins.
- Plus appears for unsaved search results and social places not already saved by the current user.
- Plus is hidden for places already on the current user's map; own saved places get an edit-style action.

Checkpoint:

- Added `UserAnnotation()` to Map and a custom recenter button that uses `.userLocation(fallback:)`.
- Added `MKLocalSearch` on Map search submit, scoped to the current camera region.
- Unsaved MapKit search results render as distinct dashed/yellow pins and use a separate sheet with `not saved yet` copy.
- Search-result `+` saves the candidate to the current user's map as `wanna`.
- Saved own places no longer show `+`; they show an edit/pencil action.
- Social places show `+` only when the current user has not already saved that place.
- Own saved `wanna` places can be marked `been` through the edit action; full edit sheet remains future work.
- Added `docs/qa/2026-06-08-build-14-map-search-location-checklist.md`.
- Swift tests passed:
  `xcodebuild -quiet test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`

Completion:

- `git diff --check`: passed.
- Swift tests passed again after bumping to Build 14 and regenerating the project.
- Build number bumped to `0.1 (14)` and regenerated `Wander.xcodeproj`.
- Archived and uploaded `/private/tmp/Wander-0.1-build14.xcarchive`.
- App Store Connect build id: `86743675-f9b9-4d5f-b51b-2efb612df992`.
- Build `0.1 (14)` is `VALID`, export compliance is `usesNonExemptEncryption=false`, attached to `Wander Alpha`, and external TestFlight review is `APPROVED`.
- Public TestFlight link remains `https://testflight.apple.com/join/knEhRa6t`.

## 2026-06-08 20:37 PDT - Codex - Map Recenter Zoom And Park Category Fix

Agent: Codex
Branch: `main`
Starting commit: `43664d5`
Starting status: worktree clean before this log entry. Mission Control localhost task create failed because `localhost:4000` was not reachable.

Goal: apply Joe's map feedback after Build 14: make the recenter control blue and bottom-right, recenter with a useful zoom around the user's current coordinate, make unsaved search result pins blue, and fix MapKit parks being categorized as hikes.

Expected files to touch:

- `Wander/Features/Map/MapScreen.swift`
- `Wander/Features/Add/AddScreen.swift`
- `Wander/Features/Discover/DiscoverScreen.swift`
- `Wander/Features/Profile/ProfileScreen.swift`
- `Wander/Services/MapKitPlaceResolver.swift`
- `Wander/Services/WanderPlaceCategory.swift`
- `WanderTests/WanderPlaceCategoryTests.swift`
- `docs/qa/2026-06-08-build-15-map-recenter-park-checklist.md`
- `docs/agent-log.md`
- `docs/setup.md`
- `project.yml`
- `Wander.xcodeproj/project.pbxproj`

Decision:

- Preserve MapKit `.park` and `.nationalPark` as Wander category `park`; the previous Map-screen search-only switch incorrectly collapsed parks into `hike`.
- Centralize MapKit-to-Wander category/icon mapping in `WanderPlaceCategory` so Map search, current-location add, manual add, Discover, and Profile stay aligned.
- Recenter uses an explicit current CoreLocation lookup and a fixed camera distance instead of `MapCameraPosition.userLocation`, because `userLocation` does not expose a stable app-defined zoom level.

Checkpoint:

- Added `WanderPlaceCategory` helper and park regression tests.
- Moved recenter control to the lower-right map chrome above the selected sheet.
- Changed recenter control and unsaved search-result pins to use the existing sky/pin-social blue.
- Added recenter zoom to a fixed 1.5km camera distance when current location is available, with a zoomed LA fallback.

Completion:

- `xcodegen generate`: passed.
- First Swift test run caught one stale reference to the removed private category mapper in current-location ranking; replaced it with `WanderPlaceCategory.primary(for:)`.
- `git diff --check`: passed.
- Swift tests passed:
  `xcodebuild -quiet test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Build number bumped to `0.1 (15)` and regenerated `Wander.xcodeproj`.
- Archived and uploaded `/private/tmp/Wander-0.1-build15.xcarchive`.
- App Store Connect build id: `2043c8e6-4972-4cbf-9de2-6e71d25af235`.
- Build `0.1 (15)` is `VALID`, export compliance is `usesNonExemptEncryption=false`, attached to `Wander Alpha`, and external TestFlight review is `APPROVED`.
- Public TestFlight link remains `https://testflight.apple.com/join/knEhRa6t`.

## 2026-06-08 20:58 PDT - Codex - Map Search Typeahead

Agent: Codex
Branch: `main`
Starting commit: `51a7231`
Starting status: worktree clean before this log entry. Mission Control localhost task create failed because `localhost:4000` was not reachable.

Goal: add typeahead suggestions to the Map search bar so short prefixes like `MCD` surface matching places such as McDonald's before submit.

Expected files to touch:

- `Wander/Features/Map/MapScreen.swift`
- `WanderTests/*` if logic is extracted enough to test directly
- `docs/agent-log.md`
- `docs/qa/*`
- `project.yml`
- `Wander.xcodeproj/project.pbxproj`

Initial approach:

- Keep saved/network matches first because Map search is still primarily the user's trusted map.
- Add debounced MapKit-backed suggestions for unsaved nearby POIs after at least two characters.
- Tapping a suggestion should run the same selection/search behavior as submit, rather than creating a second save path.

Completion:

- Added Map search typeahead with saved/network matches first and debounced MapKit POI suggestions after two characters.
- Tapping a saved/network suggestion selects and centers the existing saved/social pin.
- Tapping an unsaved MapKit suggestion centers the map, shows the blue unsaved pin, and opens the existing unsaved-result sheet with `+`.
- Added `docs/qa/2026-06-08-build-16-map-typeahead-checklist.md`.
- `xcodegen generate`: passed.
- `git diff --check`: passed.
- Swift tests passed:
  `xcodebuild -quiet test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Build number bumped to `0.1 (16)` and regenerated `Wander.xcodeproj`.
- Archived and uploaded `/private/tmp/Wander-0.1-build16.xcarchive`.
- App Store Connect build id: `9a98cbc5-8988-4952-9765-54e8f55d513d`.
- Build `0.1 (16)` is `VALID`, export compliance is `usesNonExemptEncryption=false`, attached to `Wander Alpha`, and external TestFlight review is `APPROVED`.
- Public TestFlight link remains `https://testflight.apple.com/join/knEhRa6t`.

## 2026-06-09 11:18 PDT - Codex - Rich Place Profile Sheet

Agent: Codex
Branch: `main`
Starting commit: `15473c0`
Starting status: worktree clean.

Goal: implement Joe's no-billing rich place profile direction for the Map selected-place sheet: Beli/Slate-inspired expanded profile, social proof, share, Google Maps directions, own captured answers, friend notes/reviews, and no empty metadata rows for data we cannot actually deliver.

Coordination:

- Spawned read-only subagent Maxwell to inspect `MapScreen.swift` integration points and SwiftUI gotchas.
- Spawned read-only subagent Averroes to audit current metadata availability and no-billing docs/QA implications.
- Keep code implementation local because `Wander/Features/Map/MapScreen.swift` is conflict-prone.

Expected files to touch:

- `Wander/Features/Map/MapScreen.swift`
- `Wander/Services/PlaceExternalLinks.swift`
- `WanderTests/PlaceExternalLinksTests.swift`
- `docs/decisions.md`
- `docs/open-questions.md`
- `docs/qa/*`
- `docs/agent-log.md`
- `project.yml`
- `Wander.xcodeproj/project.pbxproj`

Checkpoint:

- Added `PlaceExternalLinks` for keyless Google Maps directions/search/share URLs; no Google SDK/API key or paid place metadata provider is introduced.
- Reworked the selected Map `PlaceSheet` expanded state into a scrollable place profile: hero, social proof, share icon, directions action, real place facts, "your save", and friend save cards.
- The expanded profile only renders fields Wander actually has. It intentionally omits website, phone, hours, cuisine, order, ratings, and photos until a free/source-owned data path exists.
- Removed the Map profile sheet's fake `Los Angeles` fallback when locality/address is missing.
- Added `PlaceExternalLinksTests` and `docs/qa/2026-06-09-build-17-rich-place-profile-checklist.md`.
- Updated `docs/decisions.md` and `docs/open-questions.md` with the no-billing/no-empty metadata constraint.
- `xcodegen generate`: passed.
- Initial sandboxed `xcodebuild test` failed on CoreSimulator/SwiftPM cache permissions, not app code.
- Escalated Swift tests passed, then passed again after bumping build number to `0.1 (17)`.
- Archived `/private/tmp/Wander-0.1-build17.xcarchive` successfully.
- Uploaded build `0.1 (17)` to App Store Connect.

Completion:

- App Store Connect build id: `4d38f9a2-e228-4842-bd97-1da5acd4e3fd`.
- Build `0.1 (17)` is `VALID`, export compliance is `usesNonExemptEncryption=false`, attached to `Wander Alpha`, and external TestFlight review is `APPROVED`.
- Public TestFlight link remains `https://testflight.apple.com/join/knEhRa6t`.
- Remaining follow-up: remote visible-place attributes still need hydration into the expanded profile; local saves and fixture-backed social saves show their answer chips now.

## 2026-06-09 12:02 PDT - Codex - Build 17 Feedback Triage

Agent: Codex
Branch: `main`
Starting commit: `d35b0fc`
Starting status: worktree clean.

Goal: triage Joe/friend Build 17 feedback before implementation: user location dot color, typeahead keyboard behavior, plus/edit flow semantics, sync failed after Add, follow graph visibility, in-memory persistence, celebratory save completion, and future share/deep-link/web landing behavior.

Findings:

- Persistence loss after app kill is expected in the current implementation but not acceptable for alpha: `WanderApp` still injects `WanderModelContainer.preview`, whose `ModelConfiguration` is `isStoredInMemoryOnly: true`, and `WanderStore` is currently array-backed rather than hydrated from SwiftData on launch.
- Follow/unfollow RPCs exist, but relationship reads/followers/following joined profile reads are still partly local or not implemented. Following can appear broken because local follow state is not reliably rehydrated, remote relationship metadata is not fully returned to the UI, and remote visible places may not refresh with relationship context after follow.
- Add-tab save can show `sync failed` while the place still appears on the map because the app performs local-first save, then marks remote sync failed if `save_own_place` rejects/fails. That is a bug to debug if the network/auth path is healthy.
- Typeahead selection does not explicitly dismiss keyboard today.
- Map plus on unsaved/social places saves directly as `wanna` with default visibility; it does not currently route through the Add confirmation/details/questions flow.
- The edit pencil mostly marks `wanna` as `been` or shows "editing saved places is coming next"; full edit/details is not implemented.

## 2026-06-09 12:03 PDT - Codex - Durable Local Persistence

Agent: Codex
Branch: `main`
Starting commit: `412e355`
Starting status: one untracked file was already present: `Wander/Services/WanderStorePersistence.swift`.

Goal: execute the next highest-risk alpha fix from Build 17 feedback: make saved places, follows/blocks, drafts, source artifacts, extraction jobs, attributes, and default visibility survive app kill/relaunch.

Remaining work list from latest triage:

- Durable local persistence for saves/follows/drafts.
- Follow graph reliability: relationship refresh, remote profile/following/follower reads, and social places appearing after follow.
- Add-tab `sync failed` diagnosis.
- Map typeahead keyboard dismissal after selecting a result.
- Map plus should enter the Add-style confirmation/details flow for unsaved places instead of direct-saving incomplete metadata.
- Real edit flow for saved places: status, visibility, answers, notes.
- Save success should be a short celebratory toast/haptic/add-another moment, not a full-screen success state.
- Map user location dot should use Apple Maps-style blue.
- Place profile cleanup: address should not appear as a chip.
- Remote visible-place attribute hydration into the expanded place profile.
- Later share/deep-link/web landing page.
- M6 extraction hardening: Google Maps robustness, generic web metadata, photo OCR, TikTok/Instagram.
- Alpha readiness: privacy copy, onboarding/auth gates, analytics provider, performance/QA.

Expected files to touch:

- `Wander/Services/WanderStorePersistence.swift`
- `Wander/Services/WanderLocalStore.swift`
- `Wander/App/WanderRootView.swift`
- `WanderTests/WanderStoreTests.swift`
- `project.yml`
- `Wander.xcodeproj/project.pbxproj`
- `docs/agent-log.md`

Checkpoint:

- Reused and completed the existing untracked `WanderStorePersistence.swift` as a JSON snapshot store under Application Support.
- Live fixture mode now injects `WanderStorePersistence.live`; demo fixture mode remains non-persistent.
- `WanderStore` now restores saved places, user places, attributes, follows, blocks, drafts, source artifacts, extraction jobs, current profile, and default visibility from disk.
- Added persistence calls around local save, draft, follow, block, sync-marking, profile-shell, and extraction-job mutations.
- Added relaunch tests covering saved place answers/default visibility and social graph/draft restore.
- `xcodegen generate`: passed.
- Initial sandboxed test run failed from CoreSimulator/SwiftPM cache permissions only.
- Focused `WanderStoreTests`: passed with elevated `xcodebuild`.
- Full test suite: passed with elevated `xcodebuild`.

Completion:

- Commit `e15da72` (`fix: persist local wander state`) pushed to `origin/main`.
- Next restart point: map typeahead keyboard dismissal, then Add-style plus/edit flow.

## 2026-06-09 12:14 PDT - Codex - Map Typeahead Keyboard Dismissal

Agent: Codex
Branch: `main`
Starting commit: `e15da72`
Starting status: worktree clean.

Goal: fix the small Map UX issue where selecting a typeahead result leaves the keyboard up over the selected place/result sheet.

Expected files to touch:

- `Wander/Features/Map/MapScreen.swift`
- `docs/agent-log.md`

Checkpoint:

- Added explicit keyboard dismissal on Map search submit and typeahead selection.
- Full test suite passed with elevated `xcodebuild`.

Completion:

- Commit `b4b6259` (`fix: dismiss map search keyboard on selection`) pushed to `origin/main`.

## 2026-06-09 12:18 PDT - Codex - Build 18 TestFlight Package

Agent: Codex
Branch: `main`
Starting commit: `b4b6259`
Starting status: worktree clean.

Goal: package the durable persistence and Map keyboard fixes into TestFlight build `0.1 (18)` for Joe/friend testing.

Expected files to touch:

- `project.yml`
- `Wander.xcodeproj/project.pbxproj`
- `docs/agent-log.md`

Completion:

- Build number bumped to `0.1 (19)`.
- `xcodegen generate`: passed.
- Full test suite passed with elevated `xcodebuild`.
- Commit `280199f` (`chore: bump wander build 19`) pushed to `origin/main`.
- Archived `/private/tmp/Wander-0.1-build19.xcarchive`.
- Uploaded build `0.1 (19)` to App Store Connect.
- App Store Connect build id: `f86fc338-1efa-4cb6-b20c-3fdafb714849`.
- Build `0.1 (19)` is `VALID`, export compliance is `usesNonExemptEncryption=false`, attached to `Wander Alpha`, and external TestFlight review is `APPROVED`.
- Public TestFlight link remains `https://testflight.apple.com/join/knEhRa6t`.

Completion:

- Build number bumped to `0.1 (18)`.
- `xcodegen generate`: passed.
- Full test suite passed with elevated `xcodebuild`.
- Commit `a8d309a` (`chore: bump wander build 18`) pushed to `origin/main`.
- Archived `/private/tmp/Wander-0.1-build18.xcarchive`.
- Uploaded build `0.1 (18)` to App Store Connect.
- App Store Connect build id: `66d14c39-ab78-4b66-a05b-488a36f4a6c2`.
- Build `0.1 (18)` is `VALID`, export compliance is `usesNonExemptEncryption=false`, attached to `Wander Alpha`, and external TestFlight review is `APPROVED`.
- Public TestFlight link remains `https://testflight.apple.com/join/knEhRa6t`.

## 2026-06-09 12:32 PDT - Codex - Map Save/Edit Flow

Agent: Codex
Branch: `main`
Starting commit: `8c26a11`
Starting status: worktree clean.

Goal: replace Map direct-save/placeholder edit behavior with a real save/edit sheet that captures the same core data as Add: been/wanna, visibility, category-specific question answers, and note.

Expected files to touch:

- `Wander/Features/Map/MapScreen.swift`
- `Wander/Features/Add/AddScreen.swift`
- `Wander/Features/Add/AddQuestionTemplates.swift`
- `Wander.xcodeproj/project.pbxproj`
- `docs/agent-log.md`

Checkpoint:

- Extracted Add category question templates into shared `Wander/Features/Add/AddQuestionTemplates.swift`.
- Map unsaved result `+` now opens a save sheet with status, visibility, category-specific answers, and note instead of direct-saving.
- Map social place `+` now opens the same save sheet; final save still requires sign-in for social saves.
- Map saved-place pencil now opens the same flow prefilled with existing status, visibility, note, and answer attributes.
- The flow updates saved places through `WanderStore.saveCandidate`, so persistence/sync state paths remain shared.
- `xcodegen generate`: passed.
- Full test suite passed with elevated `xcodebuild`.

Completion:

- Commit `a71a909` (`feat: add map save edit flow`) pushed to `origin/main`.

## 2026-06-09 15:17 PDT - Codex - Build 21 Social Graph And Save Questions

Agent: Codex
Branch: `main`
Starting commit: `fa71dad`
Starting status: worktree clean.

Goal: finish the next alpha batch instead of asking Joe to test partial social graph behavior: make best-for fields multi-select, make rating chips emoji-based, make save success quieter/short-lived, and wire the remaining remote social graph list/relationship hydration path.

Expected files to touch:

- `Wander/Features/Add/AddQuestionTemplates.swift`
- `Wander/Features/Add/AddScreen.swift`
- `Wander/Features/Map/MapScreen.swift`
- `Wander/App/WanderBackend.swift`
- `Wander/Services/Remote/*`
- `Wander/Services/WanderLocalStore.swift`
- `WanderTests/*`
- `supabase/migrations/*`
- `docs/agent-log.md`
- `project.yml`
- `Wander.xcodeproj/project.pbxproj`

Checkpoint:

- Mission Control was not reachable on `localhost:4000`; repo coordination is captured here.
- Clarification for Joe: "remote" in this repo means backend/Supabase data, distinct from local fixtures or local-only saves.
- Save question templates now use emoji rating chips for "how much did you like it?" and make restaurant/bar/park "best for?" multi-select; existing tags remain multi-select.
- Add save success auto-dismisses faster; sync/sign-in-needed messages stay visible a bit longer because they are actionable.
- Map "Added to your map" / "Updated saved place" messages now clear after 2 seconds instead of sticking in the search message slot.
- Added Supabase migration `20260609211700_social_graph_rpcs.sql` for `profile_followers`, `profile_following`, and `profile_relationship`.
- Wired the new graph RPCs through `SupabaseFollowRepository`, `WanderBackend`, and `WanderStore.refreshRemoteSocialGraph`.
- Profile and graph list screens now refresh backend graph data when opened.
- Full `xcodebuild test`: passed before packaging.
- Applied hosted Supabase migration with `npx supabase db push --linked --yes`.
- Verified local/remote migration list includes `20260609211700`.

Completion:

- Bumped `CURRENT_PROJECT_VERSION` to `21` in `project.yml`.
- Regenerated `Wander.xcodeproj` with `xcodegen generate`.
- Full `xcodebuild test`: passed again after project generation.
- Commit `ffa678d` (`feat: hydrate social graph`) pushed to `origin/main`.
- Archived `/private/tmp/Wander-0.1-build21.xcarchive`.
- Uploaded build `0.1 (21)` to App Store Connect.
- App Store Connect build id: `a98d8c29-2156-4971-befd-fda8c2bb1bc8`.
- Build `0.1 (21)` is `VALID`, export compliance is `usesNonExemptEncryption=false`, attached to `Wander Alpha`, and external TestFlight review is `APPROVED`.
- Public TestFlight link remains `https://testflight.apple.com/join/knEhRa6t`.

## 2026-06-09 12:58 PDT - Codex - Build 20 Social Reliability Batch

Agent: Codex
Branch: `main`
Starting commit: `b15b637`
Starting status: worktree clean.

Goal: batch the next alpha reliability fixes before the next TestFlight: keep social places refreshed after follow graph mutations, wire profile-specific remote places, hydrate remote answer attributes for richer place sheets, make Add success less like a full-screen dead end, then test/package.

Expected files to touch:

- `Wander/App/WanderBackend.swift`
- `Wander/Services/DiscoverModels.swift`
- `Wander/Services/Remote/SupabaseDTOs.swift`
- `Wander/Services/Remote/SupabaseRepositories.swift`
- `Wander/Services/WanderLocalStore.swift`
- `Wander/Features/Add/AddScreen.swift`
- `Wander/Features/Profile/ProfileScreen.swift`
- `WanderTests/*`
- `project.yml`
- `Wander.xcodeproj/project.pbxproj`
- `docs/agent-log.md`

Checkpoint:

- Mission Control was not reachable on `localhost:4000`; repo coordination is captured here.
- Remote visible place DTOs now preserve answer attributes into `VisiblePlace.attributes`.
- Store refresh now hydrates remote profile shells and answer attributes so place sheets/social saves can read returned answers.
- Remote social filtering now trusts backend-authorized rows for following/social scopes while still honoring local block state; Friends also admits backend mutuals-only rows.
- Follow/unfollow/block/unblock now trigger a broad remote place refresh after backend success.
- `profile_visible_places` is wired through the Supabase user-place repository and Profile detail refreshes on open/after follow changes.
- Add save now returns to the Add source screen and shows a compact saved/sync-state toast with haptic feedback instead of the old full-screen success page.
- `git diff --check`: passed.
- Full `xcodebuild test`: passed.

Completion:

- Bumped `CURRENT_PROJECT_VERSION` to `20` in `project.yml`.
- Regenerated `Wander.xcodeproj` with `xcodegen generate`.
- Full `xcodebuild test`: passed again after project generation.
- Commit `caa40f1` (`feat: refresh social place data`) pushed to `origin/main`.
- Archived `/private/tmp/Wander-0.1-build20.xcarchive`.
- Uploaded build `0.1 (20)` to App Store Connect.
- App Store Connect build id: `aceee488-a4d7-4759-ba6d-63a16c9c9ca7`.
- Build `0.1 (20)` is `VALID`, export compliance is `usesNonExemptEncryption=false`, attached to `Wander Alpha`, and external TestFlight review is `APPROVED`.
- Public TestFlight link remains `https://testflight.apple.com/join/knEhRa6t`.

## 2026-06-09 12:41 PDT - Codex - Build 19 TestFlight Package

Agent: Codex
Branch: `main`
Starting commit: `a71a909`
Starting status: worktree clean.

Goal: package persistence, Map keyboard dismissal, and Map save/edit flow into TestFlight build `0.1 (19)`.

Expected files to touch:

- `project.yml`
- `Wander.xcodeproj/project.pbxproj`
- `docs/agent-log.md`

## 2026-06-09 15:44 PDT - Codex - Discover Place Row Detail Fix

Agent: Codex
Branch: `main`
Starting commit: `31e2dfd`
Starting status: worktree clean.

Goal: fix Discover place rows so tapping a place opens a design-compliant place detail surface instead of the saver profile, while keeping profile access secondary inside the place card.

Expected files to touch:

- `Wander/Features/Discover/DiscoverScreen.swift`
- `docs/agent-log.md`

Completion:

- Discover place rows now open a place detail sheet instead of jumping directly to the saver profile.
- Saver/profile access remains available from the place detail sheet.
- The Discover plus action is hidden for places already saved by the current user.
- The new place sheet mirrors the Map sheet style and only shows metadata currently available without paid/billing-backed APIs: category, address/locality, directions, share, saved-by context, note, and saved answer chips.
- `git diff --check`: passed.
- Full elevated `xcodebuild test`: passed, 80 tests.
- Commit `1722197` (`fix: open discover places as place details`) pushed to `origin/main`.
- Bumped `CURRENT_PROJECT_VERSION` to `22` in `project.yml`.
- Regenerated `Wander.xcodeproj` with `xcodegen generate`.
- Full elevated `xcodebuild test`: passed again after project generation, 80 tests.
- Commit `0753ba0` (`chore: bump wander build 22`) pushed to `origin/main`.
- Archived `/private/tmp/Wander-0.1-build22.xcarchive`.
- Uploaded build `0.1 (22)` to App Store Connect.
- App Store Connect build id: `00f928e3-bdc7-4327-92a5-dde06e148334`.
- Build `0.1 (22)` is `VALID`, export compliance is `usesNonExemptEncryption=false`, attached to `Wander Alpha`, and external TestFlight review is `APPROVED`.
- Public TestFlight link remains `https://testflight.apple.com/join/knEhRa6t`.

## 2026-06-09 16:24 PDT - Codex - Build 23 Map Detail Fixes

Agent: Codex
Branch: `main`
Starting commit: `4d3bf63`
Starting status: worktree clean.

Goal: ship the pre-place-profile fixes Joe requested: tap empty map to clear selection, remove address chips from place facts, keep selected save notes visible in expanded place cards, and investigate the followers-visible place report before changing the richer profile design.

Expected files to touch:

- `Wander/Features/Map/MapScreen.swift`
- `Wander/Features/Discover/DiscoverScreen.swift`
- `WanderTests/*` if a focused regression test is practical
- `docs/agent-log.md`

Scoped plan-eng-review notes:

- No design doc found for this branch; skipped /office-hours because this is a narrow bugfix batch and Joe explicitly asked to do these fixes before the larger place-profile change.
- Step 0 scope: keep website/order/Google reviews out of this patch. Official Google Places docs put reviews in paid Places API field tiers, so no-billing alpha should not depend on Google reviews.
- Existing code reused: `PlaceSheet`, `DiscoverPlaceDetailSheet`, `VisiblePlace.note`, `saveSummaries(for:)`, `PlaceExternalLinks`, MapKit-backed candidates, and Supabase visible-place RPCs.
- NOT in scope: Beli-style rich place profile, website/call/order fields, Google reviews, and new paid Places integration.

Checkpoint:

- Removed address from place fact chips in Map and Discover place detail sheets while keeping address/locality in subtitle text.
- Changed Map empty-tap behavior so tapping away from selected pins/candidates clears the selected sheet instead of leaving stale selection active.
- Kept selected save notes visible in expanded Map place sheets, attributed the note owner in Map and Discover, and made Map save-summary aggregation use all authorized saves for that place instead of only currently filtered/search-visible rows.
- Added a focused store test assertion that backend-authorized remote social/following rows keep their notes after hydration.
- Added `TODOS.md` guidance for the richer place-profile action bar: Directions can be generated from coordinates; Website/Call/Order require real supplied data and should be hidden when absent; Google reviews are not a no-billing alpha dependency.

Completion:

- Scoped `/plan-eng-review` result: this was a narrow bugfix/release batch, not a new architecture change. Website/Call/Order stays in the next richer place-profile data pass and must hide absent actions.
- Follower visibility investigation: app policy and Supabase RLS already say a follower can read `followers`/Everyone places; the live report is most likely a missing remote follow edge, failed local-only save/sync, stale refresh, or viewport mismatch rather than an intended rule. Added client regression coverage for remote social/following notes.
- Official Google Places docs put `reviews` in a paid field tier, so Google reviews are not part of the no-billing alpha path.
- `git diff --check`: passed.
- Full elevated `xcodebuild test`: passed, 80 tests.
- Full elevated `xcodebuild test` after build-number regeneration: passed, 80 tests.
- Commit `7357efe` (`fix: polish place detail map interactions`) pushed to `origin/main`.
- Commit `704c6a9` (`chore: bump wander build 23`) pushed to `origin/main`.
- Archived `/private/tmp/Wander-0.1-build23.xcarchive`.
- Uploaded build `0.1 (23)` to App Store Connect.
- App Store Connect build id: `2964e3eb-fdc7-428a-b7f7-eafefefa182d`.
- Build `0.1 (23)` is `VALID`, export compliance is `usesNonExemptEncryption=false`, attached to `Wander Alpha`, and external TestFlight review is `APPROVED`.
- Public TestFlight link remains `https://testflight.apple.com/join/knEhRa6t`.

## 2026-06-09 17:00 PDT - Codex - Rec.me TestFlight Slack Protocol

Agent: Codex
Branch: `main`
Starting commit: `42a517d`
Starting status: worktree clean.

Goal: make it durable that every future TestFlight build post includes a Slack update in the rec.me feedback channel, and send the Build 23 testing note now.

Expected files to touch:

- `AGENTS.md`
- `docs/agent-log.md`

Slack channel lookup:

- `#testflight-feedback` (`C0BAA7DG2AC`) is the rec.me TestFlight feedback channel.
- `#all-recme` (`C0B9FU1QNG2`) exists for broader rec.me announcements, but TestFlight build notes should go to `#testflight-feedback`.

Completion:

- Updated `AGENTS.md` to name Rec.me as the product name, keep Wander as the former/repo name, and require every future TestFlight build to post release notes to `#testflight-feedback`.
- Slack Build 23 release/testing note posted to `#testflight-feedback`: `https://recmegroup.slack.com/archives/C0BAA7DG2AC/p1781049362472419`.
- No app tests run; this was documentation plus Slack communication only.

Follow-up:

- Joe asked for recurring polling of `#testflight-feedback` for bugs/issues, with `:airplane_departure:` when triage starts and `:white_check_mark:` when done, plus scoped `plan-eng-review` / `plan-design-review` in a standalone/new-chat context when necessary.
- Attempted to create an hourly Codex automation, but the app returned `No handler registered for tool: automation_update`; recurring job was not saved from this session.
- Updated `AGENTS.md` with the full manual/automation protocol so future agents can execute it and create the automation once the handler is available.

Immediate poll:

- Found Ryan's Build 23 feedback in `#testflight-feedback`: `https://recmegroup.slack.com/archives/C0BAA7DG2AC/p1781051088761659`.
- Report: "The tap in and tap away is a little buggy. When I zoom out, sometimes i have to tap twice to select or unselect the pin"
- Added `:airplane_departure:` reaction before triage.
- Initial classification: engineering bug/regression in MapKit tap hit-testing/selection clearing, not a design review issue unless the fix changes the interaction model.
- Triage recommendation posted in-thread: `https://recmegroup.slack.com/archives/C0BAA7DG2AC/p1781074371972679?thread_ts=1781051088.761659&cid=C0BAA7DG2AC`.
- Added `:white_check_mark:` reaction after triage.
- Added the issue to `TODOS.md` as a P1 Build 23 Map tap hit-testing regression.

## 2026-06-09 17:08 PDT - Codex - Collaboration PR Workflow

Agent: Codex
Branch: `main`
Starting commit: `c7a6c75`
Starting status: worktree clean.

Goal: update repo agent instructions so Joe, Ryan, and agents coordinate through short-lived branches, worktrees when useful, and PR handoffs.

Expected files to touch:

- `AGENTS.md`
- `docs/agent-log.md`

Completion:

- Added `Collaboration And Git Workflow` guidance to `AGENTS.md`.
- Documented branch prefixes for Joe, Ryan, Codex, Claude, and OpenClaw.
- Added explicit instruction that Ryan-owned feature/fix/change sessions should push `ryan/<short-task>` branches and open or update a draft/ready PR before stopping, unless Ryan explicitly says not to push or open a PR.
- No app tests run; this was documentation/process only.

## 2026-06-09 17:24 PDT - Codex - Slack Triage Reply Correction

Agent: Codex
Branch: `main`
Starting commit: `7993c13`
Starting status: worktree clean.

Goal: correct the TestFlight feedback triage protocol so agents do not reply in Slack during triage; Slack should only get reactions unless Joe explicitly asks otherwise. Triage analysis and recommendations should happen in Codex/new standalone threads.

Expected files to touch:

- `AGENTS.md`
- `docs/agent-log.md`

Completion:

- Updated `AGENTS.md` triage rules: use `:airplane_departure:` and `:white_check_mark:` reactions only, do not post Slack triage replies by default, and surface analysis/questions/recommendations in Codex.
- No app tests run; this was documentation/process only.

## 2026-06-10 00:00 PDT - Codex - App Store Build Increment Rule

Agent: Codex
Branch: `main`
Starting commit: `a199184`
Starting status: worktree clean.

Goal: make the App Store/TestFlight build-number bump rule durable for all agents working in rec.me.

Expected files to touch:

- `AGENTS.md`
- `docs/agent-log.md`

Completion:

- Added `AGENTS.md` instructions requiring any `main` update intended for App Store Connect/TestFlight to increment `CURRENT_PROJECT_VERSION` in `project.yml`, run `xcodegen generate`, commit `project.yml` plus `Wander.xcodeproj/project.pbxproj`, and log the build number/upload status.
- Clarified that docs-only/process-only commits do not need a build bump unless they are being packaged into a new TestFlight/App Store build.
- No app tests run; this was documentation/process only.

## 2026-06-10 00:03 PDT - Codex - Remove Manual Feedback Polling

Agent: Codex
Branch: `main`
Starting commit: `b4fc05b`
Starting status: worktree clean.

Goal: remove manual Slack feedback polling instructions from `AGENTS.md`; TestFlight feedback triage should be handled by a recurring automation instead of every agent polling the channel.

Expected files to touch:

- `AGENTS.md`
- `docs/agent-log.md`

Completion:

- Removed the `TestFlight Feedback Triage` section from `AGENTS.md`.
- Kept the TestFlight release-note rule for actual build uploads/availability confirmations.
- No app tests run; this was documentation/process only.

## 2026-06-10 00:08 PDT - Codex - Roadmap Steps 1-4

Agent: Codex
Branch: `codex/roadmap-1-4`
Starting commit: `ea352b9`
Starting status: worktree clean after branch creation.

Goal: execute roadmap steps 1-4: fix Build 23 map tap hit-testing, verify/fix social visibility, polish save/add semantics, and harden the current M6 extraction path.

Expected files to touch:

- `Wander/Features/Map/MapScreen.swift`
- `Wander/Features/Add/AddScreen.swift`
- `Wander/Services/WanderLocalStore.swift`
- `Wander/Services/Remote/SupabaseRepositories.swift`
- `Wander/Services/Remote/SupabaseDTOs.swift`
- `Wander/Services/MapKitPlaceResolver.swift`
- `Wander/Services/LinkPlaceParser.swift`
- `WanderTests/`
- `TODOS.md`
- `docs/agent-log.md`

Initial notes:

- P1 map hit-testing is likely caused by fixed meter-radius tap protection at zoomed-out map scales.
- Social visibility and add sync need verification against the current remote repository and local-first store behavior before changing contracts.
- Add/save polish should route unsaved map results through confirmation/details instead of direct-save, and keep saved places on edit/pencil semantics.

Checkpoint:

- Replaced Map tap-away protection with screen-space marker hit testing using `MapReader` projection, so zoom level no longer changes whether a tap clears a selected place.
- Verified follower-visible social rows are already covered by Supabase/RLS; fixed client freshness by refreshing visible remote places after signed-in own/social saves and when Discover opens or sign-in state changes.
- Confirmed map typeahead dismissal, map plus save flow, edit flow, and Add saved toast already exist in the current implementation.
- Hardened link add fallback: if local link parsing cannot resolve a place and the user is signed in, the Add flow now enqueues/processes a backend extraction job and only confirms candidates with coordinates and sufficient confidence.
- Tightened current-location suggestions with smaller search radii, stronger distance ranking, and MapKit category precedence so parks stay parks instead of text-fallback hikes.
- Added tests for map hit-testing, extraction candidate gating, and remote visible-place refresh after signed-in saves.
- Ran `xcodegen generate` to include new test files in `Wander.xcodeproj/project.pbxproj`.
- Tests: `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO` passed, 86 tests, 0 failures. Initial sandboxed run failed due CoreSimulator/cache sandbox access; elevated rerun passed.

Completion:

- Implementation commit: `6581581`.
- PR: https://github.com/joelipshutz/wander/pull/1
- Branch is ready for review/merge. No TestFlight build number was bumped yet; do that on/after merge when this is being packaged into the next uploaded build.
- Known follow-ups: realtime social refresh is still later, richer Instagram/TikTok/photo extraction providers are still later, and the original Add sync-failed report still needs signed-in device QA against Supabase.

## 2026-06-10 00:25 PDT - Codex - Build 24 TestFlight Prep

Agent: Codex
Branch: `main`
Starting commit: `555563b`
Starting status: worktree clean.

Goal: follow up the roadmap merge with the required TestFlight build-number bump and tester-facing Slack note.

Expected files to touch:

- `project.yml`
- `Wander.xcodeproj/project.pbxproj`
- `docs/agent-log.md`

Completion:

- Incremented `CURRENT_PROJECT_VERSION` from `23` to `24` in `project.yml`.
- Ran `xcodegen generate`, which updated `Wander.xcodeproj/project.pbxproj`.
- Posted a Slack note to `#testflight-feedback` explaining that main is prepared for build 24 but a binary upload is still pending: https://recmegroup.slack.com/archives/C0BAA7DG2AC/p1781076415347879
- No tests run for this build-number-only commit; prior roadmap merge test run passed 86 tests, 0 failures.

## 2026-06-10 00:32 PDT - Codex - Tighten Merge-To-TestFlight Rule

Agent: Codex
Branch: `main`
Starting commit: `ed4382d`
Starting status: worktree clean.

Goal: clarify that app-code merges to `main` should immediately get a TestFlight build-number bump before any tester-facing Slack note.

Expected files to touch:

- `AGENTS.md`
- `docs/agent-log.md`

Completion:

- Updated `AGENTS.md` so every app-code/UI/schema/testable behavior merge to `main` is treated as a TestFlight candidate by default unless Joe explicitly says otherwise.
- Required ordering is now explicit: merge implementation, bump `CURRENT_PROJECT_VERSION`, run `xcodegen generate`, commit/push `project.yml` plus `Wander.xcodeproj/project.pbxproj`, then post Slack. If the binary is not uploaded/available yet, the Slack note must say so plainly.
- No build bump for this docs-only process correction; it does not change the app binary.

## 2026-06-10 00:30 PDT - Codex - TestFlight Feedback Triage (Pin Color)

Agent: Codex
Branch: `main`
Starting commit: `d9d1a02`
Starting status: dirty worktree on `AGENTS.md` only; treated as pre-existing local work and not modified.

Goal: triage new actionable feedback in `#testflight-feedback` for "My pin is still orange. Should be blue like Apple Maps methinks (on the map)" without replying in Slack.

Expected files to touch:

- `docs/agent-log.md`

Investigation:

- Read latest `#testflight-feedback` messages and skipped already-closed tap-hit-testing feedback plus release-announcement posts.
- Added `:airplane_departure:` to Slack message `1781074469.991469` and read the full thread; no replies/thread context were present.
- Inspected map pin styling in `Wander/Features/Map/MapScreen.swift` and theme tokens in `Wander/DesignSystem/WanderTheme.swift`.
- Confirmed current-user saved place pins intentionally use `WanderTheme.pinYou` terracotta while visible social pins use `WanderTheme.pinSocial` blue.
- Confirmed `DESIGN.md` and `docs/specs/wander-ios-product-spec.md` currently support terracotta for user pins and blue for social pins, so changing "my pin" to blue is a design-direction change unless the feedback was actually about the current-location indicator.

Outcome:

- Classified as `P3`, app area `Map`, decision `approval-needed`.
- Did not implement because the report is subjective/ambiguous and conflicts with the current design baseline.
- Recommended default path: keep saved-place ownership colors as-is unless Joe explicitly wants to revise the map color system; if the complaint is about the current-location dot instead of saved-place markers, capture a screenshot/repro and fix that specific mismatch.
- No app tests run; triage only.

## 2026-06-10 00:41 PDT - Codex - Correct Release Sequence And Upload Build 24

Agent: Codex
Branch: `main`
Starting commit: `d9d1a02`
Starting status: dirty worktree on `docs/agent-log.md` from a pre-existing TestFlight feedback triage entry; preserving it and appending this work after it.

Goal: correct the durable release-order rule and finish the actual build 24 TestFlight archive/upload sequence. Joe clarified the required order: merge, bump/push build number, archive/upload, then Slack note.

Expected files to touch:

- `AGENTS.md`
- `docs/agent-log.md`

Initial notes:

- Build 24 has already been pushed to `main` in commit `ed4382d`, but the binary has not yet been archived/uploaded.
- A Slack note was posted too early saying build 24 was prepared but upload pending. The corrected rule should prevent this sequence error going forward.

Completion:

- Updated `AGENTS.md` so the required order is explicit: merge, bump/push build number, run tests, archive/upload, set/confirm TestFlight status, then post Slack.
- Full release test command passed:
  `xcodebuild -quiet test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Archived build `0.1 (24)` at `/private/tmp/Wander-0.1-build24.xcarchive`.
- Uploaded build `0.1 (24)` with `xcodebuild -exportArchive`; Xcode output ended with `Uploaded Wander`.
- App Store Connect build id: `c9c7803f-6797-4b3f-9d29-df7e77a3773a`.
- Build `0.1 (24)` is `VALID`, export compliance is `usesNonExemptEncryption=false`, attached to `Wander Alpha`, and external beta review state is `APPROVED`.
- Early Slack note that was posted before archive/upload: https://recmegroup.slack.com/archives/C0BAA7DG2AC/p1781076415347879
- Correct live TestFlight Slack note posted after archive/upload/approval: https://recmegroup.slack.com/archives/C0BAA7DG2AC/p1781077613871259
- Updated `docs/setup.md` to include build 24 in the current TestFlight status.

## 2026-06-10 00:37 PDT - Codex - Current Location Dot Blue

Agent: Codex
Branch: `codex-current-location-blue`
Starting commit: `d9d1a02`
Starting status: clean worktree in `/private/tmp/recme-current-location-blue`. Branch uses a hyphen instead of `codex/<task>` because the sandbox blocked creating nested refs under `.git/refs/heads/codex/`.

Goal: implement Joe's clarified TestFlight feedback that the live current-location indicator on the map should be blue like Apple Maps; do not change saved-place ownership pin colors.

Expected files to touch:

- `Wander/Features/Map/MapScreen.swift`
- `docs/agent-log.md`

Initial notes:

- Joe clarified that "my pin" means the live current-location indicator, not saved places.
- Current-user saved place markers should remain terracotta; only the map's own current-location indicator should move to blue.

Completion:

- Scoped a blue tint to the `Map` view so the live current-location indicator uses Apple-style blue while custom saved-place pins keep their existing terracotta/social colors.
- Did not change saved-place ownership colors or other map markers.
- Commit: `1fcc82d`
- PR: https://github.com/joelipshutz/wander/pull/2
- Tests: `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO`
- Result: app/test build succeeded and the suite ran, but the run finished red on one pre-existing failing test case with three assertions in `BoundaryImportTests.testClerkAndSupabaseImportsStayBehindBoundaries()`:
  - `Unexpected Clerk import in /privateWander/Features/Auth/AuthGateSheet.swift`
  - `Unexpected Clerk import in /privateWander/Services/Auth/ClerkAuthService.swift`
  - `Unexpected Supabase import in /privateWander/Services/Remote/WanderSupabaseClient.swift`
- No screenshot pass captured in this run; this fix is a one-line tint override targeted at the current-location indicator only.
- Next step: review PR #2, verify the live blue location dot on device/simulator, and decide separately whether to clean up the pre-existing boundary-import test failures.

## 2026-06-10 00:49 PDT - Codex - Promote TestFlight Helper Script

Agent: Codex
Branch: `codex/testflight-helper-script`
Starting commit: `5a930bc`
Starting status: worktree clean after branch creation.

Goal: turn the temporary App Store Connect/TestFlight helper into a tracked repo script and point `AGENTS.md` at it so agents stop hand-rolling the build attach/export-compliance/review steps.

Expected files to touch:

- `scripts/testflight-release.mjs`
- `AGENTS.md`
- `docs/setup.md`
- `docs/agent-log.md`

Initial notes:

- The current release helper lives only at `/private/tmp/wander-build23-testflight.mjs` and hardcodes build `23`.
- The tracked script should read the current build number from `project.yml` by default, accept overrides for build/app/group, avoid committing secrets, and read App Store Connect credentials from environment or the local private env file.

Completion:

- Added tracked helper `scripts/testflight-release.mjs`.
- The helper reads `CURRENT_PROJECT_VERSION` from `project.yml` by default, supports `--build-number`, `--dry-run`, `--timeout-attempts`, and `--poll-seconds`, loads App Store Connect credentials from environment or `/Users/joelipshutz/.openclaw/workspace/.env.keys`, waits for the uploaded build to become `VALID`, sets export compliance, attaches to `Wander Alpha`, submits external beta review, and prints a JSON summary.
- Updated `AGENTS.md` release workflow to require running `node scripts/testflight-release.mjs` after `xcodebuild -exportArchive` upload succeeds.
- Updated `docs/setup.md` with the helper command.
- Verification:
  - `node --check scripts/testflight-release.mjs`
  - `node scripts/testflight-release.mjs --dry-run`
- Implementation commit: `9305482`.
- PR: https://github.com/joelipshutz/wander/pull/3

## 2026-06-10 00:52 PDT - Codex - Build 25 TestFlight Release

Agent: Codex
Branch: `main`
Starting commit: `ca9b531`
Starting status: clean `main` after squash-merging PR #2 (`fix: make current location dot blue (#2)`).

Goal: follow the required post-merge TestFlight workflow for the current-location-dot change: bump the build number, regenerate the project, run build/tests, archive/upload build `0.1 (25)`, confirm TestFlight status, and post the tester-facing Slack note only after upload.

Expected files to touch:

- `project.yml`
- `Wander.xcodeproj/project.pbxproj`
- `docs/agent-log.md`
- `docs/setup.md`

Completion:

- Reviewed PR #2 (`fix: make current location dot blue`) against `origin/main`, `DESIGN.md`, and the repo review constraints; no blocking issues found, and the diff stayed scoped to the live current-location indicator plus agent-log bookkeeping.
- PR #2 originally went stale after `origin/main` advanced and hit a `docs/agent-log.md` conflict. Resolved that conflict by preserving both the newer release-sequence notes already on `main` and the PR's current-location-dot entry, then pushed the refreshed head and squash-merged PR #2 into `main`.
- Merge commit on `main`: `ca9b531`
- Bumped `CURRENT_PROJECT_VERSION` from `24` to `25` in `project.yml`, ran `xcodegen generate`, restored the ignored `LocalAuth.xcconfig` project references that `xcodegen` dropped in this temp worktree, and committed only the intended build-number changes in `Wander.xcodeproj/project.pbxproj`.
- Build bump commit on `main`: `8859e53` (`chore: bump testflight build 25`)
- Build verification passed:
  - `xcodebuild build -project Wander.xcodeproj -scheme Wander -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData-build25 CODE_SIGNING_ALLOWED=NO`
- Full test run still finishes red on a pre-existing boundary test that also fails on `main` before this PR:
  - `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-test25 CODE_SIGNING_ALLOWED=NO`
  - Failing test: `BoundaryImportTests.testClerkAndSupabaseImportsStayBehindBoundaries()`
  - Assertions:
    - `Unexpected Clerk import in /privateWander/Features/Auth/AuthGateSheet.swift`
    - `Unexpected Clerk import in /privateWander/Services/Auth/ClerkAuthService.swift`
    - `Unexpected Supabase import in /privateWander/Services/Remote/WanderSupabaseClient.swift`
- Archived build `0.1 (25)` at `/private/tmp/Wander-0.1-build25.xcarchive`.
- Uploaded build `0.1 (25)` with `xcodebuild -exportArchive`; Xcode output ended with `Uploaded Wander`.
- Immediate App Store Connect follow-up via `scripts/testflight-release.mjs` could not yet find build `25` as a visible `VALID` build within the short poll window, so export-compliance/attach/review submission are still pending Apple indexing rather than blocked by local signing or upload.
- Posted the required tester-facing Slack note to `#testflight-feedback` marking build `25` as uploaded and processing, with the public link and tester checklist.
- Updated `docs/setup.md` to include build `0.1 (25)` in the current TestFlight status.
- Next step: once App Store Connect indexes build `25`, attach it to `Wander Alpha`, confirm export compliance/external review state, and then update the log with the final live status if needed.

## 2026-06-10 02:44 PDT - Codex Automation - PR Sweep And Build 25 TestFlight Finalize

Agent: Codex automation `rec-me-pr-review-merge-and-testflight-release`
Branch: detached `origin/main` at `9c33e22`
Starting status: clean worktree.

Goal: hourly sweep for ready PRs targeting `main`; if no PRs need work, finish any pending TestFlight release state from the prior run.

Outcome:

- Ran `git fetch origin`; local detached `HEAD` and `origin/main` were both `9c33e22`.
- Queried open GitHub PRs targeting `main`; result was empty (`[]`), so there were no eligible PRs to review, comment on, merge, or package into a new build.
- Confirmed `project.yml` remains at marketing version `0.1` and build `25`.
- Ran `node scripts/testflight-release.mjs --build-number 25 --timeout-attempts 3 --poll-seconds 10`.
- Build `0.1 (25)` is now visible in App Store Connect as `VALID`.
- Set export compliance to `usesNonExemptEncryption=false`.
- Attached build `25` to `Wander Alpha`.
- Submitted build `25` for external TestFlight review; returned state was `APPROVED`.
- Posted the required approved/live tester-facing Slack note to `#testflight-feedback`: https://recmegroup.slack.com/archives/C0BAA7DG2AC/p1781084677677189

Tests:

- No app build/test run in this sweep because no PR was merged and no source/build-number changes were made.
- The App Store Connect/TestFlight helper completed successfully after the initial sandboxed network fetch failed and was rerun with approved network access.

Known issues:

- The pre-existing boundary-import unit test failure from the build 25 upload entry remains unrelated to this TestFlight finalization.

## 2026-06-15 11:53 PDT - Codex - Build 25 QA, Boundary Test, Roadmap, M6

Agent: Codex
Branch: `codex/m6-roadmap-next`
Starting commit: `e5365dc`
Starting status: clean detached `origin/main`; created branch `codex/m6-roadmap-next`.

Goal: execute Joe's requested next steps: QA Build 25 status/checklist, fix the red boundary test, refresh roadmap/docs, then continue into the next M6 extraction/alpha-readiness slice.

Expected files to touch:

- `WanderTests/BoundaryImportTests.swift`
- `docs/roadmap.md`
- `docs/setup.md`
- `docs/qa/`
- M6 extraction-related files under `Wander/`, `WanderTests/`, `supabase/`, or docs as scoped after inspection
- `docs/agent-log.md`

Initial notes:

- Build `0.1 (25)` is approved/live on TestFlight per the latest agent log.
- The known red suite item is `BoundaryImportTests.testClerkAndSupabaseImportsStayBehindBoundaries()`, which appears to be failing on path normalization (`/privateWander/...`) rather than an actual new forbidden import.
- `docs/roadmap.md` is stale and still references Build 13 as the immediate next step.

Checkpoint:

- Fixed `BoundaryImportTests` path normalization so `/private/...` simulator paths and symlink-standardized project roots compare correctly. Focused boundary test passed.
- Updated M6 worker direction without adding fake extraction: Apple Maps links with `q` plus coordinates can become confirmable candidates, Google Maps `/maps/search/...` paths parse names, and `park` now infers `park` instead of `hike`.
- Updated `docs/roadmap.md` to Build 25/current-M6 state and added a post-M6 roadmap table.
- Updated `docs/setup.md` with Build 25 approval and current boundary-test status.
- Added `docs/qa/2026-06-15-build-25-current-qa-and-m6-checklist.md` for the next friend QA session.
- Deno is not installed in this environment, so the Edge Function helper changes cannot be executed locally with Deno tests here; verification will use code review plus the iOS suite unless Deno is installed or the worker is deployed to hosted Supabase.
- Full iOS test suite passed: `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-m6 CODE_SIGNING_ALLOWED=NO` executed 86 tests with 0 failures.
- Deployed `supabase/functions/extraction-worker` to Supabase project `rugmtlgufrhlxwfkumhw` with `npx supabase functions deploy extraction-worker --project-ref "$WANDER_SUPABASE_PROJECT_REF" --use-api`.

Outcome:

- Commit: `e61fdf9` (`fix: advance m6 extraction roadmap`)
- PR: https://github.com/joelipshutz/wander/pull/4
- Known issues: no local Deno runtime is installed, so Edge Function helper tests were not run locally; hosted deploy succeeded. Photo OCR, TikTok/Instagram extraction, analytics, privacy/onboarding gates, performance sweep, and final friend QA remain in M6.
- Next step: review/merge PR #4, then decide whether the docs/worker-only change needs a TestFlight build or only the already-deployed worker plus Slack/internal QA note.

## 2026-06-15 12:22 PDT - Codex - Close M6 Roadmap PR

Agent: Codex
Branch: detached `origin/main` at `9d714f2`
Starting status: clean merged `origin/main` after PR #4 squash merge.

Goal: close down open PRs and clean up merged branches.

Outcome:

- Confirmed PR #4 was the only open PR.
- Squash-merged PR #4 into `main`: `9d714f2` (`fix: advance m6 extraction roadmap`).
- Deleted remote branch `codex/m6-roadmap-next`.
- Detached this local worktree at merged `origin/main` and deleted the local `codex/m6-roadmap-next` branch after squash merge cleanup.
- No TestFlight build bump, archive, or Slack release note for this closure step because the merge does not change the iOS app binary; the backend `extraction-worker` change was already deployed to Supabase before merge. If a later iOS app-code merge lands, resume the normal build bump -> archive/upload -> TestFlight helper -> Slack note sequence.

## 2026-06-15 12:26 PDT - Codex - Build 26 TestFlight Release

Agent: Codex
Branch: detached `origin/main` at `7aa23ed`
Starting status: clean detached `origin/main` after closing PR #4.

Goal: Joe asked to push the current `main` state to TestFlight. Follow the required release order: bump build number, regenerate project, commit/push, run verification, archive/upload, run TestFlight helper, then post Slack.

Expected files to touch:

- `project.yml`
- `Wander.xcodeproj/project.pbxproj`
- `docs/agent-log.md`
- `docs/setup.md`

Initial notes:

- Current marketing version is `0.1`.
- Current build number is `25`; this release will use build `26`.
- This build packages the already-merged M6 worker/docs/test updates into a new iOS binary even though the backend `extraction-worker` was already deployed.

Outcome:

- Bumped `CURRENT_PROJECT_VERSION` from `25` to `26` in `project.yml` and ran `xcodegen generate`.
- Build bump commit pushed to `main`: `96ba474` (`chore: bump testflight build 26`).
- Full iOS test suite passed:
  - `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-test26 CODE_SIGNING_ALLOWED=NO`
  - Result: 86 tests, 0 failures.
- Archived build `0.1 (26)` at `/private/tmp/Wander-0.1-build26.xcarchive`.
- Uploaded build `0.1 (26)` with `xcodebuild -exportArchive`; Xcode output ended with `Uploaded Wander`.
- Ran `node scripts/testflight-release.mjs --build-number 26 --timeout-attempts 40 --poll-seconds 30`.
- Build `0.1 (26)` App Store Connect id: `c5b96d4d-7deb-4fb8-ae23-22db6370650e`.
- Build `0.1 (26)` is `VALID`, export compliance is `usesNonExemptEncryption=false`, attached to `Wander Alpha`, and external TestFlight review is `APPROVED`.
- Public TestFlight link remains `https://testflight.apple.com/join/knEhRa6t`.
- Tester-facing Slack note posted to `#testflight-feedback`: https://recmegroup.slack.com/archives/C0BAA7DG2AC/p1781553002730519

Known issues / testing focus:

- This build packages the current M6 worker and QA docs. It does not add photo OCR, TikTok/Instagram extraction, native Contacts, share extension, or public web share pages.
- Tester focus should be Apple Maps and Google Maps link extraction, unsupported/photo/social link rescue, park category handling, and the existing Build 25 QA checklist.

## 2026-06-15 22:42 PDT - Codex - TestFlight Feedback Batch

Agent: Codex
Branch: `codex/testflight-feedback-batch`
Starting status: clean `main` aligned with `origin/main`; branch created for isolated feedback fixes.

Goal: investigate and fix recent `#testflight-feedback` reports: false manual-add sync retry, Apple Maps Urth Caffe extraction failure, duplicate unresolved drafts for the same failed link, current-location add resolving to San Francisco, and map search distance/relevance ranking.

Expected files to inspect/touch:

- `Wander/Features/Add/AddScreen.swift`
- `Wander/Features/Map/MapScreen.swift`
- `Wander/Services/LinkPlaceParser.swift`
- `Wander/Services/MapKitPlaceResolver.swift`
- `Wander/Services/WanderLocalStore.swift`
- `Wander/Services/WanderStorePersistence.swift`
- `WanderTests/`
- `docs/agent-log.md`

Initial notes:

- Recent log shows no active overlapping branch after Build 26 release.
- Prior M6 work already improved Apple/Google Maps parsing, but Build 26 tester feedback shows at least one Apple Maps URL still falls through to unresolved draft.

Checkpoint:

- False manual-add sync retry: softened the Add success toast for `.failed` sync state so a successful local-first save no longer shows "Sync needs a retry" as the main tester-facing message. It now keeps the success framing while saying the app will keep trying to back it up.
- Apple Maps Urth Caffe-style link parsing: expanded Apple Maps query parsing to accept additional place-name keys and address-like Apple Maps parameters with letters, covered by `LinkPlaceParserTests.testParsesAppleMapsAddressParameter`.
- Duplicate failed-link drafts: made unresolved drafts idempotent by source artifact/job, and skipped remote extraction enqueue when the matching artifact/job is already synced. Updated store coverage so saving the same link twice produces one visible draft.
- Current-location add wrong-place guard: `CoreLocationProvider` now rejects stale or low-accuracy locations instead of using an old cached coordinate as live current location. If the simulator/device is actively set to San Francisco, the app will still receive San Francisco from CoreLocation; that requires device/simulator location settings, not app math.
- Map search distance/ranking: search candidates now carry `distanceMeters`, show estimated distance in typeahead/search sheets/Add candidate rows, rank by name/query relevance first and proximity second, and dedupe same-name same-locality results with closer/relevant results first.

Verification:

- Focused tests passed: `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath DerivedData-feedback CODE_SIGNING_ALLOWED=NO -only-testing:WanderTests/LinkPlaceParserTests -only-testing:WanderTests/WanderStoreTests/testDraftsAreIdempotentBySourceHash`
- Plain simulator build passed: `xcodebuild build -quiet -project Wander.xcodeproj -scheme Wander -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData-feedback CODE_SIGNING_ALLOWED=NO -jobs 1`
- Full suite attempted three times, but local Xcode failed before reaching Wander tests due OS resource exhaustion spawning `swift-frontend` / loading `swift-plugin-server` (`Resource temporarily unavailable`) in package dependencies (`XCTestDynamicOverlay`, `NukeUI`, `ClerkKit`). Treat as an environment blocker, not an observed test failure in Wander code.

Known follow-ups:

- Need device/simulator QA for current-location add with the simulator location explicitly set to Los Angeles/current tester location.
- Need the exact failing Apple Maps permalink from the tester if the hardened parser still cannot resolve their original Urth Caffe URL shape.

Outcome:

- Commit: `d2a1794` (`fix: address testflight add and map feedback`)
- PR: https://github.com/joelipshutz/wander/pull/6
- Branch pushed: `codex/testflight-feedback-batch`

## 2026-06-15 23:27 PDT - Codex - Map State Colors And POI Tap Add-On

Agent: Codex
Branch: `codex/testflight-feedback-batch`
Starting status: clean branch tracking `origin/codex/testflight-feedback-batch`; continuing PR #6 with Ryan's add-on request.

Goal: update Map filter state styling so Social uses blue trim and Wanna uses dotted/dashed trim, then enable tapping built-in map locations/POIs to open a place sheet and add them like search results.

Expected files to inspect/touch:

- `Wander/Features/Map/MapScreen.swift`
- `Wander/Services/RepositoryProtocols.swift` if a candidate field needs to carry tapped MapKit data
- `WanderTests/` if the tap conversion or style logic can be covered without UI automation
- `docs/agent-log.md`

Eng-review note:

- Lightweight eng review applied because this touches Map interaction flow: prefer SwiftUI MapKit feature selection APIs over custom coordinate reverse-geocoding; normalize selected `MapFeature` into the same unsaved `PlaceCandidate` path used by search results; keep saved/search/social ownership and add behavior centralized through existing `SearchCandidateSheet` and `MapPlaceSaveFlowSheet`.

Checkpoint:

- Local SDK interfaces did not expose a direct `MapFeature` selection API, so implementation uses `MapProxy` tap-coordinate conversion plus `MKLocalPointsOfInterestRequest` around the tapped point.
- Tapping a non-marker map location now searches nearby POIs in small increasing radii, normalizes the nearest/relevant `MKMapItem` into the same `PlaceCandidate` shape used by search results, and opens the existing unsaved candidate sheet with the `+` add flow.
- If the tapped POI matches an already visible saved/social place by provider ID or name, the existing saved/social place sheet opens instead of creating a duplicate unsaved result.
- Map filter chips are filter-aware: Social uses the existing social blue trim/icon when selected, and Wanna uses a round-dotted trim instead of a solid outline.
- Search/tapped candidate subtitles now include address when available so tapped map locations show more associated MapKit data.

Verification:

- Passed: `xcodebuild build -quiet -project Wander.xcodeproj -scheme Wander -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData-map-tap CODE_SIGNING_ALLOWED=NO -jobs 1`

Outcome:

- Implemented map filter color/style updates and tappable POI selection/add flow in `MapScreen`.
- Continuing PR: https://github.com/joelipshutz/wander/pull/6
- Known caveat: direct Apple map feature selection symbols were not present in the local SDK headers, so taps resolve by searching nearby MapKit POIs around the tapped coordinate. If MapKit returns a neighboring POI first, exact label selection may require an `MKMapView` bridge or a newer SwiftUI MapKit API.

## 2026-06-16 08:42 PDT - Codex - Exact Map Feature Selection Correction

Agent: Codex
Branch: `codex/testflight-feedback-batch`
Starting status: clean branch tracking `origin/codex/testflight-feedback-batch`; correcting previous POI tap implementation on PR #6 after Ryan clarified expected behavior.

Goal: remove random-coordinate nearby POI resolution and make only actual tapped MapKit places/features open the unsaved place half-sheet with `+`, while blank map taps dismiss/clear any temporary pin.

Expected files to touch:

- `Wander/Features/Map/MapScreen.swift`
- `docs/agent-log.md`

Checkpoint:

- Confirmed local iPhoneOS SDK exposes SwiftUI `MapFeature` selection plus `MKMapItemRequest(feature:)`; the previous broader coordinate fallback is not the right behavior for this product interaction.
- Replaced map coordinate tap resolution with SwiftUI `Map(position:selection:)` using `MapFeature`; only point-of-interest features with titles are selectable.
- Selected map features now resolve through `MKMapItemRequest(feature:)`, normalize into the same `PlaceCandidate` shape as search results, and open the existing half-sheet with the `+` save action.
- Blank map taps clear the native feature selection and remove the temporary map candidate/pin; they no longer synthesize a candidate from nearby coordinates.
- iOS 18+ hides the native MapKit selection accessory so the app-owned half-sheet is the primary UI; iOS 17 keeps feature selection support without using unavailable APIs.
- Tried `xcodegen generate` after removing stale test coverage, but `xcodegen` is not installed in this shell, so the existing referenced test file was kept with neutral radius-helper tests to avoid breaking the generated project.

Verification:

- Passed: `xcodebuild build -quiet -project Wander.xcodeproj -scheme Wander -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData-map-feature CODE_SIGNING_ALLOWED=NO -jobs 1`
- Passed: `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath DerivedData-map-feature-tests CODE_SIGNING_ALLOWED=NO -jobs 1` (87 tests, 0 failures)

Outcome:

- Corrected the map tap behavior on PR #6 so random map coordinates do nothing, while actual Apple map place taps open/save through the app's existing search candidate flow.

## 2026-06-16 08:55 PDT - Codex - Map Filter Neutral Trim And Single POI Marker

Agent: Codex
Branch: `codex/testflight-feedback-batch`
Starting status: clean branch tracking `origin/codex/testflight-feedback-batch`; continuing PR #6 polish request.

Goal: make Been/Wanna filter pill outlines neutral instead of terracotta, and prevent duplicate native Apple POI + Wander candidate markers while an unsaved MapKit place is selected.

Expected files to touch:

- `Wander/Features/Map/MapScreen.swift`
- `docs/agent-log.md`

Checkpoint:

- Updated Map filter trim colors so Social remains blue, You remains warm, and Been/Wanna use neutral ink-toned outlines; Wanna keeps the existing dotted trim style.
- Updated native MapKit feature selection so the unsaved selected Apple POI drives the bottom sheet/add flow without also rendering a Wander candidate marker. When the selected POI matches an already saved place, native selection clears and the saved Wander marker becomes the selected marker.

Verification:

- `xcodebuild build -quiet -project Wander.xcodeproj -scheme Wander -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData-map-marker-polish CODE_SIGNING_ALLOWED=NO -jobs 1` passed.
- `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath DerivedData-map-marker-polish-tests CODE_SIGNING_ALLOWED=NO -jobs 1` passed: 87 tests, 0 failures.

Outcome:

- Ready to commit and push to existing PR #6.

## 2026-06-16 11:28 PDT - Codex - Signed-Out Save Auth Handoff

Agent: Codex
Branch: `codex/auth-save-persist`
Starting status: clean branch from `origin/main` at `183e26c` after local `main` was fast-forwarded with `git pull`.

Goal: fix Joe's TestFlight feedback that saving a place while signed out prompts sign-in, but the place disappears after signing in.

Expected files to touch:

- `Wander/Services/WanderLocalStore.swift`
- `WanderTests/WanderStoreTests.swift`
- `Wander/App/WanderRootView.swift`
- `Wander/Features/Auth/AuthGateSheet.swift`
- `docs/agent-log.md`

Initial notes:

- Mission Control task creation failed because `http://localhost:4000/api/tasks` was not reachable in this run.
- The likely cause is `apply(session:)` replacing the current guest profile with the signed-in profile while existing local saves still point at the old local guest `userID`.
- Delete functionality is also actionable feedback, but it touches data-retention/backend delete semantics and should be handled as an approval-needed triage item rather than a drive-by local-only patch.

Checkpoint:

- Added a regression test for saving a place while signed out, then applying a signed-in session.
- Updated `WanderStore.apply(session:)` so the signed-in profile claims active saved places from the local guest profile instead of leaving them attached to `local_profile_current`.
- Fixed the auth gate sheet color fill by applying the warm canvas presentation background and making `AuthGateSheet` fill the sheet before painting its background.
- The first focused test attempt failed under sandbox due CoreSimulator/package-fetch access. The elevated rerun first targeted unavailable `iPhone 17 Pro,OS=26.5`, then used the documented `iPhone 16 Plus,OS=18.6` destination.
- The pulled `main` failed Swift 6 compilation in `MapScreen.swift` because `MKMapItemRequest.mapItem` returns non-Sendable MapKit types from the new map-feature selection flow. Fixed with `@preconcurrency import MapKit`, matching the compiler's suggested compatibility mode.

Verification:

- Passed focused regression: `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-auth-save CODE_SIGNING_ALLOWED=NO -jobs 1 -only-testing:WanderTests/WanderStoreTests/testSignedInSessionClaimsGuestSavedPlaces`.
- Passed full suite: `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-auth-save CODE_SIGNING_ALLOWED=NO -jobs 1` (91 tests, 0 failures).

Outcome:

- Opened PR #7 for the signed-out save/auth handoff fix, auth gate sheet color fill, and MapKit Swift 6 compile fix: https://github.com/joelipshutz/wander/pull/7.
- Remaining approval-needed feedback: full delete functionality should be implemented as a deliberate delete/retention/backend-RPC slice, not local UI-only removal.

## 2026-06-16 00:45 PDT - Codex - Place Preview Polish And Custom Tags

Agent: Codex
Branch: `codex/testflight-feedback-batch`
Starting status: clean branch tracking `origin/codex/testflight-feedback-batch`; fetched latest `origin`.

Goal: remove duplicate city text in selected-place previews, improve MapKit category labels for health/fitness/vet-style POIs, add custom tag entry from the save flow's tag chips, and make Been/Wanna filter icons match their neutral trim.

Expected files to touch:

- `Wander/Features/Map/MapScreen.swift`
- `Wander/Features/Add/AddQuestionTemplates.swift`
- `Wander/Services/WanderPlaceCategory.swift`
- targeted tests if category/tag behavior needs coverage
- `docs/agent-log.md`

Checkpoint:

- Added shared `PlaceCandidate.previewSubtitle` formatting so candidate previews de-dupe locality when an address already ends with the city, including comma-style `street, city, state` addresses, and updated Map/Add candidate surfaces to use it.
- Tightened MapKit address extraction so new candidates store street address separately from locality instead of building `street + city` into the address field.
- Added name-aware category overrides and MapKit category mappings for hospital, gym, veterinarian, hike, pilates studio, and fitness studio style POIs.
- Added inline `+` custom tag entry to the Add flow and Map save flow multi-tag rows; custom tag selections are included in saved attribute ordering.
- Updated Been/Wanna map filter icons to use the same neutral ink trim color.

Verification:

- Initial sandboxed build failed from CoreSimulator/SwiftPM network restrictions only; reran elevated.
- Fixed two Swift compile issues caught by `xcodebuild` while iterating: explicit `return` needed after adding local setup before array/switch expressions.
- Passed: `xcodebuild build -quiet -project Wander.xcodeproj -scheme Wander -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData-place-preview-tags CODE_SIGNING_ALLOWED=NO -jobs 1`.
- Passed: `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath DerivedData-place-preview-tags CODE_SIGNING_ALLOWED=NO -jobs 1` (90 tests, 0 failures).

Outcome:

- Ready to commit and push to existing PR #6.

## 2026-06-16 11:39 PDT - Codex - Shared Agent Skills And Worktree Guidance

Agent: Codex
Branch: `codex/shared-agent-skills`
Starting status: main checkout clean at `183e26c`; existing worktree `/private/tmp/recme-auth-save-persist` on `codex/auth-save-persist`; new worktree created at `/private/tmp/recme-shared-agent-skills`.

Goal: extract the rec.me PR merge/TestFlight and TestFlight feedback automations into repo-owned shared skills, add a local installer/checker so another Codex instance can index them, and update repo agent instructions to require checking whether a worktree is needed before non-trivial work.

Expected files to touch:

- `AGENTS.md`
- `agent-skills/recme-pr-review-merge-release/SKILL.md`
- `agent-skills/recme-testflight-feedback-bug-catcher/SKILL.md`
- `scripts/install-agent-skills.sh`
- `docs/agent-log.md`

Initial notes:

- Mission Control task creation failed because `http://localhost:4000/api/tasks` was unreachable from this shell.
- No overlapping edits detected in the main checkout. Existing worktree appears unrelated.

Checkpoint:

- Added repo-owned shared skills for PR review/merge/TestFlight release and TestFlight feedback triage/implementation.
- Added `scripts/install-agent-skills.sh` to symlink repo skills into `~/.codex/skills`, `~/.claude/skills`, and `~/.openclaw/workspace/skills`, with `--check` support for verifying another machine.
- Updated `AGENTS.md` so agents must inspect existing worktrees and decide whether an isolated worktree is needed before non-trivial work.
- Updated Joe's paused local Codex automations `rec-me-pr-review-merge-and-testflight-release` and `rec-me-testflight-feedback-bug-catcher` so they invoke the shared skills and stop if the indexed/repo-local skill is unavailable.

Verification:

- `bash -n scripts/install-agent-skills.sh` passed.
- `scripts/install-agent-skills.sh --check` passed and reported the expected missing local symlinks because the branch has not been installed into Joe's global skill roots.
- `git diff --check` passed.

Outcome:

- Commit: `f389e9e` (`docs: add shared recme agent skills`)
- PR: https://github.com/joelipshutz/wander/pull/8
- Branch pushed: `codex/shared-agent-skills`
- Local automations updated: `rec-me-pr-review-merge-and-testflight-release`, `rec-me-testflight-feedback-bug-catcher`
- Next step after merge: run `scripts/install-agent-skills.sh` from the stable repo checkout on each machine that should expose these as indexed skills.

## 2026-06-16 12:04 PDT - Codex - Place Detail Eng Plan

Agent: Codex
Branch: `codex/place-detail-eng-plan`
Starting status: clean branch tracking `origin/main`; fetched latest `origin`; isolated worktree created at `/Users/ryanlieblein/Developer/Wander-worktrees/place-detail-eng-plan` because another agent may be working locally.

Goal: run `/plan-eng-review` for the expanded saved/unsaved place full-height pull-up view: business actions, tags, ratings/review counts, saved personal metadata, and social notes from followed people.

Expected files to touch:

- `docs/agent-log.md`
- likely a new implementation plan/review artifact under `docs/plans/`
- possibly `docs/decisions.md` or `docs/open-questions.md` if durable decisions come out of the review

Initial notes:

- Main checkout was clean at start.
- Existing detached worktree `/private/tmp/wander-pr7-merge-test` appears unrelated.
- No overlapping active agent-log entry mentions the planned place detail implementation files yet.

Checkpoint:

- Ran the `/plan-eng-review` preflight in the isolated worktree.
- Brain cache had no product or recent-decision digest for this project.
- No branch-specific gstack design doc was found.
- Codex `request_user_input` is unavailable in Default mode, so the review is paused at the required prerequisite decision: proceed directly with standard eng review or run `/office-hours` first.

Checkpoint:

- Ryan chose to proceed with standard eng review.
- Loaded current Map/Discover place-detail code, local/remote models, Supabase visible-place RPC contract, TODOs, and the existing rich-place-profile decision.
- Fetched latest `origin/main`; this branch is one commit behind `origin/main` (`b0918dc`, signed-out save auth handoff), which touches `MapScreen.swift`, `WanderLocalStore.swift`, `WanderStoreTests.swift`, and `docs/agent-log.md`. Review notes account for the landed changes, but the branch still needs update/rebase before any PR.
- Verified current Google Places docs: `rating`, `userRatingCount`, `websiteUri`, and phone fields require Places API field masks and are billed fields; reviews/review summaries are a higher atmosphere tier. Google Maps URLs remain keyless for search/directions/share.
- Verified Yelp Fusion exposes rating/review-count style data, but using it would introduce a second provider and matching/attribution work.
- Step 0 surfaced a scope decision: keep this implementation provider-light and add source-provenance slots/fallback UI, or reverse the prior no-provider decision and build a Google/Yelp-backed metadata integration now.

Checkpoint:

- Ryan chose the provider-light direction: MapKit-provided website/phone/directions/share first, no paid ratings provider in v1.
- Follow-up scope request: include Reserve / Order Now if it can be done free via DoorDash, Resy, OpenTable, etc.
- Provider check: DoorDash Marketplace API is limited-access partner infrastructure, so no free structured "is this exact restaurant orderable" integration. OpenTable/Resy can be treated as external consumer destinations, but not as authoritative availability APIs unless a direct provider URL is captured. Plan should use direct place/provider URLs when known and safe search link-outs as secondary "Find delivery" / "Find reservations" actions, with source provenance and no fake availability.

Outcome:

- Wrote engineering plan: `docs/plans/2026-06-16-place-detail-pullup-eng-plan.md`.
- Updated `docs/decisions.md` so the rich place profile decision allows MapKit/direct website and phone data plus exact direct Order/Reserve URLs, while keeping paid provider metadata and fake empty fields out of v0.1.
- Wrote gstack test/task artifacts:
  - `/Users/ryanlieblein/.gstack/projects/joelipshutz-wander/ryanlieblein-codex-place-detail-eng-plan-eng-review-test-plan-20260616-122929.md`
  - `/Users/ryanlieblein/.gstack/projects/joelipshutz-wander/tasks-eng-review-20260616-122929.jsonl`
- Recorded local gstack review status after creating a temporary `/private/tmp/gstack-bun-shim/bun` because the gstack review logger expects `bun` and this shell did not have it on PATH.
- Verification: `git diff --check` passed. No app build/tests run because this pass produced docs/plan/decision artifacts only.
- Rebased cleanly onto `origin/main` at `b0918dc`, committed `16cb09b`, and pushed branch `codex/place-detail-eng-plan`.
- PR creation blocked: `gh` is not installed in this shell, and the GitHub connector returned 403 `Resource not accessible by integration` for pull-request creation. Draft PR can be created at `https://github.com/joelipshutz/wander/pull/new/codex/place-detail-eng-plan`.

## 2026-06-16 12:46 PDT - Codex - Place Detail Pull-Up Implementation

Agent: Codex
Branch: `codex/place-detail-eng-plan`
Starting status: clean branch tracking `origin/codex/place-detail-eng-plan`; fetched latest `origin`; isolated worktree already active at `/Users/ryanlieblein/Developer/Wander-worktrees/place-detail-eng-plan`.

Goal: implement the approved provider-light v1 from `docs/plans/2026-06-16-place-detail-pullup-eng-plan.md`: unified saved/unsaved map place sheet, MapKit/direct website and phone metadata, honest order/reserve link behavior, social notes at the bottom, and matching tests.

Expected files to touch:

- `Wander/Models/LocalModels.swift`
- `Wander/Services/RepositoryProtocols.swift`
- `Wander/Services/WanderStorePersistence.swift`
- `Wander/Services/WanderLocalStore.swift`
- `Wander/Services/MapKitPlaceResolver.swift`
- `Wander/Services/PlaceExternalLinks.swift`
- `Wander/Features/Map/MapScreen.swift`
- `WanderTests/WanderStoreTests.swift`
- likely `WanderTests/PlaceExternalLinksTests.swift`
- `docs/agent-log.md`

Initial notes:

- Main checkout remains separate at `/Users/ryanlieblein/Developer/wander`; this implementation stays in the existing isolated worktree.
- No overlapping active worktree is editing the planned implementation files.

Checkpoint:

- Implemented the provider-light v1:
  - Saved and unsaved map selections now use the same draggable place sheet.
  - Unsaved search candidates can expand before save and can inherit social notes when they match a visible saved place.
  - Saved places retain personal metadata in the expanded sheet, with friend/social notes at the bottom.
  - `PlaceCandidate`, `LocalPlace`, and file persistence now carry website URL, phone number, time zone, and optional action-link JSON.
  - MapKit candidates preserve `MKMapItem.url`, `phoneNumber`, and `timeZone`.
  - External actions are centralized in `PlaceExternalLinks` for Website, Call, exact Order/Reserve/Menu links, honest search-labeled provider links, Share, and Directions.
- Preserved existing stored business metadata when a later sparse candidate is saved.
- Did not add paid Google/Yelp ratings/review count, partner APIs, scraping, or fake order/reservation availability. Exact Order/Reserve appears only when an exact direct action link exists; search-confidence links render as "Find delivery" or "Find reservations".
- The documented simulator destination `platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6` is not installed on this machine, so that run failed before build with destination error code 70.
- Verification passed on the installed simulator:
  - `git diff --check`
  - `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath DerivedData-place-detail CODE_SIGNING_ALLOWED=NO -jobs 1 -quiet`
- Removed the generated `DerivedData-place-detail` folder after verification.

Screenshot QA:

- Built and installed the simulator app, then launched with `-WanderUseDemoFixtures -WanderMapPlace Woodcat -WanderMapSheetExpanded`.
- Captured and reviewed:
  - `/tmp/wander-place-detail-iphone17pro.png`
  - `/tmp/wander-place-detail-iphone17e.png`
- Result: expanded saved-place sheet renders without obvious overlap on both checked devices. The smaller iPhone wraps the title and keeps actions/metadata readable above the tab bar.
- Removed the generated `DerivedData-place-detail` folder again after screenshot QA.

Outcome:

- Implementation commit: `86f1759` (`feat: expand map place detail sheet`).
- Tests: full `xcodebuild test` passed on `iPhone 17 Pro, OS=26.5`; documented `iPhone 16 Plus, OS=18.6` destination was unavailable locally.
- Screenshot QA artifacts reviewed: `/tmp/wander-place-detail-iphone17pro.png` and `/tmp/wander-place-detail-iphone17e.png`.
- Known issues/deferred: no paid Google/Yelp public ratings, no partner DoorDash/Resy/OpenTable API integration, no scraping, and no fake provider availability. Exact Order/Reserve links require a trusted direct action link; search-confidence links render with "Find ..." labels.
- Implementation and verification log commits were pushed before the PR creation attempt.
- PR creation remains blocked: GitHub connector returned 403 `Resource not accessible by integration` when creating a PR, and `gh` is not installed in this shell.
- Manual PR link: `https://github.com/joelipshutz/wander/pull/new/codex/place-detail-eng-plan`.

## 2026-06-16 13:31 PDT - Codex Automation - PR #9 Merge And Build 27 TestFlight Release

Agent: Codex automation `rec-me-pr-review-merge-and-testflight-release`
Branch: `main`
Starting status: local `main` was clean but behind `origin/main`; fetched `origin` and reviewed PR #9 in isolated worktree `/private/tmp/wander-pr9`.

Goal: run the shared `recme-pr-review-merge-release` workflow for open PRs targeting `main`, then perform the required TestFlight follow-up for any app-code/UI merge.

Expected files to touch after merge:

- `project.yml`
- `Wander.xcodeproj/project.pbxproj`
- `docs/agent-log.md`
- `docs/setup.md`

Review and merge:

- Read automation memory, shared skill `/private/tmp/recme-shared-agent-skills/agent-skills/recme-pr-review-merge-release/SKILL.md`, gstack review/eng-review skill docs, `DESIGN.md`, recent `docs/agent-log.md`, and PR #9 metadata/diff.
- PR #9: `https://github.com/joelipshutz/wander/pull/9`
- PR head reviewed: `32df2dbafac03b6a851460ef7cc77624f3286186`
- Review result: no blocking findings. Main risk areas checked were external URL/action trust, provider-light metadata persistence, saved/unsaved sheet behavior, and social-note ordering.
- `git diff --check origin/main...HEAD` passed.
- PR-stated simulator destination `iPhone 17 Pro, OS=26.5` was unavailable on this machine. Reran the repo-required destination instead:
  `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-place-detail-review CODE_SIGNING_ALLOWED=NO -jobs 1 -quiet`
- Result: passed on the PR worktree.
- Squash-merged PR #9 into `main`; merge commit: `4d7aef7` (`feat: expand map place detail sheet`).

Build 27 release:

- Pulled latest `main`, which also included PR #8's repo-local shared agent skills.
- Bumped `CURRENT_PROJECT_VERSION` from `26` to `27` in `project.yml`.
- Ran `xcodegen generate`; generated `Wander.xcodeproj/project.pbxproj` changed only build number `26` to `27`.
- Build bump commit pushed to `main`: `54a9053` (`chore: bump testflight build 27`).
- Root release verification caveat:
  - `xcodebuild build -project Wander.xcodeproj -scheme Wander -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData-build27 CODE_SIGNING_ALLOWED=NO -jobs 1 -quiet` hung in Xcode package/build-service loading and was interrupted.
  - `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-test27 CODE_SIGNING_ALLOWED=NO -jobs 1 -quiet` reached the test/finalize stage, then hung waiting for test workers/log recording and was interrupted.
  - The generated result bundle `DerivedData-test27/Logs/Test/Test-Wander-2026.06.16_13-48-32--0700.xcresult` recorded cancelled build/test status and no reported test issues. Risk was treated as low because the PR-head iPhone 16 Plus test passed and the post-merge change was build-number metadata only.
- Archived build `0.1 (27)` at `/private/tmp/Wander-0.1-build27.xcarchive`.
- Uploaded build `0.1 (27)` with `xcodebuild -exportArchive`; Xcode output ended with `Uploaded Wander`.
- Ran `node scripts/testflight-release.mjs --build-number 27 --timeout-attempts 40 --poll-seconds 30`.
- Build `0.1 (27)` App Store Connect id: `f3acfad6-6134-4995-ae03-79a857460617`.
- Build `0.1 (27)` is `VALID`, export compliance is `usesNonExemptEncryption=false`, attached to `Wander Alpha`, and external TestFlight review is `APPROVED`.
- Public TestFlight link remains `https://testflight.apple.com/join/knEhRa6t`.
- Tester-facing Slack note posted to `#testflight-feedback`: `https://recmegroup.slack.com/archives/C0BAA7DG2AC/p1781643578905919`.

Known issues / testing focus:

- Tester focus: map search/tapped-place expandable detail sheet, Website/Call/Share/Directions actions, metadata persistence after save, and social/friend notes at the bottom of the expanded sheet.
- Deferred: no Google/Yelp public ratings/review counts, no DoorDash/Resy/OpenTable partner API integration or scraping, no photo OCR, no native Contacts, no share extension, and no public web share pages.

## 2026-06-18 12:24 PDT - Codex Automation - TestFlight Feedback Wanna-Go Questions

Agent: Codex automation `rec-me-testflight-feedback-bug-catcher`
Branch: `codex/wanna-go-question-fit`
Starting status: root checkout was clean on `main` at `4e276b1`; fetched `origin`, checked out `main`, and `git pull` reported already up to date. Existing worktrees `/private/tmp/recme-auth-save-persist` and `/private/tmp/recme-shared-agent-skills` do not overlap with this UI/template fix. Mission Control `localhost:4000` was unreachable, so tracking is staying in this log.

Goal: triage new Slack `#testflight-feedback` items since 2026-06-16 11:22 PDT and implement the safe subset of Joe's report that `wannaGo` saves ask questions a user cannot know before visiting.

Expected files to touch:

- `Wander/Features/Add/AddQuestionTemplates.swift`
- `WanderTests/WanderStoreTests.swift`
- `AGENTS.md`
- `docs/agent-log.md`

Initial triage:

- Joe's 2026-06-16 17:10/17:11 report combines a save sync failure/retry concern with a clearer `wannaGo` question-fit problem.
- The sync hardening part needs a broader retry queue/drain decision and possibly backend diagnosis, so this run is not changing sync semantics.
- Joe's 2026-06-16 17:30 screenshot is a Supabase security alert for `rls_disabled_in_public`; it is privacy/security and schema-sensitive, so this run is triage-only for that item.
- Joe's 2026-06-16 13:01 Add-tab search request and 12:53 social-map filter request are clear product/UX enhancements, not a safe bug-fix patch for this run.
- Ryan's 2026-06-16 11:24 "no this is not fixed" reopens the Apple Maps link parsing issue from the 2026-06-15 21:07 thread; parent thread was already checked off, so this needs a separate follow-up rather than being treated as done.

Implementation:

- Updated `AddQuestionTemplates` so `wannaGo` saves keep the existing excitement scale but skip visited-only prompts such as restaurant `price`, coffee `work_setup`, and hike `strenuousness`.
- Added pre-visit prompts that reuse existing attribute keys where possible: `planning for?` and `why save it?`, with no default tags auto-selected.
- Added `AGENTS.md` testing guidance for Codex: sandboxed `xcodebuild test` can fail on CoreSimulator, logs, or SwiftPM access, and agents should rerun the same command with escalated permissions using `prefix_rule: ["xcodebuild", "test"]`.

Verification:

- Sandboxed focused test failed before exercising app code because CoreSimulator access and GitHub package resolution were blocked.
- Elevated focused test passed:
  `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-wanna-go CODE_SIGNING_ALLOWED=NO -jobs 1 -only-testing:WanderTests/WanderStoreTests/testWannaGoQuestionTemplatesAvoidVisitedOnlyPrompts`
- `git diff --check` passed.

Remaining triage / next actions:

- P1 security/backend: Supabase alert says `rls_disabled_in_public` is publicly accessible in project `wander`. Recommended next step is to inspect hosted tables and apply/verify RLS policies explicitly; this needs backend approval and should not be changed blindly from this workflow.
- P1 sync reliability: signed-in own-place saves can fail remote sync and currently land in `.failed` with local persistence, but there is no visible retry queue drain for failed `user_places`. Recommended next step is a small sync-retry design/implementation pass with tests.
- P2 reopened link parsing: Apple Maps Urth Cafe link issue was marked handled before Ryan's "not fixed" reply; needs a fresh repro link/device/account details or a dedicated parser regression pass.
- P2 product UX: Add-tab search bar/in-page results and social person map filter are actionable enhancements, but should be planned as separate UI work.

## 2026-06-18 12:39 PDT - Codex - PR #11 Merge And Build 28 Release

Agent: Codex
Branch: `main`
Starting status: local `main` was clean and up to date at `4e276b1`; fetched, pulled, reviewed PR #11 metadata/diff, then merged PR #11.

Goal: merge PR #11, bump TestFlight build, and correct the TestFlight feedback workflow after Joe pointed out that Add-tab search and social-filter feedback had been checkmarked without implementation PRs.

PR #11 merge:

- PR: `https://github.com/joelipshutz/wander/pull/11`
- Head reviewed: `581350651fc651f428146a3a91d19bb9d077e431`
- Merge commit on `main`: `fc808cc` (`fix: tailor wanna-go add questions (#11)`)
- Scope merged: `wannaGo` add/save question templates now avoid visited-only prompts; focused regression test added; Codex `xcodebuild test` escalation procedure documented in `AGENTS.md`.

Correction / follow-up:

- Add-tab search-bar/in-page results and the social filter-pill dropdown are not implemented in PR #11, not present in another open PR, and not present in a local/remote branch found by branch/search checks.
- The Slack `:white_check_mark:` reactions on those feedback items were premature; they represented triage only, not shipped fixes.
- Follow-up required: update `agent-skills/recme-testflight-feedback-bug-catcher/SKILL.md` so enhancement/bug implementation items are not checkmarked unless an implementation PR is open. Approval-needed P1/security reports should be clearly labeled as decision-needed, not silently treated as fixed.

Build 28:

- Bumped `CURRENT_PROJECT_VERSION` from `27` to `28` in `project.yml`.
- Ran `xcodegen generate`; generated `Wander.xcodeproj/project.pbxproj` reflects build `28`.
- Build bump commit pushed to `main`: `66f61c6` (`chore: bump testflight build 28`).
- Root release verification caveat:
  - `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-build28-test CODE_SIGNING_ALLOWED=NO -jobs 1 -quiet` reached Xcode's test/finalize-log phase, then hung waiting for test log recording/workers and was interrupted.
  - Risk is low because PR #11's focused elevated test passed on the same simulator destination before merge, and the post-merge change before archiving was build-number metadata only.
- Archived build `0.1 (28)` at `/private/tmp/Wander-0.1-build28.xcarchive`.
- Uploaded build `0.1 (28)` with `xcodebuild -exportArchive`; Xcode output ended with `Uploaded Wander`.
- Ran `node scripts/testflight-release.mjs --build-number 28 --timeout-attempts 40 --poll-seconds 30`.
- Build `0.1 (28)` App Store Connect id: `c7673f93-1796-411b-8c04-62380b78ad1f`.
- Build `0.1 (28)` is `VALID`, export compliance is `usesNonExemptEncryption=false`, attached to `Wander Alpha`, and external TestFlight review is `APPROVED`.
- Public TestFlight link remains `https://testflight.apple.com/join/knEhRa6t`.

Process correction:

- Updated `agent-skills/recme-testflight-feedback-bug-catcher/SKILL.md` on branch `codex/feedback-checkmark-pr-rule` so actionable implementation feedback only gets `:white_check_mark:` after an implementation PR is open and linked.
- The updated rule also says triage-only, backlog, follow-up-needed, approval-needed, and mixed incomplete threads stay uncheckmarked.

## 2026-06-18 13:04 PDT - Codex - Linear Task Status Skill Contract

Agent: Codex
Branch: `codex/feedback-checkmark-pr-rule`
Starting status: branch clean at `d9be6d0`; root checkout has untracked `DerivedData-build28-test/` from the prior build/test run, left untouched. Existing worktrees are `/private/tmp/recme-auth-save-persist`, `/private/tmp/recme-shared-agent-skills`, and `/private/tmp/recme-wanna-go-question-fit`, with no overlap on the skill docs being edited.

Goal: update both repo-owned rec.me automation skills so Linear is the source of truth for task polling/status, and so both skills share one strict task status definition. Joe confirmed current `Done` should mean merged to `main` and pushed/available in TestFlight; later production release workflow will update `Done` to mean production.

Linear context checked:

- Team `recme` statuses: `Backlog`, `Todo`, `In Progress`, `In Review`, `Done`, `Canceled`, `Duplicate`.
- Example integrated issue: `REC-1` (`Add search bar to the top of the add tab`) is in `Backlog` with a Slack attachment, confirming Slack feeds Linear but Linear should be polled as the queue.

Expected files to touch:

- `agent-skills/recme-pr-review-merge-release/SKILL.md`
- `agent-skills/recme-testflight-feedback-bug-catcher/SKILL.md`
- `docs/agent-log.md`

Completion notes:

- Added the same Universal Linear Task Status Contract to both skills.
- Updated the feedback issue-checker skill to poll Linear `Backlog`, `Todo`, and `In Progress` issues instead of Slack, use Slack attachments only as context, move implementation work to `In Progress`, and move issues to `In Review` only after an implementation PR is open.
- Updated the PR review/merge/TestFlight skill to resolve linked Linear issues, keep merged-but-not-TestFlight work in `In Review`, and move product/app issues to `Done` only after the change is merged to `main` and available in TestFlight.
- Preserved the future production caveat: when production releases exist, the contract should be updated so `Done` means shipped in a production App Store version.

Verification:

- `git diff --check`
- Searched both skill files for stale Slack polling/checkmark language; remaining Slack mentions are only contextual or release-note-specific.

Outcome:

- Commit: `ac03f30` (`docs: align recme skills with linear statuses`)
- PR: https://github.com/joelipshutz/wander/pull/13

## 2026-06-18 13:08 PDT - Codex - REC-1/REC-3 Add Search And Social Filter

Agent: Codex
Branch: `codex/rec-1-rec-3-ui`
Worktree: `/private/tmp/recme-rec-1-rec-3-ui`
Starting status: created from latest `origin/main` at `11f70ba`; root checkout was clean on `main` after fetching/pulling. Existing worktrees `/private/tmp/recme-auth-save-persist`, `/private/tmp/recme-shared-agent-skills`, and `/private/tmp/recme-wanna-go-question-fit` do not overlap with this UI work.

Linear issues:

- `REC-1` Add search bar to the top of the add tab
- `REC-3` Add social map filter pill dropdown

Goal: implement the next clear Linear feedback issues from the updated bug-catcher workflow, then open a PR and move both issues to `In Review`.

Expected files to inspect/touch:

- `Wander/Features/Add/AddScreen.swift`
- `Wander/Features/Map/MapScreen.swift`
- `Wander/Features/Discover/DiscoverScreen.swift`
- `Wander/Services/WanderLocalStore.swift`
- `WanderTests/WanderStoreTests.swift`
- `docs/agent-log.md`

Checkpoint:

- Implemented Add-tab top search field that accepts a place name or map/location link and shows candidate results inline on the Add source page.
- Current-location results now also stay on the Add source page instead of jumping to a separate confirm step, matching the in-page-results feedback.
- Implemented social map filter as a dropdown pill with options for all social places, each visible social owner, and hiding social places.
- Extended `PlaceFilters` with `ownerIDs` and wired local/remote visible-place filtering so the selected social owner actually filters the map data.
- Added store regression coverage for filtering remote-visible social places to a specific owner.

Verification:

- `git diff --check` passed.
- Initial focused selector compiled but matched 0 tests, so it was not counted as verification.
- Elevated focused suite passed: `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-rec-1-rec-3 CODE_SIGNING_ALLOWED=NO -jobs 1 -only-testing:WanderTests/WanderStoreTests` (41 tests, 0 failures).
- Elevated full test passed: `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-rec-1-rec-3 CODE_SIGNING_ALLOWED=NO -jobs 1` (98 tests, 0 failures).
- Rebasing onto latest `origin/main` produced a `docs/agent-log.md` conflict with the skill-contract log entry; resolved by preserving both entries.
- Elevated full test passed again on rebased head `b86170f`: `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-rec-1-rec-3-final CODE_SIGNING_ALLOWED=NO -jobs 1` (98 tests, 0 failures).

## 2026-06-18 13:22 PDT - Codex - Issue Checker Eng Review Gate

Agent: Codex
Branch: `codex/issue-review-eng-gate`
Starting status: clean `main...origin/main` at `d4d7825`; existing worktrees are `/private/tmp/recme-auth-save-persist`, `/private/tmp/recme-rec-1-rec-3-ui`, `/private/tmp/recme-shared-agent-skills`, and `/private/tmp/recme-wanna-go-question-fit`, with no overlap on the issue-checker skill doc.

Goal: update the repo-owned `recme-testflight-feedback-bug-catcher` skill so Linear issue review invokes `plan-eng-review` when issue scope warrants it, and so key decisions surfaced by that review are flagged in the current thread before implementation proceeds.

Expected files to touch:

- `agent-skills/recme-testflight-feedback-bug-catcher/SKILL.md`
- `docs/agent-log.md`

Completion notes:

- Read `/Users/joelipshutz/.claude/skills/gstack/.agents/skills/gstack-plan-eng-review/SKILL.md` and updated the issue-checker skill to invoke it before implementation when Linear issue scope has non-trivial engineering risk.
- Added trigger criteria for P0/P1, auth/sync/backend/privacy/schema/RLS/data/persistence/visibility/security/migration, cross-screen behavior, multi-service/file plans, and unclear test/data/failure-mode boundaries.
- Added a decision-stop rule: if `plan-eng-review` surfaces architecture, data, test, performance, scope, or rollout decisions, the agent must flag the decision in the current thread and Linear comment before executing.
- Updated final reporting to include the engineering review gate outcome.

Verification:

- `git diff --check`

Outcome:

- Commits: `d02e8ac` (`docs: add eng review gate to issue checker`) and `b1fbbef` (`docs: log issue checker eng gate pr`)
- PR: https://github.com/joelipshutz/wander/pull/14

## 2026-06-18 21:43 PDT - Codex - PR #15 Review, Merge, Build 29 Release Attempt

Agent: Codex
Branch: `main`
Starting status: `main` clean at `origin/main`; root checkout later gained untracked `DerivedData-build29/` and `DerivedData-build29-test/` from release verification attempts, left untouched.

Goal: run the shared `recme-pr-review-merge-release` workflow for open PRs targeting `main`, merge eligible app-code PRs, and complete the TestFlight follow-up.

Open PR triage:

- PR #15 (`codex/rec-1-rec-3-ui`) was clean and app-code eligible.
- PR #14 (`codex/issue-review-eng-gate`) is still open and currently `DIRTY` after the main update.
- PR #10 (`codex/update-pr-release-skill`) is still open and currently `DIRTY`.

PR #15 review/merge:

- Reviewed REC-1/REC-3 changes across Add search, current-location inline candidates, social map filtering, local store filtering, and regression tests.
- `git diff --check origin/main...HEAD` passed in the PR worktree.
- Elevated focused PR verification passed: `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-pr15-review CODE_SIGNING_ALLOWED=NO -jobs 1 -only-testing:WanderTests/WanderStoreTests` (41 tests, 0 failures).
- GitHub would not allow self-approval, so a review comment was posted instead: https://github.com/joelipshutz/wander/pull/15#issuecomment-4745912187
- Squash-merged PR #15 to `main`: `65dc4ea` (`feat: add add-tab search and social map filter (#15)`). Branch deletion failed only because the branch is checked out in `/private/tmp/recme-rec-1-rec-3-ui`.

Build 29 release follow-up:

- Bumped `CURRENT_PROJECT_VERSION` from 28 to 29 in `project.yml`.
- Ran `xcodegen generate` so `Wander.xcodeproj/project.pbxproj` reflects build 29.
- Committed and pushed build bump to `main`: `3fc2014` (`chore: bump testflight build 29`).
- Release build/test verification caveat: simulator `xcodebuild build` and full `xcodebuild test` both reached Xcode finalization/waiting phases and then hung; at Joe's instruction to proceed with the archive, both were interrupted rather than retried further. The focused PR regression suite above passed before merge.
- Archive succeeded: `/private/tmp/Wander-0.1-build29.xcarchive`.
- TestFlight export/upload is blocked before upload by Apple tooling: `PLA Update available` and `No signing certificate "iOS Distribution" found`.
- Because build 29 is not uploaded or available in TestFlight, no tester Slack release note was posted, and linked Linear issues REC-1/REC-3 were left in `In Review` per the rec.me Linear status contract.
- Added Linear comments to REC-1 and REC-3 with the merge/build/archive status and the App Store Connect signing/license blocker.

Next steps:

- Accept/update the required Apple Developer Program license agreement and install or create an iOS Distribution signing certificate for the team.
- Re-run export/upload from the existing archive if still valid: `xcodebuild -exportArchive -archivePath /private/tmp/Wander-0.1-build29.xcarchive -exportPath /private/tmp/WanderTestFlightUpload29 -exportOptionsPlist /private/tmp/WanderExportUpload.plist -allowProvisioningUpdates`.
- After upload succeeds, run `node scripts/testflight-release.mjs --build-number 29 --timeout-attempts 40 --poll-seconds 30 --env /Users/joelipshutz/.openclaw/workspace/.env.keys`, mark REC-1/REC-3 `Done`, and post the required `#testflight-feedback` tester note.

## 2026-06-18 21:58 PDT - Codex - Build 29 TestFlight Upload Completed

Agent: Codex
Branch: `main`

Follow-up after Joe fixed the signing certificate:

- Retried export/upload from the existing archive `/private/tmp/Wander-0.1-build29.xcarchive`.
- Upload succeeded; App Store Connect accepted the package and began processing.
- Ran `node scripts/testflight-release.mjs --build-number 29 --timeout-attempts 40 --poll-seconds 30 --env /Users/joelipshutz/.openclaw/workspace/.env.keys`.
- Build `0.1 (29)` became `VALID`, build id `e34cc9e1-1696-4415-a5c0-ab8ef7082858`.
- Set export compliance to `usesNonExemptEncryption=false`.
- Attached build 29 to `Wander Alpha`.
- Submitted external TestFlight review; App Store Connect reports review state `APPROVED`.
- Marked Linear REC-1 and REC-3 `Done`.
- Posted tester note to `#testflight-feedback`: https://recmegroup.slack.com/archives/C0BAA7DG2AC/p1781845127959469

Known local cleanup:

- Root checkout still has untracked generated directories `DerivedData-build29/` and `DerivedData-build29-test/` from the earlier interrupted verification attempts; left untouched.

## 2026-06-18 22:33 PDT - Codex - Issue Checker Eng Gate PR Refresh

Agent: Codex
Branch: `codex/issue-review-eng-gate`

Follow-up after Joe said "check for more":

- Found PR #14 was conflicting after the build 29 mainline updates.
- Merged latest `origin/main` into the PR branch and preserved both the build 29 release log entries and the issue-checker skill update entry.
- Cleaned an older log merge artifact that had placed the PR #14 outcome inside the prior Linear-status contract entry.
- Updated `AGENTS.md` so the shared issue-checker skill is described as Linear issue plus TestFlight feedback work.
- Tightened `recme-pr-review-merge-release` so risky backend/sync/auth/privacy/data/persistence/visibility PRs invoke `plan-eng-review` when warranted, and key review decisions are flagged in the current thread and linked Linear issue or PR before merge.

Verification:

- `git diff --check` passed.
- No conflict markers found in `docs/agent-log.md`.
- Checked the PR diff against `origin/main`; the remaining PR surface is limited to the shared skill docs, `AGENTS.md`, and this log.

## 2026-06-18 22:14 PDT - Codex - REC-10 Followed Users Surfaces

Agent: Codex
Branch: `codex/followed-users-surfaces`
Worktree: `/private/tmp/recme-followed-users-surfaces`
Starting status: created from latest `origin/main` at `44565dd`. Root checkout has untracked generated `DerivedData-build29/` and `DerivedData-build29-test/` from the build 29 release run, left untouched. Existing worktrees are `/private/tmp/recme-auth-save-persist`, `/private/tmp/recme-rec-1-rec-3-ui`, `/private/tmp/recme-shared-agent-skills`, and `/private/tmp/recme-wanna-go-question-fit`; no overlap expected except this work may touch the same social/map/discover surfaces as the already-merged REC-1/REC-3 branch.

Linear issues:

- REC-10 Followed users don't appear in Discover or on map
- REC-7 Friends' saved places not showing in Discover or map filter
- REC-9 People follow state is inconsistent across search, profile, and Discover

Goal: implement the social-surface consistency fix as one umbrella change: followed users should appear in Discover's people rail, their visible places should feed Discover/map/social filters, and profile follow controls should not imply accidental unfollow.

Expected files to inspect/touch:

- `Wander/Features/Discover/DiscoverScreen.swift`
- `Wander/Features/Map/MapScreen.swift`
- `Wander/Features/Profile/ProfileScreen.swift`
- `Wander/Services/WanderLocalStore.swift`
- `Wander/Services/RepositoryProtocols.swift`
- `WanderTests/WanderStoreTests.swift`
- `docs/agent-log.md`

Checkpoint:

- Added a store-level remote social surface refresh that refreshes the current user's social graph, remote visible places, and per-followed-user visible places.
- Wired Discover and Map startup/auth refresh through that social surface refresh so followed users and their saved places are available outside username search.
- Added followed users from `store.following(of:)` to Discover's horizontal people rail, deduped against contacts and search results.
- After following from Discover contact/search cards, refresh social surfaces before refreshing Discover results.
- Changed the other-user profile header so the `friend`/`following` pill is status-only; `Unfollow` now lives in the overflow menu next to Block.
- Added regression coverage for remote social graph hydration followed by per-user place hydration.

Verification:

- Sandboxed `xcodebuild test ... -only-testing:WanderTests/WanderStoreTests/testRemoteSocialSurfacesHydrateFollowedUsersAndTheirPlaces` failed before compiling because CoreSimulator and Swift package network access were sandbox-blocked.
- Elevated focused regression passed after one compile fix: `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-followed-users CODE_SIGNING_ALLOWED=NO -jobs 1 -only-testing:WanderTests/WanderStoreTests/testRemoteSocialSurfacesHydrateFollowedUsersAndTheirPlaces`.
- Elevated `WanderStoreTests` passed: 42 tests, 0 failures.
- Elevated full test suite passed: `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-followed-users CODE_SIGNING_ALLOWED=NO -jobs 1` (99 tests, 0 failures).

Final outcome:

- Committed implementation as `58d1707` (`fix: hydrate followed users across social surfaces`) on `codex/followed-users-surfaces`.
- Opened PR #16: https://github.com/joelipshutz/wander/pull/16
- Attached PR #16 to Linear REC-10, REC-7, and REC-9; moved all three to `In Review`.
- Known local cleanup: worktree has untracked generated `DerivedData-followed-users/`, left uncommitted.
- Next step: review/merge PR #16, then run the standard build-number/TestFlight follow-up if merged to `main`.

## 2026-06-18 22:36 PDT - Codex - Remaining Linear Issue Sweep

Agent: Codex
Branch: `codex/followed-users-surfaces`
Worktree: `/private/tmp/recme-followed-users-surfaces`

Goal: Joe asked to look across all rec.me Linear issues, run `plan-eng-review` where needed, tee up only necessary decisions, and close as many issues as possible now.

Plan-eng-review scope result:

- REC-7/REC-9/REC-10 remain covered by PR #16.
- REC-5, REC-6, REC-8, REC-11, REC-12, and REC-13 are implementable in this same branch because they share Map/Profile/Add/store codepaths.
- REC-4 is not honestly closable yet: checked-in RLS migrations/tests already define the intended policy model, but live Supabase verification requires database/management access. Local env currently exposes app/service keys, not the management or DB credentials needed to inspect `pg_class.relrowsecurity` or apply migrations. Supabase CLI is not installed in this environment.

Expected files to touch:

- `Wander/Services/WanderLocalStore.swift`
- `Wander/Services/LinkPlaceParser.swift`
- `Wander/Services/WanderPlaceCategory.swift`
- `Wander/Features/Map/MapScreen.swift`
- `Wander/Features/Profile/ProfileScreen.swift`
- `Wander/Features/Add/AddScreen.swift`
- focused tests under `WanderTests/`
- `docs/agent-log.md`

Checkpoint:

- Added failed own-place sync retry on signed-in auth refresh for REC-5.
- Tuned place category inference so Lake Shrine / shrine / temple-style names classify as `spiritual` in local category normalization and the extraction worker for REC-6.
- Added tappable Profile Been/Wanna stat navigation with search, category, and metadata tag filters for REC-8.
- Added one-time map centering over current user's visible saved places, with a fallback to all visible places, for REC-11.
- Improved Apple Maps place-path parsing for `/place/<name>?coordinate=...` URLs while preserving existing `ll` query behavior for REC-12.
- Added on-device Vision OCR for photo imports and maps place-like recognized text into the existing confirm-candidate flow, preserving unresolved draft fallback for low-confidence photos, for REC-13.
- Added focused regression coverage for map region fitting, photo text extraction, profile metadata tag parsing, Apple Maps path parsing, Lake Shrine category override, and failed-save retry.

Verification:

- Removed generated `DerivedData-followed-users/` after the first focused rerun failed with `No space left on device`; reran with a fresh warmed `DerivedData-focused-issues/`.
- Focused regression passed: `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-focused-issues CODE_SIGNING_ALLOWED=NO -jobs 1 -only-testing:WanderTests/LinkPlaceParserTests -only-testing:WanderTests/WanderPlaceCategoryTests -only-testing:WanderTests/MapRegionFitterTests -only-testing:WanderTests/PhotoPlaceTextExtractorTests -only-testing:WanderTests/ProfileMetadataTagParserTests -only-testing:WanderTests/WanderStoreTests/testRetryFailedOwnPlaceSyncsMarksRowsSynced` (20 tests, 0 failures).
- Full elevated suite passed: `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-focused-issues CODE_SIGNING_ALLOWED=NO -jobs 1` (106 tests, 0 failures).
- `git diff --check` passed.

Final status:

- REC-5, REC-6, REC-8, REC-11, REC-12, and REC-13 are ready to attach to PR #16 and move to `In Review`.
- REC-4 remains a real decision/access item: need Supabase CLI or DB/management credentials to verify hosted RLS state before calling it closed.
## 2026-06-18 22:25 PDT - Codex - M7/M8 Planning And M7 Alpha Trust Worktree

Agent: Codex
Branch: `codex/m7-alpha-trust`
Worktree: `/private/tmp/recme-m7-alpha-trust`
Starting status: clean worktree at `origin/main` commit `44565dd`.

Goal: answer whether M7/M8 have real plans, create an isolated worktree because another agent is cooking, and start the non-overlapping M7 alpha trust/onboarding work while avoiding the active M8 social reliability worktree.

Coordination notes:

- Existing root checkout has untracked generated directories `DerivedData-build29/` and `DerivedData-build29-test/`; left untouched.
- Existing worktree `/private/tmp/recme-followed-users-surfaces` on `codex/followed-users-surfaces` has uncommitted M8/social changes in `DiscoverScreen`, `MapScreen`, `ProfileScreen`, `WanderLocalStore`, `WanderStoreTests`, and `docs/agent-log.md`.
- To avoid overlap, this branch should not edit Map/Discover/Profile/store social surfaces unless explicitly coordinated.
- Current roadmap only has high-level M7/M8 bullets. No detailed M7/M8 implementation plan exists yet.

Expected files to touch:

- `docs/plans/2026-06-18-m7-m8-alpha-plan.md`
- `docs/roadmap.md`
- `docs/agent-log.md`
- Potentially low-overlap M7 files under `Wander/Features/Auth/`, `Wander/Features/Settings/`, and app/auth gate tests after inspection.

### 2026-06-18 22:37 PDT checkpoint

Joe paused implementation and requested `/plan-eng-review` for the M7/M8 plan before continuing.

Actions:

- Interrupted focused `xcodebuild test -only-testing:WanderTests/AuthSessionTests`; Xcode reported `** TEST INTERRUPTED **`, so no pass/fail signal should be inferred from that run.
- Ran plan-eng-review against `docs/plans/2026-06-18-m7-m8-alpha-plan.md`, the current M7 diff, and the parallel M8 branch shape.
- Added review artifact `docs/reviews/2026-06-18-m7-m8-plan-eng-review.md`.
- Appended `## GSTACK REVIEW REPORT` to the M7/M8 plan.

Review outcome:

- Status: `DONE_WITH_CONCERNS`.
- M7 is acceptable as a small Settings/Auth trust lane, but needs UI/inspection or visual QA coverage for the new trust sheet before landing.
- M8 should stay in the social branch lane and needs explicit two-account QA before REC-7/REC-9/REC-10 are marked done.
- Keep M9 capture expansion out of M7/M8 until social reliability is accepted.

### 2026-06-18 22:48 PDT checkpoint

Implemented the M7 follow-up from the eng review without touching the active M8 social files.

Files changed:

- `Wander/Features/Settings/SettingsScreen.swift`
- `WanderTests/AuthSessionTests.swift`
- `docs/roadmap.md`
- `docs/plans/2026-06-18-m7-m8-alpha-plan.md`
- `docs/reviews/2026-06-18-m7-m8-plan-eng-review.md`
- `docs/qa/2026-06-18-m7-m8-alpha-trust-social-checklist.md`
- `docs/agent-log.md`

Outcome:

- Added a Settings row for `Privacy and trust`, presented as a sheet.
- Extracted the alpha trust copy into `SettingsTrustSurface` so it is testable and not buried only in SwiftUI view text.
- Covered the copy contract in `AuthSessionTests`, including Everyone/followers, Friends/mutuals, location not live broadcast, extraction not auto-save, blocks, and contacts/username search expectations.
- Added the M7/M8 QA checklist with a specific M8 two-account social graph gate.
- Updated the roadmap to point at M7/M8 active work and current Build 29 status.

Validation:

- Passed focused auth/settings contract test:
  `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-m7-alpha-trust CODE_SIGNING_ALLOWED=NO -jobs 1 -only-testing:WanderTests/AuthSessionTests`
- Passed full suite:
  `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-m7-alpha-trust-full CODE_SIGNING_ALLOWED=NO -jobs 1`
  Result: 100 tests, 0 failures.
- `git diff --check` passed.

Known issues / next steps:

- No visual simulator screenshot was captured for the new trust sheet yet; the sheet is simple, but manual QA should still verify clipping and dismiss behavior from Profile -> Settings.
- M8 implementation remains in the separate `codex/followed-users-surfaces` worktree/branch and should own Map/Discover/Profile/store changes.
- Generated untracked DerivedData directories exist in this worktree from validation runs and are intentionally not staged.

## 2026-06-18 22:59 PDT - Codex - Build 30 TestFlight Release Follow-Up

Agent: Codex
Branch: `codex/build30-release`
Worktree: `/private/tmp/recme-release-build30`
Starting status: clean worktree at merged `origin/main` commit `5a33e58`.

Goal: after merging PR #17, run the required app-code merge follow-up: bump TestFlight build number, regenerate the Xcode project, verify, archive/upload if signing allows, attach to TestFlight, and post tester-facing Slack notes after upload/availability.

Merge context:

- Squash-merged PR #17 into `main`: `5a33e58` (`feat: add m7 alpha trust surface (#17)`).
- PR #17 added the Settings `Privacy and trust` sheet, trust-copy contract tests, M7/M8 plan, eng-review artifact, and QA checklist.
- The `gh pr merge --delete-branch` command reported a non-blocking local branch deletion failure because `codex/m7-alpha-trust` is checked out at `/private/tmp/recme-m7-alpha-trust`; the PR itself merged successfully.

Expected files to touch:

- `project.yml`
- `Wander.xcodeproj/project.pbxproj`
- `docs/agent-log.md`

Planned validation:

- Run `xcodegen generate`.
- Run `xcodebuild build` and `xcodebuild test` with `CODE_SIGNING_ALLOWED=NO`.
- Archive/export/upload build 30 if signing and App Store Connect credentials are available.
- Run `node scripts/testflight-release.mjs --build-number 30`.

## 2026-06-18 23:20 PDT - Codex - PR #16 Post-Main Merge Verification

Agent: Codex
Branch: `codex/followed-users-surfaces`
Worktree: `/private/tmp/recme-followed-users-surfaces`

Goal: keep PR #16 current after `main` advanced with PR #17/build 30, then re-run verification before pushing the issue sweep branch.

Actions:

- Merged `origin/main` into `codex/followed-users-surfaces`.
- Resolved the only conflict in `docs/agent-log.md` by preserving both the issue-sweep notes and the M7/M8/build 30 notes.
- Cleared generated DerivedData to recover from local disk exhaustion during the first post-merge full-suite run.
- Removed old generated root worktree artifacts `DerivedData-build29/` and `DerivedData-build29-test/` to free enough space for a clean rerun.

Validation:

- First post-merge full-suite run reached app tests but failed when the simulator and xcresult bundle hit `No space left on device`; persistence assertions failed only after writes to simulator tmp failed.
- Reran the full suite after cleanup:
  `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-issue-sweep-merged CODE_SIGNING_ALLOWED=NO -jobs 1`
  Result: 108 tests, 0 failures.

Next steps:

- Push the updated PR #16 branch.
- Re-check GitHub mergeability.
- After PR #16 lands, run the normal build-number/TestFlight follow-up because this branch contains app-code changes.

## 2026-06-18 23:34 PDT - Codex - Build 31 TestFlight Release Follow-Up

Agent: Codex
Branch: `codex/build30-release`
Worktree: `/private/tmp/recme-release-build30`
Starting status: fast-forwarded to `origin/main` commit `b8d8b92` after PR #16 landed on top of the build 30 release commit.

Goal: keep current `main` aligned with TestFlight after PR #16 (`Fix followed users and issue sweep`) merged app-code, parser, store, profile, map, add, Supabase function, and test changes after build 30 was uploaded.

Context:

- Build 30 was uploaded and approved for the M7 trust sheet merge, but `main` advanced immediately after with PR #16.
- PR #16's own log entry calls for the normal build-number/TestFlight follow-up after landing.
- Bumping `CURRENT_PROJECT_VERSION` from 30 to 31 and regenerating the Xcode project before verification/archive/upload.

Expected files to touch:

- `project.yml`
- `Wander.xcodeproj/project.pbxproj`
- `docs/agent-log.md`

Planned validation:

- Run `xcodegen generate`.
- Run `xcodebuild build` and `xcodebuild test` with `CODE_SIGNING_ALLOWED=NO`.
- Archive/export/upload build 31.
- Run `node scripts/testflight-release.mjs --build-number 31`.
- Post the required tester-facing Slack note only after build 31 is uploaded/attached/available or clearly state if it is still processing.

Checkpoint from `/private/tmp/recme-followed-users-surfaces`:

- Confirmed `origin/main` already contains build bump commit `ed525b4` (`chore: bump testflight build 31`), so no duplicate bump commit was created from this worktree.
- `git diff --check` passed.
- `xcodebuild build -project Wander.xcodeproj -scheme Wander -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData-build31 CODE_SIGNING_ALLOWED=NO -jobs 1`
  Result: passed, `BUILD SUCCEEDED` in 629.210 sec.
- `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-build31 CODE_SIGNING_ALLOWED=NO -jobs 1`
  Result: passed, 108 tests, 0 failures.

## 2026-06-18 23:46 PDT - Codex - Build 31 TestFlight Release Complete

Agent: Codex
Branch: `codex/build30-release`
Worktree: `/private/tmp/recme-release-build30`

Outcome:

- Fast-forwarded to `origin/main` commit `b5196ef` (`docs: log build 31 verification`) after confirming it was docs-only.
- Preserved build 31 as the current TestFlight candidate because the only post-bump main change was `docs/agent-log.md`.
- Build 31 archive succeeded:
  `xcodebuild archive -project Wander.xcodeproj -scheme Wander -destination 'generic/platform=iOS' -archivePath /private/tmp/Wander-0.1-build31.xcarchive -derivedDataPath DerivedData-build31-archive -allowProvisioningUpdates`
  Result: `ARCHIVE SUCCEEDED` in 170.929 sec.
- Export/upload succeeded using App Store Connect API-key authentication:
  `xcodebuild -exportArchive -archivePath /private/tmp/Wander-0.1-build31.xcarchive -exportPath /private/tmp/WanderTestFlightUpload31 -exportOptionsPlist /private/tmp/WanderExportUpload.plist -allowProvisioningUpdates -authenticationKeyPath /Users/joelipshutz/Downloads/AuthKey_WU73VMSN38.p8 -authenticationKeyID WU73VMSN38 -authenticationKeyIssuerID 7f20b667-afd3-456b-b2bc-ca94ab295484`
  Result: `EXPORT SUCCEEDED`; uploaded package entered processing.
- TestFlight helper completed:
  `node scripts/testflight-release.mjs --build-number 31 --timeout-attempts 40 --poll-seconds 30 --env /Users/joelipshutz/.openclaw/workspace/.env.keys`
  Result: build `0.1 (31)` id `e851d502-1c07-4e52-8559-36f0e719370e`, `processingState=VALID`, `usesNonExemptEncryption=false`, attached to `Wander Alpha`, review state `APPROVED`.

Validation:

- Build 31 app-code build passed before archive:
  `xcodebuild build -project Wander.xcodeproj -scheme Wander -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData-build31 CODE_SIGNING_ALLOWED=NO`
  Result: `BUILD SUCCEEDED` in 95.756 sec.
- Build 31 full tests passed before archive:
  `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-build31 CODE_SIGNING_ALLOWED=NO -jobs 1`
  Result: `TEST SUCCEEDED` in 125.537 sec; 108 tests, 0 failures.

Release status:

- Build 30 was uploaded and approved first, but it is superseded by build 31 because PR #16 landed after the build 30 release.
- Build 31 is the current public TestFlight build attached to `Wander Alpha`.
- Public TestFlight link: https://testflight.apple.com/join/knEhRa6t
- Tester-facing Slack note: https://recmegroup.slack.com/archives/C0BAA7DG2AC/p1781851586744319

Known issues / follow-up:

- M7 trust sheet still needs human visual QA on device.
- M8 followed-user/social visibility surfaces need two-account human QA after installing build 31.
- Local disk remained tight during release; only generated DerivedData was cleaned when needed.

## 2026-06-19 00:01 PDT - Codex Automation - PR #10 Release Skill Refresh

Agent: Codex
Branch: `codex/update-pr-release-skill`
Worktree: `/private/tmp/recme-pr10-release-skill`

Goal: refresh stale PR #10 onto latest `origin/main` after PR #14 and build 31 landed, then merge it if the process/script changes are still valid.

Actions:

- Merged latest `origin/main` into PR #10.
- Resolved `agent-skills/recme-pr-review-merge-release/SKILL.md` by preserving both the pending-release sweep/TestFlight description support from PR #10 and the newer Linear status plus eng-review gate rules from `main`.
- Resolved `docs/agent-log.md` by keeping current `main` history and adding this fresh refresh note instead of replaying stale June 16 conflict blocks.
- Confirmed PR #10 remains docs/script/process-only; it does not change the iOS app binary, so it should not trigger a TestFlight build-number bump after merge.

Validation planned:

- `node --check scripts/testflight-release.mjs`
- `node scripts/testflight-release.mjs --dry-run --build-number 31 --what-to-test 'Try the current TestFlight build.'`
- `git diff --check`

## 2026-06-19 00:05 PDT - Codex - Build 31 Missing Clerk Key Regression

Agent: Codex
Branch: `codex/fix-clerk-publishable-key`
Worktree: `/private/tmp/recme-clerk-key-fix`
Starting status: clean branch fast-forwarded to latest `origin/main` commit `2e800b7`.

Goal: fix Joe's TestFlight report that build 31 signs users out after upgrade and then shows `Missing Clerk publishable key.` when trying to sign in.

Findings so far:

- `project.yml`, `Wander/Config/Auth.xcconfig`, and the generated `Wander.xcodeproj/project.pbxproj` currently leave `WANDER_CLERK_PUBLISHABLE_KEY` blank.
- The previous local/dev setup relied on ignored `Wander/Config/LocalAuth.xcconfig`; release worktrees do not have that file, so archives can silently ship with empty auth config.
- Supabase's public anon key is also only in local env, so remote sync can be silently disabled in release worktrees for the same reason.
- Clerk publishable key and Supabase anon key are public client keys, not server secrets, so the release-safe fix is to commit them into tracked client config and keep only real secrets in local env.

Expected files to touch:

- `project.yml`
- `Wander/Config/Auth.xcconfig`
- `Wander.xcodeproj/project.pbxproj`
- `docs/setup.md`
- `docs/agent-log.md`

Planned validation:

- Run `xcodegen generate`.
- Verify generated build settings resolve non-empty `WANDER_CLERK_PUBLISHABLE_KEY` and `WANDER_SUPABASE_PUBLISHABLE_KEY`.
- Add/adjust a regression test if practical.
- Run focused tests and then the full `xcodebuild test` suite if the environment allows.

Outcome:

- Root cause confirmed: build 31 was archived from a release worktree without ignored `Wander/Config/LocalAuth.xcconfig`, while tracked config and generated project settings left the Clerk publishable key empty.
- Added tracked default public client keys to `Wander/Config/Auth.xcconfig` for the alpha Clerk and Supabase projects. These are publishable/anon client keys, not server secrets; `LocalAuth.xcconfig` remains ignored and optional for alternate local projects.
- Removed the empty project-level publishable-key overrides from `project.yml` and regenerated `Wander.xcodeproj/project.pbxproj`.
- Added `WanderTests/BuildConfigurationTests.swift` to prevent tracked auth config or generated project settings from regressing to empty release keys.
- Updated `docs/setup.md` so release-capable worktrees no longer depend on local ignored auth config.

Validation:

- `xcodegen generate` succeeded.
- Release build settings check succeeded and resolved non-empty `WANDER_CLERK_PUBLISHABLE_KEY` and `WANDER_SUPABASE_PUBLISHABLE_KEY`.
- Focused test passed: `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-clerk-key CODE_SIGNING_ALLOWED=NO -jobs 1 -only-testing:WanderTests/BuildConfigurationTests` (`2` tests, `0` failures).
- Full suite passed: `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-clerk-key-full CODE_SIGNING_ALLOWED=NO -jobs 1` (`110` tests, `0` failures).

Next steps:

- PR opened: https://github.com/joelipshutz/wander/pull/18
- Needs explicit Joe approval to merge/release per `recme-pr-review-merge-release` safety boundary.
- After approval, merge urgently, then bump to build 32 and upload a replacement TestFlight build because build 31 is broken for signed-out users.

## 2026-06-19 09:05 PDT - Codex Automation - Build 32 TestFlight Follow-Up

Agent: Codex
Branch: `main`
Worktree: `/private/tmp/recme-followed-users-surfaces`

Goal: complete the scheduled PR review/merge/TestFlight workflow after PR #18 fixed missing release auth client config.

Context:

- PR #18 (`fix: ship auth client config in release builds`) merged to `main` as `4ed4c0ed`.
- Pre-merge review found no blockers. The fix is scoped to tracked public Clerk/Supabase client config, generated project settings, setup docs, and regression coverage.
- Sandboxed full-suite test failed before app code due to CoreSimulator and SwiftPM network restrictions, then the same command passed with elevated simulator/network access.

Validation before merge:

- `xcodegen generate` succeeded and left no tracked diff.
- `git diff --check` passed.
- `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-pr18-review CODE_SIGNING_ALLOWED=NO -jobs 1`
  Result: passed with elevated access, `110` tests, `0` failures.

Release plan:

- Bump `CURRENT_PROJECT_VERSION` from `31` to `32`.
- Run `xcodegen generate`.
- Run build and test validation for build 32.
- Archive/export/upload build 32 to TestFlight.
- Run `node scripts/testflight-release.mjs --build-number 32`.
- Post the tester-facing Slack release note after TestFlight attachment/approval or clearly note processing state.

Build 32 checkpoint:

- Updated `project.yml` to `CURRENT_PROJECT_VERSION: "32"` and regenerated `Wander.xcodeproj/project.pbxproj`.
- `git diff --check` passed.
- Initial elevated build failed before source failure due to `/private/tmp` running out of space at link time (`errno=28`).
- Removed generated DerivedData folders from prior automation worktrees to restore working disk space.
- `xcodebuild build -project Wander.xcodeproj -scheme Wander -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData-build32 CODE_SIGNING_ALLOWED=NO -jobs 1`
  Result: passed with elevated access, `BUILD SUCCEEDED` in `218.667 sec`.
- `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-build32 CODE_SIGNING_ALLOWED=NO -jobs 1`
  Result: passed with elevated access, `110` tests, `0` failures.

Release outcome:

- Build-number commit pushed to `main`: `96be999d` (`chore: bump testflight build 32`).
- Archive succeeded: `/private/tmp/Wander-0.1-build32.xcarchive`.
- Export/upload succeeded: `/private/tmp/WanderTestFlightUpload32`; App Store Connect accepted the upload and reported package processing.
- `node scripts/testflight-release.mjs --build-number 32 --timeout-attempts 40 --poll-seconds 30`
  Result: build `0.1 (32)` id `ba4bb8d9-6022-452f-8e59-8e7b93abc07b` was `VALID`, export compliance set to `usesNonExemptEncryption=false`, attached to `Wander Alpha`, submitted for external TestFlight review, and review state was `APPROVED`.
- Public TestFlight link: https://testflight.apple.com/join/knEhRa6t
- Tester-facing Slack note posted to `#testflight-feedback`: https://recmegroup.slack.com/archives/C0BAA7DG2AC/p1781885958732189

Known issues:

- Link/photo capture still creates unresolved drafts until backend extraction jobs are fully live.
- Social surfaces may still look sparse depending on account data.

## 2026-06-20 12:07 PDT - Codex - REC-13 Photo Extraction PR

Agent: Codex
Branch: `codex/rec-13-photo-extraction`
Worktree: `/private/tmp/recme-rec-13-photo-extraction`
Starting status: fresh worktree from latest `origin/main` at `c5b5a0e`; root checkout `/Users/ryanlieblein/Developer/wander` is dirty/behind with old build-number edits and is intentionally not used for this implementation.

Linear issue:

- `REC-13` - Photo extraction doesn't work when adding a place

Goal: implement REC-13 as a separate PR so adding from a photo can extract useful place text and show/save candidate places instead of always falling back to an unresolved manual draft.

Initial notes:

- Moved REC-13 from `Todo` to `In Progress` and assigned it to Ryan.
- REC-13 has an attachment to merged PR #16, but the current release log still lists link/photo capture as unresolved until backend extraction jobs are fully live, and the issue was not marked done. Treating this as a still-open product gap.
- Engineering review gate required because this touches extraction/add flow behavior.

Expected files to inspect/touch:

- `Wander/Features/Add/AddScreen.swift`
- `Wander/Services/PhotoPlaceTextExtractor.swift`
- `Wander/Services/WanderLocalStore.swift`
- `WanderTests/PhotoPlaceTextExtractorTests.swift`
- `WanderTests/WanderStoreTests.swift`
- `docs/agent-log.md`

Checkpoint:

- Engineering review gate outcome: clean to proceed with a narrow client-side fix. Keep the data flow local: PhotosPicker image -> Vision OCR -> ranked place queries -> existing MapKit/manual candidate resolver -> confirm/save. No schema/backend changes and no auto-save.
- Implemented ranked OCR search queries in `PhotoPlaceTextExtractor` so photo text can try multiple likely place names and nearby address/locality context before falling back to a draft.
- Updated the Add photo copy from draft-only language to scan/search language and made the Add flow try each OCR-derived query until one resolves candidates.
- Initial focused test command against the documented `iPhone 16 Plus, OS=18.6` destination could not run because this machine only has iOS 26.5 simulators installed.
- First focused run on `iPhone 17 Pro, OS=26.5` compiled successfully but failed one new extractor test because `Santa Monica, CA` outranked `Heavy Handed`. Fixed by treating locality lines as context only, not primary place candidates.
- `git diff --check` passed.
- `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath /private/tmp/DerivedData-rec13-photo CODE_SIGNING_ALLOWED=NO -jobs 1 -only-testing:WanderTests/PhotoPlaceTextExtractorTests`
  Result: passed with elevated access, `4` tests, `0` failures.
- `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath /private/tmp/DerivedData-rec13-photo-full CODE_SIGNING_ALLOWED=NO -jobs 1`
  Result: passed with elevated access, `112` tests, `0` failures.

Outcome:

- Implementation commit pushed to `codex/rec-13-photo-extraction`: `ca2f0c4` (`fix: improve photo place extraction`).
- PR opened against `main`: https://github.com/joelipshutz/wander/pull/19
- Linear `REC-13` will be moved to `In Review` with PR link attached.
- Known issue: backend image extraction remains deferred; this PR improves the current local Vision OCR -> MapKit candidate path and still falls back to unresolved drafts when no candidate resolves.
- Next step: PR review/merge/release workflow should own merge, TestFlight build, Slack release note, and moving `REC-13` to `Done` after TestFlight availability.

## 2026-06-20 12:42 PDT - Codex - PR #19 Squash Merge And TestFlight Release

Agent: Codex
Branch: `codex/pr19-merge-release`
Starting status: clean worktree at `c5b5a0e`, tracking `origin/main`.

Goal: review PR #19 (`codex/rec-13-photo-extraction`), squash-merge it to `main` only if conflict-free and non-blocking, then follow the required app-code release path with a build-number commit and TestFlight handling.

Expected files to touch:

- `project.yml`
- `Wander.xcodeproj/project.pbxproj`
- `docs/agent-log.md`

Initial notes:

- Root checkout `/Users/ryanlieblein/Developer/wander` is on `main`, behind `origin/main`, with local modifications to `project.yml`, `Wander.xcodeproj/project.pbxproj`, and `docs/agent-log.md`; those are treated as unrelated paused work and will not be edited or reverted.
- Existing PR implementation worktree `/private/tmp/recme-rec-13-photo-extraction` is clean on `codex/rec-13-photo-extraction`.
- This isolated release worktree was created from latest `origin/main` to avoid interfering with Ryan/Joe local state.

Review checkpoint:

- PR #19 metadata: open, ready, no labels, base `main`, head `codex/rec-13-photo-extraction` at `a5a758a2888a790eb94f61e84b877308a39effd8`, GitHub mergeability `MERGEABLE`, no reported GitHub checks.
- Reviewed diff against `origin/main`: `Wander/Features/Add/AddScreen.swift`, `Wander/Services/PhotoPlaceTextExtractor.swift`, `WanderTests/PhotoPlaceTextExtractorTests.swift`, and `docs/agent-log.md`.
- No blocking findings found. The change stays within the add-photo/OCR candidate flow, preserves the unresolved draft fallback when OCR search cannot resolve candidates, and adds focused extractor coverage.
- `git diff --check origin/main...origin/codex/rec-13-photo-extraction` passed.
- `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath /private/tmp/DerivedData-pr19-review-focused CODE_SIGNING_ALLOWED=NO -jobs 1 -only-testing:WanderTests/PhotoPlaceTextExtractorTests`
  Result: passed with elevated access, `4` tests, `0` failures.
- `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath /private/tmp/DerivedData-pr19-review-full CODE_SIGNING_ALLOWED=NO -jobs 1`
  Result: passed with elevated access, `112` tests, `0` failures.

Merge and build checkpoint:

- Squash-merged PR #19 to `main` with head guard `a5a758a2888a790eb94f61e84b877308a39effd8`.
- GitHub PR state after merge: `MERGED`; merge commit `f65514b7965ffd38ec4fe5265448f561886071a9`.
- Fast-forwarded this release worktree to the updated `origin/main` and resolved the expected `docs/agent-log.md` overlap by keeping both the REC-13 implementation entry and this release entry.
- Bumped TestFlight build number from `32` to `33` in `project.yml` and `Wander.xcodeproj/project.pbxproj`.
- Ran `xcodegen generate`; because the local generator wanted to churn unrelated project settings, restored the project file from `origin/main` and kept only the intended `CURRENT_PROJECT_VERSION = 33` changes.
- `git diff --check` passed.
- `xcodebuild build -project Wander.xcodeproj -scheme Wander -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/DerivedData-build33 CODE_SIGNING_ALLOWED=NO -jobs 1`
  Result: passed with elevated access.
- `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath /private/tmp/DerivedData-build33 CODE_SIGNING_ALLOWED=NO -jobs 1`
  Result: passed with elevated access, `112` tests, `0` failures.

Release outcome:

- Build-number commit pushed to `main`: `2d13e92` (`chore: bump testflight build 33`).
- First archive attempt without an explicit App Store Connect API key failed at signing/profile lookup with `No Accounts` and no matching iOS App Development provisioning profile for `com.grayline.wander`.
- Retried archive with Ryan's local App Store Connect API key (`BU88FB5ZG4`); archive succeeded at `/private/tmp/Wander-0.1-build33.xcarchive`.
- Recreated upload options at `/private/tmp/WanderExportUpload.plist`.
- Export/upload attempt:
  `xcodebuild -exportArchive -archivePath /private/tmp/Wander-0.1-build33.xcarchive -exportPath /private/tmp/WanderTestFlightUpload33 -exportOptionsPlist /private/tmp/WanderExportUpload.plist -allowProvisioningUpdates -authenticationKeyPath /Users/ryanlieblein/.openclaw/workspace/AuthKey_BU88FB5ZG4.p8 -authenticationKeyID BU88FB5ZG4 -authenticationKeyIssuerID 7f20b667-afd3-456b-b2bc-ca94ab295484`
  Result: blocked before upload with `exportArchive Cloud signing permission error` and `No profiles for 'com.grayline.wander' were found`.
- Local signing check found only one valid identity: `Apple Development: Created via API (BU88FB5ZG4)`. No Apple Distribution identity is available locally, and the configured API key does not currently have enough cloud-signing/profile access to export for App Store Connect upload.
- No `scripts/testflight-release.mjs` run, no TestFlight attachment, no tester-facing Slack note, and no Linear `Done` update for `REC-13` yet because build `33` was not uploaded.

Known issues / next steps:

- `main` has PR #19 merged and build `33` committed; code verification is complete.
- To finish TestFlight, grant Ryan's App Store Connect API key/account the required distribution/cloud-signing permission or install/provide an Apple Distribution certificate/profile for `com.grayline.wander`, then rerun the export/upload command above from this worktree or from latest `main`.
- After upload succeeds, run `node scripts/testflight-release.mjs --build-number 33 --timeout-attempts 40 --poll-seconds 30`, move `REC-13` to `Done`, post the required `#testflight-feedback` tester note, and append the final live/approved status to this log.

## 2026-06-20 13:51 PDT - Codex - Build 33 TestFlight Completion

Agent: Codex
Branch: `codex/pr19-merge-release`
Starting status: clean worktree at `4060d62`, tracking `origin/main`. Ryan provided a replacement App Store Connect API key file `AuthKey_P4ZR59AXMD.p8` to unblock build 33 export/upload.

Outcome:

- Installed the new key at `/Users/ryanlieblein/.openclaw/workspace/AuthKey_P4ZR59AXMD.p8` with owner-only permissions and updated `/Users/ryanlieblein/.openclaw/workspace/.env.keys` to `ASC_KEY_ID=P4ZR59AXMD`.
- `node scripts/testflight-release.mjs --dry-run --build-number 33 --env /Users/ryanlieblein/.openclaw/workspace/.env.keys`
  Result: resolved app id `6776850787`, build number `33`, group `Wander Alpha`, and public link `https://testflight.apple.com/join/knEhRa6t`.
- Retried export/upload from the existing archive `/private/tmp/Wander-0.1-build33.xcarchive` with key `P4ZR59AXMD`.
  Result: upload succeeded; Xcode output ended with `Uploaded Wander`.
- First helper run with `--what-to-test-file /private/tmp/recme-build33-what-to-test.txt` found build `0.1 (33)` as `VALID` and set export compliance, but Apple rejected the beta localization request with `PARAMETER_ERROR.ILLEGAL` for `filter[locale]`.
- Reran helper without the What-to-Test file:
  `node scripts/testflight-release.mjs --build-number 33 --timeout-attempts 40 --poll-seconds 30 --env /Users/ryanlieblein/.openclaw/workspace/.env.keys`
  Result: build id `6e7297a5-4955-4a3c-b237-dd510cdb85c4`, processing state `VALID`, `usesNonExemptEncryption=false`, attached to `Wander Alpha`, submitted for external TestFlight review, review state `APPROVED`.
- Linear `REC-13` was already `Done`; added a completion comment with build 33 details and the helper limitation.
- Tester-facing Slack note posted to `#testflight-feedback`: https://recmegroup.slack.com/archives/C0BAA7DG2AC/p1781988702789919

Known issues:

- TestFlight "What to Test" metadata was not updated due the App Store Connect beta localization endpoint rejecting `filter[locale]`; the same testing checklist was included in Slack.
- Backend photo extraction jobs remain deferred; build 33 improves the local OCR-to-place-candidate path.

## 2026-06-20 14:13 PDT - Codex - REC-13 Reopened Photo Extraction Fix

Agent: Codex
Branch: `codex/photo-extraction-real`
Worktree: `/Users/ryanlieblein/Developer/Wander-worktrees/photo-extraction-real`
Starting status: clean worktree from latest `origin/main` at `e969101` (`chore: bump testflight build 34`). Root checkout `/Users/ryanlieblein/Developer/wander` is intentionally left untouched so Ryan's Xcode main workspace stays stable.

Linear issue:

- Reopened `REC-13` from `Done` to `In Progress` after Ryan reported build 33 still shows the old photo draft fallback screen.

Goal: fix Add from Photo for real, with root-cause investigation first. Build 33 only added a best-effort OCR-to-MapKit path and still falls back to the old unresolved draft screen whenever OCR or MapKit matching fails.

Expected files to inspect/touch:

- `Wander/Features/Add/AddScreen.swift`
- `Wander/Services/PhotoPlaceTextExtractor.swift`
- `Wander/Services/MapKitPlaceResolver.swift`
- `Wander/Services/WanderLocalStore.swift`
- `WanderTests/PhotoPlaceTextExtractorTests.swift`
- `WanderTests/WanderStoreTests.swift`
- `docs/agent-log.md`

Investigation rules:

- No implementation changes before confirming the root cause and adding regression coverage that would have caught the build 33 gap.
- Treat the previous PR as incomplete rather than simply changing copy.

Checkpoint:

- Root cause: PR #19 added local Vision OCR plus MapKit manual search, but photo import still falls into the old unresolved-draft path whenever OCR returns no ranked query or MapKit cannot match the ranked queries. The backend cannot rescue this path today: the Supabase extraction worker still returns `photo_ocr_not_configured` for photo artifacts, so "Photo saved as a draft" is current behavior, not a stale TestFlight install.
- Fix direction: make photo import resolve through a testable staged resolver: OCR text queries first, photo GPS metadata nearby POIs second, editable manual rescue with OCR text third, and only then an honest draft when the image has no usable place signal.

Outcome:

- Added a staged `PhotoPlaceImportResolver` that tries OCR-to-MapKit candidates, then EXIF GPS nearby POIs, then an editable manual rescue with the recognized query prefilled. The generic unresolved draft path now only runs when the selected photo has no usable OCR query and no usable photo coordinate.
- Added `PhotoPlaceMetadataExtractor` for GPS metadata in imported image data and `resolveNearbyPlaces(near:)` to the MapKit resolver boundary.
- Updated Add from Photo copy and fallback draft copy to stop promising backend photo extraction that does not exist yet.
- Tightened OCR query filtering for Apple Maps UI lines (`Apple Maps`, `Search`, `Top result`) after raising the query limit from 4 to 8.
- Kept the new tests inside `PhotoPlaceTextExtractorTests.swift` because `xcodegen` is not installed in this shell and the existing generated Xcode project already includes that file.

Validation:

- Expected failing regression baseline:
  `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath DerivedData-photo-real-failing CODE_SIGNING_ALLOWED=NO -jobs 1 -only-testing:WanderTests/PhotoPlaceImportResolverTests`
  Result before implementation: failed to compile because `PhotoPlaceCandidateSearching` did not exist.
- Focused photo resolver validation:
  same command after implementation.
  Result: passed, `4` tests, `0` failures.
- Broader photo/store validation:
  `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath DerivedData-photo-real CODE_SIGNING_ALLOWED=NO -jobs 1 -only-testing:WanderTests/PhotoPlaceTextExtractorTests -only-testing:WanderTests/PhotoPlaceImportResolverTests -only-testing:WanderTests/WanderStoreTests`
  Result: passed after tightening OCR UI-noise filtering, `51` tests, `0` failures.
- Full suite:
  `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -derivedDataPath DerivedData-photo-real CODE_SIGNING_ALLOWED=NO -jobs 1`
  Result: passed, `123` tests, `0` failures.

Known notes:

- The local machine only has iOS Simulator `26.5` devices available, so validation used `iPhone 17 Pro, OS=26.5` instead of the older `iPhone 16 Plus, OS=18.6` destination in repo docs.
- Test logs still show non-critical Clerk keychain warnings (`unexpectedStatus(-34018)`) and a CoreLocation simulator warning; tests passed.
- Backend photo OCR remains deferred/not configured. This fix makes the local app behavior real and user-rescuable instead of dropping usable photo signals into the old draft screen.

## 2026-06-20 11:52 PDT - Codex - REC-14 Clerk Login Regression

Agent: Codex
Branch: `codex/fix-clerk-login-regression`
Worktree: `/private/tmp/recme-clerk-login-regression`
Starting status: clean branch from `origin/main` at `c5b5a0ed`.

Goal: fix REC-14 / TestFlight build 32 login regression where users still see missing Clerk errors and cannot sign in.

Context:

- Linear issue: REC-14, "Missing Clerk issue still blocks sign-in on TestFlight".
- Slack attachment in Linear from Ryan reports build 32 still has missing Clerk issues and sign-in is blocked; sign-out path was unavailable to test.
- Regression window points at PR #18/build 32 auth config changes.
- Mission Control task creation attempted but `localhost:4000` was not reachable (`curl` exit 7).

Expected files to touch:

- `Wander/Config/Auth.xcconfig`
- `Wander/App/WanderBackendConfiguration.swift`
- `Wander/Services/Auth/ClerkAuthService.swift`
- `WanderTests/BuildConfigurationTests.swift`
- `docs/agent-log.md`

Planned validation:

- Inspect PR #18/build 32 auth config behavior.
- Add a regression test for the actual Clerk publishable-key shape used by the SDK.
- Run focused build configuration/auth tests and the full suite if feasible.

Outcome:

- Root cause: PR #18 correctly moved public Clerk/Supabase client values into tracked `Auth.xcconfig`, but the runtime still treated unresolved Info.plist substitutions like `$(WANDER_CLERK_PUBLISHABLE_KEY)` as missing. ClerkKit also returns an unconfigured client when `Clerk.configure` fails, so the sign-in surface could remain blocked without a stronger runtime fallback/guard.
- Added static public client defaults in `WanderBackendConfiguration` and made runtime configuration fall back when Info.plist values are unresolved, blank, or missing.
- Tightened `ClerkAuthService.canPresentNativeAuth` so native auth only presents after ClerkKit returns a configured client.
- Added auth regression coverage for unresolved Info.plist values, Auth.xcconfig/project/plist wiring, Clerk publishable-key frontend decoding, native auth presentation from fallback config, and SDK configure failure.

Validation:

- `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-rec14-focused CODE_SIGNING_ALLOWED=NO -jobs 1 -only-testing:WanderTests/BuildConfigurationTests`
  Result: passed with elevated simulator access, `5` tests, `0` failures.
- Verified built app Info.plist values from `DerivedData-rec14-focused`:
  - `WANDER_CLERK_PUBLISHABLE_KEY = pk_test_Z3Jvd2luZy1waGVhc2FudC0yMi5jbGVyay5hY2NvdW50cy5kZXYk`
  - `WANDER_CLERK_FRONTEND_API = growing-pheasant-22.clerk.accounts.dev`
- `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-rec14-auth-focused CODE_SIGNING_ALLOWED=NO -jobs 1 -only-testing:WanderTests/BuildConfigurationTests -only-testing:WanderTests/AuthSessionTests`
  Result: passed with elevated simulator access, `16` tests, `0` failures.
- `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-rec14-full-after-auth CODE_SIGNING_ALLOWED=NO -jobs 1`
  Result: passed with elevated simulator access, `117` tests, `0` failures.

Known notes:

- Simulator test logs still show Clerk keychain `unexpectedStatus(-34018)` warnings; ClerkKit logs these as non-critical and tests passed.
- Mission Control remained unavailable on `localhost:4000`, so no tracker task was created.
- Ready to push `codex/fix-clerk-login-regression` and open a PR linked to REC-14. No TestFlight upload or Slack release note from this bug-fix branch until the PR is reviewed/merged.

## 2026-06-20 13:58 PDT - Codex - PR #20 Post-Main Validation

Agent: Codex
Branch: `codex/fix-clerk-login-regression`
Starting status: branch was clean, ahead of `origin/codex/fix-clerk-login-regression` after updating from latest `origin/main`.

Goal: after Joe authorized the next merge, update PR #20 (`fix: harden Clerk runtime configuration`) from the just-landed PR #19/build `33` state, resolve any overlap, rerun auth-focused and full validation, then continue the merge/release workflow.

Checkpoint:

- Updated the PR branch from latest `origin/main` after PR #19 and build `33` landed.
- The only merge conflict was in `docs/agent-log.md`; resolved by preserving both the REC-14 auth-fix entry and the PR #19/build `33` release-blocker entry.
- `git diff --check` passed after conflict resolution.
- Focused auth/config validation:
  `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-rec14-post-main-focused CODE_SIGNING_ALLOWED=NO -jobs 1 -only-testing:WanderTests/BuildConfigurationTests -only-testing:WanderTests/AuthSessionTests`
  Result: passed with elevated access, `16` tests, `0` failures.
- Full suite validation:
  `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-rec14-post-main-full CODE_SIGNING_ALLOWED=NO -jobs 1`
  Result: passed with elevated access, `119` tests, `0` failures.

Next steps:

- Push the updated PR #20 branch, verify GitHub mergeability, squash-merge to `main`, then bump the next TestFlight build number to `34`.
- Build `33` from PR #19 remains not uploaded because export was blocked by signing/cloud-signing permissions; build `34` should supersede it if signing succeeds.

## 2026-06-20 14:30 PDT - Codex - PR #20 Merge and Build 34 TestFlight Release Complete

Agent: Codex automation `rec-me-pr-review-merge-and-testflight-release`
Branch: `main`
Worktree: `/private/tmp/recme-followed-users-surfaces`
Starting status: PR #20 was updated from latest `origin/main` after build 33 completion landed.

Outcome:

- PR #20 (`fix: harden Clerk runtime configuration`) was squash-merged to `main` as `3a1c990c`.
- Bumped `CURRENT_PROJECT_VERSION` from `33` to `34` in `project.yml`, regenerated `Wander.xcodeproj`, committed `e9691016` (`chore: bump testflight build 34`), and pushed it to `origin/main`.
- Build 34 validation passed:
  - `xcodebuild build -project Wander.xcodeproj -scheme Wander -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData-build34 CODE_SIGNING_ALLOWED=NO -jobs 1`
    Result: `BUILD SUCCEEDED`.
  - `xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-build34 CODE_SIGNING_ALLOWED=NO -jobs 1`
    Result: `119` tests, `0` failures, including the new Clerk auth/config regression coverage.
- Archived build `0.1 (34)` at `/private/tmp/Wander-0.1-build34.xcarchive`.
- Export/upload succeeded with Joe's App Store Connect API key; Xcode output ended with `Uploaded Wander`.
- First TestFlight helper run with inline What-to-Test copy found build 34 as `VALID` and set export compliance, but App Store Connect rejected the optional beta localization request with `PARAMETER_ERROR.ILLEGAL` for `filter[locale]`.
- Reran helper without What-to-Test copy:
  `node scripts/testflight-release.mjs --build-number 34 --timeout-attempts 40 --poll-seconds 30 --env /Users/joelipshutz/.openclaw/workspace/.env.keys`
  Result: build id `25db0778-ac56-4b2f-a83c-dd4befb27632`, processing state `VALID`, `usesNonExemptEncryption=false`, attached to `Wander Alpha`, external review `APPROVED`.
- Tester-facing Slack note posted to `#testflight-feedback`: https://recmegroup.slack.com/archives/C0BAA7DG2AC/p1781990973821369
- Linear `REC-14` was updated with release details and moved to `Done`.

Known issues / follow-up:

- TestFlight "What to Test" metadata was not updated because the helper's beta localization lookup is using an App Store Connect filter that this endpoint now rejects. Tester instructions were included in Slack instead.
- Build 33 and build 34 both completed today; build 34 is the current release candidate because it includes the Clerk login fix.

## 2026-06-20 14:47 PDT - Codex - Feedback Skill Engineering Review Gate

Agent: Codex
Branch: `codex/feedback-skill-eng-review-gate`
Worktree: `/private/tmp/recme-shared-agent-skills`
Starting status: switched the indexed shared-skill worktree from stale
`codex/shared-agent-skills` to a fresh branch from `origin/main` at `2deb2f9c`.
The root checkout was on stale branch `codex/issue-review-eng-gate`, so this
work stayed isolated in the temp worktree.

Goal: harden `recme-testflight-feedback-bug-catcher` so agents treat
Slack/TestFlight/Linear items as bug or feature work, invoke `plan-eng-review`
when the scope is complex, and surface architecture/data/test decisions with
recommendations before implementation.

Plan-eng-review outcome:

- Scope challenge: no app-code change needed; this is a process/skill fix.
- What already exists: repo-local skill already had a basic Engineering Review
  Gate, but the indexed `/private/tmp/recme-shared-agent-skills` copy was stale
  and the gate language still allowed "lens" behavior instead of actual skill
  invocation.
- Recommendation applied: make `plan-eng-review` an invocation gate for
  non-trivial feature/enhancement work, cross-screen behavior, shared contracts,
  trust/social/search/save semantics, backend/auth/sync/privacy/schema/security,
  unclear tests/failure modes, or larger diffs.
- Follow-up amendment: kept the stable skill slug
  `recme-testflight-feedback-bug-catcher` for automation compatibility, but
  renamed the human-facing workflow to "rec.me Feedback Feature/Bug Workflow."
- Follow-up amendment: added a mid-implementation decision checkpoint so agents
  must stop and surface newly discovered architecture/data/test/performance/
  scope/product/design/rollout decisions before continuing.
- Decisions: no product decision needed. This is a workflow correctness fix.

Files expected/touched:

- `agent-skills/recme-testflight-feedback-bug-catcher/SKILL.md`
- `docs/agent-log.md`

Validation:

- `git diff --check` passed.
- `scripts/install-agent-skills.sh --check` passed with six existing symlinks
  present and pointing to `/private/tmp/recme-shared-agent-skills`.
