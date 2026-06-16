---
name: recme-testflight-feedback-bug-catcher
description: |
  rec.me/Wander TestFlight feedback triage and implementation workflow. Use when
  checking Slack TestFlight feedback, turning tester feedback into a fix, or creating
  PRs from rec.me/Wander tester reports. This skill is the shared source of truth for
  the former TestFlight feedback bug-catcher automation.
triggers:
  - testflight feedback
  - bug catcher
  - triage feedback
  - tester report
  - slack feedback
---

# rec.me TestFlight Feedback Bug Catcher

Use this skill for rec.me/Wander TestFlight feedback triage and implementation. It
centralizes the Slack triage workflow that used to live directly in Joe's local
Codex automation.

## Safety Boundary

- Do not reply in Slack from this workflow. Slack interaction is reactions only unless Joe explicitly asks otherwise.
- Do not merge, upload TestFlight, or post Slack analysis from this workflow.
- Treat Joe and Ryan's requested changes in `#testflight-feedback` as approved by default only when the direction and implementation path are clear and safe.
- Surface approval-needed instead of implementing when direction is ambiguous, the implementation plan is unclear, the fix requires a real product/design/engineering decision, or the issue is privacy/security-sensitive, backend/schema/migration-heavy, or likely to change auth/sync/visibility semantics in a non-obvious way.

## Required Setup

1. Use `/Users/joelipshutz/Developer/Wander (nametbd)` or an isolated worktree for implementation.
2. Follow repo `AGENTS.md` before non-trivial work:
   - `git fetch origin`
   - `git status --short --branch`
   - read recent `docs/agent-log.md`
   - decide whether an isolated worktree is needed
   - append/update `docs/agent-log.md`
3. Create or claim a Mission Control task for non-trivial implementation when Mission Control is reachable.
4. Use a `codex/<short-task>` branch/worktree from latest `origin/main`.

## Feedback Scan

Check Slack `#testflight-feedback` (`C0BAA7DG2AC`) for new actionable rec.me/Wander feedback.

Actionable feedback includes bug reports, broken flows, confusing UX, visual/layout issues, accessibility issues, performance problems, crashes, missing expected behavior, backend/sync/auth/privacy/data issues, or tester requests that imply product/engineering work.

Skip messages or threads that are already marked with `:white_check_mark:`, broad release announcements, pure praise, duplicates already triaged in the same thread, or anything already represented by an open PR unless a new detail changes severity or fix path.

Interpretation rule: if Joe or Ryan says "my pin" or otherwise refers to their own location on the map, default to the live current-location indicator/dot first, not saved-place ownership pins, unless the thread clearly says saved places or multiple place markers.

## Triage Workflow

For each actionable message or thread:

1. Add `:airplane_departure:` before triage.
2. Read the full Slack thread and capture the permalink.
3. Triage in Codex first.
4. Classify severity (`P0`, `P1`, `P2`, `P3`), likely app area, likely cause, recommended fix path, test plan, and open questions with recommended answers.
5. Apply plan-eng-review lens for backend, sync, auth, extraction, privacy, data model, persistence, visibility, or regression-risk issues.
6. Apply plan-design-review lens for UX, visual hierarchy, copy, affordance, accessibility, screen composition, or interaction issues.
7. Apply both lenses when cross-cutting.
8. Respect Wander/rec.me rules:
   - native iOS SwiftUI
   - Swift 6
   - iOS 17+
   - four bottom tabs only: Map, Add, Discover, Profile
   - map-first trusted place memory product
   - not lists/feed/travel/check-in/live-location
   - `DESIGN.md` governs UI
   - backend visibility/RLS is authoritative; client visibility policy is UI-only

## Implementation Path For Auto-Approved Fixes

1. Create or claim a Mission Control task if this is non-trivial and Mission Control is reachable.
2. Create a `codex/<short-task>` branch/worktree from latest `origin/main`.
3. Keep `docs/agent-log.md` current with goal, status, files touched, commands, tests, and final outcome.
4. Make the smallest safe fix that addresses the tester feedback.
5. Run relevant tests/builds. For UI changes, run simulator/screenshot checks when feasible.
6. Commit with a conventional commit message.
7. Push the branch and open a PR to `main` with a concise description, Slack feedback link, test results, and known issues.
8. Do not merge, upload TestFlight, or post Slack analysis from this workflow.

## Completion

- Add `:white_check_mark:` only after the message has either produced an approval-needed triage report or an implementation PR.
- Output a concise Codex report with Slack link, severity, likely area, decision, PR link if created, recommended next action, tests run, and open questions.
