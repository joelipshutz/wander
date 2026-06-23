---
name: recme-pr-review-merge-release
description: |
  rec.me/Wander PR landing workflow. Use when asked to review, merge, land, ship,
  or release a PR for rec.me/Wander, especially when the request mentions TestFlight.
  This skill is the shared source of truth for the former PR review/merge/TestFlight
  automation.
triggers:
  - merge a pr
  - land a pr
  - ship this pr
  - review and merge
  - testflight release
---

# rec.me PR Review, Merge, And TestFlight Release

Use this skill for rec.me/Wander PR landing work. It centralizes the merge gate and
TestFlight follow-up that used to live directly in Joe's local Codex automation.

## Safety Boundary

- Do not merge, push to `main`, upload TestFlight, or post Slack release notes unless the user explicitly requested PR landing/release work or a scheduled automation prompt authorizes it.
- Skip draft PRs, WIP PRs, PRs labeled or titled `hold` or `do-not-merge`, PRs with merge conflicts, PRs with failing required checks, or PRs whose latest head SHA has already been reviewed by this workflow unless new commits were pushed.
- Do not create App Store release metadata, submit for App Store review, change the marketing version, or announce broadly in `#all-recme` unless Joe explicitly asks.
- Machines without App Store Connect access may still review/merge PRs and may still bump/push the TestFlight build number when appropriate. They must stop before archive/upload, clearly mark the release as pending upload, and leave exact continuation commands/state in `docs/agent-log.md`.

## Thread Naming And Inbox Title

Whenever this workflow merges a PR, bumps a TestFlight build, or resumes a pending
release, update the current thread title or inbox item title when the host supports
it:

- After merging before build bump: `PR #<number> merged`
- After bumping but before upload: `Build <number> pending upload`
- After successful upload/TestFlight attach: `Build <number> TestFlight live`
- If a merge is blocked: `PR #<number> blocked`
- If there are no eligible PRs or pending releases: `rec.me PR sweep clear`

If no thread-title tool is available, use the same wording in the final
`::inbox-item{title="..."}` or equivalent host inbox/status primitive. This is the
current Codex-compatible fallback; true thread renaming is host-dependent.

## Required Setup

1. Work in `/Users/joelipshutz/Developer/Wander (nametbd)` or an isolated worktree for that repo.
2. Follow repo `AGENTS.md` before editing or merging:
   - `git fetch origin`
   - `git status --short --branch`
   - read recent `docs/agent-log.md`
   - decide whether an isolated worktree is needed
   - append/update `docs/agent-log.md`
3. Use a short-lived branch for any docs/process/build-number edits.
4. Treat unrelated local changes as belonging to Joe, Ryan, or another agent. Do not revert them.

## Required Sweep Order

Every run must check both new PR work and unfinished release work. Do not assume
"no open PRs" means "no work".

1. Fetch `origin` and inspect the current local status.
2. Check for pending TestFlight release work from already-merged PRs:
   - Read the latest `docs/agent-log.md` TestFlight/release entries.
   - Check the latest `CURRENT_PROJECT_VERSION` in `project.yml`.
   - Check recent merged PRs targeting `main`, for example:
     `gh pr list --base main --state merged --limit 20 --json number,title,mergedAt,mergeCommit,files,labels,url`
   - Check recent build-bump commits, for example:
     `git log --oneline --grep='bump testflight build' origin/main`
   - A merged PR is pending a build bump if it touches app-code, UI, schema,
     testable behavior, project config, or QA-relevant runtime code and no later
     build-bump commit packages it.
   - A build-bump commit is pending upload/finalization if `docs/agent-log.md`
     does not record archive/upload plus TestFlight helper completion for that
     build.
3. If pending release work exists, finish the oldest pending release before
   merging another app-code PR unless Joe explicitly prioritizes a newer PR.
4. Then check open PRs targeting `main` and run the PR review workflow below.
5. If both queues are empty, report the sweep as clear and do not edit
   `docs/agent-log.md` unless a previous run left incomplete state to clarify.

## Pending Release Classification

Use this classification when deciding whether a merged PR requires TestFlight:

- Requires build bump/release by default: app source, SwiftUI/UI, data model,
  persistence, auth/sync/backend client behavior, Supabase schema/contracts used
  by the app, `project.yml`, Xcode project membership, tests that encode runtime
  behavior, QA-relevant launch flags, or user-facing copy/assets.
- Usually does not require build bump: docs-only, plans, agent-skill/process
  updates, scripts not used by the app binary, backend-only changes already
  deployed outside the iOS binary, and release/status docs.
- If uncertain, treat it as pending release unless the diff is clearly
  process/docs-only. Note the decision in `docs/agent-log.md`.

## Universal Linear Task Status Contract

Linear is the source of truth for rec.me task status. Slack messages may appear as
attachments or context on Linear issues, but this workflow must not use Slack as
the task queue.

Use the `recme` team's existing statuses this way:

- `Backlog`: captured or identified, but not yet accepted for implementation.
- `Todo`: accepted and ready to build, but no active implementation owner yet.
- `In Progress`: assigned or actively being built; a branch/worktree may exist.
- `In Review`: implementation PR is open, or the PR has merged but the app change
  has not yet reached TestFlight.
- `Done`: current pre-production completion state. The issue is merged to `main`
  and the relevant build has been uploaded/attached/approved or is otherwise
  available in TestFlight. A PR merge alone is not Done.
- `Canceled` / `Duplicate`: inactive; skip unless Joe explicitly asks for cleanup.

When production releases exist, update this contract so `Done` means shipped in a
production App Store version and introduce or rename a separate TestFlight
checkpoint if needed. Until then, TestFlight availability is the completion gate.

## Linear Issue Handling

For every PR reviewed or merged, identify the linked Linear issue(s) before
changing status. Prefer direct Linear issue IDs/URLs, then branch names, PR title,
PR body, commit messages, and attachments. Branches generated by Linear commonly
include issue keys such as `REC-1`.

- If a product/app issue is linked and the PR is open, ensure the issue is
  `In Review` and comment with the PR link, head SHA, and verification status.
- If the PR has blocking findings, keep the issue in `In Review` and comment with
  the blocker, requested fix, and tests run.
- After merge but before TestFlight, keep the issue in `In Review`; comment with
  the merge commit, build-number bump status, and pending release state.
- If App Store Connect access, signing, upload, or TestFlight processing blocks
  release completion, leave the issue in `In Review`; comment with the exact
  blocker and continuation commands/state.
- Move linked product/app issues to `Done` only after the merged change is
  available in TestFlight under the current build. Include build number, PR link,
  merge commit, TestFlight status, and what to test in the Linear comment.
- Docs-only, process-only, or skill-only PRs usually do not move product/app
  issues unless they are explicitly linked as the deliverable.

## PR Review Workflow

For each eligible PR targeting `main`:

1. Read the PR description, linked Linear issues, Slack attachments on those
   issues if present, changed files, diff against `origin/main`, and relevant
   source/tests/docs.
2. Use the gstack `review` skill as the primary pre-landing review lens when available.
3. If UI/UX changed, read `DESIGN.md` and evaluate visual hierarchy, safe areas, Dynamic Type, accessibility, tap targets, copy, screen composition, and consistency with the approved rec.me/Wander direction.
4. If backend, sync, auth, privacy, data, persistence, or visibility behavior changed, invoke `plan-eng-review` when the change has non-trivial engineering risk. For narrow low-risk changes, record why full invocation was not needed and still apply the plan-eng-review lens for data flow, trust boundaries, regression risk, test coverage, and failure modes.
5. Check for scope drift, unrelated generated junk, accidental signing/project churn, privacy/visibility regressions, SwiftUI state bugs, persistence bugs, and missing tests.
6. Run appropriate verification where feasible:
   - `xcodegen generate` if `project.yml` or project membership changed
   - `xcodebuild build` with `CODE_SIGNING_ALLOWED=NO`
   - `xcodebuild test` with `CODE_SIGNING_ALLOWED=NO`
   - simulator/screenshot checks for visual changes when available

## Review Output

- If blocking findings exist, do not merge. Leave a concise PR review/comment with blocking findings, file/line references, tests run, and exact requested fixes. Update `docs/agent-log.md`.
- If only non-blocking notes exist, include them in the PR comment and continue only if they do not require changes before TestFlight.
- If review identifies key architecture, data, test, performance, rollout, or release-risk decisions, pause before merge and flag them in the current thread plus the linked Linear issue or PR comment.

## Merge Gate

Merge only when all are true:

- gstack review finds no blocking issues, or equivalent review was completed and found no blockers.
- The PR matches its stated intent and has no unacceptable scope drift.
- Required build/tests pass, or any skipped test is explicitly justified as an environment blocker and risk is low.
- No unresolved required human decision remains.
- No hold/do-not-merge signal exists.
- The branch is mergeable into latest `main`.

If the gate is clean, squash-merge the PR into `main` and delete the branch only if safe. Do not merge with known blocking findings.

## TestFlight Follow-Up After App-Code Merge

After a successful app-code, UI, schema, testable behavior, or QA-relevant merge:

1. Update local `main` to latest `origin/main`.
2. Increment `CURRENT_PROJECT_VERSION` in `project.yml`. Do not change the marketing version unless Joe explicitly asks.
3. Run `xcodegen generate` so `Wander.xcodeproj/project.pbxproj` reflects the new build number.
4. Commit both `project.yml` and `Wander.xcodeproj/project.pbxproj` with a conventional TestFlight build bump message, then push `main`.
5. Run the relevant `xcodebuild build` and `xcodebuild test` commands from `AGENTS.md`.
6. Create a concise TestFlight "What to Test" description from the merged PR(s):
   - 1-2 lines on what changed for testers.
   - A short concrete checklist of what to test.
   - Known/deferred areas when useful.
   - Keep it under 4000 characters.
7. Upload the archive/build to TestFlight using the repo's documented or discoverable upload path and available signing credentials. If upload is blocked by credentials, signing, or missing workflow, stop after the pushed build-number bump and report the blocker clearly.
8. Run `node scripts/testflight-release.mjs` after upload succeeds to set export compliance, set TestFlight "What to Test" copy when provided, attach the build to the public group, and submit external beta review. Prefer:
   `node scripts/testflight-release.mjs --build-number <n> --what-to-test-file <path>`
   or:
   `node scripts/testflight-release.mjs --build-number <n> --what-to-test "<copy>"`
   If the helper cannot set the description, continue the release, record the
   limitation, and include the same testing copy in Slack.
9. Update `docs/agent-log.md` with build number, merge/commit hash, tests run, archive path, upload status, TestFlight status, TestFlight description status, Linear status updates, known issues, and next steps.
10. Move linked product/app Linear issues to `Done` only after TestFlight is available under the current pre-production contract.
11. Whenever a new TestFlight build is uploaded, attached to the public group, or confirmed available/processing for testing, post the required tester-facing release note to Slack `#testflight-feedback` (`C0BAA7DG2AC`).

If App Store Connect access is unavailable after a build-number bump:

- Leave `main` pushed with the bumped build number.
- Do not post a tester-facing "live" Slack note.
- Add a clear `docs/agent-log.md` handoff with build number, bump commit, merged
  PR(s), tests run, exact blocker, and exact archive/upload/helper commands for
  the next capable agent.
- Set the thread/inbox title to `Build <number> pending upload`.

Slack release note must include:

- app name `rec.me`
- build number
- whether the build is live/approved or still processing
- what changed for testers
- concrete testing checklist
- known issues or deferred areas
- public TestFlight link: `https://testflight.apple.com/join/knEhRa6t`
- request to reply in-thread with device, account/email if relevant, screenshots, and exact repro steps

Docs-only or process-only PRs do not need a build-number bump unless explicitly being packaged into a new TestFlight build. If skipping the bump, note that in `docs/agent-log.md`.
