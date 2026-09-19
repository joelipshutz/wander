# Astir onboarding recording — review package

Open [the review room](http://127.0.0.1:8766/session-2026-09-16/) or [the motion lab](http://127.0.0.1:8766/session-2026-09-16/motion-lab.html). The original complete Swift board stays at [the starting page](http://127.0.0.1:8766/).

Start with TASKS.md after any context reset. It maps 67 source items into 33 workstreams, with review status separate from native implementation. transcript-audit.md explains the deduplication and unresolved choices; seven source files and their hashes are retained under transcripts/.

## Recording controls

- Drag the canvas to pan. Pinch or Command/Ctrl-scroll to zoom; + and − also work.
- Click a screen in the left outline. Present on TV enlarges the screen and copy.
- In TV mode, left/right changes the screen; up/down steps through numbered lines. Say a reference such as **R07.A.01** aloud.
- Click a line on the board to edit, or double-click a line in TV mode. Drafts and discussion notes save in this browser.
- Choose this for next pass records a review preference; click it again to clear. It does not change the app or mean the variant has shipped.
- Export decisions writes all variants, notes, choices and stable line IDs to Markdown. Export before handing the session back or moving browsers.
- Profile fields and sample Follow/Search controls are local demonstrations. Photos remain local preview object URLs. No profile, contact, invitation or follow is written to a real account.
- Motion studies start paused, have Next/Play/Pause/Replay and Reduce Motion. Device demos are storyboards, not real hardware footage.

## Source and build

revisions.json is the copy source. review.template.html is the canvas/presentation source; build_review.py packages it with the baseline index and source documents into index.html. The HTML uses local sibling images, so retain this folder alongside the parent screenshots/ and brand-assets/ when moving it. motion-lab.html is standalone code using the same image folders. The original parent index.html remains an embedded-image standalone baseline.

Copy and UI studies are review proposals. Native implementation remains in TASKS.md, especially matching contacts to Astir members, mandatory profile photo, replacing/removing existing NUX, first-use eligibility, permission state handling, and actual device recordings.
