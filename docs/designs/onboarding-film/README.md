# Native onboarding film explorations

The approved opening remains the default. Two optional debug treatments apply
the Coming Soon / Ocean Park film language to the same native welcome and auth
flow. Neither changes the words, reading holds, navigation, or auth provider.

- `WANDER_ONBOARDING_TREATMENT=film`: current Avenir/serif typography with worn
  faded Signal ink and the original film texture.
- `WANDER_ONBOARDING_TREATMENT=film-type`: the same film, with
  Helvetica Neue Condensed Black for the word sequence, lead-in, benefit copy
  and account heading; Helvetica Neue Bold Italic for the supporting line.
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
poster. Screen blending at 42% makes the background imperfections visible while
softening the horizontal scratches. The field is `#0c1010`; Signal is `#d77554`.

The Ocean Park label's native Canvas ink-removal technique supplies fine grain,
scanned rows and sparse fixed wear within SwiftUI lettering. Dropout strokes are
short, intermittent and limited to 18% opacity. No shader compiler, full-screen
rasterization, web view, or recorded button is used at runtime. The native Map
and activity preview remain their existing components. A single muted local
video layer draws the background texture above them with hit testing disabled.

Next, Log in, email, code entry and account navigation use the existing actions.
Automatic progression ends at Create your account, where all film motion holds.
There is no signup close button. Pause, backgrounding, Reduce Motion and view
removal stop decorative playback; teardown releases the queue and looper.

This is an exploration for comparison, not a selected production replacement.
The post-authentication setup and post-onboarding NUX are outside this change.
