# Native onboarding review (REC-529)

The review uses production Swift welcome, account, profile, permission, member-follow,
notification and first-visit Map views. The browser board displays actual simulator
recordings and frames beside source copy, with pan/zoom, TV viewing and review notes.
The native implementation, verified media and final browser checks are complete;
the implementation PR is the remaining handoff step.

## Current implementation

The opening keeps **“Connect with your”** fixed while **community / people / places /
loved ones** change through mechanical split-flap letters. Each changed letter has
clipped top/bottom glyph halves and 3D hinged faces, with five staggered cycles.
The headline then resolves to **“a local experiment”**. Supporting copy slides in;
the whole scene slides to the real Places and People benefit UI, then signup.

Current timing is 1.6s hold + 1.0s flips per word; delayed supporting copy enters
at 3.9s, the final phrase settles at 10.4s and holds until the page advances at
12.8s. Benefits each use 7s by default. Pause, backgrounding and manual navigation
remain available. Reduce Motion/VoiceOver stop automatic motion and resolve an
active flip to a complete readable word. An explicit empty configuration can omit
the opening for focused tests/previews.

The profile step reuses the live profile header and requires saved photo, name and
username. Upload failure blocks progression. Member search uses the existing
backend, with individual Follow → Following actions and retry protection. Contacts
copy describes connecting at a high level; it does not claim automatic matching,
and the permission data flow is unchanged. Notification examples use real native
cards. A short real Map overview and account-scoped first-use hints replace the
forced saving tutorial; the second-launch import lesson is retired.

The confirmed headline words and final phrase are implemented. Cadence, supporting
copy, its fate during the final transformation and immediate/delayed timing remain
creative review choices. The default supporting line is “Keep track of everywhere
you’ve been. Keep up with the people you love.” Plans/Events, contact matching,
curated starter lists and handwriting/material exploration remain separate work.

## Validation and native evidence — September 17

The current split-flap build/test command exited 0 (`native-split-flap-tests.log`
and matching `.xcresult`, completed 11:10:06):

- **1,989 unit tests, zero failures**, 41.869s (43.117s wall).
- **Three affected welcome UI tests, zero failures**, 59.523s: automatic progression
  33.072s, manual paging 13.583s, Next/signup/Login 12.868s.
- All four native category-glyph tests passed; actual main/compact Map frames verify
  fallback symbols when the simulator's emoji font is unavailable.

Separate native auth/background verification passed in **41.611s** and actual
profile/photo/crop/Choose passed in **79.583s**. Follow and OS permission request /
denial / recovery journeys also passed. These were executed on prior builds of
flows unchanged by the split-flap work. Signup Log in has a full-width 44pt minimum
hit area; callback wiring was already correct. Earlier nine selected UI tests
included Map/Feed coverage. **Earlier broad Map timing/selection failures remain
outside this focused clearance; no full broad UI-suite pass is claimed.**

All A/B/C recordings were visually verified for hinged glyph halves, staggered
cycles, initial lead-in/community, every word change, final headline and loaded
Map → People → signup. Launch lead-in trims are A 2.0s, B 2.0s and C 1.8s. W00/V01
use A; four state frames use raw A at 2.5/7.5/13.5/18s. A new native compact opening
screenshot is readable. `split-flap-review-ready.json` records movie hashes and
the media manifest is refreshed. The brief, gallery and full board are published.

Final browser QA passed all three videos' playback/seeking through signup,
Focus/Compare, four full-width brief images and main-board V01 playback/pause/seek.
No JavaScript errors or missing assets were found (`final-split-flap-report.json`).
This is the first native mechanical pass for creative review, not final creative approval.

## Run locally and review boundaries

Build the Wander scheme for an iPhone simulator. Debug argument
`-WanderNativeOnboardingReview welcome` uses the shared production entry flow.
Direct routes include `signup`, `login`, `identity`, `location`, `contacts`,
`friends`, `friends-empty`, `friends-failure` and `notifications`. Review routes use
in-memory repositories and local auth; they do not create real accounts, follow
members, send invitations or upload a profile.

For the real Map tour use `-WanderAuthenticatedUITest`, `-WanderMapCapture`,
`-WanderUseDemoFixtures`, `-WanderEnableWalkthroughs`, `-WanderResetWalkthroughs` and
`-WanderWalkthroughTarget mapFeatured`. Use `-WanderHoldWalkthroughStep` only for
stills; omit it for recordings. Map captures use explicitly simulated LA fixture
coordinates. Activity, members and notification examples are labeled sample data.
Conditional capabilities without captures remain explicit copy-only appendix entries.

The review room is `onboarding-copy-review/session-2026-09-16/` in the shared
workspace. `TASKS.md` retains the transcript register and remaining decisions;
`native-verification.md` records exact evidence and limitations. This branch does
not merge, deploy, upload an App Store build or change production services.
