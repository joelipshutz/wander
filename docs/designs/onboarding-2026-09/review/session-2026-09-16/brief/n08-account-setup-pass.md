# N08-N12 account setup pass

**T32 override: the profile photo is optional. Name and an available username remain required where applicable. Earlier transcript instructions to require a photo are superseded.**

**Latest N11 decision (T27):** “Keep up with the people you love” is the headline. No subtitle. Remove “Follow a few familiar people. See where life takes them.” Apply the same header to N33/N34; keep their state-specific recovery copy. Implemented and natively captured at `27ce60a`; Follow/search check passed. [Review N11](../?screen=N11&present=1&v=27ce60a).

September 18, 2026. Joe reconfirmed this as the next pass after the opening review: profile, location, contacts, following and notifications. These account-setup screens remain owned by this task. Ryan owns the post-onboarding NUX.

## Transcript direction

The deduplicated source is [T07](../transcripts/T07.txt) for profile and [T06](../transcripts/T06.txt) for location through notifications. Decisions A21-A35 and A63-A66 in [the transcript audit](../transcript-audit.md) distinguish firm direction from alternatives. The later pasted notes accepted the N31-N33 content and requested UI updates, and simplified the N36 Contacts purpose.

| Screen | What was said | Native implementation pass |
|---|---|---|
| N08 Profile, N67 crop, N35 validation | Show the actual profile header, taking roughly half the screen. Name, username and selected photo update it live; fields below, photo above. Name, username and photo are required. Improve field, placeholder and heading typography. Followers/following counts were optional, not settled. | Reconcile the preserved live-preview work with current main identity/Apple behavior. Retain edits through photo selection/crop, username checking, save/upload failure and retry. Test keyboard and compact layout. |
| N09 Location, N30 system request, N31 denied | Explain why granting location is useful. Include a clear subtitle and real in-app moving map/places UI. Compare quote-inspired and direct headlines. Preferred privacy tone: "Your location is yours." | Use the real Map preview. Keep privacy claims accurate. Cover first request, granted, denied/restricted, Settings return and continuing without location. Preserve the accepted denial wording. |
| N10 Contacts, N36 system purpose | "Drop all the invite language from this screen." Explain finding/connecting with people at a high level. Remove the old address-book-upload and Messages-number explanations. | Separate the permission primer from invitations. Reconcile concise reviewed purpose copy with current main and the actual permission flow. Do not claim automatic contact-to-member matching from the existing member search. |
| N11 Following, N33-N34 empty/error | Photo, name and username rows; large rectangular Signal Follow buttons that change to Following. No multiselect or suggested/mutual filler. Search username or display name. Requested ranked contacts with Follow/Invite mixed, and user-controlled message compose for invitations. | Reuse current main Follow behavior where it already works. Verify loading, search races, pending/failure/retry and real per-row actions. Audit the missing contact-matching/ranking dependency before representing matched contacts. Invite-message wording remains a review choice; no messages are sent by this task. |
| N12 Notifications, N32 denied | Show what people will receive: two or three animated notification cards, roughly half-screen. Friend check-in is the leading example. Import-complete and future local events were alternatives. Explore consistent icon/material treatment, including stone/statue. | Use actual native card motion and real authorization handling. Keep examples clearly identified in review evidence. Only represent supported notification capabilities; Events remains Coming Soon. Preserve accepted denied copy and verify Settings return and onward navigation. |

## Order and review checkpoint

1. Finish the opening comparison checkpoint, then start at N08 and walk continuously through N12. The approved production opening remains the baseline while film is an optional exploration.
2. Compare current main against preserved review code/captures before porting anything. The archive already has substantial profile, location, contacts, follow and notification work; captured does not mean shipped. Do not merge its discarded flip-board or Ryan-owned NUX work.
3. Present each screen with its exact transcript excerpt, current Swift copy and explicitly labeled alternatives. Resolve existing open options without reopening accepted denial wording.
4. Implement the reviewed pass in Swift and record the complete journey plus crop, username failure, Follow failure/retry, permission denial/recovery and usable Map arrival. Show the real native screens and animations in the review board with stable N08-N12 IDs.
5. Verify focused interaction paths, light/dark and standard/compact layouts. Preserve required identity work and entered values through errors/backgrounding. Account recovery N68 stays on the related account-entry verification queue.

## Current evidence and remaining work

Existing [N08-onward review](http://127.0.0.1:8766/session-2026-09-16/?screen=N08&present=1) and [native copy inventory](../native-copy.json) are from the preserved review branch. They are useful for the next discussion, not fresh main captures. Main still differs in photo requirement and Contacts invitation language; matching/ranking remains a real feature gap.

The opening/no-X correction now has fresh native verification from the film comparison pass: 22 focused checks passed at `6432401`. That former disk-blocked no-X check is no longer outstanding. Additional account-setup implementation and verification are next, after the current visual checkpoint.

Ryan's Map walkthrough, first-use hints, starter lists, device guides and contextual notification campaigns remain outside this pass. N12 is the signup notification request; N28/N29 later campaigns stay with Ryan.

## September 18 dark UI implementation checkpoint

The active change is in `wander-native-onboarding-review`, branch `codex/rec-529-dark-account-setup`, based on main `c64bc7c`. It uses Astir Ink #141714, Paper #F2E9DB, Signal #F05A3C, the app’s semantic typography and a shared dark setup scaffold. The approved opening and film archive are preserved.

- Profile: actual shared profile identity header, live name/username and chosen/existing avatar. Newer main’s Apple username-only route and optional photo remain intact; required-photo policy is a separate unresolved decision.
- Location: real MapKit plus production selected-place card, including the complete cached Hotchkiss Park photo. A gentle 3.5-second map entrance; Reduce Motion remains static. Direct headline and body preserved; privacy uses the transcript’s “Your location is yours.”
- Contacts: same complete native activity postcard as the opening, concise high-level connecting copy, real Contacts request. The postcard is illustrative. No automatic contact matching has been added.
- Following: real asynchronous profile rows, photo/name/@username, individual Signal Follow actions and per-row Following state. Name/username search, loading, empty/error/retry and duplicate-write protection. No default selections or implied contact matches.
- Notifications: three native example cards with the actual app icon, staggered entrance and reduced-motion support. Dark styling is scoped to signup; contextual campaigns remain Ryan-owned.

Native verification and fresh capture results will be recorded in `../../session-2026-09-16/TASKS.md` T24 and `../native-dark-setup.json`. Existing September 17 media retains its original labels until replacement evidence exists.
