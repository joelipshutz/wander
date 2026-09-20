# Origins and decision history

This is a curated design record, not a raw chat transcript. It separates the
source direction Joe selected from proposals still under review. Dates below
follow the local Pacific dates used in the original study; the generated asset
was created just after midnight UTC on September 18, which was September 17
locally.

## 1. The initial need: a coming-soon surface

The September 16 discussion asked to expose Events as a coming-soon tab with
flickering text and an Ocean Park identity. The wording used “retro TV” and an
imperfect neon-like rhythm. The discussion explicitly rejected flickering the
entire app. The motion belonged to a decorative surface, with app navigation
remaining usable and stable.

The next exploration was intentionally a motion study, not an integration. Joe
wanted the treatments inside separate mocked app frames, with Events in the
middle of a five-tab glass bar, on black in either light or dark appearance.
The title should be Coming Soon, without an Astir wordmark added to those Events
frames. That Events-specific composition constraint does not prohibit the
actual Astir logo in the launch or account surfaces now being explored.

## 2. Looking at references before inventing a style

The earlier chat assembled four references:

| Reference | What was being explored |
|---|---|
| [Glitcholette](https://padschneider.webflow.io/project/glitcholette-motion-font) | Individual-letter timing errors and glitches |
| [Radiate](https://animography.net/products/radiate) | Imperfect neon ignition and brightness flutter |
| [VHS Nostalgia Typography — Luke Edom](https://vimeo.com/60692354) | Soft analog recording, worn tape, uneven typography and tracking |
| [Indie](https://animography.net/products/indie) | Handmade irregularity and mild wobble |

These links are historical references, not a claim that their current pages or
licensing were rechecked for this library. The library contains no downloaded
Vimeo footage or third-party motion-font assets. The locally preserved Events
film and its original code are the reproducible source for the Astir treatment.

Joe singled out the rougher VHS section around **0:45–0:50** and the full
composition around **1:12–1:18** in VHS Nostalgia. He wanted a background that was
not perfectly digital black, slight pixelation, imperfect foreground ink,
reused-tape damage and a composition that felt very close to that reference.

## 3. Composition and font exploration

Two arrangements were compared:

- The whole phrase, COMING / SOON, degraded together.
- COMING and SOON alternating every two seconds.

The whole-phrase composition became the selected app export. It uses a pale
vertical bar and a small three-line caption: **AN / OCEAN PARK / EXPERIMENT**.
The big title is two lines with natural glyph proportions. Forced horizontal
compression from an earlier version was removed.

The original reference did not identify its typeface. The study used local
`HelveticaNeue-CondensedBlack` as a visual approximation, with fallback faces.
It was never established as an exact identification of the reference font.
The caption used a heavy italic sans treatment. None of this authorizes
substituting the splash wordmark's serif outlines.

## 4. Generating the raw field

One unlettered dark tape texture was generated with **Seedance 2.5**: eight seconds,
9:16, 1080p, no audio and no reference media. The exact request is preserved in
[source/texture-generation-prompt.txt](source/texture-generation-prompt.txt).

It asked for dense low-resolution luma grain, muted dirty chroma speckles, fine
horizontal streaks, irregular brief tracking ripples and full edge coverage.
It excluded cameras, zooms, devices, frames, lettering, graphics, light beams,
glow, smoke, clouds and lens effects. The foreground title was not generated;
it was composed separately so its layout stayed controllable across phone sizes.

The original study recorded **72 credits**, with balance 1,138 → 1,066. Later
procedural revisions and this library consumed no additional generation credits.
That accounting is preserved from the earlier record; it is not a new account
balance check. Provider account IDs, signed URLs and session data are not needed
for reproduction and are deliberately omitted here.

## 5. Three degrees of degradation

Revision 3 held the composition constant while changing wear:

| Candidate | Damage parameter | Character |
|---|---:|---|
| 03A — Light wear | 0.23 | Softer ink, fine grain, minor timing errors |
| 03B — Heavy wear | 0.62 | Chroma bleed, uneven flicker, bent edges and tracking |
| 03C — Near failure | 1.00 | Stronger dropout, smeared ink and unstable scan lines |

The assistant initially suggested 03B as a readable starting point. The durable
selected-study README records **Joe selected 03C Near failure**. The assistant's
suggestion is not the approval.

The selected refinement (revision 4) removed hue rotation and title color
contamination, kept a fixed faded Signal orange, reduced continuous sideways
jitter, added sparse speckles and retained three stronger short tracking faults
per eight-second cycle. This final refinement is what shipped as the Events
film and is the authority for “same aesthetic.” Earlier rainbow/noisier variants
remain historical exploration rather than interchangeable defaults.

## 6. Exporting and integrating Events

The selected composition was exported at 24 fps into an eight-second silent
H.264 movie. The app rendition is **720 × 1560**, 2,253,389 bytes; a **1080 × 1920**
clean reel master was also exported. A poster frame handles immediate display
and Reduce Motion. The complete source archive remains in
`docs/designs/events-coming-soon/render-source.zip`.

Events displays the precomposed movie through a native AVPlayerLayer. It does
not run the browser shader live. Its native controls and tab bar are separate.
The existing implementation notes describe playback gating, poster display,
background pausing, teardown and responsive cropping. Those runtime requirements
should be carried forward when adapting this visual language elsewhere.

The same original unlettered texture was later reused by onboarding. Onboarding's
native foreground treatment translates some effects into Canvas row slices and
color-multiplied bleed. That is an implementation approximation, not the exact
original YIQ shader. Similar parameter names alone do not guarantee parity.

## 7. September 19: first splash study

Joe asked to see the launch splash with the same Events VHS feel, emphasized
heavy distortion during the short opening, and explicitly preserved the font.
The study was created on **`codex/splash-vhs-preview`**, as a browser-only draft
PR (#686). It preserved the original PNG and applied the tape treatment with
additional early fault timing.

The first study concentrated several density dropouts and short tears near the
start. A consequence was that the image could become very dim while a fault was
happening; full-screen fault placement could also miss a small logo. Neither is
a reliable way to demonstrate object damage.

Joe subsequently asked whether it was on main and explicitly said not to put it
there. The PR was verified open, draft and unmerged before this second pass.
There are no native app changes in this study.

## 8. September 20: shared material and object damage

Joe clarified that the **objects themselves must distort** like Events, rather
than simply having moving texture around them. He also observed that the logo
on Create Account did not feel like the same material. He requested the source
videos and both detailed reusable briefs, including how the direction evolved.

The second study therefore:

- Keeps the exact original splash bitmap and font outlines.
- Uses the actual approved Events film beside both proposed applications.
- Restores the original density sequence and tracking event windows.
- Starts at source 6.60 s for an immediate, legible strong tear.
- Places the damage band relative to each artwork's bounds, making the A,
  STIR and plinth participate at both sizes.
- Separates original, static material and moving signal modes.
- Adds frame inspection, a visible tear-frame control, material close-ups and
  saved videos/stills.
- Preserves the original shader and composition separately from the adaptation.

This second pass remains a proposal. Its account layout is a visual illustration;
its decorative logo uses the shared renderer. It has not been installed into the
native account screen, merged or released.

## Evidence trail and future editing

The source discussion was read from the Codex chat titled
**[TEST] REC-542 Noninteractive waitlist confirmation [In Pro…]** (the tool's
verbatim title), thread `01a0b14b-fb09-7bf2-a1f3-4dab4e2fa600`.
The selected-study readme and renderer originally lived at workspace-relative
`astir-motion-study/2026-09-17/vhs-study/`. Their shipped archive is retained in
this repository, so future agents do not need that machine path or the chat to
reproduce the selected look.

When changing the style, record whether a change is a new proposal, Joe's explicit
selection, or an implementation approximation. Keep original source files
unchanged and put adaptations elsewhere. Update the asset manifest after actual
exports. Do not mark a proposed splash/account pass as approved merely because
the Events treatment was approved. Do not merge this branch without Joe's
explicit instruction.
