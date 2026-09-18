# Events coming-soon recording (REC-528)

Approved direction: VHS 03C, with fixed faded signal orange, less continuous
sideways jitter, sparse speckles, and occasional stronger tracking failure.
The film contains COMING / SOON and AN / OCEAN PARK / EXPERIMENT, with the
reference's vertical bar. Events is the middle of five native tabs.

## Assets and reproduction

- App loop: `Wander/Resources/Events/events-coming-soon.mp4`, H.264, 720 × 1560,
  24 fps, 8 seconds, 2.1 MiB, no audio track. Bundled and completely offline.
- Immediate/Reduce Motion still: matching `events-coming-soon.jpg`, 360 KiB.
- Reel master: 1080 × 1920, 24 fps, 8 seconds, without phone frame or controls.
- [Drive asset folder](https://drive.google.com/drive/folders/1SIGm1y7bl8TUn4JHBMQ66hTnsSOetX-1)
  contains the reel, cover, compact app loop, and original generated texture.
- The original texture was made with Higgsfield Seedance 2.5. This refinement
  and these exports consumed no additional Higgsfield credits.
- Inspired by [Luke Edom's VHS Nostalgia Typography](https://vimeo.com/60692354),
  especially the final title around 1:12–1:18. No source footage was reused.
  Helvetica Neue Condensed Black is a visual match, not an identified original.

The generation source is archived in this directory as `render-source.zip`.
Its HTML/Canvas/WebGL renderer composites the generated texture, native local
font, and deterministic effects. The accompanying macOS WebKit/AVFoundation
exporter renders exact 24 fps frames offline; the app does not ship a web view,
shader, JavaScript, export harness, or the original large texture. See the
archive README for export commands.

## Runtime contract

`EventsComingSoonScreen` supplies a single `AVPlayerLayer`. The poster appears
before deferred player construction; the muted queue and looper are created
only on the first selected, visible, active, motion-enabled presentation.
Subsequent visits reuse the player. There are no per-frame SwiftUI updates,
network dependencies, live shaders, decoder initialization on other tabs,
playback controls, PiP controller, or audio session changes.

Playback pauses as soon as the screen loses selection/visibility, the scene
becomes inactive, or Reduce Motion is enabled. Removing the native surface
from its window also pauses it and cancels pending construction. Dismantling
releases the queue, looper, layer, observation and preparation task.

Events forces a dark appearance while selected. Other tabs restore the system
appearance. Native tab order is Map, Feed, Events, Lists, Profile; Add remains
a modal action. Existing selection feedback, analytics deferral, walkthrough
native-tab geometry, Map activity gating, and deep-link destinations remain.
Events has no tutorial steps and does not expose unfinished event actions.

The same film fills normal portrait phones. Only empty upper/lower background
is cropped on shorter phones. Extreme wide windows cap artwork width to keep
all lettering visible; black fills any side margins.

## Verification

Unit coverage checks all playback gating combinations, cancellation of a rapid
first exit, reuse across 20 switches, background pause, teardown, bundled media
size/duration/audio, and composition bounds for 320 × 568 through iPad
compatibility dimensions. Native UI tests exercise five-tab placement,
repeated switches, foreground restoration, and clock/CPU/memory metrics.
Results and simulator screenshots are recorded in the implementation PR.
