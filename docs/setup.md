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

The tracked `Wander/Config/Auth.xcconfig` contains the public Clerk publishable key
and Supabase anon key for the current alpha backend. These are client-side
publishable values and are required for simulator, device, and TestFlight builds.

If you need to point a local build at a different Clerk/Supabase project, create
the ignored override config:

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

For a live Clerk/Supabase simulator smoke test against the default alpha backend,
build normally:

```bash
xcodebuild build \
  -project Wander.xcodeproj \
  -scheme Wander \
  -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' \
  -derivedDataPath DerivedData
```

`WANDER_SUPABASE_URL`, `WANDER_CLERK_FRONTEND_API`, and the public client keys are
checked in as non-secret project defaults for the Wander alpha project.

Do not commit `Wander/Config/LocalAuth.xcconfig`; it is intentionally ignored and
only for local overrides.

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

The `extraction-worker` can optionally enrich extracted candidate categories through the shared server-side AI provider layer. The `parse-discover-query` Edge Function uses the same layer for Discover natural-language search parsing. Provider keys must stay server-side as Supabase Edge Function secrets, never in the iOS app bundle or tracked config:

```bash
npx supabase secrets set OPENAI_API_KEY=<openai-project-key> --project-ref "$WANDER_SUPABASE_PROJECT_REF"
```

Provider/runtime knobs:

- `WANDER_AI_PROVIDER`: optional provider selector; defaults to `openai`. Supported values: `openai`, `anthropic`, `openai-compatible`.
- `WANDER_AI_API_KEY`: optional generic provider key. For OpenAI, existing `OPENAI_API_KEY` and `WANDER_OPENAI_API_KEY` still work.
- `ANTHROPIC_API_KEY` or `WANDER_ANTHROPIC_API_KEY`: required when `WANDER_AI_PROVIDER=anthropic`.
- `WANDER_AI_BASE_URL`: required for `openai-compatible` endpoints, for example a local or hosted `/v1` compatible API. OpenAI-compatible endpoints may omit an API key if the server is local/private and does not require auth.
- `WANDER_AI_MODEL`: optional generic model override.
- `WANDER_AI_DISCOVER_MODEL`: model for Discover parsing. OpenAI still falls back to `WANDER_OPENAI_DISCOVER_MODEL`, then `gpt-5.4-nano`.
- `WANDER_AI_CATEGORY_MODEL`: model for extraction category classification. OpenAI still falls back to `WANDER_OPENAI_CATEGORY_MODEL`, then `gpt-5.4-nano`.
- `WANDER_AI_DISCOVER_TIMEOUT_MS`, `WANDER_AI_CATEGORY_TIMEOUT_MS`, or `WANDER_AI_TIMEOUT_MS`: optional timeout overrides; defaults to `3500` and caps at `10000`. Legacy `WANDER_OPENAI_DISCOVER_TIMEOUT_MS` and `WANDER_OPENAI_CATEGORY_TIMEOUT_MS` still work.
- `WANDER_AI_CATEGORY_MODE`: optional mode; defaults to `ambiguous`, which calls the AI provider only when deterministic inference falls back to `place`. Set to `all` to classify every coordinate-backed extraction candidate. Legacy `WANDER_OPENAI_CATEGORY_MODE` still works.

The worker sends only the approved place classification payload to the selected provider: place name, address/locality/region/country, source provider, source type, and current inferred category. OpenAI requests set `store: false`; if provider config is missing or the call fails, extraction falls back to deterministic category inference.

The `parse-discover-query` Edge Function sends only the raw query plus the fixed allowed filter schema to the selected provider. OpenAI requests set `store: false`; the iOS app falls back to deterministic local parsing if the function is missing, provider config is missing, or the call fails.

```bash
npx supabase functions deploy parse-discover-query --project-ref "$WANDER_SUPABASE_PROJECT_REF" --use-api
npx supabase functions deploy extraction-worker --project-ref "$WANDER_SUPABASE_PROJECT_REF" --use-api
```

### Google Places venue photos

REC-82 loads one representative venue photo only when a signed-in user opens a place profile. The iOS app calls the authenticated `place-photo` Edge Function, which validates the Clerk/Supabase bearer token through the existing `current_profile` PostgREST contract, matches the place by provider id or name plus coordinates, requests Google's first returned usable photo, and returns a short-lived image URL plus the required Google Maps/author/source attribution. Google does not expose a storefront/signage label or usage count, so this is a best available default rather than a guaranteed exterior photo. The app falls back to its existing MapKit header when the provider is unavailable or cannot make a safe match.

Google Places currently includes separate 1,000-event monthly free caps for Text Search Enterprise and Place Details Photos. Most Rec.me places originate in MapKit, so the first photo open can consume one event from each SKU; requests above either cap are billable, and Text Search is the more expensive call. The Google Cloud project must have billing enabled. Before setting the secret, configure Places API (New), set low method quotas plus budget alerts appropriate for the alpha, and create a server-side key restricted to Places API. Yelp is not a free commercial fallback: its free access is a 30-day evaluation trial.

Keep the key server-side and deploy the function:

```bash
npx supabase secrets set WANDER_GOOGLE_PLACES_API_KEY=<restricted-server-key> --project-ref "$WANDER_SUPABASE_PROJECT_REF"
npx supabase functions deploy place-photo --project-ref "$WANDER_SUPABASE_PROJECT_REF" --use-api
```

Do not store Google photo names, image bytes, or returned image URLs in SwiftData, Supabase, fixtures, or analytics. Google Place IDs may be retained. The UI must keep the Google Maps attribution, photo author attribution when present, and source-photo link visible with the image.

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
- When creating the export options plist for App Store Connect upload, set `manageAppVersionAndBuildNumber` to `false` so Xcode cannot silently upload a different build number than the archive.
- If Xcode Accounts cannot be used for upload, pass the local App Store Connect API key to `xcodebuild -exportArchive` with `-authenticationKeyPath`, `-authenticationKeyID`, and `-authenticationKeyIssuerID`.
- After `xcodebuild -exportArchive` reports `Uploaded Wander`, run `node scripts/testflight-release.mjs --archive-path <archive>`. It waits for the uploaded build to become `VALID`, sets export compliance, attaches the build to `Wander Alpha`, submits external beta review, and prints the final TestFlight summary. Passing `--archive-path` lets the helper detect Xcode upload build-number drift before attaching the wrong TestFlight build. Use `--dry-run` before upload to verify the resolved build number and App Store Connect config.

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
