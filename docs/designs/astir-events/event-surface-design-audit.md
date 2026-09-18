# Astir Events: surface design audit

> Historical September 10 design study. The September 14 walkthrough supersedes conflicting details below: confirmation has an optional download offer; recognized confirmed guests manage RSVP and see the full guest list in App Clip/web without installing; name and username are required before entry/QR; map tap opens a collapsed card first; the invented recommendations detour is removed. Use [current revision notes](revision-20260914/review-notes.md) and [current product draft](product-spec-draft.md) for the current baseline. Earlier unselected proposals remain historical, not renewed questions.

September 10, 2026 · Independent design proposals for integration

Read against [product draft](product-spec-draft.md), [journey matrix](journey-state-matrix.md), and [DESIGN.md](https://github.com/joelipshutz/wander/blob/f8d258e869503a28d70518a050dff36a344134c6/DESIGN.md). This is a screen-specification pass, not a visual implementation or runtime test. D1–D35 remain authoritative. The proposals below do not approve the product draft's operating defaults.

## Visual and behavioral foundation

- Use DESIGN.md's **provisional Astir override**, which supersedes its older cream/terracotta/Funnel guidance: warm paper and ink, coral action accent, native editorial-serif titles, Avenir Next body/controls, adaptive Light/Dark. Keep semantic success/warning/error colors distinct from the brand accent.
- Use 8-point spacing, 44-point minimum targets, continuous rectangles, editorial underline tabs, and localized glass on individual header controls. Do not place the full header in one glass slab or build nested decorative cards.
- Let photography establish the event; keep status and the next action stable over a readable scrim or solid surface. Do not put essential copy over uncontrolled bright imagery.
- Later event decisions supersede DESIGN.md's older four-tab shell and its “Everyone means followers” wording. For new event check-ins, the ordinary audience label means **Everyone in Astir**, respecting existing restrictions. Do not open a new privacy-selector flow.
- Event-specific shortened setup is a written proposal. Keep validated identity/account separation intact; never show another account's ticket or private venue underneath a loading/authentication state. Do not insert the legacy general walkthrough before the proposed RSVP-to-QR route.

## Event detail: status determines the primary action

Above the fold, group only three things: **event identity/time**, **social proof and booking state**, and **one next action**. Use a persistent bottom action area above the safe area; keep Share as an independent header action. Guest-list access is secondary to the main action.

| Guest state | Main action/status | Supporting presentation |
| --- | --- | --- |
| Unregistered; automatic mode has capacity | **RSVP** | Face pile/count; concise free-entry and installed-app requirement. |
| Unregistered; manual approval enabled | **Request to join** | The same conversion hook; plainly state that Astir confirms requests. |
| Full or released capacity protected for waitlist | **Join waitlist** | No “spot available” claim while allocation belongs to Astir. |
| Interrupted sign-in/code/verification | **Continue RSVP** | Resume the unfinished step; retain event title. A saved phone string is not a verification-success badge. |
| Pending approval | **Request pending** status | “We'll let you know.” No fake active confirmation button. Withdraw is secondary if the proposed operating rule is accepted. |
| Waitlisted | **On the waitlist** status | Keep face pile/count; no ticket, full guest list, or exact-address benefit. |
| Active spot offer | **Accept spot** | Absolute deadline plus readable remaining time; Decline secondary. Do not describe the offer as a confirmed booking. |
| Confirmed in Clip/browser | **Get Astir** when installation is needed; **Open Astir** when available | Confirmation stays visible; full guest list and calendar remain available. Explain the app is needed for the ticket. |
| Confirmed in app | **Show ticket** | Confirmation, event time, and location state. Full guest list/calendar are secondary. |
| Offer expired / RSVP canceled | Clear expired/canceled status | Show the available next route from the actual booking rules; do not restore an obsolete Accept or ticket button. |
| Event canceled | **Event canceled** | Preserve recognizable event identity; Back to Events. Remove obsolete RSVP/ticket action. |
| Event ended; recap unpublished | **Recap coming soon** | Preserve booking/attendance state. The draft proposes waiting until publication before inviting check-in. |
| Published; valid admission, no historical completion | **Check in** | Brief promise of event photos and conversation; optional contribution is not described as required. |
| Published; valid admission and historical completion | Open the recap directly | No repeated Check in prompt, including after personal-post deletion. |
| Published; no recorded admission | Preview, with **Were you there?** help for a confirmed guest | Staff-correction route does not offer self-service attendance confirmation. |

For long events, let the title wrap above metadata; never let it push Share or the primary control off its target. On small screens or large text, reduce the image height rather than shrink the title or hide booking status.

**State treatment:** load neutral structural placeholders without a false guest count or booking status; show a retryable unavailable screen for failed event loading; retain a resolved confirmation if a secondary calendar action fails. RSVP success replaces the action with the confirmed state immediately after confirmed success; no extra celebration screen should obscure the ticket route.

## Guest ticket and staff scanner

**Guest ticket hierarchy:** event name/date → guest name/handle → large high-contrast QR on a plain field → booking status → “QR not loading? Ask staff.” Keep navigation and ornamental imagery away from the QR quiet area. A ticket-loading failure retains event/guest context and Help at door; it does not suggest bypassing installation.

Do not style an unverified cached state as current validation. Preserve any permitted ticket presentation, but label stale/unavailable status accurately. A signed-out/account-switch state removes the previous ticket. Ticket success means ready to present; admission success is a separate staff result.

**Staff scanner hierarchy:** selected event and session time at top, camera/scan target dominant, **Find guest** secondary. A manual booking result shows identity and confirmed/pending/canceled status before any admission action. Only the approved installed-app/confirmed-booking fallback gets **Record admission**; do not make it a generic override.

| Scanner result | Required emphasis |
| --- | --- |
| Accepted | Large **Admitted**, guest identity, time; **Scan next**. One attendance result; no confetti. |
| Already admitted | **Already admitted at [time]**, distinct warning treatment. Reentry follows the draft's proposed staff-lead procedure; do not show another green admission. |
| Pending/waitlisted/canceled/wrong event | Specific status and event identity. No generic “QR failed” message that implies the fallback is appropriate. |
| Unreadable QR | **Try again** and **Find guest**; preserve the active event. |
| No matching confirmed booking | Clear result with staff-help route; no fabricated confirmation. |
| Offline/roster outdated | Persistent freshness label and locally recorded-entry indicator. These support the proposed offline procedure and do not themselves approve stale-roster admission. |

Make **Admitted**, **Already admitted**, and **Cannot confirm** distinguishable by words, icons, and layout as well as color. Do not auto-dismiss a result before staff can identify the guest.

## Composer and recap

**Composer order:** compact event title/date/place association → “Your event check-in” with small eye and ordinary audience label → optional public note and own-media picker → visually separate “Feedback to Astir · Private” → optional 1–5 stars and independent comment → persistent **Check in**.

All optional fields can be empty and the action remains enabled. Stars start unselected. Private feedback must not resemble the venue-rating control or sit inside the public post preview. Own-video support is a draft proposal; keep it visibly separate from the already approved shared-gallery photos/videos scope.

Do not show the protected event-gallery picker before completion. After unlock, add gallery photos to the same personal check-in using the ordinary media picker. **No reuse explanation, disclosure, extra prompt, or substitute approval.** The existing eye indicator remains; it does not open deferred privacy controls.

During submission, show progress in the existing action and preserve entered content. On media failure, offer Retry or explicit continuation without the optional failed media; never silently drop it. On success, land inside the recap with a quiet “Checked in” acknowledgment. A return after a lost response restores completion, not a second composer/post.

**Unlocked recap hierarchy:** compact event recap header → prominent comment entry/recent conversation → shared gallery → personal check-ins. Keep comments near the top; media still earns substantial visible space. Proposed replies/likes/reporting use ordinary thread controls. Shared uploads appear immediately for eligible viewers, with uploader removal and Astir moderation.

**Locked recap:** show approved event-preview material and a labeled locked comments region using unreadable placeholder shapes, not protected text under blur. Use neutral avatar placeholders unless identity access has been explicitly established. Recommended copy: “Comments are for attendees.” A secondary **See upcoming events** route must not imply another event unlocks this one. Do not invite an ineligible viewer to submit a check-in.

**Empty/error/removal:** distinguish “No photos yet” from failed gallery loading; keep conversation usable if only media loading failed. Retry preserves completion. Removing a source photo removes that image from referenced posts and leaves their other content; use a compact neutral removed-image treatment. Deleting a personal post leaves valid recap access and independent place history intact. An admission revocation changes the protected view to preview/help, not a blank broken page.

## Private location and navigation

Use one location row vocabulary across event, ticket support, place history, and map selection:

| Location state | Presentation |
| --- | --- |
| Approximate, before eligible reveal | Neighborhood/city, **Approximate location**, stable area visualization. No exact-house-centered radius or exact Directions link. |
| Confirmed guest before reveal | Same area plus **Address available [date/time]**. The full guest list can already be accessible; location remains a separate permission. |
| Eligible window | Exact address and **Directions**, using the event's configured reveal/expiry. |
| Event entitlement expired | Return to the approximate treatment and remove exact navigation. Preserve event history/recap. Independent rights are evaluated separately. |

When permission changes while a view is open, update the location row and map representation together. Do not leave the street address in a collapsed sheet, accessibility label, calendar text, or shared preview. Avoid a disorienting map jump. A private venue's temporary event styling must not reveal its exact point.

Use the product draft's **proposed** Map, Feed, Events, Lists, Profile shell rather than reverting to the older four-tab DESIGN.md example. Preserve existing capture access; Events is not a renamed place-add action.

Within Events, show confirmed upcoming/current events first. Surface each pending/waitlist/offer state with its actual next action, then nearby discovery; provide a quiet Past events route. Loading placeholders, “Events coming soon,” and “Couldn't load events · Retry” are different states. No extra signup task in the empty state.

Map pin → event view → associated place is a reversible path: Back returns to the same map position or list scroll position. Place profiles get an **Events at [place]** section with upcoming events and dated history. Tapping history resolves to preview, composer, or recap by the same rules as a text link. It does not force another visit/check-in. Special-pin expiration removes styling, not the history section.

## Accessibility and three-second review

- Validate each state at narrow phone width, largest supported Dynamic Type, Light/Dark, VoiceOver, and Reduce Motion. Let controls stack; do not scale text down to preserve the hero.
- Give event titles enough wrapping space. In compact rows, truncate predictably and expose the full title on detail and to assistive technology. Keep names away from status/action targets.
- Label the eye “Audience: Everyone in Astir”; label feedback “Private, visible only to Astir.” These are ordinary labels, not new onboarding explanations.
- Read locked comments as locked, never their protected content. Group the face pile with an accurate guest-count description; no fictitious social proof. Read offer deadlines as full date/time without announcing every countdown tick.
- Announce state transitions once, including confirmed RSVP, admission, failed submission, and completed check-in. Preserve keyboard/focus after errors. QR has a descriptive alternative and accessible help route.
- Reduce Motion disables decorative pin pulses, parallax, and autoplay transitions. Use localized glass only where contrast remains readable; provide a solid treatment when needed.

For every screen, a three-second review should identify **which event**, **my current state**, and **what I can do next**. Pending/waitlisted states may correctly say no action is needed. A ticket must look like a ticket; a private feedback field must not look public; a nonattendee must not mistake a preview for unlocked access.

## Taste choices for root integration

No new product gate is required. Two visual choices can be resolved during design review:

1. **Hero intensity:** recommend an immersive image occupying roughly the upper third to half of a standard phone, collapsing gracefully for long titles/large text. Alternative: a taller opening image. Preserve the status/action position in either treatment.
2. **Event-marker silhouette:** recommend an event badge around the existing venue marker, with style presets, rather than replacing place identity entirely. The selected treatment must remain distinguishable from Been/Wanna and from a person's live location.

D7 reconnection and expanded privacy UI remain absent from these surfaces. Neither choice reopens them or changes the approved access rules.
