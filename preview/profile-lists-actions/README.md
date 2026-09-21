# Profiles and list actions · design proposal

September 20, 2026 · REC-549 · Owner Profile and List detail direction approved;
member Profile added for Joe's design review.

Latest refinement: remove the visible backgrounds from profile navigation icons
and the custom list Add/More actions. Preserve their 44pt tap targets and the
filled Edit/Follow/Share action row. The system-owned list Back control keeps
its native navigation treatment and behavior.

These are HTML-rendered design mockups with fictional profile/list content,
not screenshots of a tested iOS build. The included SwiftUI changes are a draft
of the same action placement and styling. Main and the launch checkout are
unchanged. Earlier profile-only work remains in draft PR #682.

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
and permissions are preserved. Lists overview is outside this proposal.

## Preview and next step

Open `index.html` for the six-screen comparison. `render.cjs` generates owner
Profile (`profile-*`), List detail (`list-*`), and member Profile (`member-*`)
in light and dark, plus `comparison.png`, using Playwright and installed Chrome.
Images reference the
existing bundled onboarding map artwork. Context imagery and platform chrome
are illustrative; native appearance is the post-approval verification step.

Reviewed the rendered previews for visual hierarchy, matching button treatment,
label fit, and readable contrast. `git diff --check` passed. Functional tests,
native compilation, device screenshots, scroll-transition checks, compact and
accessibility sizes, and owner/collaborator/viewer navigation validation are
deferred until the added member design is approved, as requested. No merge or
deployment authorized.

Implementation note: REC-559 separately changes profile navigation transitions.
This isolated branch must reconcile that work if it lands before this proposal.
