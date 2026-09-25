# rec.me App Store privacy inventory

Updated: 2026-09-21

Owner: [REC-185](https://linear.app/recme/issue/REC-185/complete-app-store-privacy-manifests-labels-and-permission-audit)

This is the source-of-truth draft for the App Store privacy questionnaire. It describes the current production-intent code path. Recheck it against the exact archived release candidate before publishing App Store Connect answers.

## Decisions

- Keep PostHog with explicit allowlisted events and the internal auth user ID. REC-626 supersedes REC-582: screenshot replay shows app content (including text, images and maps), with passwords/sign-in codes and system-owned views masked. Explicit person properties contain name and username; replay requires swizzling. Element capture, automatic screen/lifecycle events, surveys, crash autocapture, automatic person properties, console logs and network telemetry remain disabled. Recordings are arriving from TestFlight as of September 25; the new readable/named client still requires release-candidate playback validation. See [the replay activation checklist](../analytics.md#ios-session-replay) before release.
- Add `$geoip_disable = true` to every PostHog event before it is queued. PostHog project `557259` was browser-verified on 2026-08-14 with **Discard client IP data** enabled. The rec.me personal API key still lacks `project:read`; the authenticated project setting is the current evidence source.
- Declare no tracking and do not request App Tracking Transparency permission. rec.me does not combine its data with third-party data for targeted advertising, advertising measurement, or data-broker sharing.
- Keep native Contacts. REC-560 adds a separate, optional Find friends consent: permitted phone numbers and email addresses are transmitted over TLS for an immediate authenticated match. Names, organizations, notes, addresses and contact photos are not part of matching. No uploaded address book, unmatched identifiers or contact edges are retained; a private HMAC index contains only opted-in members’ verified account identifiers. Contact values never enter analytics. The separate invitation flow remains local and passes only selected recipients to Messages. Existing iOS permission grants do not imply Find friends consent. See [contact discovery](../contact-discovery.md).
- Do not declare device precise location as collected. Current location is used on-device for nearby MapKit results and the nearby widget, and is not uploaded or analytics-logged. Saved businesses carry their own place coordinates, which are place metadata rather than a device location trail.
- Declare trusted-search history. The raw query is sent to the authenticated parsing function and AI provider to produce filters.
- Treat Apple Calendar access as optional app functionality. EventKit rows are inspected locally; MapKit receives a bounded restaurant query, while rec.me services receive only a hashed occurrence key, matched place identity, reservation time, and time zone. Raw calendar identifiers, titles, notes, attendees, URLs, and addresses are not uploaded to rec.me.

## App-owned privacy manifest

`Wander/Resources/PrivacyInfo.xcprivacy` declares the app-owned data rec.me sends to Clerk/Supabase-backed product services:

| Data type | Linked | Tracking | Purpose |
|---|---:|---:|---|
| Name | Yes | No | App functionality |
| Email address | Yes | No | App functionality |
| Phone number | Yes | No | App functionality |
| Contacts/social graph | Yes | No | App functionality |
| Photos or videos | Yes | No | App functionality |
| Other user content | Yes | No | App functionality; product personalization |
| Search history | Yes | No | App functionality; product personalization |
| User ID | Yes | No | App functionality |
| Device ID | Yes | No | App functionality |

App required-reason API declarations:

| API category | Reason | Evidence |
|---|---|---|
| User Defaults | `CA92.1` | App-only onboarding, notification, and reminder state |
| File timestamps | `C617.1` | Retention and local avatar/share-file revision checks inside app/app-group containers |
| System boot time | `35F9.1` | Elapsed foreground/background session-refresh timing |

`WanderShareExtension/PrivacyInfo.xcprivacy` declares only app-group/container file timestamps with reason `C617.1`. The extension stages user-selected imports locally and does not send data off-device itself.

## Third-party behavior for App Store labels

App Store privacy responses must include third-party behavior even when it belongs in the SDK's own manifest rather than the app-owned manifest.

| Data type | Linked | Tracking | Purpose | Source |
|---|---:|---:|---|---|
| User ID | Yes | No | Analytics | rec.me calls PostHog `identify` with the internal auth user ID |
| Device ID | Yes | No | Analytics | PostHog creates an install-scoped device/anonymous ID and links it after identify |
| Product interaction | Yes | No | Analytics | Explicit allowlisted product events; replay interactions linked to the named account |
| Other usage data | Yes | No | Analytics | Coarse counts, states, sources, and error categories; readable replay content/layout/timing |

PostHog event properties must remain non-PII. Current policy forbids place names, notes, coordinates, emails, phone numbers, handles, raw searches, and imported content. Search analytics contains only length/result/latency buckets and fixed example IDs; the raw search is sent to the product parsing service, not PostHog.

REC-626 adds an explicit exception for `name`, `display_name`, and `username` person properties. Replay snapshots use a separate SDK pipeline from event-property sanitization: ordinary visible app content, including photos, notes, searches and maps, can now be sent to PostHog and linked to a named person. Do not describe these recordings as anonymous or content-free. Passwords, verification codes, system views and other SDK-sensitive text inputs remain masked; individual email/phone inputs are explicitly readable under the user-approved replay policy.

Before distribution, review Analytics purpose for Name, Photos/Videos, Other User Content, Search History, Contacts and any location/contact information visible in replay against actual release-candidate playback. The existing App Functionality declarations alone do not describe the expanded replay use. No App Store Connect responses or published privacy policy were changed by this code PR. Preserve the accurate current data linkage and do not infer a live disclosure update from this inventory.

Clerk receives account identifiers and contact information for authentication. Supabase receives the app-owned product data listed above. The authenticated parsing service passes trusted-search text to the configured AI provider. Apple system frameworks receive selected message recipients and media only when the person explicitly invokes those system flows.

## Proposed App Store Connect answers

Mark these as collected and linked to the user, not used for tracking:

- Contact Info: Name, Email Address, Phone Number — App Functionality.
- Contacts — App Functionality. This covers the social graph and optional contact matching. Phone/email matching inputs are processed transiently; verified opted-in member identifier tokens and account consent are retained. Reconcile the final privacy-policy and App Review copy with REC-560 before distributing the new binary.
- User Content: Photos or Videos — App Functionality.
- User Content: Other User Content — App Functionality and Product Personalization.
- Search History — App Functionality and Product Personalization.
- Identifiers: User ID — App Functionality and Analytics.
- Identifiers: Device ID — App Functionality and Analytics.
- Usage Data: Product Interaction and Other Usage Data — Analytics.

Do not mark data as used for tracking. Do not declare advertising data, purchases, financial information, health/fitness, sensitive information, emails/text-message contents, audio, browsing history, environment scanning, hands, or head data.

REC-626 removes map masks, so visible maps/pins may transmit location information in replay even without coordinate event properties. Reassess the location disclosure against the release candidate; do not rely on the previous no-location conclusion. rec.me adds `$geoip_disable = true` to every PostHog event, and the project-level **Discard client IP data** setting was verified enabled on 2026-08-14.

## Permission audit

| Permission | Trigger | Behavior without access | Store/privacy treatment |
|---|---|---|---|
| Location When In Use | Nearby place search after contextual UI; nearby widget uses WidgetKit authorization | Manual search/map remains available | Used on-device; not collected |
| Contacts | Optional Find friends in onboarding/Discover/Settings, or separate local invitations | General suggestions, username search and share links remain available | Explicit matching consent before transmitting permitted phone/email values; no retained address books; private verified-member index; local invitation flow unchanged |
| Camera | User chooses to take a photo | Photo picker/manual save remains available | Uploaded chosen photos disclosed |
| Photo Library Add | User chooses Save/Instagram/TikTok for generated share media | Standard share paths remain available | User-initiated write only |
| Calendars Full Access | Profile → Settings → Privacy and trust → Permissions connection | Manual check-ins and every non-calendar feature remain available | Raw EventKit content is not collected; the derived restaurant/time reminder intent is covered by Other User Content |
| Notifications | Onboarding or Settings opt-in | Core app remains available | Device push token is disclosed as Device ID for app functionality |

## Validation completed on this branch

- Both source manifests pass `plutil -lint`.
- The 19 focused build-configuration/privacy tests pass.
- The complete `WanderTests` suite passes: 1,097 tests, 0 failures.
- An optimized arm64 Release simulator build passes. Its app and share-extension manifests exactly match the reviewed source files.
- Xcode scans eight privacy manifests in the Release bundle: rec.me, the share extension, PostHog, PHPLCrashReporter, PhoneNumberKit, TikTok OpenSDK Core/Share, and Swift Crypto.

This is strong pre-archive validation, not the final signed-candidate privacy report. Production auth, moderation, backend, and version gates still need to close before the archive-level preflight below.

The privacy-policy and privacy-choices URLs are live in App Store Connect as of 2026-08-14. The complete App Privacy questionnaire is saved as a draft; publication remains gated on the final signed archive reconciliation.

## Exact-candidate preflight

Before publishing App Store privacy answers:

1. Build/archive Release with the final production configuration.
2. Confirm `PrivacyInfo.xcprivacy` exists at the root of `Wander.app` and `WanderShareExtension.appex`.
3. Generate and inspect Xcode's privacy report for the archive, including every embedded framework and extension.
4. Confirm PostHog automatic capture settings in the compiled release, verify project-level IP capture is disabled, and inspect a small sample of emitted event names/properties including `$geoip_disable = true`.
5. Confirm Contacts, current location, selected photos, raw searches, push tokens, and imported content against actual network traffic.
6. Reconcile any SDK privacy-report declaration with real runtime configuration; do not copy a vendor's maximum-capability manifest blindly.
7. Publish the privacy policy URL `https://getrec.me/privacy` and privacy choices URL `https://getrec.me/privacy-choices`.
8. Save screenshots/exported evidence of the final App Store Connect responses in the private release record, not in source control if they contain account details.

## Apple references

- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Describing data use in privacy manifests](https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests)
- [Describing use of required reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [TN3183: Adding required-reason API entries](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest)
