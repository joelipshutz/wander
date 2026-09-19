# Film refinement: direct Events 03C reference

Joe's T21 correction: more imperfection, distortion and both the little and occasional bigger failures from the Events asset. Make C's "Connect with your" italic. Keep this as the opening exploration; N08-N12 follows its checkpoint.

## What the actual reference contains

The selected revision is **03C Near failure, revision 4**. Source was read from `astir-motion-study/2026-09-17/vhs-study/README.md`, `study.js` and `tape-shader.js`, and compared with decoded frames of the actual bundled `events-coming-soon.mp4`.

- Fixed faded Signal `#d77554`, dark field `#0c1010`. The selected revision explicitly removed hue rotation; its hue should stay recognizable.
- A visible warm smear outside the lettering, delayed color registration and slightly soft edges.
- Fine moving grain plus sparse irregular light/dark flecks and small horizontal losses in the ink. Wear extends through lettering as well as the background.
- Quiet line-timing errors between larger failures; not a uniform constant sideways shake.
- Three stronger short tracking faults per eight-second loop, with displaced horizontal bands, vertical slips and head-switching noise.
- A separate authored sequence of short signal-density dips, recoveries and near-dropouts. These make the title feel unstable without permanently losing the words.
- An italic pale caption. C's stable Connect with your line now takes that italic role; the changing words and benefit headings retain the heavy condensed face.

## Why the first onboarding film felt too clean

It reused the correct unlettered video and added a scanline/dust mask, but there was no spatial displacement of letter rows, almost no real signal dropout, and no larger tracking episodes. Adding more uniform background grain alone would not close the gap.

## Native translation

The refined Swift renderer resolves the existing native SwiftUI text into a Canvas symbol and draws displaced rows. It adds warm smear, irregular wear and the reference's timing for bigger failures. The real Map/activity preview has small intermittent registration slips. A decorative overlay adds sparse picture noise; controls keep their native hit areas and actions. There is no video of the controls or web renderer inside the app.

Pause/background/account entry stop motion. Reduce Motion uses static, undistorted ink. The first film pass remains available in `opening-film-comparison-v1.html`; A remains the approved baseline. The comparison page includes the actual Events loop as an expandable reference.

Validation and capture status are recorded in T21 in `../TASKS.md`; this design note itself is not proof of a passing build or final visual selection.
