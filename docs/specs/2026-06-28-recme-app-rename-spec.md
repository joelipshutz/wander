# rec.me App Rename Spec

Date: 2026-06-28
Status: user-facing and TestFlight cutover complete; production App Store submission pending privacy/support URLs and final listing assets
Owner: Codex plan-eng-review pass

## Goal

Rename the app from Wander to `rec.me` everywhere users, testers, and external product surfaces see the name, without creating unnecessary churn in stable technical identifiers.

The first implementation should make the installed app, permission prompts, in-app copy, release notes, and living docs feel consistently like `rec.me`. Internal names can remain `Wander` where changing them would create migration, release, or collaboration risk.

Canonical casing:

- Use `rec.me` for user-facing app name, App Store/TestFlight copy, Slack release notes, docs written for testers, and in-app strings.
- Avoid `REC.me`, `Rec.me`, and `REC ME` unless a future brand decision explicitly changes casing.
- Use transitional phrasing as needed in developer docs: `rec.me, formerly Wander`.

## Priority Summary

| Priority | Scope | Recommendation |
| --- | --- | --- |
| P0 | User-facing app identity | Change installed app display name and visible app strings from Wander to `rec.me`. |
| P0 | Permission and system copy | Update location permission copy and any auth/save error copy users can see. |
| P0 | App icon | Replace the letter-based Wander icon with a text-free rec.me map/save/social mark. |
| P0 | Rename safety tests | Add focused tests or config assertions so app display name and user-facing brand copy cannot regress silently. |
| P1 | Release and tester surfaces | Rename App Store/TestFlight-facing text, Slack release note templates, and TestFlight group naming once external state is ready. |
| P1 | Living docs | Update current product docs, README, setup, and agent guidance to use `rec.me, formerly Wander`. |
| P2 | External service display labels | Rename Clerk, Supabase, PostHog, and App Store Connect display labels where safe, while keeping IDs stable. |
| P2 | Repo/project identity | Consider GitHub repo, Xcode scheme, target, and folder rename only after active PRs clear. |
| P3 | Internal Swift/env/db identifiers | Defer broad `Wander*` type, module, env var, logger, and database identifier renames. |

## What Already Exists

- Product-level repo guidance already says: `Rec.me, formerly Wander, is a native iOS social map...`; this should be corrected to canonical `rec.me`.
- The XcodeGen source of truth is `project.yml`.
- The current application target, scheme, source folder, test target, and binary are all named `Wander`.
- `Wander/Resources/Info.plist` currently has `CFBundleName = $(PRODUCT_NAME)` and no explicit `CFBundleDisplayName`.
- The bundle id is `com.grayline.wander`.
- The TestFlight helper defaults to bundle id `com.grayline.wander` and group name `Wander Alpha`.
- Several user-visible strings still say `Wander`; several newer strings already say `rec.me`.
- Build configuration tests already inspect `project.yml`, `Wander.xcodeproj/project.pbxproj`, and `Info.plist`, so they are the right place to add rename guardrails.

## P0 Implementation Plan

### 1. App Display Name

Use `CFBundleDisplayName = rec.me` for the installed app label.

Do not rename `PRODUCT_NAME`, scheme, target, executable, source folder, or test host in the first pass. Keeping those as `Wander` avoids unnecessary Xcode project churn and avoids breaking test host paths like:

```text
$(BUILT_PRODUCTS_DIR)/Wander.app/Wander
```

Files:

- `project.yml`
- `Wander/Resources/Info.plist`
- `Wander.xcodeproj/project.pbxproj` after `xcodegen generate`
- `WanderTests/BuildConfigurationTests.swift`

Expected test assertions:

- `Info.plist` declares `CFBundleDisplayName` as `rec.me`.
- `CFBundleName` can remain `$(PRODUCT_NAME)`.
- `PRODUCT_BUNDLE_IDENTIFIER` remains `com.grayline.wander`.

### 2. User-Facing App Copy

Update visible strings that mention Wander:

- `Wander/Resources/Info.plist`
  - `NSCameraUsageDescription`
  - `NSLocationWhenInUseUsageDescription`
- `project.yml`
  - mirrored location usage description
- `Wander/Services/Auth/AuthSessionProviding.swift`
  - social save account gate copy
- `Wander/Services/MapKitPlaceResolver.swift`
  - location disabled error copy
- `Wander/Features/Map/MapScreen.swift`
  - `saved on Wander` fallback copy
- `Wander/Features/Discover/DiscoverScreen.swift`
  - normalize any member search casing to `rec.me`
- `Wander/Features/Settings/SettingsScreen.swift`
  - normalize privacy/location helper copy to `rec.me`

If the implementation touches more than a few strings, add a tiny brand constant instead of scattering literals:

```swift
enum AppBrand {
    static let displayName = "rec.me"
}
```

Keep this constant app-facing only. Do not use it to rename bundle ids or backend config keys.

### 3. Focused Rename Tests

Add or extend tests in `WanderTests/BuildConfigurationTests.swift`:

- `testInfoPlistDeclaresDisplayName`
- `testProjectKeepsStableBundleIdentifier`
- `testLocationUsageDescriptionUsesRecmeBrand`

Where copy is centralized behind `AppBrand`, add a simple test that confirms the canonical value is exactly `rec.me`.

Avoid brittle full-UI snapshot tests for this rename. A config/copy test is enough to catch the likely regression.

### 4. App Icon

Replace the legacy `W` icon with a full-bleed, text-free mark built around the product's actual behavior:

- a location pin for places;
- a bookmark cutout for remembering/saving;
- a small blue orbit dot for the trusted social layer;
- a clear terracotta lower-right field that keeps the mark legible at small sizes.

Keep the existing terracotta, cream, espresso, and sky-blue palette. Generate every raster rendition referenced by `AppIcon.appiconset/Contents.json`, require exact dimensions, and remove alpha from every file. Do not bake rounded corners into the artwork; iOS applies the system mask.

The approved icon has no folded map/page corner, pencil, road lines, or secondary
lower-right object. The durable visual contract and rendition workflow live in
`docs/brand/recme-app-icon.md`.

### 5. Manual QA

Run the normal simulator build/test path after implementation:

```bash
xcodegen generate
xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

Manual checks:

- Fresh simulator install shows app label `rec.me` on the home screen.
- First location prompt says `rec.me`, not Wander.
- Signed-out save/auth copy says `rec.me`.
- Map fallback social copy says `saved on rec.me`.
- Discover and Settings do not show inconsistent brand casing.

## P1 Release And Tester Surfaces

### TestFlight And App Store Connect

Recommended:

- Keep bundle id `com.grayline.wander`.
- Keep current TestFlight public link unless Apple requires a new one for a group/name change.
- Rename the public beta group from `Wander Alpha` to `rec.me Alpha` in App Store Connect when convenient.
- Only after the group exists under the new name, update `scripts/testflight-release.mjs` default `groupName`.
- Update `docs/setup.md` and `AGENTS.md` release instructions to mention `rec.me Alpha`.
- Update tester-facing "What to Test" and Slack release note language to say `rec.me`.

Do not change `scripts/testflight-release.mjs` before the App Store Connect beta group is renamed or confirmed. The helper currently fails hard when the configured group name is missing.

### App Store Listing

Update App Store Connect metadata when the product listing is ready:

- App name: `rec.me`
- Subtitle and description: use trusted social map positioning, not generic travel/list language.
- Support/privacy URLs if they currently mention Wander.
- Screenshots if visible text or device labels mention Wander.

This can ship after P0 if the immediate goal is TestFlight consistency.

## P1 Living Docs

Update current, forward-looking docs:

- `README.md`
- `DESIGN.md`
- `AGENTS.md`
- `docs/setup.md`
- `docs/specs/wander-ios-product-spec.md`
- current roadmap/plan docs that a new agent will read first

Do not mass-rewrite historical docs:

- `docs/agent-log.md` past entries
- old reviews and implementation plans
- old TestFlight build records
- source notes that intentionally describe prior Wander-era decisions

Historical docs should remain accurate to when they were written. Add one current transition note instead of rewriting history.

## P2 Repo And Project Identity

These changes are optional and should wait for a quiet branch window:

- Rename GitHub repo from `Wander` to `rec.me` or another canonical repo slug.
- Rename local source folder from `Wander/` to `RecMe/` or similar.
- Rename Xcode project, scheme, target, test target, and generated app product.
- Rename Swift module imports from `Wander`.
- Rename `WanderTests`.
- Rename launch args such as `-WanderInitialTab`.

Recommendation: defer. The cost is high, the value is mostly developer aesthetics, and active worktrees/PRs make this a conflict multiplier.

If done later, do it as a standalone migration PR:

1. Freeze other Xcode project edits.
2. Rename through `project.yml`.
3. Run `xcodegen generate`.
4. Update test host and script paths.
5. Run full simulator tests.
6. Update agent docs with the new commands.

## P2 External Service Display Labels

Safe-to-change labels:

- Clerk application display name
- Supabase project display label
- PostHog project display label
- App Store Connect visible app name
- Slack channel topic/pinned TestFlight text

Keep these stable unless there is a separate migration plan:

- `WANDER_*` env var names
- Supabase project ref and project id
- Database table/function names if any include Wander
- Clerk/Supabase issuer/audience contracts
- Bundle id `com.grayline.wander`
- Keychain access groups, if any are introduced later

If env vars are ever renamed, the app should dual-read old and new names for at least one release.

## P3 Internal Code Identifiers

Do not change these in the rename implementation:

- `WanderStore`
- `WanderLocalStore`
- `WanderTheme`
- `WanderDebugLog`
- `WanderSupabaseClient`
- `WanderBackendConfiguration`
- `WanderApp`
- `WanderRootView`
- source folder `Wander/`
- logger subsystem `com.grayline.wander`

These are internal names. Renaming them now increases merge risk without improving tester experience.

## Architecture Review

The rename crosses four identity layers. They should not be treated as one global search-and-replace.

```text
User-visible brand
  -> CFBundleDisplayName
  -> permission prompts
  -> visible in-app strings
  -> TestFlight/App Store/Slack copy

Release identity
  -> App Store Connect app record
  -> TestFlight beta group
  -> public TestFlight link
  -> release helper defaults

Developer identity
  -> Xcode project/scheme/target
  -> repo name and local folder
  -> Swift module and tests
  -> scripts and docs

Stable platform identity
  -> bundle id
  -> env vars
  -> Supabase project/ref/config
  -> Clerk/PostHog keys
  -> keychain/install continuity
```

The correct first move is to rename the first layer, update the second layer where external state is ready, document the third layer, and leave the fourth layer stable.

## Test Review

Coverage should focus on configuration contracts and high-risk user-facing strings.

```text
project.yml
  -> xcodegen generate
    -> Info.plist
      -> built app display name

visible copy
  -> AppBrand or direct literals
    -> focused unit/config tests
      -> simulator manual QA

release helper
  -> App Store Connect group name
    -> dry-run after external group rename
```

Required before implementation PR merge:

- `git diff --check`
- `xcodegen generate`
- Full documented `xcodebuild test`
- Manual simulator app-label check

Required before TestFlight:

- Build number bump only when explicitly releasing.
- App Store Connect/TestFlight helper dry-run if group naming changes.
- Slack release note says the app is now `rec.me` and calls out that the bundle/account continuity is unchanged.

## Performance Review

The P0 rename has no meaningful runtime performance impact.

The main performance-like risk is release pipeline disruption:

- Product name or executable rename can break test host paths.
- Bundle id rename can create a separate installed app and lose existing signed-in/local state.
- TestFlight group rename can break automated attach if the script points to a group that does not exist.

Avoid those in P0.

## Failure Modes

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Changing bundle id | Existing testers get a new app install and may lose continuity. | Keep `com.grayline.wander`. |
| Renaming product/executable early | Unit tests and archive scripts can break. | Use `CFBundleDisplayName` first. |
| Blind global replacement | Historical docs, env keys, and code contracts get corrupted. | Use targeted file list and tests. |
| Inconsistent casing | Testers see `rec.me`, `REC.me`, and Wander mixed together. | Canonical casing test plus targeted grep. |
| TestFlight group mismatch | Release helper cannot attach builds. | Rename group externally before changing script default. |
| Repo rename during active branches | Worktrees and open PRs conflict or lose remote tracking. | Defer until active work clears. |

## Not In Scope For First Implementation

- Bundle id migration.
- Swift module, target, scheme, or source folder rename.
- GitHub repo rename.
- Env var rename.
- Supabase database/project ref rename.
- Clerk issuer/audience changes.
- Rewriting historical logs and old plans.
- Broader logo/wordmark or visual identity work beyond the new app icon.
- Marketing website/domain work beyond app-store-facing copy.

## Suggested Work Split

This can be parallelized if needed:

- Lane A: P0 app config, visible strings, tests.
- Lane B: living docs and release docs.
- Lane C: external service display labels and TestFlight helper, after App Store Connect state is ready.

Merge order:

1. Lane A.
2. Lane B.
3. Lane C only after the beta group/app metadata exists under the new name.

## Open Decisions

| Decision | Recommendation | Owner |
| --- | --- | --- |
| Exact public brand casing | `rec.me` | Decided by Joe on 2026-06-28. |
| Rename TestFlight group now or later | Later, unless someone is already in App Store Connect. | Joe/Ryan/release owner |
| Rename GitHub repo | Defer until active PRs clear. | Joe/Ryan |
| Add app icon/logo changes | Yes for the app icon: replace the legacy `W` with the map/save/social mark. Defer broader logo/wordmark work. | Decided by Joe on 2026-07-12. |
| Keep `Wander` internal names | Yes for P0/P1. | Engineering |

## GSTACK REVIEW REPORT

| Review Area | Status | Notes |
| --- | --- | --- |
| Architecture | pass with scope control | Treat brand, release, developer, and platform identity as separate layers. |
| Code quality | pass with targeted implementation | Avoid global replacement; use `CFBundleDisplayName` and focused string updates. |
| Tests | action required in implementation | Add config/copy assertions before merge. |
| Performance | pass | No runtime impact; release pipeline risk is the real concern. |
| Product clarity | pass with casing decision | Canonical user-facing name is `rec.me`. |

No blocking unanswered engineering questions remain for the spec. Implementation should proceed as the P0 slice unless Joe or Ryan explicitly asks for repo/project renames in the same release.
