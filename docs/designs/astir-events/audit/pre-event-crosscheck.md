# Pre-event and console requirement crosscheck

Historical 76-screen snapshot. See [the current requirement audit](requirements.md) for corrected findings, remaining proposals and current verification.
Audit date: September 14, 2026. Scope: RSVP, sign-in, phone verification, texts/download timing, onboarding return, cancellation, waitlist, admission, and the internal console. This is an internal audit, not new product approval.

Inspected the working product record, product draft, builder, recovery-screen data, generated `flow-model.json`, generated HTML's embedded model, renderer, and navigation handlers. The embedded HTML model exactly matches `flow-model.json`: 76 screens, 16 chapters. This pass inspected rendered-content generation and actual navigation targets in source; it did not run a visual browser session. Root is separately validating the full artifact and reconstructing primary discussion evidence.

## What is now faithful

The September 14 correction is present in the generated artifact. Screens 3–5 are Apple/Google sign-in, name/phone, and SMS verification in the no-install RSVP route. Screen 6 confirms the reservation; screens 7–9 show texts and ongoing no-app reservation access. Screen 10 is an explicit later entry-QR action; screen 11 is the App Store handoff. There is no immediate Get Astir CTA on RSVP confirmation. The two provider buttons both route to the phone screen. The future-event checkbox renders unchecked.

The QR-failure renderer has no QR. Expired offers have no Accept button. Duplicate admission renders the earlier entry rather than a fresh scan frame. Staff manual admission is disabled until both identity and installed-app checkboxes are checked. Those are meaningful fixes, but they do not establish complete flow fidelity.

## Concrete corrections required

### PRE-F01 — Preserve browser and installed-app context through navigation

The new surface badges are fixed per screen, while multiple different surfaces link to those same screens. This creates contradictory journeys:

- **31 Browser fallback → 3 Apple/Google sign-up:** `browserfallback.next = rsvp-auth`, but screen 3 explicitly says App Clip / full app not installed. The browser route visibly becomes the Clip route even though fallback is needed because the Clip did not open.
- **41 Wrong account → 3 → 4 → 5 → 6:** Switch account in the installed app goes to the no-install new-RSVP route, then phone verification and a fresh confirmation. This contradicts the proposed recovery rule that the original reservation is restored without a replacement booking or redundant identity steps.
- **19 Installed event → 55 guest list → 9 no-app event:** Back from the shared guest-list frame always exits to the Clip-labeled state.
- **56 Keep my RSVP → 19:** this shared cancellation frame always returns to the installed app, including a browser/Clip guest.
- **57 RSVP canceled / 60 event canceled → 18 Events:** Browse events sends a no-app guest straight to the installed app without any explicit handoff.
- **21 Staff scanner → 19 guest event:** the staff Event details button opens the guest's installed-app view; this is not a documented operator preview.

Source: builder lines 78–111, 123–126, 139–146, 167–216 and navigation handler lines 285–292. Channel assignment checks `clip_ids` before the screen's Browser surface, so recovery items initially authored as Browser are relabeled App Clip.

Correction: represent the surface and actor as retained context, or make separately named browser/Clip/app variants. Installed account recovery must return to booking recovery, not fresh RSVP. Shared guest-list/cancel actions must return to their originating surface. Mark reviewer-only jumps across guest/staff surfaces as handoffs, not product buttons that change the actor.

### PRE-F02 — No-app confirmed guests have no cancellation route

Approved D24 allows self-cancellation before event start, and D14 / the September 14 clarification retain equivalent no-install RSVP management. Screen 9 `noapp-confirmed-detail` has only View guest list and Get entry QR. Cancel RSVP exists solely on screen 19 in the installed app. Screen 56 is labeled shared but is reachable only from that installed detail and the reschedule alternative.

Source: builder lines 139–141 and 180; working record lines 68, 74, 87.

Correction: add Cancel RSVP to confirmed reservation management on every surface, with surface-preserving confirmation, canceled state, and rebooking route. Do not make download a practical prerequisite for cancellation.

### PRE-F03 — Stop displaying blanket “Approved behavior” on proposed operating rules

The builder's default `rule='Approved behavior; proposed layout'` and later `setdefault` automatically label any unlabeled frame approved. Group-level `proposed: true` does not appear in the renderer. Several frames have a note explicitly saying proposed but a higher-level approval badge saying approved:

- 12 `recover-booking`: skipping general onboarding is proposed in draft §8.13.
- 58 `events-empty`: city-level waitlist CTA was mentioned then simplified; record line 86 says not to silently add a full waitlist product. It must be separately proposed or use the approved simple coming-soon state.
- 60 `event-canceled`: guest presentation, invalidation, reminder and address consequences are draft §8.5 proposals, not D24 self-cancellation approval.
- 67–69 contextual permission screens: full sequence is proposed in draft §8.13.
- 70 / 73 / 74 console creation/publish success: draft validation and explicit event publication semantics are draft §8.19 proposals.
- 71 `console-guests`: offer holding a seat is a proposed capacity default even though staff selection and guest acceptance are approved.
- 76 `console-recap-live`: queueing/retry/delivery behavior is proposed, even though publish-before-invite is approved.

The product draft itself labels the “never later than registration closing” offer expiry rule **Approved** in §4, while the working record says expiry/registration cutoffs still require specification (record lines 67, 290), and the next draft paragraph proposes the registration cutoff. Split that sentence's approval status.

Source: builder lines 8–11, 58–62, 127, 134–137, 150, 153–157, 197–199, 285; draft lines 108–129; working record lines 67, 86, 290.

Correction: require an explicit approval-source field per behavior. Use “Approved requirements · proposed interaction” for mixed frames, and state exactly what is proposed. Never infer approval from missing metadata. Keep A/B onboarding choice unresolved.

### PRE-F04 — Verification and access-code recovery are written in notes but not shown as flows

Screen 5 always navigates to successful confirmation; Change number is a generic demo toast. Its 60-second resend label is a proposed default presented without an adjacent proposal label. There are no screens for incorrect/expired SMS code, resend, edited number requiring verification, pending verification, or interrupted verification. Screen 32 is an **event access-code** error and does not cover SMS-code errors. No normal required-access-code screen precedes confirmation.

Source: builder lines 18–20, 246, 261 and the screen inventory; draft §8.2 / §8.18; working record lines 58, 61, 273.

Correction: show distinct verification and invitation-code branches. A successful SMS verification must still route through capacity/approval evaluation. Do not allow “code verified” to visually imply every guest is confirmed. Keep proposed countdown/placement explicit.

### PRE-F05 — RSVP alternatives are disconnected from the main RSVP decision

The main route always goes from SMS verification to confirmed RSVP. Manual approval, waitlist and offers exist as a row of alternatives, but the point at which the journey branches is not displayed. There is no depicted full-event RSVP/Join waitlist action, approval request action/result, operator approval/rejection result, waitlist offer text, offer decline outcome, or already-accepted-offer outcome. A separate expired state exists, but the offer acceptance frame unconditionally navigates to confirmation even in the wrong-account/expired/replayed cases.

Source: builder line 20 and links 87–88; recovery JSON `rsvp-alternatives`; draft §4 / §8.4 / §8.11 / §8.16; D21–D23 and D31 in the record.

Correction: add a labeled decision junction after verified identity/access eligibility: available + auto approval → confirmed; manual review → pending; full/protected released space → waitlist. Keep staff selection → offer → explicit acceptance visually separate from manual approval. Show proposed handling for decline/expiry/replay rather than silently treating it as approved.

### PRE-F06 — Cancellation examples cover the outcome but omit key boundaries

There is no visible event-start cutoff state where cancellation is unavailable, cancellation failure with reservation retained, or confirmation that a canceled guest stops normal reminders. The existing canceled screen correctly has no ticket, but no path demonstrates that released seats go to protected staff waitlist selection while a waitlist is active. The post-start cutoff and staff-controlled released-space behavior are approved; exact failure/message handling remains proposed.

Source: builder lines 123–127; record lines 68 and 291; draft §8.3 / §8.10–11.

Correction: show before-start cancellation, after-start availability, and the guest/operator consequences. Keep the published event's own cancel/reschedule flow separate from a guest canceling their RSVP.

### PRE-F07 — Door lookup can visually turn an invalid ticket into a valid booking without a matching step

Screen 48's “Ticket invalid” Find guest action directly opens screen 45, already populated with Rachel's valid confirmed booking. The two checkboxes are useful, but the transition does not show an actual match/no-match result. Screen 45's Back to guest search button is a demo; there is no search, ambiguous result, ineligible result, or unresolved eligibility/staff-lead screen. D25 allows manual entry only when the installed guest's valid confirmed booking is established. D5 missed-scan correction after the event is separate and absent from the console.

Source: builder lines 94–96, 147, 245, 287–288; recovery JSON `stafffindguest`; record lines 79–80.

Correction: show search → valid / ambiguous / ineligible result. Only the valid confirmed installed-app result can enable admission. Show D5 later correction as an operator action that grants eligibility without making a personal check-in. Offline/reentry details should remain marked proposed.

### PRE-F08 — Console requirements are mostly labels, not reviewable control flows

Screen 72 lists “On/off · Start/end · Preset · Preview,” an address window, and “Confirmation · 24h · 2h · Changes,” but `kind='console'` renders each as a plain text row. There is no actual control state, draft edited value, preview/result, or failure represented for those settings. Screen 71 says “Manual approval available” and “Offer a spot,” but no selected recipient, explicit approval action, seat hold summary, or configurable offer-expiry input is shown. The offer's deadline appears only in the guest view.

Missing or underrepresented approved console capabilities:

- D11 map pin on/off, editable display start/end, preset and preview.
- D13 / D35 per-event home reveal and expiry overrides.
- D22 automatic/manual approval choice.
- D21 / D23 select a waiting guest, configure offer expiry, send their acceptance-required offer.
- D31 identify/protect released spaces while the waitlist is active.
- D29 edit **timing and templates**, including recap invitation, and preview a message. The current Event texts row does not mention templates or the recap invitation.
- D5 correct missed admission independently from personal event check-in.
- D27 Astir moderation/removal of gallery content.

Event publication and recap publication do have success storyboards, but no publication failure or draft-preserving recovery. The chosen console surface (web vs native) remains undecided in the record; phone shells must not imply it is decided.

Source: builder lines 58–62, 153–161, 278; record lines 112–122; draft §7–8.

Correction: make compact, explicit operator subflows with the fields and resulting guest states; mark detailed save/publish/delivery procedures proposed. Do not claim complete console coverage from a text row naming each control.

### PRE-F09 — “Show ticket” does not show a ticket

Screen 18 Events has a Show ticket CTA whose actual destination is screen 19 event details. Screen 19 then requires Show ticket again to reach the QR. This is a simple but meaningful repeat of the flow-clarity problem.

Source: builder line 38.

Correction: route Show ticket to the QR, or label the first action View event. Display the tappable confirmed event card separately from a direct Show ticket action.

## Internal coverage checklist for root's master ledger

“Covered” here means the current artifact represents the approved behavior; it does not mean implemented or tested in Astir. “Partial” means notes/draft cover the requirement but a screen, actual route, or boundary is missing.

| ID | Requirement / source | Current coverage | Action |
| --- | --- | --- | --- |
| PRE-01 | No-install Clip RSVP; equivalent browser fallback (D14) | Partial | Surface-preserving browser route; PRE-F01. |
| PRE-02 | Same event detail functionality in app and Clip/browser | Partial | Preserve return surface and cancellation; PRE-F01–02. |
| PRE-03 | Event imagery/title/description/date/time/RSVP/share | Covered as wireframe | Imagery and visual hook remain proposed layout, not actual photos. |
| PRE-04 | Facepile/count hook; full guest list only once confirmed (D30B) | Covered | Guest-list Back surface wrong; PRE-F01. |
| PRE-05 | Apple/Google sign-in before phone, no full-app installation | Covered in main route | Account-recovery reuse is wrong; PRE-F01. |
| PRE-06 | Collect name/phone without redundant known details | Partial | Missing-only notes exist; no scenario for known verified identity before no-install RSVP. |
| PRE-07 | SMS verification before confirmation; use actual verified status (D17) | Partial | Main happy path correct; recovery/branching missing; PRE-F04–05. |
| PRE-08 | Explain event texts; unchecked independent future-event opt-in (D19) | Covered | No original combined checkbox remains. |
| PRE-09 | Event-specific access code when required | Partial | Invalid event code frame exists; normal code branch missing; PRE-F04. |
| PRE-10 | Free RSVP only (D20) | Covered | No checkout/payment introduced. |
| PRE-11 | Auto confirmation default, manual option (D22) | Partial | Guest pending frame exists; actual branch and console mode control absent. |
| PRE-12 | Event capacity waitlist, Astir chooses recipients (D21) | Partial | State exists, not complete guest/operator route. |
| PRE-13 | Offer requires acceptance; 24h default configurable (D23) | Partial | Guest offer/expiry exists; console expiry input and selected-recipient send missing. |
| PRE-14 | Released spaces protected for waitlist selections (D31) | Partial | Notes/draft only; no console visual for protected seats. |
| PRE-15 | Self-cancel before start releases spot (D24) | Partial | No-app access and cutoff missing. |
| PRE-16 | Confirmation/calendar without installing full app | Covered as static action | Calendar result/failure is proposed and not visualized. |
| PRE-17 | RSVP → texts → later download → entry QR | Covered in corrected main sequence | Do not fix an exact download reminder time without proposal/decision. |
| PRE-18 | Automatic confirmation, 24h, 2h, changes, published-recap invite (D29) | Partial | 24h plus confirmation samples; no 2h/change SMS sample or template/timing editor. |
| PRE-19 | Required supported phone/app for entry disclosed before RSVP (D15) | Covered | Browser/desktop usage does not itself imply incompatibility. |
| PRE-20 | Full App Store app before live Events; TF is separate testing (D16) | Covered in spec | Board is a proposal, not release-readiness evidence. |
| PRE-21 | Recover existing booking; shortened event-preserving onboarding | Partial | Happy path shown; wrong-account route creates conflicting new-RSVP sequence. |
| PRE-22 | Strong optional profile-photo prompt, never block QR (D18) | Covered | A/B ordering unresolved; contextual-permission default mislabeled. |
| PRE-23 | QR in Events and direct entry route | Partial | Show ticket incorrectly opens details first; PRE-F09. |
| PRE-24 | Door admission distinct from later personal check-in (D5) | Covered | Staff correction after missed scan is absent. |
| PRE-25 | Installed-app QR failure → verified manual admission (D25) | Partial | Failure/result exists; search/ambiguous/ineligible boundaries absent. |
| PRE-26 | Upcoming/confirmed/past/empty Events states | Partial | Approved confirmed-first exists; past/loading/error absent; city waitlist is unapproved. |
| PRE-27 | Home approximate view + configured exact window (D8/D13/D35) | Partial within this scope | No-app notes exist; home scenes are installed-only, console editors missing. |
| PRE-28 | Pin controls on/off/start/end/preset/preview (D11) | Partial | Text row only. |
| PRE-29 | Internal approval/waitlist/message controls (D21–D23/D29/D31) | Partial | Text rows, not explicit editable states and guest outcomes. |
| PRE-30 | Publish recap first, then invite (D26) | Covered as success flow | Queue retry/failure remains proposed, no failure frame. |
| PRE-31 | Staff correction and Astir content moderation (D5/D27) | Missing in console | Add separate operator subflows. |
| PRE-32 | No silently approved proposals | Fails | Default badge must be corrected; PRE-F03. |
| PRE-33 | No invented complete browser-only event journey | Partial | Main gate correct; shared navigation currently jumps between browser/app/staff. |

## Verification limitation to close

The existing `verify-flow-wireframes.cjs` checks counts, IDs, key protected-content absences, unchecked marketing opt-in, screen sequence, and layout overflow. It does **not** validate state-/actor-/surface-preserving navigation, cancellation availability without the app, or proposal labels. Passing it therefore does not establish line-for-line requirement coverage. Add direct assertions for the corrected requirements rather than using screen counts as a completeness claim.
