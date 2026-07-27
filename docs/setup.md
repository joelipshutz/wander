# Setup

Last updated: 2026-07-24

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

## Widget And Share Extensions

The app ships four Home Screen widget configurations across two extensions.
`WanderWidgets` (`com.grayline.wander.widgets`) hosts Quick Capture, Search, and
Activity Calendar. `WanderNearbyWidgets`
(`com.grayline.wander.nearbywidgets`) separately hosts the system-large Nearby
Rich Visit widget because only that extension declares `NSWidgetWantsLocation`.
The app and both extensions share App Group
`group.com.grayline.wander.shared`.

`WanderShareExtension` is one app-independent Share Extension with bundle id
`com.grayline.wander.share`. It appears in any host app that supplies a supported
URL, text selection, or file through the iOS share sheet. The extension detects
Google Maps, Instagram, and TikTok from the shared URL; Apple Maps, Yelp, Resy,
OpenTable, Safari, Messages, Notes, and other sources enter through the generic
text/link route. There are not separate extension targets for each provider.

The Share Extension writes a bounded, versioned envelope to the same App Group
and exits. It does not authenticate, call social APIs, resolve places, or upload
content. The containing app drains the envelope idempotently on launch/foreground,
then the existing Import Review flow performs matching. Text is limited to
256 KB, individual files to 10 MB, the complete share to 25 MB, and each delivery
to 20 attachments. Supported files are CSV, JSON, TXT, Markdown, and RTF.
Pending envelopes expire after seven days and App Group import files are excluded
from device backup.

The App Group contains three intentionally narrow payloads. The host app writes
a redacted, aggregate-only calendar JSON snapshot containing calendar layout
and daily Been counts. The backward-compatible schema currently retains
zero-valued Wanna fields; do not repopulate them. Do not add place names, notes,
precise locations, user identities, or raw place records to that calendar
payload. The location-enabled widget uses a separate bounded nearby-place cache
described below. For sharing, the extension writes only the user-selected link,
text, or supported file into its bounded import inbox. Keep all three privacy
boundaries intact when changing any payload. The calendar widget file lives
under the App Group's
`Library/Caches` directory, is excluded from backup after every atomic write,
and is cleared immediately when the authenticated identity becomes unavailable
or changes.

WidgetKit does not offer an inline keyboard. Tapping the Search widget opens Map
with the in-app search focused; text entry and result population happen in the
app.

On iOS 18 or later, the primary widget extension also contributes one system
control named **Check-in** with a plus icon. It opens rec.me's existing I'm
Here Now nearby place picker; it does not duplicate or replace the
accessory-circular control already available for the bottom Lock Screen slots.
To assign the new control to a supported iPhone's Action Button:

1. Build and run the **Wander** scheme once so iOS discovers the embedded widget
   extension and its controls.
2. Open **Settings → Action Button**, swipe to **Controls**, and choose
   **Choose a Control**.
3. Find rec.me and select **Check-in**.
4. Hold the Action Button. Verify rec.me opens the nearby check-in flow. If the
   app requires sign-in or is still restoring the session, finish that step and
   verify the check-in flow opens afterward.

The same control can also appear in Control Center and in a configurable bottom
Lock Screen control slot. Those are alternative placements for the same iOS 18
control; the existing rec.me bottom Lock Screen widget remains a separate
WidgetKit configuration.

The Nearby Rich Visit extension uses When In Use location only. The host app
must receive that permission before the widget can request location, and iOS may
show a separate prompt asking whether the widget may use location. Its bounded
App Group cache contains the five visible MapKit candidates plus recent routing
fallbacks, including place names and coordinates needed to prefill the Rich
Visit form. The file is excluded from backup, exact distances stop rendering
after 30 minutes, and the whole result set stops rendering after 24 hours. The
widget asks WidgetKit for a 15-minute refresh and a five-minute retry after a
transient failure, but iOS ultimately schedules and budgets those reloads.
Its bottom-left App Intent refresh requests a new widget-authorized location and
MapKit search without opening the app, briefly displays `Refreshing…`, and
forces the minute timestamp forward even if the same five places are returned.
`See all` and taps outside an individual place row open the existing I'm Here
Now nearby list; individual rows continue into the selected Rich Visit form.

### First-time physical-device setup

The checked-in entitlements are intentional. Errors such as `No Accounts`,
`Unknown Name (Y7TVK75RZ8)`, `profile doesn't include the App Groups
capability`, or `No profiles for com.grayline.wander.widgets` /
`com.grayline.wander.nearbywidgets` / `com.grayline.wander.share` mean the Mac
or Apple Developer account is not provisioned yet; removing the entitlements
only hides the problem and breaks widget or share-extension updates.

1. In Xcode, open **Xcode → Settings → Accounts**, add the Apple Account that is
   a member of team `Y7TVK75RZ8`, and complete any authentication prompts.
   A Personal Team is not a substitute for access to the existing rec.me bundle
   identifiers. If the team still does not appear, an Account Holder or Admin
   must add the developer to the organization and grant Certificates,
   Identifiers & Profiles access. In **Manage Certificates**, create an Apple
   Development certificate if the account does not already have one available
   on this Mac.
2. In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list),
   register App Group `group.com.grayline.wander.shared` if it does not already
   exist.
3. Open the explicit App ID `com.grayline.wander`, enable **App Groups**,
   configure it, and assign `group.com.grayline.wander.shared`.
4. Register the explicit iOS App ID `com.grayline.wander.widgets` if it does not
   exist. Enable **App Groups** on it and assign the same group.
5. Register the explicit iOS App ID `com.grayline.wander.nearbywidgets` if it
   does not exist. Enable **App Groups** on it and assign the same group.
6. Register the explicit iOS App ID `com.grayline.wander.share` if it does not
   exist. Enable **App Groups** on it and assign the same group.
7. Changing any of these App IDs invalidates older provisioning profiles. With
   automatic signing, return to Xcode and let it request replacements. With
   manual signing, regenerate and download an iOS App Development profile for
   each App ID, including the connected device and the developer's Apple
   Development certificate.
8. In the **Wander** target's **Signing & Capabilities** pane, select team
   `Y7TVK75RZ8`, keep **Automatically manage signing** enabled, and verify that
   `group.com.grayline.wander.shared` is checked under App Groups.
9. Repeat the same team, automatic-signing, and App Group checks for both
   **WanderWidgets** and **WanderNearbyWidgets**. Their bundle identifiers must
   remain `com.grayline.wander.widgets` and
   `com.grayline.wander.nearbywidgets`.
10. Repeat those checks for **WanderShareExtension**. Its bundle identifier must
   remain `com.grayline.wander.share`.
11. Re-select the connected iPhone and build. Automatic signing should register
   the device and create/download all four development profiles. If Xcode continues
   to reuse the old host profile, use the Accounts pane to download profiles or
   quit Xcode and move only the stale host/widget/share profile to a backup folder
   from `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` (current
   Xcode) or `~/Library/MobileDevice/Provisioning Profiles/` (older Xcode),
   then reopen Xcode and build again.
12. On the iPhone, trust the Mac when prompted and enable **Settings → Privacy &
   Security → Developer Mode** if Xcode requests it.

For a code-only test while portal access is being fixed, select an iPhone
Simulator instead of a physical iPhone. The app, all four widgets, and the
Share Extension can be built and exercised in Simulator without creating device
provisioning profiles.

### Testing the Share Extension

1. Build and run the **Wander** scheme once so rec.me and its embedded Share
   Extension are installed.
2. In Safari or Notes, share a public place URL or selected text. On a physical
   device, also test the native share sheets in Google Maps, Apple Maps,
   Instagram, and TikTok.
3. If **Save to rec.me** is not visible, scroll to **More** in the share sheet,
   enable it under **Edit**, and optionally favorite it.
4. Select **Save to rec.me**, confirm the extension recognizes the content, and
   tap **Add to rec.me**.
5. Open rec.me. Its foreground drain should show **Shared places added**. Tap
   **Review** and verify the item appears in Import Review with the correct
   source badge.
6. Repeat the same URL once to verify duplicate delivery does not create another
   batch. Test a `Saved Places.csv` or JSON file from Files and verify private,
   deleted, or unsupported social links enter the explicit needs-help state
   instead of fabricating a place.

The simulator is sufficient for Safari, Notes, Files, App Group delivery, and
Import Review. Real Google Maps, Instagram, and TikTok host behavior must be
accepted on a physical iPhone because those apps may provide different
`NSItemProvider` payloads than their websites.

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

REC-82 resolves one preferred image for both the full place-profile header and collapsed map card. The iOS app first calls the authenticated `place-photo` Edge Function, which validates the Clerk/Supabase bearer token through the existing `current_profile` PostgREST contract, matches the place by provider id or name plus coordinates, requests Google's first returned usable photo, and returns a short-lived image URL plus the required Google Maps/author/source attribution. Google does not expose a storefront/signage label or usage count, so this is a best available default rather than a guaranteed exterior photo.

If Google has no trustworthy match or is unavailable, iOS calls `public.first_visible_place_photo(place_id)`. That security-invoker RPC returns the earliest uploaded visit-photo object allowed by existing user-place/visit/photo RLS. The image bytes are downloaded from the private `visit-photos` bucket with the signed-in user's auth headers. This makes the first uploaded photo the shared default for dropped pins that friends can see, without exposing a permanent public URL. A just-added local photo renders immediately from its local asset while upload is pending. MapKit/category artwork remains the final fallback when neither source exists.

With the REC-82 field mask, Google currently bills venue matching as Text Search Pro, which has a separate 5,000-event monthly free cap; Place Details Photos has a 1,000-event monthly free cap. Most rec.me places originate in MapKit, so the first photo open can consume one event from each SKU. The database RPC `public.consume_place_photo_quota()` admits at most 900 provider lookups per UTC month globally and 120 per user per UTC day before the Edge Function returns `429`, preventing the alpha from crossing the smaller photo free cap even if Google Cloud budget alerts are only advisory. Coordinate/dropped pins bypass Google and go directly to the visible user-photo fallback. The Google Cloud project must still have billing enabled. Keep Places API (New) method quotas and budget alerts configured as a second control, and restrict the server-side key to Places API. Yelp is not a free commercial fallback: its free access is a 30-day evaluation trial.

Keep the key server-side and deploy the function:

```bash
npx supabase secrets set WANDER_GOOGLE_PLACES_API_KEY=<restricted-server-key> --project-ref "$WANDER_SUPABASE_PROJECT_REF"
npx supabase functions deploy place-photo --project-ref "$WANDER_SUPABASE_PROJECT_REF" --use-api
```

The function and `first_visible_place_photo` RPC were deployed to the linked rec.me project on 2026-07-12. The user-photo fallback is live. `WANDER_GOOGLE_PLACES_API_KEY` was installed as a managed Supabase secret and `place-photo` was redeployed on 2026-07-12. A live Text Search plus Place Details Photo check matched Ronan and returned an attributed Google media URL. The hard quota RPC was added on 2026-07-13; deploy its migration before deploying the updated Edge Function. Keep the Google Cloud key restricted to Places API (New), retain provider-side quotas and budget alerts, and rotate the credential if it is ever exposed outside approved secret storage.

Do not store Google photo names, image bytes, or returned image URLs in SwiftData, Supabase, fixtures, or analytics. Google Place IDs may be retained. The UI must keep the Google Maps attribution, photo author attribution when present, and source-photo link visible with the image.

After changing the preferred-photo RPC or its RLS path, run the hosted smoke test. `--linked` uses the Supabase Management API when a direct database password is not available:

```bash
node scripts/supabase-smoke-test.mjs --linked
```

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
- Public TestFlight group `rec.me Alpha` exists with public link enabled and no custom tester cap: `https://testflight.apple.com/join/knEhRa6t`.
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
- After `xcodebuild -exportArchive` reports `Uploaded Wander`, run `node scripts/testflight-release.mjs --archive-path <archive>`. It waits for the uploaded build to become `VALID`, sets export compliance, attaches the build to `rec.me Alpha`, submits external beta review, and prints the final TestFlight summary. Passing `--archive-path` lets the helper detect Xcode upload build-number drift before attaching the wrong TestFlight build. Use `--dry-run` before upload to verify the resolved build number and App Store Connect config.

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
