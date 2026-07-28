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
project whose exact title is `Next TestFlight` whenever no release cutoff is in
the brief build-number merge window. It normally stays in `Todo`.

The issue is an append-only release manifest, not an approval queue. Its
description records the last completed TestFlight build and immutable
`testflight/build-<n>` baseline tag/commit. Each eligible merge adds the
implementation issue as related and posts one comment:

```markdown
Release payload — REC-<id> / PR #<n> / <merge-sha>

- Tester-facing change: <plain-language outcome>
- What to test: <one concrete tester action>
- Release operations: <migration, deploy, flag, data action, or "none">
- Validation: <tests/build/visual or hosted verification already passed>
```

At merge time:

1. Decide whether the diff affects app code, UI, schema/contracts required by
   the app, testable behavior, user-facing copy/assets, or release QA.
2. For eligible work, find the single open `Next TestFlight` issue. If none
   exists outside the documented cutoff window, create it. If multiple exist,
   stop and reconcile them before writing.
3. Relate the implementation issue and post the payload while context is fresh.
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
eligible release payload is appended to `Next TestFlight`. No TestFlight build
or build-number change follows unless separately requested.

## Manual Batched TestFlight Release

Run this section only for an explicit TestFlight request or an unfinished
explicit release.

### 1. Freeze and reconcile

1. Find the one open `Next TestFlight` issue and the latest immutable
   `testflight/build-<previous>` tag. For the first migrated release only, use
   the manually recorded baseline commit in the issue when no historical tag
   exists.
2. Reconcile manifest payloads against the git range from that baseline through
   current `origin/main`. This is a mechanical completeness check, not product
   re-triage. Correct missing/stale payloads and identify required migrations,
   deploys, flags, or manual QA.
3. Choose the next monotonically increasing build number. Rename the rolling
   issue to `TestFlight build <n>`, move it to `In Progress`, and record the
   intended pre-bump cutoff SHA.
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
5. Record the exact merged commit as the release candidate. Immediately create
   the fresh `Next TestFlight` issue in `Todo` with that pending build/candidate
   as its provisional baseline, then release the short merge hold. New merges
   now append to the fresh issue and are not included in the active build.

### 3. Validate, upload, and finalize

1. Check out the exact candidate in an isolated/detached worktree. Run the full
   relevant iOS test suite and generic Simulator build. Run hosted migration/
   RPC smoke verification required by any manifest payload.
2. Build concise TestFlight "What to Test" and Slack copy directly from the
   payload comments: tester outcomes, concrete checklist, and known/deferred
   behavior. Keep App Store Connect copy under 4000 characters.
3. Archive and upload that exact commit. Set
   `manageAppVersionAndBuildNumber=false` in export options.
4. Run:
   `node scripts/testflight-release.mjs --build-number <n> --archive-path <archive> --what-to-test-file <path>`
   Always pass the archive path so the helper can detect Xcode build-number
   drift. If description update fails, continue the release and reuse the same
   copy in Slack.
5. When upload/attachment is confirmed, create and push the immutable annotated
   tag `testflight/build-<n>` at the exact candidate. Never move or reuse it.
6. Post the tester-facing note to `#testflight-feedback` (`C0BAA7DG2AC`).
7. Add final evidence to `TestFlight build <n>`: candidate/tag, release PR,
   included payloads, tests, migrations/deploys, App Store Connect status,
   Slack link, known issues, and next action. Move it to `Done` only when the
   requested TestFlight release is actually available/complete.
8. Replace the provisional baseline on the fresh `Next TestFlight` issue with
   the completed build tag/commit. Do not create a release-record docs PR.

If upload/signing/App Store Connect blocks completion, keep the active release
issue `In Progress` and comment with build number, exact candidate, validation,
blocker, and continuation commands. Do not tag the build or claim it is live.
The fresh `Next TestFlight` issue may continue collecting later merges, but its
baseline remains explicitly provisional until the blocked build completes.

## Tester Slack Note

The release note must include:

- app name `rec.me`, build number, and live/approved versus processing status;
- tester-facing changes from the manifest;
- a concrete testing checklist;
- known/deferred behavior;
- public link `https://testflight.apple.com/join/knEhRa6t`; and
- a request to reply in-thread with device, account/email if relevant,
  screenshots, and exact repro steps.

Do not post a "live" note before upload succeeds. TestFlight prompts belong in
`#testflight-feedback`, not `#all-recme`, unless Joe explicitly requests a broad
announcement.

## Completion

- Merge-only completion: PR merged, implementation issue `Done`, eligible
  payload appended to `Next TestFlight`, no build or tester announcement.
- Release completion: exact candidate validated/uploaded, immutable tag pushed,
  release issue `Done`, fresh `Next TestFlight` baseline finalized, and tester
  note posted.
- Blocked completion: durable Linear/PR handoff contains exact state and restart
  commands. No repo diary or record-only PR is required.
