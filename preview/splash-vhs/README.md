# Astir VHS splash preview — REC-557

Branch-only browser motion study requested by Joe, September 19, 2026. No
native app code, splash readiness gates, fonts, or bundled assets are changed.

From the repository root, run `python3 -m http.server 65363 --bind 127.0.0.1`
and open <http://127.0.0.1:65363/preview/splash-vhs/>.

The default 1.8-second preview repeats with a 0.65-second hold. Replay, pause,
single playback, 1.2/1.8/3-second timing and compact/standard/large viewports
are available. Original and Coming Soon provide direct comparisons. These are
study durations; production launch timing remains untouched.

## Preserved sources

- The image is loaded directly from the existing `AstirLaunchWordmark` asset,
  preserving the statue, all glyphs including ONENESS, spacing, color and
  proportions. No text is re-typeset and no font is loaded for the artwork.
- The PNG SHA256 remains
  `ca42b250579fcd9571ba05520a4940ef8148a199e97aa6aeb16e918ec67e9ae8`.
- The texture is the bundled `onboarding-film-texture.mp4`, the same unlettered
  Higgsfield source used by Events; no new generation or credits.
- `tape-shader.js` derives from the approved 03C renderer in
  `docs/designs/events-coming-soon/render-source.zip`, also retained in the
  workspace's `astir-motion-study/2026-09-17/vhs-study/`.
- The earlier chat's inspiration is Luke Edom's VHS Nostalgia Typography,
  especially the rough section near 0:48 and the composition at 1:12–1:18:
  <https://vimeo.com/60692354>. No original reference footage is included.

## Adaptation

The selected source's YIQ chroma delay, grain, speckles, scanline wear,
head-switching noise, luminance dropout, horizontal tears, shadow field and
texture composite are reused. Hue rotation stays disabled. The only shader
addition is an optional `launchFault` uniform: it places tracking hits at
0.08–0.29, 0.46–0.59, 0.86–1.05 and 1.31–1.44 seconds through the central
wordmark. Original Events timing remains the renderer's default when omitted.
Density interruptions are moved into the same brief opening. The artwork uses
the native `min(460, width - 32)` width and `1600 / 764` aspect ratio.

Reduced Motion starts with static wear and disables moving playback. Hidden
pages pause the texture and reference film. A missing WebGL context shows the
original image with an explanatory status. Media is silent and local.

## Verification

- Both JavaScript files pass `node --check`; `git diff --check` passes.
- Original asset hash matches the approved source.
- Browser visual checks cover the standard and compact compositions, replay,
  pause, original comparison, and playback of the actual Coming Soon film.
- Native iOS integration and device performance are outside this motion study.
  Keep the branch unmerged pending Joe's visual direction.
