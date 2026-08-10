---
name: recme-pr-review-merge-release
description: |
  rec.me/Wander PR landing and manual batched TestFlight workflow. Use when
  asked to review, merge, land, ship, or release a rec.me/Wander PR. Merges add
  release context to the rolling Next TestFlight Linear record; build/archive/
  upload steps run only after an explicit TestFlight request from Joe or Ryan.
triggers:
  - merge a pr
  - land a pr
  - ship this pr
  - review and merge
  - testflight release
---

# rec.me PR Review, Merge, And Manual TestFlight Release

Use this skill for rec.me/Wander PR landing and explicitly requested TestFlight
releases. `main` is the releasable integration branch. TestFlight releases are
manual and may be frequent, but they package multiple completed changes whenever
Joe or Ryan decides the batch is worth testing.

## Safety Boundary

- Do not merge or push to `main` unless Joe/Ryan explicitly requested landing
  or a scheduled automation prompt authorizes PR landing.
- Do not increment a build number, archive, upload, attach a TestFlight build,
  tag a release, or post tester Slack notes unless Joe or Ryan explicitly asks
  for a TestFlight/TF build or an already-started explicit release needs to be
  completed.
- Merge/land/review-and-merge language is not release authorization. Explicit
  release language includes "push the TestFlight build", "upload the TF build",
  "release this to TestFlight", and "go push in your build".
- Updating the rolling Linear ticket's `## TestFlight note` is mandatory release
  bookkeeping for every eligible `main` landing. It is not release
  authorization and does not itself bump, archive, upload, or announce a build.
- Skip draft/WIP/hold/do-not-merge PRs, conflicts, failing required checks, or a
  head SHA already reviewed by this workflow unless new commits were pushed.
- Do not submit an App Store production release, change the marketing version,
  create production metadata, or announce in `#all-recme` unless Joe asks.
- A change that is not safe for the next TestFlight must remain unmerged or be
  behind a disabled feature flag. The rolling release record documents `main`;
  it does not cherry-pick a subset of compiled code.
- Never open a docs-only PR whose only purpose is recording a merge or completed
  release. Linear, PRs, git history/tags, App Store Connect, and Slack are the
  durable records. `docs/agent-log.md` is frozen history.

## Required Setup

1. Work in `/Users/joelipshutz/Developer/Wander (nametbd)` or an isolated
   worktree for this repo.
2. Follow `AGENTS.md`: fetch `origin`, inspect status/worktrees, read the Linear
   issue and linked PR, and protect unrelated local changes.
3. Use a short-lived branch for implementation, process, or build-number edits.
4. Keep the Linear issue and PR current with branch, validation, decisions, and
   exact handoff state.

## Linear Status Contract

- `Backlog`: untriaged feedback, or a decision-needed issue with an unanswered
  `Decision needed:` comment.
- `Todo`: triaged and accepted, with no active implementation owner.
- `In Progress`: actively implemented or, for a release record, actively cut.
- `In Review`: an implementation PR is open. Do not use this state merely
  because merged code is waiting for TestFlight.
- `Done`: implementation is merged to `main` and required merge validation
  passed. TestFlight availability is owned by the separate release record.
- `Canceled` / `Duplicate`: inactive.

If a merged change requires real-device/TestFlight QA, put that checklist in the
rolling release record. A failed QA result reopens the implementation issue or
creates a focused bug; it does not keep every merged issue in `In Review`.

## Rolling `Next TestFlight` Contract

There must be exactly one open Linear issue in the `recme` team and `mvp`
project whose exact title is `Next TestFlight`. It normally stays in `Todo` and
is reused across releases.

The issue is the mutable release queue, not an approval queue. Its description
records the last completed TestFlight build and immutable
`testflight/build-<n>` baseline tag/commit plus exactly one active section named
`## TestFlight note`. Each eligible merge adds the implementation issue as
related and appends one entry to that section while also posting the same
payload as an immutable history comment:

```markdown
Release payload — REC-<id> / PR #<n> / <merge-sha>

- Tester-facing change: <plain-language outcome>
- What to test: <one concrete tester action>
- Release operations: <migration, deploy, flag, data action, or "none">
- Validation: <tests/build/visual or hosted verification already passed>
```

The `## TestFlight note` section is the source for the next build's tester copy.
Preserve all other description content. Never create a second note heading;
append, correct, or deduplicate entries within the existing section.

At release time, the note is exported to a temporary JSON snapshot conforming
to `scripts/testflight-manifest.schema.json`. Git remains authoritative for the
binary; the JSON provides classification and tester context for every commit.
Every first-parent commit must appear exactly once with one disposition:

- `ship`: user/tester-facing payload with issue, PR, summary, test actions,
  release operations, validation, and optional known limitations;
- `exclude`: docs/process-only or otherwise non-shipping context, with a reason;
- `release-operation`: build metadata or another release-only commit, with a
  reason.

The snapshot is release evidence, not a checked-in product artifact. Attach the
final passing reconciliation JSON to the Linear release record.

At merge time:

1. Decide whether the diff affects app code, UI, schema/contracts required by
   the app, testable behavior, user-facing copy/assets, or release QA.
2. For eligible work, find the single open `Next TestFlight` issue. If none
   exists, create it. If multiple exist, stop and reconcile them before writing.
3. Relate the implementation issue, update the `## TestFlight note` section,
   and post the matching payload comment while context is fresh.
4. Move the implementation issue to `Done` after merge validation. Do not wait
   for TestFlight.
5. Exclude docs/process-only and truly backend-only work. Explain any non-obvious
   exclusion on the implementation issue.

Do not edit old payload comments to rewrite history. Add a correction comment
that links the original payload if release information changes.

## Required Sweep Order

1. Fetch `origin`; inspect local status, worktrees, the target PR, and linked
   Linear issues.
2. Check Linear for an `In Progress` issue titled `TestFlight build <n>`.
   - If it has a build-number/candidate commit but no completed upload/attach
     evidence, it is an unfinished explicit release.
   - Resume the oldest unfinished explicit release before starting another one,
     unless Joe explicitly reprioritizes.
3. If the prompt explicitly requests a TestFlight release, run the manual
   release workflow below.
4. If the prompt requests PR landing, review eligible PRs targeting `main`.
5. If no requested work exists, report the sweep clear without creating repo
   status files or record-only PRs.

## PR Review Workflow

For each eligible PR:

1. Read the PR, linked Linear issue/comments/attachments, changed files, diff
   against current `origin/main`, and relevant source/tests/docs.
2. Use the gstack `review` skill as the primary pre-landing lens when available.
3. For UI/UX, read `DESIGN.md` and check hierarchy, safe areas, Dynamic Type,
   accessibility, 44-point targets, copy, and approved rec.me direction.
4. For backend, sync, auth, privacy, data, persistence, or visibility changes,
   invoke `plan-eng-review` when `AGENTS.md` or the feedback workflow requires
   it. For a narrow low-risk change, document why it was unnecessary and still
   review data flow, trust boundaries, failure modes, and regression coverage.
5. Check scope drift, generated junk, signing/project churn, privacy/visibility
   regressions, SwiftUI state, persistence, and missing tests.
6. Run proportionate verification:
   - `xcodegen generate` if `project.yml` or membership changed
   - focused and/or full `xcodebuild test`
   - generic Simulator build
   - simulator screenshots for visual changes
   - hosted Supabase smoke/metadata checks when required by `AGENTS.md`

If blocking findings exist, do not merge. Put file/line findings, requested
fixes, and tests run in the PR and Linear. If a real product/architecture/data/
release decision remains, pause in the current thread and Linear before merge.

## Merge Gate

Merge only when:

- review found no blocking issue;
- the PR matches its intent without unacceptable scope drift;
- required validation passed, or a low-risk environment skip is explicit;
- no required human decision or hold remains; and
- the branch is mergeable into latest `main`.

If clean, squash-merge and safely delete the branch. Then complete both durable
updates in the same workflow: the implementation issue becomes `Done`, and any
eligible release payload is appended to the `Next TestFlight` issue's
`## TestFlight note` and comment history. No TestFlight build or build-number
change follows unless separately requested. A landing is incomplete until this
note update succeeds or the diff is explicitly classified as release-excluded.

## Manual Batched TestFlight Release

Run this section only for an explicit TestFlight request or an unfinished
explicit release.

### 1. Freeze and reconcile

1. Find the one open `Next TestFlight` issue and the latest immutable
   `testflight/build-<previous>` tag. For the first migrated release only, use
   the manually recorded baseline commit in the issue when no historical tag
   exists.
2. Reconcile manifest payloads against the git range from that baseline through
   current `origin/main`. Export the Linear payloads/classifications to a
   temporary JSON manifest and run:

   ```bash
   node scripts/reconcile-testflight-manifest.mjs \
     --base testflight/build-<previous> \
     --head <pre-bump-cutoff> \
     --manifest <manifest.json> \
     --build <next-build> \
     --status candidate
   ```

   This is a mechanical completeness check, not product re-triage. The command
   must pass before the build-number PR begins. Correct missing/stale payloads
   and identify required migrations, deploys, flags, or manual QA. A missing
   entry is a release blocker, even when the commit is already in the binary.
3. Choose the next monotonically increasing build number. Snapshot the current
   `## TestFlight note` into a new `TestFlight build <n>` Linear release issue,
   move that release issue to `In Progress`, and record the intended pre-bump
   cutoff SHA. Keep the rolling `Next TestFlight` issue open.
4. Briefly hold other app-code merges until the build-number PR lands and the
   exact candidate commit is captured. This prevents unmanifested code from
   entering the candidate. Docs-only work may continue if it cannot affect the
   generated project or archive.

### 2. Create the exact candidate

1. Create a short-lived release branch from the recorded cutoff.
2. Increment `CURRENT_PROJECT_VERSION` once in `project.yml`; do not change the
   marketing version unless Joe explicitly asks.
3. Run `xcodegen generate` and audit that the project diff contains only the
   expected matching build-number changes.
4. Open and merge the metadata-only release PR through the normal gate. The
   complete integration suite runs on the exact merged candidate rather than
   re-running every individual product review on this metadata PR.
5. Record the exact merged commit as the release candidate, then release the
   short merge hold. New merges continue appending to `Next TestFlight`, but
   their merge SHAs place them after the recorded cutoff and outside the active
   build. Add the build-number PR as `release-operation`, update `candidateSha`,
   and run the reconciliation command again against the exact candidate. This
   second run catches a post-bump fix like a navigation hotfix. Write the output
   files to a temporary directory and attach the reconciliation JSON to the
   Linear release issue. Do not continue while it fails.

### 3. Validate, upload, and finalize

1. Check out the exact candidate in an isolated/detached worktree. Run the full
   relevant iOS test suite and generic Simulator build. Run hosted migration/
   RPC smoke verification required by any manifest payload.
2. Generate concise TestFlight "What to Test", Slack copy, and the Linear
   release-record section from the same passing manifest:

   ```bash
   node scripts/reconcile-testflight-manifest.mjs \
     --base testflight/build-<previous> \
     --head <exact-candidate> \
     --manifest <manifest.json> \
     --build <n> \
     --status candidate \
     --write-dir <temporary-output-directory>
   ```

   Use those files as the only release-note source. The helper enforces the
   4000-character App Store Connect limit and keeps excluded work out of tester
   copy. After TestFlight state changes, regenerate with `--status processing`
   or `--status live`; do not hand-add or drop payloads.
3. Archive and upload that exact commit. Set
   `manageAppVersionAndBuildNumber=false` in export options.
4. Run:
   `node scripts/testflight-release.mjs --build-number <n> --archive-path <archive> --what-to-test-file <path>`
   Always pass the archive path so the helper can detect Xcode build-number
   drift. If description update fails, continue the release and reuse the same
   copy in Slack.
5. When upload/attachment is confirmed, create and push the immutable annotated
   tag `testflight/build-<n>` at the exact candidate. Never move or reuse it.
6. Post one top-level tester-facing announcement to `#release-notes`
   (`C0BM5CY0GQY`). Do not duplicate it in `#testflight-feedback` unless Joe
   explicitly asks.
7. Add final evidence to `TestFlight build <n>`: candidate/tag, release PR,
   included payloads, tests, migrations/deploys, App Store Connect status,
   Slack link, known issues, and next action. Move it to `Done` only when the
   requested TestFlight release is actually available/complete.
8. Only after the build is `VALID`, its What to Test copy is published, and it
   is attached to the public TestFlight group, clear the shipped entries from
   `Next TestFlight`'s `## TestFlight note`. Preserve entries whose merge SHA is
   after the candidate or whose work did not ship. Update the baseline to the
   completed build tag/commit. The note should say `No pending changes.` when
   nothing remains. Do not clear it on upload, processing, copy, or attachment
   failure. Do not create a release-record docs PR.

For cumulative questions, never expand the current delta note by memory. Run
`node scripts/reconcile-testflight-manifest.mjs --audit-sha <sha>` to report the
first and all immutable TestFlight tags containing that commit. This keeps
"first shipped in build" distinct from "changed in this build."

If upload/signing/App Store Connect blocks completion, keep the active release
issue `In Progress` and comment with build number, exact candidate, validation,
blocker, and continuation commands. Do not tag the build, clear the captured
entries from `Next TestFlight`, or claim it is live. The rolling issue may keep
collecting later merges; merge-SHA cutoff keeps those entries out of the blocked
build.

## Tester Slack Note

The release note must include:

- app name `rec.me`, build number, and live/approved versus processing status;
- tester-facing changes from the manifest;
- a concrete testing checklist;
- known/deferred behavior;
- public link `https://testflight.apple.com/join/knEhRa6t`; and
- a request to report problems in `#testflight-feedback` (`C0BAA7DG2AC`) with
  device, account/email if relevant, screenshots, and exact repro steps.

Do not post a "live" note before upload succeeds. Keep `#release-notes`
low-noise with one top-level announcement per build. Tester reports and ongoing
discussion belong in `#testflight-feedback`; `#all-recme` is only for a broad
announcement Joe explicitly requests.

## Completion

- Merge-only completion: PR merged, implementation issue `Done`, eligible
  payload appended to the `Next TestFlight` note and history, no build or tester
  announcement.
- Release completion: exact candidate validated/uploaded, immutable tag pushed,
  release issue `Done`, shipped entries cleared from `Next TestFlight`, baseline
  finalized, and tester note posted.
- Blocked completion: durable Linear/PR handoff contains exact state and restart
  commands. No repo diary or record-only PR is required.
