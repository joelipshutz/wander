# AGENTS.md

Repo guidance for Codex, Claude Code, OpenClaw, and any developer joining Wander.

## Project Overview

rec.me, formerly Wander, is a native iOS social map for remembering places worth returning to and discovering places through trusted people.

North Star: when someone needs a place, rec.me shows where trusted people have actually been, what they thought, and whether it fits the moment.

Current wedge: trusted people's place memories become a searchable map you can actually use.

Do not reframe this as a lists app, public feed, travel-only app, check-in game, restaurant-only ranking app, or live-location product.

## Coordination And Durable Records

`docs/agent-log.md` is a frozen historical archive. Do not read it for current
state, append to it, or open a PR whose only purpose is recording work that is
already represented in Linear, a PR, git history, App Store Connect, or Slack.

Before non-trivial work:

- Find or create the required Linear issue and use it as the task record.
- Run `git fetch origin`, `git status --short --branch`, and
  `git worktree list` before editing.
- Check the Linear assignee/status, linked branch or PR, and local worktrees for
  overlapping work. Use an isolated worktree when the current checkout is dirty,
  another agent may be active, or the task touches high-conflict files.
- Treat uncommitted or untracked files you did not create as belonging to Joe,
  Ryan, or another agent. Do not revert them.

During work and at handoff:

- Put plans, decisions needed, validation, blockers, branch/worktree, and exact
  restart steps in the Linear issue and PR. Do not duplicate routine progress in
  a repo-wide diary.
- Put durable product or engineering decisions in `docs/decisions.md` and real
  unresolved decisions in `docs/open-questions.md`.
- If local-only work is incomplete, leave a Linear comment naming the worktree,
  branch, last verified commit, commands already run, and exact next action.

## Agent Execution Efficiency

Be conclusive and preserve human control, while keeping routine mechanics out
of repeated model turns.

- Organize non-trivial work into a small number of named phases. Give the user
  one compact update at each phase transition with evidence established and the
  next possible human gate. Send another update only for a state change,
  decision, intervention, or unexpected failure; do not narrate unchanged
  polling or every connector call.
- Batch independent read-only checks and reuse resolved issue, PR, branch,
  commit, build, and account identifiers. Avoid broad connector discovery or
  history reads when a direct lookup is available.
- Keep judgment in the agent and deterministic mechanics in commands/scripts.
  Run long builds, tests, archives, and poll loops in one long-lived session,
  prefer quiet output, and inspect focused diagnostics only after failure.
- Preserve explicit intervention for credentials, passwords, device codes,
  signing, approvals, permission changes, destructive actions, product/data
  decisions, and unexpected validation failures. Do not optimize away these
  gates or claim success while one is outstanding.
- After a pause, perform one compact drift check and resume from the durable
  checkpoint. Do not replay completed reviews, tests, connector discovery, or
  release-note reconstruction.
- Treat two unchanged environment/auth failures as a human gate. Record the
  exact restart state instead of opening an unbounded retry loop.
- Never copy raw command output, prompts, credentials, environment values, or
  Codex task content into repo metrics. When usage analysis is requested, use
  `scripts/codex-task-metrics.mjs` and report aggregate counters only. Label raw
  rollout token counters separately from any app-reported/goal token total.

## Required Linear Tracking

Agents must work from a Linear issue for any non-trivial feature, fix, release,
or docs/process change.

Before starting implementation:

- Find the existing Linear issue if the work came from Linear, TestFlight
  feedback, or a prior planning thread.
- If the work starts in chat and no issue exists yet, create a Linear issue in
  the `recme` team that captures the user request, assign it to the active
  owner when clear, and move it to `In Progress` before editing code.
- Triage feedback once. Keep untriaged work in `Backlog`; move accepted,
  implementation-ready work to `Todo`. Do not re-triage `Todo` issues during
  later scans or again when packaging a release.
- If a real product or architecture choice blocks acceptance, leave the issue
  in `Backlog` with an unanswered comment headed `Decision needed:`. Revisit it
  only after a human answer or material new evidence.
- Link the PR or branch back to the issue once one exists.

During and after work:

- Keep the Linear issue status aligned with reality: `In Progress` while
  actively implementing, `In Review` while its implementation PR is open, and
  `Done` after the implementation is merged to `main` and required validation
  passes. TestFlight packaging is tracked by the separate rolling
  `Next TestFlight` issue, not by holding merged product issues in `In Review`.
- Add a Linear comment with validation, TestFlight/build links, known follow-up,
  or blocker details when the work is meaningful enough that future agents
  would otherwise have to reconstruct it from chat.
- Every PR must include one valid hidden `recme-testflight-payload` JSON block:
  `ship`, `exclude`, or `release-operation`. After merge, require the main-push
  manifest workflow to classify the exact commit in the machine-owned GitHub
  issue. Keep the rolling `Next TestFlight` Linear issue as the human status
  mirror; it is not the uploader's data source.

## Collaboration And Git Workflow

`main` is the integration branch. Do not do non-trivial feature, fix, or release work directly on `main`; use a short-lived branch and open a PR back to `main`.

Branch prefixes:

- `joe/<short-task>` for Joe
- `ryan/<short-task>` for Ryan
- `codex/<short-task>` for Codex
- `claude/<short-task>` for Claude
- `openclaw/<short-task>` for OpenClaw

Prefer a separate worktree for agent implementation when Joe, Ryan, or another agent may also be working locally. Before deciding, inspect `git worktree list`, `git status --short --branch`, and the Linear issue/linked PR. If a worktree is needed, create it from latest `origin/main` and do the work there:

```bash
git worktree add ../Wander-worktrees/<short-task> -b codex/<short-task> origin/main
```

Before editing, agents must run `git fetch origin`, check `git status --short --branch`, inspect existing worktrees with `git worktree list`, and inspect the Linear issue plus linked branch/PR. If there are uncommitted or untracked files, assume they belong to Joe, Ryan, or another agent. Do not edit overlapping files without calling out the overlap first.

Avoid parallel edits to high-conflict files unless explicitly coordinated:

- `Wander.xcodeproj/project.pbxproj`
- `project.yml`
- `Wander/Features/Map/MapScreen.swift`
- `Wander/Services/WanderLocalStore.swift`
- Supabase migrations

For non-trivial feature, fix, refactor, release, or docs/process changes, agents must end the session by either:

- Opening or updating a ready PR if the work is complete.
- Opening or updating a draft PR if the work is incomplete.

This applies especially to Ryan-owned work on `ryan/<short-task>` branches. Ryan's agent should push its branch and open or update the PR before stopping without waiting for a separate human prompt, unless Ryan explicitly says not to push or not to open a PR.

When a pushed branch is intended for local Xcode testing, the handoff is not
complete until the agent opens that branch's worktree `Wander.xcodeproj` in
Xcode and verifies that Xcode's Branch Chooser shows the intended branch. Open
the isolated worktree as its own Xcode project instead of switching or
overwriting another active checkout.

Before merging to `main`, update the branch from latest `origin/main`, resolve conflicts, inspect the PR diff for unrelated files or generated junk, run the relevant build/tests, and record outcome, tests, known issues, and next steps in the PR and Linear. Prefer squash merging PRs into `main`, then delete the branch.

## Shared Agent Skills

Repo-owned agent workflows live in `agent-skills/`. These files are the shared
source of truth for recurring Codex/Claude/OpenClaw workflows that should behave
the same across Joe's machine, Ryan's machine, and scheduled automations.

Install or verify local symlinks with:

```bash
scripts/install-agent-skills.sh
scripts/install-agent-skills.sh --check
```

The installer links repo skills into local indexed skill roots:

- `~/.codex/skills`
- `~/.claude/skills`
- `~/.openclaw/workspace/skills`

If the local Codex instance does not list a repo-owned skill, read the
corresponding `agent-skills/<skill-name>/SKILL.md` directly and follow it.

Current shared skills:

- `recme-pr-review-merge-release` - use when asked to review, merge, land, ship, or release a rec.me/Wander PR.
- `recme-testflight-feedback-bug-catcher` - use when checking or acting on rec.me/Wander Linear issues or TestFlight feedback.
- `recme-linear-log-triage` - use when a rec.me/Wander Linear issue would benefit from PostHog/Supabase evidence, especially auth, save, sync, visibility, backend, data, or screenshot-with-timestamp bugs.

## Tech Stack

- Native iOS, iPhone-first.
- SwiftUI, Swift 6 mode, iOS 17+.
- SwiftData for local persistence and offline-first cache.
- MapKit/CoreLocation for maps and place lookup.
- PhotosUI later for photo capture/import.
- XcodeGen owns project generation through `project.yml`.
- Planned backend: Clerk for identity/account UX, Supabase Postgres/RLS/PostGIS/storage/functions for app data.
- Current M2 implementation uses local seeded data through `WanderStore` and deterministic fakes.

## How To Run Locally

Generate the Xcode project after changing source files or `project.yml`:

```bash
xcodegen generate
```

Build:

```bash
xcodebuild build -project Wander.xcodeproj -scheme Wander -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

Test:

```bash
xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

If Xcode plugin/CoreSimulator access fails under a sandbox, rerun from a normal terminal or with approved elevated access.

## Architecture

Important folders:

- `Wander/App/` - app entry point and root tab shell.
- `Wander/DesignSystem/` - SwiftUI tokens and shared components.
- `Wander/Features/Map/` - map surface and selected place sheet.
- `Wander/Features/Add/` - current-location/manual/link/photo add flow.
- `Wander/Features/Discover/` - smart filters, search, people/profile lookup.
- `Wander/Features/Profile/` - owner profile, other-user profiles, graph lists.
- `Wander/Features/Settings/` - settings gear surface from Profile.
- `Wander/Models/` - local models, enums, visibility/sync contracts.
- `Wander/Services/` - fixtures, local store, repository/parser/provider protocols.
- `WanderTests/` - unit and contract tests.
- `preview/follow-profile-settings-mocks/` - approved visual handoff source.
- `docs/` - spec, plans, decisions, handoff, setup, reviews, agent log.

Core rules:

- Views must not call Clerk or Supabase directly. Use repository/protocol boundaries.
- Supabase RLS is authoritative for social visibility; client visibility policy is UI-only.
- Four bottom tabs only: Map, Add, Discover, Profile. Settings opens from Profile gear.
- `project.yml` is the Xcode source of truth. Regenerate with XcodeGen instead of hand-editing project membership.
- Link/photo capture in M2 is an honest unresolved-draft shell until backend extraction jobs exist.
- Native Contacts permission is planned later; M2 uses `FakeContactProvider` plus username search.

## Supabase Schema, RLS, And RPC Policy

Supabase migrations are app behavior, not incidental backend plumbing. Treat
schema, RLS, grants, and RPC definitions as production contracts.

Rules:

- Before creating, replacing, dropping, or resetting a Supabase function, inspect
  all prior migrations that define or alter that function. Preserve and restate
  its required security posture, `search_path`, grants, volatility, return type,
  and RLS assumptions in the new migration.
- Do not recreate an RPC as `security invoker` or `security definer` by default.
  Choose explicitly and document why in the migration or agent log.
- `security definer` RPCs must be narrow, grant execute only to required roles,
  pin `search_path`, and scope user-owned writes through `app.current_user_id()`
  or an equivalent authenticated-claim helper. Callers must not be able to choose
  another user's id.
- Any migration that changes auth, sync, visibility, save flows, follows,
  profiles, RLS, policies, or RPC contracts must include a regression test or a
  direct hosted verification query that checks the relevant policy/security
  posture. For recreated RPCs, add metadata assertions for `prosecdef`,
  `proconfig`, and grants when relevant.
- Treat `question_definitions.value_type`, `place_attributes.value_type`, and
  every iOS `PlaceAttributeDraft.valueType` as one shared cross-layer contract.
  Any new or changed iOS attribute value type must update both Supabase check
  constraints in the same branch, add SQL regression coverage, and exercise the
  exact production payload through authenticated `public.save_own_place` in
  `scripts/supabase-smoke-test.mjs`. An iOS unit test or a successful local-only
  save is not sufficient because a constraint failure rolls back the entire
  remote place/user-place transaction.
- Before merging or releasing a change to save-form questions, tags, cuisines,
  or personal labels, search the diff for new `valueType:` literals and verify
  each one against the hosted constraint plus the rolled-back smoke transaction.
- Any migration that creates, replaces, grants, revokes, or otherwise changes an
  iOS-called Supabase RPC must run the hosted smoke test before handoff:
  `npm --prefix scripts ci --ignore-scripts`, then
  `node scripts/supabase-smoke-test.mjs`. The pinned smoke tool uses reserved
  smoke identities inside one rolled-back transaction to exercise owner,
  collaborator, stranger, and anonymous access and catch hosted-only
  `403 permission denied for function ...` failures.
- If the smoke test lacks coverage for the RPC or RLS path being changed, extend
  `scripts/supabase-smoke-test.mjs` in the same branch instead of relying on a
  one-off manual query. Keep the test lightweight, idempotent, and safe to run
  against hosted Supabase; fixture and behavior mutations must roll back.
- Prefer `supabase db push --linked --yes` only after the local migration has
  been reviewed and the target project is confirmed. After applying a hosted
  migration, verify with `supabase migration list --linked` and, for sensitive
  functions, `supabase db query --linked` against `pg_proc`, `pg_namespace`,
  and grants.
- If `supabase test db` or pgTAP cannot run because Docker or local tooling is
  unavailable, do not call that a pass. Record the blocker, run the strongest
  hosted metadata/smoke verification available, and leave the exact gap in the
  PR and Linear issue.
- For data resets, backfills, or migrations that intentionally delete or rewrite
  tester data, document what persists, what is wiped, whether local app state can
  rehydrate stale rows, and the TestFlight/user-facing consequence.

Observability policy:

- For Linear issues involving auth, save/sync, social visibility, backend data,
  RLS, Supabase RPCs, or a screenshot/report with a useful timestamp, check
  PostHog and/or Supabase evidence when it can materially reduce guesswork.
- Do not make log pulls mandatory for every issue. Skip them for pure copy,
  visual polish, straightforward local UI bugs, or cases where logs cannot change
  the next action.
- Keep analytics and Linear comments non-PII by default: use internal user ids,
  event names, coarse error categories, counts, sync states, build numbers, and
  timestamps. Do not paste place notes, emails, precise coordinates, auth tokens,
  API keys, or raw private payloads.
- When evidence is insufficient, say exactly what is missing: build number,
  tester, approximate timestamp, screenshot, repro steps, or local Xcode console
  logs.

## Current Priorities

1. Fix M2 visual QA issues on real simulator sizes, starting with Map screen scale/orientation/safe areas.
2. Keep M2 local loop working: map, add, discover, profile, settings, follow/unfollow/block, visibility, drafts.
3. Move next to M3 only after the UI baseline is acceptable: Clerk + Supabase schema/RLS foundation.
4. Preserve docs as source of truth for new contributors: start with `docs/codex-handoff.md`, `docs/roadmap.md`, and `docs/decisions.md`.

## Known Issues And Gotchas

- The first native M2 UI pass is functionally wired but visually poor on simulator screenshots: map content appears undersized/letterboxed and controls are oversized/crowded. Treat this as the active UI bug.
- `preview/follow-profile-settings-mocks/` is the approved visual baseline. Do not generate a competing design direction unless Joe explicitly asks.
- Existing handoff mocks are a reference, not production code. Recreate the intent natively in SwiftUI.
- UI copy says Everyone/Friends/Self, but backend values are `followers`/`mutuals`/`self`. Ordinary profile/social reads still treat `followers` as followers-visible. REC-253 adds one narrow exception: Featured may use a non-private account's Everyone check-in only as an anonymous place-level aggregate; it does not expose the contributor or their save content.
- Follow graph is one-way follows; friends are mutual follows.
- Blocks are hard blocks: blocked users should disappear from search, lists, profiles, map results, and stale views.
- There may be local Xcode signing/team edits in `Wander.xcodeproj/project.pbxproj` from opening the project. Do not commit project signing churn unless intentional.

## Style Rules

- Follow `DESIGN.md` before changing UI.
- Promote visual tokens from `preview/follow-profile-settings-mocks/tokens.css` into SwiftUI tokens 1:1.
- Warm, map-first, playful utility. Avoid sterile SaaS, generic travel blue, influencer-feed language, or all-beige drift.
- Use SF Symbols/native controls where appropriate. Emoji may appear in category/question affordances only if accessible and not structural.
- Respect safe areas, Dynamic Type, 44pt minimum tap targets, keyboard, and the home indicator.
- iPhone-first. Do not stretch phone UI into desktop/iPad layouts without a specific side-panel plan.

## Brand And App Icon

- The canonical public app name is `rec.me`. Internal `Wander*` names, the
  Xcode target/scheme/module, and bundle id `com.grayline.wander` remain stable
  unless a separate migration explicitly changes them.
- Before editing the app icon, read `docs/brand/recme-app-icon.md`.
- The canonical icon master is
  `Wander/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png`.
- The approved icon is the warm matte neighborhood map in
  `Wander/Resources/AppIcon.icon/Assets/recme-warm-map-original.png`: cream and
  peach raised buildings, a sage park with one orange-red tree pin, a blue
  ocean edge, an irregular palm row contained within the coastal green strip,
  and centered black-serif `rec.me`. Keep the selected full-frame composition
  matte and do not crop, reframe, move trees, or add Liquid Glass effects
  without explicit approval.
- Regenerate the fallback master with `scripts/generate-app-icon-master.swift`;
  it validates and copies the approved Icon Composer source byte-for-byte.
- Regenerate all platform renditions with
  `scripts/generate-app-icon-renditions.sh`, then retain the
  `BuildConfigurationTests` size, alpha, and discoverability coverage.

## Analytics Maintenance

Before changing a user-facing flow, read `docs/analytics.md` and search the flow for `WanderAnalyticsEvents`. Analytics changes are part of the feature contract:

- instrument successful state transitions in the store/domain layer where practical;
- emit a raw event plus `engagement_action_performed` when an action maps to Connect, Expression, or Status;
- never log place/contact/profile content, coordinates, messages, raw search text, URLs, tokens, or private backend payloads;
- add contract/privacy tests and update `docs/analytics.md` when events or properties change;
- update and check `scripts/posthog-product-dashboard.mjs` when a dashboard metric changes;
- do not hand-edit PostHog resources tagged `recme:managed`; apply the checked-in dashboard script;
- keep Monetization blank until an explicit product decision defines it.
- keep notification delivery/frequency analytics aggregate-only on the server:
  never export recipient/event/actor/APNs IDs, tokens, copy, deep links, or
  payload data to PostHog; compute per-recipient distributions inside Supabase.

Run `npm --prefix scripts run analytics:check` for every analytics/dashboard change, then run the relevant iOS tests. Before release, validate changed events in PostHog using a non-production/test account and confirm both expected properties and the absence of private payloads.

The cross-project account and service map lives at
`/Users/joelipshutz/Developer/grayline/ops/service-account-registry.json`.
Read it before creating, logging into, configuring, or rotating any hosted
analytics/project resource, and update it in the same task when an identity,
organization, project, dashboard, region, or env-var reference changes. The
registry must contain identifiers and secret references only—never token or API
key values.

rec.me Clerk and Supabase owner access uses the verified
`joe@bondaiapp.com` Google identity. Clerk app/instance IDs, the Supabase
organization and project refs, and the current production-cutover state live in
the registry. Do not substitute Joe's personal or SwayGenie Google identities,
and do not infer a different owner from a local token name.

rec.me analytics currently belongs to the `Grayline Studio` PostHog organization
under Joe's `jolipshutz@gmail.com` Google login: project `rec.me` / ID `557259`,
dashboard `rec.me Product Funnel` / ID `1994904`. Use only the rec.me-specific
`WANDER_POSTHOG_*` env vars; never reuse the Essay Press, Coupley, or generic
PostHog credentials. Release worktrees must populate the ignored
`Wander/Config/LocalAuth.xcconfig` from the local operations env before archive,
then verify the signed archive resolves a non-empty PostHog token without
printing it. An analytics build with a blank resolved token must not be uploaded.

## Testing Rules

- Every milestone should land with matching tests.
- Run the full `xcodebuild test` command above before committing implementation changes.
- In Codex, sandboxed `xcodebuild test` commonly fails before exercising app code because
  CoreSimulator services, `~/Library/Logs/CoreSimulator`, or SwiftPM dependency fetching are
  blocked. When that happens, rerun the same `xcodebuild test` command with escalated
  permissions rather than changing the destination or interpreting the sandbox failure as a
  test failure. Use `prefix_rule: ["xcodebuild", "test"]` for the approval request.
- For focused regression checks, use the same simulator destination and add
  `-only-testing:<TestTarget>/<TestCase>/<testName>`, for example:
  ```bash
  xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData-focused CODE_SIGNING_ALLOWED=NO -jobs 1 -only-testing:WanderTests/WanderStoreTests/testWannaGoQuestionTemplatesAvoidVisitedOnlyPrompts
  ```
- Current important test coverage:
  - design tokens
  - four-tab navigation contract
  - visibility policy
  - sync state machine
  - deterministic Discover parser
  - local store follow/block/search/save/draft behavior
- For visual work, also capture simulator screenshots across at least the current iPhone target and one smaller phone target before calling the UI ready.

## App Store Build Numbers

TestFlight releases are manual and intentionally batched, but not scheduled.
Merging to `main` never triggers a build by itself. Joe or Ryan decides when
enough finished work has accumulated and explicitly asks to push a TestFlight/TF
build. Examples include "push the TestFlight build", "upload the TF build",
"release this to TestFlight", and "go push in your build". A merge-only request
means merge, update Linear and `Next TestFlight`, then stop.

`main` must remain releasable. If work should not appear in the next TestFlight,
do not merge it or keep it behind a disabled feature flag. The open GitHub issue
titled `[machine] Next TestFlight manifest` is the machine-owned queue of
changes already on `main`; it is not an approval queue and cannot select a
subset of compiled code from `main`. The rolling `Next TestFlight` Linear issue
is its human-readable status/relation mirror.

Before merge, every PR must contain one hidden `recme-testflight-payload` JSON
block. The standard PR template includes the marker. A `ship` payload requires:

- linked Linear issue (the updater supplies PR number and exact merge SHA)
- tester-facing summary
- concrete "what to test" item
- release operation or migration, or `none`
- validation already completed

Docs/process-only work uses `exclude` with a reason. Build metadata uses
`release-operation` with a reason. On every push to `main`,
`.github/workflows/testflight-manifest.yml` sweeps the complete range after the
last immutable TestFlight tag, resolves every merged PR payload, and upserts the
exact commits into the machine issue. A direct push or invalid/missing payload
becomes a red `unclassified` blocker. The updater check fails and a later push
re-sweeps the whole pending range, so missed updater runs are self-healing.
Correct a merged PR's payload and rerun the workflow, or explicitly classify a
true direct push with
`node scripts/testflight-manifest.mjs record --commit <sha> --entry-file <payload.json> --head origin/main`.

Git is authoritative for what the binary contains and the GitHub issue is the
machine metadata source. Before a build-number bump and again after the exact
candidate lands, read and reconcile the same issue directly:

```bash
node scripts/testflight-manifest.mjs snapshot \
  --base testflight/build-<previous> \
  --head <cutoff-or-exact-candidate> \
  --build <next-build> \
  --status candidate \
  --write-dir <temporary-output-directory>
```

Every first-parent commit in the range must appear exactly once as `ship`,
`exclude`, or `release-operation`. The snapshot first refreshes the issue from
GitHub, then fails on missing, unclassified, stale, duplicate, or mismatched
entries. Do not bump, archive, upload, or publish tester copy while it fails.
The final post-bump run must classify the build-number PR and any fix that
entered after the initial cutoff. Attach the generated reconciliation JSON to
the Linear release record and use the generated TestFlight and Slack files; do
not hand-maintain another release-note list.

For a cumulative ancestry question such as "what about this older commit?",
audit it separately from the current release delta:

```bash
node scripts/reconcile-testflight-manifest.mjs --audit-sha <sha>
```

Any `main` update that is intended to ship to App Store Connect or TestFlight must increment the App Store build number before upload. Do not reuse a build number for the same marketing version; App Store Connect requires monotonically increasing build numbers.

Required release workflow:

- Move the rolling Linear mirror to `In Progress` and freeze the intended
  `origin/main` cutoff SHA. Snapshot the machine issue mechanically against
  commits since the latest immutable `testflight/build-<n>` tag with
  `scripts/testflight-manifest.mjs snapshot`. Correct missing or stale entries,
  but do not re-triage already accepted product work. The command must pass
  before the build-number PR begins.
- Create/rename the Linear release record `TestFlight build <n>` and briefly hold other app-code merges while
  the build-number PR lands. This cutoff-to-candidate hold prevents unmanifested
  code from slipping into the build.
- Start a short-lived release branch from that cutoff.
- Increment `CURRENT_PROJECT_VERSION` in `project.yml`.
- Run `xcodegen generate` so `Wander.xcodeproj/project.pbxproj` reflects the new build number.
- Commit both `project.yml` and `Wander.xcodeproj/project.pbxproj`, open the
  release PR, and merge it through the normal gate.
- Record the exact merged release-candidate commit and release the short merge
  hold. Later merges accumulate in the same machine issue but fall after the
  locked candidate and do not enter the active build. Rerun the snapshot against
  the exact candidate; attach the passing report and generated copy to the
  Linear release issue. Run the full relevant
  `xcodebuild` test/build gate and archive that exact commit from an isolated or
  detached worktree, even if `main` advances afterward.
- Upload the binary with the incremented build number. The export options plist
  must set `manageAppVersionAndBuildNumber` to `false` so Xcode cannot silently
  upload a different build number.
- Set/confirm export compliance and attach the uploaded build to the public
  TestFlight group by running
  `node scripts/testflight-release.mjs --archive-path <archive> --reconciliation-file <generated-reconciliation.json> --what-to-test-file <generated-what-to-test.md>`
  after upload succeeds. The helper refuses to mutate App Store Connect unless
  the reconciliation is passing, matches the requested build and current exact
  candidate, classifies every commit, and hashes to the supplied What to Test
  copy. Passing the archive path also lets the helper detect and process the
  actual uploaded build number if App Store Connect reports a different one.
- When the build is available, create and push the immutable annotated tag
  `testflight/build-<n>` at the exact archived commit. Never move or reuse a
  TestFlight tag. Then advance the same machine queue with
  `node scripts/testflight-manifest.mjs finalize --build <n> --candidate <sha> --tag testflight/build-<n> --head origin/main`.
- Update `TestFlight build <n>` with the build/tag, tests,
  upload/approval status, tester-note link, known issues, and final release
  evidence, then move it to `Done`.
- Update the rolling Linear mirror from the finalized machine baseline. Do not
  open a follow-up repo PR just to record the completed release.
- Only after archive/upload has completed should an agent post a tester-facing Slack note. If the binary is still processing or not yet externally approved, the Slack note must say that plainly.
- If the build is attached to TestFlight or confirmed available, follow the Slack release-note rules below and state the live/approved status.

If upload or App Store Connect processing is blocked after the build-number PR
merges, keep the rolling release issue `In Progress` and put the exact candidate
commit, build number, validation, blocker, and continuation commands there. Do
not create the immutable release tag or finalize the machine baseline until the
release completes. The machine issue may collect later merges; the locked
candidate SHA keeps them outside the blocked build.

Docs-only or process-only commits to `main` do not need a build-number bump
unless they happen to be present in a later explicitly requested app release.
App-code merges wait in `Next TestFlight` until that manual request arrives.

## TestFlight Release Notes

Whenever an agent uploads a new TestFlight build, attaches it to the public
group, or confirms it is available for testing, the agent must also post one
top-level release announcement to the dedicated rec.me Slack release channel:

- Release channel: `#release-notes`
- Release channel ID: `C0BM5CY0GQY`
- Feedback channel: `#testflight-feedback`
- Feedback channel ID: `C0BAA7DG2AC`
- Public TestFlight link: `https://testflight.apple.com/join/knEhRa6t`

The Slack note must include:

- App name `rec.me`, the build number, and whether the build is live/approved or still processing.
- What changed, written for testers rather than engineers.
- What needs testing, as a concrete checklist.
- Known issues or intentionally deferred areas.
- A request to report problems in `#testflight-feedback` with device,
  account/email if relevant, screenshots, and exact repro steps.

Keep `#release-notes` low-noise: one top-level announcement per build and no
duplicate release post in `#testflight-feedback` unless Joe explicitly asks.
Tester reports and ongoing discussion belong in `#testflight-feedback`.
`#all-recme` (`C0B9FU1QNG2`) remains for broad announcements only when Joe
explicitly requests one.

## TestFlight Helper

Use `scripts/testflight-release.mjs` after a successful `xcodebuild -exportArchive`
upload. The helper reads `CURRENT_PROJECT_VERSION` from `project.yml` by
default, requires the version-2 reconciliation generated from the machine
GitHub issue and its generated What to Test file, verifies the live issue still
matches the locked classification hash, waits for the uploaded build to become `VALID`, sets
`usesNonExemptEncryption=false`, attaches the build to `rec.me Alpha`, submits
external beta review, and prints the App Store Connect/TestFlight summary.
Always pass `--archive-path <archive>` so the helper can verify Xcode's uploaded
build number before touching TestFlight.

```bash
node scripts/testflight-release.mjs \
  --archive-path <archive> \
  --reconciliation-file <generated-reconciliation.json> \
  --what-to-test-file <generated-what-to-test.md>
```

Useful overrides:

- `--build-number <n>` to process a specific build instead of the current `project.yml` value.
- `--archive-path <path>` to read Xcode's archive upload metadata and process the actual uploaded build number when it differs from the requested build number.
- `--reconciliation-file <path>` is required and must be the passing JSON generated by `scripts/testflight-manifest.mjs snapshot` for the exact build/candidate.
- `--dry-run` to verify the reconciliation, resolved app id, group, and build number without calling App Store Connect. The reconciliation and generated What to Test inputs remain required.
- `--what-to-test-file <path>` is required in normal use and must be the file generated alongside the reconciliation JSON. Inline `--what-to-test` is accepted only when its exact content hash matches that generated output.
- `--locale <locale>` to set a non-default TestFlight beta build localization. Default: `en-US`.
- `--timeout-attempts <n>` and `--poll-seconds <n>` if App Store Connect indexing is slow.

The script reads App Store Connect credentials from env vars or `/Users/joelipshutz/.openclaw/workspace/.env.keys`: `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_PATH`. Never commit the `.p8` key or local env file.

## Useful References

- Product spec: `docs/specs/wander-ios-product-spec.md`
- Engineering plan: `docs/plans/2026-06-01-wander-ios-eng-plan.md`
- Contract lock: `docs/plans/2026-06-01-wander-m1-5-contract-lock.md`
- Design system: `DESIGN.md`
- Design review: `docs/reviews/2026-06-01-plan-design-review.md`
- Engineering review: `docs/reviews/2026-06-01-plan-eng-review.md`
- Handoff for new agents/developers: `docs/codex-handoff.md`
- Setup commands: `docs/setup.md`
- Historical agent log archive: `docs/agent-log.md` (frozen; do not use for current state)
- App icon source of truth: `docs/brand/recme-app-icon.md`
