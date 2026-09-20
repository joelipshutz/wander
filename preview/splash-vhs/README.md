# Astir shared tape study — REC-557, revision 2

Branch-only visual review of Events, the launch splash and the create-account
logo. Uses the exact logo PNG and the approved Events texture/signal source.
No native app or timing changes. Keep draft PR #686 unmerged.

```sh
python3 preview/splash-vhs/serve.py --port 65364
```

Open <http://127.0.0.1:65364/preview/splash-vhs/>. Compare Motion, Static material
and Original logos. “Show a tear” pauses at a strong source frame; the slider
inspects any frame. The full eight-second and short 1.8-second cycles begin at
source 6.60 seconds. “Larger previews” expands the phone frames.

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

The previous study remains in git history at `9e2ae5b`. This revision replaces
its custom flicker sequence with the original source timing and moves the band
into object-relative coordinates. It does not modify the original renderer in
`docs/brand/analog-tape/source/`.

## Review verification — September 20, 2026

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
