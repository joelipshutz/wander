# REC-636 implementation drafts

The SQL drafts have been packaged as an ordered migration pair through Supabase CLI 2.114.0. **The migrations are not installed. Both targeted rollback previews and the full predeployment smoke preview pass; post-install hosted smoke remains outstanding.** Native query/store integration and the approved D11 Live display lease now exist, but do not establish backend readiness. Keep the remote default `unified_live_v1` off. The delegated first rollout is internal-only after required verification.

## Current integration

[store.patch](store.patch) is historical applied input and has since been extended. **Do not reapply it.** The source of truth is `Wander/Services/WanderLocalStore.swift`, `LiveFeedQuery.swift`, `LiveFeedDisplayLease.swift`, `Features/Live/LiveBrowseSelection.swift` and `LiveScreen.swift`, with their focused tests.

Committed controls install `selectLiveFeedQuery(_:)` and refresh through the existing Feed surface. The native RPC payload includes time/type/polygon, selected center/radius, categories and people. Explicit nil restores the legacy API; ordinary tab return preserves the query. The SQL applies all refinements before the bounded page limit and includes each in the cursor fingerprint. Missing RPC capability fails visibly rather than silently returning a legacy page. Canonical viewer taxonomy travels with Live results; source actors’ private category overrides never become viewer facets.

D11 is approved and implemented as session-only, per-activity monotonic authorized-response receipts: social rows expire after 15 minutes, page loads renew only rows they authorize, and owner rows remain exempt. This does not change Profile, canonical owner data or legacy nil-query Feed cache policy. Receipts begin before media work; device suspension counts and wall-clock changes cannot extend them. Current device-location centering is not implemented; selected-city centers work.

## Packaged migrations

1. [Private contextual messages](../../../../supabase/migrations/20261014020218_private_contextual_messages.sql): creates the private messaging contract and dormant flag registration.
2. [Live activity feed](../../../../supabase/migrations/20261014020238_live_activity_feed.sql): adds the filtered Live RPC, polygon validator and time index.

Only the draft-status comments changed during packaging; executable SQL matches the reviewed source drafts. These migration files are the deployment source of truth. Keep the original drafts as historical review input and do not apply them separately.

## Deployment procedure

1. Inspect `supabase --version`, `supabase migration new --help` and `supabase db push --help`. Review the confirmed linked target and migration history before any hosted change. Do not replay old migrations or repair unrelated history as part of this feature. Use a reviewed, targeted deployment of only the new ordered pair; a CLI push is acceptable only if its dry run identifies exactly those two files.
2. The CLI-generated messaging migration is already packaged first. Review it against [private-contextual-messages.sql](private-contextual-messages.sql); it creates the messaging contract and dormant Boolean `unified_live_v1` registry row while preserving existing keys/ranges.
3. The CLI-generated Live migration is already packaged second. Review it against [live-feed.sql](live-feed.sql); it adds the complete Live query RPC, polygon validator and time index without replacing legacy Feed APIs or visibility helpers. Do not regenerate duplicate migrations or apply documentation drafts directly.
4. Review both generated migrations and run their rollback-only regressions. Verify radius/category/person predicates precede the limit, all filters bind the cursor, viewer taxonomy matches the native projection, and no authorized source subset broadens. Run the integrated native store/query/lease tests and appropriate regression suite.
5. Apply through the approved migration workflow to the confirmed target, then compare local and hosted migration records, inspect function/grant metadata and run hosted smoke. If the migration tool allocates its own version, reconcile the returned version with the local filename before another deployment. Keep the global `unified_live_v1` value false. Activation remains a separate internal rollout step through the full-launch flag platform.

## Durable dormant checks

[rec636_dormant_metadata.sql](../../../../supabase/tests/rec636_dormant_metadata.sql) checks the fourteen exact function identities and ABI/security/grant contracts, private-table RLS, the nine-key flag registry and 660 type/range combinations. It requires global Live Off, uses only the catalog search path for expression evaluation and rejects unreviewed executable dependencies. Run it inside the ordered rollback preview before installation, then without previews after installation. These checks supplement the behavior smoke suite.

[rec636_preinstall_baseline.sql](../../../../supabase/tests/rec636_preinstall_baseline.sql) reports only aggregate new-object, Live-row and exact reserved-profile counts. Compare before and after each rolled-back preview; all new-object/row counts must remain zero. It is not a post-install success check.

Offline verifier contracts run with `node --test scripts/rec636-dormant-metadata.test.mjs`. The recovery metadata preview and rollback baseline pass; this does not install the migrations or establish real client delivery.

## Read-only real-client preflight

`scripts/rec636-real-client-verification.mjs` defaults to offline input validation. Explicit `--preflight` validates two supplied identities through the actual gateway and reads their inboxes; `--help` describes its stdin-only input. It discovers no credentials and reports no tokens, profile fields or message bodies. Sixteen offline tests cover its target, identity, transport and output contracts.

Write mode is blocked until a privileged cleanup companion is implemented and verified. A passing preflight does not prove participant enrollment, absence of empty conversations, delivery, concurrency or native UI behavior. Use designated internal accounts and signed-in test sessions; do not put secrets in command arguments or review artifacts.

## Two-account verification protocol

Use two designated internal test accounts, mutually following each other, with explicit operator-owned account flags. Keep the global flag off. Use a shared synthetic place and synthetic message text; record pass/fail and aggregate counts without saving credentials or private message bodies in evidence.

1. Start from the same Wanna context on both accounts. Confirm the existing invitation route is unchanged, then send a private message, fetch it on the other account, reply and mark it read. Relaunch and verify server-acknowledged history and read state.
2. Send the same client UUID concurrently and after an interrupted response. Both successful replies must identify the same message and history must contain one row. Concurrent reciprocal conversation starts must return the same conversation ID. Concurrent sends from opposite participants must both finish without deadlock.
3. Remove either account's approval, remove a mutual follow, block in each direction and revoke the quoted source in separate trials. Existing and fresh inbox/history/send/retry/read requests must respect each change. Restore only the fixture state between trials. Global enablement or a device override must never replace account approval.
4. Verify Live type/time/category/person/radius/drawn-area filters against known synthetic results, including a second page and a cursor reused with a different query/account. Verify a broad initial camera in sparse data, a tighter default in dense data and no automatic reframing after a manual pan.
5. Go offline after an authorized Live refresh. Social rows must disappear after their individual 15-minute leases; owner rows and Profile history remain. Resume, change accounts, background the messaging inbox/thread and verify no stale private state is exposed. Actual replay and app-switcher captures remain separate required evidence.

Quota boundaries and authorization during lock waits need controlled synthetic fixtures and two database sessions; do not flood real accounts to reach limits. At 19 messages in the minute, two simultaneous new sends by one sender must yield one acceptance and one rate limit, while an idempotent retry still succeeds. Hold the sender advisory lock, start a contextual request in another session, revoke its source and release the lock: the waiting request must reject access. A reciprocal-start test must also cover the unique-pair conflict wait. The rollback SQL suite covers single-session limits and access changes; it does not prove these concurrent cases or real client authentication.

## Verification status and commands

- Native tests include `PrivateMessageRepositoryTests`, `PrivateMessageRPCClientTests`, `LiveFeedQueryTests`, `LiveFeedStoreTests` and `LiveFeedDisplayLeaseTests`, plus existing Feed audience/paging/navigation coverage. The [integrated validation report](../review/integrated-validation.md) is the single authority for candidate identity, executed checks, results and outstanding validation; the suite inventory here is not a pass claim.
- SQL regressions are `supabase/tests/private_contextual_messages.sql` and `supabase/tests/live_activity_feed.sql`. Both use synthetic fixtures and roll back. Messaging covers per-account approval/revocation/restoration, global-flag non-bypass, mutual/block/source access, idempotency, quotas and read acknowledgments. Live covers 60 newer nonmatches before eligible results, every refinement, viewer taxonomy, tied pagination and cursor/account mismatches.
- The smoke runner includes both suites in direct and linked paths. After migrations are installed, run `npm --prefix scripts ci --ignore-scripts`, then `node scripts/supabase-smoke-test.mjs` against the confirmed target. Missing RPC/schema must fail; do not skip suites to make smoke pass.
- Full credential-free linked smoke export is available with `node scripts/supabase-smoke-test.mjs --write-linked-sql <output.sql>`. Before installation, append both ordered migration files using repeated `--migration-preview` arguments. After installation, omit previews and run the exported file with the pinned CLI's `db query --linked --project-ref <confirmed-project> --file <output.sql>`. This export includes the additional linked suites; `--print-sql` alone does not.
- Individual offline rollback-preview generation is available: `node scripts/supabase-smoke-test.mjs --print-sql --migration-preview docs/designs/astir-live/implementation-drafts/private-contextual-messages.sql --migration-test supabase/tests/private_contextual_messages.sql`; repeat with `live-feed.sql` and `live_activity_feed.sql`. **Generation is not database execution.** Both targeted migration previews were subsequently executed and passed. The Live test now removes only automatic signup follows from its exact synthetic accounts; every original assertion remains. Rollback checks found zero new tables, RPCs, flag rows or fixture profiles. The first broader preview failed an existing notification-copy assertion, also reproduced without Live. [REC-638 / PR #741](https://github.com/joelipshutz/wander/pull/741) restores the already-deployed source and changes only three stale expected strings. That correction passes the full existing-schema hosted suite; the Live candidate includes it, and its complete linked preview now passes with both new migrations. Preview mode omits the paid-import ledger suite by the runner’s existing rule; the full existing-schema run included it. Post-install smoke must run without previews, followed by metadata verification. No schema changes persist from these previews.

## Internal messaging boundary

- Both participants require an operator-owned, account-specific `unified_live_v1` Boolean true row, plus mutual friendship and all existing access checks. A global true row or client/device override cannot approve a participant. Revoking either account row denies subsequent inbox/history/send/retry/read access. Client roles retain no flag write grants.
- Messaging is 1:1 text only, without attachments, groups, presence, realtime subscriptions or message push delivery. Pending/ambiguous retries preserve their client-generated idempotency UUID. Initial fetches, paging and send/read responses provide server acknowledgment, not delivery evidence.
- Client state is memory-only; the dedicated ephemeral transport disables URL caching/cookies and avoids body/raw-error logging. Review replay masking, inactive-scene cover and account/lifecycle evidence in the integrated validation report before activation.
- Each operation rechecks participants, account approval, mutual friendship, hard blocks and context access. A revoked/deleted context suppresses its message, preview and unread count. Unrelated follow-on text still requires conversation eligibility.
- **Account-deletion retention remains a broad-rollout blocker.** Soft-deleted accounts lose access while stored rows remain; physical profile deletion cascades through conversations/messages. No new purge schedule or retention period is approved by this draft.
- Reporting/moderation, retention/export, notification scope and operational recovery require resolution before broader rollout. Existing profile block/report routes remain. Draft send limits are 20/minute and 200/day, with 50 new conversations/day; authenticated hosted verification and operational tuning are still required.
