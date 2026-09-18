# Native onboarding review (REC-529)

The review uses production Swift views. The local browser board displays simulator
recordings and frames beside source copy, with pan/zoom, TV viewing and review notes.
The implementation remains in draft PR #648 for creative review.

## September 17 native material explorations

Joe requested a maximum of three native explorations without Higgsfield credits.
Station, Sculpted, and Graphic share the exact approved words, three-row geometry,
two-flip mechanism, and scene sequence. Station uses restrained bevels and a crisp
mechanical face; Sculpted adds depth and fuller caps; Graphic uses the largest caps
and flat matte faces. All use uppercase Signal letters and adaptive light/dark faces.
The source implementation is commit `6174988`.

`OnboardingFlapSurface` retains UIKit/Core Animation tile layers and rasterizes a
small branded glyph atlas on size/appearance changes. During each flip only changed
tile layers update; stationary cells skip work. Middle-hinged halves accelerate on
the fall and decelerate on landing. This replaces the repeated SwiftUI Text layout
and per-face live drawing. The existing Avenir Next family supplies condensed heavy
caps. Slides share a 0.6-second curve (0.32, 0, 0.18, 1), with existing view retention
and animation-completion cleanup preserved.

Debug-only `WANDER_ONBOARDING_FLAP_FINISH=station|sculpted|graphic` selects a review
treatment. Release defaults to Station; this is a capture selector, not a remote
feature flag or an approved final material selection. No Higgsfield generation ran,
and no creator reference art or video is bundled into the app.

The build passed, along with 22 focused unit tests. Three new pixel-render regression
checks cover the final settled board, appearance/finish reuse, and resizing. Manual
paging and rapid Next/signup/login tests passed on this app build. The timed automatic
test initially missed its page-two observation during slow simulator startup; its
clock now starts with the real Play control. The unchanged timing limits passed in
54.004 seconds (`native-flaps-auto-test.xcresult`); no timing threshold was relaxed.

The comparison gate is `opening-explorations.html`: three actual simulator recordings
in each appearance, with Replay/Pause, shared relative-time scrubbing, letter zoom,
individual focus, and full-screen presentation. `native-finishes.json` identifies
each recording and its launch offset. Raw captures are played directly; the browser
skips launch footage without reconstructing or re-encoding app motion. Functional
test success does not establish physical-device frame pacing.

All six complete recordings reach account creation in browser playback. Light/dark
switching, replay/pause, seeking, focus, letter zoom, full screen, keyboard controls,
and compact browser width passed with no JavaScript errors or missing assets. Six
compact-phone native screenshots were also visually inspected. The review's local
server now supports HTTP byte ranges: without them these raw captures exposed a
zero-length seekable range. Restart the local room with
`python3 serve_review.py --port 8766` from `onboarding-copy-review`. Browser evidence
is `native-board-qa/native-finishes-report.json`; the native source/recording hashes
and differing static-tail durations are recorded in `native-finishes.json`.

## Preserved opening sequence

The opening is a centered, fixed three-row split-flap board. All letters are uppercase
Signal coral; flap faces are white in light appearance and dark in dark appearance.
The first row is CONNECT WITH YOUR, the second cycles COMMUNITY → PEOPLE → PLACES →
LOVED ONES, and the third stays blank. Each changed cell makes two hinged flips,
using clipped upper/lower glyph faces. The final phrase occupies the same grid:
A / LOCAL / EXPERIMENT, centered one word per row.

Selected description A.03 is “Keep track of everywhere you’ve been. Keep up with the
people you love.” It slides in just above pagination/Next after 3.6 seconds and stays
through the final phrase. The word cadence is 1.8 seconds held + 0.6 seconds flipping.
The final phrase settles at 9.6 seconds, holds 2.4 seconds, then slides left while the
Places composition enters from the right. Both benefit pages get seven seconds.

The Places square contains the production PlaceProfileMapSurface, MapKit and the
real Hotchkiss Park photo retrieved through Astir’s authenticated place-photo endpoint
on September 17. Its original Google Places attribution and image bytes are bundled
for the signed-out introduction, through a narrowly scoped PlacePhotoRepository;
there is no substitute stock photo, embedded credential, or change to backend access.
Stale opening hours and ratings are omitted. The temporary dedicated review-account
session used to retrieve the photo was ended. Provenance is in
Wander/Resources/Onboarding/OnboardingHotchkissPark.json.

The benefit panels mount during the opening so the real photo loads before the first slide.
Places → People moves only the upper native UI while the lower board stays anchored
and flips to KEEP UP WITH / THE PEOPLE / YOU LOVE. Example places/activity labels
are removed. ActivityPostcardView still uses fictional sample activity. Account entry
slides the outgoing composition left and the incoming account view right-to-center.
The slide duration is 0.6 seconds. SwiftUI animation completion retains outgoing
views until rendering finishes; a wall-clock cleanup timer could hide the park early
under simulator load. Rapid Next taps are retained in a bounded queue
instead of disappearing during a transition. Direct Log in remains available.

Reduce Motion/VoiceOver stop automatic motion and resolve an active word flip to a
readable word. Pause, foreground/background handling and manual navigation remain.
An explicit empty configuration can omit the opening for focused tests/previews.

## Prior validation, before the material explorations

The stable-panel simulator build passed its complete unit suite; the subsequent preview-preloading and animation-completion adjustments passed all three affected UI tests again:
**1,992 tests, zero failures**, 32.572s (33.117s wall), in
`uppercase-stable-ui-tests.xcresult`. A preceding run had one unrelated existing
performance outlier at 0.123681s against a 0.1s ceiling. That unchanged test passed
both an isolated recheck and this full rerun; no threshold was relaxed.

All three affected welcome UI tests passed with zero failures in 64.553s: automatic
progression, bidirectional manual paging, and rapid Next → signup → close → login →
close (`uppercase-completion-ui-tests.xcresult`). Earlier verification caught lost fast
Next taps; the bounded queue fixes that behavior and the unchanged rapid-tap test now passes. Added unit coverage checks
three centered uppercase rows, two continuous physical flips, exact final text,
real bundled photo decoding/attribution and rejection of other-place photo requests.

The final light/dark simulator recordings and main-phone state captures are published
in the review room. Exact frames confirm the real park photo, uppercase grid,
anchored benefit board, retained outgoing Map and both sides of account entry.
Compact light/dark layout captures use the preceding stable-panel build; the final
preloading/completion edits change lifecycle timing only. Earlier A/B/C recordings
and browser explorations remain linked from Archives.

Earlier native auth/background verification passed in 41.611s and profile/photo/crop
in 79.583s. Follow and OS permission request/denial/recovery journeys also passed on
prior builds of those unchanged flows. Earlier broad Map timing/selection failures
remain outside this focused clearance; no full broad UI-suite pass is claimed.

## Preserved scope and restart

The broader branch includes required profile photo/name/username with the shared
live profile preview and upload-failure gates; member search and individual follows;
shortened Contacts copy; native notification examples; and a short Map overview plus
account-scoped contextual hints replacing the forced saving tutorial. Those areas
are deferred in this refinement, as requested. Plans/Events, contact matching,
curated starter lists and further material/quote exploration remain separate work.

Debug argument `-WanderNativeOnboardingReview welcome` runs the same production entry
flow with local account/profile repositories. It does not create accounts, follow
members, send invitations or upload a profile. The park is actual place data; other
activity/member/notification samples remain identified in the review inventory.

The review room is `onboarding-copy-review/session-2026-09-16/` in the shared workspace.
`TASKS.md` retains the full transcript register. `native-verification.md` and the media
manifest record capture evidence. `opening-explorations.html` compares the three new
native treatments; `opening-review.html` preserves the previous light/dark baseline,
and `archives.html` preserves earlier A/B/C and HTML explorations. This
work does not merge, deploy or upload a new release.
