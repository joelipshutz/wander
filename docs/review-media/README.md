# Review evidence storage

Source repositories keep app code, required runtime assets, decisions and
small final evidence. Raw recordings, complete review sessions and repeated
exports live once in shared evidence storage outside individual worktrees.
Git LFS changes how bytes are transferred; it does not prevent each checkout
from expanding the same media.

## Keep useful evidence

- During a task, use one workspace evidence directory keyed by its issue.
  Record its location in the issue and link it from the relevant decision.
  Reuse that directory across branches and attempts.
- At task completion, retain the final passing test result, a concise findings
  report, required reproducible inputs, and the final capture or necessary
  before/after pair for each behavior. Keep unresolved failure evidence.
- Once the final evidence is verified and files are closed, remove only the
  task's redundant intermediate recordings, frame dumps and successful reruns.
  Do not delete another task's files, unique originals, release archives/dSYMs,
  credentials, user data or a historical archive explicitly kept by Joe.
- Captures normally last 30 seconds, at most 60 unless the investigation needs
  longer. Do not embed every image into a giant standalone HTML document.
- Before moving unique evidence, verify its destination by checksum and update
  references. For team access, use an already approved project artifact service
  and a stable link; a local path alone is not a backup or a team handoff.

## Repository limits

`scripts/check-review-storage.py` checks the integrated PR tree in CI:

- New or modified documentation/preview/evidence files and review images are
  limited to 1 MiB per file and 5 MiB in total per change.
- Recordings, result bundles, profiler traces and packaged session archives
  belong in shared storage, even when a Git LFS pointer is tiny.
- The retired onboarding archive may not be reintroduced under its old path.
- Production assets under `Wander/Resources/` are outside this review-evidence
  rule because the app needs them. Do not put review evidence there to evade
  the rule. Existing unchanged legacy files are not silently deleted.

Check staged changes with:

```sh
python3 scripts/check-review-storage.py --base origin/main --staged
```

If a review needs larger final evidence, preserve it outside the checkout and
link it. Do not silently increase the budget, override ignores, or convert it
to LFS merely to make the pointer small. Keep the Review storage check passing.

## Existing onboarding archive

The [onboarding index](../designs/onboarding-2026-09/README.md) opens the full
historical review through `scripts/review-media.py`. Its 1,622 paths, modes,
sizes, Git blob IDs and SHA-256 hashes are pinned in the adjacent JSON manifest.
The shared directory is outside worktrees and is reused by all linked checkouts.
On APFS, restoration clones existing LFS objects with copy-on-write storage;
other filesystems copy them once. Distinct archive files are never hard-linked
to each other or to LFS objects, and modified archive files are never overwritten.

`prepare` is offline by default. `prepare --download` permits a missing source
commit or LFS object to be fetched from this repository's `origin`. Fetching
does not expand the archive into the working tree. `verify` checks every file;
`serve` verifies before binding a byte-range-capable server to localhost.

Do not prune the shared archive as a build cache. It is preserved evidence.
The pinned historical Git commit and its LFS objects remain the recovery source;
this change does not rewrite history, retire old worktrees, or claim historical
Git/LFS storage has disappeared. Three concurrent local build/test slots and
weekly compiler-cache maintenance remain unchanged.
