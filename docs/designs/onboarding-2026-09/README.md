# Onboarding review archive

The September 2026 review contains 1,622 files (4.45 GB): native captures,
selected and rejected studies, transcripts, decisions, original media and a
source-recovery bundle. REC-606 preserves it once outside app worktrees.
The current source tree keeps this index and a checksum manifest, so checking
out another branch does not download another copy of the archive.

From any checkout:

```sh
python3 scripts/review-media.py prepare
python3 scripts/review-media.py verify
python3 scripts/review-media.py serve
```

Open <http://127.0.0.1:8776/session-2026-09-16/founders-video-review.html>.
Preparation reuses existing historical Git/LFS objects and verified shared
files. On a fresh clone, `prepare --download` explicitly fetches missing
historical objects. Normal builds do not need this archive.

`python3 scripts/review-media.py path` prints the shared directory. It is under
`.review-media/astir/` beside the primary clone, shared by all its linked
worktrees. The read-only archive retains the original relative paths, offline
HTML, video seeking and browser-local notes behavior. Export browser notes
before retiring a review; they are not part of the saved archive.

Useful entry points after serving:

- [Selected founders video](http://127.0.0.1:8776/session-2026-09-16/founders-video-review.html)
- [Selected native film C](http://127.0.0.1:8776/session-2026-09-16/opening-film-events-match.html)
- [Native screen and copy board](http://127.0.0.1:8776/session-2026-09-16/index.html)
- [Historical studies](http://127.0.0.1:8776/session-2026-09-16/archives.html)

The source-history bundle is at `<shared-directory>/source-history/onboarding-branches.bundle`.
Its original manifest and recovery instructions are in the shared archive's
`source-history/manifest.json` and `README.md`. It remains an incremental Git
bundle requiring this repository's normal history. Use current build/device
rules when reproducing historical code, not old hard-coded capture commands.

The exact archive is pinned to commit
`d31fd7f384be14bb291af7f16b3fe3cfea206098` and indexed in
[`docs/review-media/onboarding-2026-09.json`](../../review-media/onboarding-2026-09.json).
Git history is unchanged; historical Git/LFS objects remain the recovery source.
This migration removes materialization from the current tree, not historical
storage. Existing old worktrees are not switched, reset or deleted automatically.

For new review work, use the [evidence retention policy](../../review-media/README.md).
Keep concise decisions and useful final evidence rather than copying this
historical preservation approach into every task.
