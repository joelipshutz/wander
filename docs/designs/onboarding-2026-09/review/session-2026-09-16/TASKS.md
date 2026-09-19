## September 19 release/VHS checkpoint — T33 active

- Joe lifted the main hold: land current wind-cleaned 90.965-second video and selected native film C. Earlier TestFlight bump authorization remains active. Do not wait for a VHS selection. No Drive upload.
- VHS: three eight-second options complete at `founders-vhs-review.html`, original Events shader at 0.62 / 0.82 / 1.0. Zero generation credits. Corrected a WebKit frozen-input issue by decoding actual source frames. 192 frames per clip and identical cleaned AAC packets verified. Source/recipe/provenance saved.
- Native N08 optional photo, N09 Find places nearby, N11 headline only, V05 Instagram copy/icon centering implemented; actual native screenshots now on `device-onboarding-review.html`. Founders Play/Pause/Mute/background/Skip/end paths passed native UI tests on iPhone 16e. Current screen captures are c71aee6, not mislabeled as a later source.
- Main integrated at 1185c81, film C selected for production in a96f060. Final full unit + focused film/player UI suite running via managed helper (`native-release-validation.log` / `.xcresult`). No main push, version bump or TestFlight upload yet. Signed device build to follow.
- Reproducible archive publication: installing official Git LFS 3.8.0 for large historical media, preserve original bytes. Do not add oversized ordinary Git files. Update source-history bundle and verify portable server/checksums before push.
- Linear update was rejected by automatic approval review for external/private payload; no message sent. Separate short-update permission question remains unanswered. Do not bypass that rejection.

# Astir onboarding recording — task ledger

Source: Joe + Ryan review supplied September 16, 2026. This file is the durable restart point for the full transcript work.

## Active — land the current video; separate VHS clip explorations (T33)

Joe explicitly lifted the main hold: land the original/current wind-cleaned welcome video while preparing separate VHS explorations. **VHS options must not block main.** The earlier requested TestFlight bump remains part of the release work. Preserve the current copy and playback UI; a later selected treatment should be an asset replacement. Make at most three short clips using the original Events VHS reference: similar distortion/flicker, heavy and slightly lighter alternatives. Prefer deterministic reuse without Higgsfield credits; Higgsfield is authorized if needed.

- [ ] Finish native current-candidate validation and focused HTML/device review, land to main directly as Joe requested (no implementation PR), classify the direct push in the TestFlight manifest, and complete the previously requested release. Switch the selected film C to the intended release default; preserve normal account controls and Ryan’s NUX.
- [ ] Preserve/publish the complete reproducible process archive with a safe large-media strategy. No oversized ordinary Git blobs.
- [ ] Separately produce up to three short actual founders-video VHS samples from the Events reference, preserve cleaned audio/outtake, show comparison clips; do not hold the current-video landing for this choice.

Native verification: current source `c71aee6`; movie end and Play/Pause/Mute/background/Skip tests passed. Unit suite found only a stale N09 string expectation (old headline); updated to Joe’s exact new wording. N08–N12 capture inventory and photo-free journey still finishing. Signed generic-iPhone review build is queued after the tests.

## Active — decisions locked; combined Xcode device review (T32)

Joe confirmed **N08 profile photo is optional** and **N09 header is “Find places nearby.”** Keep N09’s existing body/privacy copy. Both earlier open decisions are now settled. Put the complete selected opening, setup screens and founders’ video back into the screen-by-screen study, and prepare Xcode for a device test when Joe returns. This authorizes local native integration/build; it does not lift the main/TestFlight hold.

Local branch: `codex/rec-547-film-welcome-device` in the reusable native review checkout. Main was fetched and merged, preserving Ryan’s landed NUX. Main had reintroduced required-photo guards in the UI, submission and entry resolver; remove those while retaining real identity validation, saved-progress proof and selected-photo upload errors. Native film commits through `1155ca4` have been integrated; Xcode project membership is regenerated with XcodeGen.

- [x] Complete optional-photo/N09 enforcement, native founders player and handoff, and a dedicated Onboarding Review Xcode scheme using local review providers and film C.
- [ ] Focused unit/UI checks, fresh real Swift captures and full study playback, then signed device build and Xcode handoff. Preserve normal app data; no phone reset.
- [ ] Sync the reproducible repo archive and source bundle after the verified local candidate. Main and TestFlight remain held for review.

Build space: used Joe’s prior explicit approval for inactive cache `7ef21b121dec605c23c7`, under the helper maintenance lock after confirming no usage. Preserved its small TestResults folder; only that cache removed. Free space reached 52.0 GiB. Later, after another dip, the inactive Events VHS cache `aec8e56c6426cbcd5dfc` was cleared under Joe’s T29 cache approval; its XCTest bundles and all dSYMs were preserved, no handles or release archives were present. Evidence: `cache-cleanup-2026-09-19/events-vhs/cleanup.json`. Evidence: `cache-cleanup-2026-09-19/cleanup.json`.

Build checkpoint: local source is saved at `c71aee6` (core `b1fbb9c`). Three compile attempts found and corrected merge overlaps (missing newline in the carousel, duplicate avatar property/fetch, duplicate notification examples, missing contextual-primer accent). Current `native-device-review-tests-v5` is running through the helper. `v3` stopped at the disk floor; `v4` compiled and exposed the accent issue. Do not interrupt it or start a duplicate. Native video store/UI tests, no-photo profile journey, and N08–N12 capture inventory are selected. Xcode project was opened and Branch Chooser verified `codex/rec-547-film-welcome-device`; scheme selection and signed build still pending. `Onboarding Review` uses an environment route, avoiding XcodeGen argument sorting.

Linear update was rejected by automatic approval review as an external transmission of private project/build details. Joe has a pending async question about a brief REC-547 update. Do not retry that transmission without the requested authorization. Local records continue.

## Active — wind cleanup and retained outtake (T31)

Joe requested reducing the wind in the founders’ recording, preserving natural voices, and showing the finished video for listening approval. Higgsfield is allowed if needed. Joe explicitly chose **include the celebratory outtake afterward**, through the final “Cut.” The new edit retains original seconds 23.5–114.465 (90.965 seconds), removing only the setup. This supersedes T30’s proposed 75-second ending; preserve the original and the earlier cut for comparison.

- [x] Apply conservative speech-preserving wind cleanup to the existing recorded audio, with no voice replacement or regenerated dialogue. Keep the original video picture and timing.
- [ ] Check duration, channel/sample alignment, clipping, voice retention and the final outtake. Provide a same-position original/cleaned listening comparison; do not claim subjective listening approval from measurements.
- [ ] Open the final actual movie in the web review, preserve recipes and hashes in the local repository archive, and wait for Joe’s listening review. Main/TestFlight hold remains active.

## Active — release preparation and founders’ video (T30 / REC-547)

Joe requested selected film C and reviewed setup changes on main and a new TestFlight build, then explicitly said **do not commit anything to main yet** while adding the founders’ video. That hold is active. Prepare locally; no merge, main push, build bump, upload, or Drive publication. Joe specifically requested the entire design process, source, assets and reproducible review tools in the repository, overriding the normal no-session-diary preference for this dedicated design archive.

- [x] Inspect the attached original `IMG_4916.mov`: 114.465 seconds, portrait footage of Joe and Ryan in a park; inspect key frames and generate an explicitly machine-produced timing transcript locally. Proposed useful take: 23.5–98.6 seconds (75.1 seconds), excluding setup and outtakes. Original remains untouched.
- [x] Read-only drift check: origin/main is `eb4e6ad`; Ryan’s NUX landed as `8fce990` / PR #663. REC-529 is Done. Track this follow-up in REC-547 without reopening or rewriting Ryan’s completed issue.
- [x] Prepare a non-destructive cut and specify controls/placement. `founders-video-review.html` opens the actual 75.1-second H.264 cut with the original linked. Playback verified at 540×960, no media error. Native integration and cut approval remain pending. Recommendation: after N08–N12 account setup, before Ryan’s first-use walkthrough; opt-in Play with sound, captions available, visible Skip, normal pause/scrub/mute, end/skip enters NUX once. Do not fire NUX timers underneath the video.
- [ ] Preserve the original Events behavior in the Astir logo: shared continuous clock, fine ongoing movement and sparse larger distortion; only the logo animates on Create your account. Existing C source `1155ca4` is the starting point, not yet the final release candidate.
- [x] Save a runnable **local repository archive** at `docs/designs/onboarding-2026-09/`: 1,552 review files initially (3.63 GiB logical, APFS-cloned), source bundle with seven preserved branches, original movie and proposed cut, checksums and a portable byte-range review server. `git bundle verify` passed. The archive is uncommitted/unpublished while main is held; large-media delivery remains a release-preparation step. Preserve source/capture hashes; exclude build caches and credentials. Archive packaging must distinguish original capture bytes from any browser renditions.
- [ ] After the video checkpoint is settled: integrate film and setup branches with latest main, preserve Ryan’s NUX, validate the exact candidate, land main and complete the explicitly requested TestFlight workflow. No release candidate or next build number has been selected.

The two earlier open decisions (N08 optional photo and N09 headline/subtitle) remain unchanged. User’s new shipping intent supersedes older statements that film was only an archived exploration, but the current main hold takes precedence.

## Remaining decisions — September 19 (T29)

Two product/copy choices remain in this pass: N08 photo requirement (original transcript requested required; newer main and this review currently keep optional, with Apple username-only flow), and final N09 headline/subtitle (current direct headline/body remain, shorter subtitle is only a proposal). N09 privacy and actual-map UI are already implemented; N11 and V05 copy are settled. Contact-to-member matching/ranking is unfinished engineering that was requested, not a new copy choice. Ryan owns NUX. Film remains an archived exploration; no request to merge it. Further device/edge-state validation and V05 recapture are execution work.

## Ready for review — V05 Instagram notification and centered icons (T28)

Joe: **“Your Instagram import is ready”**, with vertically centered app icons on all notification cards. Implemented in native Swift and VoiceOver at `ed8646a` on the local setup branch. Existing notification-denial UI check passed: 1 passed, 0 failed, 0 skipped (`native-v05-notification-tests.xcresult`, summary JSON retained).

Fresh full native V05/N12 movie and N12/N32 stills are at `native-captures/v05-instagram/`; the main board is refreshed. N12 has Continue; N32 is the distinct denied state with Open Settings and Not now. Both share the corrected examples. Visual/OCR inspection confirms the full title and centered icons. Original media and pre-change HTML remain archived. N11 stable line IDs are preserved. Compact simulator shut down.

The first capture surfaced persistent denied permission on N12, corrected by preserving N32 then reinstalling only the fictional review app for N12. Its clean installation also exposed a missing capture launch fixture flag; the script now explicitly passes `-WanderAuthenticatedUITest` and checks the expected controls. No app auth code changed. No cache deletion was required or performed. No merge or release.

## Ready for review — N11 headline only (T27)

Joe: N11 should say **“Keep up with the people you love”** with **no subtitle**. Remove “Follow a few familiar people. See where life takes them.” Keep the existing eyebrow, search, rows and actions. This shared header also applies to its empty/error variants N33/N34. Work on the preserved `codex/rec-529-dark-account-setup` branch; film source `1155ca4` and its recordings stay archived.

- [x] Update the native headline and omit empty subtitle layout/accessibility.
- [x] Native source `27ce60a`; shared-helper build and existing Follow/search interaction passed. Fresh N11/N33/N34 captures are OCR-verified and published on the board. Opened [N11](./?screen=N11&present=1&v=27ce60a) with the new headline and no subtitle. Existing line numbers remain stable; old .03 is retired. Prior board is preserved at `native-n11-headline-archive.html`; original captures remain unchanged. Compact simulator shut down after capture. Film archives are unchanged. No merge/release.

## Ready for review — original Events motion; static account heading (T26)

Joe wants the original Events film's distortion back, keeping the app palette and C typography. On Create your account, **only the Astir logo animates**; the heading, supporting copy and controls are still. Preserve the current study. This supersedes T25's animated-account-heading direction. N09 onward remains separate.

- [x] Inspect selected Events 03C revision 4 source and actual steady/fault movie frames; identify separate per-label clocks, coarse scanlines and different displacement scale in the previous native port.
- [x] Preserve T25 at git tag `archive/rec-529-film-app-palette-2026-09-18` (`945c280`), `opening-film-app-palette-archive.html` and its own `native-film-app-palette-archive.json`. Earlier media stays unchanged. Work on `codex/rec-529-film-events-match`.
- [x] Native Swift source `1155ca4`: shared film timing and screen coordinates, reference raster scale, finer wear, four color-tail offsets and original smooth tracking-band falloff. Fonts, app colors, copy, slides and hit targets retained. Account heading is static.
- [x] Shared-helper build and **26/26 focused checks passed**: 24 unit plus two UI journeys covering both film treatments, automatic account arrival, live Next/login/email and background recovery. Source `1155ca4`; evidence `native-film-events-match-tests.xcresult`. First compile caught a CGFloat/Double ambiguity, corrected before the passing run; failed compile evidence retained.
- [x] Full native C recording (53.6 seconds) and ten-second account hold captured at `1155ca4`. Account PNGs 1.25 seconds apart: 52,523 changed logo pixels, **zero changed pixels in the heading and all UI below it**, exact email-button RGB `[240,90,60]`. Existing iPhone 16e shut down after capture.
- [x] [New HTML study](opening-film-events-match.html?v=1155ca4) opened in the in-app browser beside the exact Events reference. Play/pause, scene seeking, account looping and TV view checked; both movies load with no errors, browser console clean. Archive links and source/media checksums verified. Manifest `native-film-events-match.json`; report `native-board-qa/film-events-match-report.json`. Fresh compact-simulator validation only; no new physical-device performance claim.

Implementation brief: [film-events-match.md](brief/film-events-match.md). Metal Toolchain remains unavailable on this Mac; refine native Canvas drawing without installing a compiler or generating media. No merge/release is requested.

## Previous review — film C with app palette (T25)

Joe paused N09 review to revise the preferred film C opening/account study. Exact scope and checks: [film-app-palette.md](brief/film-app-palette.md). Keep fonts, motion, wear and custom background; restore app palette, remove logo backing, animate the full logo and account heading, restore all account controls to normal solid native UI. Only one revised exploration. Preserve linked archives.

- [x] Recover immutable C `1e27cb4`; inspect native source and actual transparent logo artwork. REC-529 remains the existing shared issue; do not change Ryan's NUX status or task titles.
- [x] Preserve N08–N12 work at `8051f8d`; reuse clean native worktree/cache on `codex/rec-529-film-app-palette`, based on main `f3d9cb6` plus the four archived film commits. Resolve generated project membership with XcodeGen.
- [x] Implement app palette, transparent strongly animated artwork, live account hero and unfiltered/static form controls in Swift. Completed and captured at `945c280`; prior warm C remains unchanged.
- [x] Native build and **24/24 focused tests passed** (22 unit, two UI tests covering B/C). Full revised C recording reaches account entry and holds for ten seconds. `native-film-app-palette.json` pins source, media and verification. Two native PNGs 1.25 seconds apart show 99,631 changed hero pixels, zero changed control/copy pixels, and exact solid Signal `#F05A3C` on the email button. No logo backing seam.
- [x] New HTML study shell and revision brief with linked previous studies. Swift parse/diff checks and HTML module/link checks pass.
- [x] Fresh HTML study opened in the in-app browser: [Film C · App palette](opening-film-app-palette.html?v=945c280). Full native playback, seeking, account loop and TV view verified; no browser errors. Prior studies linked. Fresh compact-device validation only; the standard simulator was already in use elsewhere. Owned iPhone 16e shut down after recording.

Joe approved the one-time cache cleanup. Removed only inactive completed phone-install cache `b929e46e0b532ccc9eca` under the helper maintenance lock; free space reached 50.9 GiB. Cleanup evidence: `film-app-palette-cache-cleanup.json`. Native build/tests and the requested local review delivery are complete; no merge or external publication occurred. Existing publication approvals remain pending; do not retry prior blocked GitHub/Linear publication.

## Previous checkpoint — dark native account setup (T24)

Joe: “fix the UI for all of these … true to the app (with full image and everything) … fit with the previous screens … colors and the background being dark.”

Scope: N08 Profile → N09 Location → N10 Contacts → N11 Following → N12 Notifications, plus affected validation/empty/denial states. Native Swift, real components/full place imagery, warm paper text and Signal accents on Astir Ink. Preserve the approved opening and archive film C; no VHS layer. Ryan retains post-onboarding NUX.

- [x] Reconcile source with latest main `c64bc7c`; archived film preserved at branch/tag. Reuse clean native worktree/cache on `codex/rec-529-dark-account-setup`.
- [x] Implement consistent dark scaffold, real shared profile header, full Hotchkiss Park preview, concise Contacts, individual Follow/search and signup-only native notification cards. Local commits `5eac124` + `8051f8d` on `codex/rec-529-dark-account-setup`. Native photo crop toolbar refinements brought forward without restoring old mandatory-photo rules.
- [x] Preserve current Apple username-only identity behavior and optional-photo policy from newer main; this UI pass does not silently restore the old mandatory-photo policy. Keep identity/photo policy as an explicit later decision.
- [x] Capture actual full iPhone 16e screens N08–N12 and N31–N34; native map/notification movies; full images and per-screen copy/provenance refreshed in existing review tab. Manifest: `native-dark-setup.json`, captures: `native-captures/dark-setup/`. Opening and film archive unchanged.
- [x] Final source builds; 67 unit tests passed in `native-dark-setup-final.xcresult`. First pass additionally passed five UI tests (capture inventory, per-row Follow/search, Location/Contacts denial recovery, notification denial recovery, Apple username-only). Found and fixed Profile swipe-to-dismiss keyboard.
- [x] Final Profile checks **2/2 passed** in `native-dark-setup-profile-final.xcresult`, commit `8051f8d`: native photo selection/cropping, unavailable username after keyboard dismissal, identity retention across backgrounding. Fixed unchanged TextField writes clearing availability. The keyboard check uses actual onscreen geometry because iOS keeps an offscreen AX keyboard. Earlier failures remain recorded; no full final all-target suite is claimed.
- [x] Existing N09 tab refreshed and visually verified. Native movie loads at 1170×2532 without error. Primary and denial/empty media hashes match the board; final N35/N67 captures added. Verified on iPhone 16e; no new standard-size/iPad pass claimed. Owned simulator shut down after testing.

- [x] Local review checkpoint ready. External publication remains pending earlier approval; do not retry blocked publication. Contact matching/ranking remains unimplemented and must not be represented as working.

## Current review - N09 onward; main phone install (T23)

Joe requested latest main on his phone, then asked to walk N09 onward while installation was being prepared. Continue both: review Location -> Contacts -> Following -> Notifications; profile N08 remains in the account-setup scope. Use original T06/T07 transcript notes, preserve accepted denial wording, and keep Ryan's NUX separate. Existing board screens are September 17 native review captures, not new current-main captures.

- [x] Open N09 in the existing native review board and re-read the actual T06 excerpt and A24-A35 decisions.
- [ ] N09 review is open; [line-by-line notes](brief/n09-review.md) capture current copy and transcript-backed versus new proposals. Direct vs expressive headline; explanatory subtitle; actual native map motion; simplify privacy wording to the favored 'Your location is yours.' Current screenshot still has the old privacy sentence. No new copy decision is assumed.
- [ ] Then N10 Contacts, N11 Following and N12 Notifications. Transcript-backed brief: `brief/n08-account-setup-pass.md`.
- [x] Finish requested main phone install. Connected iPhone 16 Pro, developer mode enabled; existing Astir development signing identity present. Clean main checkout fast-forwarded to `fed006dd31bad11b06f567abd4a8acab691b32da`. Build 175 succeeded through the shared helper; log `phone-main-build.log`. Code signature verification passed. Installed and launched normal main on the connected iPhone 16 Pro, preserving app data and without preview/test-auth flags. Evidence: `phone-main-install.json` and `phone-main-launch.json`. Archived film C was not installed. Space was below the 50 GiB build floor, then recovered above it without deleting review assets. No source edits or external release.

## Final film refinement and archive (T22)

Joe prefers C. Keep its shakiness through the full slide from A local experiment into Keep track of everywhere you have been, and keep buttons responsive. Preserve the exploration for later; no request to merge it. Read-only fetch confirms origin/main is `916a6b7`; the film branch includes that base but its film commits are not on main.

- [x] Find cause: `isPlaying` pauses while `previousSelection` exists, and the same value was driving the film preference. Separate continuous decorative motion from the reading timer.
- [x] Verify native automatic flow and live Next/Log in/email interactions while film plays.
- [x] Record the complete corrected native B/C sequences, inspect scene handoffs, and refresh the comparison.
- [x] Archive an immutable comparison, manifest, source reference and restart instructions. Keep the approved production opening unchanged and N08-N12 queued after this checkpoint. Ryan retains NUX.

Completed at `1e27cb4513ee4f55d496ea7554ce2242c81e5610`, pinned by local tag `archive/rec-529-film-c-2026-09-18`. **24 focused tests passed: 22 unit + two UI tests**, both UI tests covering B and C. The interaction test now runs film unpaused, starts a Places handoff, uses Log in, then exercises rapid Next, signup email and verification/background recovery. Both complete native recordings reach account creation.

[Archived review](opening-film-archive.html?v=1e27cb4), pinned `native-film-archive.json`, source/restart notes in `archives/film-c-2026-09-18/README.md`. Updated working comparison also points to the new recordings. Browser Focus and Watch scene transition playback verified. A remains the approved prior capture; B/C use new full native recordings in `native-captures/film-continuous/`. No new generation, push or merge. Existing publication approvals remain pending; archiving does not authorize publication.

Continuity evidence: a stationary empty-header region sampled every 100 ms around opening-to-Places had a 1.1-second near-frozen run before the fix and none after (mean pixel change <0.2 on an 8-bit scale). This supports continuous texture during the handoff, not a physical-device frame-rate guarantee. Full transition contact sheets were inspected; all media hashes matched. Evidence: `native-film-continuous-tests.xcresult`, `native-board-qa/film-continuity-pixels.json`, `film-continuity-before.jpg`, `film-continuity-after.jpg`, and `native-captures/film-continuous/capture-checks.json`.

## Active refinement - study Events 03C and increase film damage (T21)

Joe says the film is getting there but is too clean. Use direct inspiration from the actual Events asset and its brief: little imperfections plus occasional bigger distortion. C's "Connect with your" must be italic. This refinement precedes the queued N08-N12 pass.

- [x] Read the actual selected 03C / revision 4 brief, Canvas composition and tape-shader source; inspect the bundled Events movie's stable, tracking and dropout frames.
- [x] Carry over smeared registration, uneven signal dropout, scanline displacement, fine dust/wear and three stronger tracking faults per eight-second cycle in native Swift rendering. Preserve approved A, copy, slide pacing and native controls. Keep fixed faded Signal rather than hue rotation.
- [x] Make C's stable lead italic, matching the reference caption language; keep main changing/benefit headings condensed.
- [x] Build/test, inspect full native recordings and distortion frames, then refresh B/C on the comparison page. Preserve the first film pass for comparison.

Source: `astir-motion-study/2026-09-17/vhs-study/README.md`, `study.js`, `tape-shader.js` and `Wander/Resources/Events/events-coming-soon.mp4`. The original reference has sparse small wear, authored brief density failures, and major tracking windows at 1.68-1.88, 4.72-4.88 and 6.93-7.18 seconds of an eight-second cycle. The current onboarding mask had no spatial distortion and almost none of those dropout behaviors, explaining the mismatch. Reuse existing texture; no new Higgsfield generation required. External publication remains pending the previously requested approval; local work continues.

Completed locally at native source `04667200de81b0eef066644e347989145941ee9a`. **26 focused tests passed: 22 unit and four UI tests**, with no failures/skips in the final runs. The automatic-playback test exercises both B and C through a hittable email field at signup. Evidence: `native-film-distortion-playback-tests.xcresult` (25) and `native-film-auto-only.xcresult` (1). The new auto test was absent from the first run's discovery; the isolated run explicitly discovered and passed it.

Fresh B/C full-phone recordings independently reach account creation. Their hashes and per-take source commits are in `native-film-comparison.json`; A retains its earlier approved capture. The [updated comparison](opening-film-comparison.html?v=0466720) includes the exact Events 03C film, and the [previous film pass](opening-film-comparison-v1.html) keeps its own manifest. Playback/pause, full account endpoints, italic C and the reference player were checked in the browser; no media or console errors. No new Higgsfield generation. Existing iPhone 16e is left in paused C with the native Style menu for Joe's review.

Two regressions were fixed before delivery: the decorative overlay now disables hit testing on an explicit parent ZStack; and unsafe color-matrix/backdrop filtering around AVPlayer/material content was removed after full-speed playback exposed a RenderBox crash. Ink filtering is limited to pure native text. Final full recordings and the automatic UI journey pass after the fix. Failed evidence is preserved separately, not offered as a complete review take. See `native-board-qa/native-film-distortion-report.json` and `film-distortion-renderer-failure.md`. Physical-device pacing remains unmeasured. No push, merge, release or message to Ryan; existing external-publication approvals remain pending. N08-N12 remains next after this visual checkpoint.

## Next after opening review - N08 account setup (T20)

Joe explicitly reconfirmed the next pass: **N08 profile -> N09 location -> N10 contacts -> N11 following -> N12 notifications**, including related crop, loading, validation, failure/retry and denied-permission screens. Transcript notes exist and were rechecked against T07/T06 and audit decisions A21-A35/A63-A66. The actionable [N08 account-setup brief](brief/n08-account-setup-pass.md) now collects the directions, alternatives, implementation gaps and verification sequence.

- [x] Recover and consolidate the transcript-backed notes for all five screens.
- [x] Confirm this is our account-setup work after the opening checkpoint. Ryan retains post-onboarding NUX, including later notification campaigns.
- [ ] Reconcile current main with preserved native account-setup work before porting changes. Contact matching/ranking is still a real dependency; do not represent search as matching. Honor the transcript's required identity/photo direction while reconciling current identity flows.
- [ ] Implement and review N08-N12 in Swift, then refresh continuous and edge-state recordings and focused validation. Existing review captures remain labeled as archive source until replaced.

Fresh no-X signup verification was completed in T19 (22 focused native checks and four complete captures). Any older pending-disk wording below is historical for that specific correction. T19 film stays an optional exploration; it does not automatically select the styling of subsequent forms.

## Current exploration — film treatment beside approved opening (T19)

Joe requests the existing Coming Soon / Ocean Park VHS treatment across the complete opening through the interactive account screen. Reuse its imperfections and Signal treatment, soften horizontal damage, keep Next/Log in and account fields/providers interactive. This is an exploration beside the approved version, not a replacement or authorized merge. Latest refinement asks for a matching-font version including Connect with your and Keep track of everywhere you’ve been.

Deliver three comparisons: (A) approved baseline, (B) film with current typography, (C) film with Coming Soon typography throughout the main headings. Same approved words, line order and timing; no NUX changes. Film stops automatic progression at real Create your account; input remains native. Reuse original generated texture; additional Higgsfield generation is unnecessary. Current account/setup queue below resumes after this visual checkpoint.

- [x] Read actual Events video/source archive and Ocean Park native label; inspect the actual poster. Reference uses HelveticaNeue-CondensedBlack, faded Signal, dark texture, grain and occasional tracking damage. It already contains a reusable Higgsfield-generated texture.
- [x] Isolate in existing native worktree/cache on `codex/rec-529-onboarding-film-exploration`, from main `916a6b7` (includes no-X signup). Keep approved default and original recordings intact.
- [x] Build debug-selectable native film/current-type and film/matched-type treatments with live controls and accessibility/lifecycle behavior. Local commit `64324018242bc2c20db9f66b31fd28fa96607f9a`; approved remains default.
- [x] Run native interaction checks and capture full iPhone 16e screens. **22 tests passed: 19 unit tests + 3 UI tests**, including both film styles, signup without X, login and verification/background recovery. Four automatic recordings reach Create your account. Physical-device pacing and additional device sizes are not newly verified.
- [x] Publish local [side-by-side Swift recordings](opening-film-comparison.html?v=6432401) with play/pause, seeking, full phones, focus, TV and approved light/dark. Native Style menu, switching, Next and replay verified. No merge or TestFlight release; Ryan retains NUX.
- [ ] Push draft PR only after requested approval. Automatic approval review rejected exporting the code/assets to GitHub; source and local review are complete. Prepared body: `/tmp/rec-529-film-pr.md`. Public diff/body redaction checks pass; no push occurred.
- [ ] Post Linear validation handoff only after approval. Automatic approval review also rejected the detailed issue comment. The local ledger holds the restart information.

Evidence: `native-film-final-tests.xcresult`, matching log, `native-film-comparison.json`, `native-captures/film-exploration/capture-checks.json`, and `native-board-qa/*-film-states.jpg`. The existing iPhone 16e (`6CB5D49F-FA87-4D3E-9C2E-F9A1296F257C`) is intentionally left open for Joe's requested review, with local test auth, matching film type, paused introduction and Style menu. Xcode Branch Chooser shows `codex/rec-529-onboarding-film-exploration` in `wander-native-onboarding-review`. Other devices were not touched.

Implementation note: the first Metal approach could not compile because this Mac lacks MetalToolchain. Native Canvas ink replaced it before the passing build. No new toolchain or Higgsfield generation. Previous build failures remain documented in the logs. Approved recordings remain available and link to the fresh no-X captures. Source is locally committed; review media and ledger remain local.

## Active queue and ownership — September 18 (T18)

**Joe’s latest direction:** “Did we already look at the other screens after the onboarding? … how’s the task ledger looking? What should we be doing next? We’re not going to do the nux. Ryan’s going to do that.”

**Owner boundary:** This task owns the opening, account entry and account setup through arrival on the usable Map. **Ryan owns post-onboarding NUX:** Map tour/finale, voluntary Feed/Lists/Plus/place hints, starter lists, device-guide demonstrations and contextual notification decisions. Keep the existing NUX transcript/spec and draft #663 as reference; do not implement, merge, delegate or send Ryan messages from this task without a further request. Do not use an old “resume NUX next” instruction farther down this file as the active queue.

### What is actually ready

| Area | Captured / reviewed evidence | Shipped status |
|---|---|---|
| Opening and welcome → account entry | Approved native light/dark slides; prior 240 unit + four UI checks and Simulator build passed. | Merged in #668. Signup X removed in #670; fresh build/capture of that tiny correction is pending disk headroom. |
| N04–N07 · Signup, email verification, login, password | Existing native captures and auth journey evidence. | Opening uses current main auth. Recheck archive refinements against main; do not assume every old review change shipped. |
| N08/N67 · Profile and photo crop | Actual empty/filled/chosen-photo/crop captures and a passing prior profile journey. Live profile preview and required photo were implemented in the review branch from the transcript. | Review implementation preserved; main still has optional photo. Reconcile with current identity/Apple flow before porting. No new policy approval is inferred from capture existence. |
| N09/N31 · Location | Actual MapKit preview, compact view, iOS request and denial/recovery evidence. Headline alternatives remain review choices. | Review refinements are unmerged. |
| N10/N36 · Contacts | Actual concise primer and system-dialog captures. | Review refinements are unmerged. Main still uses invitation wording. Automatic contact matching/ranking remains unimplemented; member search is not contact matching. |
| N11/N33–N35 · People and profile/error states | Actual search/following, empty/error and username/profile-state captures; prior per-row Follow tests. | Review refinements are unmerged. Compare existing main Follow work before bringing them forward. |
| N12/N32 · Notifications | Actual native card examples, compact light/dark, system request and denial/recovery evidence. | Review refinements are unmerged; final copy/material choices remain reviewable. |
| Post-onboarding NUX | Native draft #663 plus transcript-backed spec; last checked at `32f1ede`. | **Ryan-owned; outside our execution queue.** |

“Captured/audited” does not mean Joe approved every option, that every edge case passed, or that the screen is on main. Account/setup captures above come from the preserved native review branch, not a fresh current-main run.

### Our next work, in order

1. **Review the five setup screens together: N08 profile → N09 location → N10 Contacts → N11 people → N12 notifications.** Use the existing full native captures and exact transcript/copy alongside them. Start at N08, including the live profile preview and crop. Retain already accepted denial/empty-state wording. Resolve only remaining visual/copy alternatives, not previously settled directions.
2. **Bring that reviewed setup into current main as a separate focused change.** Reconcile current identity and Follow behavior; preserve the shipped Signal opening and no-X signup. Keep Contacts claims truthful until actual matching exists. Do not merge the broad historical split-flap/NUX branch wholesale.
3. **Verify and refresh native delivery.** One continuous account-setup recording plus crop, retry, Follow and denied-permission branches; standard/compact, light/dark. Capture N68 account recovery through the real entry coordinator. First finish the pending no-X build/test when the required 50 GiB headroom permits. Existing recordings must retain their actual source labels until replacement captures exist.
4. **Events opening later.** Remains a separate requested follow-up after core onboarding review; it is not a reason to restart the discarded flip-board explorations.

Capture audit this turn: standalone files exist for N04–N12, N30–N36, N67 and the notification system request. **N68 account recovery remains uncaptured** and stays on our auth queue. N37 Camera, N38 Calendar and N39 save-to-Photos also remain purpose-text-only; these are conditional app-feature follow-ups, not missing required signup screens. Preserve them for the post-onboarding handoff rather than expanding this pass into NUX.

References: [full native review room](http://127.0.0.1:8766/session-2026-09-16/?screen=N08&present=1), [line-by-line native copy](native-copy.json), [transcript decision audit](transcript-audit.md), [Ryan’s NUX reference](brief/nux-transcript-spec.md). No new app code, build, deployment or message to Ryan was performed for this ownership/status update.

## Historical checkpoints — evidence, not the active execution queue

The T18 queue above supersedes prior owner/work-order statements. Earlier “Done” labels can mean a copy study, a capture or review-branch implementation; use the current table for shipped status. Preserve this history for provenance.

## Current follow-up — remove signup close and audit remaining NUX (T17)

Joe: “there should be no x on create your account screen. other than that ship it to main. did we axe any info from onboarding? how are the following steps? did we have more to do ther enext?”

- [x] Opening already merged via PR #668, main `ba54c5296ee9601797ee2ce90ee66d1355ca95bd`.
- [x] Work isolated on `codex/rec-529-no-signup-close` in existing native worktree/cache. Hide the close toolbar for sign-up; retain signup Log in and login close. Update the existing real-entry UI journey.
- [x] Source review/diff/redaction checks passed. PR #670 merged as `a956cdec904cb3e3051f3828de61117c140f9515` from `766a7ce00423d6cd7fb96a7f1b0d76cc14c550f2`; required PR validation passed. Main manifest workflow `35321008498` passed; issue #342 records exact merge SHA as ship. Xcode Branch Chooser confirms `codex/rec-529-no-signup-close`.
- [ ] Fresh native tests/build, simulator update and new signup captures are blocked before compilation by the shared 50 GiB disk floor (43.4 GiB at attempt). The small toolbar-only change was merged with an explicit low-risk environment skip under repository policy. Prior simulator/recordings remain installed and are labeled as predating the correction. Reuse the same helper/cache, run the two affected UI journeys and generic build once headroom permits; then install and recapture actual Swift. No fresh native pass is claimed.
- [x] Audit actual main: opening changed the old diary/trusted-discovery slide wording into the approved connection/Places/People narrative. Post-auth identity → location → contacts → friends → notifications remain. Main still has optional photo and invitation-based Contacts; the improved profile/permission/follow screens in the broad review archive are NOT part of PR #668.
- [x] Recheck current NUX draft #663 at `32f1ede0351a2f67c380897efbbf07466b5634f1`. It now implements actual populated Map M01–M06, native finale alternatives, static Nearby/Check In/Wanna annotations, optional native Feed reveal and Lists’ three purposes. These supersede the older “HTML only” / wrong-annotation claims farther down this ledger and in the September 17 spec.
- [ ] NUX draft gates: choose motion/finale timing/Feed treatment; define four localized starter lists; build N27 device-feature demonstrations; settle N28/N29 notification policy; reconcile latest approved opening; finish validation. Draft has 34 walkthrough unit tests and 10 focused UI checks passing, but full unit 2048/2050 with two unresolved data performance thresholds, and no complete final UI-suite pass. Do not merge the draft or old split-flap foundation with this one-line signup fix.
- [ ] Account setup next pass: profile preview/photo policy, truthful Contacts/member matching and follow behavior, native location/notification presentation. Contact matching remains unimplemented. Events is deferred until this opening checkpoint.

Intentional tutorial cuts (in the NUX draft, not this opening merge): long forced N13–N24 save lesson and scheduled second-launch N26 import lesson; teach those capabilities at voluntary first use. Preserve actual N27 setup guide and location/permission states. REC-529 was reopened to In Progress after PR #670 auto-completed it; the unmerged scope remains open. The current checkpoint is this T17 ledger. The attempted issue-description prepend did not apply; its old split-flap description remains historical.

## Current shipping pass — approved Signal slides, final heading spacing (T16)

Joe approved the single Signal slide treatment and authorized shipping after one final typography adjustment. Keep orange words centered; bring the stable serif lead-in down closer and make it the same size or slightly larger. Preserve all approved copy and timing. Events remains deferred.

- [x] Save exact T16 feedback before editing.
- [x] Isolate approved opening on current main: `codex/rec-529-opening-signal`, in the existing `wander-native-onboarding-review` build/cache path. Preserve all earlier NUX/physical exploration in `wander-onboarding-review-archive`, branch `codex/rec-529-native-onboarding-review`, at `a2bfb91`.
- [x] Extract only approved opening, native previews and account transitions; final typography fix. Plain orange words remain anchored; serif uses 0.108 × content width versus words 0.104 × width and sits 0.145 × width above their center. Removed unused physical renderer/configuration. Static accessibility includes final copy; capture/test route uses real AppEntryView.
- [x] Fresh native verification: 240 unit tests + four UI journeys passed; generic Simulator build passed after merging latest main. Full dark/light recordings and six compact screens verified.
- [x] Canonical gallery, brief, W00–W02 and source provenance refreshed at `?v=4cba092`. Original NUX source is preserved in the archive worktree; earlier Signal gallery remains usable.
- [x] Review, public PR #668 and required CI passed; squash merged as `ba54c5296ee9601797ee2ce90ee66d1355ca95bd`. Main manifest workflow succeeded and issue #342 classifies the exact commit as ship. No TestFlight upload/version bump. Keep REC-529 open for remaining NUX scope.

Build attempts: first stopped before tests because unsigned-simulator setting was omitted; second compile found and fixed Swift font argument order. Final run uses established CODE_SIGNING_ALLOWED=NO and shared cache, with welcome/photo/auth/navigation tests plus four UI journeys. `native-opening-final-tests.log/.xcresult` is the pending final evidence. Disk crossed below the 50 GiB gate; APFS copy-on-write preserved identical archive/media bytes and reclaimed duplicate storage without deleting source/history/evidence.

Final evidence: `native-board-qa/native-opening-final-report.json`. Source `4cba092`; integration/docs head `18b2419`; Xcode Branch Chooser confirmed `codex/rec-529-opening-signal`. Joe asked about white: source comparison confirms light `.white` and dark Astir Ink are unchanged from `966866b`. Joe then requested a simulator build; latest integrated app installed on the existing iPhone 17 Pro, dark mode, opening paused, local test auth. Leave it open for his testing. Compact simulator is shut down.

Prior NUX captures retain archive source provenance. Do not publish internal transcripts/review notes or overwrite unfinished NUX. This public code shipment is separate from the previously blocked broad/internal publication.

## Current launch-blocker checkpoint — ONE plain Signal text slide exploration (T15)

T15 supersedes the flip-board mechanism and all three finishes. Preserve exact copy and the T14 serif “Connect with your.” Use natural Avenir Next Bold uppercase Signal-orange text without tiles, texture or letter effects. Each outgoing word slides left simultaneously with the incoming word sliding from the right. COMMUNITY gets its own initial entrance. The final A / LOCAL / EXPERIMENT and the native benefit phrases use that same slide language. Whole opening composition moves into Places; the upper native UI and lower complete phrase move together between benefits. Persistent masthead/actions remain usable.

Implementation timing for this single review: shared 1.5-second slide and easing; initial entry adds 1.5s before the existing 1.8s holds; final phrase holds 2.4s; benefits each hold 7s. Preserve the quick serif lead-out fade before the final phrase. Flap haptics are inactive because their mechanism has been removed from this path. Show full native light/dark recordings of the same treatment, not three options.

- [x] Preserve exact T15 transcript and scope here before edits.
- [x] Native whole-text slides implemented at `966866b`, with shared timing, exact copy, retained outgoing labels and existing accessibility/manual controls.
- [x] Shared-helper build passed: 29 welcome unit tests and three native UI journeys, zero failures. Evidence: `native-signal-slide-tests.log/.xcresult`. Older unrelated place-data performance/Map failures remain outside this focused pass.
- [x] Both complete native light/dark recordings reach account creation; six compact screens and full-size/mid-transition frames inspected.
- [x] Canonical gallery now contains one native treatment at `?v=966866b`, with exact T15 transcript and state replay controls. Physical gallery archived; W00–W02, four-state brief, full flowchart and provenance refreshed.
- [x] Playback, pause, state/account seeking, light/dark switching, TV/narrow layouts, source/movie hashes and HTTP206 pass. Both simulators shut down. Local handoff saved; STOP for Joe/Ryan feedback. Evidence: `native-board-qa/native-signal-slide-report.json`.

Native implementation `966866b`; local handoff `a2bfb91`; native worktree clean. Capture/verification helpers are saved under `tools/native-signal-slide/`. REC-529 is In Review. Public posting gates remain unchanged.

**Explicitly deferred:** do not search for or inspect the events-placeholder chat/style until after this checkpoint. Do not begin a second exploration. Separate NUX work remains untouched. Existing public GitHub and detailed Linear publication approval gates remain; local work proceeds.

## Previous correction — approved large caps, larger benefit copy, serif lead-in


T14 and two attached native screenshots approve the large PLACES treatment and the new physical motion. Joe flags the small benefit copy as harder to read and explicitly asks for a serif “Connect with your.” Preserve the large opening Avenir Next caps, materials and motion. Reduce the benefit board from 17 to 13 columns, matching its longest approved line, so its caps can be roughly one-third larger without rewriting copy or reducing the upper preview. Use Astir’s native editorial serif for the external lead-in.

- [x] Preserve exact feedback and both screenshots under transcripts/T14-*.
- [x] Implement serif lead-in and 13-column benefits; update the existing exact row/copy contract.
- [x] Native source `d4225f5` built through the shared helper. All 28 welcome tests and three affected native UI journeys passed (`native-physical-readable-tests.log/.xcresult`). The earlier unrelated place-data performance failures remain visible below; the entire unrelated suite was not rerun for this typography/layout edit. Six replacement recordings are underway.
- [x] All six final native recordings, the first Station page, W00–W02, brief and comparison gallery now show `d4225f5`. Prior physical recordings remain as comparison evidence; the accepted first take is archived under `archives/native-physical-first/`.
- [x] All 12 settled benefit frames and six compact light/dark opening/benefit screens inspected. Browser playback, pauses, state/bookmark seeking and whole-phone framing pass; no errors. Six HTTP 206 checks and 27 source/six movie hashes pass. Both task-owned simulators are shut down. Evidence: `native-board-qa/native-readable-report.json`. Local handoff saved; public publication still awaits the existing approval choice.

**External handoff note:** automatic approval review rejected the detailed Linear comment because it contained internal project status, local paths and review evidence. The issue status did update to In Review; no detailed comment was posted. The handoff is preserved locally. A Keep local / Approve Linear choice is pending; do not retry without approval. This is separate from the older public GitHub push gate.

Current opening implementation: `d4225f5`; local handoff: `a98ffac`; REC-529 is In Review. The native worktree is clean. Resume from this T14 correction, keep the public publication gate and separate NUX work intact, and apply feedback to the same Swift branch.

## Physical implementation retained beneath the T14 correction

Source: `transcripts/T13-physical-flaps-and-transitions.txt`. Joe says the flaps look digital/2D, asks for physical flipping and a slowdown on the final leaves, flags the font, and wants the upper benefit slide and between-screen ticker to last as long as the earlier word changes. Keep the existing three explorations. T14 resolves the font feedback: the large Avenir Next Bold caps are approved, while the external lead-in must be editorial serif. Matching light/dark faces and independent cell rhythms remain.

- [x] Diagnose: the native benefit board inherited the eased 0.6-second slide progress and only two turns. The face renderer had little visible thickness; Graphic was explicitly flat and omitted hinges. Flap lettering was SF Mono rather than the app’s Avenir Next family.
- [x] Implement visible leaf edges, stronger recess/bevel, fixed hinges in all finishes, continuous half-turn lighting and moving cast shadow. Final three turns brake progressively. Avenir Next Bold caps centered in equal cells without squeezing.
- [x] Give benefit flutters their own linear 1.5-second progress and the opening turn budget. Upper/full-scene slides now take 1.5 seconds too; cleanup still waits for native animation completion.
- [x] Source committed locally as `19a7c8c`. The first full unit run passed all 2,003 tests. The final run passed all 28 welcome tests and all three UI journeys (manual paging, automatic progression, signup/login). The slower-slide back-swipe regression is fixed by retaining the requested destination and passes its unchanged test.
- [x] Scoped validation complete. Final run has one unrelated place-data 100ms performance budget outlier (123.6ms). The unchanged isolated recheck still exceeds its warm-read (132.3ms/100ms) and list-suggestion (766.0ms/750ms) budgets. Retain this unresolved performance evidence; do not claim a clean final full-suite run or broaden the opening change into place-data work. Native test frames show clean Avenir caps and visibly tilted physical leaves. Fresh native recording is underway.
- [x] Physical media replaced by the fully verified T14 `physical-v2` revision described above; first physical takes are retained.
- [x] Evidence and local handoff saved. Public PR push still awaits the existing approval choice; never retry that rejected publication without approval.

Independent-flutter gallery archived in `archives/native-finishes-independent/`. Native source was clean at `1ee9654` before this pass. Separate `wander-nux-playthrough` checkout has ongoing NUX edits; leave that work untouched. Broader NUX ledger remains below.

## Previous refinement — faster independent flutter, matching face appearance

Latest source: `transcripts/T12-independent-flutter-excerpt.txt`. Joe rejected synchronized timing/repeated letter paths and reverted the contrasting face colors. Dark faces now belong on dark app screens; light faces on light app screens. Signal caps remain unchanged. Every cell on the three-row board must still move, but with its own start, turn lengths, letter path and settling time. This supersedes T10’s exact eight-turn cadence and T11’s inverted face colors. Keep the external lead-in, full-phone gallery, final words and scene timings.

- [x] Native renderer now caches a deterministic motion plan per cell and word change, using the full row/column cell index. Faster 12–16 opening turns fit the existing 1.5-second window. The previous renderer reused column indices across rows, creating identical blank-row glyphs and timings.
- [x] Revert face appearance to match the surrounding app mode across all three finishes; Signal letters and natural font proportions preserved.
- [x] Source `2ef36f9312639b712673481d1d1b7a0ece1904d5` built with the shared helper. All 2,001 unit tests (including 26 welcome tests) and three onboarding UI tests passed. Independent timing/paths, exact glyph settlement, stable pause/scrub, automatic/manual paging and signup/login checks are green. Log/result: `native-independent-flaps-tests`.
- [x] All six complete Swift flows in `native-captures/finishes-independent/` reach account creation. Compact dark/light views pass. Gallery, four-state brief and W00–W02 updated; all six files load/play/seek with HTTP 206 support and no console errors. TV bounds, narrow stacking and complete phones in smaller windows checked; wrapped card headers no longer push phones under the transport.
- [x] Local handoff and evidence updated: `native-board-qa/native-independent-report.json` verifies 27 source fingerprints and all six movie hashes. Both capture simulators are shut down. Public push remains pending the existing approval choice; do not retry it.

Current native source is `2ef36f9`; local handoff commit is `1ee9654`; Linear is In Review. The canonical gallery now shows its six independent-flutter recordings. Previous gallery preserved in `archives/native-finishes-full-board/`. Exact excerpt T12 is first in the current brief. Creative feel and physical haptics remain for Joe/Ryan review. Broader NUX implementation gaps remain preserved below.

## Previous refinement — full screens, three visible rows, eight flips, contrasting faces

Joe accepts the finishes and asks for complete phone screens, eight flips in the existing flutter interval, and every cell on all three rows moving. Keep the external lead-in and its quick fade. Latest color correction: BLACK faces on the light app background, WHITE/OFF-WHITE faces on the dark app background, Signal letters in both. This supersedes earlier face colors in the transcripts. Apply it to opening and benefit boards across all three finishes. Native edits now remove the unchanged-glyph skip and hidden outer rows, use eight cycles over 1.5s, and reserve separate header space above the visible board. All three finishes share this mechanism. Four haptic impacts and scene/copy timings stay as previously specified. Source commit `b7ff1f4` includes all refinements. Current gallery uses whole phones; all six replacement recordings are published and checked through signup.

- [x] Implement source revision and regression coverage for all 30 opening cells, including blanks/repeated letters, and exact end states.
- [x] Shared-helper build; all 25 welcome and 147 navigation checks passed. Manual paging and signup/login passed. Auto progression passed the unchanged isolated recheck (53.242s); its first Play tap left the test paused. Broad unit results retain an unrelated 0.1s place-category timing outlier (0.1213s, then 0.1022s). Do not claim a clean full-suite run.
- [x] Compact visual checks with the new contrasting faces.
- [x] Capture all three finishes in light/dark, publish actual full-phone recordings, update current brief/evidence. Native copy/source/video hashes refreshed; W00–W02 updated; TV/full-phone playback and all six account seeks passed. Both owned devices shut down. Evidence: `native-board-qa/native-full-board-report.json`.

**Publication checkpoint:** Native implementation is `b7ff1f4`; local handoff commit is `4ddddfb`. The public PR still has `2c10e7c`. Automatic approval review rejected the push because it would publish internal review notes to a public repository. A choice to keep this revision local or publish code/notes is pending; do not retry the push without that approval. The local gallery, brief, source code and verification are complete.

Prior analog pass is preserved in archives/native-finishes-analog/. The current gallery and brief now use the verified eight-cycle native recordings. Physical haptic feel remains for iPhone review.

## Playback repair — September 17

Joe could not play the current gallery. Confirmed root cause: port 8766 had no server, and all three videos had no buffered data/metadata; the browser retained the HTML but new media requests failed. The range-capable server now starts detached from tool-session lifetime using `python3 start_review.py` in `onboarding-copy-review/`. It remains loopback-only. The launcher reuses an existing listener; server PID/log are local. Do not replace it with an attached long-running tool session.

Each gallery card now has Play/Pause and clicking the video toggles it. Global Play/Pause resumes; Restart is separate. Playing or switching letter/full-phone views preserves the chosen framing and current position. Browser checks verified individual playback/pause, all-three playback, and immediate Play after light-mode switching; a detached parent-1 server and HTTP 206 range response were independently verified. Native Swift files and source/capture hashes are unchanged.

## NUX spec re-audit — latest user request

Joe asked to also build NUX and carefully ground its spec in the transcript. [Transcript-backed NUX spec](brief/nux-transcript-spec.html) rereads raw T05 and T04, distinguishes final direction from options, and audits actual Swift against prior completion claims. **Corrections:** OB20 Feed scroll is still an HTML exploration; OB23 native Lists copy describes tabs rather than the requested three purposes; OB24 points to imports instead of Nearby Places; OB25 points to directions/actions instead of Check In/Wanna. Location-aware demo content, top-right Next, handwritten annotations, finale alternatives and device-feature demos still need work. Do not treat these as native-complete. The NUX implementation order and exact boundaries are recorded in that doc. Opening mechanics/captures remain the immediate active build.

## Previous pass — separate lead-in, longer analog flutter, four haptics

Latest Joe/Ryan feedback supersedes the earlier three-visible-row opening and two-flip cadence. Preserve the natural monospaced font correction. “Connect with your” is plain text OUTSIDE the board; only COMMUNITY → PEOPLE → PLACES → LOVED ONES occupies the visible middle row. Fade the lead-in quickly (180ms) before revealing and flipping the final A / LOCAL / EXPERIMENT rows. Use seven flips over 1.5s, staggered cells, physical hinges, gravity/drop and slight stop rebound. Four low-intensity crisp haptic taps per opening word/final change; pause/background/accessibility/navigation suppress them. Supporting line still arrives at 3.6s; opening ends at 15.6s. Benefit and account slides remain separate.

- [x] Confirm brief and implement shared native mechanics, separate header, row reveal and haptic cursor.
- [x] Shared-helper native build and 26 focused unit tests passed. All three final UI tests passed after fixing the exact fade boundary and quick-close auth reset. Source `39214cb`. Compact light/dark openings visually checked; all six complete flow recordings now reach account creation.
- [x] Published all six raw Swift recordings at opening-explorations.html?v=39214cb, with word/fade/final/slide controls and compact-window phone framing. Browser appearance/seek/play/pause/focus/narrow-layout checks passed. First Graphic dark take ended on People; preserved as incomplete, replaced with an account-verified take. Physical-device smoothness and haptic feel remain open.
- [x] One authorized Higgsfield/Seedance 2.5 8s study completed. Visual review found extra rows and incorrect final wording; excluded from the app and retained as a labeled reference in higgsfield-motion-study.html.
- [x] Source/capture evidence and handoff updated; current source is 39214cb. NUX spec re-audit is ready, and its explicit native gaps remain the next implementation pass.

Restart: same isolated native worktree/branch and draft PR #648. Current native source is committed and pushed at 39214cb; documentation handoff 2c10e7c is also pushed to draft PR #648. All six captures and the current review are published. The shortened public-code PR description was accepted after the detailed write was rejected. Detailed Linear handoff sync was rejected; keep the full NUX spec and restart state local. Linear status is In Review. Both task-owned capture simulators are shut down. Resume NUX from brief/nux-transcript-spec.md; do not repeat transcript ingestion or call the current generic hints complete. Previous review remains archived under archives/native-finishes-natural-type/. Higgsfield job output: /tmp/astir-analog-study-result.json. No Instagram account changes are part of this implementation.

## Latest correction — natural lettering restored and preview replaced

Joe rejected the font appearance and could not see all three previews clearly. Root cause is confirmed in source: the material pass changed the earlier bold monospaced font to Avenir Next Condensed Heavy and then applied an additional horizontal-only squeeze to fit the same cells. This was an assistant-introduced typography distortion, not merely a browser screenshot defect.

- [x] Remove horizontal-only glyph scaling; restore bold native monospaced letterforms with one uniform font size fitted to the cells. All three finishes share identical glyph metrics.
- [x] Corrected build and 22 focused unit checks passed. Main-phone lettering in all three finishes and shared Station typography on compact light/dark screens were visually inspected. All six recordings were replaced and reach the account screen. Source: `7a5125f8999000925d2cb61e90172f57e33abb88`.
- [x] Review opens with large native letter crops. Replay shows full phone screens. Narrow windows stack all three treatments vertically; no hidden horizontal strip. Browser checks passed for all six videos, play/pause/seek, focus, letter inspection, fullscreen, keyboard controls and narrow layout, with no missing assets or JavaScript errors. Rejected condensed take is preserved in Archives.
- [x] Source/capture evidence and [corrected review](opening-explorations.html) updated. Final documentation is pushed in `565bc0dad4de10d90b91f8228efc162653b5e162` to the same draft PR #648; REC-529 is In Review. Native worktree is clean. No Higgsfield generation needed.

## Current checkpoint — September 17: three native material explorations

Joe authorized a maximum of three directly built explorations without Higgsfield credits. **Station, Sculpted, and Graphic are implemented in native Swift** on the existing REC-529 branch. They share the approved words, three-row geometry, two-flip mechanism, and separate scene slides. Station has restrained mechanical faces; Sculpted has more depth/fullness; Graphic has the largest caps and matte faces. No Higgsfield generation ran, and no creator reference art/video was bundled into the app.

- [x] Build the three native treatments using retained Core Animation layers and a cached glyph atlas. Source commit: `61749886a7af1b1a80333c942356503dc03bb7fa`.
- [x] Preserve uppercase Signal glyphs, light/dark faces, CONNECT WITH YOUR → COMMUNITY / PEOPLE / PLACES / LOVED ONES → A / LOCAL / EXPERIMENT, and A.03 above Next.
- [x] Update the shared slide curve to 0.6 seconds. Keep the real Hotchkiss Park preview/photo, upper-only Places → People handoff, anchored lower board, and native account entry.
- [x] Build and pass 22 focused unit checks, including final face settlement, theme/finish reuse, and resizing. Manual paging and rapid Next/signup/login passed. Automatic progression passed after starting the timed test with the real Play control (54.004s); no timing limit changed. Initial launch-based observation failure is retained in the log.
- [x] Record six complete native flows, with each final account screen verified from the simulator. Raw capture playback skips launch footage without re-encoding or rebuilding app motion.
- [x] Browser controls/media QA passed with no JavaScript errors or missing assets: six native videos play and seek through account creation, light/dark switching, focus, zoom, full screen, keyboard controls, and mobile browser width. All six compact-phone layouts are visually inspected. Evidence: `native-board-qa/native-finishes-report.json` and `finishes-compact-native.jpg`. The local server now supports HTTP byte ranges; this fixes previously unavailable seeking of raw captures.
- [x] Native verification and source/capture fingerprints updated; [the comparison gate](opening-explorations.html) is ready for Joe/Ryan's material and motion feedback. Draft PR #648 is updated and pushed through `4b7af4033877e07a8a119162efe4a1ef5819e794`; REC-529 is In Review and the native worktree is clean. A concise creative-review update is posted to Linear; detailed validation and restart evidence remain in this ledger and the PR. Do not treat creative selection as complete.
- [ ] Joe/Ryan choose the finish and review the motion. Functional tests do not prove physical-device smoothness; this remains a creative gate. The earlier raw recording already contains sparse changing frames during slides, so export alone is not the explanation. No 60-fps/device claim is made.

**Review:** [three native finishes](opening-explorations.html). The previous [uppercase baseline](opening-review.html), [internet references](motion-references.html), [exact transcript/four-state brief](brief/opening-motion-brief.html), full board and brand shelf remain linked. Broader onboarding stays deferred behind this gate.

**Restart:** do not regenerate copy or ingest transcripts again. Worktree `/Users/joelipshutz/Documents/ChatGPT/New project/wander-native-onboarding-review`; branch `codex/rec-529-native-onboarding-review`; issue [REC-529](https://linear.app/recme/issue/REC-529); draft [PR #648](https://github.com/joelipshutz/wander/pull/648). The complete original task register remains below. Map UI timing/selection failures from the broader suite remain a pre-merge gate. No merge or release is authorized.

## Proposed next passes — specification requested September 17

[Spec for passes 1, 2 and 3](brief/onboarding-next-pass-spec.md): Map walkthrough verification and reproduced regressions; missing native Camera/Calendar/Save to Photos/account-recovery captures; post-signup profile/permissions/People polish and validation. This is the scope document for Joe’s review, not a new implementation or completion claim. Focused Map-tour tests previously passed; broader existing-Wanna editor/confirmation failures still need diagnosis. The current opening review remains the completed baseline below.

## September 17 opening refinement · uppercase, centered board and dark mode

Source: [latest complete notes](transcripts/T08-opening-refinements.txt). Focus this pass on the opening and its transitions; defer other onboarding changes while preserving the full register below.

- [x] Uppercase Signal-colored letters; white/light flap faces in light mode and dark faces in dark mode.
- [x] Three consistent centered rows, equal character cells, fewer flips; rotating word centered in row two. Use CONNECT WITH YOUR / [WORD] / blank as the opening reading, preserving the confirmed lead-in.
- [x] Final board uses A / LOCAL / EXPERIMENT, centered on three rows. Every flipped glyph has a split-flap face.
- [x] Select A.03 supporting copy and delayed entrance; move it above pagination/Next.
- [x] Opening board slides left out while the native Places UI and lower benefit board slide in.
- [x] Places → People: only upper native UI slides; lower board stays anchored and flips its letters to the next benefit. Remove Example places/activity labels.
- [x] Replace Circuit Coffee study with real Hotchkiss Park preview component/photo inside the square.
- [x] Account transition slides current elements out and new account UI in.
- [x] Capture actual light and dark Swift videos/stills, then verify TV playback and compact layout.
- [x] Archive previous native A/B/C copy and recordings: archives/native-split-flap-v1/opening-review.html. Keep earlier HTML exploration links.
- [x] Update same draft PR #648 and source/capture evidence after validation.

Current verified implementation: three rows, 17 equal cells; two flips over 0.6s after a 1.8s hold; description at 3.6s; final phrase settled at 9.6s; opening slides at 12s; 0.65s slides; seven seconds per benefit. Both upper native views retain their identity, preload during the opening, and use SwiftUI animation completion to avoid hiding the outgoing Map early. Real Hotchkiss Park photo pulled through Astir’s authenticated place-photo endpoint and cached with original attribution for signed-out use. Temporary review-account session ended. Final build: 1,992 unit tests and three affected UI tests passed. `uppercase-stable-ui-tests.xcresult` records the 1,992 unit tests; `uppercase-completion-ui-tests.xcresult` records the three final navigation tests (64.553s); prior timing outlier passed the rerun without threshold changes.

**Review handoff:** commit `44376daf78d1a747b8ba3d1260e771f9d181ba6e` is pushed to the same branch and draft [PR #648](https://github.com/joelipshutz/wander/pull/648). Current [opening review](opening-review.html) opens in dark mode with light mode alongside; both actual Swift recordings reach account creation. Full-phone TV fit, compare/replay/pause/seek, latest four-state brief and archive links passed with no JavaScript errors or broken assets (`native-board-qa/uppercase-report.json`). The full board retains 46 native screen/recording cards plus four clearly identified copy-only appendix entries (399 lines). Compact layout evidence is from the stable-panel build; later lifecycle edits do not change dimensions. Native source and media fingerprints are refreshed.

**Restart:** review Joe/Ryan’s feedback against this opening and the T08 excerpt in the four-state brief, then change this same Swift branch and replace native captures. Do not rebuild the old HTML motion approximations or restart transcript ingestion. The broader task register remains deferred and preserved below. Broader Map UI failures remain a pre-merge gate; this pass is ready for creative review, not release.

## Previous checkpoint — September 17, 2026: native mechanical split-flap pass verified and published

Historical checkpoint below. Resume from the September 17 refinement above; preserve the complete register and do not restart transcript ingestion.

- **Latest motion implementation:** the requested **mechanical split-flap display / flip board for individual letters** is implemented in settled native source with top/bottom 3D hinged flap faces and five staggered cycles per changed letter. The actual current build/tests PASSED exit 0, and final A/B/C native recordings are visually verified and published. The [motion brief](brief/opening-motion-brief.html), gallery and full board are regenerated. Final browser QA passed; implementation is saved in [draft PR #648](https://github.com/joelipshutz/wander/pull/648). Cadence remains a first pass for creative review.
- **Current source timing:** 1.6s hold + 1.0s mechanical flips = **2.6s per word**; delayed supporting text starts its slide at **3.9s**; final phrase settles at **10.4s**, holds 2.4s, then the whole page advances at **12.8s**. Places and People each use **7s** by default. Reduce Motion/VoiceOver switched on mid-flip resolves to a complete readable word. Source-copy refs/hashes and A/C timing metadata are updated; cadence and supporting timing remain for review.
- **Confirmed copy:** **Connect with your** stays as the lead-in while **community / people / places / loved ones** change; the whole headline ultimately resolves to **a local experiment**. Supporting copy slides in and the whole scene slides into the next native benefit UI. Letter flips and scene slides are distinct. Exact cadence, supporting-copy fate and alternative wording/timing remain review choices.
- **Published native media:** the [opening gallery](http://127.0.0.1:8766/session-2026-09-16/opening-review.html), brief and [native board](http://127.0.0.1:8766/session-2026-09-16/) now use verified A/B/C mechanical split-flap recordings. Exact native-frame review confirmed glyph halves/staggered cycles, initial lead-in/community, all word changes, final headline and loaded Map → People → signup in all three. Trims are A **2.0s**, B **2.0s**, C **1.8s**; W00/V01 are replaced from A and state frames use raw A **2.5/7.5/13.5/18s**. New W00-compact native screenshot is readable. `native-captures/split-flap-review-ready.json` records hashes; media manifest is refreshed. Previous pulse media is superseded. Cadence remains for creative review.
- **Current split-flap validation:** **1,989 unit tests, 0 failures, 41.869s (43.117s wall)**, plus **3 affected welcome UI tests, 0 failures, 59.523s**, in `native-split-flap-tests.log` / `.xcresult`, completed 11:10:06. Auto progression 33.072s; manual paging 13.583s; Next/signup/Login 12.868s. Source and hashes are unchanged from the audited snapshot. Earlier nine selected UI tests included Map/Feed and passed; broad Map timing/selection failures remain uncleared. No full broad UI pass is claimed.
- **Earlier unchanged-flow evidence:** native auth passed **41.611s** on the previous pulse build. Profile/photo/crop/Choose passed **79.583s** separately; Follow, OS permission denial/recovery and native Map/compact checks have recorded prior-build evidence for flows unchanged by split-flap work. The previous 1,984-unit/three-UI pulse result is historical; current split-flap validation is above. These separate auth/profile journeys were not rerun on this new build.
- **Native implementation retained:** welcome/account routing; required photo/name/username and live shared profile header; search and individual Follow/Following; concise N10/N36 Contacts wording; real location MapKit and notification cards; short Map overview, in-context finale and first-use hints; forced N13–N24 saving flow and N26 second-launch import lesson retired. Contact matching, Plans/Events, starter lists and other explorations remain separate in the register.
- **Task and ownership:** [REC-529](https://linear.app/recme/issue/REC-529), Joe, In Review. Branch `codex/rec-529-native-onboarding-review`; worktree `/Users/joelipshutz/Documents/ChatGPT/New project/wander-native-onboarding-review`; base `4937033a99175b2b22b48440a1376b644f6ad8e6`. Final commit is `7bfe12886bd4924e8c0bec281eab5837bc4d8da1`; the branch is pushed and clean, with [draft PR #648](https://github.com/joelipshutz/wander/pull/648) open. Implementation, capture and brief work for this pass is complete. Main simulator `3634A858-7A50-4EC3-8C21-56E6B16A6985`; transcript simulator `D0D0B63E-85CE-401E-A701-0D57069908E0`.
- **Files:** `native-copy.json` retains the 41-card source-copy inventory; `native-verification.md` records scoped evidence and the current correction; `native-captures/media-manifest.json` fingerprints media; `opening-options.json` is the alternative-copy source. The board contains 47 native screen/recording cards and four copy-only appendix entries, with pan/zoom, notes/export, brand shelf and TV mode. W00 is opening; W01 Places; W02 People. Earlier HTML phone studies remain archived.
- **Final browser QA:** all three videos play/seek through signup; Focus/Compare, four full-width brief images, and main V01 playback/pause/seek passed with no JavaScript errors or missing assets (`final-split-flap-report.json`).
- **Next:** Joe/Ryan review the native opening takes and four-state brief; apply their next copy/motion feedback on the same branch. Broader Map UI timing/selection failures require resolution before merge. Current split-flap build/tests, native frame verification and media publication are complete. Preserve first-pass creative boundaries and prior-build auth/profile evidence in the handoff. No merge, release, App Store upload, real invitations/accounts/follows or production backend changes are authorized.


## Historical checkpoint — September 16, 2026

### September 17 review correction — opening ticker

- User rejects the motion prototype's **“A life full of”**. This was assistant-invented placeholder copy, not wording from the recording.
- The original T07 transcription recovered the lead-in but garbled the word list. **Superseded by Joe’s direct September 17 confirmation:** lead-in **“Connect with your”**, rotating **community / people / places / loved ones**. These are confirmed user words, not reconstructed guesses.
- Placement: fixed introductory text and changing word in the **upper part of the screen**. T07 says “the top thing, the stable text.” The explanatory description joins it, then the entire composition moves away for the native UI benefit slides.
- New direct motion clarification: changing text should **fade out / fade in like a changing train-station sign**, rather than the current rolling-word effect. This supersedes the initial prototype's animation treatment.
- Joe also confirmed that after the rotating words, the **whole lockup** fades to **“a local experiment”**. The stable lead-in must disappear with the changing word and supporting description.
- The confirmed opening is now included in `OnboardingWelcomeConfiguration.current`. Explicit empty configuration remains available for focused tests. Supporting description baseline: **“Keep track of everywhere you’ve been. Keep up with the people you love.”**, delayed by default. Alternative supporting lines and immediate/delayed timing remain review choices. Combined build-for-testing passed at 09:53; final unit/UI reruns and actual refreshed captures are tracked separately.

- DONE: preserve all seven originals and SHA256 manifest; read every transcript; reconcile three duplicate pairs into four conversation segments. Reading order is T07 → T01/T06 → T02/T05 → T03/T04 → typed notes.
- DONE: comprehensive source audit with 67 stable evidence IDs (A01–A67), raw-only clarifications, and 16 unresolved choices in [transcript-audit.md](transcript-audit.md).
- DONE: retrieve approved brand package, exact prior IG quote task and saved taste; verify two candidate quotes against primary sources. A separate file named “brand workbook” was not located. See [brand-context.md](brand-context.md).
- DONE: inspect current Contacts source and Apple review history. Member matching is missing; long disclosure was an internal response to a real upload/consent concern, not evidence Apple mandated exact wording. See [contacts-evidence.md](contacts-evidence.md).
- DONE: build the [revision room](index.html): 25 cards, 60 variants, 268 numbered copy lines, pan/zoom, TV mode, local drafts/notes/choices and export. Six interactive studies in [motion-lab.html](motion-lab.html), with [motion-handoff.md](motion-handoff.md). Current Swift baseline stays intact.
- DONE: create the explicitly requested separate Events coming-soon task [REC-528](https://linear.app/recme/issue/REC-528/add-an-explicitly-coming-soon-events-preview-and-tab). The overall task register remains here; no broad umbrella issue was created.
- DONE: source verification of Featured/Friends/pins, Map Search, N28/N29 eligibility, live setup guide and current Feed cache/SQL path. See [permission-and-map-evidence.md](permission-and-map-evidence.md) and [feed-performance.md](feed-performance.md).
- DONE: bounded production catalog and aggregate timing checks using isolated Astir read-only access. Deployed Feed matches REC-497 main. Historical authenticated Feed: 1,111 calls, 361.338 ms mean, 2,294.802 ms maximum, accumulated since July 21 across versions/accounts. This supports investigating server cost; it does not establish today’s bottleneck or p95. Fresh representative traces/query plans remain open. Sanitized evidence is in feed-production-evidence.json.
- SCOPE FOR THIS PASS: finish the extensive review package requested in the recording. Settled direction is recorded below; proposals are not automatically approved. App implementation is a separate execution stage requiring isolated branches, source changes, native verification and PRs. A scope question was offered; no answer is assumed.
- REVIEW PASS COMPLETE: artifacts, core interactions, export, source hashes, local asset links and all 67-item task coverage verified. NEXT: collect selections on the review variants, then implement settled/selected app work from the register below. Do not restart transcript ingestion after compaction.

## Overall task register

**Review status** describes work in this package. **App work** describes what remains in Swift/backend/web; a prototype does not complete that work. Evidence IDs link to the complete source inventory in [transcript-audit.md](transcript-audit.md).

| ID | Workstream / concrete result | Evidence | Review status | App work / dependency |
|---|---|---|---|---|
| OB01 | Archive sources, deduplicate, keep this restart ledger and complete coverage audit | A01–A03 | Done | None |
| OB02 | Recover brand, IG quote taste and approved asset/material references | A04–A05 | Done; exact workbook unavailable | Use approved wordmark; stone icons remain exploration |
| OB03 | Welcome: immediate-description and delayed-description ticker prototypes, then actual UI benefits | A06–A12,A33 | Done: A/B motion + three copy directions | Confirmed words and whole-lockup final phrase implemented in the native default; delayed baseline and alternative supporting lines/timing remain for review. Refreshed native capture and validation underway. |
| OB04 | Welcome copy alternatives: remember places, people you love, plans together | A09–A11 | Done: three copy sets; native Plans capture still needed | Two native benefits implemented with actual MapKit and activity-card views; Plans/Events preview remains separate. |
| OB05 | Remove Get started; auto transition to N04; early/repeated Log in | A13,A19 | Done: two timing options + motion sequence | Implemented once-through automatic transition, Next, pause and direct Log in; actual native recording. |
| OB06 | Events coming-soon welcome preview and separate tab ticket | A14–A16 | Done: existing native preview + REC-528 | Reuse Events UI; no live RSVP/backend promise; separate from onboarding |
| OB07 | Tab consolidation follow-up | A17–A18 | Tracked | Investigate architecture later; global app flicker explicitly rejected |
| OB08 | N04–N07 brand refresh; compare coherent email/lock/logo material | A05,A20 | Done: accepted copy + three material studies | Approved Astir artwork integrated into production account/login/password/email screens; existing auth behavior preserved. |
| OB09 | N08 typography/fields alternatives and live profile-header preview | A21–A22 | Done: three type/field studies; live name/handle/photo preview | Shared production profile header now previews name, username and selected photo live. |
| OB10 | N08 mandatory photo/name/username | A23 | Spec recorded | Required identity/photo validation, explicit upload failures, retry and offline/resume gates implemented; native journey validation in progress. |
| OB11 | N09 location: direct/quote headline, benefit subtitle, real map motion, concise privacy | A24–A26 | Done: three options + preferred privacy line | Actual Swift MapKit camera, staggered pins and selected-place entrance implemented and recorded. Copy choices remain reviewable. |
| OB12 | N10 separate contact connection from invitations; N36 concise purpose | A27–A28,A66 | Done: evidence + future/fallback purpose copy | N10/N36 shortened to high-level connect wording, removing rejected disclosures. Automatic contact matching remains a separate implementation dependency. |
| OB13 | N11 immediate Follow→Following, search, ranked contact/member rows | A29–A30 | Done: searchable fictional demo + three copy sets | Production member search and individual Follow/Following, pending/retry and existing-follow state implemented. Contact matching/ranking remains open. |
| OB14 | N11 user-controlled Messages invite and message variants | A31 | Done: three message proposals | User chooses recipient and sends; no invitations sent during this task |
| OB15 | First connections and low-network People unit | A32,A47 | Done: People/Feed copy; activation spec | First two is activation aspiration, not empirical threshold; coordinate prior People layout work |
| OB16 | N12 coherent icon colorways + 2–3 useful animated notification cards | A34–A35 | Done: three headline sets, icon colorways + replayable examples | Three actual Swift notification examples implemented with native entrances and Reduce Motion; Events example omitted. |
| OB17 | Replace forced N13–N24 save tutorial with short map overview | A36–A38 | Partial: short native sequence exists | Forced save tour is removed. Location-aware populated demonstration and full visual/motion verification remain in the transcript-backed NUX spec. |
| OB18 | Featured/Friends/More/Search/Plus/import/pin definitions and accurate order | A39–A40,A43 | Done: source-verified definitions + ring examples | Actual Featured/Friends/More/Search/Plus/pin sequence implemented and source-verified. |
| OB19 | Map coach A/B motion, target cue, automatic readable pacing, immediate Next | A41–A42 | Partial: native hint baseline; motion exploration pending | Current Next is in the coach, not the requested top-right position. Two native entrance/exit treatments and final readable pacing still need review. |
| OB20 | Voluntary first-Feed scroll/reveal prototype + Feed/People explanation | A44–A46 | HTML exploration only; native reveal pending | Current Swift has a contextual Feed hint. The roughly-20-item decelerating first-entry reveal is not implemented natively. |
| OB21 | Test Feed server/caching hypothesis separately | A48 | Done: source + deployed catalog + historical server timing evidence | Existing REC-458/319/320/378/441; measured evidence required before diagnosis |
| OB22 | N25 connection-first finale variants, in-context overlay, 4s vs 6s and Skip | A49–A51 | Done: three new options + original; 4s/6s study | Original Bourdain finale implemented in context with six-second timeout and immediate Skip; replacement quote remains open. |
| OB23 | Lists first-entry one-block education, four localized starter-list proposals | A52–A55 | Partial: native hint differs from transcript | Replace tab-explanation copy with the three purposes: sharing recommendations, personal organization and imported places. Four curated/localized starter lists remain open. |
| OB24 | Nearby Places annotation on first voluntary Plus | A56,A58 | HTML annotation study only; native correction pending | Current Swift points to Import. The requested static handwritten Nearby Places annotation on voluntary Plus remains to build. |
| OB25 | Check In/Wanna annotations on actual place profile | A57–A58 | HTML action study only; native correction pending | Current Swift points to Directions/Call/Website/Reservation. The transcript asks for Check In/Wanna annotations on the actual place profile. |
| OB26 | Remove N26 second-launch import lesson | A59 | Done in native code | N26 eligibility/checkpoints are retired. Do not reinstate the launch-count import lesson; contextual Nearby Places guidance still needs its correction. |
| OB27 | N27 real website setup guide + Action Button/share/widgets motion studies | A60 | Guide native; device-motion studies pending | Actual setup-guide NUX is preserved and captured. Action Button/share/widget demonstrations remain exploratory; browser storyboards are not native completion. |
| OB28 | Verify N28/N29 trigger semantics before deletion | A61 | Done: eligibility verified; retention choice unresolved | Actual conditional N28/N29 captured through production presentation and permission gates; consolidation decision remains open. |
| OB29 | Preserve onboarding/contextual location requests | A62 | Direction recorded | Real location request and denied recovery preserved; native permission-state verification included. |
| OB30 | N31/N32/N33 UI-only refresh, retain accepted wording | A63–A65 | Done: UI studies with exact accepted copy | Shared native typography/spacing used for accepted empty/failed/denied states; exact wording retained. |
| OB31 | Keep remaining accepted states; no invented address/brand action | A67 | Done | “650 Kensington” is incidental; no new work inferred |
| OB32 | Motion handoff with transcript provenance and exact transitions/options | A01,A07–A08,A35,A41–A42,A45,A50,A58,A60 | Done: motion-handoff.md | Native Swift motion recordings replace browser animation studies for implemented scope; unresolved explorations excluded. |
| OB33 | Validate artifact, links, saved selections, TV controls and complete coverage | A03 | Done: browser, syntax, source hash, asset and coverage checks | Native board browser QA passes playback, pan/zoom, TV, notes/export, copy coverage and asset requests; final capture/test ledger below. |

## Settled direction

The narrative moves through awareness → desire → ability → reinforcement. Benefits should register quickly and center shared life, connection and neighborhood familiarity. The long forced save-form tour goes away. The short map overview ends on Map; Feed, Lists, Plus and place actions are introduced when first used. N26 is removed. Profile photo becomes required. Follow actions happen per row. The Events teaser is visibly coming soon. N31–N33 copy is accepted. None of this approves one arbitrary headline, font, motion duration or starter-list title.

## Decisions still to select

1. Review the current welcome cadence and selected A.03 description persistence. September 17 confirms the lead-in, four rotating words, final three-row phrase, delayed lower A.03 placement and two benefit slides; earlier A/B/C alternatives are archived. Keep the accessible returning-user path.
2. Welcome, location, contact and People headlines; invitation message variant; notification icon material/colorway.
3. N08 type/field treatment and whether profile metrics appear in preview.
4. N25 quote/original line, optional button, blur/static treatment and four/six-second duration.
5. Map coach entrance/exit treatment and whether pin explanation is separate or overlaps search.
6. Feed scroll treatment and fallback examples; forcing Feed is explicitly deferred.
7. Four starter lists: final names, local sourcing, content, ownership and editability.
8. Annotation dismissal on drag; Next and action dismissal must work.
9. N28/N29 retention/consolidation after actual eligibility has been explained.

## Existing work to coordinate

- [REC-393 — Polish NUX import copy, save walkthrough, and pacing](https://linear.app/recme/issue/REC-393): its August scope improves the long save tutorial. September recording replaces that tutorial; coordinate supersession before anyone implements obsolete requirements. Do not silently close Ryan's issue.
- [REC-426 — Edge-state and accessibility appearance matrix](https://linear.app/recme/issue/REC-426): overlaps N31–N33 polish and native verification.
- [REC-458 — Feed/Profile/Place latency](https://linear.app/recme/issue/REC-458): use as context for measured Feed work, not proof of a server diagnosis.
- [REC-470 — Contacts App Review remediation](https://linear.app/recme/issue/REC-470) and [REC-396 — Location pre-prompt](https://linear.app/recme/issue/REC-396): relevant permission history.
- [REC-467 — Events definition](https://linear.app/recme/issue/REC-467), [REC-525 — Events contracts](https://linear.app/recme/issue/REC-525), [REC-526 — Events data foundation](https://linear.app/recme/issue/REC-526): existing Events implementation work; this recording asks for a separate coming-soon presentation task.

## Restart sequence

1. Read this checkpoint and open tasks; inspect the artifact files already present.
2. Read `transcript-audit.md` only for evidence/ambiguities; originals are retained for exact wording.
3. Read Contacts/brand/Feed evidence before changing dependent copy or behavior.
4. Finish review package and verify it; then update each review status here.
5. If proceeding to app implementation, inspect the actual repo AGENTS.md, coordinate Linear overlap and use an isolated checkout. Implement settled direction while preserving unresolved choices explicitly. Run native checks and create the required PR. No deploy/release was requested.

## Source handling

The seven original attachments are preserved under `transcripts/T01.txt` through `T07.txt`; paths and hashes are in `transcripts/manifest.json`. T01/T06, T02/T05, T03/T04 appear to be differently transcribed versions of the same segments. Keep unique statements from either version; do not count repeated material as separate decisions.

## Latest inline notes

- N31 Location denied: copy is fine; update UI.
- N32 Notifications denied: same.
- N33 Empty people: copy is fine; update UI.
- N36 Contacts purpose: focus on finding/following people. Remove invitation emphasis and detailed address-book/Messages disclaimers if consistent with actual behavior and App Store review requirements. User explicitly asked to check the review history if that language was required.
- Remaining system/brand screens: no clear additional change requested.

## Guardrails and restart

Preserve current review screenshots as the baseline. Distinguish accepted copy, proposals, implementation tasks, and open choices. Do not count a design proposal as implemented app behavior. No production deployment or release was requested. Before app implementation, use a Linear task and an isolated checkout per repository instructions. Resume by reading this ledger, the decision table (to be added), and the current checkpoint; do not reread all transcripts unnecessarily.

## Deliverables and verification

- **Overall tasks:** this file, covering all 67 source items through 33 workstreams.
- **Copy:** COPY-DECK.md and revisions.json (single source of review copy); all options labeled, exact accepted auth/system lines preserved.
- **Review room:** index.html, generated by build_review.py from review.template.html; Current Swift screens links back to the original complete board.
- **Motion:** motion-lab.html and motion-handoff.md; six studies with optional Reduce Motion, cancellation and explicit sample/storyboard labels.
- **Visuals:** icon-material-study.png, ICON-STUDY.md, existing Events native prototype and ASSET-PROVENANCE.md; approved brand remains underneath.
- **Evidence:** transcript-audit.md, brand-context.md, contacts-evidence.md, permission-and-map-evidence.md, feed-performance.md.
- **Verified in real browsers:** pan/zoom, TV presentation, line navigation, draft persistence across reload (temporary QA draft removed), live profile-name/handle preview, inline Follow→Following, sample name search, notification replay, Bourdain quote attribution, selected list-copy parity and separate Contacts headline/purpose. Independent review caught stale TV scroll; fixed and browser-retested on a scrolled Notifications → Contacts transition. Export was clicked successfully and emitted its completion message. No real follow/invite/account operation is connected to these demos.
- **Native app:** unchanged by this review pass. Required photo, contact matching/search, real per-row following, actual guide brand refresh, removal/sequence changes, first-use eligibility and accessibility/native integration remain app work. Native capture of In Common/Plans and device-feature videos remains to be produced; device studies here are storyboards. Generated icon sheet needs individual asset preparation after material selection.

## Latest implementation priorities

1. Review supporting-copy and timing options using the confirmed native opening: Connect with your → community / people / places / loved ones → whole-lockup fade to a local experiment. Do not reopen the supplied word list as a missing-input blocker. Finish refreshed native capture and validation.
2. Coordinate REC-393 supersession; replace the forced long save tutorial with the selected map demo, remove N26 and implement first-use eligibility. Preserve analytics/completion/reset behavior.
3. Implement contact matching/search and immediate follow actions before shipping the proposed N10/N36 find/follow language. Resolve final contact data-flow disclosure against the actual design and Apple reviewer notes.
4. Implement N08 photo requirement and selected profile/brand treatment; integrate permission/notification UI and N31–N33 appearance checks.
5. Integrate voluntary Feed/Lists/contextual experiences, real local list content, selected N25 ending, and native motion/accessibility variants. Produce native Plans and device-feature captures.
6. Refresh the existing setup guide’s Astir branding. Keep Events coming-soon work in REC-528 alongside, but separate from, existing Events implementation.
7. Obtain representative current app traces and a bounded query plan to separate server, token/network, media and frame costs. Current aggregate server evidence is supporting history, not a resolved performance diagnosis.

No app source, backend function, account setting or release was changed by this review package. The only new external work item is the explicitly requested Events ticket.
