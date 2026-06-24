---
name: recme-testflight-feedback-bug-catcher
description: |
  rec.me/Wander feedback-driven feature development and bug-fix workflow. Use
  when checking TestFlight/Slack/Linear feedback issues, turning tester feedback
  into a fix or feature PR, or creating PRs from rec.me/Wander tester reports.
  This skill is the shared source of truth for the former TestFlight feedback
  bug-catcher automation.
triggers:
  - testflight feedback
  - bug catcher
  - triage feedback
  - tester report
  - linear issue
  - slack feedback
---

# rec.me Feedback Feature/Bug Workflow

Use this skill for rec.me/Wander TestFlight feedback triage, feature development,
and bug-fix implementation. It centralizes the issue-checker workflow that used
to poll Slack directly. Linear is now the source of truth for task polling and
status. Treat tester requests as product input that can become feature work, not
only bug reports.

Compatibility note: keep the skill slug and directory name
`recme-testflight-feedback-bug-catcher` until all automations, symlinks, and
external references have been migrated. The human-facing workflow name is
"rec.me Feedback Feature/Bug Workflow."

## Safety Boundary

- Do not poll Slack as the task queue. Use Linear issues as the queue; Slack links
  or message attachments on Linear issues are context only.
- Do not reply in Slack or use Slack reactions from this workflow unless Joe explicitly asks otherwise.
- Do not merge, upload TestFlight, or post Slack analysis from this workflow.
- Do not move product/app issues to `Done`; the PR review/merge/explicit
  TestFlight release workflow owns `Done` after merge completion, with
  TestFlight as the gate only for issues explicitly scoped to release/QA
  validation.
- Treat Joe and Ryan's requested changes in Linear issues as approved by default only when the direction and implementation path are clear and safe.
- Surface approval-needed instead of implementing when direction is ambiguous, the implementation plan is unclear, the fix requires a real product/design/engineering decision, or the issue is privacy/security-sensitive, backend/schema/migration-heavy, or likely to change auth/sync/visibility semantics in a non-obvious way.
- Do not treat "came from Slack/TestFlight" as permission to skip planning. Many
  feedback items are feature requests with architecture, product, design, data,
  or rollout consequences.

## Required Setup

1. Use `/Users/joelipshutz/Developer/Wander (nametbd)` or an isolated worktree for implementation.
2. Follow repo `AGENTS.md` before non-trivial work:
   - `git fetch origin`
   - `git status --short --branch`
   - read recent `docs/agent-log.md`
   - decide whether an isolated worktree is needed
   - append/update `docs/agent-log.md`
3. Use the Linear issue as the task record. Update its status and comments as work progresses.
4. Use a `codex/<short-task>` branch/worktree from latest `origin/main`.

## Universal Linear Task Status Contract

Linear is the source of truth for rec.me task status. Slack messages may appear as
attachments or context on Linear issues, but this workflow must not use Slack as
the task queue.

Use the `recme` team's existing statuses this way:

- `Backlog`: captured or identified, but not yet accepted for implementation.
- `Todo`: accepted and ready to build, but no active implementation owner yet.
- `In Progress`: assigned or actively being built; a branch/worktree may exist.
- `In Review`: implementation PR is open, the merge/review gate is actively in
  progress, or the issue is explicitly TestFlight-gated and the requested build
  has not yet reached TestFlight.
- `Done`: implementation is merged to `main`, required validation passed, and no
  further app change is required. For issues explicitly scoped to TestFlight QA,
  release validation, or a user-requested TestFlight push, `Done` still requires
  the relevant build to be uploaded/attached/approved or otherwise available in
  TestFlight.
- `Canceled` / `Duplicate`: inactive; skip unless Joe explicitly asks for cleanup.

When production releases exist, update this contract so `Done` means shipped in a
production App Store version and introduce or rename a separate TestFlight
checkpoint if needed.

## Linear Issue Scan

Poll Linear for actionable rec.me/Wander issues, not Slack. Check the `recme`
team and relevant projects such as `mvp`, prioritizing issues in:

- `Backlog` for newly captured feedback that needs triage.
- `Todo` for accepted work ready to implement.
- `In Progress` for work already assigned or started by an agent.

Skip `In Review` issues unless Joe explicitly asks the issue-checker to inspect
them; PR/release handling owns that state. Skip `Done`, `Canceled`, and
`Duplicate` issues.

Actionable feedback includes bug reports, broken flows, confusing UX, visual/layout issues, accessibility issues, performance problems, crashes, missing expected behavior, backend/sync/auth/privacy/data issues, or tester requests that imply product/engineering work.

Use Slack attachments/permalinks on Linear issues only to understand original
tester context. Do not use Slack `:white_check_mark:` as task state. If an issue
is already represented by an open PR, ensure the Linear issue is `In Review` and
leave the PR/release workflow to finish it unless a new detail changes severity
or fix path.

Interpretation rule: if Joe or Ryan says "my pin" or otherwise refers to their own location on the map, default to the live current-location indicator/dot first, not saved-place ownership pins, unless the thread clearly says saved places or multiple place markers.

## Triage Workflow

For each actionable Linear issue:

1. Read the Linear title, description, comments, labels, project, assignee,
   attachments, and any Slack permalink attached to the issue.
2. Triage in Codex first.
3. Comment in Linear with the triage summary when the issue needs a durable
   decision, implementation plan, or handoff.
4. Classify the issue type first: `bug/regression`, `feature/enhancement`,
   `design/UX`, `backend/data`, `release/process`, or `decision-only`.
5. Classify severity (`P0`, `P1`, `P2`, `P3`), likely app area, likely cause, recommended fix path, test plan, and open questions with recommended answers.
6. Run the Engineering Review Gate below before implementation when the issue
   scope warrants it. Otherwise note why the gate was skipped.
7. Apply plan-design-review lens for UX, visual hierarchy, copy, affordance, accessibility, screen composition, or interaction issues.
8. Apply both lenses when cross-cutting.
9. Respect Wander/rec.me rules:
   - native iOS SwiftUI
   - Swift 6
   - iOS 17+
   - four bottom tabs only: Map, Add, Discover, Profile
   - map-first trusted place memory product
   - not lists/feed/travel/check-in/live-location
   - `DESIGN.md` governs UI
   - backend visibility/RLS is authoritative; client visibility policy is UI-only

## Engineering Review Gate

This is an invocation gate, not a vibe check. For gate-required work, actually
invoke the `plan-eng-review` skill before implementation. Do not merely say you
used an "eng lens." Prefer the indexed `plan-eng-review` skill when available;
if it is not indexed, read and follow
`/Users/joelipshutz/.claude/skills/gstack/.agents/skills/gstack-plan-eng-review/SKILL.md`.

Run `plan-eng-review` for:

- P0/P1 issues.
- Any feature/enhancement that introduces a new user-facing flow, new surface,
  new persisted state, new filtering/search semantics, or new cross-screen
  behavior.
- Auth, sync, backend, privacy, Supabase schema/RLS, data model, persistence,
  extraction, visibility, security, or migration work.
- Work that changes cross-screen app behavior, app-wide state, release flow, or
  any contract used by more than one feature.
- Work that changes how testers interpret trust, social visibility, map pins,
  search, save state, recommendations, or user identity.
- Plans likely to touch more than eight files, add more than two new
  classes/services, or introduce a new queue/cache/job/integration.
- Any issue where the test plan, failure modes, data flow, or implementation
  boundary is unclear.

Skipping `plan-eng-review` is acceptable for isolated copy changes, obvious
one-file UI polish, small template swaps, docs/process-only edits, or tests that
do not change runtime behavior. Also acceptable: tiny feature affordances that
stay on one screen, introduce no shared state, and reuse an existing tested code
path. Record the skip reason in `docs/agent-log.md`, the Linear comment, and the
final Codex report when implementing.

When the gate runs, the agent must produce an engineering review packet before
coding:

- Scope challenge: smallest complete version, existing code to reuse, and what
  is explicitly not in scope.
- Architecture/data-flow summary, including an ASCII diagram for non-trivial
  data flow or state changes.
- Failure modes: at least one realistic production failure per new code path and
  how the user would recover.
- Test plan: unit/integration/simulator coverage, edge cases, regressions, and
  any manual QA needed.
- Decision list: every unresolved architecture, data, test, performance, scope,
  or rollout question, each with an opinionated recommendation and tradeoff.

Decision handling:

- If `plan-eng-review` identifies architecture, data, test, performance, scope,
  or rollout decisions, stop before implementation.
- Surface each key decision in the current Codex/automation thread with a
  recommendation and tradeoff. If a native question tool is available, use it;
  otherwise write the decision brief in chat and pause. Do not bury decisions
  only in Linear, a PR body, or `docs/agent-log.md`.
- Also leave a Linear comment summarizing the blocked decision and recommended
  option so the issue record stays durable.
- Do not silently choose a direction for product-sensitive, security-sensitive,
  schema/data, sync, visibility, or release-risk decisions.
- Once Joe explicitly accepts a path, update the Linear comment and
  `docs/agent-log.md`, then proceed with implementation.
- During implementation, if new architecture, data, test, performance, scope,
  product, design, or rollout decisions appear that were not covered by the
  accepted plan, stop coding and surface them the same way before continuing.
  Do not "just finish the patch" when the discovered choice can change user
  behavior, data shape, trust semantics, test scope, or release risk.
- If the new decision is small and reversible, state that explicitly, recommend
  the default, record it in `docs/agent-log.md`, and continue only when the
  tradeoff is genuinely low risk. When in doubt, pause and ask.

Decision brief format when no native question tool is available:

```markdown
Decision needed: <short title>
Recommendation: <recommended option> because <one concrete reason>.
Options:
- A) <recommended option> - upside, downside, expected effort.
- B) <alternative> - upside, downside, expected effort.
What breaks if wrong: <user-visible or engineering consequence>.
```

Record the `plan-eng-review` outcome in the final Codex report:

- `not needed` with skip reason
- `clean` with the review summary
- `blocked on decision` with the decision link/context
- `converted to approval-needed` when the issue should not be auto-built

## Implementation Path For Auto-Approved Fixes

1. If the issue is in `Backlog` but the direction is clear and safe, move it to
   `Todo` or directly to `In Progress` when starting work. If direction is not
   clear or approval is needed, leave it in `Backlog` or `Todo` and comment with
   the decision needed.
2. Complete the Engineering Review Gate before claiming implementation. If the
   gate is required and returns unresolved decisions, stop and flag them in the
   current thread before executing.
3. When starting implementation, assign/claim the Linear issue when possible,
   move it to `In Progress`, and comment with branch/worktree.
4. Create a `codex/<short-task>` branch/worktree from latest `origin/main`,
   preferably using the Linear issue key in the branch name.
5. Keep `docs/agent-log.md` current with goal, Linear issue, engineering review
   gate outcome, status, files touched, commands, tests, and final outcome.
6. Make the smallest safe fix that addresses the tester feedback.
7. Re-check the Decision handling rules during implementation whenever the code
   path, data shape, UI behavior, test scope, or release risk changes from the
   reviewed plan.
8. Run relevant tests/builds. For UI changes, run simulator/screenshot checks when feasible.
9. Commit with a conventional commit message.
10. Push the branch and open a PR to `main` with a concise description, Linear
   issue link, source Slack link if applicable, test results, and known issues.
11. Move the Linear issue to `In Review` and comment with the PR link, head SHA,
   tests run, and known gaps.
12. Do not merge, upload TestFlight, move issues to `Done`, or post Slack analysis
   from this workflow.

## Completion

- This workflow is complete when it has either produced an implementation PR and
  moved the Linear issue to `In Review`, or it has left a clear approval-needed /
  follow-up-needed Linear comment without pretending the issue is done.
- Do not mark a Linear issue `Done`; `Done` requires merge to `main` plus any
  issue-specific release gate, and is owned by the PR review/merge/explicit
  TestFlight release skill.
- If one Linear issue contains multiple actionable requests, move it to
  `In Review` only after every in-scope request has an open implementation PR or
  an explicit Joe-approved non-implementation outcome. Otherwise split the issue
  or comment with completed and remaining subitems.
- Output a concise Codex report with Linear issue link, source Slack link if
  applicable, severity, likely area, engineering review gate outcome, decision,
  PR link if created, recommended next action, tests run, and open questions.
