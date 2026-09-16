# Events backend, messaging and door performance review

**Status: findings and proposals for D18A; no implementation, benchmark, hosted query, service change or production measurement.** The existing Supabase boundary remains the recommended starting point. No evidence currently justifies Redis, a separate Events service, a new queue platform or a global app-store rewrite.

Inspected worktree: `wander-events-flowchart-review`, HEAD `f8d258e869503a28d70518a050dff36a344134c6`, containing reviewed code `a0117cff6ed55a967f4212b45bb28d8c39ca1488`. Observed `origin/main` is `0d29d776f42132a28548355ae4e18302cdc3857a`; the intervening diff contains Events design documentation, not changes to the inspected backend/worker/test code. Repository paths below are relative to that worktree. Plan references are to the sibling `astir-events-spec/engineering-plan.md`.

The September plan's 30-friend beta is context, not an approved event attendance limit. Load sizes and budgets below are synthetic measurement proposals, not measured capacity, product limits or new approvals.

## Findings

### BP1 — P1: unchanged push scheduling would drain an event burst slowly

**Evidence, high confidence:** `supabase/migrations/20260712112000_schedule_push_notification_worker.sql:6–8` schedules one invocation per minute; line 22 requests a limit of 100. `supabase/functions/push-notification-worker/index.ts:113–117` clamps that request to 20 and makes one claim. The latest inspected claim definition also caps at 20 (`supabase/migrations/20260828212329_calendar_reservation_notification_governance.sql:808–815`); lines 900–909 claim with `FOR UPDATE SKIP LOCKED` and a ten-minute lease. There is no drain loop in `index.ts:121–132`.

**Consequence inferred from code, not measured:** with only that scheduled invoker, N newly eligible logical push jobs need at least `ceil(N/20)` claim batches, ignoring other backlog/retries/provider work. A 300-job burst requires 15 scheduler ticks; a 1,000-job burst requires 50. Timing depends on tick phase and processing, so these are not observed 15/50-minute delivery latencies. This is the current push path, not an existing Events SMS implementation or a verified live cron configuration.

**Proposal:** preserve the current database claim/lease/result pattern, but give the shared messaging foundation a bounded drain budget: claim a small batch, process with explicit provider concurrency, settle, and claim again only while time/attempt budget remains. A prompt post-commit wake-up for newly committed work can coexist with the scheduled recovery sweep; a lost wake-up must never lose the persisted intent. Do not enqueue by waiting for a provider response inside RSVP or admission transactions. Size dispatch from actual provider limits and measured queue age, not by simply changing 20 to an unbounded number. Separate channel adapters/eligibility within the common foundation; SMS must work without an APNs token.

**Already required:** confirmed RSVP messaging, D13 current event revision, no duplicate logical sends, no consent bypass, unknown-outcome recovery. **Still proposed:** worker budgets, wake-up mechanism, precise latency target and provider retry/fallback policy. No product choice is needed just to avoid inheriting the current 20-per-minute bottleneck.

### BP2 — P1: bounded claim count does not bound all worker work

**Evidence, high confidence:** latest claim SQL performs several pending/claimed cleanup updates before selecting its limited batch (`20260828212329_calendar_reservation_notification_governance.sql:818–869`). Its index is `(status, not_before, priority desc, created_at)` at lines 53–55, while selection orders by priority first at line 900. This is a query-plan inspection point, not proof the existing index is ineffective. Token payloads are aggregated per claimed recipient without a token-count cap at lines 928–947.

The worker starts all claimed events concurrently (`index.ts:121–123`), and all tokens of each event concurrently (`:140–142`). It settles each event through a separate RPC (`:149–156`), then awaits its analytics HTTP call (`:157–159`). The provider fetch has a five-second timeout (`:87`, `:417`); the shared service RPC fetch at `:632–640` has no explicit request timeout. Each nonempty batch also requests a 30-day frequency snapshot (`:124–125`, `:273–280`); analytics fetch has a two-second timeout (`:299–303`). These are request/scan opportunities, not recorded slow operations.

**Proposal:** bound network concurrency across all token/message sends, not merely job count; give claim and settlement calls deadlines within the overall worker budget. Retain provider-accepted, retryable, failed and unknown outcomes per delivery. A slow analytics export should not determine whether the dispatch loop makes progress; aggregate/batch coarse telemetry or move frequency snapshots off every dispatch batch, preserving delivery settlement first. Do not select retry semantics merely from performance pressure.

Measure cleanup scans, sort cost and active/historical queue selectivity. If global cleanup dominates, make cleanup incremental/bounded while retaining eligibility checks for every candidate at claim/dispatch; never speed this up by sending to canceled, opted-out or unauthorized recipients. Choose any new index from the actual due-work plan; do not add every conceivable index or silently reorder business priorities. Priority/fairness and delivery timing remain policy-sensitive if the proposed change makes some messages materially later.

### BP3 — P1: correctness and contention: keep capacity locks local and short

**Evidence:** the approved plan requires coordinated event capacity across offer issuance, confirmation, approval, cancellation and capacity edits (`engineering-plan.md:138–142`), plus code accounting in consistent lock order (`:325–328`). Existing list invitation acceptance locks a single invite row (`supabase/migrations/20260729123000_web_links_and_place_list_invites.sql:210–217`); that is insufficient to serialize competing offers for one event. Existing place operations show scoped transaction advisory locks (`supabase/migrations/20260824080307_private_place_taxonomy.sql:719–734`), establishing an available pattern rather than the Events design.

**Proposal:** use one coherent per-event capacity serialization point, with deterministic event/code/booking lock ordering. Perform canonical identity and operation lookup as appropriate, then under the required lock recheck current eligibility/deadlines and atomically update booking, seat/code accounting and a small delivery intent. Avoid profile/photo expansion, whole guest-list serialization, provider calls, media work or fan-out over all attendees inside that critical section. Return the small authoritative operation result; obtain optional display enrichment separately.

Do not lock all events through a single global mutex, and do not solve hot-event contention by removing serialization. New unreserved verification and pending manual applications hold no seat under D5/D6; a long sign-in session must not hold a database lock. Admission does not allocate another seat: avoid taking the capacity lock for every scan unless the chosen consistency contract requires it. Admission still needs current booking/admin eligibility and a canonical uniqueness boundary, including cancellation races.

Expired offers cannot occupy capacity simply because a cleanup job is late. Prefer indexed event-scoped counts of active commitments initially, or a rigorously maintained ledger if measurement justifies it; a cached counter alone cannot ignore time-based expiry. Evaluate current server time after lock acquisition, not transaction-start `now()`, for deadline decisions. Do not use a partial-index predicate containing `now()` to represent currently unexpired offers; index stable status/event fields plus deadline and filter against current time during the transaction.

**Measure:** separate SQL execution from lock wait; hot single-event versus equally sized multi-event workloads; final invariants and retries under contention. Enqueue/notification failures must not stretch the lock by waiting for network recovery. A timeout after possible commit remains unknown, resolved through stable operation identity, not treated as permission to create another booking.

### BP4 — P1: avoid a guest/profile request per row or an unbounded event snapshot

**Evidence:** current feed fetch requests a capped page, renders authorized content before media, then obtains media in one batched RPC (`Wander/Services/Remote/SupabaseRepositories.swift:691–716`). Existing gallery uses a bounded stable multi-field cursor (`:2602–2624`; SQL example `supabase/migrations/20260723183000_visible_place_photo_gallery.sql:61–69`). Photo requests are deduplicated and chunked in 32s (`SupabaseRepositories.swift:2458–2475`), but compatibility fallback makes individual requests (`:2489–2494`). These are patterns to adapt; fallback request amplification must be measured if reused.

One RPC is not automatically one cheap query: existing list snapshot SQL calls `place_list_detail` for every summary (`supabase/migrations/20260730010000_surface_snapshot_rpcs.sql:93–98`) and expands owners' visible places (`:70–73`). Copying this all-details shape into Events could couple first render to every booking/profile/media record. No Events implementation exists yet, so this is an anticipated integration risk, not a reproduced N+1 bug.

**Proposal:** a small permitted event-detail projection supplies event metadata and the viewer's authoritative state. Fetch a bounded guest-list page only when allowed/requested. Batch display profiles, relationship flags and mutual counts for that page; avoid calling a profile-detail RPC for each attendee or fetching their whole place history. Event counts and permission-filtered face previews should be separate from loading every guest. Preserve blocked/private-profile rules: “faster” is never a reason to serialize hidden rows then blur them.

Use stable cursor ordering with a unique tie-breaker for event discovery, the member's reservations, guest list, waitlist, admission history and message log. Page size is an implementation tuning parameter, not a new limit on the full list. Bound server inputs as well as clients. Define consistency when ranking data changes between pages; don't promise snapshot completeness from a changing cursor without a snapshot contract. Console guest lookup must be scoped to the selected event and appropriate indexes; debounce text searches/cancel obsolete responses rather than downloading the entire account directory.

**Candidate index/access patterns, conditional on final schema and EXPLAIN:**

| Access path | Candidate shape to evaluate |
| --- | --- |
| Current viewer's booking for one event | Event/account lookup plus current state or generation; preserve approved retry/rebooking history |
| Event commitments / offer expiry | Event + stable status + deadline; narrow state counts, no scan of all historical events |
| Event/code accounting | Code/event/state and deadline for held allowance; unique logical operation/redemption identity |
| Member's upcoming/past reservations | Account + appropriate ordering keys + unique tie-breaker |
| Event guest/waitlist/roster page | Event + state + selected stable page keys; batch join profile projections |
| Canonical admission / queued operation replay | Event/guest canonical uniqueness and operation-ID lookup; do not add one-history-per-user constraints that conflict with rebooking |
| Worker due work and retries | Stable pending/claimed status, due/lease timestamps and selected priority order; inspect both fresh and reclaimed work plans |

These are query/index proposals, not agreed table names, DDL or permission to add an unapproved booking/plus-one policy.

### BP5 — P1: correctness and resource risk: offline readiness must mean a complete durable roster

**Evidence:** D9 requires event/account-scoped minimum roster data, visible last sync, durable local admission records, safe reconciliation and account-switch isolation (`engineering-plan.md:298–306`). A partial snapshot, lost queue row or whole-batch success claim would violate approved behavior. There is no existing Events web console or measured staff-browser storage profile to claim reusable offline capacity.

**Proposal:** build a minimal roster projection, indexed for local QR/booking lookup; keep unrelated feedback, recap media and private venue fields out. Avatars should not make roster readiness depend on a full image download. Transfer bounded pages/chunks with a version/completeness manifest. Stage a refresh separately and atomically promote it only when complete, retaining the prior good version on failure. The server snapshot/version method must prevent unrelated pages being represented as one consistent roster; don't hold a database transaction open across a series of browser network requests. If device quota or supported size is exceeded, report preparation failure and preserve the previous roster. Never silently truncate and display Ready, and do not introduce a guest-count limit without review.

Store admissions as individually keyed durable operations, not by rewriting an ever-growing JSON array on each scan. Persist before acknowledging offline entry. Avoid rescanning or re-rendering the full guest list on each camera frame; suppress repeat decoding while one scan is being resolved and keep the manual lookup available. Neither UI batching nor optimistic success may precede the required durable write.

Reconcile bounded batches with stable IDs and individual outcomes; start measurement with 25–50 rows and one in-flight batch per device as tuning candidates, not approved settings. Apply server checks and deduplication; clear only acknowledged operations, retain conflict/unknown rows, and allow subsequent batches to progress without claiming unresolved rows synced. A 1,000-row upload must not create one long capacity-lock transaction. No new broker is needed for a browser queue plus current backend RPCs. Exact local persistence/retention and background support remain implementation validation, not an approved retention period or an eviction guarantee.

Measure actual staff Safari/other intended browsers under reload, backgrounding, shell update, quota denial and eviction, not only desktop Playwright. Test two disconnected devices and one busy reconnecting event. Local counts remain local; no offline queue operation grants recap access before canonical server validation.

### BP6 — P1: payload, memory and main-thread cost matter alongside SQL latency

**Evidence:** feed's metadata-first rendering already decouples initial content from storage/signing (`SupabaseRepositories.swift:695–704`). D16 keeps shared native Events components small and uses separate public/private projections (`engineering-plan.md:454–466`). D9 confines offline data to necessary door information (`:298`).

**Proposal:** browser/Clip event detail should not fetch full console roster, all images or protected recap just to show RSVP. Lazy-load heavy console/gallery modules and below-fold media; cancel superseded event/search requests; render/virtualize long staff lists while retaining accessible lookup and clear state. Optimize public cover assets separately from permission-scoped account data. Never put personalized guest-list/home/QR/roster responses in a shared public cache to improve first render.

Capture compressed/uncompressed response bytes, client decode time, memory, DOM growth and scan-to-durable-result duration. Query duration alone will miss a large JSON payload or a local full-list rewrite. Exact bundle/cache budgets need measurements once the web package exists; no invented existing bundle-size result is reported.

## Proposed measurement fixtures and method

Use local/disposable test infrastructure and synthetic accounts; **not production traffic, real guest records or real SMS/APNs sends**. Hosted rollback smoke proves targeted compatibility, not load performance: its single transaction cannot model committed multi-session races. For measurements against a representative isolated hosted environment, record tier/region/network/commit and disclose differences from production.

| Experiment | Starting fixtures and load candidates | Record and verify |
| --- | --- | --- |
| Small event baseline | 30 and 100 confirmed guests; 10–30 pending/waitlisted; 2 staff devices; 1–5 simultaneous RSVP attempts | Cold/warm event/booking/guest-page API timing, bytes, queries, door scan-to-result; exact record/permission correctness |
| Arrival and RSVP burst | 300 guests, 50 waitlist, active code and offer holds; 20 then 50 independent sessions contend for last 10 seats; compare one hot event with ten independent events | p50/p95/p99 latency, lock wait/hold, commit/retry/unknown counts, deadlocks/timeouts, exact seat/code/admission invariants; no cross-event bottleneck |
| Query selectivity | 1,000 current-event guests; 100,000 synthetic historical booking/message rows across other events/accounts; page sizes 25/50/100 | EXPLAIN ANALYZE/BUFFERS in disposable DB with representative authorized roles, rows scanned/returned, sort/temp spill, index use, RLS cost; constant HTTP request count per bounded page |
| Notification burst | 30/300/1,000 newly due jobs, plus existing backlog; 1/2/5 tokens per push recipient; fake provider 50ms/500ms/timeout and 429/permanent/unknown responses | Enqueue-to-first-attempt and accepted/unknown/terminal queue ages, throughput, maximum network concurrency, per-row retry behavior, SQL cleanup work, settlement time and fairness; no duplicate logical work or location/consent leak |
| Prepared roster | 30/300/1,000 entries; interruption on a middle page; original complete roster present; artificial quota/write failures | Bytes and storage use, preparation time, local lookup latency, atomic completeness; failure never labels partial roster Ready |
| Offline arrival/reconnect | 2 and 5 devices; scripted 1–2 scans/sec/device as stress inputs, not expected human attendance rate; 300 queued rows including duplicates/conflicts; lost response after commit | Durable-write latency, UI responsiveness, queue bytes, per-batch server time, lock contention, drain time; unresolved rows preserved, exactly one canonical admission |
| Browser lifecycle | Intended real staff devices with offline reload/background, storage eviction, shell update and account switch | Supported behavior with device/OS/browser/build; unavailable-storage state and privacy. Do not claim browser persistence survives every OS eviction |

For short runs record counts and distributions, not just averages; use repeated warm/cold runs and a short sustained workload to expose accumulating queues. Use real separate DB connections and a third observer for committed-state correctness. Collect `pg_stat_activity`/`pg_locks` wait samples and transaction duration; examine representative query plans and buffer reads. Do not enable expensive production tracing as part of this review. Provider stubs need controllable acknowledgement/timeout behavior so throughput is never improved by skipping settlement or permission checks.

**Provisional engineering targets to discuss after the baseline, not approvals or measured results:** event/booking server p95 within a few hundred milliseconds under the agreed small-event workload; online admission acknowledgement around one second on representative venue connectivity; local lookup/durable acknowledgement comfortably below the next intentional scan; first screen request count bounded independently of total guest count. Record queue-age objectives separately for confirmation, offer, scheduled reminder and publication burst before release. Avoid a single average “notification latency” that conceals missed reminders or slow bulk drain. Where hardware/network makes a target unrealistic, report the breakdown and supported operating procedure rather than removing persistence, eligibility or app gates.

## Choice and ownership assessment

**No additional consequential architecture choice is required on current evidence.** Recommend keeping the selected Supabase boundary, using bounded workers, short per-event capacity transactions, indexed/paginated projections and a complete durable browser roster. Those are implementation proposals supporting approved D2/D4–D14/D16 invariants; they do not add services or reduce scope.

The highest-impact unresolved performance input is the acceptable delay from a committed booking/offer or published recap to first delivery attempt, coupled with representative guest volume. Establish that as an explicit release measurement target once the provider and isolated workload are known. Do not ask the user to pick batch sizes, indexes or mutex types. If measurement later shows the required delivery window cannot be met without materially higher service cost or changing the promised timing, that tradeoff warrants a choice then; it is not established now.

Foundation owner: database contracts, lock order, index/query plans and core load fixtures. Shared messaging owner: bounded claim/dispatch/settlement plus provider limits and queue-age evidence. Before-event/door owner: paged guest/console views, roster/queue lifecycle, real staff-device and multi-device load checks. After-event/map contributes publication burst and entitlement fixtures to the same messaging foundation. Migration ordering and shared worker edits need one active owner; load optimization must not create a second capacity or delivery authority.
