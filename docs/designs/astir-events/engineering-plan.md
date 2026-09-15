# Astir Events — engineering plan and conditional handoff

Status: engineering review completed through D19A on September 15, 2026. Architecture, contracts, tests, performance, 22 implementation tasks and two-lane rollout are documented. **Conditional handoff: nine product/design decision groups remain.** The affected task clauses remain gated; actual App Clip/provider/device, privacy, offline and distribution proofs belong to implementation. No production implementation or release was performed or authorized by this review.

Start with the [Joe/Ryan handoff](engineering-handoff.md), [shared contracts](engineering-contracts.md), [task list](implementation-tasks.md) and [remaining decisions](engineering-open-decisions.md).

## Approved scope

**D1 — A, approved September 15, 2026:** plan the complete Events journey, deliver it in stages, and organize implementation for two people/agents working in parallel where dependencies allow. Do not cut the post-event experience to make the first plan smaller. Under D8, Joe delegated the work split to engineering judgment; the plan below uses two changing work packages rather than permanent platform ownership. Individual task assignments can be made at implementation kickoff without reopening this planning choice.

The full loop is discovery → identity and verified RSVP → preparation texts → installed-app QR and staff admission → published recap → explicit event check-in → protected content and lasting map/place history. App, App Clip, browser fallback, Events-tab discovery, internal console, and recovery paths all remain in scope.

The September roadmap's outcomes are Astir 001 locked internally, a usable beta for 30 friends, and the brand/publishing system. The event may take place in October. Its older reduced event-hub suggestion does not supersede the subsequent Events product decisions. Current App Store availability is a prerequisite for live Events, not an assumption that the public release has already happened.

## Source and approval boundaries

- [Product spec draft](product-spec-draft.md), especially sections 2–5 and dated amendments.
- [September 14 walkthrough amendments](revision-20260914/review-notes.md).
- [All-flow screen review](astir-events-flowchart.html): 172 screen states/comparisons, including seven added for D9B offline admission; these are not 172 separately approved production screens.
- [Requirements inventory](audit/requirements.md): retain the approved, derived, proposed, open, deferred and superseded distinctions; later explicit user amendments take precedence.
- [Planned acceptance criteria](events-exit-criteria.md): 121 specified scenarios, including four added for approved D9B offline admission; these are not executed production integration tests.
- [Merged review copy on main](https://github.com/joelipshutz/wander/tree/main/docs/designs/astir-events), PR #641, merge commit `0d29d776f42132a28548355ae4e18302cdc3857a`. The main workflow classified this as documentation only. Merging the review artifact does not approve its open proposals or implement Events. REC-467 was observed as Done in Linear on September 15; that external status is not product approval.
- September 15 local amendments after that merge: D3A recovery copy is reflected in screens 56 and 59; D9B adds offline-door screens 166–172 immediately after the arrival section. The latest pass updates approval annotations on screens 94, 97, 123 and 133 for D4–D6/D13/D14; it does not change their layout or routes. All 165 original IDs, numbers, order and routes remain intact. The 172-screen, 13-section HTML flowchart passed its preview/expansion and offline-branch checks, with 26 native and 146 wireframe primary previews, no browser errors and no external requests. Local SHA-256 is `b8431da1c92cfac28a7b1ec5ac74c3cff5946f5654994cd6251c0efa905a3993`. These revisions and the completed conditional engineering handoff form the subsequent repository update; they were not part of PR #641. Supplemental graph exports are labeled as the earlier 165-screen snapshot. The invitation-code console mock shows generation/cap configuration; the approved consumed/held/available accounting and individual-code deactivation still need their detailed controls in a later design pass.

Reconnection, missed connections, expanded profile/check-in privacy controls, paid tickets and outside-host event publishing retain their existing deferred/excluded status. No further scope reduction was approved.

## Approved architecture boundary

**D2 — A, approved September 15, 2026:** Events is a cohesive module inside Astir's existing backend. Keep the existing identity, canonical places and visit history; do not introduce a separate Events backend requiring synchronization of those records.

```text
Full app       App Clip       Guest browser       Internal console
    \              |                |                    /
     +--------- authenticated Events operations --------+
                              |
                  Existing Supabase database
                              |
          +-------------------+-------------------+
          |                   |                   |
     Event / RSVP       Admission +         Canonical place
     lifecycle          historical             + visit
                        completion             + activity
```

This boundary governs persistence and shared business rules. The public event-preview route also exists; it returns only permitted public information and is not an authenticated participant operation. The console's operator authorization remains distinct from guest authentication. Engineering D7 below selects one full-access Team admin role for the Events console. The selected host packaging and proposed API/state contracts are detailed in [engineering-contracts.md](engineering-contracts.md); actual provider/Clip compatibility remains a foundation proof.

The minimum persistence contract follows the approved product behavior:

- Each event references one existing canonical place; an event is not a duplicate venue.
- RSVP state, valid admission and historical completion remain separate facts. Admission alone creates no personal post or Been visit.
- An explicit event check-in records completion and creates one event-linked canonical visit coherently. Profile, place history and the map present that same visit/activity.
- Deleting the personal event post removes its visit without erasing historical completion. Protected recap still requires valid admission; revoked admission can remove access even after completion.
- Venue rating is intentionally absent for an event check-in. Optional private event feedback is separate. Existing place ratings, notes, audiences, independent visits and explicit save intent must survive event creation/deletion.
- Personal-post engagement and the event's shared recap conversation are distinct. A second copy of the same personal post/history is not introduced.

The implementation must adapt the current generic save/projection/reconciliation behavior identified below; D2 does not approve invoking the existing save unchanged. New event operations use the repository/service boundaries rather than requiring views to coordinate independent writes.

| Failure at the approved boundary | Required outcome |
| --- | --- |
| Connection drops after event check-in commits | Retry resolves the same completion and visit; no second post or visit |
| Visit creation fails while completing check-in | No durable completed state that lacks its required visit |
| Personal event post is deleted | Remove that visit; retain completion and independent history; evaluate recap access using current admission |
| Event check-in has no rating or note | No generated venue rating and no fallback display of an unrelated older private note |
| A historical activity already has comments | Preserve its established engagement identity; do not duplicate or move conversations |

Keeping this work in the existing database permits a transaction boundary for related data changes. PostgreSQL functions are already used by Astir and are supported directly by Supabase's API ([database function documentation](https://supabase.com/docs/guides/database/functions)). Exact constraints, transaction locking, grants and retry contracts remain part of the remaining architecture review.

## What already exists — inspected facts

Initial read-only reconnaissance used `042f804d6c8419784c0e1827a9808998900195b8`. Relevant history integration was then rechecked against `a0117cff6ed55a967f4212b45bb28d8c39ca1488`. The subsequent flowchart merge changes documentation only.

| Area | Existing implementation | Events-specific gap |
| --- | --- | --- |
| Identity | Clerk Apple/Google sign-in, canonical user identity, session adoption | Verified phone status and an Events RSVP/recovery contract across app, Clip and web |
| Navigation | Deferred URL intent, place/profile/list/activity routes | Event link resolution, Events tab and a shortened return-to-ticket onboarding path |
| Places and history | Canonical places, user/place relationship, visit IDs, feed engagement, map/place presentation | Event identity, booking, admission, retained completion, event-aware post and deletion behavior |
| Media | Private visit-photo storage, photo upload/delete and activity engagement | Protected event gallery/video, event conversation and source-removal propagation |
| Notifications | Scheduled push worker, locked claims, retries and token suppression | Events message types, transactional SMS, independent future-event opt-in and delivery handling |
| Operations | Moderation audit primitives and backend access controls | Internal event console, RSVP controls, scanner and staff corrections |
| Distribution | Full app, share extension and widget targets | App Clip target/configuration, browser application and their deployment/recovery verification |

Checked-in configuration is not proof of hosted service configuration. Simulator/unit checks are not proof of production Apple sign-in or cross-install account recovery. Existing project learning `app_review_auth_release_gate` applies to that distinction; the already completed App Review account validation is not being reopened as a newly reproduced failure.

## Verified integration constraints

These findings motivated D2. The architectural boundary is approved; detailed persistence and migration behavior still requires the remaining review.

**F1 — P1, confidence 9/10: ordinary check-in saving is not an unchanged Events implementation.** The product requirement is “without a venue rating” (product spec line 31), while `Wander/Services/WanderLocalStore.swift:5338` calls `PlaceRating.scoreForSave(status: .been, score: ratingScore)`. `Wander/Models/PlaceRating.swift:25` returns `normalized(score) ?? defaultScore`, and line 6 sets `defaultScore = 3.0`. The same store writes `userPlace.visibilityRaw = visibilityForSave(visibility).rawValue` at line 5355. Events must preserve independent ratings/audiences (product spec line 38). These are existing generic behaviors, not an observed production Events bug.

**F2 — P1, confidence 9/10: recap eligibility cannot be inferred from a visible personal visit.** The product explicitly retains access after personal-post deletion when admission remains valid (product spec line 34). `LocalPlaceVisit` stores `deletedAt` but no event/admission/completion identity (`Wander/Models/LocalModels.swift:386–403`). `deleteVisit` soft-deletes the visit at `WanderLocalStore.swift:5483` and can remove its parent save at lines 5487–5489. A new Events contract must distinguish these lifecycles.

**F3 — P1, confidence 9/10: preserve canonical history and its existing conversations.** Main's new `supabase/migrations/20260915000053_resolve_checkin_history_engagement.sql` resolves historical visits to existing engagement and repairs missing explicit-visit activities without duplicating them. The Events plan must account for this newer main behavior rather than using the initial reconnaissance commit as its final baseline.

**F4 — P1, confidence 9/10 for the identity gap; App Clip SDK feasibility remains unverified:** the product requires the same event/reservation identity across Clip, web and the full app (product spec lines 42–46). Existing `AuthSession` holds `let userID: String` and `let phoneNumber: String?` (`Wander/Services/Auth/AuthSessionProviding.swift:49–53`), not a proof that a phone is verified. `ClerkAuthService.swift:841–849` maps canonical user identity and the primary phone string. The server's `app.current_user_id()` trusts a signed canonical identity claim with subject fallback (`supabase/migrations/20260814090000_clerk_identity_continuity.sql:8–26`). A phone string or a forwarded event link cannot establish the RSVP owner.

Clerk's documented OAuth linking depends on matching email addresses; different addresses require explicit association ([Clerk account linking](https://clerk.com/docs/guides/configure/auth-strategies/social-connections/account-linking)). Therefore Google RSVP followed by Apple sign-in using a different email cannot be assumed to restore the same reservation. Apple documents Clip/full-app storage and identity transfer facilities, but these do not establish automatic browser-cookie or arbitrary provider-session transfer ([Apple continuity documentation](https://developer.apple.com/documentation/appclip/sharing-data-between-your-app-clip-and-your-full-app)). The existing working product record explicitly keeps SMS verification separate from initial Apple/Google sign-in; no phone-only signup change has been approved.

Recovery behavior is approved under D3A below. The transfer mechanism still needs a concrete cross-surface authentication feasibility check; approval of the recovery experience is not evidence that the current SDK already implements that handoff.

All source line numbers above refer to application code at `a0117cff`, not an arbitrary older local checkout. They are reconnaissance evidence; no implementation tests have been run for Events.

## Approved account and reservation recovery

**Engineering D3 — A, approved September 15, 2026:** recover the existing account and its reservation. Reuse a valid current/transferred session when possible; otherwise preserve the event through original-account sign-in, account switching and support. Joe approved the concrete walkthrough with “thats good.” This engineering decision is separate from the earlier product D3.

```text
Full-app RSVP recovery (installation may happen later)
                |
      Valid authenticated session?
         / yes              \ no
 Lookup this account       Sign in, keeping the event
         \                  /
          Actual booking-state lookup
            /               |                 \
    Confirmed found     Other real state      No matching RSVP
          |             (pending/waitlist/     for this account
 Missing required        offered/canceled)          |
 name/username only      Show that state       Find my RSVP
          |                                        |
     Existing QR                          Original-account sign-in
                                          or Get help
```

The diagram covers recovery inside the installed app. Confirmed guests can continue using App Clip/browser for event details, the guest list and RSVP management before choosing to install; those actions do not route them to a required download.

- Check actual booking state before showing an absence. Loading, network failure and pending/waitlisted/offered states are not “no RSVP.” Repeated actions resolve the existing state.
- For a completed lookup without a matching RSVP, show **“No RSVP found for this account. Already RSVPed?”** with **Find my RSVP** and **Get help**. The sign-in screen says **“Sign in with the account you used to RSVP”** and offers Apple and Google. Do not claim to know that another account owns a booking from an ordinary event link.
- On successful original-account authentication, retrieve that account's existing reservation; do not ask the guest to RSVP again. Complete any required missing name/username before the QR and skip unrelated onboarding. A profile photo remains optional.
- Preserve the event if sign-in is canceled or another account is tried. An unrecoverable account goes to support without inventing a replacement reservation or bypassing the installed-app admission gate.
- Never treat a phone string, name or forwarded link as ownership proof. No silent identity merge or reservation transfer. A new self-service provider-linking flow (D3B) is not part of this selection.

**Feasibility work required before implementation handoff:** verify pinned Clerk 1.5.0 with actual App Clip Apple/Google authentication, Clip-to-app transfer and browser-to-app return, including expired/deleted sessions and a different current app account. Apple supports native Apple sign-in and federated authentication sessions in Clips ([Apple platform guidance](https://developer.apple.com/videos/play/wwdc2020/10120/)); the specific Clerk integration is not yet validated. Astir currently configures Clerk without shared-session options (`ClerkAuthService.swift:58`). Clerk's `transferable` sign-in option means sign-in/sign-up fallback, not cross-surface transfer. Browser cookies and native keychain sessions need separate handoff verification ([Clerk configuration](https://clerk.com/docs/ios/reference/native-mobile/configuration), [Clerk session overview](https://clerk.com/docs/guides/how-clerk-works/overview)). No auth configuration or production code was changed by this review.

## Approved waitlist offer capacity

**Engineering D4 — A, approved September 15, 2026:** an issued waitlist offer reserves one available spot for its recipient until the stated deadline. Only issue as many active offers as there are available spots. An eligible acceptance in time confirms that reserved spot. The previously approved default is 24 hours, adjustable in the console. D14 below subsequently sets the new-RSVP cutoff; bounding new offers by that cutoff and editing an already-issued deadline still require explicit handling without breaking a promised hold.

The capacity contract includes confirmed guests and active unexpired offers: their combined count cannot exceed event capacity. D5A and D6A below settle that pending manual approval and unfinished verification hold no capacity.

- Offer issuance, ordinary confirmation, manual approval, cancellation and capacity edits coordinate on the same event's capacity. Two operators must not each allocate the last place from stale counts.
- Acceptance atomically converts that recipient's offer hold to a confirmation, without consuming a second place. Validate the authenticated recipient, actual offer generation/state and current server time after obtaining the capacity lock.
- Decline or expiry releases the individual hold. Existing product D31 still protects released spaces for staff selection while a waitlist exists. No automatic next offer or promotion follows.
- An expired offer is ineligible even if an expiry worker runs late; it also stops occupying capacity without depending on that worker. Repeating a previously successful acceptance resolves its recorded result/current booking state, including a later cancellation, rather than creating another confirmation or reviving a canceled booking.
- Reject a capacity reduction below confirmed guests plus active holds and show the operator the conflict. Do not silently remove confirmations or withdraw promised spots. Separate cancellation/deadline-edit procedures are not approved by this constraint.
- An offer is visibly unconfirmed and does not unlock confirmed guest-list or QR access.

**Verified pattern and adaptation — P1, confidence 9/10:** the motivating draft requirement is “Hold one spot for each outstanding offer until acceptance, decline, or expiry” (product spec section 4, now approved by D4). Current `supabase/migrations/20260729123000_web_links_and_place_list_invites.sql:210–217` reads a specific invitation `for update`; it checks `if invite_row.expires_at <= now() then` at line 225 before `if invite_row.accepted_at is not null then` at line 228. Events needs both shared event-capacity coordination and a retry-result check that can recognize a successful earlier acceptance after its original deadline. A lock on separate offer rows alone would not serialize competing allocations. This is a requirement for new Events code, not an observed Events production bug. The existing list-invitation bearer token does not supply Events ownership semantics.

| Failure or race | Required outcome |
| --- | --- |
| Two operators offer the last spot | Only one hold commits; the other sees current capacity |
| Acceptance reaches the server after expiry, or waits for a lock past expiry | No confirmation from the expired offer; deadline checked within the capacity transaction |
| Acceptance commits but its response is lost | Retry finds that accepted booking; no second seat or misleading expiry for a still-valid confirmation |
| Cleanup job is delayed | Expired offers neither accept nor occupy capacity |
| Capacity is reduced while holds exist | Reject an incompatible reduction and explain the existing commitments |

## Approved capacity during manual review

**Engineering D5 — A, approved September 15, 2026:** a submitted application awaiting manual RSVP approval does not reserve a seat. Joe answered “a” to the pending D5 choice. Manual approval confirms an eligible applicant only when unprotected capacity is available. Existing issued waitlist offers retain their D4A holds; approving an application cannot take one of those spots or bypass D31's protection for waitlist selections.

If no eligible spot remains, keep the application pending and show the operator that approval could not complete. Do not show confirmation, send a confirmed-RSVP message or unlock confirmed benefits. Moving the application to a waitlist is a separate action, not an automatic consequence approved by D5. D6A separately settles unfinished SMS verification, which occurs before submission for manual review.

The same event-capacity transaction from D4 must govern manual approval. Two operators approving different applicants for the last available place cannot both succeed. A repeated approval or retry after a lost response resolves the existing/current booking without allocating another seat or sending another confirmation. These are consistency requirements for the approved behavior; no new backend implementation or runtime test is claimed.

| Review/approval situation | Required outcome |
| --- | --- |
| Many applications are pending | They occupy no seats; each remains visibly unconfirmed |
| Last available spot is approved concurrently for two applicants | One confirms; the other remains pending with a capacity explanation |
| Remaining capacity is reserved for issued offers or protected waitlist selections | Manual approval cannot consume it |
| Approval commits but its response is lost | Retry resolves the existing/current booking; no second allocation or confirmation message |

## Approved capacity during phone verification

**Engineering D6 — A, approved September 15, 2026:** a genuinely new RSVP attempt without an existing booking or issued offer does not hold a spot while the guest completes phone verification. Joe answered “a” to the pending D6 choice. Evaluate current eligibility, approval mode and available capacity when the verified guest submits the RSVP. Starting sign-in, entering a phone number, sending an SMS code and successful phone verification do not themselves reserve capacity or confirm attendance.

If the final available spot fills before submission, preserve the successful phone verification and event context, then offer the event waitlist. Joining remains the guest's choice. Do not require another SMS verification merely because capacity changed, automatically join the waitlist, or show a confirmation that did not commit. With manual approval enabled, use the actual pending/full result and D5's no-hold rule.

This applies to new unreserved attempts only. Recovering an existing confirmed account does not surrender or duplicate its booking. An existing D4 offer retains its original hold and deadline during sign-in or verification retry; the retry neither adds a hold nor extends one. An expired, unaccepted offer cannot confirm, while a previously successful acceptance resolves the actual existing/current booking under D3/D4.

| Guest state before submission | Capacity held? | Next step |
| --- | --- | --- |
| New guest signing in or verifying a phone | No | Submit after verification; check current capacity and approval mode |
| Application pending manual review | No | Astir approves only with unprotected capacity |
| Current valid waitlist offer | One spot until its stated deadline | Eligible owner accepts that offer |
| Existing confirmed RSVP | Existing confirmed spot | Restore the booking; do not RSVP again |

No temporary verification-seat timer or abandoned-seat cleanup lifecycle is added. SMS resend/expiry controls remain a separate provider/interaction detail; D6 is not approval of a specific resend countdown. Capacity and SMS recovery acceptance cases below are planned, not executed.

## Approved console authorization

**Engineering D7 — user clarification, approved September 15, 2026:** one **Team admin** role has access to every Events console function. Joe wrote: “A jsut one team admin role for now that has all accfess. anyone with console can do everything”. The explicit written clarification governs the decision. There is no organizer/door-staff role split or per-event staff assignment in the first implementation.

Every authorized team admin can manage all Events through the console: event setup and publishing, guest lookup, RSVP approval, waitlist offers, scanning and verified manual admission, attendance corrections, private venue settings, media/moderation, private event feedback, recap publishing, and event messages. These controls continue to enforce the approved business rules; full console access does not permit an accidental capacity overrun or invent attendance on a guest's behalf. All-access is scoped to the Events console, not infrastructure credentials or unrelated service administration.

Use individually identified accounts and server-maintained Team admin membership tied to canonical identity. The backend must authorize console reads and mutations; merely opening the console URL, signing into an ordinary guest account, or changing a client-side flag grants no console access. Revoked membership blocks subsequent protected server operations. D9 explicitly permits a previously authorized offline roster; a disconnected device cannot learn about a remote revocation until it reconnects. Record the acting identity for console changes. There is one authorization level among admitted team members, so scanner users have the same Events permissions as everyone else with console access.

Guest-facing routes and guest previews still use their actual/requested guest permission state. Team admin console access does not turn an ordinary public event response into a source of private addresses, phone numbers, feedback or recap content.

**Existing boundary to preserve — confidence 9/10:** `supabase/migrations/20260813010000_community_moderation.sql:79–81` uses `revoke all on table public.content_reports from public, anon, authenticated, service_role;` followed by `grant select on table public.content_reports to service_role;`. That is privileged tooling access, not a human console-membership system. The moderation runbook (`docs/backend/community-moderation-runbook.md:59`) prohibits exposing the service-role key to an app or browser. Events needs its Team admin authorization while keeping privileged backend credentials server-side; client UI visibility alone is insufficient. Existing moderation audit attribution is a useful pattern, not proof that console membership already exists.

| Console access case | Required outcome |
| --- | --- |
| Authorized Team admin opens any Events control | Full Events functionality, including the scanner and private feedback |
| Ordinary member or unauthenticated visitor opens the same route/calls its API | No protected console data or mutation |
| Team admin membership is revoked while the page stays open | Subsequent server reads/writes fail authorization; offline roster/queue follows D9's reconciliation rule |
| Admin changes event settings or corrects attendance | Preserve actor attribution and approved event/guest invariants |
| Admin previews a public or nonattendee experience | Apply that preview's guest permissions; no administrative data leakage |

No membership, credentials or live-service configuration was changed by this planning decision.

## Two-agent execution model selected under D8

**Engineering D8 — scheduling delegated September 15, 2026:** Joe replied, “lets do whatever makes the most sense to get it done, not sure if platform is the best way to do it”. This delegates the division of work; it does not approve a fixed platform split or assign Joe/Ryan by specialty. The selected plan is **small parallel foundations, then end-to-end journey ownership**, with two active implementation packages at a time. This is a planning decision, not authorization to start production implementation.

A permanent app/Clip versus backend/web split would put the common backend, both web surfaces, messages, media and operational tooling behind one lane. Splitting journeys immediately would instead duplicate work on identity, event state, routing, migrations and the console shell. A short shared-foundation stage addresses those risks before the work separates by journey.

### Stage 0: agree the minimum shared contract

One agent drafts the event/place/user identifiers, booking/admission/completion states, guest/admin permission responses, operation errors and retry identities; the other reviews them against the approved flows and existing Astir boundaries. Use common deterministic fixtures, including pending, offered, admitted-without-completion, completed-with-deleted-post and approximate-home states. This is a compact dependency contract, not an attempt to finish every backend endpoint before client work begins.

### Stage 1: two parallel foundation packages

| Work package | Concrete output | Boundary |
| --- | --- | --- |
| Events data and rules | Minimum event/account/booking operations; canonical place relationship; agreed admission/completion interfaces; capacity and Team admin foundations; an early check that event visits preserve existing ratings, notes, audiences and history | Own backend contracts and migration ordering. Prove the risky history behavior early; leave full gallery, delivery and console feature work to the journey packages. |
| Entry and identity | App/Clip target and link integration; actual Apple/Google and account-recovery feasibility; minimal guest-web and console entry shells; client adapters against the shared contract | Own project generation, shared login and app entry changes in this stage. A mock screen or scaffold is not a completed authentication integration. |

**Foundation checkpoint:** integrate the two packages as soon as a real signed-in guest can retrieve the correct event and booking state, with a minimal persisted RSVP operation and verified retry/identity behavior using controlled test data. Confirm the admission/completion/visit interfaces and demonstrate the canonical-history protection. Report what has actually been exercised across Clip, browser and full app; public distribution and SMS-provider verification remain explicit checks wherever not yet proven. Do not wait for a fully built backend or polished UI to discover incompatible contracts.

### Stage 2: two complete journey packages

| Work package | Owns the complete behavior across necessary surfaces |
| --- | --- |
| Before the event and at the door | Discovery and Events upcoming states; RSVP/verification/invitation codes; manual review, offers and cancellation; guest list and management; preparation messages; QR, scanner and admission; associated Team admin console panels |
| After the event and on the map | Recap publication and its invitation trigger; explicit event check-in/private feedback; gallery/video/conversation; deletion/removal effects; past Events; event pins, place and canonical history; associated Team admin console panels |

Both packages may touch native, web and backend feature code. Each owns its flow's required tests and failure states. After-event development uses the shared admitted/completed fixtures while real door work proceeds; it must later pass with admission produced by the integrated door flow. The shared messaging foundation has one owner and an agreed enqueue/result contract; the other package adds its event-specific triggers rather than building another delivery system. Console feature panels attach to the common shell and single Team admin guard.

### Coordination and joined release

```text
Agreed event / identity / state / permission contract + fixtures
                           |
          +----------------+----------------+
          |                                 |
  Events data + rules                Entry + identity
  and history proof                  app / Clip / browser
          |                                 |
          +---- early real integration -----+
                           |
          +----------------+----------------+
          |                                 |
  RSVP -> texts -> door              Recap -> check-in -> map
  including its console              including its console
          |                                 |
          +--- complete joined journey -----+
                           |
     exceptions, regressions and compatible distribution
```

- Give each shared integration file one active editor per stage: `project.yml` and generated project, app entry/root navigation, auth, shared model/repository/store seams, map integration and migration ordering. Feature owners submit narrow changes through that integrator; they do not independently redesign these seams. Handoff the integrator role explicitly at a checkpoint rather than creating a permanent third lane.
- Use separate short-lived worktrees/PRs with small integrations. Rebalance the next ready package between Joe and Ryan's agents at checkpoints; do not leave an agent idle solely because a permanent platform label says another agent owns the remaining work. Another person's skillset or availability is not assumed.
- Each completed slice must work with its actual dependencies. The whole approved loop remains the delivery objective, including exceptional paths, guest permissions, source-media removal and independent place-history preservation.
- Treat app, App Clip, guest web, console and backend distribution as one compatibility gate before public Events links activate. Existing source has no App Clip target or guest-web/console application. The current GitHub workflow classifies TestFlight changes rather than building/testing these new artifacts; their build, test and publication paths must be part of implementation tasks.
- The final handoff assigns bounded task estimates as alternative human-led and agent-execution ranges; human supervision/setup and external waits remain explicit limitations. The unproven cross-surface authentication and history integration are critical-path risks; the design's 32 native captures and now 172 review states are not evidence those integrations are implemented.

**Source evidence:** `project.yml:31–55` defines the existing native targets and directly attached dependencies; `Wander/Resources/Wander.entitlements:7` contains the existing associated link domain; `Wander/App/AppEntryView.swift:214` is an existing universal-link entry seam. `.github/workflows/testflight-manifest.yml:19` and `scripts/testflight-manifest.mjs:34` govern release classification. `AGENTS.md:134` explicitly warns against uncoordinated parallel changes to project files, map, store and Supabase migrations. The history constraints motivating the early proof are F1–F3 above. These are evidence for the sequencing choice, not runtime validation of Events.

## Required protected data and media integration

These requirements implement the already approved home-reveal/expiry, attendee recap, source-removal and account-isolation rules. They do not reopen those product decisions or require a new choice of permissions.

- Keep one canonical place identity while separating the generally visible approximate home presentation from authorized exact address/coordinates/navigation. Check the event's reveal window and the viewer's current entitlement on the server. Apply this across event details, map, place history and shared/calendar previews; ordinary place queries must not provide a bypass. Preserve independently established location rights.
- Protect both recap metadata/conversation and the actual photo/video bytes. Admission plus historical completion governs the recap, including after personal-post deletion. A selected gallery photo used in a permitted public post does not unlock the surrounding gallery, its conversation or other source media.
- Source removal invalidates gallery entries, personal-post references and generated derivatives, while retaining the rest of each post and its visit. Removing a personal post does not remove the historical completion needed for valid recap access.
- Protected caches must be scoped to account/event and the relevant permission/source version. Clear or retire affected entries on account change, source removal, revoked access and exact-address expiry; revalidate before redisplay when entitlement is uncertain. A failed authorization must not fall back to an old protected URL or cached private presentation.
- Use the existing account-bound authenticated download pattern as the starting point for revocable media, with current event/media authorization. Video and range requests need equivalent access checks. A signed URL's lifetime alone is not an access-revocation design. Backend response caching and client caching must both respect the contract.

**Verified constraints — confidence 9/10, not reproduced production Events bugs:** `LocalModels.swift:172,176–177` stores ordinary place `address`, `latitude` and `longitude`. `Wander/App/WanderBackend.swift:651` builds a photo-cache key from canonical place, photo and variant; lines 652–670 can return memory/disk content before a network request. `PlacePhotoDelivery.swift:129,199,206` reads disk bytes and uses capacity-based eviction rather than event permission expiry. `SupabaseRepositories.swift:979–982` issues a visit-photo URL with `expiresIn: 3600`. These paths cannot be reused unchanged as proof of Events privacy.

`WanderSupabaseClient.swift:954–967` already obtains authenticated headers and calls `validateAuthenticatedUser(expectedUserID)` for downloads. Extend that account-bound pattern with Events authorization rather than adding an unrelated media identity system. Existing visit-photo access uses `app.can_read_place_visit(vp.visit_id)` (`20260709220000_place_visits_visit_photos.sql:547`); that must not substitute for the independent admission/completion facts required by Events.

Supabase documents that signed-token expiry and CDN cache lifetime are independent, and storage deletion can take time to propagate. Consequently, a short token or deleted storage object alone cannot establish immediate permission/source invalidation ([Supabase Smart CDN documentation](https://supabase.com/docs/guides/storage/cdn/smart-cdn)). Keep the access-aware application response in control and verify the actual deployed delivery/cache behavior. No promise to recall content a guest already saw or copied is introduced.

| Failure/change | Required observable result |
| --- | --- |
| A home reveal window expires while its screen is open | Retire exact presentation/navigation and return to approximate data, unless independent access applies |
| An old request finishes after account switching | Its private data cannot appear under the new account or populate that account's cache |
| Admission is revoked during recap use | Subsequent protected access fails; stale content is not used as an authorization fallback |
| A personal post is deleted while valid admission/completion remain | Its post/visit disappears; protected recap eligibility remains valid |
| One source photo appears in the gallery and several posts, then is removed | Retire all corresponding references/derivatives without deleting the other post content or visits |
| Refresh fails when current private entitlement cannot be established | Show a retryable unavailable/locked state, not an unsupported private-data fallback |

No new permanent offline recap/home-access promise is implied. Door connectivity and any approved offline roster procedure are separate from content caching. Exact API/storage shapes and implementation tests remain part of the detailed tasks.

## Approved offline door admission

**Engineering D9 — B, approved September 15, 2026:** Team admins may use a previously downloaded guest list to admit matching guests during a total connectivity outage and record admissions locally for later reconciliation. Joe selected the option explicitly noting that the list may miss recent cancellations/changes and recap access waits for server validation. This extends the previously approved online manual-lookup fallback; it does not waive installed-app/account requirements or permit guest self-admission.

The Events console must prepare an event-specific roster while the Team admin is authenticated and online. Display the event, last successful synchronization time and a clear offline state. Scope stored roster data to that account/event and the minimum information needed to identify a confirmed guest and perform the approved door checks. This is a deliberate offline capability, not an incidental browser cache of the full administrative console. Keep unrelated private feedback, recap media and private venue data out of the roster payload.

Offline admission creates a durable local record identified by a stable operation ID and linked to the roster snapshot, event, guest/booking and acting admin. Show **Admitted offline · awaiting sync**. Reopening or retrying the same local operation must not lose it or produce another logical admission. Detect repeats on the same device, while acknowledging that disconnected devices cannot share a live entry state. Never present local totals as authoritative across devices.

On reconnection, submit the recorded operations through the same admission validation and uniqueness boundaries used online. Current server authorization, event/booking state and duplicate/conflict handling govern the outcome. Valid operations become server-recorded admission once; invalid or conflicting operations remain visible for Team admin resolution. Do not silently restore a canceled RSVP, invent a confirmed booking, discard unresolved rows, or label the entire queue successful after partial failure. Client timestamps are context for review, not proof that a currently invalid booking was valid at entry.

Only valid server-recorded admission contributes recap eligibility. The attendee still needs historical completion of the explicit event check-in for full protected recap access. A local queued admission alone unlocks neither check-in eligibility nor protected content. A repeat synchronization cannot create a personal place visit or send duplicate attendance-dependent invitations.

Protect the downloaded roster and queue on the device. A local sign-out/account switch must lock or remove protected roster access, never show it to the next account, and must make unsynchronized work explicit before any destructive cleanup. Remote team-membership revocation or booking changes cannot be learned during a total outage; enforce current rights on synchronization and route unresolved admissions to an authorized Team admin. Do not promise remote erasure of data from a disconnected device. Exact local persistence, retention and browser lifecycle handling require implementation validation.

| Offline door case | Required result |
| --- | --- |
| Guest matches a downloaded confirmed entry and passes installed-app/account checks | Admin can admit and queue the operation, visibly awaiting server validation |
| No roster was prepared, or event/guest identity cannot be established | No invented confirmed entry; show the missing basis and require team resolution |
| Guest canceled after the roster download | Offline view may be stale; synchronization exposes the conflict without silently restoring their booking |
| The same guest is recorded on two disconnected devices | Reconciliation produces one canonical admission and makes conflicting/repeated records understandable |
| Queue upload partly succeeds, connection drops and upload repeats | Retain unresolved operations; successful operation IDs return their existing result |
| Staff session expires or membership is revoked | Authenticate an authorized Team admin before protected server access; preserve a resolvable queue without bypassing membership |
| Attendee opens the recap before offline entry has reconciled | No protected access from the pending local record; normal eligibility resumes after valid recorded admission |
| Browser reloads or is closed during an outage | Durable prepared roster/queue works within verified browser support; explicitly report unavailable/lost storage rather than pretending it synced |

Include the console's offline shell/persistence and reconciliation checks in the before-event/door package. The after-event package consumes only canonical server admission, so it can proceed independently using agreed fixtures. Browser offline capability must be tested on intended staff devices; no offline implementation or tests were executed by this review.

## Approved invitation-code counting

**Engineering D10 — A, approved September 15, 2026:** a capped invitation code consumes a use when an eligible booking becomes confirmed. Joe answered “A” to the D10 choice. Pending applications and waitlist entries consume no uses. For a five-use code, five pending applicants have consumed zero uses; five successful confirmations consume five. Invitation-code allowance and event-seat capacity remain separate limits.

- All confirmation paths—automatic RSVP, manual approval and accepted waitlist offer—apply the same code accounting. Confirm the booking, allocate its event seat and settle the required code use coherently. Failed identity/verification, invalid code or unavailable capacity cannot consume a use or produce a misleading confirmation.
- Typing/checking a code, sending/resending a phone-verification code, viewing an event and joining a pending/waitlist state do not consume the confirmed-guest allowance. A code remains distinct from identity proof and phone verification.
- Retries or duplicate responses for the same successful confirmation resolve the existing booking/redemption without spending a second use. A competing operation must not observe the same final allowance as available and oversubscribe it. Coordinate invitation-code quota with event capacity in a consistent transaction/lock order.
- **Required interaction with D4's promised offer:** issuing an offer that requires a capped code must reserve its necessary code allowance as well as its event seat. This is a held allowance, not a consumed use. Eligible timely acceptance converts both reservations into one confirmed booking/redemption. Decline/expiry releases the unconsumed allowance and seat hold. If the code has insufficient available allowance, do not issue an offer that cannot be honored; show the Team admin the blocking limit.
- The console distinguishes consumed, held-for-offer and available allowance, alongside the separate event-capacity counts. Pending applications and waitlist entries do not reserve code allowance merely by existing. Direct confirmations cannot take allowance already committed to a valid offer.

Engineering D11A below settles cancellation and subsequent rebooking; D12A settles disabling a code for new versus already-submitted requests. Other edits to issued codes/caps remain unresolved. Binding a generated code to a named invitee would also be additional product behavior; the code itself never transfers a booking or proves the holder's account.

| Code-count case | Required outcome |
| --- | --- |
| Five-use code; five applicants remain pending or waitlisted | Zero consumed uses; no confirmed benefits |
| Successful eligible confirmation | One use settles with one booking/seat allocation |
| Two confirmations contend for the last available use | At most one new confirmation consumes it; the other retains a truthful nonconfirmed state |
| Confirmation fails for lack of event capacity | No code use consumed |
| Offer holds the last required code allowance | Another confirmation cannot spend that hold; timely eligible acceptance can settle it |
| The held offer expires or is declined | Release the unconsumed code allowance; no automatic next offer |
| Successful confirmation response is lost | Retry resolves the same booking/use; no duplicate charge or confirmation message |

This is an extension of the already selected shared Events transaction boundary. Existing place-list invitations demonstrate a locked acceptance pattern, but do not implement this capped Events-code ledger. No live codes, bookings or counters were created or changed.

## Approved cancellation and code allowance

**Engineering D11 — A, approved September 15, 2026:** Joe answered “A” to returning the invitation-code use when a confirmed guest cancels. A five-use code with five confirmed guests returns to four consumed uses after one successful cancellation. This changes the code allowance; the already approved event-capacity and protected-waitlist rules still govern the released seat.

- Settle the booking cancellation, seat release and release of its associated consumed code use coherently. Release exactly the unit attached to that confirmation, once; preserve the booking/redemption history for support. Bookings without a code cannot manufacture allowance.
- A failed cancellation retains the confirmed booking and its consumed use. Repeated cancellation requests return the existing result without returning another use. Existing self-cancellation timing remains unchanged.
- Rebooking is a new attempt under current code validity/available allowance, registration, approval, capacity and waitlist rules. It has no reserved claim to the released use or seat; another eligible person may obtain them first. It must not bypass D31's protected waitlist inventory.
- Retrying an old successful RSVP or offer acceptance after cancellation returns the current canceled state; it must not revive the booking or consume the released allowance again. A deliberate new rebooking action is distinct from a retry.
- Unaccepted-offer decline/expiry releases held, unconsumed allowance under D4/D10; it is not an additional cancellation refund. Concurrent cancellation, rebooking, confirmation and offer operations preserve both quota and capacity limits.

Planned acceptance covers exactly-once release, failed cancellation, stale retries, concurrent reuse and rebooking when the allowance or seat has been taken. D11 does not determine code edits or event-wide cancellation; D12 and D13 below subsequently settle code deactivation and upcoming-event rescheduling. No production cancellation or counter changes were made.

## Approved invitation-code deactivation

**Engineering D12 — A, approved September 15, 2026:** Joe answered “a”: disabling one invitation code blocks new submissions using that code, while already-submitted pending requests and waitlist entries retain their code eligibility. Existing applicants can still progress subject to approval, available code allowance, event capacity and protected-waitlist rules. This is deactivation of an individual code, not switching off the event's entire code requirement.

- Retained eligibility belongs to an actual account-bound request submitted with verified identity/phone and successful code validation. Merely opening a link, typing/checking a code or starting verification does not establish it. Record the accepted request's association with the code; do not infer eligibility from an untrusted client flag or a matching code string.
- Deactivation and submission must have a consistent server ordering: a submission committed before deactivation retains eligibility, while a new submission afterward cannot use the code. A lost-response retry retrieves the existing submitted state without being misclassified as a new submission or creating another request.
- Pending/waitlisted requests still reserve neither seats nor code allowance. Deactivation alone cannot force these guests to find another code, but exhausted allowance or capacity can still prevent confirmation or offer issuance. Keep the console's eligibility, quota and capacity outcomes distinct.
- Preserve existing confirmations and valid issued offers; disabling a code is not a booking cancellation or offer withdrawal. Existing individual guest/booking eligibility rules still apply.
- Cancellation followed by a deliberate rebooking is a new attempt under D11. Its old code eligibility does not carry over; a disabled code cannot authorize that new submission. Preserve the original history without reviving the canceled request.

Other code edits, quota reductions and event-wide access-rule changes are not selected by D12. Planned acceptance distinguishes previously submitted requests, unfinished attempts, concurrent deactivation/submission, lost-response retries and canceled guests returning. No live code configuration was changed.

## Approved upcoming-event rescheduling

**Engineering D13 — A, approved September 15, 2026:** Joe answered “A”: if an upcoming event moves to a new future date, keep existing RSVPs confirmed, notify guests of the new date and let them cancel. Do not require another acceptance step or replace the event with a new invitation. This approval covers a future schedule change, not event-wide cancellation, a venue change or rewriting a completed event.

- Keep the canonical event/link, booking identity, seat allocation and code redemption. Rescheduling alone neither releases nor consumes another seat/code use. Canceled or otherwise unconfirmed bookings are not revived or promoted by a date edit; pending/waitlist status remains truthful.
- Persist the new schedule as one coherent event revision. Event detail, Events, management, ticket, console and newly generated calendar data show its current date/time and time zone. A ticket still checks current server eligibility; an old link resolves the same current event. Existing exported calendar copies may require a user update—do not claim that an already-saved calendar entry changes automatically without a verified update mechanism.
- The approved important-change program sends affected confirmed guests the new date and a route to their event/RSVP management. Record the send intent with the successful change; a failed save sends no change notice, and retrying the same published revision does not create another logical notice or booking. Delivery failure does not roll back the truthful event schedule or pretend the guest was notified.
- Recalculate future event-relative reminders against the new schedule, invalidating obsolete scheduled work. A worker must recheck the current event revision, booking eligibility and whether its message is still due before dispatch. Do not replay reminders for the old date; late/already-elapsed reminder policy and provider retry details still require review.
- Recalculate event-relative exact-address reveal/expiry using the new start/end and configured offsets, preserving independent location rights. If the new reveal threshold is later, event-based access returns to approximate until eligible again; already disclosed addresses cannot be recalled. Do not silently reinterpret a specifically configured absolute-time override as a relative offset; make the resulting schedule explicit in console review.
- Guests who cancel follow the approved pre-start self-cancellation rule against the current event start and D11's seat/code release rules. Rescheduling itself does not add a cancellation deadline or retain entitlement after cancellation.
- Preserve issued offer deadlines/holds unless a separately reviewed action changes them; a reschedule is not an automatic offer extension or withdrawal. Surface conflicts between an issued deadline and the proposed schedule rather than silently breaking the promise. Pending applications and waitlist entries require no replacement request merely because the date changed.
- A prepared offline door roster may still contain the old schedule during a total outage. Display its snapshot date/time and freshness; on reconnection, reconcile against the current event/booking under D9. Do not promise that an offline device receives a schedule edit immediately.

Planned acceptance includes successful and failed schedule updates, duplicate publication, old links/tickets, stale queued reminders, already-revealed home locations, exported calendars and stale offline rosters. These are integration requirements, not completed runtime checks. Event cancellation, completed-event edits and issued-offer policy remain separate. D14 below subsequently sets the new-RSVP cutoff.

## Approved late RSVP and registration close

**Engineering D14 — A, approved September 15, 2026:** Joe selected “Allow new RSVPs until the event ends by default.” Astir can set an earlier closing time in the console. A person arriving at 7:15 for a 7–10 pm event can complete the ordinary online RSVP flow if registration is still open and the other requirements allow it. The earlier proposed default of closing at event start is superseded.

- Use event end as the default closing time, with an explicit earlier override. Show the effective close in the console and enforce it using authoritative server time at the verified RSVP submission. Starting sign-in or verification before closing does not reserve an entitlement to submit afterward; a lost-response retry still retrieves a request that actually committed before close.
- Late guests complete normal account/phone verification, required name/username, installed-app QR and admission. A required invitation code, manual approval, event capacity and D31's protected waitlist inventory still apply. An open clock never converts pending/waitlisted status to confirmed, reserves an unfinished attempt's seat or bypasses an issued offer.
- At/after the effective close, do not create a new RSVP from an unfinished attempt. Preserve event/account state and show that registration is closed, while keeping an existing booking recoverable. Closing new registration does not cancel an existing confirmed RSVP or withdraw a still-valid issued offer.
- Self-cancellation still closes at event start under the earlier approved rule; D14 does not extend it for late registrants. Recap/check-in requirements still depend on validated admission and explicit completion.
- This is an online signup path, not offline registration. A guest absent from a prepared offline roster cannot be invented as confirmed during an outage; D9's existing missing-roster/help path applies.
- Follow D13 when the event schedule changes. Recompute a closing time that follows event end, distinguish a specifically configured earlier absolute cutoff, and surface conflicts with existing issued offers. A change must not silently shorten an offer's promised deadline. New-offer bounding and explicit issued-deadline editing remain to be resolved together with those commitments.

Planned acceptance includes a late eligible signup, console earlier close, verification crossing the cutoff, a lost successful response, capacity/waitlist/manual-approval cases and the offline missing-roster path. Registration remaining open does not itself guarantee an attendee can enter before the event finishes.

## Code-quality review

Read-only inspection uses the clean review checkout at `f8d258e869503a28d70518a050dff36a344134c6`, whose app code retains the `a0117cff` baseline cited above. No implementation files were edited or application tests run by this review.

**CQ1 — P2, confidence 9/10: the proposed shared native entry layer needs a deliberate dependency boundary.** The motivating plan requirement is Stage 1's “App/Clip target and link integration” and Stage 2's two journey packages sharing integration seams. Existing code has `var copy: AuthGateCopy` in `Wander/Services/Auth/AuthSessionProviding.swift:229`, while `struct AuthGateCopy: Equatable` is defined inside `Wander/Services/WanderLocalStore.swift:24`. That store is 11,457 lines at the inspected baseline. Adding the full auth source to a Clip target therefore requires resolving this and its other dependencies; it is not already an independent Clip-ready module. `Wander/App/WanderBackend.swift:198–218` collects the existing feature repositories, and `project.yml:58–62` / `:149–153` already demonstrate separately selected shared source groups. These are inspected source facts and a future integration risk, not an observed Events runtime bug. Store size alone is not the finding; the concrete cross-feature dependency and proposed second native target are.

**CQ2 — P1, confidence 9/10: preserve the already-required error/state distinctions at the Events transport boundary.** D3 distinguishes failed lookup from no RSVP, D4 preserves expiry/capacity outcomes, D7 requires current Team admin authorization and D9 exposes reconciliation conflicts. Existing `Wander/Services/Remote/WanderSupabaseClient.swift:399–400` defines token failure as `statusCode == 401 || statusCode == 403`; `:370–387` refreshes/retries that RPC; `:512–515` maps both statuses to `WanderRemoteError.notAuthenticated` and other failures to `invalidResponse(String)`. `WanderTests/BuildConfigurationTests.swift:602` explicitly covers 403 refresh behavior. This generic contract is not sufficient proof of the required Events distinction between signed-out, signed-in-but-denied, expected booking outcomes and uncertain network completion. No production Events failure was reproduced.

Implement the approved Stage 0 operation-error contract with stable Events outcomes, authoritative resulting state and operation identity. Preserve current account fencing and repository/transport seams; do not infer authorization, cancellation, expiry or capacity by parsing human error strings. Unknown transport completion remains recoverable through the same operation identity/current-state lookup, not a new blind mutation. Resolve permission-versus-authentication meaning before it is discarded by generic decoding, with focused regression coverage of existing refresh behavior. This is required by D3/D4/D7/D9, not an additional guest-facing policy or authorization to rewrite unrelated networking.

**Existing check-in integration constraint (D2, not a new product vote):** `CheckInSaveDraft` at `RepositoryProtocols.swift:902–905` bundles ordinary `userPlace`, `visit` and `historicalWant` inputs. `WanderBackend.swift:1036–1052` labels its sequential parent/visit writes a “Test and local repository fallback,” while production `CheckInRepository` writes atomically. Events completion must retain its own admission/completion/private-feedback meaning and use the approved cohesive transaction, with faithful fakes; a permissive fallback must not make a split-write Events test look valid. Reconcile the returned canonical visit through the existing history boundary without adding another visit writer or turning private event feedback into a place rating.

**Coverage of the other code-quality dimensions:** DRY review found reusable selected-source groups, transport/auth fencing, repository protocols and canonical-history conventions; no production Events implementation exists yet to claim measured duplicate Events code. Shared contracts/presentation must not become four independent versions of capacity or permission policy. Debt/abstraction review bounds the integration work under approved D16A; a wholesale store rewrite, app-wide package migration or second networking/backend stack is not required by the approved scope. Error recovery cases are recorded above and in the acceptance criteria, with detailed tests still to be reviewed.

**Diagram accuracy:** the historical `docs/specs/wander-ios-product-spec.md:1062` diagram says “SwiftData Local Store,” whereas current `Wander/Services/WanderStorePersistence.swift:20–24,40–45` uses `wander-store-v1.json` and a `JSONEncoder`/atomic file write. Preserve dated historical designs as history, and draw the Events integration against current persistence/adapters. No inline ASCII architecture diagram was found in the inspected core entry/store/backend/protocol/transport files that would need an immediate source edit. The current plan's conceptual backend and two-lane diagrams remain consistent; the concrete D16 diagram below adds the native dependency boundary.

## Approved Events code organization

**Engineering D16 — A, approved September 15, 2026:** Joe answered “a”: give Events focused components and a small shared layer for the full app and App Clip, with narrow connections to the existing systems. This accepts the small up-front setup/extraction cost to keep Clip dependencies bounded and reduce collisions between the two work lanes. D2's backend, canonical identity/place/history and D8's sequencing remain unchanged.

The following paths are planned repository locations, not existing implementation files or newly approved production artifacts. Use the current XcodeGen selected-source pattern initially; do not require an app-wide package migration to create the boundary.

| Planned area | Responsibility and dependency boundary | Integration owner |
| --- | --- | --- |
| `AstirEventsShared/Contracts` | Native event/booking/admission/completion representations, operation/result types and repository interfaces. Keep independent of the full app's store, root navigation, map and ordinary place-edit forms. Guest code never receives service-role credentials or protected admin-only records. | Stage 0 contract owner; one editor at a time after agreement |
| `AstirEventsShared/Presentation` | Shared native event detail/RSVP/management presentation and state mapping where the app and Clip have the same approved behavior. Host-provided actions handle sign-in, invocation, handoff and navigation. Surface-specific installation/QR rules remain explicit rather than inferred from a missing callback. | Before-event package, coordinated with Clip entry owner |
| `AstirEventsShared/Transport` | Events repository implementation using the existing account-bound auth/transport conventions and CQ2 outcome contract. Extract only the required reusable protocols/types/helpers from their current app location. Compose dependencies in each host; do not import `WanderBackend` or `WanderLocalStore` into the Clip merely to obtain one helper. | Entry/identity foundation owner; shared seam thereafter |
| `Wander/Features/Events` | Full-app Events tab, upcoming/past sections, native entry QR, event check-in and recap UI. Keep booking/door and recap/history files separate so journey owners do not edit one enormous Events screen/store. Screens depend on Events contracts; server permissions remain authoritative. | Before-event/door and after-event/map packages in their respective subareas |
| `Wander/Services/Events` | Full-app adapters for event completion, canonical visit/history reconciliation, protected media caches and map/place presentation. Consume the one server result and existing visit identity; do not issue a second ordinary place check-in or mix private feedback into venue ratings. | After-event/map package, through the shared-history integrator |
| `AstirEventsClip` | Thin new Clip host for invocation, host authentication and shared guest presentation. Include only its required shared sources/resources/dependencies. App-only QR/admission, explicit check-in/upload, map/history and unrelated onboarding remain in the full app. | Entry/identity foundation, then before-event package |
| Guest browser and internal console | Web-native feature modules consume the same documented wire contract and language-neutral fixtures. Sharing native Swift source with web is not required. Guest and Team admin projections remain separate; before/after-event panels attach to the same authenticated console shell. | Foundation shell owner, then the corresponding journey package |
| Existing Supabase functions/migrations | Shared canonical transactions, authorization, capacity/code accounting, admission/completion, delivery intents and protected projections. Clients render the authoritative result; they do not each reimplement mutation eligibility as an authority. | Data/rules foundation, then serialized migration ownership with journey contributors |

```text
 Full-app Events host                     App Clip host
       |                                      |
       +------- shared guest presentation ----+
                         |
              shared Events contracts
                         |
              Events repository adapter
                         |
        required auth + account-fenced transport
                         |
          Existing Supabase Events operations
                         |
       canonical booking / admission / completion / visit
                         |
               full-app integration only
                         |
        history adapter -> existing local snapshot/cache
                         -> place / map / feed presentation

 Browser / console -> equivalent wire contract + fixtures
                   -> same authorized server operations
```

The lower full-app history path is not a dependency of the shared presentation or Clip target. Public event reads use their permitted projection without manufacturing a signed-in session; account-bound guest mutations and Team admin operations use their appropriate authorization. The diagram is a dependency/data-flow sketch, not a claim that every screen must make the same authenticated request.

### Concrete integration rules

- Separate `AuthGateCopy` and other genuinely needed small auth contracts from incidental full-store placement. Audit transitive dependencies before adding shared source membership, including app configuration/brand resources and SDK availability. Preserve the existing canonical-account checks, session switching and token refresh behavior while adding the Events-specific permission distinction. Actual Clerk/Clip compatibility still needs the foundation proof.
- Shared native presentation accepts small contract values and host actions, not `WanderStore`, `WanderBackend`, `AppEntryCoordinator` or app persistence models. Source-folder naming alone does not enforce this: each host must compile with its selected sources and dependency set, so the foundation verifies the boundary before feature work grows around it.
- Preserve expected-account checks before/after token retrieval and network completion, account-keyed refresh deduplication and stale-response rejection. Bind Events state, drafts and pending operations to the account/event; switching accounts must not attach the previous user's result or protected content to the new session. Protect unresolved offline door work under D9 rather than silently clearing or reassigning it. Existing evidence includes `WanderSupabaseClient.swift:230,287,458` and `AuthSessionProviding.swift:550,592`.
- Keep an explicit public-preview transport seam. The current RPC path calls `configuredAuthenticatedUserID()` at `WanderSupabaseClient.swift:363`; it cannot serve a logged-out event unchanged. Add the permitted public projection without weakening authentication for booking, admission, recap or Team admin commands.
- Keep user intent/state separate from backend state: shared presentation maps loading, authenticated-no-match, pending, offered, confirmed, admitted and completed without granting rights itself. Unknown or unsupported response states cannot default to confirmed or reveal protected content. Reconcile a lost response using the same operation identity rather than creating a replacement booking.
- Use separate Events completion/private-feedback inputs and a required cohesive repository command. Its result carries the canonical visit/completion outcome into the full-app adapter. Ordinary place drafts remain responsible for ordinary place saves; event media references and private feedback retain their approved boundaries. An existing local/test sequential-write fallback cannot stand in for the Events atomic contract.
- Maintain one set of wire examples, state/outcome names, timestamps and pagination semantics for Swift and web consumers. Share code where the language/runtime fits, and compare each consumer against the same fixtures where it does not. Do not build a universal cross-language UI framework or regenerate unrelated app contracts for this feature.
- The Stage 1 integrator owns `project.yml`, generated project membership, shared auth/transport extraction, canonical link parsing/deferred intent and root entry composition. Current link parsing lives in `WanderWidgetShared/WanderWidgetDeepLink.swift:68`; `Wander/App/WanderWidgetLaunchRequest.swift:32` guards inbox delivery through validated session state. Share event-link interpretation across native hosts while retaining host-specific routing, event context and fresh account-owned booking lookup after sign-in/account switching. The after-event integrator owns narrow canonical-history/map hooks. Each seam has one active editor at a time; the other lane contributes a reviewed patch or contract request. Feature work remains parallel in separate short-lived worktrees.
- Account/event/permission/source-scoped cache behavior follows the existing protected-data section. A shared source directory is not permission to share one user's protected cache with another account or to make the Clip depend on the full app's JSON snapshot.

**Code-quality result:** CQ1 is addressed in the selected plan by D16A; CQ2 and the canonical check-in constraints are included as required implementations of previously approved behavior. All six code-quality dimensions were examined. No application code was changed and no app/Clip build or runtime test has passed as part of this review; those checks belong to implementation and the next test-review plan.

## Test coverage review — D17A

The [engineering test plan](engineering-test-plan.md) maps **121/121 named acceptance scenarios plus 24 technical risk groups** to planned files, assertions, test layers and package owners. The [full mapping](test-review/coverage-map.md) retains each source authority trace; unresolved product clauses remain unresolved. The [mapping validator's report](test-review/mapping-verification.json) confirms unique membership, required fields and 78 existing source locations. This validates the planning artifact only: no Events tests have been implemented or executed, and no runtime coverage percentage is known.

The plan includes an ASCII execution/user-flow coverage tree, branch/error cases, regression obligations, fixtures, deterministic clocks and a staged execution/evidence model. Existing XCTest/XCUITest, pgTAP, Node and Deno suites provide adjacent patterns. Extend the existing full-app UI target; add Clip-specific wiring, the browser test harness and Events test jobs during implementation. The repository's release-manifest workflow does not prove runtime correctness. Planned filenames are package-level implementation guidance, not 158 separate work tickets or a selected browser framework implementation.

### Findings carried into the test requirements

| Finding | Evidence and required proof |
| --- | --- |
| **T1 — high-priority validation gap, confidence 10/10:** sequential/rollback tests cannot prove competing seat, code or offer allocation | `scripts/supabase-smoke-test.mjs:64–85` wraps checks in one rollback transaction. Add an isolated separate-session race runner with committed fixture setup, controlled lock contention and authoritative post-lock deadline checks. Assert final counts and stable operation identities. Covers B05–B15, TB01–TB02. |
| **T2 — high-priority validation gap, confidence 9/10:** existing auth and relaunch tests cannot prove real Clip/browser installation recovery | `AuthSessionTests.swift:159,279` uses the preview provider; `OnboardingUITests.swift:598` is simulator-fixture relaunch. Prove Apple/Google, current-number verification, installation followed by icon launch and original-account recovery with the actual signed app/Clip. Record public invocation separately from TestFlight. Covers I01–I12, TN01–TN04 and E01–E05. |
| **T3 — high-priority validation gap, confidence 9/10:** separately passing screens or mocked replies can hide broken admission-to-recap/history integration | Existing ordinary history tests and local auth fixtures lack Events records. E01–E12 each carry the same real account/event/booking/admission/completion/visit through the joined journey; seed only the starting state and verify server facts after each boundary. Offline pending admission must not create recap rights. Covers P/V/H cases and TP03. |
| **T4 — high-priority validation gap, confidence 9/10:** UI blur, a successful storage delete or a mocked provider response is insufficient evidence | Current photo cache/delivery behavior was inspected in the protected-data section; existing APNs tests inject delivery. Test protected JSON, original/thumbnail/range bytes, current access after revocation/removal, direct grants/RLS, delayed message work and ambiguous provider outcomes. Distinguish one logical send intent from physical provider delivery. Covers P13–P15, H06, M08–M14 and TP01/TB03/TB06/TB07/TB09. |

These are required proof of already-selected behavior, not newly reproduced production bugs or changes to product scope. The critical regression suite preserves ordinary check-ins/saves, ratings, notes, audiences, history engagement, lists, blocks, widgets, authentication and onboarding. No new LLM feature was selected; no model-eval claim is made.

Automate contract/decoder/state/DB/worker/browser branches; use integrated service tests where mocks hide ownership or side effects; retain actual device/provider checks for invocation, installation, auth, camera, delivery and staff-browser offline persistence. Forty-seven named scenarios include a real-device requirement in the map; this is a set of scenarios with variants, not a claim that 47 device runs are sufficient. Unknown implementation branches join the map during each feature PR.

The [QA journey guide](events-qa-test-plan.md) gives `/qa` and `/qa-only` the surfaces, actions and expected outcomes without implementation detail. Its gstack discovery copy is saved at `/Users/joelipshutz/.gstack/projects/joelipshutz-wander/joelipshutz-codex-rec-467-events-flowchart-eng-review-test-plan-20260915-153217.md`. The workspace guide remains the source; update the discovery copy when that guide changes.

**Engineering D18 — A, approved September 15, 2026:** Joe answered “A” to continue from the completed test mapping to performance and then final delivery/rollout planning. This checkpoint does not mark tests passed or turn proposed product clauses into approvals.

## Performance review — D18A

The [performance review](performance-review/README.md) examines query growth/N+1, memory, caching and slow or complex paths, with five implementation risks: PF1 event-entry/query dependencies, PF2 capacity-lock contention, PF3 event-wide delivery backlog, PF4 media/map resource growth and PF5 offline roster/queue growth. The linked evidence memos distinguish inspected source structure from unmeasured Events behavior. **No Events benchmark, build, load test or hosted performance query ran.**

The existing architecture remains the starting point: current Supabase, focused shared native components, page/viewport summaries, current authorization and the selected two-stage ownership. No new consequential product/architecture choice was identified. Normal implementation tuning—page sizes, candidate indexes, bounded transfer concurrency—does not impose a guest or upload limit or waive a selected flow. A materially higher-cost service, reduced media capability or a demonstrated delivery-delay compromise would require a concrete new decision if the foundation measurements reveal it.

Source evidence is especially important for notification planning: the checked-in scheduler invokes push once per minute, while the worker and latest claim function cap a single batch at 20. A 300-job fixture therefore requires 15 claim batches through that scheduled path alone, before competing backlog/retries; this is conditional code arithmetic, not measured live delivery latency or an Events SMS implementation. Preserve durable intent, current eligibility, per-delivery outcomes and provider rate limits while designing the event messaging foundation. Do not simply inherit the old scheduling throughput or raise concurrency without a bound.

The [measurement plan](performance-review/measurement-plan.md) defines independent entry, query, transaction, door, delivery, media-memory and map measurements plus new test locations. Its synthetic 30/300/3,000-record fixtures and provisional timing/memory review triggers are diagnostic starting points, not approved product caps or service-level promises. Establish the actual Clip/provider/device baseline at the foundation checkpoint and retain both correctness and performance evidence. Historical REC-441 measurements supply test methods and implementation precedents; they are not Events results.

The existing test mapping remains 121 named acceptance scenarios plus 24 technical risk groups. Performance measurement groups supplement them, particularly contention, delayed delivery, offline persistence, video ranges, stale caches and ordinary-map regressions. They do not count as executed acceptance tests.

**Engineering D19 — A, approved September 15, 2026:** Joe answered “A” to finalize the two-person engineering handoff after the performance review. Remaining product/design proposals keep their existing status. No production implementation starts from this checkpoint.




## Final execution and rollout

The [handoff](engineering-handoff.md) assigns two changing lanes: parallel data/history and entry/identity foundations, then before-event/admission and after-event/history journeys. T01 agrees the shared contract; T06 proves one real persisted RSVP across hosts before broad feature work. T12 messaging is early so both journeys can use it. T18 integration and T19 performance can run together after T17 access proof, using separate fixtures/devices. The [module-level dependency table](implementation-tasks.md#dependency-and-ownership-table) and task JSON define the exact DAG; shared auth, project generation, migrations, console shell and history hooks have one active integration owner.

Twenty-two work packages total an estimated 252–490 active agent-hours, or 488–796 engineer-hours if human-led. These are alternative estimates, not additive totals. A conservative fixed-lane model yields 168–320 active elapsed agent-hours, roughly 6–11 working weeks at an illustrative six productive lane-hours per weekday, excluding external waits. Re-estimate after T06; this is not a delivery commitment or measured AI speedup.

The [rollout and rollback plan](engineering-rollout.md) defines additive server deployment, compatible native/Clip/web/console artifacts, disabled discovery/activation controls, public invocation proof and a later authorized live-event gate. Rollback must preserve bookings, admission/completion facts, unresolved offline records and message outcomes. Distribution is in scope. No deployment, account configuration, migration or app release happened during this review.

## NOT in scope

- Reconnection/missed-connections feature — the product discussion explicitly deferred it for a later joint session.
- Expanded profile/check-in privacy settings — previously deferred; the selected current access rules still apply to both place and event data.
- Paid ticketing, checkout and refunds — the selected first release uses free RSVP.
- Outside-host publishing — Astir's Team admin console owns this release's events.
- A second Events backend, generalized cross-language UI platform or broad package rewrite — D2/D16 select existing infrastructure and focused native sharing.
- Production implementation or release in this review — this deliverable is a plan and review artifact; the tasks specify future work.

Own-video in the personal composer, second-degree Friends, a separate event bookmark and the other OD01–OD09 clauses are **open**, not silently cut from scope or accepted. Shared-gallery video is already in scope. No new follow-up TODO candidate was created; full-scope engineering work is in the tasks and previously deferred work retains its status. No TODOS.md change is proposed.

## Failure handling and diagram maintenance

The [failure matrix](engineering-failure-modes.md) covers each flow family in the test diagram, with realistic failures, planned tests, explicit handling and visible outcome. There are **zero unmapped silent-failure planning gaps** after review. This does not mean runtime error handling exists: Events implementation and tests are still future work. Unknown write completion, stale access, partial offline reconciliation, capacity races and ambiguous provider delivery are explicitly represented.

Add small inline diagrams during implementation at these proposed boundaries:

| Proposed location | Diagram to keep synchronized with tests |
| --- | --- |
| `AstirEventsShared/Contracts` state models | Independent viewer/booking/admission/completion states; unknown is not none |
| Events transaction migrations and `supabase/tests` | Capacity + code hold acquisition, confirmation, expiry/cancellation; fresh clock after locks |
| `events-web/src/console/offline` | Complete snapshot → durable pending operation → current-state server reconciliation |
| `Wander/Services/Events` history adapter | Explicit check-in → one canonical visit + historical completion; post deletion preserves completion |
| Event media service/worker | Authorized source → derivatives/references → source removal and cache invalidation |
| Events notification worker | Durable logical intent → bounded attempt → provider receipt/unknown outcome → reconciliation |

These paths are implementation guidance, not assertions that new files exist. Existing history/projection diagrams and feed grouping must be updated if their behavior changes. Preserve original visit/activity identifiers through the newer REC-494 display grouping on main.

## Implementation Tasks

The flat list below is generated from the same task source as the [detailed task handoff](implementation-tasks.md). Each package includes concrete files, assertions, exit criteria, source findings and open-policy dependencies there; the [JSONL](implementation-tasks.jsonl) is the machine-readable handoff. Priority P1 blocks release. No checkbox is complete.

- [ ] **T01 (P1, human: ~12–20h / agent: ~6–12h)** — shared-contract — Define Events states, commands and shared response fixtures. Lane shared; depends on none.
  - Surfaced by: D2/D3/D7/D16; CQ1/CQ2; T1–T4; TR01/TR03/TR05. Inspected evidence remains anchored at f8d258e/a0117cff; reconcile implementation against latest main, including f8493c0 Feed grouping/profile-header drift.
  - Files: `AstirEventsShared/Contracts/EventContracts.swift`, `AstirEventsShared/Contracts/EventRepository.swift`, `events-web/src/events/contracts.ts`, `tests/fixtures/events/event-contracts.json`, `docs/decisions.md`
  - Verify: Cross-review the minimum user/event/place/booking/admission/completion/visit/source/operation identifiers, typed outcomes and current permissions; ordinary data and guest/admin projections remain distinct.; Validate deterministic native/web fixtures for unknown, failed lookup, no booking, pending, offered, confirmed, admitted and completed-with-deleted-post; unknown states fail closed.; Record timestamp/cursor/version/error semantics, public-read seam, analytics allowlist and short compatibility contract; separate proposed product clauses from approved rules.; At kickoff verify current issue/worktree/main baseline and shared-file owners; one active editor for contract and migration sequencing. No project-wide framework rewrite.
- [ ] **T02 (P1, human: ~24–40h / agent: ~12–24h)** — data-foundation — Add canonical Events data and prove history preservation early. Lane A; depends on T01.
  - Surfaced by: D2/D4/D7/D16; CQ2; T3; TR02/TR04; existing ordinary-check-in rating/audience hazards.
  - Files: `supabase/migrations/YYYYMMDDHHMMSS_events_core.sql`, `supabase/tests/events_core.sql`, `supabase/tests/events_completion_history.sql`, `Wander/Services/Events/EventHistoryAdapter.swift`, `WanderTests/Events/EventHistoryAdapterTests.swift`
  - Verify: Implement minimum event/canonical-place relationships, independently persisted booking/admission/completion identity and Team admin membership/authorization; include a narrow real verified-RSVP operation for the checkpoint.; Implement/prove the completion-to-canonical-visit seam with a faithful repository contract: null event venue rating, preserved old notes/ratings/audiences/save intent, idempotent operation and coherent rollback.; Run pgTAP grants/RLS/schema and ordinary-history regressions; extend reserved-identity hosted rollback smoke when the implementation environment is authorized.; A owns serialized migration allocation in foundation; the history adapter is handed to B after T06. Do not use the test/local sequential generic check-in fallback as atomic Events proof.
- [ ] **T03 (P1, human: ~24–48h / agent: ~12–28h)** — entry-identity-foundation — Build thin App Clip host and prove actual account continuity. Lane B; depends on T01.
  - Surfaced by: D3/D16; CQ1/CQ2; T2; PF1; TN01–TN04/TR06.
  - Files: `project.yml`, `Wander.xcodeproj/project.pbxproj`, `AstirEventsClip/AstirEventsClipApp.swift`, `AstirEventsShared/Transport/EventTransport.swift`, `Wander/Services/Auth/AuthSessionProviding.swift`, `Wander/Services/Auth/ClerkAuthService.swift`, `Wander/Services/Remote/WanderSupabaseClient.swift`, `WanderWidgetShared/WanderWidgetDeepLink.swift`, `Wander/App/AppEntryView.swift`, `AstirEventsClipUITests/EventClipLaunchTests.swift`
  - Verify: B is the sole foundation editor for XcodeGen/generated membership, entitlements, shared-auth extraction and root link entry; extract only necessary contracts rather than importing full store/map into Clip.; Build selected full-app/Clip hosts, then use signed isolated devices/accounts for actual Apple and Google provider exchange, phone-verification mechanism and supported continuation; validate SDK/platform capabilities instead of assuming normal iOS docs prove Clip support.; Preserve canonical event intent through auth cancellation, account switch, install/icon launch and original-provider recovery; no silent linking/booking merge. Distinguish 403 permission denial, auth failure and uncertain operation outcome.; Measure cold invocation, auth and event-read dependency intervals separately. If approved Clip/auth continuity is infeasible, report the specific evidence and alternatives before changing the journey.
- [ ] **T04 (P1, human: ~20–32h / agent: ~8–18h)** — web-console-foundation — Create guest web fallback and authenticated Team admin shell. Lane B; depends on T01.
  - Surfaced by: D3/D7/D16; CQ2; T2/T4; PF1; C-NOAPP.
  - Files: `events-web/package.json`, `events-web/src/guest/EventEntry.tsx`, `events-web/src/auth/AccountSession.ts`, `events-web/src/console/ConsoleShell.tsx`, `events-web/src/console/AdminGuard.ts`, `events-web/tests/guest/entry.spec.ts`, `events-web/tests/console/authorization.spec.ts`, `supabase/tests/events_console_authorization.sql`
  - Verify: Implement public fallback and browser Apple/Google/phone/session adapters against the common contract; missing Clip is not missing RSVP. Real provider/backend continuity is the T06 acceptance gate.; Create a separate console shell with individual operator identity and Team admin contract/error handling; direct-API revoked/nonadmin enforcement must be proved with the real T02 backend at T06.; Add browser harness and shared contract fixtures. Keep full confirmed guest-list/RSVP management available without download; app-only QR/check-in/upload are explicit actions.; Web/native host shells and credentials remain separated; no service-role secret or admin payload is exposed to guest clients.; Scaffold shells against shared fixtures independently of pending provider proof; connect real identity/backend before T06 passes. Mock shells are not that proof.
- [ ] **T05 (P1, human: ~12–20h / agent: ~6–12h)** — test-ci-foundation — Wire feature tests, isolated fixtures and compatibility jobs. Lane shared; depends on T01, T03, T04.
  - Surfaced by: D16; T1–T4; TR01–TR06; existing release-classification CI is not runtime verification.
  - Files: `.github/workflows/events-checks.yml`, `scripts/events/fixtures.mjs`, `scripts/events/concurrency.mjs`, `scripts/events/evidence.mjs`, `WanderTests/Events/EventWireContractTests.swift`, `events-web/tests/contracts/event-wire-contract.spec.ts`, `supabase/tests/events_contract_compatibility.sql`
  - Verify: Extend existing XCTest/XCUITest, pgTAP, Node and Deno runners; add the actual Clip/web build/test paths rather than using manifest CI as a substitute.; Implement reserved rollback SQL fixtures plus a separate committed isolated multi-session race fixture with cleanup; HTTP/storage/worker journeys must not depend on another connection’s uncommitted data.; Create common run IDs, controlled clock/recipient adapters and evidence statuses passed/failed/blocked/skipped; no real guest sends or secret-bearing logs.; Contract checks reject unknown rights, source leakage and old/new version incompatibility; coordinator serializes project/workflow/migration changes.
- [ ] **T06 (P1, human: ~12–20h / agent: ~6–12h)** — foundation-integration — Prove signed-in event and booking retrieval across real hosts. Lane joined; depends on T02, T03, T04, T05.
  - Surfaced by: D8 foundation checkpoint; D2/D3/D16; T2/T3; PF1/PF2.
  - Files: `scripts/events/foundation-checkpoint.mjs`, `docs/testing/astir-events-foundation-proof.md`, `WanderUITests/Events/EventFoundationTests.swift`, `events-web/tests/journeys/foundation.spec.ts`
  - Verify: Use one isolated account/event through actual provider sign-in, current-number verification, minimal persisted RSVP, response-loss retry and same booking lookup in app/Clip/browser; do not seed the post-RSVP state.; Demonstrate the completion/history seam preserves a distinct prior rating/note/audience/save; prove failed visit write cannot leave committed completion.; Record exact signed builds, configuration, current account IDs and all unavailable capabilities; calibrate entry/query baselines without promising final SLOs.; Proceed to two journey packages once shared contracts are proven; if a real platform constraint breaks the approved experience, bring that concrete tradeoff back rather than building around a mock.; Prove T04 browser retrieval with a real account-owned booking and public projection against T02, plus direct-API denial for a nonadmin/revoked Team admin. Shell fixtures cannot satisfy this gate.
- [ ] **T07 (P1, human: ~20–32h / agent: ~10–18h)** — event-configuration — Implement event publishing, schedule and private-home controls. Lane A; depends on T06.
  - Surfaced by: D2/D7/D13/D14; T4; PF1; C02/C03/H01–H06.
  - Files: `supabase/migrations/YYYYMMDDHHMMSS_events_configuration.sql`, `events-web/src/console/EventEditor.tsx`, `events-web/src/console/HomeSettings.tsx`, `supabase/tests/events_home_projections.sql`, `supabase/tests/events_schedule.sql`, `events-web/tests/console/event-editor.spec.ts`
  - Verify: Build event draft/configuration/publish controls for one canonical place, media cover, timing, approval/code settings, offer default/override, registration close and map styling window.; Enforce consent prerequisite and approximate/exact home projections by current booking/window independently of recap; prevent ordinary canonical-place queries, previews/calendar/nav from bypassing it.; Implement upcoming reschedule revision semantics: retain booking/seat/code/offer identity, recompute relative reveal/expiry, preserve explicit absolute override, persist change intent and invalidate obsolete scheduled work.; Serialize migrations through the designated data integrator; test before/at/after time boundaries and failed save. Event cancellation/completed-event edits remain excluded until their policies are approved.
- [ ] **T08 (P1, human: ~32–48h / agent: ~16–28h)** — booking-rules — Implement atomic RSVPs, invitation quotas, offers and cancellation. Lane A; depends on T06, T07.
  - Surfaced by: D4–D6/D10–D14; CQ2; T1; PF2; TB01/TB02/TB10.
  - Files: `supabase/migrations/YYYYMMDDHHMMSS_events_booking_transactions.sql`, `supabase/tests/events_capacity_codes.sql`, `supabase/tests/events_booking_transitions.sql`, `scripts/events/concurrency.mjs`, `events-web/src/console/GuestReview.tsx`, `events-web/src/console/InvitationCodes.tsx`
  - Verify: Implement short event-scoped transactions with stable operation/booking-generation identities and consistent event/code lock order; no provider work under lock.; Enforce no hold for unfinished verification/pending requests, offer holds for seat plus required code allowance, confirmation-only redemption, exactly-once cancellation refund, grandfathered committed requests after code deactivation and default registration through event end.; Use current server time after locks; late expiry worker and lost successful response cannot violate promise/current state. Reject capacity reduction below confirmations plus valid holds.; Run separate-session controlled races for last seat/code/offer, cancellation/new attempt and lock waits crossing deadlines; assert final allocation and message intents.
- [ ] **T12 (P1, human: ~32–48h / agent: ~16–30h)** — event-delivery — Implement one durable SMS/push program and console controls. Lane A; depends on T07, T08.
  - Surfaced by: D13; product D19/D26/D29; T4; PF3; TB03/TB06/TB09/TR03/TR05.
  - Files: `supabase/migrations/YYYYMMDDHHMMSS_events_delivery_intents.sql`, `supabase/functions/events-notification-worker/index.ts`, `supabase/functions/events-notification-worker/index.test.ts`, `events-web/src/console/EventMessages.tsx`, `Wander/Features/Events/EventNotificationRouter.swift`, `supabase/tests/events_delivery_intents.sql`
  - Verify: Build the single enqueue/claim/settlement contract shared by RSVP/reminder/change/offer and recap triggers; keep stable message identity, current event revision/recipient eligibility and per-channel consent.; Distinguish verified event phone, future marketing checkbox and event-SMS opt-out; canonical View event links and private-safe previews work without app. Console edits timing/content/preview with truthful save outcomes.; Use bounded claims/concurrency and explicit unknown-provider-result recovery; replayed callbacks or push failure do not duplicate intended SMS. Assess existing 20-job/minute scheduled path rather than inheriting it as Events throughput.; Test controlled sender/provider receipts, stale jobs, reschedule/cancel/permission changes, malformed callbacks, claim expiry and mixed success. Do not log recipient/private content or call accepted queued messages delivered.
- [ ] **T09 (P1, human: ~32–48h / agent: ~16–28h)** — guest-journey — Complete app, Clip and browser RSVP, account setup and ticket routes. Lane A; depends on T03, T04, T08.
  - Surfaced by: D3/D6/D14/D16; CQ2; T2; PF1; C-NOAPP.
  - Files: `AstirEventsShared/Presentation/EventDetailView.swift`, `AstirEventsShared/Presentation/EventRSVPFlow.swift`, `AstirEventsShared/Presentation/EventGuestList.swift`, `events-web/src/guest/RSVPFlow.tsx`, `events-web/src/guest/GuestList.tsx`, `Wander/Features/Events/EventsScreen.swift`, `Wander/Features/Events/EventTicketView.swift`, `Wander/Features/Events/EventAccountSetupView.swift`, `WanderTests/Events/EventRoutingTests.swift`
  - Verify: Wire nine event states, canonical link sources, actual lookup/loading/recovery, same-surface back navigation, verified phone, Apple/Google cancel/error, invitation code/pending/waitlist/offer/manage/cancel against real commands.; Keep optional install CTA dismissible and guest list/manage available to recognized confirmed Clip/web guests; unknown is distinct from successful no-booking lookup.; Full app Events tab shows confirmed/upcoming/past/empty states; QR uses only missing required name/username setup, optional photo and no general-tour/permission gate. Guest list pages follow-first/mutual counts under current visibility.; Run native/web parity, accessibility, malformed/stale response, account-switch and provider cancellation tests; do not duplicate transaction eligibility as a client authority.
- [ ] **T10 (P1, human: ~20–32h / agent: ~10–18h)** — online-door — Implement QR validation and verified manual admission in console. Lane A; depends on T08, T09.
  - Surfaced by: D5 product admission separation; engineering D7/D9; CQ2; T3/T4; PF2.
  - Files: `supabase/migrations/YYYYMMDDHHMMSS_events_admission.sql`, `events-web/src/console/Scanner.tsx`, `events-web/src/console/GuestLookup.tsx`, `supabase/tests/events_admission.sql`, `events-web/tests/console/online-admission.spec.ts`
  - Verify: Validate actual event/booking/account/app-entry prerequisites; no browser-only unsupported-phone waiver. Handle scan duplicate, wrong event, canceled credential, ambiguity, QR failure and current Team admin authorization.; Manual lookup verifies the eligible booking/full-account requirement and records the same canonical admission command; correct/revoke attendance affects access without creating/deleting a personal post.; Keep lost-result operation identity and resolve before retrying; admission creates neither canonical place visit nor completed event check-in.; Test direct unauthorized API access and camera/lookup on intended staff hardware in addition to browser fixtures.
- [ ] **T11 (P1, human: ~24–40h / agent: ~12–24h)** — offline-door — Add complete offline roster and durable admission reconciliation. Lane A; depends on T10.
  - Surfaced by: D9B/D7/D13; T3/T4; PF5; TB04/TB05/TB08/TP03.
  - Files: `events-web/src/console/offline/RosterStore.ts`, `events-web/src/console/offline/AdmissionQueue.ts`, `events-web/src/console/offline/Reconcile.ts`, `events-web/tests/console/offline-admission.spec.ts`, `events-web/tests/console/offline-performance.spec.ts`, `supabase/migrations/YYYYMMDDHHMMSS_events_offline_reconciliation.sql`
  - Verify: Download bounded versioned chunks and promote only a complete durable roster; show event, snapshot freshness and explicit offline status. Index local lookup; persist individual stable operations before acknowledging offline admission.; Preserve queued work through reload/update/network loss, separate original account/event ownership and handle quota/eviction/storage failure without false success. Do not include recap/private feedback/unnecessary exact-home data.; Reconcile bounded batches through current server membership/booking/admission uniqueness; duplicates and invalid/stale records have individual truthful outcomes and unresolved rows remain visible.; Test two disconnected devices, canceled booking/rescheduled event/revoked admin, response loss, partial batches and real staff browser lifecycle. Recap remains locked before successful server validation.
- [ ] **T13 (P1, human: ~24–40h / agent: ~12–24h)** — event-completion-history — Build event check-in, private feedback and canonical history adapter. Lane B; depends on T06.
  - Surfaced by: D2/D16; product D1–D4/D33/D34; CQ2; T3; PF4.
  - Files: `Wander/Features/Events/EventCheckInView.swift`, `Wander/Services/Events/EventHistoryAdapter.swift`, `Wander/Services/Events/EventCompletionRepository.swift`, `supabase/migrations/YYYYMMDDHHMMSS_events_completion.sql`, `events-web/src/console/EventFeedback.tsx`, `WanderTests/Events/EventCheckInTests.swift`, `supabase/tests/events_completion_history.sql`
  - Verify: Own the history seam handed over from A: cohesive completion result creates exactly one event-labeled canonical-place visit, no public venue rating, and preserves independent old visit/note/rating/audience/save intent.; Implement existing-style composer with optional note/photos/event tags and independently optional private stars/comment; all-empty explicit submit is valid and routes to recap. Keep feedback restricted to authorized Team admin access.; Bind draft/result to account/event, retry stable operation after force-close/lost response, and retain historical completion after personal-post deletion; failed visit write rolls back completion.; Test generic ordinary check-ins/saves unchanged, original engagement identity preserved, deletion/retry/old snapshots do not duplicate or resurrect event visits. Selected-media pipeline completes in T14.
- [ ] **T14 (P1, human: ~40–64h / agent: ~20–40h)** — protected-event-media — Implement shared photo/video uploads, reuse and source removal. Lane B; depends on T13.
  - Surfaced by: D2/D16 protected-data requirements; product D6/D27/D28/D32; T4; PF4; TP01.
  - Files: `Wander/Services/Events/EventMediaRepository.swift`, `Wander/Services/Events/EventProtectedMediaCache.swift`, `Wander/Features/Events/EventGalleryView.swift`, `supabase/functions/events-media/handler.ts`, `supabase/functions/events-media-worker/index.ts`, `supabase/migrations/YYYYMMDDHHMMSS_events_media_references.sql`, `events-web/src/console/EventMedia.tsx`, `scripts/events/media-access-smoke.mjs`
  - Verify: Implement attendee and first-party shared-gallery photos/videos, own-photo composer contribution, same-post gallery-photo references and no preapproval/reuse explanation. Finalized eligible uploads appear immediately.; Use paged authorized manifests, sized derivatives, file-backed bounded video upload/playback and stable retry/finalization IDs; do not hold all gallery/original/video bytes in memory.; Current admission/completion/source/post-audience governs JSON and actual original/thumbnail/HEAD/range bytes. Account/event/permission/source cache identity, old URL failure, invalidation and stale-response guards apply before redisplay.; Source removal retires all post/gallery references and derivatives while preserving other media/notes/visits/ratings; retry worker cleanup and delayed derivative completion cannot resurrect content. Test actual warm-cache delivery paths.
- [ ] **T15 (P1, human: ~24–40h / agent: ~12–24h)** — recap-conversation — Complete rich recap, publication, discussion and return invitation. Lane B; depends on T12, T13, T14.
  - Surfaced by: Product D1/D3/D5/D26–D28/D33; D7/D16; T3/T4; PF1/PF3.
  - Files: `Wander/Features/Events/EventRecapView.swift`, `Wander/Services/Events/EventConversationRepository.swift`, `events-web/src/guest/RecapPreview.tsx`, `events-web/src/console/RecapEditor.tsx`, `supabase/migrations/YYYYMMDDHHMMSS_events_recap_conversation.sql`, `supabase/tests/events_conversation.sql`, `WanderUITests/Events/EventRecapTests.swift`
  - Verify: Build event-focused cover, comments near top, familiar comment/reply/like behavior, photos/videos plus, personal check-ins and upper-right share. Keep shared recap conversation distinct from personal-post engagement.; Publish through Team admin console before queuing eligible admitted-guest invitations in T12; no-show and preview-only callers receive no protected metadata/content behind blur.; Return from app deletion/reinstall recovers the same admission/completion; deleted personal post does not recreate it. Share uses canonical event link and only permitted preview, with no automatic external posting.; Test publication failure, repeated revision, stale/current access, source deletion, own/other-author actions and accessible preview/locked content; define only agreed editing/reporting behavior.
- [ ] **T16 (P2, human: ~24–40h / agent: ~12–24h)** — map-place-feed — Integrate event pins and inline place/feed history without regressions. Lane B; depends on T07, T13.
  - Surfaced by: D2/D16; product D4/D9–D13/D35; T3; PF1/PF4; latest-main drift f8493c0 adds REC-494 Feed grouping (#632) and REC-498 profile header (#636).
  - Files: `Wander/Services/Events/EventMapProjection.swift`, `Wander/Features/Map/MapScreen.swift`, `Wander/Features/Map/PlaceProfileMapSurface.swift`, `Wander/Services/FeedModels.swift`, `Wander/Features/Feed/FeedActivityDisclosure.swift`, `Wander/Services/Events/EventHistoryAdapter.swift`, `WanderTests/Events/EventMapPresentationTests.swift`, `supabase/tests/events_map_history.sql`
  - Verify: Implement permitted Featured/You/Friends event projections under console styling window, approximate private-home geometry and authoritative attendance; use coalesced viewport/page summaries rather than per-pin detail hydration.; Pin reveals collapsed event card over normal map with event at place hierarchy; expand event then canonical place. Add inline paged place event history and event-labeled feed/profile posts with audience eye.; Preserve current ordinary map caches/cancellation and stable selection, old ratings/notes/audiences/save intent and one event visit. At most one integrator edits shared MapScreen/store/feed seam at a time.; Against latest f8493c0-or-newer main, verify current display-only Feed grouping retains original activity/engagement/route IDs; distinct event check-ins are neither merged nor duplicated. Retain new profile-photo-header behavior.; Build summary/history/map integration against media manifests while T14 proceeds; complete actual-media permission integration before T17/T18.
- [ ] **T17 (P1, human: ~20–32h / agent: ~10–20h)** — protected-integration — Prove current access across every projection and cache. Lane A; depends on T09, T11, T14, T15, T16.
  - Surfaced by: T4; D7/D9/D13 protected-data rules; TP01/TP02/TP03; TR02/TR03/TR04.
  - Files: `supabase/tests/events_recap_access.sql`, `supabase/tests/events_home_projections.sql`, `WanderTests/Events/EventProtectedCacheTests.swift`, `events-web/tests/guest/recap-privacy.spec.ts`, `events-web/tests/guest/home-privacy.spec.ts`, `scripts/events/media-access-smoke.mjs`
  - Verify: Run access matrix across booking/admission/completion/post audience/home window/independent rights: direct SQL/RPC, raw JSON, DOM/native accessibility, media metadata, previews/calendar/nav and actual bytes.; Warm browser/CDN/native memory/disk caches, then revoke/remove/expire/switch account while requests run; no stale result may reauthorize or repopulate a protected cache.; Check D13 relative-window recalculation versus absolute overrides, independent rights and D9 offline operations before/after reconciliation. Preserve ordinary history and retained completion after deletion.; Exercise latest schema grants/RLS and real authenticated transport, including denied versus expired auth; privacy-safe logs and analytics are verified rather than presumed.
- [ ] **T18 (P1, human: ~32–48h / agent: ~20–32h)** — joined-acceptance — Run complete integrated journeys and ordinary-app regressions. Lane A; depends on T10, T11, T12, T15, T16, T17.
  - Surfaced by: T1–T4; all 121 acceptance mappings plus 24 technical risks; D8 joined-release checkpoint.
  - Files: `scripts/events/integrated-journey.mjs`, `events-web/tests/journeys/events-integrated.spec.ts`, `WanderUITests/Events/EventsIntegratedJourneyTests.swift`, `docs/testing/events-device-matrix.md`, `docs/testing/astir-events-acceptance-results.md`
  - Verify: Execute E01–E12 continuously with same canonical account/event/booking/admission/completion/visit/media IDs, real app/Clip/browser/console APIs and workers; seed only starting state, not intermediate success.; Run full mapped native/SQL/browser/worker suites including controlled multi-session concurrency and ordinary check-in/save/list/rating/visibility/block/history/widget/auth/onboarding regressions against current main.; Record exact fixture/build/platform/time, server assertions, outbox/provider evidence and passed/failed/blocked/skipped status per case variant. Screenshots and stitched mocks cannot constitute an integrated pass.; Add new implementation branches to coverage map and resolve every high-risk approved failure; proposed details only become assertions after their recorded decision.
- [ ] **T19 (P1, human: ~20–32h / agent: ~10–20h)** — performance-validation — Measure entry, contention, delivery, media/map and offline scaling. Lane B; depends on T11, T12, T14, T16, T17.
  - Surfaced by: PF1–PF5; T1/T4; D18 source-review hypotheses, not measured SLOs.
  - Files: `WanderTests/Events/EventLoadingPerformanceTests.swift`, `WanderTests/Events/EventMapPerformanceTests.swift`, `WanderUITests/Events/EventMediaPerformanceUITests.swift`, `scripts/events/performance-load.mjs`, `events-web/tests/console/offline-performance.spec.ts`, `docs/testing/astir-events-performance.md`
  - Verify: Calibrate foundation baseline and run controlled 30/300/3000 records, mixed large media and existing 1500-pin map fixtures; report exact environment and cold/warm state.; Measure request counts/query plans, lock wait separately from operation latency, queue oldest age and due-to-provider intervals, memory/transfer/player high-water marks and durable offline lookup/write time.; Retain current authorization, no overselling and one canonical visit at every size; provider calls never hold allocation locks, page work stays bounded, roster readiness requires complete data.; Compare Events off/on on the same actual device/dataset; record p50/p95/failure rates with timeouts retained. Tune simple indexes/pages/concurrency from evidence without imposing new guest/upload caps.
- [ ] **T20 (P1, human: ~20–36h / agent: ~14–28h)** — distribution-provider-proof — Verify exact release artifacts, public invocation and real provider delivery. Lane A; depends on T18, T19.
  - Surfaced by: T2/T4; TN03/TR06; app, Clip, browser, console and backend are one compatibility gate.
  - Files: `docs/testing/astir-events-release-compatibility.md`, `docs/testing/events-device-matrix.md`, `AstirEventsClip/Resources/AstirEventsClip.entitlements`, `events-web/public/.well-known/apple-app-site-association`, `scripts/events/release-compatibility.mjs`
  - Verify: Verify final app/Clip identifiers, association domain, entitlements, signed dependencies, supported OS, provider environments and compatible contract versions; release app and Clip as coordinated artifacts.; Exercise actual public invitation invocation on supported physical devices separately from local/TestFlight invocation; fresh install/icon launch, expired session, original Apple/Google recovery and browser fallback preserve one booking.; Use controlled test numbers/devices for actual current-number verification, event SMS and APNs delivery; record provider acceptance/receipt distinctions, denied notifications and opt-out.; Validate real staff camera/browser offline lifecycle, privacy controls and cleanup on the exact target hardware. Record store/provider/domain processing waits separately from active effort.
- [ ] **T21 (P1, human: ~12–20h / agent: ~6–14h)** — release-controls — Rehearse additive rollout, feature controls and non-destructive rollback. Lane B; depends on T05, T17.
  - Surfaced by: D2/D7/D9/D16; TR02/TR04; compatible distribution and retained bookings/history/door work.
  - Files: `Wander/Services/Events/EventFeatureConfiguration.swift`, `supabase/tests/events_launch_permissions.sql`, `events-web/src/console/LaunchConfiguration.tsx`, `events-web/tests/console/launch-configuration.spec.ts`, `scripts/events/release-compatibility.mjs`, `docs/testing/astir-events-rollout-rollback.md`
  - Verify: Define staged additive schema/functions/web/app/Clip deployment and capability compatibility; separately control public discovery/new RSVP/sending rather than assuming UI visibility grants authorization.; Rehearse older app/new backend and newer app/preactivation. Unknown capabilities fail safely; safe guest management/ticket/console routes for existing commitments remain considered when disabling new acquisition.; Use forward repair/feature disable rather than destructive rollback of live bookings, admissions, completion/history or offline queues. Pause unnecessary sends while retaining truthful delivery state; rollback cannot silently discard pending staff work.; Name rollout owner, metrics/alerts and specific rollback triggers, restore steps and evidence; migration/project files have one editor at a time and feature tasks use separate short-lived worktrees.
- [ ] **T22 (P1, human: ~8–16h / agent: ~6–12h)** — release-handoff — Close release evidence and run the controlled Events rollout. Lane joined; depends on T20, T21.
  - Surfaced by: Full D1 scope; D8 two-lane integration; D19 final planning handoff does not authorize production implementation.
  - Files: `docs/testing/astir-events-acceptance-results.md`, `docs/testing/astir-events-rollout-rollback.md`, `docs/testing/astir-events-release-compatibility.md`, `docs/decisions.md`, `docs/open-questions.md`
  - Verify: Review exact release revisions and all agreed acceptance/device/provider/performance results; explicitly list blocked/skipped/unimplemented cases and unresolved proposed details instead of claiming zero defects.; Resolve release-blocking product details with concrete reviewable interactions; deferred reconnection/expanded privacy, extra push cadence, second-degree Friends and personal-composer video do not enter by implication.; After separately authorized publication/activation, run controlled real-event smoke and monitor current booking/admission/media/delivery/queue health; exercise rollback triggers without exposing private guest data.; Update actual issue/PR/release handoff, compatible artifact versions, owners and operational access; measure completed work rather than presenting this planning estimate as a delivery date.

## Completion summary

| Review item | Result |
| --- | --- |
| Scope challenge | D1A accepted the full experience; no further scope reduction |
| Architecture | 4 source integration findings F1–F4; selected decisions and detailed contracts recorded |
| Code quality | 2 findings CQ1–CQ2; focused components and typed/current-state outcomes specified |
| Tests | Flow diagram and all 121 acceptance scenarios mapped; 24 added technical risk groups. T1–T4 are summaries of those risks, not extra counts |
| Performance | 5 groups PF1–PF5 with source evidence and a provisional measurement plan |
| Total review items | 35 = 4 + 2 + 24 + 5; planning findings/risk groups, not 35 reproduced production bugs |
| Scope/existing code | NOT in scope and What already exists documented; selected reuse retains required integration changes |
| TODO additions | 0 new candidates; no new deferral invented |
| Failure modes | 0 unmapped silent-failure planning gaps; runtime handlers/tests remain unimplemented |
| Outside voice | Skipped under the running-under-Codex rule; collaborator source checks are not an outside-model review |
| Parallelization | 2 work lanes, 4 useful overlap windows: foundations, journeys, joined-test/performance work, release preparation; shared contract/integration gates remain sequential |
| Lake Score | Not numerically reconstructed: the surviving record establishes full scope D1A, but not a comparable scored denominator for all historical recommendations |
| Unresolved choices | 9 grouped product/design decisions; each group's constituent clauses and affected tasks are listed separately |
| Runtime validation | No Events app/Clip build, application test, benchmark, hosted change or public-provider feasibility pass performed |

The original app-source review is pinned to `f8d258e869503a28d70518a050dff36a344134c6`, including the canonical-history repair at `a0117cff6ed55a967f4212b45bb28d8c39ca1488`. Main was refreshed through `f8493c0` before packaging: REC-494 display grouping and REC-498 profile-header behavior were reviewed for drift. The original activity-ID regression is incorporated in TR02 and the history tasks. Prior ordinary-history repairs warrant real regression evidence, not relying on Events-only mocks.

Approval checkpoints D15A/D17A/D18A/D19A approved continuing and completing the review; they are not approvals of unresolved clauses or evidence that future tests pass. Product/design changes from Joe and Ryan's ongoing flowchart walkthrough should update the affected contract, task and test assertion together. The remaining choices can be reviewed as one coherent product pass, rather than nineteen more technical checkpoints.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
| --- | --- | --- | --- | --- | --- |
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 fresh records on this branch | Not run in this engineering pass | Existing product direction preserved |
| Codex Review | Outside-model plan review | Independent second opinion | 0 | Skipped under Codex | No cross-model validation claimed |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | ISSUES OPEN (PLAN) | 35 review items, 0 unmapped critical planning gaps, 9 decision groups |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 fresh records on this branch | Existing design artifacts; ongoing user review | Open layouts/policies preserved, not rescored |
| DX Review | `/plan-devex-review` | Developer experience | 0 | Not run | No public developer platform selected |

**VERDICT:** Conditional engineering handoff complete. Full-product implementation/release is **NOT CLEARED**; affected product choices and actual implementation proofs remain. Eng review required before full release clearance. Publishing this documentation does not assert those gates passed.

**UNRESOLVED DECISIONS:**
- OD01 — Registration-rule changes, offer deadlines versus closing, quota/mode edits and active-queue semantics.
- OD02 — Cancellation, venue changes and completed-event edits; outage recovery does not authorize unpublishing.
- OD03 — Participation defaults, plus-ones/named bookings, re-entry/exceptions and pending withdrawal.
- OD04 — Reminder/download prominence, channel mix and late/rescheduled message behavior.
- OD05 — Preview/teaser payloads, private-home presentation/consent controls and external sharing.
- OD06 — Own-video in personal posts, public/private editing interactions and remaining discussion controls.
- OD07 — Second-degree Friends, pin/motion treatment and overlapping/promotion windows.
- OD08 — Post-ticket general onboarding, profile discovery and optional-photo presentation.
- OD09 — Exact Events navigation/grouping, event bookmarking and remaining calendar/icon actions.
