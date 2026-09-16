# Astir Events — remaining decisions at engineering handoff

Source review: September 15, 2026, after engineering D19A authorized final handoff synthesis. This is a decision inventory, not approval of the product draft, authorization to implement, or a claim of production readiness. Product D1–D35 and engineering D1–D19 are separate numbering systems. Later explicit amendments take precedence over older audit labels.

**Count: nine unresolved product/design decision groups.** Each group identifies its constituent choices; nine is a grouping count, not a count of individual yes/no questions. These can be resolved through a coherent whole-draft review rather than nine more question rounds. Routine proposed defaults and engineering validation are listed separately and are not secretly approved by this grouping. Not every remaining layout detail blocks the foundation.

Primary sources: [product draft](product-spec-draft.md), especially lines 134–167; [engineering decisions](engineering-plan.md), especially D3–D14; [working product record](working-product-record.md), lines 135–150; [September 14 amendments](revision-20260914/review-notes.md), lines 21–33 and 49–51; and the [source requirements ledger](audit/requirements.tsv). Line references describe the source at this review; the conditional engineering handoff is complete.

## Nine decision groups

### OD01 — Changes to registration rules, offers, and the active queue

**Approved invariant.** A valid offer holds a seat and any required code allowance until its deadline; timely eligible acceptance confirms it. Pending applications and ordinary waitlist entries hold neither. Released inventory is protected while the waitlist exists. Individual-code deactivation preserves already-submitted verified requests, but does not grant quota. New registration closes at event end by default, with an earlier console override; closing registration does not withdraw an existing valid offer. Upcoming-event rescheduling does not silently alter an issued promise. Engineering D4–D6 and D10–D14 settle these rules.

**Still unresolved.** Select how new offer deadlines are bounded by registration close/event end, and what an operator may do when a later closing-time or schedule edit conflicts with an issued deadline. Also settle prospective versus retrospective approval-mode/code-cap/whole-event-code-rule edits; the proposed explicit pending-to-waitlist action; what happens to declined/expired offers; and which waiting/offered/withdrawn states keep waitlist protection active. Guest withdrawal and operator removal are proposed queue controls, not selected rules.

**Proposal on record.** Approval changes affect new requests; pending requests remain pending. New offer-duration settings affect new offers; changing an issued deadline requires a guest-visible update. Declined/expired offers return to waiting for reselection; waiting or offered guests keep the waitlist active. These do not yet resolve every deadline conflict and must not be treated as a complete approved contract.

**Blocks / foundation.** Blocks final registration/configuration transitions and queue/offer acceptance contracts. Identity, event retrieval, ordinary confirmed-booking retrieval, and already-selected capacity/code invariants can proceed. Sources: product lines 58, 64–78, 139, 146, 153; engineering D4–D6, D10–D14.

### OD02 — Event cancellation, venue changes, and later edits

**Approved invariant.** Moving an upcoming event to a future date preserves confirmed bookings, seats, code uses and the canonical link; it sends the important-change notice and recalculates future event-relative scheduling. Astir publishes the recap when ready and then invites eligible attendees. Neither approval determines event-wide cancellation, a venue change, or edits to a completed event.

**Still unresolved.** Confirm the event-wide cancellation behavior and its consequences for bookings, code allowance, admissions, location access and messaging. Define which venue changes and completed-event edits are permitted and their consequences, especially where historical place association or protected location is involved. A temporary recap outage is a recovery state; it does not, by itself, authorize a new operator “unpublish recap” capability.

**Proposal on record.** Keep the original link showing a canceled event, stop normal reminders and invalidate tickets. The draft does not settle all associated accounting/history consequences. Do not infer them from individual self-cancellation.

**Blocks / foundation.** Blocks destructive lifecycle/admin actions and their final acceptance cases, not creation, preview, normal publication, or the approved future-to-future reschedule path. Sources: product lines 74, 140, 167; engineering D11, D13.

### OD03 — Participation rules and exceptional door handling

**Approved invariant.** Admission requires the installed app, the correct account/confirmed booking and required identity. Staff can handle a QR-loading failure through verified lookup. A prepared offline roster permits durable pending admission followed by server reconciliation; it does not permit offline signup or protected recap access before validation. Every authorized console user has the single Team admin role. Duplicate submission must not create duplicate attendance.

**Still unresolved.** Select the physical reentry policy and the allowed outcomes of a Team admin's exceptional identity/booking-conflict review. Confirm the proposed participation defaults: one named booking per person, no anonymous plus-one, and withdrawal of pending applications. A transferable booking/QR has not been approved; introducing one would require additional scope, not an assumed solution to account recovery.

**Proposal on record.** When identity or a qualifying roster entry cannot be established, route to team resolution without inventing eligibility. Present rejection without internal notes and retain actor attribution. This does not specify permission to waive a required account, phone verification, installation or capacity constraint.

**Blocks / foundation.** Blocks the final exception/reentry and participation policy, not ordinary online admission or D9's pending/reconciliation mechanics. Sources: product lines 96–98, 150–151; engineering D3, D7, D9, D14.

### OD04 — Reminder prominence and channel behavior

**Approved invariant.** The configurable event program includes confirmation, 24-hour and 2-hour reminders, important changes, and the published-recap invitation. The post-event content notification and text remain in scope. Future-event SMS consent is separately unchecked. Download is optional after RSVP and becomes required for the door QR; guest-list and RSVP management access in Clip/web do not require installation.

**Still unresolved.** Choose the later QR/download reminder's prominence and placement. Confirm the per-message push versus SMS behavior where not already specified, and the proposed late/elapsed reminder behavior, including after rescheduling. This is about communication behavior, not an opportunity to introduce an earlier hard download gate or silently omit an approved channel.

**Proposal on record.** Send the late confirmation, skip elapsed reminders, send each remaining reminder once, and let SMS opt-out stop texts without canceling the booking. Use the event as the truthful source even when delivery fails. Delivery-provider retry/backoff and delivery receipts are engineering details; they do not need a new product choice unless they change this behavior.

**Blocks / foundation.** Blocks final scheduling/channel fixtures and arrival-prompt design. Message intents, opt-in data, canonical links and delivery status handling can proceed. Sources: product lines 82–86, 145; September 14 review lines 23–25 and 51; engineering D13.

### OD05 — Preview payloads, private-venue presentation, and external sharing

**Approved invariant.** Nonattending Astir members can see an event preview; protected gallery/conversation remain attendee-and-completion gated. Personal posts default to Everyone in Astir under existing restrictions. Full guest lists require confirmed RSVP; the pre-RSVP face pile/count is a conversion feature. Homes require consent, approximate presentation, controlled reveal and expiry; exact access expires 24 hours after event end by default. Gallery-photo reuse inside public Astir event check-ins is approved without a reuse explanation.

**Still unresolved.** Specify anonymous-web recap/post-preview access separately from the already-required public event-detail entry; permitted preview media/posts and any teaser avatar; the actual approximate-home payload/presentation and consent-recording control; and the Instagram share destination/payload. These choices must not expose protected gallery content, comment identities or exact home details by implication. Approval for reuse within Astir is not blanket approval for off-platform media publishing.

**Proposal on record.** Use a stable neighborhood area, an “Approximate location” label, title/general area/approved imagery, and recorded operator consent before publication. Omit exact street/house/coordinates/navigation until entitled. Keep exact home addresses out of calendar exports. Preserve existing privacy restrictions and do not implement the deferred expanded privacy UI.

**Blocks / foundation.** Blocks final public/anonymous and private-location response projections, preview/share designs and their access tests. Canonical event/place linkage, entitlement evaluation and restricted attendee content can proceed with explicit separate projections. Sources: product lines 88–90, 108–114, 130, 143, 155; working record lines 142 and 146–150; ledger R075/R156.

### OD06 — Personal media, editing, and conversation controls

**Approved invariant.** An explicit check-in may have no note, photo or private feedback. Private optional stars/comment never become a venue rating. Shared recap photos **and videos**, comments, replies and likes remain in scope. Eligible uploads appear immediately. Source-photo removal propagates through references; deleting the personal post/visit retains historical completion while valid attendance persists. No reuse explanation or replacement approval is allowed.

**Still unresolved.** Decide whether the personal composer accepts the attendee's own videos, in addition to its approved own-photo path. Confirm public note/media editing versus private-feedback editing and the remaining comment/reply/like/report controls, using existing Astir conventions where applicable. These interactions must respect settled source-removal and completion behavior; their detailed design is not approval to cut shared-gallery video or social interactions.

**Proposal on record.** Edit public note/media and private feedback separately; permit own photo/video support; retain retryable drafts; display a neutral removed-photo state. Upload-size/encoding limits, storage deletion propagation and retry implementation are engineering constraints to validate, not new content-audience decisions.

**Blocks / foundation.** Blocks final composer capabilities and edit/moderation/conversation interaction contracts. Approved completion/history semantics and the protected media boundary can proceed. Sources: product lines 104–116, 142, 149; working record lines 138–143; ledger R128.

### OD07 — Map filters, overlapping events, and final pin treatment

**Approved invariant.** Permitted viewers can discover upcoming/recent event pins. Featured includes all permitted viewers; You reflects attendance; Friends reflects relevant friends' attendance. Tapping a pin opens a collapsed event card over the normal map, then the full event; the ordinary place profile retains inline event history. Console controls include on/off, start/end and style presets.

**Still unresolved.** Select second-degree Friends inclusion, final pin shape/motion/preset treatment, and default promotion/overlap rules. The alternatives shown in the visual review are not approved designs.

**Proposal on record.** Seven days before through seven days after, operator adjustable; prefer live, then next upcoming, then most recent ended event within its active window; break simultaneous live ties by earliest start then title, with a route to other venue events. Reduced-motion behavior remains required for any animated choice.

**Blocks / foundation.** Blocks final map query/filter expectations and visual acceptance. Place-event linkage, card-to-detail navigation and history can proceed. Sources: product lines 120–130; September 14 review lines 29–30 and 51; ledger R127/R156.

### OD08 — Account discovery and continuation after the ticket

**Approved invariant.** Reuse known identity and a valid session; recover the original account/booking without silent merging. Required name and username precede QR, with only missing values collected; photo is strongly prompted but optional. A phone string alone is not verification. The ticket must not be delayed by the general onboarding sequence.

**Still unresolved.** Confirm when and how deferred general onboarding resumes, the proposed discoverability of RSVP-only profiles before that onboarding, and the optional-photo layout. These choices must not reopen required identity, create a required photo, repeat completed steps or falsely mark general onboarding complete.

**Proposal on record.** Continue with existing profile/privacy discovery behavior for signed-in members, not anonymous web; defer location, contacts, friend discovery, notifications and the general walkthrough until relevant use. Exact sequencing/layout remains proposed. Whether session transfer/provider invocation actually works is a separate technical proof, not a product choice to waive identity.

**Blocks / foundation.** Blocks final post-ticket onboarding/profile-discovery acceptance. The approved original-account recovery and minimal identity-to-QR path can proceed. Sources: product lines 136 and 148; September 14 review lines 21–26 and 51; engineering D3, D16; ledger R051/R119.

### OD09 — Navigation, saving, and remaining action design

**Approved invariant.** Events is a new tab; confirmed events lead, with simple nearby/empty states. Guests can return through Events/place history according to eligibility. Calendar is available after confirmed RSVP; sharing and the recap's upper-right Share remain in the intended flow. The dedicated recommendations/Explore nearby branch was removed.

**Still unresolved.** Confirm whether a distinct Save event/bookmark action exists, exact tab placement and request/offer/past-event grouping, and remaining calendar/share action presentation. The recorded icon-color request has no identified target and cannot be represented as implemented. External-share access/payload is OD05, not a second independent permission decision.

**Proposal on record.** Map, Feed, Events, Lists, Profile; confirmed/current first, then requests/waitlists/offers, nearby events and a Past events entry. Omit a separate Save event action in the first release **only if that proposal is accepted**. Calendar failure preserves the reservation and offers a supported alternative; use current event time/link and an approximate home label. Calendar provider integration is a feasibility detail, not a reason to claim saved calendar copies automatically update.

**Blocks / foundation.** Blocks final navigation/action design and any bookmark persistence requirement. Existing approved entry, detail and return routes can proceed. Sources: product lines 120, 130, 152, 155; ledger R016/R123/R126/R155; engineering D13.

## Routine defaults that should travel with whole-draft review

These remain labeled proposals where the source labels them that way. They do not warrant fabricated independent decision rounds:

- **Verification recovery:** proposed 60-second resend countdown, editable/reverified phone, event context retained, distinct expired/incorrect-code errors. Provider limits may determine the final countdown; verification itself is approved.
- **Truthful recovery:** retain check-in drafts, distinguish loading/failure/no-match, retry the same committed operation, and explicitly retry or omit optional failed media. No duplicate completion, silent media loss or false publication success. Correctness follows approved identity/history invariants; incidental copy/layout is proposed.
- **Cancellation presentation:** one confirmation and a canceled result. Historical cancellation/code records are already required by engineering D11; preserving them is no longer a new product question. Independently held place rights survive.
- **Guest-list layout:** followed people first and permitted mutual counts are already requested. Proposed face selection, display-name/photo layout, omission of phone/internal information and a count differing from visible faces must respect established restrictions; they do not reopen confirmed-only access.
- **Console/publishing mechanics:** local event time zone, required field validation, preview, explicit publication, truthful success/failure and unavailable-link states are proposed routine controls. Validate against the final lifecycle policy; do not use a generic Publish control to imply unrestricted edits.
- **Derived post-event return states:** unpublished waiting state, existing completion recovery, missing-admission help, staff correction and invalid-admission access loss preserve selected gates. Invitation deduplication and temporary-unavailability recovery are routine contract details. An outage is not a new check-in requirement.
- **Tags and design details:** optional event tags and Astir configuration/generation are requested. Storage, generated-option limits, exact controls, long-name/accessibility layout and nonambiguous empty/loading/error treatment need implementation/design work, not an invented additional product capability.

The remaining proposals within mixed approved/proposed section-8 items must retain their labels until review. An artifact's existence or successful browser check cannot supply approval.

## Validation and engineering work, not human product decisions

These are prerequisite proofs or design tasks. A failed proof may produce a real tradeoff later; it does not justify inventing a choice now.

- Real App Clip target/build/dependency size; supported invocation and public/TestFlight distribution; Apple/Google provider behavior, verified phone, cancellation/return, installation/session handoff and original-account recovery on actual devices. Fixture authentication cannot prove these.
- Authenticated browser fallback and full-app routing across the nine surface/account states, session/account fences, no stale protected cache across account or entitlement changes, and truthful server error classification.
- Transactional booking, seat/code holds, completion/canonical visit identity, exactly-once retry handling, existing history/audience compatibility, migration/rollback and concrete repository/API contracts. Preserve the approved shared backend and focused native/shared boundaries.
- Browser-console offline durable storage, roster freshness/account ownership, persistence failure, restart, repeated sync, duplicate/conflict reconciliation and server-validated recap eligibility. A screen showing “awaiting sync” is not proof of durable storage.
- Media/video processing, source-removal propagation, protected payloads, transport limits, notification/SMS delivery/provider configuration, calendar integration and performance measurements. Benchmarks and physical-device/provider checks remain unexecuted unless separately evidenced.
- Deployment/domain ownership, operator membership setup, signing, secrets, service configuration and production release readiness. These are engineering/operations work under the established scope; this document does not authorize service changes.

## Consistency assessment and stale labels

**No directly contradictory approved constraints were found that force a product reversal before foundation work.** The material incomplete combination is OD01: promised issued-offer deadlines, registration closing/event end, and later schedule/configuration edits. D4/D13/D14 deliberately preserve existing promises but leave new-offer bounding and explicit edits unresolved. The implementation must select a coherent rule before claiming the complete offer lifecycle is specified; it must not silently truncate or extend a promise.

Do not mistake intentional differences for contradictions: registration can remain open until event **end** while self-cancellation stops at **start**; Clip/web management is available without installation while admission requires the full app; confirmed RSVP unlocks the full guest list while validated admission plus completion unlocks recap; deleting a post can retain completion while removing a source photo removes its references; Astir-wide visibility does not imply anonymous-web visibility.

Older “open” wording for invitation-code counting/cancellation/deactivation, prepared offline admission, Team admin permissions, original-account recovery, future-to-future rescheduling and registration cutoff is superseded by engineering D3–D14. In particular, September 14 review line 51's invitation-code-accounting label is stale; only the remaining rule edits in OD01 are open. Existing visual controls do not yet demonstrate every approved accounting/deactivation requirement.

Reconnection/missed connections and the unexplained solo/single/private idea remain deferred under product D7. Expanded privacy controls, paid tickets and outside-host publishing retain their deferred/excluded status. They are **not** newly created implementation TODOs or additional unresolved groups in this count.
