# Static texture and material brief

## Intent

A frame should feel physically recorded, worn through repeated playback and
slightly compromised by the transfer back to digital. Even with every clock
stopped, the typography and sculpture must belong to the same imperfect recording
as the background. The treatment should read as Astir's Events film immediately.

“Static material” here means a still picture of worn tape. It does not mean
continuously animated television snow. Grain may be present, but its coordinates,
brightness and color must stop changing in a static or Reduce Motion presentation.

## Nonnegotiable source constraints

- Use the exact supplied artwork. Do not regenerate the sculpture, retrace the
  wordmark, substitute a font, squash the glyphs or change tracking to make the
  treatment easier.
- Use the same relative composition and intrinsic ratio. The launch artwork is
  1600 × 764. Its native width is `min(460, availableWidth - 32)`; the account
  header's image frame is 172 points wide before its existing padding.
- Preserve the cream lettering and statue, the orange plinth, the ONENESS detail,
  and all transparent counters. Events uses faded Signal `#d77554`; the splash
  keeps its original palette. Shared texture does not imply recoloring every
  brand asset orange.
- All visible art receives the material: statue, STIR, plinth and inscription.
  The old STIR-only glimmer mask is not an adequate mask for this effect.
- The phone frame, system indicators, form fields and navigation are outside the
  decorative material pass. Existing live UI retains its contrast and hit areas.

## Visual specification

### Field

Use the existing unlettered tape video or a fixed frame from it. It is a flat,
nearly black charcoal/green field, with low-resolution luminance grain, sparse
colored flecks, horizontal damage and soft uneven density. It fills the viewport
edge to edge. It is not a photographed television, a CRT bezel, a light beam,
smoke, a space scene or an atmospheric cloud animation.

The original generation requested black levels around 4–9%, but that was a prompt
intention, not a measured display calibration. The compositing recipe below is
the reproducible source of truth. Do not lift the final black level by an arbitrary
percentage just to make the grain obvious in a screenshot.

### Object surface

Keep the object's own light/shade structure while giving flat regions the same
imperfect density as the title in Events. Noise must be composited across the
image after the artwork is drawn, so it marks the cream letters and orange base
as well as the empty field. The material should remain perceptible inside large
letter strokes when the video is paused.

The photographic statue already contains detail; retain that detail. Do not
replace it with procedural stone, simplify it into a flat silhouette or add a
second incompatible crack pattern. The same recorded wear goes over the existing
photograph and the vector-like letters.

### Edges and chroma

Analog registration is soft and directionally smeared. Preserve readable edges,
then add a restrained offset tail. The result is not a uniformly defocused logo.
The Events renderer separates luminance from chrominance, keeps the luminance
sample relatively sharp and takes four displaced color samples. This is the
reason the material stays readable while feeling damaged.

Stay anchored to the input colors. The selected revision removed broad hue
rotation and color contamination from the title. Dirty green/blue/magenta traces
may remain in the underlying source texture; animated rainbow logos were not the
selected direction.

### Specks, scan wear and gaps

Flecks are sparse and uneven. Small holes and dusty traces break the otherwise
clean recording. Horizontal wear should be fine enough to avoid looking like
uniform one-point black grooves cut through every glyph. Avoid a regular
screen-door or perfect halftone pattern. Do not add crisp digital rectangles or
random RGB blocks.

## Exact selected composition recipe

The preserved [composition source](source/study.js) is authoritative. At damage
`d = 1` (03C), the relevant operations are:

| Stage | Selected value / operation |
|---|---|
| Base fill | `#0c1010` |
| Texture | Cover-cropped, alpha `0.78`, `brightness(0.88) saturate(1.15)` |
| Uneven field | Radial center `rgba(25,36,29,0.25)` to edge `rgba(0,0,0,0.48)` |
| Coarse grain canvas | 180 × 320, nearest-neighbor scaled to composition |
| Grain RGB construction | Shared random luma in 0–110, additional R/G/B ranges 22/26/24 |
| Grain beneath art | Screen blend, alpha `0.11` |
| Quiet art density | `0.94` before signal pulse |
| Original title shadow | Warm shadow alpha `0.38`, blur `1.5` logical units, x offset `0.4` |
| Original caption/bar shadow | Pale green/gray shadow alpha `0.33`, blur `1`, x offset `0.5` |
| Grain over complete image | Multiply blend, alpha `0.23` |
| Fine shader grain | Noise centered on 0, amplitude `0.031` total |
| Fine scan wear | Luma attenuation up to `0.10` |
| Normal chroma delay | `6.6` pixels at the canonical 720-pixel raster |
| Chroma samples | Offset/weight: `1/0.44`, `2.3/0.25`, `-0.55/0.20`, `3.8/0.11` |
| Bright speck threshold | Noise ≥ `0.9984`; addition `0.38` |
| Dark speck threshold | Noise ≤ `0.0013`; multiply down by up to `0.70` |

The shader works in RGB/YIQ and clamps the final RGB values. Noise is procedural;
film encoding will change individual pixels. These parameters reproduce the
selected algorithm, not a claim that every platform's decoded raster is bit-exact.

For the logo adaptation, the original raster is drawn where the original
composition draws the title. The complete image still receives the final wear.
The foreground shadow is applied to the raster silhouette, never to a new text
layer. Alpha counters retain their shape, subject only to the signal's sampled
registration.

## Building a static deliverable

1. Load the exact artwork and original texture locally.
2. Choose a quiet source frame with no active tracking tear or deep density loss.
   This study uses source time **0.40 s**: type clock 0.63 s, shader clock 0.57 s.
3. Render the full material pipeline once, including grain and registration.
4. Hold the resulting pixels. Do not keep a hidden movie or random generator
   ticking behind the still.
5. Save a full composition and a close-up of the actual logo. Record the chosen
   source time, resolution and asset hashes.

The original renderer's `still` flag disables several moving artifacts. For a
literal frozen material sample, this study instead evaluates an ordinary quiet
frame once and holds it. This preserves the exact static flecks and registration
seen in the moving version. Both approaches can be accessible, but they are not
pixel-identical and should not be mislabeled as such.

## New texture generation, only if required

The existing clip is preferred. The exact original prompt is preserved at
[source/texture-generation-prompt.txt](source/texture-generation-prompt.txt).
Original generation: Seedance 2.5, 8 seconds, 9:16, 1080p, no audio, no reference
media, no camera motion. That run cost 72 credits according to the original
study. Reusing the existing asset and procedural renderer costs no new generation
credits.

If making another texture, keep lettering out of the generator. Generate the
unlettered field only, then composite exact approved assets. Match density at the
loop boundary and inspect the full clip. A prompt request for a seamless loop is
not proof of a seamless result.

## Static acceptance review

- A held frame looks related to Events before anyone presses Play.
- Texture is visible on the object's interior, not just in the background.
- Original glyphs, counters, spacing and sculpture identity can be recognized.
- The art is not darkened so much that the treatment only reads as dimming.
- Fine edges feel slightly recorded and smeared without turning all text blurry.
- The palette stays anchored to the source; the orange is not cycling through hues.
- Cream and orange areas share the same material scale at splash and account sizes.
- Real UI and its text remain legible. The account form is not part of the noise
  mask merely because its logo is distressed.
- Reduced Motion produces a stable frame with no flicker, grain refresh or drift.
