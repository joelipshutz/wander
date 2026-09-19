# Feed performance hypothesis and Setup guide

Recorded September 16, 2026. Read-only investigation of transcript T02/T05: “the feed server transaction … is really inefficient,” “we're not caching,” and “test the hypothesis.” After the source audit, the existing isolated Astir account was verified and three bounded production metadata/statistics queries were run. No database data/schema mutation, app edit, account-setting change, or new device benchmark was performed.

## Finding

**Production statistics now support meaningful historical server cost; the cause of today’s complaint remains unproven.** The local Feed SQL has a concrete candidate worth measuring: it computes the Featured collection from all eligible history, independently of the 25-item activity page, and limits the collection to eight only after place deduplication/projection. The latest locally available main retains that shape and adds per-event visibility work. This is source evidence of potentially expensive work. The measured historical server statistics below strengthen the hypothesis but do not identify its exact hot path or prove that the database dominates the current end-to-end delay.

**“We're not caching” is not accurate for the current native implementation.** Automatic Feed reentry reuses successful in-memory data for 60 seconds and concurrent same-context refreshes share one request. Fresh launches, expiration, manual refresh, account changes, and presentation-revision invalidation still need network work. No private Feed content is persisted to disk by this mechanism.

Past measurements establish client-side and request-sequencing problems too. They do not establish the cause of the current complaint. Measure server time, transfer time, first content, media readiness, and frame hitches separately before choosing a rewrite.

## Source versions

- Current review-board/build-174 checkout: `/Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174`, commit `4a9f122c062d04db2f06e7b75226a9e85999169b`.
- Locally available `origin/main`: `4937033a99175b2b22b48440a1376b644f6ad8e6`, REC-497 repeat/edit Wanna saves. Read with `git show`; no remote fetch or checkout change.
- Production function readback subsequently confirmed the deployed `app.followed_feed` body exactly matches the latter REC-497 definition in `20260916171502_repeat_wanna_saves.sql` (MD5 below). The build-174 checkout’s older function does not match.

## Bounded production check completed

Read `/Users/joelipshutz/.config/project-access/README.md` and used only the isolated `supabase-astir` launcher. Sandboxed Keychain lookup initially reported no credential; the approved unsandboxed verification succeeded for the correct Astir project. No login, credential replacement, or shared account switch was required.

Ran **three read-only transactions**, each with a 2.5-second statement timeout, 250 ms lock timeout, and explicit rollback. Queries read function metadata, statistics availability, then at most 12 matching aggregate statement entries. They did not return contact/profile/place content, raw user identifiers, SQL parameter values, or credentials. No statistics were reset and no user Feed was invoked.

Deployed `app.followed_feed` body MD5: `2bf5e501b9a1b65a38c48b9ab446f54e`, an exact match to current inspected REC-497 main. Build-174 source body MD5 is `16fdfbb9e77254e535af2e32aecabc5a`, so current server behavior must be profiled against REC-497.

Existing `pg_stat_statements` data contains these dominant authenticated statement fingerprints:

| Statement containing RPC | Calls | Mean server execution | Maximum | Standard deviation | Statistics accumulated since |
|---|---:|---:|---:|---:|---|
| `followed_feed` | 1,111 | **361.338 ms** | **2,294.802 ms** | 435.296 ms | July 21, 2026 |
| `activity_media` | 352 | 32.681 ms | 613.616 ms | 41.637 ms | August 12, 2026 |
| `activity_engagement_summaries`, dominant fingerprint | 655 | 38.894 ms | 1,119.198 ms | 61.434 ms | August 10, 2026 |
| `activity_engagement_summaries`, second fingerprint | 587 | 37.136 ms | 1,325.035 ms | 78.851 ms | August 10, 2026 |

These are **actual accumulated server execution timings, not planner cost estimates**. The dominant Feed fingerprint accounts for 401.446 seconds of execution over its 1,111 calls. It recorded 8,235,115 shared buffer hits, one shared buffer read, and no temporary blocks written. This does not show an obvious disk-spill story; nested function/CPU/authorization work remains a candidate requiring a plan. Counters do not identify the expensive internal operation.

**Limits:** the statistics span multiple app/server versions and accounts. No reset or per-request timestamps isolate REC-497 or this recording session. These are not p50/p95/p99, cannot be paired into a single request waterfall, and exclude client/network/image-download latency. Tracking is `top`, so nested helper costs are not individually broken out. The small extra Feed fingerprints and administrator entries are retained in the evidence file but not conflated with the dominant authenticated history.

The SQL connection had **no app request identity** (`app.current_user_id() IS NOT NULL` returned false). Running Feed as-is would measure its empty/no-viewer path. I did not invent a user ID, set JWT claims, or call a representative account’s Feed. A fresh representative authenticated trace and bounded query plan are the remaining measurement gap.

Evidence and reproducible read-only queries: [numeric/function receipt](feed-production-evidence.json), [function catalog query](astir-feed-catalog-readonly.sql), [statistics availability query](astir-feed-stats-catalog-readonly.sql), [existing timing query](astir-feed-existing-timings-readonly.sql).

## Actual request path

1. Feed mounts, yields a UI frame, and calls `refresh(force: false)`. [FeedScreen.swift:122](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Features/Feed/FeedScreen.swift:122>)
2. Store joins a same-account/context request, or checks successful content, matching presentation revision, and the 60-second age. Forced refresh bypasses age reuse. [WanderLocalStore.swift:1621](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Services/WanderLocalStore.swift:1621>), [FeedModels.swift:171](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Services/FeedModels.swift:171>)
3. Repository calls `followed_feed` with first-page limit 25. A narrow initial-token-unavailable/not-authenticated failure retries once after 300 ms; other failures are surfaced. The underlying transport also supports token refresh after an HTTP 401/403. These can add startup latency without a slow query. [WanderLocalStore.swift:2283](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Services/WanderLocalStore.swift:2283>), [WanderSupabaseClient.swift:339](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Services/Remote/WanderSupabaseClient.swift:339>)
4. On cold load, server-authorized text/cards publish immediately after the Feed result is decoded/projected, before media. Warm refresh retains existing content. [SupabaseRepositories.swift:680](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Services/Remote/SupabaseRepositories.swift:680>), [WanderLocalStore.swift:1674](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Services/WanderLocalStore.swift:1674>)
5. The repository then calls `activity_media`, resolves private photo URLs in batches of up to eight, and produces the hydrated page. Engagement summaries follow. Thus “first card visible,” “photos visible,” and “refresh completed” are different milestones. [SupabaseRepositories.swift:701](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Services/Remote/SupabaseRepositories.swift:701>), [SupabaseDTOs.swift:391](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Services/Remote/SupabaseDTOs.swift:391>)
6. If the resulting activity is empty, Feed subsequently requests people recommendations. This matters for the proposed experience for someone who has followed nobody: recommendation readiness can arrive later than the empty Feed. [FeedScreen.swift:467](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Features/Feed/FeedScreen.swift:467>)

Existing `Remote RPC` signposts wrap the transport operation including token work, response, and decoding. They can locate expensive client-visible calls, but do not isolate database execution from networking. Record those stages separately.

## Server-side candidates to measure

The RPC is a `stable` read projection returning JSON, not evidence of a long write transaction. In the build-174 SQL:

- `eligible_events` applies follow/profile/block/source-place/visit/list visibility rules across candidate events.
- Activity uses a cursor, ordered `page_limit + 1`, then a 25-item page.
- `rendered_featured` separately reuses `eligible_events`, deduplicates by place, calls `feed_place_projection` in its selection and non-null predicate, excludes the viewer's saved places, then sorts and limits to eight.
- `feed_place_projection` joins the source save, place, profile, and optional visit. `feed_list_projection` counts undeleted list items. Actual repeated-call counts and planner behavior need a plan, not inference from SQL formatting.
- Actor/time and place/time indexes already exist. Do not claim “missing indexes” before examining the plan and cardinalities.

Sources: [current Feed projection](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/supabase/migrations/20260725214600_check_in_feed_projection.sql:97>), [projection helpers](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/supabase/migrations/20260725214600_check_in_feed_projection.sql:6>), [Feed indexes](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/supabase/migrations/20260720234500_feed_activity.sql:49>), [media RPC](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/supabase/migrations/20260811220214_activity_ticket_media.sql:6>).

The newer [REC-497 SQL at inspected main](https://github.com/joelipshutz/wander/blob/4937033a99175b2b22b48440a1376b644f6ad8e6/supabase/migrations/20260916171502_repeat_wanna_saves.sql#L194) retains the full-history Featured shape. It adds `app.can_read_activity_event(viewer_id, event.id)` alongside the existing visibility predicates, and replaces place rendering with an event-specific Wanna helper. Those correctness checks must be preserved during optimization; measure their contribution with the exact deployed function.

## What previous evidence does and does not show

| Record | Relevant result | Limitation |
|---|---|---|
| [REC-319](https://linear.app/recme/issue/REC-319/fix-latency-when-switching-feed-friends-and-featured-filters), Done | Tracks slow Feed filter changes and avoiding redundant refetch/redecode. | Historical issue, not a current latency measurement. |
| [REC-320](https://linear.app/recme/issue/REC-320/fix-feed-scroll-hitching-after-scrolling-begins), Done; PR #536 | Found repeated client bookmark scans, engagement publications, context rematerialization, and cache clearing. Fixed with indexing/batching/retained roots/cached photos. Aug 28 iPhone 16 Pro / iOS 26.6 fixture checks reported around 86 FPS; three extra cold samples had hitch ratios 0, 0, 3.32 ms/s. | Dense deterministic fixture, older commit. Not production-network performance; not all cold samples had zero hitches. |
| [REC-441](https://linear.app/recme/issue/REC-441/improve-login-feed-and-map-responsiveness-over-the-astir-redesign), Done; PRs #594/#603 | Controlled real repository with synthetic 100 ms Feed and 400 ms media delays: first content 504.65 → 100.59 ms. Five overlapping reads → one request; warm read → zero requests. | Demonstrates a waterfall/cache fix, not real server duration or cellular throughput. The issue's long description contains stale publish-blocker checkpoints; current status/PR attachments show subsequent completion. |
| [REC-378](https://linear.app/recme/issue/REC-378/make-physical-map-and-feed-hitch-tests-enforce-stable-regression), Todo | Existing hitch tests collect metrics but do not yet enforce stable device-specific hitch budgets. Requests three fresh-process samples and removal of raw UI-runner timing ceilings. | Passing a UI interaction test does not prove a frame-performance budget. |
| [REC-458](https://linear.app/recme/issue/REC-458/profile-frame-drops-and-interaction-latency-on-feed-profile-and-place), Backlog | Newer report still sees Feed/Profile hitches and requests Feed, Profile, and Place traces. | Device/build unspecified and not independently reproduced in the issue. |

The checked-in [REC-441 report](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/docs/reviews/rec-441-performance.md>) contains methods and measurement limits. Its two cited September 4 focused/Map result-bundle paths were **not present** when checked in this workspace. This pass therefore relies on the durable report and code/tests for those historical measurements; it did not re-extract the original samples.

Useful existing tests: [concurrent/warm cache test](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/WanderTests/WanderStoreTests.swift:6655>), [first-content-before-media benchmark](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/WanderTests/RemoteRepositoryTests.swift:1280>), and [cold-first-scroll fixture test](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/WanderUITests/MapPlaceCardActionInteractionUITests.swift:122>). Tests were inspected, not rerun. Running their synthetic delays again would not resolve the server hypothesis.

## Next measurement tasks

- [ ] Record affected device, OS, exact app build, network, thermal state, follow count, activity count, and media mix. Include a new account/few follows and a mature account as separate cases.
- [ ] Capture at least three cold-process first-Feed samples, three warm reentries inside 60 seconds, expired-cache reentry, and forced refresh. Record actual RPC count and whether presentation revision invalidated reuse.
- [ ] Time tap → shell, token readiness, Feed request start → response, decode/projection, first card paint, media RPC, signed URLs/image readiness, engagement completion, and recommendation readiness for empty Feed. Correlate hitches with those intervals.
- [x] Confirm deployed Feed SQL and obtain existing aggregate server timings: completed as above.
- [ ] Measure a fresh representative `followed_feed` execution with consented/sanitized data. Prefer read-only query statistics first; obtain a bounded plan with actual row counts/buffers in a safe replica/staging environment. Inspect Featured work separately from the activity page, helper-function work, sort/deduplication, and authorization predicates. No fresh representative production benchmark was run here; the read-only aggregate-statistics check is complete.
- [ ] Choose the fix from evidence: optimize/defer or split Featured if it dominates first content; reduce invalidation/refetch if cache misses dominate; optimize media if photos dominate; address rendering/layout if RPC is fast but the main thread hitches. Preserve block/privacy/account isolation and exact event semantics.
- [ ] Re-run equivalent before/after conditions and enforce REC-378's stable regression budget. Treat REC-458 as open until current Feed/Profile/Place evidence exists.

## N27 Setup guide: found and verified

The exact app destination is **[https://getrec.me/extensions](https://getrec.me/extensions)**, from [FirstVisitWalkthrough.swift:1928](</Users/joelipshutz/Documents/ChatGPT/New project/wander-release-174/Wander/Features/Onboarding/FirstVisitWalkthrough.swift:1928>). A read-only public fetch returned **HTTP 200**, HTML title **“Extensions · rec.me”**, at September 16, 2026, 17:48:57 PDT. Verification used the returned HTML; the interactive controls were not browser-click-tested in this pass.

The existing page is substantive, not a placeholder:

| Guide | Content present | Existing presentation |
|---|---|---|
| Import | Google Maps/Instagram/TikTok sharing; Notes/pasted text and review | Five-step native-screen walkthrough |
| Action Button | Settings → Action Button → Controls → select Check-in; press and hold to open nearby places | Seven-step native-screen walkthrough |
| Widgets | Home/Lock/Control Center; Nearby, Quick Add, Search, Activity Calendar | Five-step native-screen walkthrough |
| Share extension | Share → More → Edit → Favorites; then share into the app | Five-step native-screen walkthrough |

All four expose Pause and previous/next controls in the HTML and use real screenshot assets under `/product/extensions/`. The returned HTML has no video element. It is not evidence that the new cinematic phone/action-button animation requested in the transcript already exists.

**Concrete follow-up:** refresh the guide's rec.me branding, app/shortcut names, old “Add to rec.me” and “Wanna” labels, TestFlight CTA as appropriate to the actual release, and screenshots against the current Astir app. Reuse its verified instructional sequence as the starting point for N27's new motion concepts. Keep the existing destination visible on the review board while that refresh is tracked.

## Status

Source investigation, bounded production function/statistics check, and Setup guide verification are complete. Existing server timings support the performance hypothesis; exact current bottleneck attribution and a fresh representative trace remain open. No backend rewrite or performance-resolution claim is justified by this pass alone.
