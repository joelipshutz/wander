# Film C revision — Astir palette and account hero

## September 18 review direction

Scope: opening slides and Create your account. This changes course from N09 temporarily; N08 profile / N09–N12 setup and Ryan's NUX are outside this revision.

1. Keep C's exact fonts, wording, reading holds, slide transitions, static, flicker, small wear and occasional larger distortion.
2. Use the app palette: Signal **#F05A3C**, Ink **#141714**, and the existing Paper/text tokens. Retain the custom film background texture. The warmer Events palette stays in the Events experiment.
3. The Astir statue, letters and Signal bar receive the strong native VHS treatment. The logo PNG already has transparency; remove the separate dark backing so its background matches the surrounding custom field. Apply to onboarding's launch artwork and account hero; the existing compact masthead's text receives the same effect before its material background is drawn.
4. At Create your account, only the logo and heading animate. Keep C's fonts. The background remains a still of the custom texture; the subtitle, providers, email field, legal text and all actions are normal native UI. Continue with email is solid app Signal, with no film modifier or overlaid film layer.
5. Preserve continuous film motion through the earlier slide transitions. Next / Log in / auth controls stay live. Reduce Motion gives static undistorted artwork, and backgrounding suspends decorative animation.
6. Deliver one revised native C study, with explicit links to the previous studies. Existing archives and recordings are not overwritten. A remains the approved production opening; this is a local review revision, not a merge request.

## Source and preservation

- Current local branch: `codex/rec-529-film-app-palette` in `wander-native-onboarding-review`.
- Based on main `f3d9cb6` plus the four archived film commits; the N09 setup branch remains at `8051f8d`.
- Previous preferred C: [continuous-film archive](../opening-film-archive.html?v=1e27cb4).
- Previous motion pass: [before transition fix](../opening-film-comparison-v2.html).
- First film exploration: [first film pass](../opening-film-comparison-v1.html).
- New review: [Astir palette study](../opening-film-app-palette.html).

## Acceptance checks

- Build real Swift; capture full native opening and at least eight seconds on account entry.
- Confirm logo backing has no rectangular seam; inspect stable and distorted frames.
- Confirm Signal button interior stays #F05A3C and pixel-stable while hero changes.
- Run the existing native film interaction test through slide interruption, Log in, rapid Next, email, and verification/background recovery.
- Inspect compact and standard layouts where the existing devices are available; report any missing coverage.
- Verify HTML playback, seeking, account loop, archive links and media hashes.

## Completed native review

- Source **`945c280`**, branch `codex/rec-529-film-app-palette`, based on main `f3d9cb6` plus archived C.
- **24 tests passed, zero failures/skips**: 22 unit and two native UI tests. Both retained film styles complete automatic playback and keep Next, Log in, email and verification/background recovery functional.
- New [HTML study](../opening-film-app-palette.html?v=945c280) uses fresh full-phone Swift media, with an account-screen loop. It links the earlier immutable studies.
- Pixel evidence from two native screenshots 1.25 seconds apart: 99,631 changed hero pixels; zero changed control/copy pixels. Email button is exact app Signal #F05A3C. The decoded movie differs by at most one color level at the sampled button interior, as expected from compression.
- Full layout and account artwork inspected on iPhone 16e, iOS 26.3.1. No new standard-size/iPad or physical-device performance pass is claimed; the standard simulator was already in use elsewhere.
- Browser playback, seeking, account loop and TV view passed with no console errors. The owned compact simulator is shut down. No merge or release.
- Joe approved the one-time deletion of the inactive completed phone-build cache; evidence is `film-app-palette-cache-cleanup.json`. All source, archives and final test evidence are preserved.

Evidence: `native-film-app-palette.json`, `native-film-app-palette-tests.xcresult`, `native-film-app-palette-test-summary.json`, `native-board-qa/film-app-palette-report.json`, and `native-captures/film-app-palette/`.

To resume: read this brief and T25 in TASKS.md, inspect the source branch without overwriting N08–N12 work (`8051f8d`), and use the shared iOS build helper for any native changes. The capture and prepare helpers accept `--output film-app-palette`, `--treatment film-type`, `--account-hold 10`, and `--find-account`. Preserve prior media when making the next revision.
