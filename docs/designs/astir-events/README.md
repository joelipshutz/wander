# Astir Events — flowchart and screen review

Open **[astir-events-flowchart.html](astir-events-flowchart.html)** locally in a browser. This is the September 14 review snapshot: all 165 screen states in 12 continuous sections, with the screens visible inside the flowchart and expandable in place.

## Open the actual screens

GitHub shows HTML source rather than running this page. Download the HTML using **Download raw file**, then open the downloaded file in Safari or Chrome. All screen images and the short motion preview are embedded, so the HTML works by itself without installation, a server, sign-in, or an internet connection.

For the supporting specification and diagram links, keep this entire directory together. From an existing checkout, open the copy on `main` in a separate worktree to avoid disturbing application work:

```sh
git fetch origin main
git worktree add --detach ../astir-events-review origin/main
open ../astir-events-review/docs/designs/astir-events/astir-events-flowchart.html
```

The HTML is about 35 MB because it includes every preview. Allow the initial download to finish. No Xcode build is needed.

## Review status

This is a product/design review artifact for [REC-467](https://linear.app/recme/issue/REC-467/define-place-centered-events-guest-rsvp-attendance-and-follow-up). Joe and Ryan are still reviewing it. Engineering planning is in progress; committing these files does not approve unresolved layouts or operating proposals.

- Each screen identifies its surface: full app, App Clip, browser, text, or internal console.
- There are 26 primary native mock previews and 139 primary wireframe previews, plus supplementary native variants. Native images come from an isolated SwiftUI design sandbox with sample event data.
- Confirmed guests can view the guest list and manage their RSVP in App Clip or browser without downloading. Installation is optional after RSVP and required for the entry QR and admission.
- Door admission and the later explicit event check-in are separate. An event check-in creates one event-labeled visit at the linked place.
- Reconnection and expanded privacy controls remain deferred. Photo ordering, pin treatments, and other marked proposals remain open where labeled.

See the **[product spec draft](product-spec-draft.md)** for approved requirements versus proposed operating rules. Links to working notes that are not included here are labeled as authoring references. Earlier planning tickets may contain superseded product direction; use the dated amendments in this specification for this review.

## Files and validation

The main HTML is byte-for-byte identical to the reviewed workspace copy. [Coverage](flowchart/continuous-coverage.json) verifies 165 unique screens with no omissions or duplicates. [Browser verification](flowchart/inline-preview-verification.json) records decoded previews, desktop/mobile expansion, search, printing, motion playback, and zero external requests. These checks validate the artifact, not the future Events implementation.

- [Compact overview](flowchart/astir-events-overview.svg)
- [Editable compact overview](flowchart/astir-events-overview.excalidraw)
- [All-screen connection map](flowchart/astir-events-all-screens.svg)

The complete HTML is the review entry point. The large connection map is a supplemental reference.
