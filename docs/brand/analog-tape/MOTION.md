# Motion and signal-failure brief

## Current splash/account revision 4 — September 20, 2026

Joe clarified that “half a second” meant **move the liked bend earlier in the
order**, not extend its duration. Revision 3's stretched event was an assistant
misinterpretation and is superseded. The flicker removal remains requested.

- Use elapsed time from first splash frame, beginning at **0.00 s**.
- First fault: **0.50 ≤ t < 0.70 s**. The original 0.20-second waveform runs
  at its original speed: `faultTime = 1.68 + (elapsedLoopTime - 0.50)`.
  There are five event samples at the intended 24 fps (0.500–0.667 s).
- “Show a tear” holds **0.60 s**, mapping to waveform 1.78 s: the same shape
  previously shown at revision-3 source time 1.80 s.
- Later faults retain elapsed 4.55–4.71 and 6.76–7.01 s. Their brightness
  collapse remains removed. The eight-second reference movie is independent
  of the splash clock and paused by default; its archived bytes are unchanged.
- Artwork opacity is constant **0.94**. Do not execute the original density/
  dropout sequence, shader luminance pulse or event-band darkening.
- Background texture is fixed at source 0.40 s; coarse grain, fine grain,
  flecks and streaks use fixed seeds. Only geometry and registration move.
- No whole-logo blink, random brightness refresh or artificial minimum hold.
  Row displacement and fine timing error are intentional geometric motion.
- The default 1.2 s preview and 0.8 s quick launch include the early tear.
  The 0.35 s case deliberately misses it. Never stall a real launch to play it.
- [Native measurement and integration timing](SPLASH-TIMING.md): three launches
  of installed simulator build 177 showed about 2.79–3.38 seconds. This is a
  baseline, not a fixed native duration or proof of current-main performance.

The following sections preserve the original Events recipe and v2 rationale.
Where those differ, the current revision above governs splash/account playback.

## Intent

Use the movement of the approved Events 03C film. It behaves like a compromised
recording that mostly holds together, then briefly fails to track. The object
itself is the recorded signal: a horizontal slice of a letter, the statue or the
plinth moves out of registration. The motion is not just a flickering layer of
noise in front of an otherwise clean logo.

Every quiet interval keeps the material described in [STATIC-TEXTURE.md](STATIC-TEXTURE.md).
Motion changes where the signal is sampled and how much density survives. It
does not replace the artwork with another drawing or animate the letter shapes
as vector paths.

## Rhythmic character

The chosen revision combines low continuous instability with occasional forceful
faults. Joe chose 03C / Near failure, then the selected refinement kept the orange
stable, reduced constant sideways jitter, added sparse speckles and retained
three strong short tracking faults in the eight-second loop.

Readability returns between failures. Use interruptions measured in frames,
not a smooth sine-wave bob across the entire logo. Do not make the whole screen
breathe in and out, add a long fade-in, or extend the launch gate to show the film.
A short splash must encounter meaningful damage near the beginning.

## Source clocks and exact timing

The original export evaluates the composition at `t = frame / 24` for 192 frames.
03C uses two related clocks:

- Foreground density: `signal(t + 0.23)`, on a 12-second source sequence.
- Tape shader: `t + 0.17`, with an 8-second tracking cycle.
- Texture source: `t % 8` in deterministic export.

The delivered movie is an eight-second render. Its loop repeats those rendered
frames; it does not continue the 12-second density sequence indefinitely. A live
implementation must deliberately choose whether to match that eight-second
movie or the longer procedural clock. For Events matching, repeat the same
recorded eight-second window.

### Tracking failures

| Shader-clock interval | Visible source-film interval (`t`) | Approximate duration |
|---|---|---|
| 1.68–1.88 s | 1.51–1.71 s | 0.20 s / about 5 frames |
| 4.72–4.88 s | 4.55–4.71 s | 0.16 s / about 4 frames |
| 6.93–7.18 s | 6.76–7.01 s | 0.25 s / about 6 frames |

These are hard finite event windows. Inside a window, the displacement oscillates
rapidly and can change direction; it does not make a long eased slide. The actual
24-fps export quantizes the boundaries.

### Foreground density sequence

The following intervals are in the **density clock**, before subtracting 0.23 s
to locate them in the exported video. Outside them, density is 0.94.

| Start–end (s) | Density |
|---|---:|
| 0.72–0.81 | 0.35 |
| 0.81–0.86 | 0.94 |
| 0.86–0.99 | 0.16 |
| 1.04–1.13 | 0.58 |
| 3.20–3.28 | 0.12 |
| 3.31–3.45 | 0.43 |
| 5.74–5.88 | 0.35 |
| 5.88–5.94 | 1.08 |
| 5.94–6.08 | 0.18 |
| 8.64–8.76 | 0.38 |
| 8.79–8.91 | 0.06 |
| 9.00–9.13 | 0.51 |
| 10.47–10.60 | 0.28 |

The last four entries describe the reusable procedural source, but are outside
the selected eight-second movie's composition window. Do not silently fold those
entries into the delivered Events loop and call it an exact match.

## Signal components

### 1. Fine row timing

At every rendered frame, the shader generates a small horizontal error per
raster row. The time seed steps at 24 Hz. With `d=1`, the fine term has amplitude
`0.36 / resolution.x` before centering the random value, plus two low-amplitude
wobble terms (`0.00043` and `0.00010`). This gives slight life without a constant
large side-to-side shake.

### 2. A wandering damage band

A deterministic noise sample changes its target every half-second:
`center = 0.16 + 0.69 * noise(floor(shaderTime * 2), 2.8)`.
The original screen band has width `0.08` in normalized y coordinates, with a
soft center-to-edge falloff. Its vertical placement is not perfectly symmetric
or locked to the center of a letter.

### 3. Horizontal tears and vertical slip

During a fault, the row tear is
`event * damageBand * 0.098 * sin(shaderTime * 41)` at 03C strength. Because the
shader samples displaced source pixels, the visible drawing shifts in the
opposite direction to the source-coordinate offset. Preserve that relationship
when porting to a drawing API.

The original also adds a brief vertical sample slip of
`event * 0.011 * sin(shaderTime * 31)` of screen height. These ingredients act on
the composited recording. The layer's layout bounds do not animate or relayout.

### 4. Chroma registration and density collapse

The usual 6.6-pixel chroma delay gains up to another 9 pixels inside an active
band. The same band reduces luminance by up to 58%. Foreground density failures
are a separate clock, so brightness and geometry do not always fail together.
Do not tie every strong tear to a near-black flash: then the torn object becomes
invisible precisely when its geometry should be seen.

The shader also applies a mild 17.4-radian/second luminance pulse, at amplitude
0.07 for 03C. This is one layer of the source; it is not the main motion.

### 5. Dropout streaks, flecks and bottom-edge noise

Sparse horizontal lines and short dusty spans appear at 24-fps seed intervals.
Small bright and dark flecks are spread irregularly. Head-switching noise is
concentrated near the bottom edge of the original recording. Do not distribute
every artifact evenly or add a full-screen white flash.

## Scaling to a logo

Events' title occupies a large fraction of its screen. The account logo is much
smaller. Applying the original wandering band in full-screen coordinates can
miss the logo entirely and leave only background noise. That was a practical
problem in the first splash study.

The v2 study preserves the original event windows, waveforms, density sequence,
chroma algorithm and material, but expresses the damage band's position in the
**artwork's normalized bounds**:

- The random band center remains `0.16 + 0.69 * noise(...)`.
- Band width is 0.20 of the artwork artboard, approximately matching the original
  band relative to Events' title composition.
- Horizontal tear amplitude scales with artwork width, retaining the source's
  0.098 coefficient and waveform.
- Vertical slip scales with artwork height, with a 2.5 conversion factor to keep
  the fault visible on a shallow wordmark.
- The whole raster participates: photographic A, letters, base and inscription.
- Actual field pixels remain under the artwork, avoiding a rectangular animated
  sticker or a different black patch behind the logo.

This is a documented spatial adaptation of the approved style, not a claim that
Astir's different-shaped logo can be pixel-identical to the Events title. The
proposed adaptation itself still needs Joe's visual approval.

## Short splash timing

For the new study, begin at source-film time **6.60 s**. The strongest existing
fault then starts 0.16 s after presentation and lasts to roughly 0.41 s. The
artwork remains available during the failure because this passage does not
coincide with the deepest density blackout. The following quiet frames restore
legibility. A 1.8-second option shows this passage and the loop return.

This changes only the starting phase of a decorative animation. It must never
change app-readiness checks, map loading, authentication, a minimum launch
hold, networking or the moment the app becomes usable. The study's 1.8-second
cycle is a visual sample, not a proposed production loading delay.

## Account-screen application

Use the same raster, material and failure recipe at its existing smaller width.
Keep title text, form fields, Apple/Google buttons, links, focus and accessibility
steady. Input should remain native; the movie/canvas is decorative. An account
screen is not an excuse to put a recorded form over live controls.

For this branch, the account composition is a browser illustration of the native
layout. The logo effect is the real shared renderer. The UI around it is not a
functional login and is not a pixel-accuracy claim about the shipping layout.
The current native approximation uses Canvas row slices and color-multiplied
bleed; it does not execute the original YIQ shader. Native parity needs a later
implementation and visual comparison, rather than assuming the algorithms match.

## Playback, accessibility and implementation

- Target the source's 24-fps cadence, not a faster glossy 60-fps glitch treatment.
- Use one shared clock when objects should feel recorded together.
- Pause both media and decorative rendering when the page/view is hidden,
  inactive, offscreen or superseded by another surface.
- Reduced Motion uses a static material rendition. Merely freezing the clock
  while continuing to regenerate noise is still animation.
- Preserve a still fallback before the decoder/rendering surface is ready.
- Keep source media offline and silent, with no audio-session changes, controls,
  PiP or tap affordance inside the production composition.
- Do not drive whole forms or app state at 24 Hz. Limit updates to the decorative
  surface, and validate on the actual lowest target device before adoption.
- For alpha assets, preserve the entire artboard and layer registration. Never
  crop the glyph mask independently from the image.
- A prerecorded movie, a GPU shader and a native row-slice approximation have
  different tradeoffs. Match visual output first, then measure decoder startup,
  frame pacing, memory, energy and interaction. Do not claim performance from
  this browser study.

## Review and deliverable checklist

Watch Events and the proposed surface together. Pause at source ~6.92 s and
inspect whether letters, sculpture and plinth visibly tear. Then inspect the
quiet 0.40 s material frame. Check the complete loop and the short launch
passage. Review at both native display size and a magnified crop.

Deliver the preserved input, material still, motion video, exact source timing,
parameter changes, file hashes, implementation source and known platform limits.
The frame slider should make the shape deformation apparent without needing to
catch a one-frame fault by eye. Never approve this style solely from a screenshot
of the background texture.
