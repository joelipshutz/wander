# rec.me App Store launch readiness

Updated: 2026-08-12

Owner issue: [REC-186](https://linear.app/recme/issue/REC-186/prepare-recme-app-store-product-page-and-review-package)

Parent: [REC-180](https://linear.app/recme/issue/REC-180/prepare-recme-for-app-store-launch)

## Recommendation

Launch rec.me as a **warm editorial utility**: emotionally clear like Corner, trustworthy like Beli, and immediately useful like Mapstr—without copying any of them.

The category position to own is:

> A living map of places your real people actually experienced, with enough context to choose what fits the moment.

Do not lead with import, ratings, or generic discovery. Lead with people and proof of real experience. Keep the first screenshot understandable in under two seconds.

Recommended first-frame promise:

> Your people. Their places. One map.

## Screenshot storyboard v1 — awaiting approval

![Six-panel rec.me App Store storyboard](concepts/v1/recme-app-store-storyboard-v1.png)

The six panels use current, working rec.me UI rather than invented product screens. The visual system uses the existing cream, terracotta, sky, sun, serif, and black brand language. Before final export, fixture names and content should be replaced with a small public-safe fictional social graph and every screenshot should be recaptured from the release candidate.

| Order | Promise | Product proof |
|---|---|---|
| 1 | Your people. Their places. One map. | Dense Friends map |
| 2 | See where your friends actually went. | Friends' place feed |
| 3 | Find a place that fits right now. | Natural-language trusted search |
| 4 | Remember every place worth returning to. | Place memory and detail |
| 5 | Save it before you lose it. | Add/import surface |
| 6 | Make plans together. | Shared lists |

All six portrait files are opaque 1320 × 2868 PNGs, matching Apple's accepted 6.9-inch iPhone size. rec.me targets iPhone only (`TARGETED_DEVICE_FAMILY = 1`), so an iPad screenshot set is not required for this build.

## Competitor read

| App | What it owns | What rec.me should learn | What rec.me should avoid |
|---|---|---|---|
| [Beli](https://apps.apple.com/us/app/beli/id1478375386) | Restaurant ranking and friends' taste | Crisp three-part story and trusted recommendations | Becoming restaurant-only; forced invite mechanics |
| [Corner](https://apps.apple.com/us/app/corner-curate-share-places/id1668282277) | Vibe, social maps, and Gen-Z cultural energy | Emotional copy and beautiful social proof | Collage overload, opaque AI, and onboarding friction |
| [Mapstr](https://apps.apple.com/us/app/mapstr-save-follow-places/id917288465) | Broad save/import utility | Immediate solo value and organization | Utilitarian sameness and surprise paywalls |
| [World of Mouth](https://apps.apple.com/us/app/world-of-mouth/id1454663016) | Premium expert trust | Editorial authority and restraint | A distant expert voice instead of real relationships |
| [Step](https://apps.apple.com/us/app/step-your-world/id1474971037) | Broad social map | Category breadth and friend-based discovery | Leading with import instead of the emotional wedge |
| [Swarm](https://apps.apple.com/us/app/swarm-check-in-explore-map/id870161082) | Place memory and check-ins | Long-term memory value | Gamified check-in framing |

Recent public reviews reinforce four product requirements:

1. Give a useful solo experience before asking for contacts or invitations.
2. Make trust, personalization, and data use legible rather than mysterious.
3. Preserve organization as the map grows: search, filters, tags, and lists.
4. Avoid surprise paywalls, forced invite loops, and unstable core flows.

## Live App Store Connect audit

Read-only snapshot taken 2026-08-12. No App Store data was changed.

| Surface | Current state | Launch action |
|---|---|---|
| App/version | `rec.me`, version `1.0`, Prepare for Submission | Keep public version 1.0 |
| Uploaded builds | Builds 127–136 are valid but all report marketing version `0.1` | Change `MARKETING_VERSION` to `1.0`, test, archive, and upload a new candidate |
| Release behavior | Automatic after approval (`AFTER_APPROVAL`) | Switch to manual release before submission |
| Subtitle | `Places from people you trust` | Keep; it is concrete, differentiated, and within the 30-character limit |
| Screenshots | 0 screenshots / 0 sets | Finalize and upload the approved six-panel 6.9-inch set |
| Categories | None selected | Primary: Social Networking. Secondary: Travel |
| Age rating | Not completed | Complete the questionnaire honestly; UGC/social behavior must be represented |
| Privacy | Privacy policy URL and privacy choices URL missing | Use the live getrec.me URLs and complete labels from the production data-flow audit |
| Support/marketing URLs | Missing | Add `https://getrec.me/support` and `https://getrec.me/` |
| Review information | Missing | Add contact, demo account, and reviewer walkthrough |
| Description/keywords | Drafts exist but need final copy | Replace with the product-page draft below after feature verification |
| Latest binary | Build 136 is valid, iOS 17+, export encryption false | Not selectable for version 1.0 because of the marketing-version mismatch |

The linked in-app pages currently return HTTP 200: support, privacy, terms, community standards, and privacy choices.

## Hard submission blockers

| Gate | Evidence | Required before submission |
|---|---|---|
| [REC-182](https://linear.app/recme/issue/REC-182/switch-recme-to-production-clerk-and-supabase-auth) — production auth | Release currently inherits the tracked Clerk test key and `.clerk.accounts.dev` host | Use production Clerk/Supabase configuration and production Associated Domains; validate sign-in, deletion, and a clean-device session |
| [REC-183](https://linear.app/recme/issue/REC-183/close-app-store-ugc-safety-and-moderation-gaps) — UGC safety | Blocking exists, but no in-product place/person/content report path or moderation workflow was found | Add report/filter/moderation intake, response ownership, auditability, and regression coverage |
| [REC-185](https://linear.app/recme/issue/REC-185/complete-app-privacy-manifest-labels-and-permission-audit) — privacy | App targets do not include an app-owned `PrivacyInfo.xcprivacy`; App Store privacy fields are empty | Audit all app/SDK collection, add manifests as required, verify permissions, and complete the privacy labels |
| [REC-187](https://linear.app/recme/issue/REC-187/harden-recme-production-backend-and-operations-for-launch) — backend/ops | Production readiness remains in progress | Complete hosted backend, observability, rollback, and operational validation |
| Version/build compatibility | Store version is 1.0; all uploaded binaries are 0.1 | Generate and upload a new 1.0 build only after the other release gates are closed |

Apple's UGC guideline requires objectionable-content filtering, reporting with timely response, blocking abusive users, and published contact information. The current report/moderation gap is therefore a review blocker, not a post-launch enhancement.

## Product-page copy draft

### Name

`rec.me`

### Subtitle

`Places from people you trust`

### Promotional text

`Remember places worth returning to—and find your next one through people you trust.`

### Keywords

`map,friends,restaurants,travel,save,discover,lists,checkin,local,food,cafes,bars,hikes,trip`

### Description

Find places through people you trust—not anonymous ratings.

rec.me turns real experiences from friends into a living map you can actually use. See where your people went, what they thought, and what fits the moment when you need a place now.

WITH REC.ME, YOU CAN

• See places your friends have actually visited

• Search your trusted map in natural language

• Save restaurants, bars, coffee shops, hikes, shops, and more

• Keep the notes and context that make a place worth remembering

• Organize places into lists and make plans together

• Control who can see what you share

Your map gets more useful with every memory—and every person you trust.

Need help? Visit https://getrec.me/support

Privacy: https://getrec.me/privacy

Terms: https://getrec.me/terms

### Reviewer notes outline

The final notes should include:

1. A dedicated review account with a populated trusted graph and sample places.
2. Exact steps for Sign in with Apple and any email/phone fallback.
3. A short walkthrough of Map, Feed, trusted search, Add, Lists, reporting, blocking, and account deletion.
4. An explanation of location, contacts, notifications, photo-library, and camera prompts, including how to test without granting each permission.
5. Confirmation that the backend is live and that reviewer access does not depend on a one-time code sent to an unavailable device.
6. Notes for the share extension, widgets, imported links, and any intentionally limited launch behavior.

Do not put real customer credentials or private user data in this document or source control.

## Release sequence

1. Approve the positioning, first-frame copy, and six-panel storyboard.
2. Close REC-182, REC-183, REC-185, and REC-187 with evidence.
3. Replace concept fixtures with public-safe release fixtures and capture final screens from the release candidate.
4. Set version 1.0, increment the build, regenerate the project, and run the full test suite plus small/large-phone visual QA.
5. Archive and upload only on explicit release instruction.
6. Complete App Store Connect metadata, categories, rating, privacy, agreements, pricing/availability, review account, and manual-release setting.
7. Run a final pre-submission audit, then submit only with explicit approval.

## Validation performed for this audit

- Latest `origin/main` built successfully on an iPhone 16 Plus simulator running iOS 18.6.
- Current Map, Feed, search, place detail, Add, Lists, Profile, and import surfaces were exercised and captured.
- All concept panels were verified as opaque 1320 × 2868 PNGs.
- The App Store Connect audit was read-only and redacts review credentials.
- App targets are iPhone-only.
- Current legal/support URLs were checked live.

## References

- [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Upload app previews and screenshots](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- [Add a privacy manifest](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)
- [App Store categories](https://developer.apple.com/app-store/categories/)
- [Age rating values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/)
- [Select an App Store version release option](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option)
