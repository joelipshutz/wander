# Astir Events — flowchart and engineering handoff

Start with the **[Joe/Ryan engineering handoff](engineering-handoff.md)** for the two-agent work split, shared checkpoints and estimates. Open the **[full flowchart](astir-events-flowchart.html)** to review all **172 screen states in 13 continuous sections**, with screen previews visible and expandable in place.

## Open the screens

GitHub displays HTML source. Choose **Download raw file**, then open the downloaded HTML in Safari or Chrome. All preview images and the short motion comparison are embedded: no server, sign-in, Xcode build or network connection is needed. The file is about 35 MB; let its download finish.

Keep this directory together to use its specification and supplemental-diagram links. From an existing checkout, a separate review worktree avoids disturbing app work:

```sh
git fetch origin main
git worktree add --detach ../astir-events-review origin/main
open ../astir-events-review/docs/designs/astir-events/astir-events-flowchart.html
```

## Build plan

- [22 implementation tasks](implementation-tasks.md): dependencies, two work lanes, verification and alternative human/agent effort estimates.
- [Shared contracts](engineering-contracts.md): state machines, operations, permissions and cross-surface continuity.
- [Engineering plan and review report](engineering-plan.md): selected D1–D19 decisions and source evidence.
- [Nine remaining decision groups](engineering-open-decisions.md): affected clauses and tasks, with approved behavior kept separate.
- [Test plan](engineering-test-plan.md), [121-case mapping + 24 risk groups](test-review/coverage-map.md), [failure handling](engineering-failure-modes.md) and [QA journeys](events-qa-test-plan.md).
- [Performance review](performance-review/README.md) and [rollout/rollback](engineering-rollout.md).
- [Product specification](product-spec-draft.md), [requirements ledger](audit/requirements.md) and [September 14 amendments](revision-20260914/review-notes.md).

## Approval and validation status

This is the September 15 conditional engineering handoff for [REC-467](https://linear.app/recme/issue/REC-467/define-place-centered-events-guest-rsvp-attendance-and-follow-up). The issue was observed as Done; that status and this documentation merge do not approve open policies or prove Events is implemented. Joe and Ryan's product/design review remains in progress.

The full loop remains in scope. App Clip/browser RSVP, confirmation texts, guest-list access and RSVP management do not require a download. The installed app is required for the door QR. Staff admission and later explicit event check-in are distinct; the check-in creates one event-labeled canonical place visit. D9B adds prepared offline staff rosters, durable pending admission and server reconciliation before recap rights.

The HTML has 26 primary native mocks and 146 wireframe previews; 32 native variants appear in comparisons. Native images are fixtures from a separate design sandbox, not production feasibility evidence. The latest HTML is byte-for-byte identical to the reviewed workspace artifact. [Coverage](flowchart/continuous-coverage.json), [preview checks](flowchart/inline-preview-verification.json), [offline changes](flowchart/offline-door-update-verification.json) and [approval annotations](flowchart/approval-annotations-update-verification.json) document artifact validation. No Events runtime tests, benchmarks, migrations or releases were performed.

[Publication manifest](publication-manifest.json) records source and published hashes. Markdown source links use the immutable reviewed app baseline; local authoring-only references are labeled. Historical design audits retain their dated conclusions; later explicit amendments and the current decision inventory take precedence. The checked task graph has 22 unique packages and no dependency cycle. The 121-case mapping is complete as planning, not executed test coverage.

## Supplemental diagrams

These exports are the **earlier 165-screen snapshot**. They do not include the seven later offline-door states; use the HTML as the complete current review.

- [Compact overview](flowchart/astir-events-overview.svg)
- [Editable compact overview](flowchart/astir-events-overview.excalidraw)
- [All-screen connection map](flowchart/astir-events-all-screens.svg)
