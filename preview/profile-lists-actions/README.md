# Profiles and list actions · approved design

September 20, 2026 · REC-549 · Joe approved the native hands-on appearance of
owner Profile, member Profile and List detail, and explicitly requested shipping
the implementation to main.

Latest refinement: remove the visible backgrounds from profile navigation icons
and the custom list Add/More actions. Preserve their 44pt tap targets and the
filled Edit/Follow/Share action row. The system-owned list Back control keeps
its native navigation treatment and behavior.

The preview images are HTML-rendered design mockups with fictional profile/list
content, not screenshots of a tested iOS build. The included SwiftUI changes
implement the approved action placement and styling. Existing app typography
is unchanged; the action labels use the existing `AstirTypography.control`.

## Shared treatment

- Equal-width primary and Share actions directly below identity: Edit for the
  owner and managed lists, Follow/Following/Friends for another member.
- 44pt minimum height, 8pt gap, 12pt continuous corners, 15pt adaptive Avenir Next
  Demi Bold. Labels can wrap at larger Dynamic Type sizes.
- Neutral fill: primary text at 5.5% opacity on paper, 10% on ink. No border,
  shadow, icon or accent fill on this action row, following Joe's IG reference.
- The shared SwiftUI label is `AstirIdentityActionLabel`. Existing buttons own
  behavior, permissions and share-card presentation.

## Owner profile

Feedback moves to the leading edge. Notifications and hamburger Settings stay
trailing. These header icons float directly on the screen without glass,
borders or shadows. Edit profile and Share profile sit below Member since. Feedback
rollout, notification badge, profile header motion and walkthrough targets
remain connected.

## Member profile

Back stays leading and More stays trailing, both with unfilled icon treatment.
Follow/Following/Friends and Share
profile sit below Member since using the same shared label as owner Profile and
List detail. The existing relationship action still follows or opens unfollow
confirmation; mutual connections retain the Friends label. Share uses the same
share-card route and is omitted when the record has no shareable ID. More keeps
the existing Unfollow, Mute, Report and Block actions and permission gates.

The mockup shows Following, fictional member Jamie Park, and the existing places
in common row beneath the actions. No notifications or messaging action is
added. Activity, map, privacy rules, counts and header motion remain unchanged.

## List detail

The native Back control stays leading; Add places and More use unfilled icons
trailing. Edit list and Share list sit
below owner/collaborator information and above the map. Edit remains subject to
the existing permission check. Visitors see only Share; offline/local records
without a shareable ID omit Share. Existing collaborator/leave/report controls
and permissions are preserved. Lists overview is outside this change.

## Preview and validation

Open `index.html` for the six-screen comparison. `render.cjs` generates owner
Profile (`profile-*`), List detail (`list-*`), and member Profile (`member-*`)
in light and dark, plus `comparison.png`, using Playwright and installed Chrome.
Images reference the existing bundled onboarding map artwork. Context imagery
and platform chrome are illustrative. Joe's separate native hands-on review
approved the appearance; these PNGs remain HTML mockups.

Reviewed the rendered previews for visual hierarchy, matching button treatment,
label fit, and readable contrast. `git diff --check` passed. No fresh automated
native build or tests were run for this shipping pass: available storage was
12.3 GiB, below the required 50 GiB build floor; the iOS helper refused to
start the focused native run. The repository's
`agent-skills/recme-pr-review-merge-release/SKILL.md` permits an explicit low-risk
environment skip. Before the next release, run native compilation and functional
tests, capture device screenshots, and check scroll transitions, compact and
accessibility sizes, and owner/collaborator/viewer navigation. Main landing is
authorized; a TestFlight or App Store release requires its own release workflow.

Implementation note: REC-559 separately changes profile navigation transitions.
This branch integrated latest main (`d6dd423`) cleanly. The REC-549 source
implementation has not changed since Joe's approval.
