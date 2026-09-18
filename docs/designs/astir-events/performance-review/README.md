# Astir Events performance review

September 15, 2026. Source review under D18A, against `f8d258e869503a28d70518a050dff36a344134c6` in `wander-events-flowchart-review` (app-code baseline `a0117cff`). **No Events benchmarks, builds, load tests or live-service checks ran.** These are implementation risks and measurement proposals, not diagnosed Events production defects.

The existing architecture is suitable to begin implementation. Keep the selected Supabase backend, small native shared layer and two-stage ownership model. Current evidence does not justify a second backend, another queue service, an app-wide store rewrite or a scope cut. No new consequential product/architecture choice was identified by this section; actual provider/device proofs can still expose one later.

## Findings to carry into implementation

| Finding | Evidence | Implication within the approved approach |
| --- | --- | --- |
| **PF1 — entry/query growth, P1, confidence 9/10** | General root entry restores the store (`WanderRootView.swift:418`, `WanderLocalStore.swift:571`). Adjacent visit-photo reads sign each result in a loop (`SupabaseRepositories.swift:967`). Existing feed already returns useful content before batch media (`:691–716`). | Keep event entry independent of general store/maintenance in the Clip. Use small authorized summaries, stable pages and batch enrichment. Avoid per-guest/profile/photo calls or downloading every guest/media item before the primary action. Full guest-list access remains available through pages. |
| **PF2 — transaction/lock growth, P1, confidence 9/10** | D4–D14 already require coherent capacity/code/state transitions. Existing list-invite row locking (`20260729123000_web_links_and_place_list_invites.sql:210–217`) is only an adjacent pattern. | Use short event-scoped transactions and deterministic lock ordering; keep provider calls, images and whole-list expansion outside them. Recheck current time after waiting for locks. Compare one busy event with multiple events; speed never permits overselling or losing a promised hold. |
| **PF3 — message burst backlog, P1, confidence 10/10 for checked-in structure** | Scheduled push invocation is once/minute (`20260712112000_schedule_push_notification_worker.sql:6–8`). Worker limits each single claim to 20 (`push-notification-worker/index.ts:113–117,121–132`); latest claim SQL also limits 20 (`20260828212329_calendar_reservation_notification_governance.sql:808–815`). | Do not assume unchanged scheduling can send an event-wide burst promptly. A 300-job fixture needs 15 claim batches through that path alone, excluding backlog/retries; this is arithmetic, not observed delivery time or current SMS behavior. Measure queue age, bound all send concurrency and preserve durable claim/settlement/unknown-outcome behavior. Exact worker budgets/provider timing remain proof tasks. |
| **PF4 — media/map resource growth, P1, confidence 9/10** | Current image caches have separate byte/decoded/disk budgets; upload accepts whole photo `Data` (`WanderLocalStore.swift:6994`). Existing map debounce/cancellation appears at `MapScreen.swift:203–240`. | Plan file-backed bounded video transfer/playback and visible-image work; account for total memory instead of stacking equal caches. Keep permission/source identity in every protected cache. Preserve viewport/summary/map optimizations; do not hydrate whole event histories per pin or rebuild the full store for each comment/upload. |
| **PF5 — offline roster/queue growth, P1, confidence 9/10** | D9 requires complete prepared roster, durable admission acknowledgement and per-operation reconciliation. No Events console/storage implementation exists to measure. | Stage bounded roster chunks and promote only a complete version; index local lookup and store individual durable operations. Never mark a partial download Ready, truncate guests silently, or rewrite one growing queue blob per scan. Validate real staff-device lifecycle and quota behavior. |

P1 here means a constraint/proof that must be addressed before Events ships, not a claim that production is currently broken. These findings reinforce existing approved recovery, authorization, atomicity, history and offline behavior. Tunable page sizes, transfer concurrency, database indexes and diagnostic budgets are engineering work, not new guest-count or upload restrictions.

## Execution paths

```text
Link / Events tab
  +--> permitted compact event content -----------------> useful detail
  +--> legitimate session --> current guest state ------> correct action
  \--> visible cover rendition (independent)

RSVP / offer / cancellation
  --> auth + operation identity
  --> short event/code/booking transaction
      --> authoritative result + durable delivery intent
  +--> truthful client state
  \--> bounded worker --> current eligibility --> provider --> settlement

Gallery / guest list / place history
  --> authorized first page --> visible rows/thumbnails/posters
  --> next cursor on demand; cancel obsolete reads
  \--> selected media --> bounded file/range transfer or playback

Map viewport/filter
  --> coalesced permitted summaries --> cached projection --> visible pins
  \--> selected pin --> event detail (not every pin's complete gallery)

Door offline preparation
  --> versioned bounded roster chunks --> complete durable promotion
  --> local lookup --> durable operation --> show awaiting sync
  \--> reconnect --> bounded per-row reconciliation --> accepted/conflict/wait
```

All paths retain the test review's account fences, current authorization and stable operation identity. Old cached data cannot substitute for a missing permission result. No new offline recap access is introduced.

## Measurement and ownership

The [measurement plan](measurement-plan.md) defines fixture sizes, intervals, provisional diagnostic budgets, actual-device checks and future test locations. All numeric targets await baseline calibration; the 30/300/3,000 fixture sizes are not product limits. Cold invocation, provider delivery, SQL lock wait, UI first content, media throughput and offline durable writes are reported separately.

- Entry/identity foundation: Clip dependency/build proof, useful event content, session/booking request coalescing and icon-launch recovery timing.
- Data/rules foundation: query plans, authorization cost, page contracts and concurrent transaction correctness/latency.
- Before-event/door: shared delivery foundation, guest/console pages, complete roster, queue and hardware proof.
- After-event/map: page/media/memory/projection work and ordinary-history/map regressions; integrates its recap trigger with the same delivery foundation.

Evidence details: [entry and Clip](entry-clip.md), [backend and door](backend-door.md), [media and map](native-media-map.md). These are proposals within the selected architecture. If actual measurements force a product compromise—such as reduced media support, materially delayed notices or a higher-cost service—bring that specific tradeoff back before changing the approved journey.

## Review disposition

All four performance dimensions were examined: query access/N+1, memory, caching and slow/complex paths. No new architecture vote is necessary on current source evidence. The next checkpoint is to finish the engineering handoff: contracts, two-agent task dependencies and estimates, rollout/rollback, remaining product proposals and final review accounting. Performance outcomes remain unverified until implementation.
