# Astir Events: working product record

Status: discovery and product decisions in progress. This is not an approved product spec, an engineering plan, or permission to implement.

### September 15 engineering review amendments

Engineering decision numbers restart at D1 and are separate from the historical product D1–D35 below. The working engineering plan records D1A (complete journey, staged delivery, two parallel lanes) and D2A (cohesive Events module in the existing backend).

**Engineering D3A approved:** Joe replied “thats good” to the concrete original-account recovery walkthrough. Reuse a valid session where possible; otherwise keep the event while the guest signs in with the account used to RSVP. After an actual no-match lookup, use “No RSVP found for this account. Already RSVPed?” and Find my RSVP / Get help; never infer another account's booking from a public event link. Original-account sign-in retrieves the existing reservation and proceeds through only required missing identity to the QR. Loading/failure and pending/waitlisted/offered states remain distinct. Account switching/support are included; silent merges, booking transfers, replacement RSVPs and a new self-service provider-linking flow are not. The App Clip/browser/full-app transfer mechanism remains to be validated. Product spec section 8 item 1 is now approved on that basis; its other operating proposals remain unapproved.

**Engineering D4A approved:** Joe selected “Reserve the spot until the deadline. Only send as many active offers as there are open spots; accepting in time confirms their place.” An issued offer holds one spot for that recipient and converts to confirmation on eligible timely acceptance. Decline/expiry releases the hold; D31 still protects released capacity for staff selection while a waitlist exists, without automatic promotion. All competing capacity operations must preserve available capacity, and the console must reject reductions below confirmed guests plus active holds. A late cleanup job cannot prolong a hold or permit expired acceptance; repeat acceptance resolves the existing/current booking. This settles the previously open per-offer hold in product D23. Pending approval/verification holds, registration cutoff, and changes to issued deadlines remain separate unresolved rules.

**Engineering D5A approved:** Joe answered “a” to whether applications awaiting manual approval should hold seats. They do not. Approval confirms an eligible applicant only with available unprotected capacity, preserving issued waitlist offers and D31's protected waitlist selections. If there is no eligible capacity, keep the application pending and tell the operator why approval failed; do not create confirmation or its benefits. Retries and simultaneous approvals must not duplicate allocations or messages. Moving an applicant to the waitlist remains a separate proposal. This settles pending manual-review holds, while unfinished verification holds remain unresolved.

**Engineering D6A approved:** Joe answered “a” to whether new RSVP attempts should hold seats during phone verification. They do not. Evaluate capacity and approval mode when the verified guest submits. If the last spot filled, preserve verification and event context, then offer the waitlist as a choice; do not automatically join it, repeat verification solely because of capacity, or claim confirmation. Existing confirmed bookings remain protected. Existing issued offers retain their original hold/deadline during verification retries without another hold or an extension. This resolves the verification-hold question left open under D4/D5; SMS resend timing remains separate.

**Engineering D7 approved by explicit clarification:** Joe wrote “A jsut one team admin role for now that has all accfess. anyone with console can do everything”. Record one **Team admin** role with every Events console permission. The written clarification supersedes the earlier A/B role descriptions; it does not select separate organizer/door-staff permissions. Everyone authorized for the console can manage events, scan/lookup/admit guests, approve RSVPs, manage offers, correct attendance, publish, send event messages, change venue settings, moderate content and access private event feedback. No per-event staff assignment in the first implementation. Individual authentication and backend authorization still distinguish team admins from guests; console access is not anonymous/public. Guest permission rules, capacity constraints and admission eligibility remain intact. No live account or permission changes were made.

**Engineering D8 — work allocation delegated:** Joe replied “lets do whatever makes the most sense to get it done, not sure if platform is the best way to do it”. He did not select the proposed platform ownership options or assign Joe/Ryan by specialty. Engineering judgment selects small parallel foundation packages (Events data/rules and entry/identity), an early real integration checkpoint, then two end-to-end packages: before-event/door and after-event/map. Either agent may work across app, web, console and backend within its package; shared integration files have one active owner per stage. Assign and rebalance concrete work at kickoff/checkpoints. Preserve the full scope and joined release checks; this is planning, with no production implementation begun.

**Engineering D9B approved:** Joe selected “Use a downloaded guest list offline. Record admissions for later reconciliation; the list may miss recent cancellations or changes. Recap access waits for server validation.” Team admins may prepare an event roster online and use it during an outage to admit matching guests after the existing installed-app/account checks. Offline records are pending reconciliation, not authoritative server admission. Display roster freshness and pending/synced/conflicted results; stable operation IDs prevent duplicate logical admissions. Reconcile current booking/event/admin eligibility and surface stale cancellations, changes and duplicates rather than silently restoring them. Protected recap still needs validated server admission plus historical check-in completion. No new role, device exception, anonymous walk-in or permanent offline recap access is approved.

Updated: September 15, 2026. Historical source-fidelity audit dated September 14: see audit/requirements.md; the later amendments above take precedence.

**Engineering D10A approved:** Joe answered “A”: capped invitation codes count confirmed guests. A use is consumed when an eligible booking becomes confirmed; pending applications and waitlist entries do not consume uses. All confirmation paths enforce code quota and event capacity together; failed attempts and retries cannot consume extra uses. To preserve D4's promised offer, hold its required code allowance when issuing it, settle that hold on acceptance and release it on decline/expiry. An invitation code remains separate from account identity and phone verification. D11 below subsequently settles cancellation/rebooking and D12 settles deactivation; other issued-code edits remain unresolved.

**Engineering D11A approved:** Joe answered “A” to “When a confirmed guest cancels, does their code use become available again?” Return the consumed use once on successful cancellation, together with the booking/seat change. A five-use code with five confirmations returns to four used after one cancellation. Failures and retries cannot create allowance. Rebooking must pass current code, capacity, approval and protected-waitlist rules without a reserved claim; old confirmation/offer retries cannot silently restore a canceled booking. This does not approve code-edit behavior or event-wide cancellation/rescheduling policy.

**Engineering D12A approved:** Joe answered “a” to “If you disable an invitation code, what happens to guests already pending or waitlisted?” Keep their submitted requests eligible and block new submissions using the disabled code. Retained code eligibility requires an actual account-bound verified submission, not a link open or unfinished attempt. Existing applicants still need approval and available code allowance/capacity; they gain no hold. Existing confirmations/valid offers are not canceled. A canceled guest's deliberate rebooking starts a new attempt under D11 and cannot use the disabled code. This selects individual-code deactivation, not all code edits or switching the event's entire code requirement off.

**Engineering D13A approved:** Joe answered “A” to “If Friday's event moves to Saturday”: keep RSVPs confirmed, notify guests and let them cancel. No reconfirmation gate. Preserve the canonical event, booking and seat/code allocation; reflect the new schedule in event/ticket information, future event-relative reminders and address windows. Guest cancellation still follows D11. A reschedule does not revive canceled bookings or silently reset issued-offer deadlines. Existing exported calendars and offline rosters may remain stale until updated; previously disclosed addresses cannot be recalled. This approval covers an upcoming event moved to a new future date, not event-wide cancellation, venue changes or edits to completed events.

**Engineering D14A approved:** Joe explicitly selected “Allow new RSVPs until the event ends by default (recommended)” for a 7:15 arrival at a 7–10 pm event. Astir can set an earlier closing time in the console. Late registrants complete the normal online account/phone verification, code, approval, capacity/waitlist and installed-app entry requirements. Beginning verification before closing is not a seat hold or permission to submit after closing. The earlier event-start registration-close proposal is superseded; the approved event-start self-cancellation cutoff remains. D14 adds no offline registration and does not silently cancel existing confirmations or issued offers.

**Engineering D15A approved:** Joe answered “A” at the architecture checkpoint to continue into code organization, tests, performance and rollout. Architecture direction is reviewed, with actual App Clip/account handoff, detailed contracts and distribution still requiring validation. This does not approve all remaining product/design proposals or authorize implementation/release.

**Engineering D16A approved:** Joe answered “a” to organizing Events as focused components with a small app/App Clip shared layer and narrow connections to existing systems. The engineering plan now specifies shared native contracts/presentation/transport, thin host composition and full-app-only canonical history/map adapters, using selected XcodeGen source membership initially. This preserves D2's shared backend and D8's two changing work packages; it is not an app-wide store/package rewrite or permission to implement. Existing error handling must preserve previously approved Events state/permission distinctions, and private feedback must remain separate from ordinary place ratings.

**Engineering D17A approved:** Joe answered “A” to continue into test coverage. The review will map the 121 named acceptance scenarios and technical failure branches to automated tests and actual-device/provider checks. None of those future Events tests is implemented or passed merely because the mapping exists.

**September 15 test-review result:** all 121 named scenarios and 24 additional technical risk groups now have planned files, assertions, layers and package ownership. [The test plan](engineering-test-plan.md), [full mapping](test-review/coverage-map.md) and [QA guide](events-qa-test-plan.md) preserve proposed clauses and distinguish simulated tests from real service/device proof. Mapping validation passed; no Events runtime tests were implemented or run. Engineering D18A approved continuing to performance. This is not product or implementation approval.

**Engineering D18A approved:** Joe answered “A” to continue to performance and then final two-person delivery/rollout planning. Test mapping is complete at the current spec level; production test execution remains future implementation work. D18 is no longer pending.

**September 15 performance-review result:** [source review](performance-review/README.md) covers entry/query growth, short capacity transactions, delivery backlog, media/map memory and complete offline roster/queue handling. The current architecture remains appropriate; no new product/architecture choice was identified. [Measurement fixtures and provisional budgets](performance-review/measurement-plan.md) are planning guidance, not product limits or measured results. Engineering D19A approved final synthesis; the [conditional handoff](engineering-handoff.md), [22 tasks](implementation-tasks.md), contracts and rollout are complete, with [nine remaining product/design groups](engineering-open-decisions.md). No app/backend change or benchmark ran.

**Engineering D19A approved:** Joe answered “A” to finalize the engineering handoff after the performance review. Compile contracts, task dependencies/ownership, estimates, rollout and remaining decisions. This authorizes finishing the plan, not starting production implementation or approving previously proposed product behavior.

September 15 local visual update: the complete flowchart now has 172 screens in 13 continuous sections. Offline-door screens 166–172 sit immediately after arrival; the original 165 screen IDs, numbering, ordering and routes remain intact. The latest pass corrects approval annotations on screens 94, 97, 123 and 133 for D4–D6/D13/D14; existing reschedule UI already preserves confirmation, and the start-time self-cancellation cutoff remains correct. Local HTML preview and branch checks passed with 26 native and 146 wireframe primary previews, no browser errors and no external requests. Current HTML SHA-256: `b8431da1c92cfac28a7b1ec5ac74c3cff5946f5654994cd6251c0efa905a3993`. This verifies the review artifact, not actual offline persistence or admission. Invitation-code accounting/deactivation controls remain to be detailed in the console mock. The planned acceptance document still contains 121 named, unexecuted scenarios, now including D10–D14 cases. These revisions await the next repo update; PR #641 contains the earlier 165-screen snapshot.

Planning record: [REC-467](https://linear.app/recme/issue/REC-467/define-place-centered-events-guest-rsvp-attendance-and-follow-up), observed as Done on September 15, assigned to Ryan. Existing [planning document](https://linear.app/recme/document/events-in-astir-product-backend-guest-journeys-and-build-plan-69fdbac8d668) is prior context. Its recommendations yield to the user's later recording and instructions in this task. No changes have been made to that document or issue.

## Source of authority

1. User's September 9 transcripts and direct additions in this task, followed by confirmation to begin the specification workflow. Later answers supersede earlier exploration where clear.
2. Original transcript: `/Users/joelipshutz/.codex/attachments/6ae904a6-a3b8-416d-b521-d116614a93cf/pasted-text.txt`. D1 answer transcript: `/Users/joelipshutz/.codex/attachments/089ef3f0-1347-4b1a-92ce-bac6e68c5104/pasted-text.txt`.
3. September roadmap: `/Users/joelipshutz/Documents/ChatGPT/New project/september-roadmap-deck/september-roadmap.html`.
4. Existing project decisions and planning records where they do not conflict with the latest user direction.
5. Verified code and platform documentation for current behavior and feasibility. Neither establishes new product intent.

App names Astir, rec.me, and Wander refer to the same project. Use Astir in current prose.

## Purpose and intended outcome

Events introduce people to Astir through a real experience. A guest first cares about the gathering. Astir progressively supports RSVP, preparation, entry, post-event content, and a place memory on the map. The guest need not understand the whole app at the start.

Actors: a new guest without the app, an existing app member, returning or interrupted guests, and Astir's internal event operators. Prior planning states Astir always hosts; no current instruction changes that boundary.

The September plan calls for an internally locked first event, a usable beta with 30 friends, and functioning brand/content/mailing-list work. Joe and Ryan provide the planned capacity. The event date can fall in October. The full product experience must be specified before release slices are agreed; no automatic scope reduction is authorized.

September 10 launch clarification: the user is launching Astir separately and instructs this spec to assume the app is available on the App Store before the Events experience goes live. Public availability is a prerequisite for the live journey, not a verified current release status. TestFlight remains a testing path. The version offering public App Clip entry must itself include the reviewed/released App Clip; a prior full-app release alone does not establish that feature's availability.

The specification is complete when the approved product behavior covers the full intended journey and relevant exceptional paths, the existing-product integration is explicit, and the engineering handoff contains testable acceptance criteria, dependencies, and verified constraints. No claim of a working implementation is made by a completed spec.

## Direction established by the user

### Event primitive and place relationship

- An event is a time-specific occurrence associated with exactly one place.
- A place may have zero, one, or many events.
- Event visibility and eligibility for map display require explicit rules.
- Private venues may need special properties. Do not assume that linking a canonical place makes its address or map pin publicly visible.
- D8 custom answer: people can discover information about an event through its associated location. A home is a special place type; its place view may remain accessible and show an "approximate location" or area/radius rather than the exact spot. The user did not choose the earlier proposal to hide the home's entire place profile. D13/D35 settle the default reveal and expiry window. The draft proposes public fields and a stable approximate area for review.
- The resident/owner or renter must provide the appropriate consent for a home venue. How that consent is captured and what location is disclosed remain unresolved.
- D13B with user amendment: a home venue's exact address becomes available to confirmed guests 24 hours before the event by default. A guest whose RSVP is confirmed after that threshold receives it immediately. Astir can change the reveal timing per event in the console. Nonattendee approximate-location access is separate from this guest address permission.
- D35A: exact-address access expires 24 hours after the event ends for all guests by default, returning the event and place to approximate location. Astir can adjust that cutoff per event in the console. Independent location rights remain separate; expiry cannot recall an address already seen.

### Entry and event detail

- Shared event links and in-app Events navigation lead to the equivalent event detail experience.
- Preferred no-install experience: App Clip. D14A approves an equivalent browser RSVP when the Clip cannot open. Preserve the event and the same RSVP identity across Clip, browser, and full-app entry; authentication/handoff feasibility still requires validation.
- D16 updated on September 10: the live flow assumes public App Store availability before launch. TestFlight must support beta testing of the product flows through Apple's testing entry points; it is not a substitute for the public App Clip invocation experience. Do not repeatedly reopen this settled launch assumption.
- Event detail: immersive imagery, overlaid text, a strong title, concise description, time/date, social proof, face pile, and guest-list view. D30B with amendment: before RSVP confirmation, show a face pile/count as a deliberate RSVP hook; the full guest list unlocks only after confirmation. Pending approval, waitlist membership, or an unaccepted offer does not unlock it. Keep the hook and RSVP action prominent without making the teaser equivalent to the full list.
- RSVP is a primary action. Share is prominent. Save remains a product decision.
- Keep Apple's system App Clip invocation card distinct from Astir's immersive event detail screen. The desired detail is content, not an extra blocking launch animation.

### RSVP

- Desired sign-up choices: Apple and Google.
- September 14 recheck: the user's explicit instruction was sign up with Apple/Google within the RSVP screen, then provide a phone number. Screens 3 and 4 stay within the no-install App Clip/browser RSVP. Dividing those tasks into two screens is a layout proposal; SMS verification is not a replacement for the selected provider sign-in.
- Capture a name and phone number, avoiding unnecessary repetition of information already available.
- D17A: verify the phone number by SMS code before confirming RSVP. Reuse an already verified matching number where applicable. A pending or failed verification is not a confirmed RSVP. Verification confirms control of the number; it does not replace Apple/Google sign-in or subscribe the person to future-event texts.
- D19A: clearly explain event-specific texts during RSVP, with a separate optional, unchecked opt-in for future-event texts. Leaving the future-events checkbox unchecked must not prevent RSVP or suppress agreed event-specific updates. This supersedes the original combined checkbox proposal, “get updates from astir about this event and others.” Exact copy, consent records, opt-out handling, and reminder triggers remain to be detailed.
- D18A: profile photo is optional, with a strong prompt during full-app setup. It is not required to complete RSVP, see the admission QR, or complete the post-event check-in. Reuse an existing profile photo where present; optional event-post photos remain a separate field.
- Support an access code when an event requires it.
- Show an RSVP confirmation and an event detail state reflecting the RSVP.
- Include calendar access in the desired experience; the App Clip implementation path requires platform validation.
- D20A: the first Events release supports free RSVP only. Paid checkout, payment collection, and refunds are outside this release's selected scope.
- D21C: when an event reaches capacity, offer an event-specific waitlist. Astir chooses who receives available/released spots; no automatic waitlist promotion has been selected. Waitlist membership is not a confirmed ticket.
- D22A with user amendment: automatically confirm eligible RSVPs when space is available by default. Astir must be able to enable manual RSVP approval on its side, exposed through the internal console. A pending approval is distinct from confirmed registration. D23 settles offer/acceptance mechanics and D31 settles released-space priority; capacity accounting and switching approval modes still need concrete rules.
- D23A: selecting a waitlisted guest sends them an offer they must accept. Default offer expiry is 24 hours, adjustable in the console. An offer is not a confirmed ticket until accepted. The draft must define capacity holds, identity-bound acceptance, expiry/decline, late-event cutoff, and recovery without silently auto-confirming waitlisted people.
- D24A: a confirmed guest can cancel their own RSVP anytime before the event starts, releasing their spot. Consequent ticket/address/message state changes must remain consistent. D31A: while a waitlist exists, hold released spaces for Astir's deliberate waitlist selections; new guests join the waitlist instead of taking those spaces through automatic confirmation.

### Before and at the event

- D29A: event texts include automatic confirmation, reminders 24 hours and 2 hours before the event, important event changes, and the published-recap invitation. Timing and templates are configurable in the console. Waitlist/status messages must also follow the approved registration flow. Eligible recipients, combined notices, stale/late reminder suppression, delivery failure, and opt-out handling need concrete rules in the draft; future-event marketing retains its separate optional opt-in.
- Full-app installation and the guest's event QR code are the intended hard admission gate.
- September 14 recheck: RSVP confirmation and event texts precede any required full-app download. A guest without the full app retains their reservation and can return through the App Clip/browser for permitted event details and guest-list access. They install later to retrieve the entry QR before admission. The previous wireframe's immediate Get Astir → installation sequence was a presentation error, not an approved download deadline. The exact scheduling of a download reminder remains a design proposal.
- D15A confirms that a guest must have a phone capable of running Astir, and that requirement must be clear before RSVP. Browser RSVP does not grant browser-only admission or an unsupported-device exception. A person browsing on a computer may still own a supported phone; do not equate the browsing device with their admission device.
- The QR is accessible inside the Events tab.
- A guest coming from RSVP should have a shortened, context-preserving onboarding route.
- Admission and the later product check-in are distinct actions. Define their user-facing names and stored meanings separately.
- D25A: if a guest has installed Astir but cannot load their QR, staff may verify them against the confirmed booking and manually record admission. This is a permitted QR-failure fallback, not an unsupported-device or no-app admission path. Staff scanner UI, duplicate use, offline operation, and the precise identity-verification procedure still need concrete rules. D5 staff correction of a missed scan remains separate from this door-time action.
- D5A: recorded admission establishes eligibility for the attendee recap. Staff can correct a missed scan. A confirmed RSVP or a guest's self-confirmation alone does not establish eligibility. The later explicit event check-in is still required for full recap access.

### Events tab

- Confirmed events appear at the top when present.
- Upcoming nearby events appear in a simple block/list treatment.
- With no upcoming events, keep the coming-soon experience simple. A waitlist was mentioned and then simplified; do not silently add a full waitlist product.
- Event detail retains the same applicable functionality across in-app and App Clip entry.

### After the event

- D26A: Astir publishes the recap as ready from the console, triggering the attendee invitation to check in and see the content. A content notification and text bring eligible guests back. Detailed waiting-state behavior before publication and delivery/retry handling belong in the draft.
- A required post-event check-in is part of the intended content-unlock progression.
- D1 resolved in the latest answer: an event-specific check-in, analogous to the place check-in, creates the attendee's personal event post. This is distinct from door admission and from a comment on the shared event recap.
- The personal post supports a note and photos, with no public rating. D2A settles that note, photos, and private feedback are all optional; an explicit Check in submission is still required to complete the step and unlock content for an eligible attendee. A submission with none of those fields filled is valid. Personal-post video support remains unresolved. Repeated references to note/photos establish the direction; the isolated transcribed phrase "no photos" is not treated as a clear reversal.
- D34A: private feedback offers optional 1–5 stars and an optional comment, visible only to Astir. Both fields remain optional under D2A. Never use this feedback as a public venue rating.
- After check-in, land on the attendee-specific event recap view. The map remains part of the progression, but is not the immediate post-submit destination.
- The recap experience contains an event recap, Astir-provided photos/videos, attendee-provided photos/videos, comments/social activity, and personal event check-ins. Comments should be prominent near the top. D27A: an eligible attendee's shared-gallery upload becomes visible immediately to eligible gallery viewers; uploaders can remove their content and Astir can moderate it. Layout and interaction details remain proposed; source-photo and post-deletion effects are settled by D32A/D33A.
- D6A: before completing check-in, attendees may add their own photos. After unlocking, they may add event-gallery photos to their personal event check-in. The initial composer does not expose the protected gallery. D28A permits shared-gallery photos in public Astir event check-ins. The user's amendment explicitly removes the proposed reuse explanation: no reuse explainer, disclosure prompt, tooltip, or additional approval step in that product flow. Keep the already-requested small eye audience indicator. This does not introduce external social-network publishing or blanket off-platform reuse.
- D32A: when the uploader or Astir removes a source gallery photo, remove that photo from all check-ins referencing it and preserve the rest of each check-in. D33A: deleting a personal event check-in removes its post/visit, but keeps the historical completion needed for recap access while attendance eligibility remains valid. Independent visits, ratings, and recorded admission remain separate.
- The associated place profile must expose a route to its events and allow attendees to return to an old event recap. Event history persists after any temporary map treatment ends.
- D10A: the special map treatment means the venue has an upcoming/recent event. Everyone allowed to discover that event can see the treatment, subject to the venue's location rules; it is not limited to a person's completed event memory. When the treatment ends, ordinary place access still exposes event history. D11A settles console controls for on/off, display start/end, style presets, and preview. D12A settles that tapping the special pin opens the event view, which links to the place profile. Overlapping-event precedence and initial/default schedule values remain to be defined.
- D3A settles that nonattendees across Astir can see an event preview. Discovery is not limited to friends or second-degree connections. The full gallery and conversation remain for attendees who complete the event check-in. Public-web access, which media/posts appear in the preview, and event/private-venue exceptions remain to be defined.
- The nonattendee preview shows the presence of the comments section with a gray/blurred locked treatment and unreadable comment text. User-proposed copy: "Attendees can see comments. Join the next one to unlock." A visible profile photo was suggested tentatively; identity visibility is not settled. For design review, the wording must not imply attending a future event unlocks past events the person did not attend.
- Derived access requirement: the blurred treatment must use a locked representation, not disclose protected comment text and depend on visual blur to conceal it. Accessible labels must communicate the locked state without reading protected comments. Any profile photo used must be allowed for that viewer; this rule does not itself approve displaying photos.
- D9C: personal event check-ins default to everyone in Astir, including the posted identity, note, and selected photos. Show a small eye icon indicating the audience. Event check-ins follow the shared check-in privacy model. This does not open the full event gallery or comments, expose private feedback, establish anonymous public-web access, or override private-venue location protections. Public visibility of a submitted check-in does not decide visibility of every guest-list entry or every comment author's avatar.
- The user explicitly wants expanded profile-level and individual-check-in privacy later, including a followers-only audience, applying consistently to both ordinary place and event check-ins. Preserve that future requirement and the desired everyone default; do not silently build the entire future privacy UI in this Events pass. The eye icon is requested now; whether it is interactive requires design definition. Existing restricted records, blocks, and established profile restrictions must retain their protections; no instruction retroactively broadens historical place data.
- D4A settles that completing the event check-in marks the venue Been and creates an event-labeled place visit without a public venue rating. The earlier recommendation accompanying A also preserves the audiences of prior visits; the user has not authorized broadening them. The event experience needs a save path that respects these semantics; choosing this behavior does not determine the storage design.
- D4 clarification from the user: this is a special event check-in whose visible identity is the event, for example, "Rachel checked into Vinyl Sound Bath on [date]." It remains connected to the canonical place and counts as checking into that place. Event title/date lead the presentation; the venue remains the place association. This is one logical check-in represented appropriately in event activity and place history, not two separate submissions or duplicated visits. The exact schema remains an engineering decision.
- D18A resolves the earlier conflicting profile-photo preferences: strongly prompt during app setup, but keep the photo optional. Profile photo absence cannot block the event progression.
- D7: the user explicitly deferred the reconnection discussion until they are together again. Preserve missed connections, people met, and the unexplained "solo, single, or private" wording for that discussion. Do not specify behavior, assume these are included in the first release, or reopen the topic in the current question rounds. This is a deferred decision, not a permanent rejection of the ideas.

### Internal event operations

- Astir's internal team operates the events; no customer-facing host marketplace is requested.
- D10/D11A: provide an internal console with event-pin on/off, display start/end, style presets, and preview. Custom icon/color/animation editing is not part of the selected control set.
- D13B amendment: include a per-event home-address reveal-time override, defaulting to 24 hours before event start. The console can change this timing without changing RSVP identity or attendee-recap eligibility.
- D21C/D22 amendment: include internal waitlist selection and the ability to enable manual RSVP approval; default approval is automatic. These controls operate within the event's capacity and eligibility rules. Exact staff selection/approval actions and their guest-facing results remain to be detailed.
- D23A/D25A: the console must support configurable offer expiry and authorized staff recording of verified manual admission. Keep staff actions attached to the event and guest so repeated actions do not duplicate registration or attendance.
- D26A/D27A: Astir can publish the recap as ready and moderate shared-gallery content. Recap publication is the trigger for the post-event invitation; publishing/notification retries must not repeatedly message the same guest unintentionally.
- D29A/D31A: configure event-message timing/templates and allocate released spaces to the staff-managed waitlist while one exists. New automatic RSVPs must not consume the released spaces awaiting those selections.
- Event visualization controls must use the same event/place association and visibility rules as the guest experience. Choosing a style or activating a map treatment cannot itself publish a private exact location or grant recap access.
- Existing-repo audit found no reusable shared event/admin console in the inspected checkout. A console is new scoped work; its native/web delivery surface, operator access, save/publish behavior, and when clients receive changes remain to be defined.

## Earlier proposals changed by this session

| Prior record | Earlier direction | Latest direction to carry into this spec |
| --- | --- | --- |
| Competitor deck | External registration provider recommended | Astir RSVP with App Clip as preferred no-install entry |
| REC-408 | On-site App Clip attendance without full installation | App Clip RSVP first; full app and event QR required for admission |
| REC-467 document | Place memory optional and web recap available without install | Required post-event check-in/content gate and full app admission |
| REC-467 document | Reconnection and assisted introductions in the first complete release | D7 explicitly parks the discussion until the next time the founders are together; behavior and release scope remain unresolved |
| REC-467 document | Public venues first | Private venue properties explicitly need a contract; release inclusion unresolved |
| REC-467 document | Production App Clip deferred to a later phase | App Clip is the preferred public RSVP journey, with browser fallback; user says App Store release will precede live Events |

The related issues remain unchanged while decisions are in progress. Preserve REC-408's unrelated shared-place recommendation work.

## Historical source audit of existing behavior

The code findings below were recorded during the September 9–10 inspection. The September 14 fidelity audit checks product intent and artifacts; it does not reverify current app/release behavior.

Audit checkout: `wander` at `dd4ade8984feb7524c23ad6c2af95432d7333886`. Refreshed `origin/main`: `f74ae736a0186ef61235f434da4a05c85b88a889`. The relevant `WanderLocalStore` drift only changes list ordering, so the findings below remain applicable. Paths below are relative to `/Users/joelipshutz/Documents/ChatGPT/New project/wander`.

| Evidence | Existing behavior | Event integration consequence |
| --- | --- | --- |
| `Wander/Models/LocalModels.swift:162` | Canonical place has exact coordinates and provider identity | Venue confidentiality is a new contract |
| `Wander/Models/LocalModels.swift:247` | User/place relationship owns Been/Wanna status and visibility | Repeated visits at one venue share parent visibility |
| `Wander/Models/LocalModels.swift:387` | Repeatable place visit holds date, note, rating, answers, and tags | A place visit is not an RSVP or admission record |
| `Wander/Services/WanderLocalStore.swift:5282` | Check-in changes the user/place relationship to Been and updates summaries | Automatic attendance-to-check-in conversion would change existing map/history behavior |
| `Wander/Services/VisibilityPolicy.swift:3` | Save visibility and blocks govern personal place access | Hiding identities alone does not hide a private venue |
| `supabase/migrations/20260824080308_private_taxonomy_projections.sql:436` | Featured can include anonymous canonical-place aggregates | Private venue protection must also cover aggregation and previews |
| `Wander/App/WanderRootView.swift:3336` | Current tabs: Map, Feed, Lists, Profile | Events requires an explicit navigation placement |
| `Wander/Services/RepositoryProtocols.swift:897` | Check-in draft and atomic persistence boundary already exist | Preserve retry identity and existing visit semantics |
| `Wander/Services/Auth/ClerkAuthService.swift:278` | Existing Apple/Google authentication through Clerk | Reuse identity foundation, but Clip compatibility is unproven |
| `Wander/Resources/Wander.entitlements:7` | Existing `getrec.me` associated domains and app group | New event/Clip routes need domain configuration |
| `Wander.xcodeproj/project.pbxproj:1226` | No App Clip target in inspected project | Do not describe the Clip as an existing capability |

Targeted model/navigation/migration searches found no Events or RSVP domain implementation. Calendar reservations and Shared Visits are adjacent features with different meanings.

### Internal console inventory

Targeted read-only searches of the inspected repository covered internal/admin/console/dashboard names, app Settings, scripts, documentation, web routes/frameworks, and package manifests. No shared event-operations console was found; this does not establish absence in other repositories.

- `Wander/Features/Settings/ProfileSettingsViews.swift:123` and `:355`, with `docs/feature-flags.md:16`: an account-entitled native tester panel supports Boolean/integer feature overrides and reset. Changes apply locally to the device/account and require restart; it is not an event-publishing console.
- `supabase/migrations/20260815023000_feature_flags.sql:20`: global/account feature settings exist, but authenticated app users have read-only access. Tester entitlement does not establish permission to write shared event configuration.
- `docs/analytics.md:7` and `docs/backend/community-moderation-runbook.md:49`: analytics dashboards and SQL/operator moderation procedures are adjacent operations surfaces, not a content-management interface.
- Derived requirement: the event console writes shared per-event configuration through explicit internal-operator authorization; keep it distinct from local tester overrides and specify publication/refresh behavior during engineering review.

### RSVP identity and onboarding audit

Read-only source findings from the same inspected checkout; these do not verify current hosted authentication-provider settings or select new product behavior.

- `Wander/Services/Auth/ClerkAuthService.swift:277`: Apple and Google sign-in exist. An incomplete provider signup can return `requiresAdditionalVerification`; the inspected flow has no event-specific recovery for that result. Event context must survive it.
- `Wander/Services/Auth/AuthSessionProviding.swift:48` and `Wander/Services/Auth/ClerkAuthService.swift:807`: the session carries an optional phone string but no verification status. Targeted native auth/onboarding searches found no SMS verification implementation. Do not treat the presence of a number as proof of D17 verification.
- `Wander/Features/Onboarding/OnboardingFlowView.swift:188`, `:243`, and `:370`: identity validates name/handle and availability; photo is optional, and selected avatar upload failure currently does not block continuation. The event flow must preserve the user's D18 optional-photo rule.
- `Wander/Features/Onboarding/OnboardingState.swift:3`, `:247`, and `:368`: identity, location, contacts, friends, and notifications precede general app entry; completion also enrolls the first-visit walkthrough. The proposed shortened return-to-event path needs explicit deferred-step and walkthrough behavior, rather than merely deep-linking behind this existing gate.
- `supabase/migrations/20260714033000_profile_identity_updates.sql:139`, `20260714013000_shared_visits.sql:3`, and `20260717180000_discover_profile_recommendations.sql:20`: profile mirroring can create identity before onboarding, defaults are non-private, and profile discovery does not check onboarding completion. RSVP-only account discoverability must be stated in the product draft, not accidentally inferred from completion of full-app setup. This finding concerns discovery by signed-in Astir users, not anonymous web exposure.

### D4 integration follow-up: verified code implications

Read-only follow-up to D2A/D3A/D4A; no runtime tests or implementation changes performed. Same inspected checkout as above.

- `Wander/Models/PlaceRating.swift:23` and `Wander/Services/WanderLocalStore.swift:5310`: the ordinary Been save path substitutes 3.0/5 when no rating is supplied. An event check-in must preserve an absent venue rating throughout the UI, local save, sync, and backend; hiding the rating input is insufficient.
- `Wander/Services/WanderLocalStore.swift:9416`, `supabase/migrations/20260824080307_private_place_taxonomy.sql:834`, and `supabase/migrations/20260725214500_check_in_ticketing.sql:420`: local aggregates ignore absent ratings, but server parent writes and the delete trigger can replace parent ratings. Adding, editing, retrying, or deleting an unrated event visit must not invent a venue rating or erase independent rated visits. Deleting a rated visit must recompute from surviving rated visits. Include an existing 5-star venue visit plus an unrated event visit in regression coverage.
- `Wander/Models/LocalModels.swift:247`, `:387`, and `Wander/Services/WanderLocalStore.swift:5326`: existing visibility is on the user/place parent, and ordinary visit creation can update that parent. Event audience rules need an explicit design that preserves earlier visit audiences.
- Derived engineering requirement: one durable event/user completion association and retry-safe visit identity tie explicit submission to its event-labeled place visit and content access. Door admission remains a separate fact. This states required behavior, not a final table design.
- Derived engineering requirement: preview data and protected full gallery/comments must have enforced access rules, including direct media URLs, cached content, and account switching. A blurred teaser cannot carry protected comment text to an unauthorized client.
- `supabase/migrations/20260824080308_private_taxonomy_projections.sql:436`: ordinary check-ins can contribute exact-coordinate place aggregates. Astir-wide event preview access must not automatically grant private-venue location access in map, Featured, search, profiles, lists, or media projections.

## Platform findings that constrain the flow

- App Clip launch includes system-controlled invocation/card behavior. Safari, Messages, a social-app browser, dismissed cards, and unavailable downloads need separate handling. [Apple invocation guidance](https://developer.apple.com/documentation/appclip/supporting-invocations-from-your-website-and-the-messages-app).
- The installed full app takes over subsequent invocations and must support equivalent functionality. [Apple launch configuration](https://developer.apple.com/documentation/appclip/configuring-the-launch-experience-of-your-app-clip).
- Public App Clip links and TestFlight experiences have different distribution requirements. Passing the controlled beta flow does not demonstrate a cold public invitation. [App Clip launch configuration](https://developer.apple.com/documentation/appclip/configuring-the-launch-experience-of-your-app-clip), [TestFlight App Clip testing](https://developer.apple.com/help/app-store-connect/test-a-beta-version/test-an-app-clip-experience).
- Apple supports Sign in with Apple and federated auth via `ASWebAuthenticationSession`. Google is not categorically excluded, but Clerk's exact Clip flow and callback compatibility require verification. [Streamline your App Clip](https://developer.apple.com/videos/play/wwdc2020/10120/).
- Apple identity scopes provide name/email, not phone collection. [Authorization scopes](https://developer.apple.com/documentation/AuthenticationServices/ASAuthorization/Scope).
- Clip data can be removed when unused. Shared storage/keychain features do not prove reservation or SDK session continuity. [Data handoff](https://developer.apple.com/documentation/appclip/sharing-data-between-your-app-clip-and-your-full-app).
- Ephemeral Clip notification authorization lasts up to eight hours after launch. It does not substitute for the planned SMS journey. [Clip notifications](https://developer.apple.com/documentation/AppClip/enabling-notifications-in-app-clips).
- Unsupported devices and restricted installations need an explicit policy for both RSVP and eventual admission. App Clip access to Calendar, Contacts, Photos, and Messages data is restricted. [Functionality constraints](https://developer.apple.com/documentation/appclip/choosing-the-right-functionality-for-your-app-clip).

## Decision queue

### D1: Meaning of the required post-event check-in

Status: answered by the second transcript. D2–D4 subsequently resolve optional fields, nonattendee preview direction, and Been/place-visit integration. Remaining details are tracked separately.

Decision: an event-specific, personal check-in post analogous to a place check-in, supporting note/photos and separate private feedback, without a public rating. Submit opens the attendee recap. It is not a bare attendance acknowledgment, a door scan, or only a comment on a shared event post.

The original recommendation to reuse place check-in must yield where its public rating, question set, visibility, and Been/visit side effects differ from this new experience. No engineering choice between reusing a visit model and adding a separate entity has been made.

### D2–D4: Approved decisions

Status: answered in chat with "2A 3A" and "4A", plus additional locked-comments direction. User prefers questions directly in chat with A/B/C/D options.

- D2A: All fields optional. The explicit Check in submission remains the completion requirement. Neither a public contribution nor private feedback is mandatory.
- D3A: Preview across Astir. The full gallery and conversation require attendee check-in. Show the comments section as a gray/blurred locked teaser; user-proposed copy and tentative avatar idea are captured above. This decision does not settle anonymous public-web access, every public media/post item, or private-venue exceptions.
- D4A: Yes, an event-labeled Been/place visit without a venue rating. Earlier visit audiences must remain intact. Existing venue ratings must not be silently replaced by an event rating or a synthetic default.
- D4 follow-up clarification: lead with the event identity in the check-in presentation, e.g. "Rachel checked into Vinyl Sound Bath on [date]." The same logical check-in counts as a visit to the linked place. Preserve the connection through event activity, place history, and map behavior without creating a second duplicate visit.

### Post-event flow: current agreement and open boundaries

| State or transition | Behavior | Decision status |
| --- | --- | --- |
| Nonattending Astir member opens past event | Event preview plus locked comments teaser; no readable comments or full gallery | D3A approved; preview items and avatar visibility open |
| Person with recorded admission follows post-event prompt | Arrives at event check-in with optional note/personal photos/private feedback | D1/D2A/D5A approved; staff correction workflow still needs detail |
| Confirmed RSVP without recorded admission opens event | Does not gain the full attendee recap merely through RSVP; missed scan can be corrected by staff | D5A approved; assistance presentation open |
| Attendee submits with every optional field empty | Submission is valid and creates their event-labeled visit | D2A/D4A approved |
| Check-in completes | Venue becomes Been; no public venue rating is created; open attendee recap | D1/D4A approved |
| Attendee reads recap | Full event gallery and conversation available | D3A/D26A approved; publish when ready, then invite |
| Checked-in attendee selects event-gallery photos | Can add them to the personal event check-in after unlock | D6A/D28A/D32A approved; detailed editing layout proposed |
| User later opens venue | Can navigate to the venue's event history and applicable event view | D1 answer approved; place-profile layout open |
| Event's special pin treatment ends | Ordinary place access still provides event history | Direction approved; start/end window and overlapping events open |
| Any Astir member sees a submitted event check-in | Event identity/date, author, note and selected photos follow the everyone default; small eye audience icon shown | D9C approved; existing restrictions and private-venue rules still apply |
| Viewer taps an active special event pin | Opens the event view with a route to its place profile | D12A approved; multiple-event precedence open |
| Confirmed guest opens a home event before address reveal | Exact address remains unavailable; permitted approximate-location presentation applies | D13 approved; radius/details still open |
| Address reveal time arrives for a confirmed guest | Exact address becomes available; default threshold is event start minus 24 hours, configurable per event | D13B plus console override approved |
| RSVP is confirmed after the effective reveal time | Exact address is available immediately | D13B approved |

### D5–D7: Answered and deferred decisions

Status: user answered "5A 6A" and explicitly said D7 will be discussed and added later when they are together again.

- D5A approved: eligibility requires admission recorded at the door, with staff able to correct a missed scan. Confirmed RSVP/no-show and self-confirmation are not substitute eligibility paths. Full recap access additionally requires completing the event check-in. Staff correction does not itself create the attendee's personal check-in or place visit.
- D6A approved: own photos before check-in; event-gallery photos can be added after unlock. Preserve the earlier check-in/visit identity when adding media. Gallery reuse is settled by D28A and source-photo removal by D32A; the exact edit interaction remains proposed.
- D7 deferred by user: retain reconnection and the "solo, single, or private" idea for their next joint discussion. No behavior or first-release commitment is settled. Do not repeatedly ask this question during the current pass, or silently include the old planning document's networking scope.

### D8–D10: Answered decisions and remaining details

Status: user answered D8 with a custom rule, D9C with shared-privacy direction, and D10A with an internal-console requirement.

- D8D custom: the event stays discoverable through its location association. Home venues are a special place type; a place view/map may show an approximate area/radius rather than the exact spot. Do not apply the earlier "hide the whole home place profile" proposal. Exact approximation and cross-surface location rules remain open; D13 settles guest reveal timing.
- D9C approved: everyone in Astir is the default audience for personal event check-ins; show a small eye icon. Later privacy controls at both profile and check-in level must work across places and events. Broader privacy UI is deferred, not a current blocker; preserve existing restrictions and historical audiences while defining the new default. The full shared gallery/comments keep their distinct attendee-completion gate.
- D10A approved: a discoverable upcoming/recent event gives the place special map treatment for eligible viewers. Add an internal console to control visualization. D11/D12 subsequently settle the control set and tap behavior.

### D11–D13: Approved decisions

Status: user answered "11 A 12A 13B but changeable via console".

- D11A: on/off, display start/end, style presets, and preview in the internal console. Exact presets, initial schedule values, and operator publishing behavior remain to be designed within this control set.
- D12A: special event pin opens the event view, with a clear route to the place profile. Multiple events at one place and approximate private-location areas require consistent extensions after this primary behavior.
- D13B plus amendment: default reveal is 24 hours before event start for confirmed guests; confirmation after the threshold grants immediate address access within the active window. Astir can change the reveal timing per event in the console. This does not grant unconfirmed viewers the address or alter recap eligibility. D35A subsequently settles after-event expiry; event rescheduling, already-revealed information, and canceled/revoked RSVPs have proposed defaults in the draft.

### D14–D16: Approved decisions and launch clarification

Status: user answered "14A 15A 16C. should work on tf or public", then paused to clarify App Clip distribution. After the Apple documentation explanation, the September 10 instruction was: "we'll launch the app before this is live. assume app store will be launched. We're doing that now. so continue".

- D14A: equivalent browser RSVP if the App Clip cannot open. The full app remains required before admission.
- D15A: retain the supported-phone/full-app requirement and disclose it before RSVP. No unsupported-device admission exception or browser-only full event journey has been selected.
- D16 updated: specify the full public journey and support TestFlight testing; assume public app release precedes live Events. No exact release date was selected. The public App Clip must be reviewed and available with the relevant full-app version before enabling public Clip entry. Do not claim a release or App Clip build already exists.
- Distribution finding, reverified from Apple on September 9: TestFlight testers launch configured Clip experiences through TestFlight; that route does not show the normal App Clip card. Ordinary public default/demo links require the app and Clip to have passed review and be available on the App Store. A browser-RSVP/TestFlight-app pilot is a possible testing arrangement, not the selected live release plan. [Apple testing guide](https://developer.apple.com/documentation/AppClip/testing-the-launch-experience-of-your-app-clip), [App Clip experience configuration](https://developer.apple.com/documentation/appclip/configuring-the-launch-experience-of-your-app-clip).

### D17–D19: Approved decisions

Status: user replied "A A A" to the immediately preceding D17, D18, D19 round. Map the three answers in that order.

- D17A: SMS verification before RSVP confirmation. An already verified matching number may be reused; number verification and Apple/Google authentication remain distinct. Pending, failed, or expired verification must have explicit recovery states and cannot silently create a confirmed spot.
- D18A: strongly prompt for a profile photo during app setup but keep it optional. No profile-photo admission or content gate is selected.
- D19A: explain event-specific texts during RSVP and provide a separate optional, unchecked future-event opt-in. This explicitly replaces the original combined checkbox structure. Do not interpret a phone number, successful verification, RSVP, or an unchecked future-events box as future-event marketing opt-in. Consent persistence, opt-out behavior, exact disclosures, and provider configuration remain engineering/product details to specify.

### D20–D22: Approved decisions

Status: user answered "A C 22 A for now with option to do B on our end". A maps to D20; C maps to D21; D22 is automatic by default with an internal manual-approval option.

- D20A: free RSVP only for the first release; omit paid ticketing/checkout.
- D21C: support a waitlist for full events and let Astir choose who receives available spots. This is separate from the earlier simplified city/coming-soon empty state. D23 subsequently settles that a selected guest receives an offer requiring acceptance.
- D22A plus amendment: default automatic confirmation when the guest meets requirements and capacity is available; Astir can enable manual approval from its internal controls. The staff-managed waitlist stays distinct from approval mode. A waitlisted or pending guest does not receive the confirmed-state benefits merely from submitting the request.
- Derived consistency requirement: confirmed registration, pending approval, and waitlist membership must have distinct guest-facing states. Capacity accounting must be atomic and prevent oversubscription. D31A subsequently approves protecting released spaces for staff waitlist selection rather than allowing new automatic RSVPs to take them.

### D23–D25: Approved decisions

Status: user replied "A A A" to the immediately preceding D23–D25 round.

- D23A: send the selected waitlisted guest an offer that requires their acceptance; 24-hour expiry by default, adjustable in the console. Expiry/registration cutoffs and capacity holds must be specified so an offer cannot produce an unusable ticket or oversubscribe the event.
- D24A: allow guest self-cancellation until event start and release the spot. No paid refund flow applies. The later draft must spell out consequences for QR, address, reminders, and staff-managed waitlist allocation.
- D25A: staff verify an installed-app guest against a confirmed booking and manually record admission when the QR will not load. This does not waive the full-app/supported-device requirement. Staff verification and offline procedures must be concrete in the draft.

### D26–D28: Approved decisions

Status: user replied "A A A but dont explain reuse pls" to D26–D28. Apply the explicit amendment to D28; do not retain the original recommended explanatory copy.

- D26A: Astir publishes the recap as ready from the console, then invites attendees to check in. Do not assume an automatic invitation at a fixed time regardless of content readiness.
- D27A: eligible attendee shared-gallery uploads are immediately visible to eligible gallery viewers. The uploader can remove their own content and Astir can moderate it. Initial Astir preapproval of every upload was not selected.
- D28A with amendment: shared-gallery photos may be included in attendees' public Astir event check-ins. Omit the reuse explanation entirely from this UI. Do not add a substitute approval prompt or silently bring back the proposed upload disclosure. Existing public/private field distinction and the eye audience icon remain; this amendment applies specifically to explaining gallery reuse.
- D32A subsequently resolves source-photo removal: remove the photo everywhere it is referenced, preserving the rest of each check-in. Reuse permission and omission of an explainer remain unchanged.

### D29–D31: Approved decisions

Status: user answered "A B and it should be a hook and A". Map to D29A, D30B plus an explicit conversion-hook instruction, and D31A.

- D29A: automatic confirmation, 24-hour and 2-hour reminders, important changes, and invitation after recap publication; timing/templates editable in the console. State-change messages such as waitlist offers still follow their approved flow, with recipient/opt-out/error handling to be specified.
- D30B with amendment: face pile/count before confirmation, deliberately presented as a hook to encourage RSVP; full guest list only after confirmed RSVP. Use truthful social proof and a clear RSVP action. The exact copy/design remains to be reviewed. Do not expose the full list through the teaser, qualify pending/waitlisted guests as confirmed, or make an RSVP unlock the protected recap.
- D31A: protect canceled/released spaces for Astir's waitlist selections while a waitlist exists; new guests enter that waitlist. Outstanding offers and remaining space must stay consistent with event capacity. Rules for increasing total capacity, exhausting the waitlist, and expired offers should follow concrete draft defaults for review.

### D32–D34: Approved decisions

Status: user answered "32 A 33 A 34 A" after opening the linked questions document.

- D32A: if the uploader or Astir removes a source gallery photo, remove that photo from the gallery and every personal event check-in referencing it. Preserve each remaining check-in, its other media, and its place visit. This does not reopen permission to feature gallery photos or add a reuse explanation.
- D33A: deleting a personal event check-in removes its post/visit but preserves historical completion for recap access while recorded attendance remains valid. Do not relock the recap solely because the post was deleted. Do not erase independent visits, independent venue ratings, or staff-recorded admission. Recompute place state from the remaining valid history and preserve any independent place-save intent.
- D34A: offer optional 1–5 stars and an optional private comment to Astir. Both are optional independently, and an entirely empty check-in remains valid. These values never appear in the public post or become a venue rating.

### D35: Home address after the event — approved

Status: user answered "A" to the sole pending D35 question.

- D35A: exact-address access expires 24 hours after the event ends for all guests; the event and place return to approximate location. Astir can adjust that cutoff per event in the console. Before-event reveal remains governed by D13B.
- This controls future display/access, including event-provided exact navigation; it cannot recall an address a guest already saw. Canceled/revoked registration and existing independent location rights remain separate. Expiry does not delete event history, personal check-ins, or otherwise-valid recap access.

### Other details for whole-draft review

The list below is the discovery checklist, not a new question queue. The consolidated draft now supplies 20 labeled proposed defaults, a post-event return-state table, and 13 acceptance scenarios. These proposals cover event navigation, access-code recovery, capacity/approval conflicts, publication, calendar/share/save behavior, onboarding, and operational recovery. Review them as a complete product candidate; detailed design and engineering validation follow confirmation.

1. Follow through on D5 attendance eligibility, including staff correction, a missed admission scan, and mistaken/revoked attendance.
2. D6/D28 settle gallery photo access and public Astir check-in reuse after unlock, with no reuse explainer. Define editing/removal consequences without reopening those choices or exposing the full gallery before the gate.
3. Follow through on D10–D12 visualization controls, time window, tap behavior, and multiple events at one place. The pin's discovery meaning is settled.
4. D30 settles the guest-list hook and confirmation gate. Define exact preview/avatar fields and private-home approximate presentation while respecting the distinct guest-list, post, location, and recap audiences.
5. D7 is parked for the user's next joint discussion. Only return to reconnection scope and the meaning of "solo, single, or private" when the user reopens it.
6. D15 settles unsupported-device policy. Specify the supported-device disclosure and interrupted install/recovery behavior without silently introducing admission exceptions.
7. D16 settles public-release availability before live Events; retain separate TestFlight validation. Sequence the remaining engineering dependencies against Astir 001 without reopening the public-release assumption.
8. D17–D19 settle phone verification before RSVP, optional profile photo, and separate future-event opt-in. Remaining setup details include username, notifications, exact consent copy and opt-out operation. Broader profile/per-check-in privacy controls are explicitly future work under D9; do not reopen their release scope during this pass.
9. D20–D25 settle free RSVP, staff-managed waitlist/offer acceptance, default automatic approval with manual mode available, self-cancellation, and verified manual admission for installed-app QR failure. Remaining operational details include access codes, capacity priority/holds, transferability/plus-ones, walk-ins, duplicate/expired QR, offline admission, and exact staff actions. Draft clear proposed defaults for review rather than silently treating them as approved.
10. D29 settles message cadence and console control. Draft precise event change/cancellation, time-zone/address-reveal behavior, message suppression/delivery recovery, and interrupted-link/authentication recovery.
11. D26–D28 settle console recap publication, immediate attendee uploads with removal/moderation, and photo reuse without explanation. Define remaining media limits, no-content-yet state, and edit/delete/retry behavior for personal posts/private feedback, including access and references afterward.
12. Events tab placement and confirmed/past/empty states, plus existing-map/search/visit regressions to cover.

## September 14 walkthrough amendments — current authority

Source: the two latest recordings, the inline screen-by-screen review, and the explicit response separating RSVP eligibility from installation. [Atomic transcript audit](audit/transcript-feedback-20260914.md) and [requirements ledger](audit/requirements.md) retain exact excerpts and dispositions. These amendments supersede conflicting earlier layout descriptions:

- Show nine event-detail states: full app / App Clip / browser, each with unknown identity / known account without an RSVP / recognized confirmed RSVP. Unknown must offer account recovery and cannot be treated as a new guest automatically.
- Every invite, confirmation, reminder, and shared View event link identifies the same event. The recipient’s actual account, booking, and available surface govern the destination; forwarding does not grant the sender’s rights.
- Apple/Google remains screen 03. Screen 04’s optional future-events checkbox has no trailing period. Screen 06 completes RSVP, offers calendar, and optionally offers download with the entry-QR reason. The guest can dismiss/stay and receive texts without installing.
- Recognized confirmed RSVP unlocks full guest list and View or change RSVP in App Clip/web. Cancellation lives inside management. Download is required for entry QR/admission, not these RSVP actions. The later reminder’s prominence timing is not selected.
- Required name and username precede entry/QR; profile photo stays optional. Recover saved data. Optional-photo layout A/B remains a design choice, not permission to skip required identity.
- Published recap triggers a content notice and SMS, plus full-app push when permitted. If the app was deleted, event detail still works; choosing check-in/upload explains reinstall and recovers the same attendance/completion.
- Event check-in resembles the existing composer, with optional event-specific tags generated/configured in the console. A ten-tag example is not a fixed count. No public rating; empty submission stays valid. Rich event recap uses cover imagery, normal comment controls, media plus, and upper-right Share.
- Normal map → special pin → collapsed event card → expanded event. Use Astir 001 at [place], smaller at, and handle long names. Explore square/round/glow/pulse; no final style is selected. Featured is visible to all permitted viewers during the console window, You reflects attendance, Friends reflects relevant friends’ attendance. Second-degree Friends is unresolved.
- Remove old screen 31 map recommendations and Explore nearby from old 30. The standard place profile keeps inline Events here; omit the giant bottom event CTA. Ordinary discovery remains.
- Console and staff scanner are internal web, including event setup, post-event work, first-party media, tags, and optional generated invitation codes with capped/uncapped usage. Codes may start off. Detailed redemption accounting remains open.
- Full guest list orders follows first and shows mutual counts, preserving the confirmed gate and existing protections. D7 reconnection remains deferred.
- Deliver the revised browser review, isolated SwiftUI front-end mock with real simulator captures, and a planned complete exit test suite. This is design-only work with sample data, not app/backend implementation or a production release.

The icon-color target remains unidentified; the user was asked which icon. Instagram sharing payload, exact invitation-code semantics, second-degree Friends, pin choice, and tag generation/persistence details remain review items. Do not treat them as selected by displaying an example.

## Workflow checkpoint

Using gstack `/spec` for discovery and specification, then `/plan-design-review`, then `/plan-eng-review`. User approved this sequence and requested product ambiguity resolution before implementation.

- Skill invocation: `spec`, interactive, `46880-1788990903-e4c63412`.
- Duplicate planning work found: REC-467 and REC-408. Reconcile with these rather than create competing planning records.
- No app code, backend data, external document, issue content, or release state changed.
- D1–D6 and D8–D35 are answered at the level recorded above. D7 is explicitly deferred until the user's next joint discussion; expanded privacy controls are also future work. The companion journey-state-matrix.md records known flows and concrete gaps; product-spec-draft.md consolidates approved behavior and proposed operating defaults for whole-document review. Question cards have repeatedly been hard for the user to find; a linked, opened questions document successfully supported A/B/C/D answers. Do not describe the full product/engineering spec as approved.
- D35 completes the current standalone decision queue. Present the complete product draft with proposed defaults clearly labeled for confirmation; design and engineering reviews remain outstanding. Approval of D35 alone does not approve the draft's operating proposals.
- The user subsequently said "ok go design review gstack" and asked whether onboarding is captured. Design review is authorized against the product draft, with onboarding emphasis; do not ask for the already-established review target/focus again. This authorizes review, not silent adoption of every proposed default. See design-review.md for progress and the first pending design choice. Existing app/source changes remain outside this spec-only task.
- The user then requested the whole journey as wireframes, with options and alternate flows, before answering isolated design questions. The first whole-flow version contained 73 numbered screens in 15 chapters, including a 24-screen main journey and side-by-side A/B onboarding comparison. It was rendered and checked as a local artifact. Design 1 remains pending; no operating proposals were silently accepted and the full seven-pass design review remains in progress. Continue from the full visual context, not another unexplained standalone card.

- September 14 fidelity checkpoint: the user requested a line-by-line audit after the RSVP/download sequencing error. Both transcripts and exact question/answer pairs were rechecked, including later amendments. See [the internal audit](audit/requirements.md) for 135 source-traced requirements, dispositions, and queued unapproved/open/deferred work. The corrected board has 125 frames in 16 chapters (28 main-journey frames), with targeted rendered checks passed. Current product draft, journey matrix and board preserve later download timing and distinguish proposals from approvals. This checkpoint supersedes the earlier 73/76-screen status; it does not finish the full design review or authorize app implementation.

- September 14 installed-entry clarification: the user explicitly asked about an invite opened with Astir installed, then about finding/tapping an event in the new Events tab. Both entry routes now visibly converge on the event detail inside Astir. The earlier existing-member Ready to RSVP state did not sufficiently illustrate those entry routes. Confirmed event cards open their current detail; Show ticket is separate. Signed-out, pending, waitlisted, offered, missing-phone and required-code variants preserve the app/event context. These clarify existing direction without approving new operating defaults. R136–R137 record the direct source messages. Current board: 136 frames, 17 chapters; main journey remains 28 frames. Checklist: 137 entries.

- Latest walkthrough baseline: 165 traced frames in 18 chapters, 156 requirement entries, 90 atomic new-transcript clauses, and 117 planned exit scenarios. The nine-state comparison and event-link decision controls are the starting point for visual review. The user authorized a separate SwiftUI front-end mock with sample data and simulator screenshots; this does not authorize production app or backend changes. See revision-20260914/review-notes.md for the current amendments and remaining choices.

- Native design deliverable: separate SwiftUI sandbox built successfully; 32 actual Simulator screenshots across two dedicated iPhones and a pulse recording. The native HTML gallery labels pin options A–D and distinguishes SwiftUI simulations of App Clip/browser from real platform integrations. See native-prototype/README.md for capture scope and limits. This is local design work, with no live Astir code/backend or external event-message changes.
