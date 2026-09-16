# Astir Events — gstack design review

Status: in progress. The user authorized `/plan-design-review` and asked specifically about onboarding. The current product draft is the review target; this instruction does not silently approve every operating proposal in it. No application code is being changed.

## Review scope and evidence

- Review all seven passes, with particular attention to the RSVP → app-install → ticket onboarding path. The target and focus are established by the conversation; no repeat scope-selection question is needed.
- Initial design completeness: **6/10**. Product permissions and major states are well described. Missing screen hierarchy, onboarding return routing, contextual prompts, exact visible recovery, and accessibility behavior prevent an implementation-ready design.
- A complete design plan will give every screen one primary action, a defined back destination, meaningful loading/empty/error/success/partial states, an explicit identity/booking recovery path, and consistent visual/accessibility rules.
- Existing source: `wander/DESIGN.md`, its Astir visual override, native design-system components, onboarding sources, the working product record, and journey matrix. The older DESIGN.md navigation and Everyone/followers wording must not override newer source behavior or user-approved Events audiences.
- Repository: GitHub; base branch `main`. Inspected checkout `ed202f25e0f2a7d7ac9cb9cb422b38c30eaa1c41`; refreshed `origin/main` `1775f8dd737b2c2d04170d53de2314bd501bd103`. The checkout is clean and behind the remote; it was not switched or modified. Relevant origin changes confirm Astir naming/icon and tab styling without changing the inspected onboarding gate.
- gstack session: `992-1789086717-94f457d3`, start `1789086717`, interactive, telemetry off, explicit checkpoints. Designer binary is absent at the configured path. Use HTML wireframes as the documented fallback. Optional brain-cache commands could not run because `bun` is absent from their environment; the explicit session records and repository sources provide the required context.
- The installed skill contains the review passes inline; its referenced `sections/review-sections.md` is absent from the installed package. The inline seven-pass instructions are available and govern this review.

## What already exists

Astir's active visual direction is warm paper `#F2E9DB`, ink `#141714`, adaptive dark mode, signal coral `#F05A3C`, and its contrast-safe small-text companion `#B23620`. Native editorial serif serves major titles; Avenir Next serves controls, identity, and body copy. The plan should extend these tokens and native components rather than introduce an Events-specific brand.

Existing authentication, profile mirroring, required identity handling, optional avatar selection, permission steps, and error controls are the foundations. A saved Astir profile may already supply a valid name/handle when the provider session does not. Read the real current profile before displaying a repair form. This is code evidence, not a verified claim about webhook timing or all live accounts.

The current general entry flow mounts full onboarding before the main app. The event route must resolve a real signed-in session and matching reservation while deliberately handling the shortened journey ahead of the general carousel, permissions, and walkthrough.

Evidence and proposed details: [onboarding audit](onboarding-design-audit.md), [event-surface audit](event-surface-design-audit.md). These audits are preparation and recommendations, not approved changes or completed review passes.

## Pass 1 — Information architecture

Initial score: **6/10**. The product draft provides the destination but has not selected whether optional profile setup comes before or alongside a returning RSVP guest's ticket.

### Design 1 — Where optional profile setup belongs

**Pending user choice.** For a guest with a confirmed reservation and a valid recovered profile:

- **A (recommended): ticket first.** Show the confirmed event ticket immediately, with the prominent optional Add a photo prompt below it. Photo selection/upload/cancellation/failure never displaces or blocks the QR.
- **B: one brief profile screen first.** Prefill identity, strongly offer a photo, and provide a clear Skip for now action to the ticket. This preserves a dedicated setup moment but adds an interstitial before entry.

Both paths preserve actual authentication and reservation ownership. Both repair genuinely missing/invalid required identity before the authenticated ticket. Neither reruns completed onboarding or demands a profile photo. Pending/waitlisted/offered guests get their actual event state, never a fabricated ticket.

The recommendation follows hierarchy as service: a guest opening Astir for an event should immediately find the action they need at the door. This is a layout/sequencing choice, not an admission exception or removal of account validation.

Coverage is equivalent; these options differ in sequencing, not completeness. Specification effort is roughly 30 minutes for a human designer or 10 minutes of agent work for either, excluding implementation and validation.

A gains direct access to the ticket and keeps optional-photo failures out of the arrival path; its tradeoff is that guests may give the profile prompt less attention. B gives photo setup dedicated attention and keeps it in one clear place; its tradeoff is an extra screen and skip action before the event promise is fulfilled.

Wireframes: complete Events journey (local authoring source; authority retained in the requirements ledger). They are layout studies with a nonfunctional QR, not approved final visuals or a working event implementation.

### Full visual context requested by the user

The user asked to see the whole journey in the same wireframe style, including options and alternate flows, before continuing isolated design questions. Design 1 remains unselected; showing A in the main path is illustrative, not approval. Both A and B now appear together in the Onboarding options filter.

The board contains **73 numbered screens across 15 chapters**, with a **24-screen main journey**. Coverage includes invitation, Apple/Google sign-in, phone verification, confirmation, app installation and account recovery, optional photo setup, Events navigation, guest list, door admission, recap invitation, personal check-in, protected recap, gallery-photo selection, event posts, map/place history, and recommendations. Branches include browser fallback, manual approval, waitlist offers/expiry, existing members, wrong accounts, missing identity, QR/scan failures, missed admission, locked/unpublished recap, photo failures/removal, cancellation/rescheduling, shared uploads, private-home address timing, contextual permission prompts, and console publication.

The previous two-option page is preserved at `onboarding-choice-original.html` beside the expanded page. The builder and source content are in this specification folder. No approved product decisions or application code were changed by this expansion. Operating defaults, layout, copy, and sequencing remain proposals where previously unapproved.

Artifact validation: rendered the generated self-contained HTML in an isolated browser; checked 73 screens, 15 chapters, 24 main screens, working filters, unique element IDs, no script errors, and no horizontal overflow in narrow/large-text mode or the mobile viewport. Verified absent QR on QR failure, absent protected comments/gallery in locked preview, no acceptance action for expired offers, no new scan UI for duplicate admission, initially unchecked future-event consent, and staff admission disabled until both verification checks are selected. Visually inspected the overview, representative screens, and narrow dark/large-text rendering; corrected dark text inheritance. These are artifact checks, not tests of an implemented Astir flow.

The board was queued to open in Codex; refreshing the existing in-app tab also loads it. The next conversation can refer to screen numbers and evaluate complete flows rather than presenting a new isolated question immediately.

## Remaining passes

### September 14 correction — surfaces and download timing

The user flagged that the board hid App Clip/browser versus installed-app boundaries and made installation look required immediately after RSVP. Rechecked the original recording, the user's later explicit Apple/Google → phone instruction, and D14/D15/D17/D19/D29. The approved sequence is no-install RSVP and phone verification → confirmation plus event texts → later full-app installation/shortened setup for the entry QR → admission. Text delivery and reservation access do not depend on downloading Astir. The exact download-reminder time is not newly settled.

Corrected the existing board to **76 screens in 16 chapters, including 27 main-journey screens**. All screens have explicit surface labels. Screens 3–4 both stay in the App Clip, with equivalent browser fallback; the provider step and phone-verification step are distinct from full-app installation. The confirmation action now opens the confirmed RSVP instead of pushing download. Confirmation and reminder texts, no-app event return, and a deliberate later Get entry QR handoff appear before installation. Onboarding A/B remains an unselected proposal about setup after installation. The prior board is preserved as `onboarding-review-before-surface-correction.html`.

Passes 2–6 (interaction states, journey, visual specificity, system alignment, responsive/accessibility) and Pass 7 (decision register) remain to be completed interactively. Preparatory audits do not count as completed passes. Do not assign final scores, claim design completeness, or begin engineering/implementation before this review reaches those stages.

### September 14 requirement-by-requirement audit

Re-read both pasted transcripts, recovered the original decision questions/answers, and applied later amendments. The [internal requirement audit](audit/requirements.md) now contains **135 entries**: 96 directly approved requirements, 8 derived consistency constraints, 20 unapproved operating proposals, 6 open choices, 2 deferred areas, and 3 superseded directions. D1–D35 have a source crosswalk, with D7 deferred. The September roadmap context was rechecked.

The current board contains **125 traced frames across 16 chapters, including 28 main-journey frames**. Corrections cover no-install timing/surface continuity, new RSVP versus booking recovery, required-code/SMS recovery, no-app cancellation, rescheduled dates, staff-only admission/correction, actual console control illustrations, mixed recap media, personal-post audience markers, place/history links, removed-content return behavior, simple coming-soon, home identity/location windows, and notification-value presentation. Approval labels no longer imply unapproved behavior is settled.

Final artifact verification passed: no script errors or duplicate element IDs; valid model and related-path targets; complete frame-to-requirement mapping; the targeted navigation/permission-presentation cases in [verification-results.json](audit/verification-results.json); narrow/mobile and large-text overflow checks. Visually inspected the final overview, representative event/recap/post/console/removal frames, and dark large-text composer. These are local wireframe checks, not runtime validation of Astir or complete visual approval.

The audit names remaining proposal-only gaps (including private-feedback/post editing, mistaken-admission revocation, offline reconciliation and detailed failure cases). The audit is complete; it does not complete the remaining design-review passes or select onboarding A/B. Continue from this corrected, source-traced baseline.

### Installed invite and Events discovery follow-up

The user then explicitly called out two entries: an invitation with Astir already installed, and finding/tapping an event in the new Events tab. The previous existing-member RSVP state did not sufficiently illustrate the event-detail entry itself. A dedicated `installed-entry` chapter now shows both routes converging on the same full event detail, signed-out return, actual booking-state alternatives, and installed-app phone/code handling. Confirmed cards open confirmed detail; Show ticket remains a direct QR shortcut. Opening a link or card does not itself create an RSVP.

Current baseline: **136 frames, 17 chapters, 28 main-journey frames; 137 checklist entries.** The added routes passed rendered click-through checks, retained full-app surface identity and event context, and passed the existing regressions. The invite/Events/common-detail contact sheet was visually inspected. The source crosswalk and exact HTML hash agree. This is a design clarification of the original requirements; the remaining design choices stay open.

## Not in scope

- Reconnection/missed connections and “solo, single, or private”: deferred by D7 until the founders' next discussion.
- Expanded profile/check-in privacy controls: future work under D9; preserve current restrictions.
- A new global Astir visual identity or changes to unrelated app screens: use the existing design system.
- Production app implementation, publishing, database changes, and a release. The September 14 user request separately authorizes an isolated SwiftUI design sandbox with local fixtures and simulator screenshots.

### Wireframe access repair

The user reported that the section link opened Unable to load file. The generated HTML is intact. Browser automation was blocked by the Browser Use URL policy for the hidden `.gstack` file location, so the actual tab could not be inspected; the exact file-viewer cause is unverified. An identical copy is now maintained at `astir-events-spec/astir-events-wireframes.html` on every build. Use its plain workspace file link for handoff, without a section fragment; the board’s own navigation reaches Already in Astir. This changes artifact delivery only, not product content.

## September 14 walkthrough revision

The latest two recordings and explicit download clarification are captured in [revision notes](revision-20260914/review-notes.md), the current product draft and the 156-entry requirements ledger. The current HTML review has 165 traced frames across 18 chapters, including 28 main-journey frames. Nine event-detail states appear side by side, and the decision controls cover surface, recognized account/booking, entry-account completion, event phase, admission and historical check-in completion. The latest user-selected behavior supersedes conflicting earlier layout descriptions above; historical checkpoints are retained for provenance.

Guest-list/RSVP management is gated by recognized confirmed RSVP, not installation. The optional confirmation download offer gives its entry-QR reason. Required name and username precede entry, photo remains optional, post-event reinstall recovers the same attendee/completion, and map pin tap first opens a collapsed card. The web console, optional invitation codes, generated/edited tag preview, social guest ordering, rich recap controls, and removal of the invented recommendations detour are reflected in the artifacts.

The two independent final source reviews found route, surface, and retained-draft mismatches; the root corrected them and added relevant local artifact checks. The 117-case exit suite is a planned engineering acceptance specification with NOT EXECUTED status. It is not proof of backend or live-app correctness.

## Native design sandbox and artifact checks

The [Native mock comparisons in the flowchart](astir-events-flowchart.html) contains 32 actual Simulator captures: 29 primary frames and three smaller-phone checks, plus a six-second pulse preview. The standalone SwiftUI project builds successfully in Xcode 26.3. App Clip and browser treatments are visual simulations inside this sandbox; they are not released platform integrations. The native study uses Hotchkis Park while the numbered flow review keeps Studio Thirty as a separate fixture.

The primary event states, composer, recap, map, place, setup, and compact samples were visually inspected. Pin treatments are labeled A–D in the gallery, with a separate static Reduce Motion treatment. The current native source and capture/build evidence are in [native verification](native-prototype/verification.json); the gallery’s image loading, enlargement, filters and mobile width are checked separately in [gallery verification](audit/native-gallery-verification.json).

The 165-frame HTML review passed its source trace and targeted click-through checks with no script errors, duplicate IDs, or narrow/large-text overflow. These checks verify the review artifacts. They do not execute the 117 planned engineering acceptance scenarios or establish backend, authentication, privacy, messaging or admission correctness. Production app/services remain unchanged by this task. Native validation is Light appearance and selected compact screens; broad native accessibility/Dynamic Type and Dark Mode coverage remain engineering/design validation work.

## GSTACK REVIEW REPORT

| Review | Status | Finding |
| --- | --- | --- |
| Product discovery | Decisions through D35 captured; D7 deferred | Operating defaults remain explicitly proposed. |
| Design plan review | In progress, initial 6/10 | System audit complete; first information-architecture choice pending. |
| Engineering review | Not run for Events | Follows the design review and approved product decisions. |

**VERDICT:** Design review in progress; engineering review required.

**UNRESOLVED DECISIONS:**
- Design 1: ticket-first optional profile setup versus a brief profile screen before the ticket.
