# Astir Events: product spec for review

September 14, 2026 · Draft for whole-document review · Source-fidelity audit recorded

This document consolidates the approved direction through D35 and the September 14 walkthrough amendments. Those later amendments take precedence where they refine earlier decisions. It is ready for whole-document product review, not yet an approved final specification or permission to implement. **Approved** sections carry the user's decisions. **Proposed defaults** are concrete recommendations awaiting this review. D7 reconnection and expanded privacy controls remain deferred. Engineering architecture and storage design follow product approval.

Sources: working product record (authoring reference; not bundled) and 25-state journey matrix (authoring reference; not bundled). Decision references point to the record. Latest approvals incorporate D32A–D35A. The D28 amendment “dont explain reuse pls” remains in force.

Visual review: [complete flow wireframes](./astir-events-flowchart.html) show the main journey, onboarding A/B options, alternate guest paths, and the Astir console. Screen layouts and proposed defaults remain under review; the board does not add product approvals.

Native visual review: [Swift simulator screen gallery](./astir-events-flowchart.html) shows the new surfaces using the Hotchkis Park example from the recording. The numbered wireframes retain the separate Studio Thirty example. Both are local design fixtures, not live event changes.

## 1. Purpose and scope

**Approved direction.** Events bring a guest into Astir progressively: discover a gathering, RSVP, receive helpful preparation texts, enter with Astir installed, return for event content, complete an event check-in, and find their event memory on the normal map and linked place profile. The event should make sense before the guest understands the rest of Astir.

The September session supports Astir 001, a usable 30-friend beta, and the accompanying brand work within Joe and Ryan's capacity. Astir operates the events; this is not a marketplace for outside hosts. Specify the complete experience before agreeing release slices.

Assume Astir is on the App Store before live Events. Support TestFlight testing separately. This is a launch prerequisite, not a claim that release or App Clip availability has already been verified. Free RSVP is the selected first-release scope; paid tickets, checkout, and refunds are excluded (D16, D20A).

Reconnection, missed connections, and “solo, single, or private” remain parked for the founders' next discussion. Expanded profile/check-in privacy controls remain future work. Neither is reopened here (D7, D9).

## 2. Product concepts and permissions

**Approved.** Every event is a time-specific occurrence at exactly one place. A place can have many events or none. Event access, precise-location permission, and personal-post visibility are separate.

| Concept | Meaning and effect |
| --- | --- |
| RSVP | A reservation or request. Pending approval, waitlisted, offered, and confirmed are distinct states. Only confirmation gives confirmed-guest benefits. |
| Admission | Door attendance recorded for this guest and event. This establishes recap eligibility but creates no personal post or place visit. |
| Event check-in | The attendee's explicit post-event submission. It creates one event-labeled personal post/place visit and marks the venue Been, without a venue rating. |
| Personal post | That check-in's social presentation: event identity/date, member identity, optional note, and selected photos. Default audience: everyone in Astir, subject to existing protections. |
| Private feedback | Optional 1–5 stars and an independently optional comment to Astir. Neither appears publicly or becomes a venue rating. |
| Protected recap | The full shared gallery and conversation. Access requires valid recorded admission **and** historical completion of event check-in for this event, including after personal-post deletion. |

RSVP, installation, a publicly visible personal post, or attendance at another event cannot substitute for this event's access requirements. Staff correcting admission do not submit a check-in on the attendee's behalf (D1–D6, D9).

Existing blocks, historical audiences, independent visits/ratings, and explicit place-save intent retain their protections. Event activity and place history represent one logical visit, not duplicate submissions (D4, D9, D33).

## 3. Discovery, sign-in, and RSVP

**Approved.** Shared links and Events navigation lead to equivalent event detail experiences. Prefer App Clip without installation; when it cannot open, support equivalent browser RSVP. An installed app handles its applicable entry. Preserve event and reservation identity across these routes (D14).

**Installed-app entry, explicitly clarified September 14.** An invitation opened on a phone with Astir installed lands on that event inside Astir. Separately, tapping an upcoming event in the new Events tab opens the same in-app detail. Show the event before requesting an RSVP. Tapping a confirmed event card opens its confirmed detail; the separate Show ticket action opens its QR. Both entry paths resolve the account’s actual confirmed, pending, waitlisted, offered, or unregistered state. Opening a link or card does not itself submit an RSVP. Reuse a valid session and verified matching phone; if signed out, preserve this event through sign-in, cancellation, and return. Installation and the new-user setup sequence are not repeated for an already set-up member. Capacity, access-code and location restrictions remain the same. The comparison board shows full app, App Clip, and browser across unknown identity, known account without an RSVP, and recognized confirmed RSVP. Unknown identity is not proof of no RSVP: recover the account before choosing a booking state. Forwarding the canonical event link never transfers the sender’s identity or reservation.

The event detail uses immersive imagery, title, concise description, and date/time. Before RSVP, the face pile and guest count are an explicit conversion hook. The full guest list unlocks only after **confirmed RSVP**; pending applicants, waitlisted guests, and unaccepted offers do not qualify. This is separate from the stricter attendee check-in requirement for the protected recap. RSVP is primary before registration; the confirmed state offers View or change RSVP with cancellation inside management. Share sits at the upper right. Recognized confirmed guests can view the full guest list and manage their RSVP in App Clip/web without downloading. The full list places followed people first and shows mutual counts, while preserving existing protections. Apple's invocation card is distinct from Astir's event screen (D30B).

Before RSVP, clearly explain that entry requires a supported phone and installed Astir. A desktop visitor may own such a phone; browser usage alone must not imply incompatibility. Browser RSVP does not create browser-only admission (D15).

Offer Apple and Google sign-in. Collect name and phone without unnecessary repetition. Verify the number by SMS before confirming RSVP; reuse an already verified matching number where applicable. Explain event-specific texts and offer a separate unchecked optional future-event opt-in. Leaving it unchecked does not prevent RSVP or suppress event updates (D17, D19).

Support optional invitation codes configured in the internal web console. Operators can generate codes with capped or uncapped usage, include them in invitation text, or leave the feature off initially. Invitation codes remain distinct from phone-verification codes. Redemption and usage accounting details still require engineering decisions. RSVP is free. Automatically confirm eligible requests when unprotected space is available by default; Astir can enable manual approval in its console. Pending approval must be visibly different from confirmation. Confirmed guests receive a confirmation state, full guest-list access, calendar access, and their event at the top of Events (D20–D22, D30–D31).

## 4. Full events, offers, and cancellation

**Approved.** At capacity, offer an event-specific waitlist. Astir chooses who receives available spots; there is no automatic first-in-first-out promotion. This is separate from the simple city-level “events coming soon” state (D21).

Selection sends a spot offer that the guest must accept. Its default expiry is 24 hours, adjustable in the console. Bounding an offer by registration closing is a proposed operating rule below. An unaccepted offer is not confirmation. Guests can cancel their confirmed RSVP before event start, releasing the spot (D23–D24).

**Approved.** While a waitlist exists, released spaces are protected for Astir's selections. New guests join the waitlist rather than automatically taking those spaces. Protecting the spaces does not automatically select or promote a guest; Astir still chooses recipients and each offer requires acceptance (D31A).

**Proposed defaults.** Hold one spot for each outstanding offer until acceptance, decline, or expiry. Clearly show the deadline. Expired acceptance opens “Offer expired” with no ticket; duplicate acceptance shows the existing confirmation. Do not automatically send the next offer. Keep an expired or declined entry visible to operators for deliberate reselection. Close registration at event start unless Astir sets an earlier time; this would also bound the offer deadline.

## 5. Preparation, location, and admission

**Approved timing, amended by the September 14 walkthrough and explicit download clarification.** RSVP finishes in App Clip/web, with Add to calendar and an optional, dismissible download offer explaining that the entry QR is in Astir. The guest may stay on the event, view the confirmed guest list, manage their RSVP, and receive confirmation/reminder texts without installing. Full-app installation is required for the entry QR and admission; it is not a gate on those confirmed-RSVP actions. Every View event link returns to the same canonical event in the receiver’s available surface and actual account/booking state. The exact point when the later QR reminder becomes more prominent remains undecided.

**Approved.** Returning RSVP guests receive shortened, event-preserving app setup. Strongly prompt for a profile photo, but allow skipping it. A missing profile photo cannot block RSVP, QR access, or event check-in. The admission QR lives in Events (D18).

Automatically send confirmation, reminders 24 hours and two hours before the event, important changes, and the published-recap invitation. These messages are configurable from the console. Event-specific delivery remains distinct from optional future-event texts; recap invitations follow publication (D19, D26, D29A).

Homes are a special place type. Their event/place association can remain discoverable with an approximate area instead of the exact location. The resident/owner or renter must consent to venue use. Exact address access goes to confirmed guests 24 hours before event start by default, configurable per event. Later confirmations receive it immediately after that threshold (D8, D13).

Exact-address access expires for all guests 24 hours after the event ends by default. Astir can adjust the cutoff per event in the console. The event and place return to approximate location, including their navigation affordances. Event history, personal check-ins, and otherwise-valid recap access remain. This does not revoke independent location rights or recall an address already seen (D35A).

The same location restrictions apply to map pins, place profiles, histories, and event previews. Discovering an event or seeing someone's public event post does not grant its private address.

At the door, staff normally verify the full-app event QR and record admission. If an installed-app guest cannot load it, staff may verify them against their confirmed booking and record admission manually. This is not an unsupported-device waiver. Staff can later correct missed admission scans; RSVP/no-show or self-confirmation alone does not establish attendance (D5, D15, D25).

The proposed door procedure below addresses identity, duplicate scans, reentry, and connectivity. Canceled or invalid bookings do not automatically qualify for the QR-loading fallback.

## 6. Post-event check-in, recap, and media

**Approved.** Astir publishes the recap as ready from the console, then invites attendees back through a content notification and text. An eligible attendee completes an event-specific check-in analogous to place check-in. Note, own photos, event-specific tags, and private feedback are all optional; submitting every field empty is valid. There is no public rating (D1–D2, D26). Use the existing check-in composer idiom. Astir can generate suggestions and configure event tags in the web console; ten tags is an illustrative example, not an approved fixed count.

Private feedback offers optional 1–5 stars and an optional comment to Astir, with no star selected by default. Both may be skipped independently. It remains separate from the public note and cannot create or change a public venue rating (D34A).

If an attendee has deleted the app, the event remains viewable in App Clip/web; choosing check-in or upload explains reinstall, then recovers the same attendance and completion. No second RSVP/admission is created. The composer makes public post content distinct from private feedback. Show the requested small eye audience indicator. Public presentation leads with the event, for example, “Rachel checked into Vinyl Sound Bath on [date].” Venue association remains intact. Successful submission creates one place visit and opens the attendee recap, not the map (D4, D9).

Before submitting, guests can select their own photos. Protected event-gallery photos become available only after unlock and can then be featured in the same public Astir event check-in. Do not add a reuse explainer, disclosure, extra prompt, or replacement approval step. Retain the existing small eye audience indicator and ordinary public/private labels (D6, D9, D28 plus amendment).

The intended recap contains event recap content, Astir-provided and attendee-provided photos/videos, prominent comments/social activity, and personal check-ins. Attendee shared-gallery uploads appear immediately to eligible viewers; uploaders can remove their own media and Astir can moderate it. The full gallery and conversation remain restricted to admitted, checked-in attendees. Selecting a gallery photo for a public event check-in does not open the rest of the gallery (D1, D3, D5, D27–D28).

Nonattending members can see an Astir-wide event preview. Show the comments area's locked state without readable comments. Public personal posts remain visible according to their own audience; this does not open the shared gallery. Teaser copy must never imply that joining a future event unlocks this past event (D3, D9).

**Approved removal behavior.** When an uploader or Astir removes a source gallery photo, remove that photo everywhere it is referenced within Astir, preserving the rest of each check-in. Do not add a reuse explanation. Deleting a personal post removes its event visit but retains historical check-in completion for recap access while valid attendance persists. Do not erase admission, independent visits, or independent ratings (D32–D33).

Proposed media/comment defaults below cover remaining presentation and interactions; source-photo propagation, personal-post deletion/access, and private-feedback fields are settled.

## 7. Events, map, and permanent place history

**Approved.** Events places confirmed events first, followed by a simple upcoming-nearby list. Keep the no-upcoming-events state simple. The associated place profile provides a lasting route to its events and each viewer's applicable recap or preview.

A special map treatment signals an upcoming/recent event to everyone permitted to discover it, subject to location rules. It is not restricted to attendees' completed memories. The normal map remains visible: tapping a special event pin opens a collapsed event card over the map, and expanding that card opens the full event view. The card reads “Astir 001 at [place]”, with smaller “at” and support for long place names. The event links to the standard place profile, which includes inline Events here history. When special styling ends, ordinary place access still exposes event history (D10, D12).

The internal console is a simple authenticated web interface, including the staff scanner; it is not a tab in the native guest app. It supports event setup, post-event publishing, and first-party media, plus pin on/off, start/end, style presets, and preview. Within the promotion window, Featured includes all permitted viewers, You reflects their attendance, and Friends reflects relevant friends’ attendance. Second-degree Friends scope remains undecided. Square, round, glow, and pulse pin studies are alternatives, with reduced-motion support; none is a selected final style. It also controls exact-address reveal and expiry timing, manual RSVP approval, waitlist selection, offer expiry, recap publication, and event messages. These controls cannot grant an ineligible viewer protected location or recap access (D11, D13, D22–D23, D26, D29, D35).

**Proposed defaults.** Display special styling from seven days before the event through seven days after, within operator controls and only once published. At a shared venue, prefer a currently live event, otherwise the next upcoming event, otherwise the most recently ended event whose display window remains active. If multiple events are live, choose the earliest start, then title as a tie-breaker. Show a route to the venue's other events. These precedence and timing rules are proposals, not D12 decisions.

The recap has an event-focused cover and the familiar place-profile structure, comment actions, a plus control for photos/videos, and upper-right Share. The share destination/payload for Instagram remains to be defined. Delete the invented dedicated recommendations screen (old 31) and Explore nearby branch from old 30. Ordinary Astir discovery remains available; the place profile has inline event rows, not a giant event button at the bottom.

## 8. Routine defaults proposed for whole-draft review

None of this section is approved. These concrete defaults reduce repetitive decision rounds while exposing consequential effects for review.

1. **Interrupted entry:** retain event context through authentication cancellation and offer retry. If the account differs from the booking owner, offer account switching and support; never silently merge identities or create a replacement reservation. Repeated RSVP actions show the existing state.
2. **Verification recovery:** offer code resend after 60 seconds and an edit-number action. An edited number must be verified. Show expired/incorrect-code errors without discarding the event. Engineering/provider validation may change the countdown; verification remains required.
3. **Cancellation:** ask once before canceling; then show a canceled state, invalidate admission access, and remove precise-address/navigation entitlement. Preserve the confirmation history for support. Already disclosed addresses cannot be recalled. Rebooking follows current availability and approval rules.
4. **Offer and approval changes:** changing approval mode affects new requests, not existing confirmations. Pending requests remain pending until Astir resolves them. Changes to offer duration apply to new offers; changing an issued deadline requires a guest-visible update. Held offers cannot silently exceed capacity.
5. **Event changes:** show canceled events as canceled at their original link, stop normal reminders, and invalidate tickets. A reschedule preserves reservations while clearly showing the change and offering cancellation. Recalculate future address reveal from the new start; flag already disclosed information for the operator.
6. **Check-in recovery:** preserve a draft after failure. A lost response or repeat submission returns the existing completion instead of creating another visit. If photo upload fails, offer retry or explicit submission without that optional photo. Never announce successful publication while silently dropping requested media.
7. **Post editing:** edit note/media and private feedback separately. Recompute event-derived Been after deletion while preserving independent visits, ratings, and explicit place-save intent. Use a neutral removed-photo state without explaining reuse. These interactions supplement approved D32–D34 behavior.
8. **Private venue presentation:** use a stable neighborhood area rather than an exact-house-centered circle. Label it “Approximate location.” Show the event title, general neighborhood/city, and approved event imagery; omit street address, house number, exact coordinates, and exact navigation until eligible reveal. Require the operator to record venue consent before publication. Apply approved D13/D35 reveal/expiry consistently across event and place surfaces.
9. **Time and controls:** show the event's local time zone on event detail, offers, and calendar entries. Console edits remain drafts until explicit Publish; preview distinguishes guest and nonattendee views. Surface successful publication and failures. Warn when a change affects confirmed guests; do not silently issue unrelated messages.
10. **Reminder recovery:** send confirmation for a late RSVP, skip reminder times already passed, and send each remaining scheduled reminder once. SMS opt-out stops texts without canceling the RSVP; event details and the ticket remain available in Astir. Changes update the event view even if delivery fails.
11. **Capacity and approval:** pending approval/verification do not hold seats; active offers do. Manual approval immediately confirms an eligible pending request only when unprotected capacity exists. Otherwise keep it pending and show the operator why; offer an explicit move to the waitlist with a guest-visible update. Any later waitlist promotion uses the approved offer/acceptance flow. Declined/expired offers release their holds and return to waiting for Astir's reselection. Waiting or offered guests keep the waitlist active; guests may withdraw and staff may remove entries. Prevent capacity reductions below confirmed guests plus active offers until Astir resolves the excess.
12. **Guest-list presentation:** show permitted existing profile photos from confirmed guests and the confirmed count before RSVP. After confirmation, place followed people first with mutual counts and show display names/profile photos; omit phone numbers and pending/waitlisted people. Preserve existing restrictions. The count and visible face selection may differ when protections apply.
13. **RSVP return onboarding:** recover the reservation's signed-in account and verified-phone status; a stored phone string alone proves nothing. Complete required name and username before the entry QR, collecting only missing values, with the strong optional photo prompt, then open Events and its QR. Defer location, contacts, friend discovery, notifications, and the general walkthrough until relevant use; never put them before the ticket. RSVP-only accounts follow existing profile/privacy discovery rules for signed-in Astir members, including before full onboarding; this grants no anonymous web exposure. The latest walkthrough approves required name and username before entry/QR, with photo optional and saved data reused. Broader deferrals and exact layout sequencing remain proposed; this is not an existing Events capability.
14. **Media and conversation:** show “Recap coming soon” before publication. The discussion already calls for shared photos/videos, comments, replies, and likes; immediate eligible uploads and Astir removal are also approved. Exact controls, reporting, and editing behavior remain proposed. Propose own photo/video support in the personal composer; gallery-photo reuse remains as approved. Failed uploads retain a retryable draft. Uploader removal and operator moderation apply immediately without prepublication approval. No reuse explanation is introduced.
15. **Door and operator procedure:** staff match the signed-in account to its confirmed booking before manual admission. Repeat scans show prior entry rather than add attendance; a staff lead approves reentry. Prepare an offline confirmed roster with visible freshness and log assisted admissions for reconciliation. If eligibility cannot be established, hold the guest for staff-lead resolution rather than record invented attendance. Operators manage event publication, approval, waitlists, guest cancellation, and moderation; log corrections and keep a guest-facing help route.
16. **Participation:** one named booking per person; each additional guest completes their own RSVP, verification, installation, and admission. No transferable QR or anonymous plus-one. A walk-in follows that same flow only while registration is open and capacity permits. Pending applicants may withdraw; operator rejection explains the resulting state without exposing internal notes.
17. **Events navigation:** add Events between Feed and Lists: Map, Feed, Events, Lists, Profile. Keep confirmed upcoming/current events first, ordered by start time. Below them, show the member's pending requests, waitlists, and offers with explicit status and applicable next action, then upcoming nearby events. Provide a Past events entry for past reservations and attendance, newest first; it opens the viewer's eligible preview/composer/recap. With no nearby events, show “Events coming soon” without an extra onboarding task. Loading, retryable failure, and genuinely empty results must look different.
18. **Access codes:** after tapping RSVP, ask for a required code before completing the reservation flow, equivalently in Clip, browser, and app. A missing/invalid code gives an inline error and retry; retain the event and any completed identity steps. A code prefixed in the event link may prefill the field but must still be validated. Changing a code affects new requests, not existing confirmations or valid spot offers. A valid code does not override capacity, approval, device, or verification requirements.
19. **Publishing an event:** internal operators create a draft with a title, cover image, description, start/end and time zone, one linked place, location type, capacity, and RSVP rules. Resolve or create the venue before publishing; home venues also need recorded consent and approximate/exact-location settings. Block publishing if required information is missing or times/capacity are invalid. Preview shows the public detail, confirmed-guest view, and location schedule; Publish makes the event discoverable under its configured access rules. Draft/unknown links show an unavailable state and a route back to Events.
20. **Share, calendar, and saving:** Share opens the event's existing link with permitted preview content. Offer Add to calendar after confirmation; a failed or unavailable calendar action leaves the reservation intact and offers another supported route. Calendar entries use the event time and link, with an approximate label for a private home rather than embedding its exact address. Propose leaving a separate Save event/bookmark action out of the first release; it was discussed but not selected, and remains part of this review rather than an approved scope cut.

**Proposed post-event return states.** These apply to links, Events, and place history, whether or not a text arrives:

| Situation | What the guest sees and can do |
| --- | --- |
| Event ended; recap not published | “Recap coming soon.” Preserve attendance/booking status. Do not request the required event check-in until publication. |
| Published; valid admission, no completed check-in | Show the event check-in invitation/composer; submitting opens the recap. |
| Published; valid admission and historical completion | Open the recap directly, including if the personal post was deleted. |
| Published; confirmed booking but no recorded admission | Show the preview and a “Were you there?” help route to request staff correction; self-report does not unlock content. |
| Staff corrects a missed scan after publication | The guest becomes eligible for the composer, or recap if historical completion exists. Issue the attendee invitation once; staff do not create the post. |
| A mistaken admission is revoked | Remove protected access; show preview/help. Preserve independent place history; existing post moderation is a separate explicit action. |
| A published recap is temporarily unavailable | Preserve completion and drafts; show an unavailable/retry state. Restoring the same recap does not force another check-in or resend invitations automatically. |

The scope now includes an isolated SwiftUI front-end mock and simulator screenshots using local sample data. This authorizes that design artifact only; live Astir code, backend changes, and a release remain separate. Planned exit criteria (authoring reference; not bundled) describe the end-to-end checks required before implementation can ship; these are not executed integration tests.

## 9. Whole-document review

The September 14 internal requirements audit (authoring reference; not bundled) traces each product requirement to original user wording or its exact question/answer pair. It separates approved requirements, derived consistency constraints, unapproved operating proposals, open design choices, and deferred work. No count of screens or passing artifact check establishes product approval.

The standalone decision queue through D35 is resolved, with D7 explicitly deferred. Review the full journey plus the proposed defaults in sections 4, 7, and 8. In particular, the remaining account-discovery defaults beyond the approved name/username gate, one-person bookings, door procedure, media interactions, and operating rules are proposals rather than prior approvals.

Design review is already authorized and in progress; it specifies screen hierarchy, navigation, copy, and empty/error states. Engineering review will ground the event/place relationship, identity handoff, permissions, message delivery, and migration/rollback plan in the existing app. These later reviews may reveal a concrete tradeoff to bring back; they are not permission to reopen settled direction or add the deferred reconnection/privacy features.

## 10. Product review acceptance scenarios

Before final approval, walk the complete experience as a new Clip guest, browser fallback guest, existing member, pending applicant, waitlisted guest, and door operator. Follow each through interruption, recovery, and return.

| Scenario | Required result |
| --- | --- |
| A guest opens the event without a working Clip | Browser RSVP retains the same event; later app entry returns to the same reservation. |
| RSVP is interrupted by sign-in, code entry, or phone verification | Retry preserves context; no unverified or duplicate confirmation appears. |
| An event fills while an eligible request is being processed | Capacity is respected; pending/waitlist/offer states remain explicit, and protected released spots go through Astir selection. |
| A guest is pending, waitlisted, or holding an unaccepted offer | Show the guest-list hook; do not grant confirmed guest-list, ticket, or address benefits. |
| A confirmed guest installs Astir before arrival | Reach their event QR with the agreed identity/photo requirements; the proposed shortened route does not require general onboarding first. |
| An installed-app guest's QR cannot load | Staff can establish eligibility and record one admission; duplicate actions do not create another attendance record. |
| A confirmed guest did not attend | They cannot unlock the protected recap through RSVP or self-report. A missed-scan correction must come from staff. |
| An admitted guest submits an empty event check-in | Create one event-labeled venue visit, no venue rating, and open the recap. |
| A guest includes private stars/comment | Private feedback is absent from the public post and public venue rating. |
| A completed attendee adds gallery photos, then the source is removed | Keep one visit; remove only the referenced source photo from affected posts and preserve remaining content. |
| An attendee deletes their personal event check-in | Remove that post/visit; retain eligible recap access and independent place saves, visits, ratings, and audiences. |
| A home passes its reveal or expiry boundary | Exact address/navigation follows the configured eligible window; approximate location and event history persist elsewhere. |
| A viewer returns through Events, a place, a shared link, or a recap text | The same identity, attendance, completion, publication, and location rules determine what they see. |

Confirm the full product behavior and proposed defaults before treating this as the product baseline. Design review remains in progress; engineering review follows the approved product/design baseline. The separate SwiftUI sandbox is a front-end design artifact; no production app/backend implementation is included.
