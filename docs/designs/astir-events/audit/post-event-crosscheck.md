# Post-event, place/map, home and audience fidelity audit

Historical 76-screen snapshot. See [the current requirement audit](requirements.md) for corrected findings, remaining proposals and current verification.
September 14, 2026. This is an audit of the current 76-screen review artifact, not an application security test or permission to implement. Only this audit file was changed.

The main product decisions are substantially recorded, but the visual board is **not yet a faithful complete walkthrough**. Its most consequential conflicts are the missing event-to-place route, personal-post deletion returning to a screen that still shows the deleted post, and ended-event links returning to a future confirmed event. Several approved requirements survive only in notes outside the phones.

## Evidence and method

- User evidence: [discussion record](discussion-evidence.json), especially M017–M024, M038, M045 and M047; original transcript (local authoring source; authority retained in the requirements ledger); post-event answer transcript (local authoring source; authority retained in the requirements ledger).
- Product authority: [working product record](../working-product-record.md) and [product draft](../product-spec-draft.md). D1–D6 and D8–D35 are approved at their recorded scope. Draft defaults and designs are proposals. D7 and expanded privacy controls remain deferred.
- Actual generated data: flow-model.json (local authoring source; authority retained in the requirements ledger). SHA-256 at audit: 809389875769009f4dd3fa4f493b36759f8aaffa8ce501c320444a199cf95f2c. Its parsed data exactly matched the payload embedded in the generated HTML.
- Actual display logic: build-flow-wireframes.py (local authoring reference; see the requirements ledger), including renderer branches and CTA destinations. Findings below distinguish explicit conflicts, omitted paths, and unapproved proposals. I did not rerun the builder or claim a fresh screenshot-based visual test.
- The board expressly says actions are illustrative. An external action being simulated is not itself a defect. A button going to the wrong existing screen, or an essential flow having no depicted destination, is a fidelity gap in the requested whole-flow review.

## Required corrections

### PE01 — Eye audience indicator disappears on the normal personal post

**Approved requirement.** D9C and M022 request the small eye icon for personal event check-ins; D28 explicitly retains it. See [record lines 98–106](../working-product-record.md).

**Actual.** after_post (local authoring source; authority retained in the requirements ledger) contains the words Everyone in Astir, but the post renderer (local authoring reference; see the requirements ledger) renders no eye. The recap's personal check-in row also omits it, while the initial composer, failed-upload composer, and removed-photo post do render it.

**Correction.** Render the same eye plus explicit audience label on every personal-post presentation. Make the recap's personal-post preview identifiable as an authored event check-in, with event/date and the applicable note/media, instead of a generic Your check-in row. This requires no new privacy settings or audience selector.

### PE02 — The recap does not visually establish the required mixed photo/video gallery

**Approved requirement.** The post-event transcript expressly calls for first-party photos/videos and third-party photos/videos; [draft line 88](../product-spec-draft.md) preserves both.

**Actual.** The recap renderer (local authoring reference; see the requirements ledger) labels a section Photos & videos, then calls pics() (local authoring reference; see the requirements ledger), which renders four generic photo placeholders. None has a video affordance or an Astir/attendee source. The upload alternative shows one attendee video, but gallery-result (local authoring reference; see the requirements ledger) again renders the unchanged four photos plus a text row mentioning the video. There is no shared-gallery video viewing state or Astir-provided video example.

**Correction.** Give recap/gallery items explicit illustrative media types and sources, render both Astir and attendee photos/videos, and depict opening a video. Source labeling is a design proposal; the presence of both sources and media types is approved. Keep personal-composer video support labeled proposed—it was not approved by the shared-gallery decision.

### PE03 — Selecting two photos produces a post with one unrelated placeholder

**Approved requirement.** D6 adds selected event photos to the same existing personal check-in and place visit.

**Actual.** after_gallery (local authoring source; authority retained in the requirements ledger) says 2 photos selected and Add 2 photos. The renderer displays four unmarked image tiles, then three separate text rows naming selections. Its next screen, after_post, says two photos in model items, but the post renderer ignores those items and shows a single Photo from the night tile.

**Correction.** Visually mark the actual selected thumbnails and carry those same two thumbnails into the updated post. Show the preserved event identity and note. Do not introduce a reuse explanation or a second check-in submission.

### PE04 — Comments are near the top, but the conversation flow stops at labels

**Approved requirement.** D1 wants prominent comments/social activity and personal check-ins below them. Text comments/replies/likes/reporting are concrete **proposed** interaction defaults in [draft line 123](../product-spec-draft.md).

**Actual.** The conversation is correctly near the top. However, after_recap (local authoring source; authority retained in the requirements ledger) has a Leave a comment CTA without a destination; the renderer (local authoring reference; see the requirements ledger) displays Comment · Reply · Like as plain text. There is no comment-entry/sent state, reply context, liked state, or reporting/removal route. The renderer also replaces the model's Alex/Maya comments with unrelated hardcoded Rachel/Jordan comments.

**Correction.** Draw the minimum proposed conversation route and retain coherent sample content across it. Keep interaction details visibly proposed. Do not add reconnection or missed-connections UI.

### PE05 — The required pin → event → place chain is broken

**Approved requirement.** D12A explicitly selects special pin → event view → clear route to the place profile. Each event has exactly one canonical place. See [draft lines 23 and 100](../product-spec-draft.md).

**Actual.** map_special_event (local authoring source; authority retained in the requirements ledger) can open after_recap or go directly to map_place_history. After opening the event recap, there is **no place link**: its actions go to photo selection, gallery upload, and an unlinked comment action. The venue rows in normal/removed-photo posts are plain divs, not routes. Place-history event rows are also static, although the bottom CTA opens Vinyl Sound Bath.

**Correction.** Put a clear Studio Thirty place link in the applicable event view and wire it to the canonical place. Keep the event route as the special pin's primary behavior. Make the place's events genuine destinations, including the second sample event, rather than only descriptive rows. Avoid using an alternative direct map-to-place shortcut as the sole fulfillment of event-to-place navigation.

### PE06 — Ordinary place history still renders the special event pin; discovery is shown only as an attendee memory

**Approved requirement.** D10 is an upcoming/recent discovery signal for all permitted viewers, not only completed attendees; it is temporary. Ordinary place history remains after it ends. Post-event transcript line 3 (local authoring source; authority retained in the requirements ledger) makes the visual distinction explicit.

**Actual.** map() (local authoring reference; see the requirements ledger) draws the same E marker and Vinyl Sound Bath label for every nonprivate map, including map_place_history (local authoring source; authority retained in the requirements ledger). The sole special-pin screen says Your event is now part of your place history and Been; its Open event action always opens an unlocked attendee recap.

**Correction.** Add an ordinary-pin/expired-styling example that still exposes event history. Show the same special treatment for a permitted nonattendee/upcoming viewer, with the correct event detail or locked preview destination. The existing completed-attendee route is valid for that persona, but cannot stand in for all viewers. Keep the seven-day window and event precedence labeled proposed, as in draft line 104.

### PE07 — Post-event return links reset the event to tomorrow

**Approved/draft requirement.** Ended-event states must preserve their lifecycle, and historical completion retains recap access. Proposed entry routing is laid out in [draft lines 131–141](../product-spec-draft.md).

**Actual.** recap_unpublished (local authoring source; authority retained in the requirements ledger) says Vinyl Sound Bath has ended, but View event opens confirmed-detail, which offers Show ticket, guest list and Cancel RSVP. Its Back to Events action and other post-event returns open the same events-list (local authoring source; authority retained in the requirements ledger) whose renderer says Tomorrow · 7 PM for Vinyl Sound Bath. Past events has no destination. Both buttons in after_text always open the composer, with no completed-attendee return variant.

**Correction.** Provide a past/ended Events state and ended event detail, and route post-event returns there. Show first-time eligible return → composer and historical-completion return → recap. Keep repeat actions from implying another required post/visit. This can be explicit storyboard variants; the board need not implement real account state.

### PE08 — Deleting a personal post has no entry flow and returns to the deleted post

**Approved requirement.** D33 removes the personal post and its event visit while preserving historical completion and valid recap access. Independent visits, ratings and explicit saves remain intact. See [record line 316](../working-product-record.md).

**Actual.** recap_removal_results (local authoring source; authority retained in the requirements ledger) correctly states deletion and retained access, but no personal-post screen offers a delete/manage route into it. Open recap goes to after_recap, which unconditionally renders Your check-in and Add to your check-in. Following the board onward restores the original post and the event-derived Been state.

**Correction.** Add a proposed personal-post management/delete route and a retained-access recap variant with the deleted personal card absent. Show place state derived from whatever independent history remains; do not restore this event visit. Do not silently choose behavior for creating another post after deletion—label any such interaction as proposed.

### PE09 — Source-photo removal is described, but its source-gallery consequence is not shown

**Approved requirement.** D32 removes the source photo from the gallery and every referencing personal post while preserving other content and visits. D27 separately allows uploader removal and Astir moderation.

**Actual.** gallery-manage (local authoring source; authority retained in the requirements ledger) sends Remove photo directly to recap_photo_removed, an illustrative personal-post result. The route never shows the updated shared gallery, does not identify which of the earlier selected photos was removed, and returns to the unchanged generic gallery/recap. Astir moderation exists only in notes; there is no operator moderation screen. The removal preview itself correctly keeps a note, remaining photo, audience eye and Been label.

**Correction.** Give the selected/source/removed photo consistent identity, show it absent from the shared gallery and referenced post, and keep those changed variants consistent on return. Draw the minimal operator remove result alongside uploader removal. Do not add a reuse explainer, permission prompt, or automatic personal-post deletion.

### PE10 — Home snapshots lack the event/place identity and onward routes needed to review canonical-place integration

**Approved requirement.** D8/D12 keep the home place discoverable approximately and connected to its event. D13/D35 define the configurable confirmed-guest address window. Every event still has exactly one place.

**Actual.** home-before, home-revealed and home-expired (local authoring source; authority retained in the requirements ledger) correctly show approximate → exact-address placeholder → approximate states. They never name the associated event. Back to event, Directions, View event memories and Back to map have no destinations. The main Vinyl Sound Bath consistently belongs to public Studio Thirty; the home chapter therefore does not establish which distinct event/canonical home is being followed.

**Correction.** Name a separate illustrative home event and its one canonical home, carry both identities through event/place/history views, and connect the existing home actions. Label the exact-address example as invented; an actual residential address is unnecessary. Depict confirmed-before-reveal, eligible-window and expired destinations without accidentally returning to the public-venue example.

### PE11 — Home eligibility differences and cross-surface restrictions are largely notes, not visible alternatives

**Approved requirement.** Confirmed guests alone receive the event-provided exact address within the effective window; late confirmation during that window grants immediate access; expiry returns event/place/navigation to approximate. Public personal posts and discovery do not grant address access. [Draft lines 68–72](../product-spec-draft.md).

**Actual.** The home chapter contains one before/eligible/after sequence. It does not show the simultaneous nonconfirmed viewer, late-confirmation transition, private-home personal post/place-history presentation, or event-provided Directions becoming unavailable after expiry. The exact window's end appears only in the outside note/console row. Canceled/revoked booking consequences are proposed in the draft and mentioned in cancellation notes, but no private-home cancellation variant visualizes them.

**Correction.** Add paired eligible/ineligible home event/place views and a late-confirmation return, plus an expired navigation result. Carry approximate location into the home personal post/history. If depicting cancellation/revocation behavior, label those exact operational consequences proposed; do not expand this into the deferred privacy product. The current approximate SVG itself does not expose an exact house marker.

### PE12 — Console controls and home consent are listed but cannot be reviewed as controls

**Approved requirement.** D11 requires pin on/off, display start/end, preset and preview; D13/D35 require adjustable address reveal/expiry; home use requires resident/owner/renter consent. D26 requires publication before attendee invitations.

**Actual.** console-publish (local authoring source; authority retained in the requirements ledger) renders these as static rows. Preview changes has no destination. console-event (local authoring source; authority retained in the requirements ledger) mentions recording home consent only outside the operator screen. console-preview lists Guest views without rendering them. Recap publication has a happy path and queued-invitation result, but no publication failure or failed-invitation retry variant despite their proposed draft treatment.

**Correction.** Draw compact editable control examples and previews for the selected map/home settings, and a visible home-consent field/status before publication. Keep exact consent capture and draft/publish mechanics proposed. Add proposed publication-failed versus published/invitation-failed states so operators can see that the latter does not retract the recap or repeat successful invitations. Do not invent a larger admin product.

### PE13 — Missing post-event correction, revocation, temporary failure and editing paths

**Authority.** D5 approves staff correction and the admission gate. [Draft lines 115–123 and 135–141](../product-spec-draft.md) propose the concrete retry/edit/return behavior.

**Actual.** recap_missing_admission ends at an unlinked Ask Astir to check button. There is no staff-corrected → composer route, corrected guest with historical completion → recap route, revoked-admission → locked preview/help state, or published-recap-unavailable retry state. The upload-error screen is useful but is not a general failed check-in/unknown-submission result. Personal note/media editing and separate private-feedback editing also have no depicted route; the only edit example is adding gallery photos.

**Correction.** Add the missing bounded alternate states with approval labels matching their authority. A staff correction must not automatically create the attendee's post/visit. Revocation must not silently erase unrelated history or imply automatic post moderation. Preserve the same completion on retry. Keep private-feedback editing distinct from the public card.

### PE14 — Proposed behavior is incorrectly given the approved-behavior badge

**Actual mechanism.** screen() defaults (local authoring reference; see the requirements ledger) supply Approved behavior; proposed layout. The renderer displays that string per screen; a group's proposed summary does not override it.

**Concrete examples in this audit's scope:**

- console-preview says its explicit publishing action is proposed in its note, but shows Approved behavior. Console event draft/publish behavior is proposed in draft defaults 9/19.
- location-primer, location-denied and notification-primer appear under a Proposed contextual onboarding summary but carry the approved-behavior label; exact contextual sequencing is draft default 13.
- rsvp-canceled and event-canceled include proposed precise-address/rebooking/cancellation consequences under the approved label. Self-cancellation is approved; every stated consequence is not thereby approved.
- Events placement/past navigation are proposed; the events-list screen should distinguish those from the approved confirmed-first list.

**Correction.** Separate approved requirements from proposed operating behavior per screen, rather than treating every proposal as only layout. The existing labels on map_recommendations, recap_unpublished and recap_upload_error demonstrate the available Proposed interaction pattern. Approval of D35 or authorization to run design review did not approve all draft defaults.

### PE15 — Empty Events adds a city waitlist that was explicitly simplified away

**Requirement.** [Record line 86](../working-product-record.md) says keep coming soon simple; the earlier waitlist mention was simplified. D21's full-event waitlist is separate. [Draft line 126](../product-spec-draft.md) explicitly says no extra onboarding task.

**Actual.** events-empty (local authoring source; authority retained in the requirements ledger) asks users to join a list and has Join the event waitlist as primary, with Approved behavior; proposed layout. Calling it a city-interest action in the note does not establish approval. Its Explore the map destination also says Near Studio Thirty despite this empty state not establishing any event venue context.

**Correction.** Restore the simple Events coming soon state and a context-appropriate ordinary map destination. Keep the approved waitlist flow for an actual full event.

## Requirements currently represented correctly

- Explicit Check in is required, every composer field may be empty, private stars start unselected, and private feedback is visually separate. Submission opens the recap rather than the map. No public venue rating is rendered.
- The initial composer offers own photos; protected-gallery selection occurs only after the recap in the main sequence. No forbidden reuse explanation, disclosure or approval prompt was found.
- Comments are near the top of the attendee recap. The nonattendee screen uses empty blurred placeholders rather than protected text, and its copy does not imply attending the next event opens this past recap. It does not invent approved avatar visibility.
- The model records the Everyone in Astir default, same logical event/place visit, independent-history preservation, immediate eligible uploads, source-removal propagation, and post-deletion access retention. Findings above concern missing or contradictory visual execution of those recorded rules.
- Approximate home maps avoid an exact pin; reveal and expiry defaults are correct in the model/console notes. The public-venue main journey consistently uses Studio Thirty; no multi-place event is explicitly asserted. The home alternative lacks enough identity to verify its canonical relationship.
- Console recap publication precedes invitations; the success screen accurately says invitations queued, not delivered. Discovery/guest-list/location/recap permissions are distinct in the product record.
- No deferred reconnection or expanded profile/check-in privacy controls were silently added to the board.

## Suggested repair order

1. Repair the lifecycle and access destinations, deletion persistence, canonical event-to-place route, and home identity/window variants.
2. Render the required personal-card eye, selected media, mixed source photo/video recap, and actual conversation/post-management alternatives.
3. Add the compact operator previews/recovery states, correct approval labels, and remove the city-waitlist drift.
4. Rebuild once, then verify rendered screenshots and every defined CTA against the corrected model. Keep acceptance of proposed defaults separate from approval of the visual artifact.
