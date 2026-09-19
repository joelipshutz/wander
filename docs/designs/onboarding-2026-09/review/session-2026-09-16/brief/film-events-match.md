# Film C — original Events motion, app palette

September 18, 2026. T26; supersedes T25 account-heading animation.

Joe: “Look back at the OG film from the events tab. I want it to be like that same animation … the way that it … distorted things was really nice … create your account should not have the animation. It should just be the [Astir] on the create account screen … keep this archive.”

## What changes

- Reuse the selected Events 03C / revision 4 film as the reference, including small continuous errors and the occasional stronger line distortion. Keep app Signal/Ink colors, C's condensed type and italic Connect with your, approved copy and slide timing.
- Use one native film clock across the opening, retained outgoing/incoming scenes and account artwork. Newly appearing text joins the existing phase instead of starting its own distortion cycle. Pause/background freezes that phase; Reduce Motion stays undistorted.
- Use screen coordinates and the reference's 720-pixel raster scale for line errors, fine scan wear and delayed color edges. Remove the coarse local-label scanline mask and repeated local wear pattern.
- On account entry: animate the transparent Astir statue/letters/bar only. Create your account, supporting text, fields, providers, links and the solid Signal email button remain still. Retain the still textured background.

## Reference and archive

The original renderer is in `astir-motion-study/2026-09-17/vhs-study/{study.js,tape-shader.js}`. The selected movie is copied unchanged at `native-captures/events-reference/events-coming-soon-03c.mp4`. It has three short tracking windows per eight seconds and separately authored 12-second type-density failures. This native Canvas interpretation does not claim pixel identity with the pre-rendered WebGL movie; it shares its timing and spatial formulas without baking tappable UI into video.

T25 remains at [App-palette archive](../opening-film-app-palette-archive.html), source `945c280`, git tag `archive/rec-529-film-app-palette-2026-09-18`, and an independent archive manifest. Older warm C remains [here](../opening-film-archive.html?v=1e27cb4).

## Verification and delivery

**Complete at source `1155ca4`.** 26 focused native checks passed (24 unit, two UI journeys covering both film treatments). The 53.6-second full native C recording includes a ten-second account hold. Two PNGs 1.25 seconds apart show 52,523 changed logo pixels, zero changed heading/control pixels, and exact solid Signal on the email button. [Open the new HTML study](../opening-film-events-match.html?v=1155ca4), with the original Events film alongside it. Browser playback, scene seeking, account looping and TV view passed with no console/media errors. The existing iPhone 16e was shut down after capture. This is compact-simulator evidence, not a new physical-device performance assessment. N09/setup and Ryan's NUX remain outside this revision. Local exploration only; no merge or publication.
