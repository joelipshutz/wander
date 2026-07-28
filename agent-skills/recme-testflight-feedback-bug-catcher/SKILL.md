---
name: recme-testflight-feedback-bug-catcher
description: |
  rec.me/Wander feedback triage and implementation workflow. Use when checking
  TestFlight/Slack/Linear feedback, triaging a new report once, or turning an
  accepted rec.me issue into a feature/fix PR. Linear is the source of truth.
triggers:
  - testflight feedback
  - bug catcher
  - triage feedback
  - tester report
  - linear issue
  - slack feedback
---

# rec.me Feedback Feature/Bug Workflow

Use this skill for rec.me/Wander tester feedback, product requests, bug triage,
and implementation. Keep the directory slug for compatibility with existing
automations; the human-facing workflow is "rec.me Feedback Feature/Bug
Workflow."

## Safety Boundary

- Use Linear as the queue. Slack links/attachments are source context, not task
  state. Do not poll or react in Slack unless Joe explicitly asks.
- Triage each issue once. Do not reclassify accepted `Todo` work on every scan
  or reconstruct decisions already recorded in Linear.
- Do not merge, upload TestFlight, add build numbers, or post tester release
  notes from this workflow. The PR/release workflow owns merge and the rolling
  `Next TestFlight` manifest.
- Treat clear, safe requests from Joe or Ryan as approved. Surface a decision
  before implementation when direction is ambiguous, architecture is unclear,
  or the work is privacy/security-sensitive, schema/migration-heavy, or likely
  to change auth/sync/visibility semantics.
- Feedback can be a feature request, not just a bug. "Came from TestFlight" is
  not permission to skip product/design/engineering review.
- `docs/agent-log.md` is frozen history. Put current state in Linear and the PR.

## Required Setup

1. Work in `/Users/joelipshutz/Developer/Wander (nametbd)` or an isolated
   worktree.
2. Follow `AGENTS.md`: fetch `origin`, inspect status/worktrees, read the Linear
   issue and linked branch/PR, and protect unrelated local changes.
3. Use the Linear issue as the task record. Keep status, assignee, branch,
   decisions, validation, blockers, and exact restart steps current there.
4. Implement on `codex/<short-task>` (or the active agent's matching prefix)
   from latest `origin/main`.

## Linear Status Contract

- `Backlog`: untriaged feedback, or triaged feedback waiting on a real decision.
- `Todo`: triaged, accepted, and ready to implement. Do not triage it again.
- `In Progress`: actively claimed or being implemented.
- `In Review`: an implementation PR is open.
- `Done`: implementation is merged to `main` and required merge validation
  passed. Waiting for a later TestFlight batch does not keep it open.
- `Canceled` / `Duplicate`: inactive.

TestFlight packaging and QA checklists live on the separate rolling
`Next TestFlight` release record. If later tester QA finds a regression, reopen
the implementation issue or create a focused bug with that build as evidence.

## Triage-Once Scan

Scan the `recme` team and relevant projects such as `mvp` in this order:

1. `Backlog` issues that have not yet received a structured triage outcome.
2. `Todo` issues ready to implement, using the accepted outcome already present.
3. `In Progress` issues assigned to the active agent or needing a documented
   resume/handoff.

Skip:

- `Backlog` issues whose latest durable outcome is an unanswered comment headed
  `Decision needed:`. Revisit only after a human answer or material new evidence.
- `Todo` issues for re-triage; inspect only enough to implement the accepted
  scope or detect genuinely contradictory new information.
- `In Review`, unless Joe asks to inspect the PR or new evidence changes the fix.
- `Done`, `Canceled`, and `Duplicate`.

If an open PR already represents the issue, ensure it is `In Review` and leave
landing to the PR/release workflow.

Interpretation rule: when Joe or Ryan says "my pin" or their own location on the
map, default to the live current-location indicator first, not saved-place
ownership pins, unless the report clearly names saved places or multiple markers.

## Triage Workflow

For each untriaged actionable issue:

1. Read title, description, comments, labels, project, assignee, attachments,
   timestamps, and attached Slack context.
2. Identify the exact user problem and whether remote evidence can change the
   next action.
3. Invoke `recme-linear-log-triage` only for useful auth, save/sync,
   Supabase/RLS/RPC, backend-data, visibility, missing-place, or timestamped
   reports. Do not pull logs for every issue.
4. Classify type: `bug/regression`, `feature/enhancement`, `design/UX`,
   `backend/data`, `release/process`, or `decision-only`.
5. Classify severity and set Linear priority consistently:
   - P0 -> Urgent
   - P1 -> High
   - P2 -> Medium
   - P3 -> Low
6. Record likely area/cause, smallest safe fix, test plan, evidence, and open
   questions in one structured Linear comment.
7. End triage in exactly one durable state:
   - accepted and ready -> `Todo`;
   - starting immediately -> assign/claim and `In Progress`;
   - real decision required -> remain `Backlog` with a comment headed
     `Decision needed:` and a recommendation/tradeoff;
   - not actionable -> `Canceled` or `Duplicate` with rationale.
8. Run the engineering/design review gates below before implementation when the
   scope warrants them.

Respect repo direction: native SwiftUI, Swift 6, iOS 17+, four tabs (Map, Add,
Discover, Profile), map-first trusted place memory, `DESIGN.md` for UI, and
Supabase RLS as authoritative for visibility.

## Engineering Review Gate

Actually invoke `plan-eng-review` before implementation for:

- P0/P1 issues;
- a new user-facing flow/surface, persisted state, search/filter semantics, or
  cross-screen behavior;
- auth, sync, backend, privacy, schema/RLS, data model, persistence, extraction,
  visibility, security, or migration work;
- changes to app-wide state, release flow, or a multi-feature contract;
- changes to tester trust around identity, map pins, search, save state,
  recommendations, or social visibility;
- likely scope above eight files, more than two new classes/services, or a new
  queue/cache/job/integration; or
- unclear data flow, failure modes, test plan, or implementation boundary.

It may be skipped for docs/process-only edits that do not alter runtime, isolated
copy, obvious one-file UI polish, small template swaps, tests-only work, or a
tiny affordance using an existing tested path. Record the specific skip reason
in Linear and the PR/final report.

When invoked, produce before coding:

- scope challenge and smallest complete version;
- architecture/data-flow summary and ASCII diagram when non-trivial;
- realistic failure modes and user recovery;
- unit/integration/simulator/manual QA plan; and
- every unresolved architecture/data/test/performance/scope/rollout decision,
  with a recommendation and tradeoff.

If the review exposes a material decision, stop before implementation. Ask in
the current thread and add a `Decision needed:` Linear comment. Continue only
after Joe/Ryan accepts a path. If implementation uncovers a new material choice,
pause the same way; do not silently finish a patch that changes user behavior,
data shape, trust semantics, or release risk.

Apply `plan-design-review` for material hierarchy, copy, affordance,
accessibility, composition, or interaction changes, and both lenses when the
issue is cross-cutting.

Decision brief when no native question tool is available:

```markdown
Decision needed: <short title>
Recommendation: <option> because <concrete reason>.
Options:
- A) <recommended option> — upside, downside, effort.
- B) <alternative> — upside, downside, effort.
What breaks if wrong: <user-visible or engineering consequence>.
```

## Implementation Path

1. Start only from `Todo` or an explicitly approved `Backlog` issue. Claim it,
   move it to `In Progress`, and comment with branch/worktree.
2. Complete required review gates and resolve decisions before coding.
3. Create the isolated branch/worktree from latest `origin/main`.
4. Make the smallest complete fix that satisfies the accepted outcome.
5. Re-check the decision gate if scope, data, behavior, tests, or release risk
   changes during implementation.
6. Run proportionate tests/builds and simulator/screenshot QA for visual work.
7. Commit conventionally, push, and open a PR linked to Linear and original
   Slack context when applicable. Include tests and known gaps.
8. Move the issue to `In Review` and comment with PR, head SHA, validation, and
   exact remaining work.
9. Stop. Do not merge or update `Next TestFlight`; the landing workflow does
   both after the PR passes review.

## Completion

This workflow completes when it either:

- produces an implementation PR and moves the issue to `In Review`; or
- leaves a durable `Decision needed:`/follow-up outcome without pretending the
  issue is ready.

Do not move the issue to `Done`; the landing workflow does so after merge. If
one issue contains multiple requests, split it or account for every in-scope
item before `In Review`.

Report: Linear link, source Slack link if any, severity/priority, area, evidence
decision, review-gate outcome, PR, tests, next action, and open questions.
