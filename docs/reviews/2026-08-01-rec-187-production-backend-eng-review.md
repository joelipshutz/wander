# REC-187 Production Backend Engineering Review

Date: 2026-08-01
Branch: `codex/rec-187-prod-backend`
Reviewer: Codex

## Scope

Audit and harden the currently linked rec.me Supabase project without resetting data, changing providers, rotating credentials, flipping the iOS Release build to new credentials, or releasing a build. This is the safe implementation slice of REC-187 and REC-182.

## Step 0: Scope Challenge

### What already exists

- One active rec.me Supabase project, `wander`, linked as project ref `rugmtlgufrhlxwfkumhw`.
- Local and hosted migration ledgers match through `20260730010000_surface_snapshot_rpcs.sql`.
- All app-owned public tables have RLS enabled. The only public table without RLS is PostGIS-managed `spatial_ref_sys`.
- Edge Functions are deployed and manually validate their trust boundary: Svix for Clerk webhooks, `WANDER_WORKER_SECRET` for workers, and Clerk/PostgREST identity checks for client-facing functions.
- Required named secrets for Clerk webhook delivery, APNs, workers, Supabase, Google Places, and OpenAI are present. Values were not read or copied.
- The iOS Release configuration still points to the Clerk development instance and uses the same auth config file as Debug.
- Production contains 11 profiles, 126 user places, 19 lists, 27 list items, 16 follows, 27 storage objects, and zero rows in `analytics_events`. Database size is 141 MB.

### Minimum complete change

1. Remove unintended anonymous/authenticated execution from the service-role-only Clerk mirror RPC.
2. Correct the list-item RLS expression that can accept a user-place reference for a different place.
3. Remove unused anonymous analytics ingestion and restrict analytics events to signed-in, self-attributed inserts.
4. Make new public relations opt-in to Data API grants.
5. Add focused pgTAP and permanent hosted smoke assertions.
6. Prove the forward migration against the hosted schema inside a rolled-back transaction before any live migration is considered.

This review does not authorize a database reset, production-project promotion, Clerk production deployment, DNS/OAuth changes, credential rotation, Release configuration flip, migration push, or TestFlight/App Store release.

## Architecture

```text
Clerk signed webhook
  -> clerk-profile-webhook Edge Function
     -> service_role PostgREST call
        -> public.mirror_clerk_profile (SECURITY DEFINER)
           -> app.mirror_clerk_profile

iOS authenticated user
  -> Supabase Data API
     -> RLS / authenticated RPC
        -> user-owned rows

anonymous web visitor
  -> public.public_web_preview only
     -> deliberately minimized public projection
```

## Findings

### P0: Clerk mirror RPC is client-callable

Hosted metadata shows `anon` and `authenticated` can execute `public.mirror_clerk_profile(...)`, even though the function is a security definer documented as service-role-only. The originating migration revoked `PUBLIC` but did not revoke the cloud-generated direct grants to Data API roles. The function can create, update, or hard-delete profile data based on caller-supplied webhook fields.

Fix: explicitly revoke `public`, `anon`, and `authenticated`; retain only `service_role`. Add metadata assertions to pgTAP and the hosted smoke suite. Do not probe this by calling the vulnerable RPC against a real profile.

### P1: List-item RLS compares an inner column to itself

The insert/update policies use `up.place_id = place_id` inside a `user_places up` subquery. PostgreSQL binds the unqualified right-hand `place_id` to `up.place_id`, making it a tautology. A direct Data API write can therefore pair a visible `user_place` with a different `place_id`.

Fix: fully qualify all outer `place_list_items` references and test both matching and mismatched payloads through authenticated RLS.

### P1: Anonymous analytics inserts are allowed

The original policy accepts `user_id is null`, and the hosted table has a direct `anon` insert grant. The app does not use this table, and production has zero analytics rows, so the current behavior only creates a spam/abuse surface.

Fix: revoke anonymous access; allow authenticated `select`/`insert` only; require `user_id = app.current_user_id()`.

### P2: New Data API objects are not explicitly opt-in

`supabase/config.toml` leaves `auto_expose_new_tables` unset. Existing hosted grants show why explicit least privilege matters.

Fix: set `auto_expose_new_tables = false`. Every future migration must grant only the exact roles and operations required.

### REC-163 diagnosis is stale

Production already has `place_visits_sync_user_place_after_delete`, created by `20260709220000_place_visits_visit_photos.sql`. Migration `20260725214500_check_in_ticketing.sql` replaces the function but does not drop the trigger, so no replacement trigger migration is warranted. The existing rollback smoke covers deleting the latest ticket and deleting the final ticket; that behavior must pass before REC-163 is closed.

## Failure modes and controls

| Failure | Control |
|---|---|
| Webhook loses production access | Preserve `service_role` execute and assert it in pgTAP/smoke |
| Authenticated client can spoof webhook events | Assert both `anon` and `authenticated` lack execute |
| List add starts rejecting valid rows | Test a matching `place_id`/`user_place` pair before testing mismatch rejection |
| Analytics hardening breaks app behavior | Repo search found no app caller; production table is empty; retain authenticated self inserts |
| Migration is incompatible with hosted schema | Run migration preview plus focused pgTAP inside one hosted rollback transaction |
| Check-in deletion regresses | Run full hosted rollback smoke after the preview |
| Production cutover strands alpha data | No cutover/reset in this branch; require an explicit backup and data decision first |

## Production cutover decision still required

Recommendation: harden and promote the existing Supabase project instead of creating a second database. It is healthy, small, fully migrated, and already integrated with Edge Functions and App Store builds. A second project would duplicate schema, buckets, secrets, functions, quotas, and operational failure modes without providing a mature staging pipeline.

Before cutover, Joe must explicitly choose how to handle the 11 Clerk-development profiles and their user-owned rows. Production Clerk identities will not automatically equal development identity IDs. The safe default is: export/verify a recoverable backup, preserve global place catalog data, and perform a reviewed cleanup/migration of development user-owned data during a scheduled cutover. No deletion or credential flip is part of this change.

## Validation plan

- Hosted migration ledger parity before changes.
- Focused hosted migration preview with `production_security_hardening.sql` pgTAP, rolled back.
- Full hosted smoke with the migration preview, rolled back.
- Hosted metadata check after any future live migration: RPC ACL, `prosecdef`, pinned `search_path`, analytics grants, policy expressions, and migration ledger.
- No iOS test suite is required for this DB-only patch; no client payload or value-type contract changes.

## Execution evidence

- Focused hosted migration preview: 15/15 pgTAP assertions passed; transaction rolled back.
- Full hosted smoke with migration preview: passed; transaction rolled back.
- Dry run: exactly `20260802001500_production_security_hardening.sql` pending.
- Live push: exactly that migration applied successfully.
- Post-push ledger: local and hosted both include `20260802001500`.
- Post-push metadata: `anon` and `authenticated` cannot execute Clerk mirroring; `service_role` can; anonymous analytics insert is revoked; authenticated analytics update/delete are revoked; both list policies contain the qualified place equality.
- Full hosted smoke on deployed state: passed after making the pre-existing geography assertion select its named fixture deterministically; transaction rolled back.
- REC-163: production trigger presence and both deletion transitions verified; no duplicate trigger migration created.

## Out of scope

- Applying the migration to production before review.
- Clerk production instance creation/deploy, DNS, OAuth, webhook secret replacement, or Supabase issuer change.
- Alpha data deletion or migration.
- Database network restrictions, paid plan/backups configuration, or secret rotation without an approved access/rollback plan.
- Build-number increment, archive, TestFlight upload, App Store submission, or Slack release note.
