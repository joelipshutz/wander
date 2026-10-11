# REC-636 implementation drafts

These SQL files are review drafts, **not installed migrations**. They remain unpackaged, undeployed and unexecuted. Native query/store integration and the approved D11 Live display lease now exist, but do not establish backend readiness. Keep the remote default `unified_live_v1` off. The delegated first rollout is internal-only after required verification.

## Current integration

[store.patch](store.patch) is historical applied input and has since been extended. **Do not reapply it.** The source of truth is `Wander/Services/WanderLocalStore.swift`, `LiveFeedQuery.swift`, `LiveFeedDisplayLease.swift`, `Features/Live/LiveBrowseSelection.swift` and `LiveScreen.swift`, with their focused tests.

Committed controls install `selectLiveFeedQuery(_:)` and refresh through the existing Feed surface. The native RPC payload includes time/type/polygon, selected center/radius, categories and people. Explicit nil restores the legacy API; ordinary tab return preserves the query. The SQL applies all refinements before the bounded page limit and includes each in the cursor fingerprint. Missing RPC capability fails visibly rather than silently returning a legacy page. Canonical viewer taxonomy travels with Live results; source actors’ private category overrides never become viewer facets.

D11 is approved and implemented as session-only, per-activity monotonic authorized-response receipts: social rows expire after 15 minutes, page loads renew only rows they authorize, and owner rows remain exempt. This does not change Profile, canonical owner data or legacy nil-query Feed cache policy. Receipts begin before media work; device suspension counts and wall-clock changes cannot extend them. Current device-location centering is not implemented; selected-city centers work.

## Package and verify

1. Inspect `supabase --version`, `supabase migration new --help` and `supabase db push --help`. Review the confirmed linked target and migration history before any hosted change.
2. Run `supabase migration new private_contextual_messages` first. Copy reviewed [private-contextual-messages.sql](private-contextual-messages.sql) into the CLI-generated file and replace its draft-status comments. This creates the messaging contract and dormant Boolean `unified_live_v1` registry row while preserving existing keys/ranges.
3. Run `supabase migration new live_activity_feed` second. Copy [live-feed.sql](live-feed.sql) into that CLI-generated file. It adds the complete Live query RPC, polygon validator and time index without replacing legacy Feed APIs or visibility helpers. Do not invent migration filenames or apply documentation drafts directly.
4. Review both generated migrations and run their rollback-only regressions. Verify radius/category/person predicates precede the limit, all filters bind the cursor, viewer taxonomy matches the native projection, and no authorized source subset broadens. Run the integrated native store/query/lease tests and appropriate regression suite.
5. Apply through the approved migration workflow to the confirmed target, verify `supabase migration list --linked`, inspect function/grant metadata and run hosted smoke. Activation remains a separate internal rollout step through the full-launch flag platform.

## Verification status and commands

- Native tests include `PrivateMessageRepositoryTests`, `PrivateMessageRPCClientTests`, `LiveFeedQueryTests`, `LiveFeedStoreTests` and `LiveFeedDisplayLeaseTests`, plus existing Feed audience/paging/navigation coverage. The [integrated validation report](../review/integrated-validation.md) is the single authority for candidate identity, executed checks, results and outstanding validation; the suite inventory here is not a pass claim.
- SQL regressions are `supabase/tests/private_contextual_messages.sql` and `supabase/tests/live_activity_feed.sql`. Both use synthetic fixtures and roll back. Messaging covers per-account approval/revocation/restoration, global-flag non-bypass, mutual/block/source access, idempotency, quotas and read acknowledgments. Live covers 60 newer nonmatches before eligible results, every refinement, viewer taxonomy, tied pagination and cursor/account mismatches.
- The smoke runner includes both suites in direct and linked paths. After migrations are installed, run `npm --prefix scripts ci --ignore-scripts`, then `node scripts/supabase-smoke-test.mjs` against the confirmed target. Missing RPC/schema must fail; do not skip suites to make smoke pass.
- Offline rollback-preview generation is available: `node scripts/supabase-smoke-test.mjs --print-sql --migration-preview docs/designs/astir-live/implementation-drafts/private-contextual-messages.sql --migration-test supabase/tests/private_contextual_messages.sql`; repeat with `live-feed.sql` and `live_activity_feed.sql`. **Generation is not database execution.** Local/hosted SQL behavior and metadata verification remain outstanding.

## Internal messaging boundary

- Both participants require an operator-owned, account-specific `unified_live_v1` Boolean true row, plus mutual friendship and all existing access checks. A global true row or client/device override cannot approve a participant. Revoking either account row denies subsequent inbox/history/send/retry/read access. Client roles retain no flag write grants.
- Messaging is 1:1 text only, without attachments, groups, presence, realtime subscriptions or message push delivery. Pending/ambiguous retries preserve their client-generated idempotency UUID. Initial fetches, paging and send/read responses provide server acknowledgment, not delivery evidence.
- Client state is memory-only; the dedicated ephemeral transport disables URL caching/cookies and avoids body/raw-error logging. Review replay masking, inactive-scene cover and account/lifecycle evidence in the integrated validation report before activation.
- Each operation rechecks participants, account approval, mutual friendship, hard blocks and context access. A revoked/deleted context suppresses its message, preview and unread count. Unrelated follow-on text still requires conversation eligibility.
- **Account-deletion retention remains a broad-rollout blocker.** Soft-deleted accounts lose access while stored rows remain; physical profile deletion cascades through conversations/messages. No new purge schedule or retention period is approved by this draft.
- Reporting/moderation, retention/export, notification scope and operational recovery require resolution before broader rollout. Existing profile block/report routes remain. Draft send limits are 20/minute and 200/day, with 50 new conversations/day; authenticated hosted verification and operational tuning are still required.
