# Native onboarding film explorations

The approved opening remains the default. Two optional debug treatments apply
the Coming Soon / Ocean Park film language to the same native welcome and auth
flow. Neither changes the words, reading holds, navigation, or auth provider.

- `WANDER_ONBOARDING_TREATMENT=film`: current Avenir/serif typography with worn
  faded Signal ink and the original film texture.
- `WANDER_ONBOARDING_TREATMENT=film-type`: the same film, with
  Helvetica Neue Condensed Black for the word sequence, benefit copy and
  account heading; Helvetica Neue Bold Italic for both the stable
  "Connect with your" lead-in and supporting line.
- Unset, `approved`, or unknown values: approved opening. Release builds ignore
  the environment override.

For a local simulator review, launch with `-WanderAuthenticatedUITest
-WanderOnboardingUITestSignedOut` and optionally set
`WANDER_ONBOARDING_REVIEW_PICKER=1`. The Style menu switches treatments without
replacing native controls and can replay the introduction. This menu is limited
to the debug fixture route and does not appear in ordinary app launches.
The fixture route uses local test authentication, not a live account.

## Material and interaction

`onboarding-film-texture.mp4` is the original, unlettered Higgsfield texture
from the Coming Soon source archive documented in
[the Events asset handoff](../events-coming-soon/README.md). No additional
media generation is used. Its first frame provides the immediate/Reduce Motion
poster. Screen blending at 48% with slightly stronger contrast keeps background
wear visible. The field is `#0c1010`; Signal is `#d77554`.

The selected Events 03C renderer supplies the damage cadence, not just its
background texture. Native Canvas resolves SwiftUI ink into a symbol, then draws
displaced rows with warm registration smear, irregular flecks, scanned rows and
brief density dropouts. Three stronger tracking faults occur in each 8-second
cycle (1.68-1.88, 4.72-4.88 and 6.93-7.18 seconds); quieter motion remains between
them. The original 12-second sequence of short signal-density failures is also
preserved. Signal hue remains fixed. The intro geometry has small registration
slips during faults; actual Map/activity components and bottom actions remain
native. Sparse dust, short scratches and head-switching noise cross the picture.

This translates the selected Events composition and tape-shader algorithms
archived in `../events-coming-soon/render-source.zip` into native Swift drawing.
The reference was inspected at steady and fault frames. No shader compiler,
web view or recorded button is used at runtime. The original native views retain
layout, accessibility and hit areas; decorative drawings do not handle touches.
A single muted local video layer supplies the original background texture.

Next, Log in, email, code entry and account navigation use the existing actions.
Automatic progression ends at Create your account, where all film motion holds.
There is no signup close button. Pause, backgrounding, Reduce Motion and view
removal stop decorative playback; teardown releases the queue and looper.
Reduce Motion selects undistorted static ink even when toggled during a fault.

This is an exploration for comparison, not a selected production replacement.
The post-authentication setup and post-onboarding NUX are outside this change.
