# Native onboarding film explorations

The approved opening remains the default. Two optional debug treatments apply
the Coming Soon / Ocean Park film language to the same native welcome and auth
flow. Neither changes the words, reading holds, navigation, or auth provider.

- `WANDER_ONBOARDING_TREATMENT=film`: current Avenir/serif typography with worn
  app Signal ink and the original film texture.
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
poster. Screen blending at 48% keeps background
wear visible. The field is app Ink `#141714`; Signal is app Signal `#F05A3C`.

The selected Events 03C renderer supplies the damage cadence, not just its
background texture. Native Canvas resolves SwiftUI ink into a symbol, then draws
displaced rows with delayed Signal registration, fine raster wear and
brief density dropouts. One shared clock and screen coordinate system keep every
word and retained slide in the same film phase; the reference raster is 720/393
pixels per point, independent of phone density. The four color-tail sample offsets
and smooth tracking-band falloff follow the Events renderer. Native Canvas retains
the actual SwiftUI glyphs; this is not a claim of pixel-identical WebGL output. Three stronger tracking faults occur in each 8-second
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
Only the masthead text enters Canvas; its material backing stays outside symbol filtering, and the
AVPlayer surface has no color-matrix filter. Those combinations triggered an
iOS Simulator RenderBox crash during live playback despite passing static tests.

Next, Log in, email, code entry and account navigation use the existing actions.
The film's playback state is independent of the carousel reading timer. Reading
holds pause during a scene slide; texture, ink faults and registration slips
continue through opening-to-Places and Places-to-People on both retained scenes.
Automatic progression ends at Create your account. Only its transparent statue/letter/bar artwork keeps the native film motion. The account heading and supporting copy are still; every form control is solid, unfiltered native UI. The custom texture is held behind the form, never over the controls.
There is no signup close button. Pause, backgrounding, Reduce Motion and view
removal stop decorative playback; teardown releases the queue and looper.
Reduce Motion selects undistorted static ink even when toggled during a fault.

Joe preferred C and preserved the prior warm version as an archive at `1e27cb4`. The September 18 revision retains C typography and motion with app colors and a seamless logo background. The subsequent Events-match revision keeps only the account artwork animated and returns the heading to still ink. The prior app-palette study is archived at `945c280`.
It remains separate from the approved production opening; no merge is implied.
The post-authentication setup and post-onboarding NUX are outside this change.
