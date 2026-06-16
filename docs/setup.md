# Setup

Last updated: 2026-06-15

## Requirements

- macOS with Xcode installed.
- iOS Simulator runtime available.
- XcodeGen installed and available as `xcodegen`.
- GitHub access to `joelipshutz/wander`.

## Clone

```bash
git clone git@github.com:joelipshutz/wander.git
cd wander
```

If you are working in Joe's local workspace, the repo path is:

```bash
/Users/joelipshutz/Developer/Wander (nametbd)
```

## Generate Project

`project.yml` is the source of truth for the Xcode project.

For local live-auth builds, create the ignored auth config first:

```bash
set -a
source /Users/joelipshutz/.openclaw/workspace/.env.keys
set +a
cat > Wander/Config/LocalAuth.xcconfig <<EOF
WANDER_CLERK_PUBLISHABLE_KEY = $WANDER_CLERK_PUBLISHABLE_KEY
WANDER_SUPABASE_PUBLISHABLE_KEY = $WANDER_SUPABASE_ANON_KEY
EOF
```

```bash
xcodegen generate
```

Run this after changing file membership, targets, or generated project settings.

## Open In Xcode

Open:

```text
Wander.xcodeproj
```

Do not commit incidental signing/team changes from Xcode unless intentional.

## Build

```bash
xcodebuild build -project Wander.xcodeproj -scheme Wander -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

For a live Clerk/Supabase simulator smoke test, make sure `Wander/Config/LocalAuth.xcconfig` exists, then build normally:

```bash
xcodebuild build \
  -project Wander.xcodeproj \
  -scheme Wander \
  -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' \
  -derivedDataPath DerivedData
```

`WANDER_SUPABASE_URL` and `WANDER_CLERK_FRONTEND_API` are already checked in as non-secret project defaults for the Wander dev project.

Do not commit `Wander/Config/LocalAuth.xcconfig`; it is intentionally ignored.

## Test

```bash
xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

Known good focused regression result on 2026-06-15:

```text
BoundaryImportTests.testClerkAndSupabaseImportsStayBehindBoundaries(): passed
```

Run the full suite before merging implementation branches. As of this update, the previous red boundary-import path-normalization failure is fixed on `main`.

If CoreSimulator or Swift plugin server errors happen in a sandbox, rerun from a normal terminal or with approved elevated access.

## Fixture Mode

Default app launches use an empty local store. Do not seed demo people or places for normal simulator, device, or TestFlight builds.

Use this launch argument only for screenshots, local demos, or tests that intentionally need Joe/Maya/Ryan fixture data:

```text
-WanderUseDemoFixtures
```

## Supabase

The new Wander Supabase project was created on 2026-06-02.

- Project name: `wander`
- Project ref: `rugmtlgufrhlxwfkumhw`
- Region: `us-west-2`

Local-only credentials are stored in:

```text
/Users/joelipshutz/.openclaw/workspace/.env.keys
```

Useful commands:

```bash
npx supabase projects list
npx supabase migration list --linked
npx supabase db push --linked
npx supabase functions deploy clerk-profile-webhook --project-ref "$WANDER_SUPABASE_PROJECT_REF" --no-verify-jwt --use-api
```

Local Supabase requires Docker. Docker is not currently available in this environment, so the local stack commands are blocked until Docker/OrbStack/Colima is installed and running:

```bash
npx supabase start
npx supabase db reset
npx supabase test db supabase/tests/rls_visibility.sql
```

The hosted migrations and Clerk profile webhook have been pushed/deployed. The latest hosted migration is `20260604185000_save_own_place.sql`, which adds the direct signed-in own-place save RPC used by the iOS add flow. The current SQL tests passed against hosted Postgres through a temporary Node `pg` runner because the Supabase CLI pgTAP runner still requires Docker.

The `extraction-worker` Edge Function was last deployed from branch `codex/m6-roadmap-next` on 2026-06-15. It supports coordinate-backed Google Maps, Apple Maps, and generic coordinate metadata links while leaving unsupported/photo/social sources as drafts/manual rescue.

Current hosted SQL test status:

```text
supabase/tests/rls_visibility.sql: 15 assertions, 0 failures
supabase/tests/clerk_profile_mirroring.sql: 14 assertions, 0 failures
```

## Clerk

The new Wander Clerk application was created on 2026-06-02.

- App name: `Wander`
- App id: `app_3Eb3JbpbMDjOA2qKUCqfsZwfct9`
- Development instance id: `ins_3Eb3Je6FO3qfUDIt5n3aTHMxYN1`
- Development domain: `growing-pheasant-22.clerk.accounts.dev`

Local-only Clerk env values are stored in `/Users/joelipshutz/.openclaw/workspace/.env.keys`.

The Clerk development instance has session token claims patched for Supabase:

```json
{"role":"authenticated"}
```

The repo is linked to the Clerk app through the Clerk CLI remote link:

```bash
npx clerk whoami --json
```

Clerk user profile mirroring is wired through Svix:

- Supabase Edge Function: `clerk-profile-webhook`
- Function URL: `https://rugmtlgufrhlxwfkumhw.supabase.co/functions/v1/clerk-profile-webhook`
- Clerk/Svix endpoint id: `ep_3Eb5WlmjQlDav83RHa3hWxp07wd`
- The endpoint currently listens to all Clerk events; the function handles only `user.created`, `user.updated`, and `user.deleted`.

The Svix signing secret and function service credentials are stored local-only and in Supabase Edge Function secrets. Do not commit them.

Live Clerk/Supabase smoke status as of 2026-06-04:

- Clerk disposable user creation works.
- Clerk profile mirroring through Svix -> Edge Function -> Supabase works.
- Clerk default session token includes `sub`, `role=authenticated`, `iss=https://growing-pheasant-22.clerk.accounts.dev`, `alg=RS256`, and a `kid` present in Clerk JWKS.
- Hosted Supabase accepts the Clerk token after adding the Clerk provider connection with domain `https://growing-pheasant-22.clerk.accounts.dev`.
- Full hosted API smoke passed for profile search, follow, visible places, social save, block, unblock, and unfollow.

## Visual QA

For UI work:

1. Run the app in the simulator.
2. Capture screenshots for Map, Add, Discover, Profile, and Settings.
3. Test at least the active iPhone target and one smaller iPhone target.
4. Verify safe areas, bottom nav, sheets, search/chips, text fitting, and home indicator spacing.

Current known visual failure:

- Map screen is undersized/letterboxed and the controls are too large/crowded on the simulator screenshot Joe shared on 2026-06-01.

## TestFlight

Current status as of 2026-06-16:

- Signed archive succeeds locally for `com.grayline.wander`.
- App Store Connect app record exists for bundle id `com.grayline.wander`.
- Builds `0.1 (1)` through `0.1 (27)` uploaded successfully and began App Store Connect processing. Build `0.1 (27)` packages the expanded map place detail sheet from PR #9.
- Public TestFlight group `Wander Alpha` exists with public link enabled and no custom tester cap: `https://testflight.apple.com/join/knEhRa6t`.
- Build `0.1 (5)` is attached to the public group. Export compliance is set to `usesNonExemptEncryption=false`.
- Build `0.1 (5)` passed external TestFlight review.
- Build `0.1 (6)` is attached to `Wander Alpha`, export compliance is set to `usesNonExemptEncryption=false`, and external TestFlight review is `APPROVED`.
- Build `0.1 (7)` is attached to `Wander Alpha`, export compliance is set to `usesNonExemptEncryption=false`, and external TestFlight review is `APPROVED`.
- Build `0.1 (8)` is attached to `Wander Alpha`, export compliance is set to `usesNonExemptEncryption=false`, and external TestFlight review is `APPROVED`.
- Build `0.1 (9)` is attached to `Wander Alpha`, export compliance is set to `usesNonExemptEncryption=false`, and external TestFlight review is `APPROVED`.
- Build `0.1 (10)` is attached to `Wander Alpha`, export compliance is set to `usesNonExemptEncryption=false`, and external TestFlight review is `APPROVED`.
- Build `0.1 (11)` is attached to `Wander Alpha`, export compliance is set to `usesNonExemptEncryption=false`, and external TestFlight review is `APPROVED`.
- Build `0.1 (15)` is attached to `Wander Alpha`, export compliance is set to `usesNonExemptEncryption=false`, and external TestFlight review is `APPROVED`.
- Build `0.1 (16)` is attached to `Wander Alpha`, export compliance is set to `usesNonExemptEncryption=false`, and external TestFlight review is `APPROVED`.
- Build `0.1 (20)` is attached to `Wander Alpha`, export compliance is set to `usesNonExemptEncryption=false`, and external TestFlight review is `APPROVED`.
- Build `0.1 (21)` is attached to `Wander Alpha`, export compliance is set to `usesNonExemptEncryption=false`, and external TestFlight review is `APPROVED`.
- Build `0.1 (22)` is attached to `Wander Alpha`, export compliance is set to `usesNonExemptEncryption=false`, and external TestFlight review is `APPROVED`.
- Build `0.1 (23)` is attached to `Wander Alpha`, export compliance is set to `usesNonExemptEncryption=false`, and external TestFlight review is `APPROVED`.
- Build `0.1 (24)` is attached to `Wander Alpha`, export compliance is set to `usesNonExemptEncryption=false`, and external TestFlight review is `APPROVED`.
- Build `0.1 (25)` is attached to `Wander Alpha`, export compliance is set to `usesNonExemptEncryption=false`, and external TestFlight review is `APPROVED`.
- Build `0.1 (26)` is attached to `Wander Alpha`, export compliance is set to `usesNonExemptEncryption=false`, and external TestFlight review is `APPROVED`.
- Build `0.1 (27)` is attached to `Wander Alpha`, export compliance is set to `usesNonExemptEncryption=false`, and external TestFlight review is `APPROVED`.
- Increment `CURRENT_PROJECT_VERSION` in `project.yml` before each additional TestFlight upload, then run `xcodegen generate`.
- If Xcode Accounts cannot be used for upload, pass the local App Store Connect API key to `xcodebuild -exportArchive` with `-authenticationKeyPath`, `-authenticationKeyID`, and `-authenticationKeyIssuerID`.
- After `xcodebuild -exportArchive` reports `Uploaded Wander`, run `node scripts/testflight-release.mjs`. It waits for the uploaded build to become `VALID`, sets export compliance, attaches the build to `Wander Alpha`, submits external beta review, and prints the final TestFlight summary. Use `--dry-run` before upload to verify the resolved build number and App Store Connect config.

## Main Files To Read First

```text
AGENTS.md
README.md
docs/codex-handoff.md
docs/roadmap.md
docs/decisions.md
docs/open-questions.md
docs/setup.md
docs/agent-log.md
docs/specs/wander-ios-product-spec.md
docs/plans/2026-06-01-wander-ios-eng-plan.md
DESIGN.md
```

## Common Commands

Status:

```bash
git status --short --branch
```

Recent commits:

```bash
git log --oneline -5
```

Verify remote main:

```bash
git ls-remote origin refs/heads/main
```
