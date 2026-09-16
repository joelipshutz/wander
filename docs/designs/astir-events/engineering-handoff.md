# Astir Events — build handoff for Joe and Ryan

September 15, 2026 · REC-467 · Planning completed through engineering D19A.

**Two agents are recommended.** Start with a small shared contract, build data/rules and entry/identity in parallel, integrate one real RSVP, then split by the guest journey. This keeps both people useful without putting every backend and browser task behind one permanent platform owner.

The complete experience remains in scope: invitation or Events discovery → Apple/Google and verified-phone RSVP → texts without forced installation → installed-app QR and admission → published recap → explicit event check-in → protected content and lasting place/map history. Confirmed guests can manage their RSVP and view the full guest list in Clip/web. Admission and the later event check-in remain separate.

**This is a conditional engineering handoff, not a claim that the whole product draft is approved.** Nine product/design groups remain, each tied to the affected tasks. Approved foundation work is well defined; final affected feature contracts cannot be called complete until those choices are resolved. No production implementation, migration or release was performed.

## What to open

| Need | Artifact |
| --- | --- |
| Review the whole journey with actual inline screen previews | [172-screen flowchart](astir-events-flowchart.html) — download/open the HTML locally; GitHub displays its source |
| Start building from the task/dependency list | [22 implementation tasks](implementation-tasks.md) |
| Agree native/web/backend boundaries | [Shared contracts and state machines](engineering-contracts.md) |
| Finish remaining product choices | [Nine decision groups](engineering-open-decisions.md) |
| Understand the selected architecture and review evidence | [Engineering plan](engineering-plan.md) |
| Verify implementation | [Test plan](engineering-test-plan.md), [case mapping](test-review/coverage-map.md), [QA journeys](events-qa-test-plan.md), [failure handling](engineering-failure-modes.md) |
| Measure and launch | [Performance review](performance-review/README.md), [rollout/rollback](engineering-rollout.md) |

## Parallel execution

| Stage | Lane A | Lane B | Integrate when |
| --- | --- | --- | --- |
| Shared start | T01 contract and fixtures | Review the same contract and fixtures | State names, identity and operation/error examples agree |
| Foundations | T02 data, rules and early canonical-history proof | T03 real native/Clip identity proof; T04 guest-web and console shells | T05 test wiring and T06 one real persisted RSVP across actual hosts |
| Complete journeys | T07 event controls → T08 booking/code/offer rules → **T12 shared messaging early** → T09 RSVP/ticket → T10 online door → T11 offline door | T13 check-in/history → T14 gallery/video → T15 recap and publication → T16 map/place/feed | Each small slice passes its own tests; recap uses the one T12 delivery foundation |
| Joined verification | T17 access/cache proof → T18 integrated journeys | T19 performance after T17; can run alongside T18 on separate fixtures/devices | Actual records and actual device/provider evidence, not joined mocks |
| Release preparation | T20 compatible artifacts/public invocation | T21 rollback and activation-control rehearsal | T22 evidence closure and later authorized activation |

T04 can scaffold while provider proof is unresolved; its real integration must pass T06. T16 does not need to wait for the entire video pipeline to build its summary/history path, but actual media permissions still join the release proof. The task DAG names acceptance dependencies; useful tests/scaffolding can begin before a predecessor's final gate without claiming that gate passed.

```text
                       T01 shared contract
                     /                     \
           T02 data/history            T03 identity + T04 web/console
                     \                     /
                     T05 tests + T06 real integration
                     /                     \
  T07 -> T08 -> T12 -> T09 -> T10 -> T11    T13 -> T14 -> T15 -> T16
                 \____________________________^ shared delivery
                     \                     /
                    T17 current-access proof
                     /                     \
              T18 full journey          T19 performance
                     \                     /
              T20 distribution  ||  T21 rollback
                           T22 release gate
```

The arrows summarize the machine-readable dependencies; the task JSON is the precise DAG. Both people choose A/B at kickoff and may exchange the next ready package. These are work lanes, not statements about Joe or Ryan's specialties.

## Shared-file ownership

The lanes overlap in native Events, web Events/console, Supabase migrations/tests and existing history integration. They are not automatically conflict-free just because the product journeys differ.

- Stage 1 entry integrator owns `project.yml`, generated project membership, root navigation, shared auth/transport extraction and canonical link dispatch. The other agent sends narrow reviewed changes through that owner.
- Data/rules integrator owns schema/API fixtures and migration ordering. Separate feature migrations may be drafted in parallel; ordering/application is serialized and reviewed against current main.
- After-event/history integrator owns narrow `WanderLocalStore`, map/feed and canonical-visit hooks. Avoid two simultaneous store/map rewrites.
- One owner implements the shared message service and console shell. Journey owners add triggers/panels through those contracts.
- Use independent short-lived worktrees and small PRs. Reassign integration ownership explicitly at stage boundaries; do not create an assumed third engineer. Tests require distinct accounts/events/devices when running concurrently.

## Scope and estimates

The 22 tasks total approximately **252–490 active agent-hours**, or **488–796 engineer-hours if human-led**. These are alternative bottom-up estimates, not additive numbers or a fixed AI speedup. They include implementation, tests and iteration; humans still provide decisions, review, physical-device/provider work and release approval.

The conservative fixed-lane model is **168–320 active elapsed hours** with two lanes. At an illustrative six productive lane-hours per weekday, that is roughly **6–11 working weeks**, before App Review/provider waits, unresolved decisions or scope changes. This is a planning envelope, not a delivery promise. Agent tools can run longer days, but simply dividing total hours by two hides shared work, device gates and rework. Re-estimate after T06 proves actual identity/Clip/web/history integration; that is the earliest credible date-setting point.

The estimate covers the approved whole loop. Choosing additional currently proposed behavior may change it. The task verification file checks arithmetic and dependency consistency, not real-world velocity.

## First implementation checkpoint

When implementation is separately authorized, assign the two owners, refresh current main and reconcile the linked planning/App Clip work. Run T01, then T02 and T03/T04 in parallel. The first integrated checkpoint must prove canonical account/phone/booking continuity, actual host builds, a minimal real RSVP and protected canonical-history behavior. Do this before building all 172 review states into production screens.

The most important remaining product contract is how issued-offer deadlines interact with registration/event closing and later edits (OD01). The other groups cover lifecycle edits; participation/door exceptions; reminder channels; previews/home/share; media/editing; map treatment; post-ticket continuation; and navigation/saving. They can be reviewed coherently with Joe and Ryan rather than reopened as unexplained technical questions.

## Verification and current limits

- **121 acceptance scenarios + 24 technical risk groups mapped**, with concrete future tests and owners; none has passed as an Events runtime test.
- **Five performance risk groups** reviewed; no Events benchmark or device/provider feasibility pass is claimed.
- Actual Clip/provider/install continuity, protected media/location, offline staff-browser persistence and compatible public distribution remain implementation proofs.
- Retrospective/source baseline includes canonical-history repair at `a0117cff`; latest-main drift through `f8493c0` adds display-only Feed grouping and profile-header behavior. Preserve original visit/activity engagement IDs through grouping and add that regression.
- Outside-model review was skipped by gstack's running-under-Codex rule. The collaborating agents supplied source checks; they are not an independent model review.
- REC-467 is currently marked Done in Linear. That external status does not approve this draft's open choices or prove Events is implemented.
