# Apple Developer transfer preflight

Task record: [REC-649](https://linear.app/recme/issue/REC-649).

The standalone checker in `scripts/apple-transfer-preflight.py` performs local,
read-only checks. It does not sign, create credentials, contact services, change
TestFlight, or edit production configuration. Python 3 is its only dependency
for source and AASA checks; archive checks also require macOS `codesign` and
`security`. It prints check names and Boolean outcomes, never full profiles,
certificates, environment values, or subprocess diagnostics. Exit 1 means a
check failed or an input/tool could not be read. A pass covers only the chosen
mode, not approval to transfer or release.

## Preparation before the transfer window

1. Inventory the five bundle IDs, App Groups, associated domains, Apple sign-in
   configuration, and push credential references. Keep operational account
   status in REC-649. Verify that unrelated apps do not consume the two Astir
   groups before planning their transfer.
2. Keep the current signing team and production credentials in place. Run the
   source contract check against the checkout being prepared:

   ```sh
   python3 scripts/apple-transfer-preflight.py source . --team Y7TVK75RZ8
   python3 -m unittest discover -s scripts -p 'test_apple_transfer_preflight.py'
   ```

3. Retain the existing released archives and dSYMs. Run archive checks against
   each release used as a baseline, with its actual signing team and App ID
   prefix. Specify the expected signing stage explicitly. Xcode's automatic
   signing can create a development-signed archive and re-sign it for App Store
   distribution during export. The prefix and team are separate arguments:

   ```sh
   python3 scripts/apple-transfer-preflight.py archive /path/to/Astir.xcarchive \
     --team Y7TVK75RZ8 --app-id-prefix Y7TVK75RZ8 --signing-kind development
   ```

   Use `--signing-kind distribution` for an archive signed for distribution.
   A development-stage pass is not a distribution validation pass. Check the
   export method and distribution package separately; do not change the
   expected signing stage simply to make a failed check pass.

   Signature trust, unreadable XML entitlements, missing profiles, and profile
   decoding errors remain failures. Do not replace these results with an older
   verification report. The checker does not modify trust settings. It checks
   all five product IDs, matching versions, signatures, App Groups, domains,
   main/Clip associations, stage-appropriate push environment, signing team, prefix, and
   profile expiry. This is a targeted supplement to the normal release gate;
   it does not validate every possible provisioning entitlement or replace
   Xcode/App Store validation.

4. Validate local website AASA source files or separately obtained response
   bodies. This command does not download them. Use `--cards` for the Astir
   website variant; omit it for the legacy getrec.me variant:

   ```sh
   python3 scripts/apple-transfer-preflight.py aasa /path/to/website-aasa.json \
     --kind website --app-id-prefix Y7TVK75RZ8 --cards
   python3 scripts/apple-transfer-preflight.py aasa /path/to/clerk-aasa.json \
     --kind clerk --app-id-prefix Y7TVK75RZ8
   ```

   The validator supports the current simple path/component contract with one
   matching details entry per app ID. It fails on conditional/exclusion routing
   or multiple matching entries rather than simulate Apple's matching
   algorithm. Check both AASA paths on each website hostname, plus Clerk's
   well-known endpoint. HTTP status, redirects, response headers, Apple CDN
   refresh, and real-device link behavior require separate verification.

## Cutover prerequisites

- Obtain Clerk's supported Apple identity migration procedure before changing
  Apple sign-in configuration. It must preserve existing Clerk user IDs and
  connected accounts, including Hide My Email users and main/Clip sign-in.
- Plan recipient credential creation and secure custody separately. Keep
  private key material out of source control and task comments. Do not revoke
  credentials used by unrelated apps.
- Preserve all five bundle IDs and both App Group names. Determine actual
  recipient profile prefixes after transfer; never derive a prefix solely
  from the recipient team ID.
- Prepare push verification with controlled devices on both current and new
  builds. The worker reads one team/key/private-key tuple for both APNs
  environments. Coordinate all three values together, retain the bundle-ID
  topic, account for in-flight dispatch, and verify delivery and notification
  taps before resuming normal dispatch. Preserve device and queued-event data.

## Transfer window and verification

The transfer itself, TestFlight shutdown, production auth/push changes, App
Group transfer, new provisioning profiles, and release upload require the
separate authorized cutover. Follow Apple's current transfer instructions and
Clerk's response at that time. Prepare new recipient profiles after the app
transfer completes.

Run archive mode with the actual recipient team and actual profile prefix.
If a newly signed application identifier changes, prepare additive AASA entries
while retaining old identifiers and existing routes. Repeat `--app-id-prefix`
for each prefix that must work. Update the website's existing exact-ID tests
when adding identifiers. Do not deploy a speculative recipient prefix.

| Scenario | Required result |
| --- | --- |
| Existing Apple user, including Hide My Email | Same Clerk user and app data after reauthentication |
| New Apple user | One new account, working profile and sync |
| Clip to full app | Correct same-account continuation and parent association |
| App update with staged share import | Import remains readable in the shared group |
| Both widgets after update | Current account state and working deep links |
| Each native link route on each domain | Correct app/Clip routing on current and new builds |
| Push on existing and newly registered devices | Delivery, display, and tap behavior verified |
| Keychain/session reset on first recipient update | Clear reauthentication without duplicate identity |

Stop the rollout on identity mismatch, missing shared state, failed signatures,
or push failures. Retain the prior configuration references for diagnosis and
the service-specific recovery procedure; do not assume the Apple ownership
transfer itself can be rolled back like a deployment.

References: [Apple app transfer overview](https://developer.apple.com/help/app-store-connect/transfer-an-app/overview-of-app-transfer/),
[accepting a transfer](https://developer.apple.com/help/app-store-connect/transfer-an-app/accept-an-app-transfer/),
[Sign in with Apple migration](https://developer.apple.com/documentation/technotes/tn3159-migrating-sign-in-with-apple-users-for-an-app-transfer).
