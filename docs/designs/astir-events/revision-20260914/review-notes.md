# Astir Events — September 14 walkthrough changes

The latest clarification separates the gates: a recognized confirmed RSVP permits the full guest list and RSVP management in App Clip or web. Download is optional after RSVP and required for the entry QR/admission. Check-in and shared-gallery contribution also require the full app.

## Review artifacts

- [Interactive flow review](../astir-events-wireframes.html): event-link decision tree, nine surface/account states, the numbered main journey, alternatives, and internal web console.
- [Native mock comparisons in the flowchart](../astir-events-flowchart.html): Simulator captures of the major guest surfaces and pin options A–D; the App Clip/browser views are visual simulations in the sandbox.
- [Product draft](../product-spec-draft.md): current behavior and separately labeled operating proposals.
- [Requirements ledger](../audit/requirements.md): 156 requirements with source and screen coverage.
- [Transcript crosscheck](../audit/transcript-feedback-20260914.md): 90 atomic clauses from the latest walkthrough.
- [Planned exit criteria](../events-exit-criteria.md): 117 named scenarios, all NOT EXECUTED against Astir.
- [Platform notes](platform-notes.md): App Clip installation and identity-continuity constraints for engineering.

## Changes to the reviewed screens

Existing numbered screens keep their previous numbers; additions use N-prefixed labels. Removed screen 31 is not renumbered into a different experience.

| Existing reference | Current treatment |
| --- | --- |
| 03 | Apple/Google authentication retained. Recognize an existing booking before creating another. |
| 04 | Name/phone and SMS verification; future-event opt-in separate and unchecked, with no trailing period. |
| 06 | RSVP finished, calendar available, optional dismissible download offer with its QR-at-door reason, and Stay on the event. |
| Texts and event return | One canonical View event link; receiver’s actual app/account/booking/phase determines the state. Explicit confirmation, 24h, 2h, change, and recap examples. |
| Confirmed event | View guest list and View or change RSVP work without installing; cancellation is inside management. |
| Entry | Missing required name/username leads to setup before any QR presentation. Photo is optional. |
| 25 | Existing-style event composer with optional note, own photos, tags, and private feedback. Empty check-in remains valid. |
| 26 | Rich event recap cover, comment controls, media plus, upper-right Share, and event-led personal check-ins. |
| 29 | Normal map with distinctive event pin, then a collapsed card, then the full event. “Astir 001 at [place]” uses smaller “at.” |
| 30 | Standard place profile with inline Events here history. |
| 31 | Removed, together with Explore nearby on 30. |
| Console | Explicitly internal web; event/recap controls, first-party media, optional generated/capped/uncapped invitation codes, tags, message program, and scanner. |
| Full guest list | People followed first, with permitted mutual counts. |

## Fidelity corrections found during verification

The interactive mock now updates booking state after cancellation and the surface after installation. Authentication returns through the event-state decision. Post-event reinstall checks admission and prior completion instead of always opening a fresh composer. Profile completion guards the QR path. No-app home views hide full-app tabs. Failed-photo drafts retain the note/error. Tag edits affect the local preview, and map filters select one view and honor the illustrated attendance state.

These are local design-artifact behaviors. They do not establish production authentication, persistence, notification delivery, permission enforcement, or code quota/capacity correctness.

## Verification evidence

The interactive HTML has 165 traced frames and passed the targeted navigation/surface/state checks, including narrow/large-text rendering. The independent source reviews’ concrete mismatches were corrected. The native sandbox built successfully and produced 32 real Simulator captures across two dedicated iPhones, plus the pulse recording. The light gallery embeds compressed previews, keeps pin options A–D distinct, and supports enlargement and filtering. Native captures are Light appearance; comprehensive native interaction/accessibility and production acceptance checks are not claimed.

- [Flow artifact verification](../audit/verification-results.json)
- [Native build and capture evidence](../native-prototype/verification.json)
- [Gallery verification](../audit/native-gallery-verification.json)

## Still open

The exact pin shape/motion, optional-photo layout, later QR reminder prominence, second-degree Friends scope, Instagram share payload, and invitation-code accounting remain review choices. Tag generation/storage mechanics need engineering. The icon-color target was not identified in the recording and remains unconfirmed. D7 reconnection and expanded privacy controls remain deferred.

The product/design review continues from these concrete artifacts. No backend or production app changes, external event messages, publication, or release were performed.
