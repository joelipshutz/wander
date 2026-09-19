# Astir onboarding — reproducible design archive

REC-547, September 19, 2026. Joe authorized landing the selected native film C and current cleaned founders’ video, with a TestFlight build. The separate VHS founders treatments are review options and do not hold the release. This process archive is not itself an installed app build; no Drive copy is used.

This archive preserves the actual review process Joe requested: transcript inputs, line-by-line decisions and stable screen references, old HTML studies, actual Swift simulator recordings/stills, original brand/reference assets, media checksums, preparation scripts, and recoverable native source branches. The native app remains the source of UI and animation. Earlier HTML-only proposals are explicitly historical.

## Open the review from a future checkout

Install Git LFS (https://git-lfs.com), then from a normal full checkout of this repository run:

```sh
git lfs install
git lfs pull --include="docs/designs/onboarding-2026-09/**"
python3 docs/designs/onboarding-2026-09/run.py --verify
python3 docs/designs/onboarding-2026-09/run.py --port 8776
```

Then open <http://127.0.0.1:8776/session-2026-09-16/founders-video-review.html>. The server supports byte-range requests for seeking and binds to localhost. It has no Python package dependencies. Other entry points:

- `session-2026-09-16/founders-vhs-review.html` — three eight-second Events-style video treatments beside the current original picture, zero generation credits.
- `session-2026-09-16/device-onboarding-review.html` — focused current walkthrough with actual Swift captures.
- `session-2026-09-16/opening-film-events-match.html` — selected native film C alongside the actual original Events film.
- `session-2026-09-16/index.html` — native screen/copy board, pan/zoom, TV presentation and notes export.
- `session-2026-09-16/archives.html` — earlier studies, including retired split-flap directions.
- `session-2026-09-16/TASKS.md` — decision history, release state, unfinished work and restart instructions.
- `session-2026-09-16/brief/founders-video.md` — video placement, playback states, wind-cleanup recipe and handoff.

The archive preserves media bytes exactly; it does not silently relabel older captures as the latest source. Notes made interactively in the browser are stored in that browser’s localStorage. Use the board’s **Export notes** button to preserve any additional unsupplied review notes; this package does not claim to contain those private browser notes.

## Native source recovery

`source-history/onboarding-branches.bundle` preserves eight local source branches that were not fully represented on main. It was checked with `git bundle verify`. It is an incremental bundle: use it inside a normal full clone of this repository, whose history supplies the prerequisite commits. To import without changing the current branch:

```sh
git bundle verify docs/designs/onboarding-2026-09/source-history/onboarding-branches.bundle
git fetch docs/designs/onboarding-2026-09/source-history/onboarding-branches.bundle 'refs/heads/*:refs/archive/onboarding-2026-09/*'
```

Selected checkpoints:

| Source | State |
| --- | --- |
| `1185c81` | Combined native candidate, selected film C default: optional N08 photo, N09 headline, native founders player and review scheme; verification in progress |
| `1155ca4` | Preferred film C, app palette, original Events timing, static account heading, animated Astir logo |
| `945c280` | Prior app-palette film study; account heading still animated |
| `1e27cb4` | Earlier warm C with continuous motion through slide handoffs |
| `ed8646a` | Dark setup with N11 headline only and revised V05 Instagram notification/centered icons |
| `18b2419` | Approved clean Signal slide opening |
| `a2bfb91` | Earlier native review history, including retired opening explorations |

Create an isolated worktree at the desired source if rebuilding. Use XcodeGen for project membership. On Joe’s Mac, all Xcode builds/tests must use the workspace `.tools/ios-work.py build -- ...` wrapper and its existing cache/device reservations; the repository AGENTS.md and current workspace rules take precedence over historical scripts. The archived scripts retain historical machine paths as evidence. The portable HTML playback above does not need those paths, Xcode, the original `/tmp` helpers, or a running simulator.

For a native C run, the historical debug selector is `WANDER_ONBOARDING_TREATMENT=film-type`. This remains a review selector at `1155ca4`, not a production default. Film C and setup are combined with main in the device-review branch. Film C becomes the release default in the combined candidate at a96f060; historical sources remain exactly as reviewed. Source tests and capture recipes are preserved with the branch. The original Events renderer and its authored inputs are already in `../events-coming-soon/render-source.zip`; the native bundle includes the exact unlettered texture assets used by the film study.

## Founders’ video

`review/session-2026-09-16/founders-video/` contains the unchanged original, a separate proposed 75.1-second H.264 cut, source contact sheet, timing transcript and edit-decision JSON. The earlier cut uses original seconds 23.5–98.6. Joe subsequently approved the full outtake: the current 90.965-second cut uses 23.5–114.465, through the final Cut. Both original-audio and wind-cleaned cuts are preserved, alongside the DeepFilterNet 0.5.6 provenance/checksums and reproducible Python recipe. No Higgsfield credits were used. The transcript is local machine output with known recognition errors, not approved subtitles. The exact media-export Swift source is saved in the review’s tools directory. The Swift AVKit handoff is implemented in the local review branch. Build/device verification and Joe’s listening approval are tracked separately; no subjective audio approval is inferred from processing metrics.

## Verification and publication boundary

`review-manifest.json` records exact path, size and SHA-256 for every included review file. Execution logs, raw XCTest output folders, DerivedData, credentials and hidden files are excluded. Final concise test summaries and visual evidence remain. `source-history/manifest.json` records bundle references and source provenance.

The package contains roughly 3.8 GiB of historical captures. Git LFS preserves binary media and the source-history bundle without changing the original bytes or placing oversized blobs in ordinary Git. The portable server detects missing LFS content through the manifest verification above. The original raw founders movie and every selected/rejected study remain available. Source-frame intermediates for the new VHS treatments are recreated by `extract_frames.py`; they are not archive deliverables.

Native validation and device signing are documented separately from media verification. Check the current TASKS ledger and `onboarding-device-review.md` for the exact build/validation state. Ryan’s NUX remains his existing implementation. The selected film C opening, normal account controls, optional N08 photo and N09+ copy refinements are native Swift. No live account is created by the Onboarding Review scheme.
