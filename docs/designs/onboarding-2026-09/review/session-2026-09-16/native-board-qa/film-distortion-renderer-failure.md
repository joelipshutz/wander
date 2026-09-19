# Film distortion validation findings

1. First run: 24/25 tests passed. Film signup's email field remained non-hittable after the slide had landed. The full-screen decorative views were separate children of an implicit overlay container. An explicit ZStack with hit testing and accessibility disabled at the container fixed the regression. The unchanged tests then passed 25/25.
2. Full-speed capture at source `7d5cfeb` exposed a separate runtime crash about 2.3 seconds after launch. The 25 passing checks had exercised paused film controls, not a complete automatic film playback. Do not use those results as proof of live playback stability.
3. Crash evidence: `Wander-2026-09-18-070612.ips`, EXC_BAD_ACCESS / SIGSEGV on `com.apple.RenderBox.Device`. The stack starts in `RB::Filter::ColorMatrix::set_globals` and includes `BackdropColorMatrixItem::render`. The unsuccessful capture returned to Home rather than reaching signup.
4. Removed the AVPlayer surface's contrast/color-matrix filter and excluded the material-backed masthead from Canvas symbol filtering. Text distortion, italic C lead-in, density failures, tracking and decorative picture noise remain. Added a test that runs both film variants automatically through all scenes and requires the real account email field to become hittable.

Final outcomes belong in the latest native verification report. The failed capture/log are retained for diagnosis and are not published as a complete review video.
