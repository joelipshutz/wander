# Astir shared tape study — REC-557, revision 4

Branch-only visual review of Events, the launch splash and the create-account
logo. Uses the exact logo PNG and the approved Events texture/signal source.
No native app or readiness changes. Keep draft PR #686 unmerged.

```sh
python3 preview/splash-vhs/serve.py --port 65364
```

Open <http://127.0.0.1:65364/preview/splash-vhs/>. The clock starts at **zero**.
The selected bend now begins **0.50 seconds after launch**, lasts its original
0.20 seconds, and never blinks the logo. “Show a tear” pauses at elapsed 0.60 s.
This corrects revision 3's mistaken interpretation of “half a second” as duration.

The 1.2-second default and 0.8-second quick cycle show it during a short splash;
the 0.35-second case shows a launch too fast to catch it. The eight-second cycle
shows later faults as well. No minimum hold is added to the native app. Three
launches of installed simulator build 177 measured approximately **2.79–3.38 s**
of visible splash; see [method and limits](../../docs/brand/analog-tape/SPLASH-TIMING.md).

The reference Events film is paused by default, with independent playback
controls. Its original flicker is retained only in that historical source.
The proposed splash/account keep constant opacity, fixed material and no
luminance pulse or band darkening. Geometry and registration still move.

The account form is an inert illustration of the native layout. Its decorative
logo uses the same shader and exact bitmap as the splash; UI labels are drawn
after the signal pass. The logo is never re-typeset. “Static material” holds the
material still; “Original logos” shows the supplied bitmap without added wear.

[Detailed library](../../docs/brand/analog-tape/README.md) includes separate static
and motion briefs, original prompt, preserved source, history and asset hashes.
Original source bytes are not edited. Earlier revisions are recoverable at
`26c6dbe` (v3), `49c2d59` (v2), and `9e2ae5b` (v1).

“Save preview videos & stills” writes two locally recorded MP4s and four PNGs into
`media/` via the loopback helper. Recordings start at elapsed zero and run eight
seconds; the selected short-cycle setting is restored afterward. These are
requested-24-fps, real-time review captures, not frame-exact production masters.
The stable `*-v2.mp4` URLs contain the latest revision for existing viewers.

## Current revision 4 verification — September 20, 2026

- Early event schedule: 0.50–0.70 s, normal waveform speed; held bend at 0.60 s.
- Browser controls, short cycles, still inspection and export checked.
- Three installed-build native launches recorded and decoded for timing.
- Both saved videos decoded with AVFoundation: 720 × 1560, silent, 8.249 s,
  about 22.06 fps nominal. The 0.65-second recorded frame shows the early bend.
- All 182 decoded splash frames retained steady logo-band luma: 35.11–36.90/255,
  minimum/maximum ratio 95.15%, with no deep brightness dropouts.
- Refreshed stills inspected; original material stills remain byte-identical.
- JavaScript syntax, source-asset hashes and git whitespace checks passed.
- No native source changes or new iOS build. Latest-main/physical-device timing
  remains outside this existing-build measurement; see the timing record.

## Previous revision 3 verification — September 20, 2026

- Browser renderer compiled without warnings/errors. The 1.80-second still
  visibly bends the lettering and statue while keeping them readable.
- First fault window is 1.55–2.05 seconds: 0.50 s (12 samples at 24 fps).
  The original 0.20-second waveform is time-stretched, not repeated faster.
- Both refreshed silent 720 × 1560 MP4s decode with AVFoundation. They measure
  about 8.247 seconds and 22.8 fps nominal as real-time review recordings.
- All 188 decoded splash frames were checked over the full logo band
  (x 0–720, y 560–1000, every fourth pixel). Mean luma ranged 35.00–37.09/255;
  minimum/maximum ratio 94.36%. There are no deep brightness dropouts in this
  recording. This aggregate check complements the visual review; it does not
  claim every moving edge has identical brightness.
- Updated stills, recordings and hash manifest are saved. Logo, Events movie,
  raw texture and archived original source bytes remain unchanged.
- JavaScript syntax and git diff checks passed. No native build was needed
  for this browser-only revision. Native adoption is still outside this PR.

## Previous revision 2 verification — September 20, 2026

- In-app browser: Events and both canvas surfaces rendered together; Motion,
  Static material, Original logos, Show a tear, and the short 1.8-second cycle
  were exercised. Static output held the same source time across observations.
- The source 6.92-second still visibly displaces the sculpture and STIR edges.
  The 0.40-second still retains object wear without moving noise.
- Both saved MP4 files decoded with AVFoundation; extracted frames were checked.
  Each is 720 × 1560, silent, about 8.264 seconds and approximately 23 fps nominal
  from a requested 24-fps live capture. They are review recordings, not exact
  192-frame production exports.
- Browser error/warning log was empty at verification. JavaScript syntax checks,
  Python server compilation and git whitespace checks passed.
- Original artwork, Events movie and texture checksums match the existing
  resources. The three readable original source files match the preserved ZIP
  byte for byte. `docs/brand/analog-tape/assets.json` records every media hash.
- No native build was run: this change contains only browser study code, review
  media and the requested documentation. Native performance is untested.
- Account UI is an illustrative composition and uses local macOS font faces;
  the saved videos preserve this reviewed rendering on other platforms.
