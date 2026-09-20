# Astir analog tape system

Reusable material and motion briefs for the **approved Events 03C / Near failure**
look. The Events film is the visual authority. The splash and account applications
in this branch are **proposals for Joe's review**, not approved production changes.

Joe requested this library on September 20, 2026 so future work can reuse the
same texture and animation without reconstructing the exploration from chat.
His standing constraint for this work is explicit: **keep it on the remote branch;
do not merge to main**. REC-557, `codex/splash-vhs-preview`, draft PR #686.

## Start here

1. Watch the [approved Events film](../../../Wander/Resources/Events/events-coming-soon.mp4).
2. Read [Static texture and material](STATIC-TEXTURE.md).
3. Read [Motion and signal failure](MOTION.md).
4. Read [Origins and decision history](HISTORY.md) before changing the direction.
5. Open [the three-surface study](../../../preview/splash-vhs/index.html) through
   the local server below. It includes Events, the revised splash, the account
   logo, a material close-up, static mode, frame inspection and source videos.

```sh
# From the repository root; no dependencies or credentials required.
python3 preview/splash-vhs/serve.py --port 65364
# http://127.0.0.1:65364/preview/splash-vhs/
```

## What belongs to the system

The object looks as if it and the background were recorded together, copied
between worn tapes, and digitized. Noise sits inside the object's surface;
registration bleed softens its boundary; row timing faults physically displace
pieces of its silhouette. The quiet intervals carry the same material as the
violent ones. Background noise alone is insufficient.

The style has two reusable parts. **Material** is the damaged image that can be
held completely still. **Motion** is the time-varying behavior of that image.
A motion-disabled or static application must still look like the same brand.

Keep the exact source artwork. Astir's sculptural A, serif STIR outlines, Signal
plinth and ONENESS inscription are an image asset, not a font replacement task.
The Events headline has its own condensed face; that does not authorize changing
Astir's logo or any existing text face to that font.

## Assets and source of truth

| Resource | Repository location | Role |
|---|---|---|
| Approved Events film | `Wander/Resources/Events/events-coming-soon.mp4` | Visual authority: 720 × 1560, 24 fps, 8 seconds, silent |
| Events poster | `Wander/Resources/Events/events-coming-soon.jpg` | Recorded material / still reference |
| Unlettered texture video | `Wander/Resources/OnboardingFilm/onboarding-film-texture.mp4` | Original generated dark tape field; 1080 × 1920, 8 seconds |
| Texture poster | `Wander/Resources/OnboardingFilm/onboarding-film-texture.png` | Native still background resource |
| Original splash | `Wander/Resources/Assets.xcassets/AstirLaunchWordmark.imageset/AstirLaunchWordmark.png` | Immutable 1600 × 764 RGBA artwork |
| Original complete render archive | `docs/designs/events-coming-soon/render-source.zip` | Original composition, shader, CSS, exporter and texture |
| Readable original shader | [source/tape-shader.js](source/tape-shader.js) | Unmodified selected Events 03C shader |
| Readable original composition | [source/study.js](source/study.js) | Original layout, type, density and grain logic |
| Original exporter | [source/export-vhs.swift](source/export-vhs.swift) | Original WebKit/AVFoundation 24-fps export implementation |
| Original generation prompt | [source/texture-generation-prompt.txt](source/texture-generation-prompt.txt) | Full exact prompt for the texture |
| Current adaptation | `preview/splash-vhs/tape-shader.js` and `preview.js` | Object-relative tracking plus exact artwork input |
| Saved preview videos/stills | `preview/splash-vhs/media/` | Review artifacts; not app resources |
| Hash manifest | [assets.json](assets.json) | File integrity, provenance and location checks |

The media already in the repository is referenced directly instead of duplicating
large videos under another name. The two new preview videos are stored alongside
the study. “Save preview videos & stills” records local canvas output; no external
service or generation credits are involved.

## Portable application brief

> Use Astir's approved Events 03C analog tape material and timing. Keep the supplied
> artwork and glyphs exactly as supplied. Composite the artwork into the original
> tape field, apply material wear to the artwork itself, then pass the composition
> through the recorded signal: luma/chroma separation, registration delay, sparse
> flecks, irregular density loss and short horizontal tracking tears. Anchor the
> hue to the asset's existing palette. Make actual object edges and interior rows
> visibly displace during faults. Use the same texture in the quiet and moving
> states. For a brief launch, choose a short passage around an existing strong
> fault rather than inventing a different animation. Keep forms and navigation
> steady. Supply a static material rendition and a review video. Do not replace
> fonts or redraw the Astir logo.

See the two detailed briefs for exact parameters, timing tables, acceptance
criteria, implementation constraints and failure patterns.

## Adoption boundary

This branch changes only the study and documentation. Native integration,
performance acceptance and release adoption require a later explicit decision.
The existing app timing, account logic and UI assets are untouched. A browser
study is evidence of visual direction, not proof of iOS frame pacing or readiness.
