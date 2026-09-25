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
marking full-app onboarding complete. New-device password sign-in continues the
same Clerk Device Trust attempt with its advertised email code. Unsupported
verification methods fail closed; verify the enabled provider/account policies
on a signed device before release. Private profiles cannot join collaborative lists under the existing
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
The testing branch also includes REC-598, which removes the duplicate painted
footer and copies the exact share URL before every social-platform handoff.

The existing website continues to offer the exact-item native deep link and
TestFlight/App Store fallback. TestFlight is a distribution fallback, not proof
of deferred-link or account migration through a generic TestFlight invitation.

## Validation and rollout

For local signed testing, open this branch's `Wander.xcodeproj`, select the
`AstirClip` scheme and a connected, unlocked development iPhone. In Edit Scheme
→ Run → Arguments, add an enabled `_XCAppClipURL` environment variable containing
a fresh Astir share URL. Disable `-AstirClipDemo` for live-service checks. Running
from Xcode opens the destination directly; it does not show a Messages footer.
The new Save RPC must be deployed before testing a successful live Save.

For the native launch card, use Settings → Developer → Local Experiences on the
test phone, with `com.grayline.wander.Clip` and the invocation URL. Confirm whether
the full app is already installed before changing device state; preserve its data.
Local card testing and production Messages verification are separate checks.
See [Apple's local testing procedure](https://developer.apple.com/documentation/appclip/testing-the-launch-experience-of-your-app-clip).

### Branch testing setup

- Native: `codex/rec-408-shared-app-clip`, [PR #728](https://github.com/joelipshutz/wander/pull/728).
- Website: `codex/rec-408-app-clip`, [PR #24](https://github.com/joelipshutz/astir-site/pull/24).
- [Website preview](https://astir-site-git-codex-rec-408-app-clip-hotchkiss-technologies.vercel.app):
  `ASTIR_APP_CLIP_ENABLED=true` is scoped to this Vercel Preview branch only.
  Its generated banner uses the canonical share URL; the Vercel hostname is not
  an associated domain or an App Clip invocation host.

Use fresh links for profile/map, place, list, activity and list invitation. On
each installed social app, invoke sharing, return and paste into a local text
field to verify the complete URL is available even if that platform does not
attach a clickable link automatically. Messages link artwork should have no
painted button/footer. Validate recipient visibility separately from public artwork.

Website metadata can be checked on the preview before production deployment.
Xcode invocation can test Clip routing, authentication, Save/Join and continuation
before public release. TestFlight Clip experiences launch the Clip without the
native launch card. Apple's website/Messages experience requires the associated
website plus an approved, released app containing the Clip. Real Messages footer
screenshots therefore belong to the published-experience gate, not a branch-only
simulator run. See the Apple testing procedure above for each invocation method.

Current validation results and any outstanding gates are recorded on REC-408 and
the two PRs. A successful website deployment or signed build alone does not prove
device authentication, installation continuation or Messages rendering.

1. Run `xcodegen generate`, then the `AstirClip` unit/UI scheme and the parent
   `Wander` suite. UI demos use `-AstirClipDemo` and optional
   `-AstirClipDemoInvite`; fixtures are Debug-only and use synthetic data.
   After integrating `origin/main` at `94b402240`, all 27 Clip unit/contract tests,
   both Clip Save/Join UI tests and all 2,552 parent unit tests passed on the
   available iOS 26.5 simulator on 2026-09-23. Four home-city test fixtures now supply the phone
   number required by the current onboarding contract. All five previously failing parent
   invitation/conversation/follow UI cases also passed a focused rerun without
   changing those UI flows before the main integration. Two later full-suite runs
   were interrupted, the second after disk exhaustion. They exposed additional
   check-in UI/keyboard failures and do not count as full-suite passes. Complete
   the broader UI gate on a host with sufficient free disk before merge.
2. Run the migration preview inside the existing rollback-only hosted smoke:
   `node scripts/supabase-smoke-test.mjs --linked --migration-preview supabase/migrations/20260923013423_app_clip_save.sql`.
   The smoke includes `supabase/tests/app_clip_save.sql`. Do not apply the migration
   to production merely to validate the draft. Confirm security metadata, caller
   identity, repeat-save behavior, deleted restoration, exact legacy place IDs,
   private visibility and anonymous denial. The focused hosted migration preview,
   share-card privacy suite and 28 web-link/invitation checks passed on 2026-09-22.
   The complete rollback-only hosted smoke also passed on 2026-09-23 after
   adopting the Events home-area fixture correction already on `origin/main`.
   A subsequent read confirmed the preview RPC and reserved fixture profiles did
   not remain. The draft Clip RPC is not deployed for live Save operations.
3. Apple identifier registration, associated domains, parent Sign in with Apple
   association and dedicated App Group membership for both targets were verified
   in the live dashboards on 2026-09-23. Both provisioning profiles were regenerated
   and verified in the signed builds. Clerk production identity and the existing parent native
   registration and Clip registration/callback are verified. Production Clerk has
   Device Trust enabled; the Clip retains the exact password attempt, sends its
   advertised email second-factor code and verifies it before adopting the created
   session. Both current and legacy Device Trust statuses are covered. Wrong codes
   remain retryable; cancellation discards the challenge and pending Save/Join.
   The 27 Clip unit/contract tests pass. Xcode account setup and the signed
   development Clip and parent Release builds now pass. Signature and entitlement
   inspection confirms both profiles, matching versions/builds, the parent/Clip
   association, App Group, Apple sign-in and all three domains.
   Signed-device authentication remains required; do not disable Device Trust to
   accommodate a failing client.

   Live-auth simulator checks require a signed simulator build. An unsigned
   `CODE_SIGNING_ALLOWED=NO` launch fails in Clerk configuration with Keychain
   OSStatus `-34018` (missing entitlement), before any provider login. Synthetic
   auth tests do not exercise this Keychain requirement. Keep this distinction
   explicit when interpreting the full UI suite. The focused normal-launch and
   login-entry UI test passed with `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
   GENERATE_INFOPLIST_FILE=YES`. The last override supplies plists for the existing
   parent test bundles. This validates startup, not a completed provider login.
4. Test real native sign-in, profile creation, an existing Been/Wanna save, new
   save, revoked/blocked invitation, repeated acceptance and account change.
   Install the full app over the signed Clip and prove the same account and exact
   link survive onboarding. Exercise a revoked session and network failures.
5. Verify explicit analytics against a controlled test account. Clip replay and
   automatic capture are disabled; no content, tokens or URLs are event fields.
   See `analytics.md`. Measure the signed, thinned release Clip size; an unsigned
   build-directory size is only an early signal. The signed local Release Clip
   currently contains 15,973,956 unthinned bytes. Both signed targets resolve
   Clerk and Supabase configuration, but their analytics token is absent. Populate
   the approved Astir-specific ignored configuration before analytics validation
   or upload; the local build is not a release candidate.
6. Configure the default App Clip experience with the approved 1800×1200 header,
   subtitle and action. Upload/release only through the normal approved release
   workflow. Validate TestFlight invocation and then the published experience.
7. Deploy and verify every relevant host's AASA before enabling the website
   banner. Test actual Messages on devices with/without the full app, a sender
   in contacts, revoked links and fresh URLs. Capture real received Messages cards
   at that stage. Simulator Clip screenshots do not prove Messages rendering.

Do not merge this draft until backend, signed-device identity and installation
handoff gates are resolved. Do not enable the production website banner or claim a live
Messages footer from simulator-only evidence.

## Platform references

- [Website and Messages invocations](https://developer.apple.com/documentation/appclip/supporting-invocations-from-your-website-and-the-messages-app)
- [Default App Clip experience](https://developer.apple.com/help/app-store-connect/offer-app-clip-experiences/offer-a-default-app-clip-experience)
- [Test the launch experience](https://developer.apple.com/documentation/appclip/testing-the-launch-experience-of-your-app-clip)
- [Share data with the full app](https://developer.apple.com/documentation/appclip/sharing-data-between-your-app-clip-and-your-full-app)
- [Clerk native Apple setup](https://clerk.com/docs/ios/guides/configure/auth-strategies/sign-in-with-apple)
