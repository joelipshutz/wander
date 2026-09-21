# Astir shared tape study — REC-557, revision 3

Branch-only visual review of Events, the launch splash and the create-account
logo. Uses the exact logo PNG and the approved Events texture/signal source.
No native app or timing changes. Keep draft PR #686 unmerged.

```sh
python3 preview/splash-vhs/serve.py --port 65364
```

Open <http://127.0.0.1:65364/preview/splash-vhs/>. Compare Motion, Static material
and Original logos. “Show a tear” pauses at source 1.80 seconds; the slider
inspects any frame. The full eight-second and short 1.8-second cycles begin at
source 1.40 seconds. The selected bend spans source 1.55–2.05 seconds. “Larger previews” expands the phone frames.

The account form is an inert browser illustration of the current native layout.
The decorative logo is rendered through the same actual shader as the splash.
The brand logo is never re-typeset. In production, form controls should stay
native and outside the decorative effect.

[Detailed library](../../docs/brand/analog-tape/README.md) includes separate static
and motion briefs, original prompt, preserved original shader/compositor,
iteration history and asset hashes. The exact Events movie and source texture
are linked from their existing tracked paths.

“Save preview videos & stills” writes two locally recorded videos and four PNGs
into `media/` via the loopback-only helper. It is not a network upload or native
app build. The videos are real-time canvas captures at a requested 24 fps;
they are visual-review artifacts, not the deterministic 192-frame Events master.
Use the preserved offline exporter as a starting point for production-quality
frame-exact outputs if the visual direction is approved.

Revision 2 remains in git history at `49c2d59` (revision 1 at `9e2ae5b`).
Revision 3 stretches the selected first tracking waveform to half a second,
removes art-opacity dropouts, shader pulse and band darkening, and holds the
material grain/texture steady. Geometric distortion and chroma registration
remain. The other two source tracking faults retain their timing. The original
renderer in `docs/brand/analog-tape/source/` is unchanged. Existing video link
paths are refreshed with the current proposal.

## Current revision 3 verification — September 20, 2026

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
