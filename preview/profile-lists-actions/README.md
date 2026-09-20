# Profile and list actions · design proposal

September 20, 2026 · REC-549 · Awaiting Joe's design approval.

These are HTML-rendered design mockups with fictional profile/list content,
not screenshots of a tested iOS build. The included SwiftUI changes are a draft
of the same action placement and styling. Main and the launch checkout are
unchanged. Earlier profile-only work remains in draft PR #682.

## Shared treatment

- Equal-width Edit and Share actions, in that order, directly below identity.
- 44pt minimum height, 8pt gap, 12pt continuous corners, 15pt adaptive Avenir Next
  Demi Bold. Labels can wrap at larger Dynamic Type sizes.
- Neutral fill: primary text at 5.5% opacity on paper, 10% on ink. No border,
  shadow, icon or accent fill on this action row, following Joe's IG reference.
- The shared SwiftUI label is `AstirIdentityActionLabel`. Existing buttons own
  behavior, permissions and share-card presentation.

## Profile

Feedback moves to the leading edge. Notifications and hamburger Settings stay
trailing. Edit profile and Share profile sit below Member since. Other-member
profile actions keep their existing placement. Feedback rollout, notification
badge, profile header motion and walkthrough targets remain connected.

## List detail

Back stays leading and Add places stays trailing. Edit list and Share list sit
below owner/collaborator information and above the map. Edit remains subject to
the existing permission check. Visitors see only Share; offline/local records
without a shareable ID omit Share. Existing collaborator/leave/report controls
and permissions are preserved. Lists overview is outside this proposal.

## Preview and next step

Open `index.html` for the four-screen comparison. `render.cjs` generates
`profile-light.png`, `list-light.png`, `profile-dark.png`, `list-dark.png`, and
`comparison.png` using Playwright and installed Chrome. Images reference the
existing bundled onboarding map artwork. Context imagery and platform chrome
are illustrative; native appearance is the post-approval verification step.

Reviewed the rendered previews for visual hierarchy, matching button treatment,
label fit, and readable contrast. `git diff --check` passed. Functional tests,
native compilation, device screenshots, scroll-transition checks, compact and
accessibility sizes, and owner/collaborator/viewer navigation validation are
deferred until design approval, as requested. No merge or deployment authorized.

Implementation note: REC-559 separately changes profile navigation transitions.
This isolated branch must reconcile that work if it lands before this proposal.
