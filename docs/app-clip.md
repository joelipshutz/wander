# Shared-link App Clip

REC-408 adds `AstirClip` (`com.grayline.wander.Clip`) to the existing parent app
`com.grayline.wander`. The shared-link increment includes profile/map, place,
list, activity and list-invitation links. Physical event QR attendance is separate.

The [App Clip service map](app-clip-service-map.json) records the relevant account
identifiers and their verification sources. Repository configuration and direct
service verification are labeled separately; unresolved dashboard checks remain
explicitly pending. It contains no credentials or private keys.

## Behavior

The Clip displays public share artwork, then uses the same account-authorized
RPCs as the full app for protected content. A published image token never grants
access to a private profile, activity or list. The first native implementation
shows up to 20 list places and 100 profile places, with the cap stated on screen.

Save and Join stay inside the Clip. Apple, Google, email-code and password paths
reuse `ClerkAuthService`; a first-time account supplies name and handle without
marking full-app onboarding complete. Additional verification/MFA is currently
reported as a sign-in limitation; verify the enabled provider/account policies
before release. Private profiles cannot join collaborative lists under the existing
server contract. The Clip explains that condition and does not change privacy.

`save_app_clip_place` writes a new Wanna using the current caller's default
visibility (Self for private profiles). Repeated requests leave live saves,
notes, Been status and visibility untouched. The RPC cannot modify canonical
place metadata or choose a different user. Deleted snapshots can be restored
without their old note, answers, attribution or scheduled date. Existing history
is retained. Invitation acceptance uses the existing idempotent invitation RPC;
a subsequent list-read error does not turn a committed acceptance into a failure.

Ephemeral responses are not persisted. Token/account checks run before and after
network requests. Session replacement clears private presentation and pending
actions. Sign-out resets analytics identity and the installation continuation.

## Installation continuation

The dedicated App Group `group.com.grayline.wander.clip` contains only the validated
link, optional internal account ID and a seven-day expiry. No credential is copied
there. The parent waits for validated authentication and normal onboarding before
opening that destination, rejects another account, and retains the record until
navigation consumes it. An explicit incoming link takes precedence.

The Clip configures Clerk's Keychain service as the parent's existing service.
Apple documents automatic corresponding-Clip-to-parent Keychain migration. Actual
SDK session continuity must be proven on a signed device before release, including
Apple identity grouping, existing Google/email accounts, sign-out and fresh install.
The app must not silently create another account to repair a failed handoff.

## Native preview and website

The companion `astir-site` change adds the Clip to AASA and emits the Smart App
Banner only when `ASTIR_APP_CLIP_ENABLED=true` and the preview is available.
The default remains off. Apple's native icon and action footer are controlled by
its App Clip experience, not custom OG footer markup. The action is configured
in App Store Connect; individual OG cards still supply their artwork and title.
REC-598 removes the duplicate painted footer separately.

The existing website continues to offer the exact-item native deep link and
TestFlight/App Store fallback. TestFlight is a distribution fallback, not proof
of deferred-link or account migration through a generic TestFlight invitation.

## Validation and rollout

1. Run `xcodegen generate`, then the `AstirClip` unit/UI scheme and the parent
   `Wander` suite. UI demos use `-AstirClipDemo` and optional
   `-AstirClipDemoInvite`; fixtures are Debug-only and use synthetic data.
2. Run the migration preview inside the existing rollback-only hosted smoke:
   `node scripts/supabase-smoke-test.mjs --linked --migration-preview supabase/migrations/20260923013423_app_clip_save.sql`.
   The smoke includes `supabase/tests/app_clip_save.sql`. Do not apply the migration
   to production merely to validate the draft. Confirm security metadata, caller
   identity, repeat-save behavior, deleted restoration, exact legacy place IDs,
   private visibility and anonymous denial. The focused hosted migration preview,
   share-card privacy suite and 28 web-link/invitation checks passed on 2026-09-22.
   A subsequent read confirmed the preview RPC and reserved fixture profiles did
   not remain. The complete hosted smoke is not green: its unchanged Events
   interest fixture lacks the Los Angeles home-area record now required by the
   hosted `register_events_launch_interest` contract. Resolve that fixture/schema
   drift before treating the full backend gate as passed.
3. Register the Clip identifier, associated domains, Sign in with Apple grouping,
   and dedicated App Group for both signed targets. Verify the correct Clerk
   native application registration and callback behavior. Preserve the existing
   parent identity and its authentication configuration.
4. Test real native sign-in, profile creation, an existing Been/Wanna save, new
   save, revoked/blocked invitation, repeated acceptance and account change.
   Install the full app over the signed Clip and prove the same account and exact
   link survive onboarding. Exercise a revoked session and network failures.
5. Verify explicit analytics against a controlled test account. Clip replay and
   automatic capture are disabled; no content, tokens or URLs are event fields.
   See `analytics.md`. Measure the signed, thinned release Clip size; an unsigned
   build-directory size is only an early signal.
6. Configure the default App Clip experience with the approved 1800×1200 header,
   subtitle and action. Upload/release only through the normal approved release
   workflow. Validate TestFlight invocation and then the published experience.
7. Deploy and verify every relevant host's AASA before enabling the website
   banner. Test actual Messages on devices with/without the full app, a sender
   in contacts, revoked links and fresh URLs. Capture real received Messages cards
   at that stage. Simulator Clip screenshots do not prove Messages rendering.

Do not merge this draft until backend, signed-device identity and installation
handoff gates are resolved. Do not enable the website banner or claim a live
Messages footer from simulator-only evidence.

## Platform references

- [Website and Messages invocations](https://developer.apple.com/documentation/appclip/supporting-invocations-from-your-website-and-the-messages-app)
- [Default App Clip experience](https://developer.apple.com/help/app-store-connect/offer-app-clip-experiences/offer-a-default-app-clip-experience)
- [Test the launch experience](https://developer.apple.com/documentation/appclip/testing-the-launch-experience-of-your-app-clip)
- [Share data with the full app](https://developer.apple.com/documentation/appclip/sharing-data-between-your-app-clip-and-your-full-app)
- [Clerk native Apple setup](https://clerk.com/docs/ios/guides/configure/auth-strategies/sign-in-with-apple)
