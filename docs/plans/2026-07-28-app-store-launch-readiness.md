# rec.me App Store Launch Readiness

Date: 2026-07-28

Tracking: REC-180

Scope: preparation only; no production credential cutover, App Store version creation, upload, submission, or public announcement is authorized by this plan.

## Recommendation

Move toward a public App Store launch now. Do not run a long open-ended beta.

Use one final, short external TestFlight gate after the production Clerk cutover and all launch blockers below are complete. That build must use the exact production configuration intended for the App Store. Test sign-up, sign-in, save/sync, social visibility, reporting, and account deletion on physical devices, then submit the same binary to App Review.

This gate is necessary because the current TestFlight build uses a Clerk development instance. Moving to production changes the Clerk issuer, public key, Frontend API domain, OAuth credentials, user IDs, webhook secret, Supabase trust configuration, and associated-domain entitlement at the same time. App Review should not be the first production-auth smoke test.

## Verified Current State

### App Store Connect

- App record exists: `rec.me`, Apple ID `6776850787`, bundle id `com.grayline.wander`.
- TestFlight build `0.1 (108)` uploaded successfully and is `VALID`.
- No iOS App Store version record exists yet.
- No App Store localization, description, keywords, screenshots, age rating, category, privacy URL/label, support URL, review account, or review notes are configured.

### Clerk and Supabase

- Clerk application `Wander` has a development instance only. `clerk deploy status` reports `not_started` and no production instance or domain.
- Build 108 embeds a `pk_test_` Clerk key, `growing-pheasant-22.clerk.accounts.dev`, and the matching development `webcredentials:` entitlement.
- Clerk development configuration enables Google sign-in and disables Apple sign-in. A public iOS app that offers Google sign-in needs an equivalent privacy-preserving login option under App Review Guideline 4.8; Sign in with Apple is the expected route.
- Clerk development users cannot be transferred to the production instance. Existing tester identities therefore need an explicit fresh-start or data-migration decision.
- Supabase currently trusts the Clerk development issuer. Production must add the production Clerk third-party auth integration and preserve the `role=authenticated` session claim.
- The production Clerk instance needs its own signed webhook endpoint configuration and secret for `user.created`, `user.updated`, and `user.deleted`.
- In-app account deletion exists. The webhook path inventories account-owned storage, deletes stored objects, hard-deletes the profile, and relies on foreign-key cascades to remove owned records. This must be re-verified end-to-end with a production Clerk user before submission.

### Apple safety and privacy

- rec.me is a social app with user-generated profile, place, list, note, and photo content.
- Blocking and muting exist, but there is no user/content reporting flow, moderation intake, or published support contact.
- There is no server/client post filter for objectionable free-text content.
- The app has no in-app Privacy Policy, Terms, Community Standards, or Support links.
- `getrec.me`, `/privacy`, `/terms`, `/support`, and `/import-help` currently return the same Squarespace `Coming Soon` page. Apple requires functional URLs and an easily accessible in-app privacy policy.
- The onboarding asks for Contacts permission but does not read contacts or perform contact matching. Do not request a sensitive permission before the matching feature exists.
- App-owned code uses UserDefaults and file-timestamp APIs, but the app and share extension do not contain their own `PrivacyInfo.xcprivacy` manifests. Bundled PostHog, PLCrashReporter, PhoneNumberKit, and swift-crypto resources do contain SDK manifests.
- Build 108 has no PostHog project token, so product analytics are currently disabled. Decide whether launch enables privacy-disclosed, non-PII analytics with a user control or intentionally relies on Apple crash/metric reporting for the first release.

## Public Launch Gates

All P0 items must be complete before creating the App Store submission candidate.

### P0 — Production identity and backend

1. Run interactive `clerk deploy` from the linked repo and clone the development configuration into a production instance.
2. Use the owned rec.me web domain chosen for launch, add Clerk's DNS records, deploy certificates, and register native iOS app `com.grayline.wander` with the correct App ID prefix.
3. Configure production login methods:
   - Recommended: email/password or email code, Google, and Sign in with Apple.
   - Faster fallback: disable Google and launch with first-party email authentication only.
4. Configure production Clerk session claim `role=authenticated`.
5. Add the production Clerk issuer to Supabase Third-Party Auth.
6. Create the production Clerk webhook using the deployed Supabase Edge Function, store the new signing secret in Supabase secrets, and limit subscribed events to the three handled user events.
7. Replace the iOS Release Clerk key/domain and associated-domain entitlement with production values while preserving an explicit development configuration for local work.
8. Resolve existing development tester data before new production accounts claim handles:
   - Recommended while the app is still private: fresh-start production identities and remove or namespace obsolete alpha profile rows after an explicit backup.
   - Alternative: write an explicit account/data reassignment migration. Do not attempt to copy Clerk development users; Clerk does not support it.
9. Run hosted auth/RLS smoke coverage with production tokens and verify create, profile mirror, save/sync, visibility, follow/block, upload, notification registration, and account deletion.

### P0 — Production backend and launch operations

1. Decide whether the current Supabase alpha project becomes production or whether a separate production project is required. If it is promoted, document that decision and remove alpha-only data/config after an explicit backup.
2. Review every hosted migration, exposed schema, RLS policy, storage policy, RPC grant, Edge Function JWT setting, webhook secret, and service-role use against the public threat model.
3. Verify database backups/recovery, plan limits, logs, alerts, and a tested rollback/hotfix path. Public launch must not depend on an unmonitored free-tier assumption.
4. Confirm production APNs credentials/environment and exercise notification registration, account switching, delivery, block/mute suppression, and account-deletion cleanup from the production candidate.
5. Restrict and budget-alert Google Places, AI/extraction, Supabase, and other operational keys. Keep provider keys server-side and validate existing per-user/global quotas against public abuse.
6. Remove or explicitly gate fictional alpha fixtures, debug launch arguments, preview overrides, and operational scripts so they cannot mutate or appear in public user state.
7. Define launch monitoring and owners for sign-up failures, sync/RLS errors, webhook failures, report/moderation intake, crashes, provider spend, and App Review messages.

### P0 — UGC safety and moderation

1. Add Report actions on other-user profiles and every surface that renders another member's shared text/photo content.
2. Persist reports server-side with reporter, target/content identifiers, reason, optional detail, timestamps, and a privacy-safe status trail. Reporters must not be able to read other reports.
3. Provide a real moderation intake with an owner, response SLA, audit trail, and the ability to remove content or accounts. A dead-end email composer alone is insufficient.
4. Filter objectionable free text before public posting and repeat validation server-side for profile identity/bio, list names/descriptions, place notes, custom tags, and other shared text.
5. Keep the existing hard-block behavior and verify it hides both users and their content across search, profiles, map/feed/list surfaces, notifications, and stale caches.
6. Publish Community Standards and a real support contact, and link both from Settings.

### P0 — Privacy, permissions, and legal surfaces

1. Publish real pages for Privacy Policy, Terms, Support, Community Standards, data deletion/privacy choices, and import help. Replace all placeholder routes.
2. Add Settings links to Privacy Policy, Terms, Community Standards, Support/Contact, and privacy choices.
3. Inventory data collected by rec.me and Clerk, Supabase, Apple/MapKit, Google Places, PostHog if enabled, push notifications, and any AI/extraction provider. Use it to complete the App Privacy label accurately.
4. Cover at least account/contact information, identifiers, user content, photos, saved-place/location data, diagnostics, product interaction, and vendor sharing/retention/deletion behavior where applicable.
5. Add valid app/extension privacy manifests for the required-reason APIs actually used, and validate the exported archive privacy report.
6. Remove the Contacts permission step and purpose string until real contact matching exists, or implement the promised on-device/consent-based behavior with a reviewed privacy design.
7. Confirm account deletion from the production app removes Clerk identity, database rows, storage objects, device tokens, and shared UGC as required, with honest timing/error copy.

### P0 — App Store product page and review

1. Decide the public marketing version. Recommendation: first public release is `1.0`; do not submit the internal `0.1` alpha label by accident.
2. Create the iOS App Store version only after the version choice is confirmed.
3. Complete name/subtitle, primary category, content-rights declaration, age rating, copyright, price/availability, DSA trader status, and release mode.
4. Write description, keywords, promotional text, support URL, marketing URL, and privacy policy URL.
5. Produce final iPhone screenshots from the production-config candidate. Use real approved UI and safe seeded content; no dev banners, placeholder copy, or private tester data.
6. Create a durable App Review account in the production Clerk instance and seed enough social/place data for the reviewer to exercise the core value. Put credentials only in App Store Connect review details, never in git or Linear.
7. Add review notes that explain location-denied fallback, account deletion, report/block flows, optional Contacts removal/behavior, production backend availability, and any non-obvious widgets/share-extension behavior.
8. Verify all URLs on a clean device/network and run App Store Connect's required-field checks before submission.

### P1 — Launch quality and distribution

- Decide whether to enable PostHog for the public build. If enabled, keep properties non-PII, publish the practice, and add a clear analytics control.
- Convert public share/invite destinations to rec.me universal links with an App Store fallback; coordinate existing REC-56, REC-123, and REC-172.
- Ensure `https://apps.apple.com/app/id6776850787` is used as the durable public App Store destination after the version is live.
- Prepare support ownership, moderation alerts, App Review monitoring, crash monitoring, launch analytics, and rollback/hotfix procedures.
- Limit the first availability footprint if support/moderation coverage or legal localization is not ready globally.

## Final Candidate Gate

The same exact commit and build must pass all of the following before App Store submission:

- Release build and complete automated test suite pass.
- Hosted Supabase smoke suite passes with a production Clerk token.
- Production sign-up/sign-in works for email, Google, and Apple if enabled.
- Reviewer account works on a clean physical device.
- Save/sync, social visibility, report, block, support links, permissions, and permanent account deletion pass on physical devices.
- App/extension privacy manifests and exported archive validation pass.
- App Store product page, privacy label, screenshots, age rating, content rights, review details, price/availability, and DSA status are complete.
- A short external TestFlight smoke run finds no P0 regression.
- Joe explicitly approves App Store submission and the release mode; only then attach the build and submit it for review.

## Human Decisions Still Required

1. Production root domain: recommend `getrec.me` unless ownership/brand migration makes another controlled domain safer.
2. Alpha data: recommend a backed-up fresh start rather than trying to preserve development Clerk identities.
3. Login: recommend Sign in with Apple plus Google and email; fallback is disabling Google for launch.
4. Analytics: enable privacy-controlled PostHog at launch, or intentionally ship without it.
5. Public version: recommend `1.0` rather than `0.1`.
6. App release: manual release after approval is safer than automatic release immediately after review.

## Primary References

- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Apple account deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app/)
- [Apple App Privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [Apple App Store submission workflow](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/)
- [Clerk production deployment](https://clerk.com/docs/guides/development/deployment/production)
- [Clerk development and production instances](https://clerk.com/docs/guides/development/managing-environments)
- [Supabase Clerk third-party auth](https://supabase.com/docs/guides/auth/third-party/clerk)
