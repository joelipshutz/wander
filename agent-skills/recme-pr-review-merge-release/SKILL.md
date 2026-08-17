---
name: recme-pr-review-merge-release
description: |
  rec.me/Wander PR landing and manual batched TestFlight workflow. Use when
  asked to review, merge, land, ship, or release a rec.me/Wander PR. Merges add
  release context to the machine-owned Next TestFlight GitHub manifest and its
  Linear mirror; build/archive/upload steps run only after an explicit
  TestFlight request from Joe or Ryan.
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
- Every PR must include one valid `recme-testflight-payload` block. The
  merge-to-main updater records that payload, or a visible `unclassified`
  blocker, in the machine manifest. This is not release authorization and does
  not itself bump, archive, upload, or announce a build.
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

## Efficient Execution And Human Checkpoints

Keep the safety gates below, but do not turn deterministic release mechanics
into dozens of model turns. The normal execution shape is five visible phases:

1. `Scope` — requested PRs/build, linked Linear records, authorization, and
   immutable baseline are known.
2. `Candidate` — manifest snapshot passes and the exact candidate is locked.
3. `Validate` — tests, build, archive prerequisites, and required hosted smoke
   checks pass on that candidate.
4. `Release` — archive/upload and `testflight-release.mjs` finish.
5. `Finalize` — immutable tag, manifest baseline, Linear evidence, and the one
   Slack tester announcement finish.

At each phase transition, send one compact status line containing the phase,
the evidence just established, and the next possible human gate. Send another
message only when the state changes, a human action is required, or an
unexpected failure changes the plan. Do not narrate unchanged polls or every
individual connector call.

Human intervention remains explicit for:

- initial merge/TestFlight authorization when it is not already in the prompt;
- credential, password, device-code, signing, or browser confirmation;
- a required product, data, migration, or release decision;
- a destructive or permission-widening action; and
- an unexpected validation failure whose resolution changes scope or risk.

Optimize everything between those gates:

- Batch independent read-only GitHub and Linear lookups once, reuse resolved
  issue/PR/candidate identifiers, and avoid broad list/history reads. Generated
  manifest copy is the Slack source; reading channel history is unnecessary.
- Run each long Xcode validation/archive command once in a long-lived command
  session with `-quiet`. Poll no more often than needed to keep the user updated
  (normally 45–55 seconds), and inspect focused diagnostics only after a
  nonzero exit. Do not feed successful compiler logs back into model context.
- Group deterministic commands by phase so one tool invocation can establish
  one checkpoint. Keep decision-making in the model; keep waiting, polling,
  hashing, and state-transition mechanics in scripts.
- After a credential pause, perform one compact drift check of the locked
  candidate and manifest, then resume from the recorded phase. Do not replay
  completed review, validation, or connector discovery.
- Treat a repeated environment/auth failure as a human gate after the second
  unchanged attempt. Record the exact restart state instead of opening a retry
  loop.

For expensive or benchmarked tasks, capture a privacy-safe aggregate report
from the local Codex rollout with:

```bash
node scripts/codex-task-metrics.mjs \
  --session <rollout.jsonl> \
  --from <phase-start-iso> \
  --to <phase-end-iso> \
  --reported-tokens <optional-app-goal-total>
```

The metrics command ignores message text, tool arguments/results, credentials,
and environment values. Record only aggregate raw/cached/fresh/output tokens,
task/tool counts, failures, compactions, phase duration, time to first token,
and the task-complete-to-next-user-message human-gate wait estimate. Raw rollout
counters and app-reported goal usage are different measures; label both when
both are available.

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

There must be exactly one open GitHub issue titled
`[machine] Next TestFlight manifest`. It is the machine source of truth. The
`Next TestFlight` Linear issue remains the human status/relation mirror, not a
second data source that the uploader reads.

Every PR must carry exactly one hidden JSON block. The PR number and exact merge
SHA are deliberately omitted because the updater fills those from GitHub after
merge:

```html
<!-- recme-testflight-payload
{
  "disposition": "ship",
  "issue": "REC-123",
  "testerFacingChange": "Plain-language outcome.",
  "whatToTest": ["One concrete tester action."],
  "releaseOperations": "none",
  "validation": "Tests/build/visual verification passed."
}
-->
```

Use `exclude` with a `reason` for docs/process-only work and
`release-operation` with a `reason` for build metadata. The PR check rejects a
missing, malformed, or untouched template payload.

On every push to `main`, `.github/workflows/testflight-manifest.yml` sweeps the
entire range after the last immutable TestFlight tag, resolves each commit's
merged PR, and upserts a machine comment in that issue. Direct pushes and PRs
without valid payloads become red `unclassified` entries and fail the updater
check. A later push re-sweeps the complete range, so missed workflow runs are
self-healing. Every first-parent commit appears exactly once as:

- `ship`: user/tester-facing payload with issue, PR, summary, test actions,
  release operations, validation, and optional known limitations;
- `exclude`: docs/process-only or otherwise non-shipping context, with a reason;
- `release-operation`: build metadata or another release-only commit, with a
  reason.

At release time, `scripts/testflight-manifest.mjs snapshot` reads that same
issue, refreshes it from Git, fails on any unclassified commit, and generates
the temporary JSON, reconciliation evidence, TestFlight copy, Slack copy, and
Linear release record. The TestFlight helper requires gate version 2, verifies
the live issue still hashes to the locked snapshot, and then may touch App Store
Connect. Attach the final passing reconciliation JSON to the Linear release
record.

At merge time:

1. Decide whether the diff affects app code, UI, schema/contracts required by
   the app, testable behavior, user-facing copy/assets, or release QA.
2. Put the correct `recme-testflight-payload` block in the PR before merge and
   require the PR payload check to pass.
3. After merge, require the `TestFlight manifest / sync-main` workflow to pass.
   Its output links the machine issue. Relate the implementation issue to the
   rolling Linear mirror for human status when applicable.
4. Move the implementation issue to `Done` after merge validation. Do not wait
   for TestFlight.
5. Exclude docs/process-only and truly backend-only work. Explain any non-obvious
   exclusion on the implementation issue.

If a merged PR payload needs correction, edit the PR body and manually rerun the
manifest workflow. The machine comment is updated and the next snapshot binds
to its new hash; record the reason for correction on the implementation issue.
For a true direct push, use
`node scripts/testflight-manifest.mjs record --commit <sha> --entry-file <payload.json> --head origin/main`
to add an explicit classification; never hand-edit the machine JSON comment.

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
- the branch is mergeable into latest `main`; and
- its machine-readable TestFlight payload is valid.

If clean, squash-merge and safely delete the branch. Then require the main-push
manifest updater to record the exact commit and classification, update the
Linear mirror, and move the implementation issue to `Done`. No TestFlight build
or build-number change follows unless separately requested. A landing is
incomplete while its exact commit is unclassified in the machine issue.

## Manual Batched TestFlight Release

Run this section only for an explicit TestFlight request or an unfinished
explicit release.

### 1. Freeze and reconcile

1. Find the one open machine manifest issue, its Linear mirror, and the latest immutable
   `testflight/build-<previous>` tag. For the first migrated release only, use
   the manually recorded baseline commit in the issue when no historical tag
   exists.
2. Snapshot and reconcile the machine issue against the git range from that
   baseline through current `origin/main`:

   ```bash
   node scripts/testflight-manifest.mjs snapshot \
     --base testflight/build-<previous> \
     --head <pre-bump-cutoff> \
     --build <next-build> \
     --status candidate \
     --write-dir <temporary-output-directory>
   ```

   This is a mechanical completeness check, not product re-triage. The command
   must pass before the build-number PR begins. Correct missing/stale payloads
   and identify required migrations, deploys, flags, or manual QA. A missing
   entry is a release blocker, even when the commit is already in the binary.
3. Choose the next monotonically increasing build number. Put the generated
   release-record output into a new `TestFlight build <n>` Linear release issue,
   move that release issue to `In Progress`, and record the intended pre-bump
   cutoff SHA plus machine-manifest issue URL. Keep the rolling Linear mirror
   open.
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
   and run the snapshot command again against the exact candidate. This
   second run catches a post-bump fix like a navigation hotfix. Write the output
   files to a temporary directory and attach the reconciliation JSON to the
   Linear release issue. Do not continue while it fails.

### 3. Validate, upload, and finalize

1. Check out the exact candidate in an isolated/detached worktree. Run the full
   relevant iOS test suite and generic Simulator build. Run hosted migration/
   RPC smoke verification required by any manifest payload.
2. Generate concise TestFlight "What to Test", Slack copy, and the Linear
   release-record section from the same live machine manifest:

   ```bash
   node scripts/testflight-manifest.mjs snapshot \
     --base testflight/build-<previous> \
     --head <exact-candidate> \
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
   `node scripts/testflight-release.mjs --build-number <n> --archive-path <archive> --reconciliation-file <generated-reconciliation.json> --what-to-test-file <generated-what-to-test.md>`
   Always pass the archive path so the helper can detect Xcode build-number
   drift. The helper must refuse App Store Connect mutations when the gate file
   is missing, failing, for another build/candidate, incomplete, or does not
   hash to the supplied What to Test file. If description update fails after
   the gate passes, continue the release and reuse the same copy in Slack.
5. When upload/attachment is confirmed, create and push the immutable annotated
   tag `testflight/build-<n>` at the exact candidate. Never move or reuse it.
   Then advance the same machine manifest baseline:

   ```bash
   node scripts/testflight-manifest.mjs finalize \
     --build <n> \
     --candidate <exact-candidate> \
     --tag testflight/build-<n> \
     --head origin/main
   ```
6. Post one top-level tester-facing announcement to `#release-notes`
   (`C0BM5CY0GQY`). Do not duplicate it in `#testflight-feedback` unless Joe
   explicitly asks.
7. Add final evidence to `TestFlight build <n>`: candidate/tag, release PR,
   included payloads, tests, migrations/deploys, App Store Connect status,
   Slack link, known issues, and next action. Move it to `Done` only when the
   requested TestFlight release is actually available/complete.
8. Only after the build is `VALID`, its What to Test copy is published, and it
   is attached to the public TestFlight group, update the Linear mirror from the
   finalized machine baseline. Later commits remain pending automatically. Do
   not finalize on upload, processing, copy, or attachment failure. Do not
   create a release-record docs PR.

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

- Merge-only completion: PR merged, implementation issue `Done`, exact commit
  classified by the machine updater and mirrored in Linear, no build or tester
  announcement.
- Release completion: exact candidate validated/uploaded, immutable tag pushed,
  release issue `Done`, machine baseline finalized while later entries remain
  pending, Linear mirror updated, and tester note posted.
- Blocked completion: durable Linear/PR handoff contains exact state and restart
  commands. No repo diary or record-only PR is required.
