# rec.me Production Blue/Green Cutover and Undo Runbook

Status: pre-cutover. A fresh local backup and an independently encrypted iCloud Drive copy were verified on 2026-08-14. The Clerk password-hash export, green target, and traffic switch remain blocked gates. No traffic has moved.

## Fixed identities

- Source/rollback Supabase project: `wander` (`rugmtlgufrhlxwfkumhw`), `us-west-2`.
- Intended target name: `recme-production`, same Supabase organization and region.
- Fresh private backup root: `/Users/joelipshutz/.private_backups/recme/2026-08-14-pre-launch-cutover/`.
- Encrypted off-device copy: `iCloud Drive/Grayline Backups/recme/2026-08-14-pre-launch-cutover.tar.gz.enc`; AES-256-CBC with PBKDF2, archive and SHA-256 sidecar mode `0600`, recovery passphrase stored in macOS Keychain service `com.grayline.recme.backup.2026-08-14`.
- Independent older recovery point: `/Users/joelipshutz/.private_backups/recme/2026-08-01-pre-production-cutover/`.
- Source must not be reset, deleted, paused, or repurposed during the cutover and rollback window.

## What “undo” means

There are two rollback boundaries:

1. **Before target production writes:** undo is clean. Stop the cutover, keep the source project and current iOS/Clerk configuration, and discard or pause the unlaunched target.
2. **After target production writes:** do not blindly point clients back to the old database. First preserve the target, reconcile writes created since cutover, and then restore or roll forward. A blind switch would lose production changes.

The current iOS app embeds its Supabase URL/key at build time. A backend switch therefore needs a new TestFlight/App Store build unless a separately reviewed runtime configuration layer is added. “Undo” is a controlled release procedure, not an instantaneous server toggle.

## Backup contract

The backup is complete only when all of these exist and validate:

- `database/database-full-v2.custom`: final verified compressed PostgreSQL logical dump containing all accessible schemas and data, including `app`, `public`, `auth`, cron, Realtime, Storage metadata, Vault ciphertext, and the migration ledger. `database-full.custom` is an earlier independent point-in-time snapshot retained for redundancy.
- `database/globals-and-roles.sql`: global roles without role passwords.
- `storage/`: every object byte from every source bucket. The 2026-08-14 inventory contains `visit-photos`, `profile-avatars`, and `google-place-photo-cache`; do not rely on an older fixed bucket list.
- `config/source-repo-config.tar.gz`: migrations, Edge Function source, Supabase config, hosted smoke test, and current iOS auth config.
- `config/hosted-functions.json`: deployed function inventory.
- `config/hosted-secret-digests.json`: hosted secret names/digests. Supabase does not return secret values after creation.
- `secrets/recme-operational.env`: private local copy of the rec.me values available in the approved local key store; mode `0600`.
- `secrets/database-vault-decrypted.base64.env`: owner-only, one-line base64 export of the source database Vault values, including the scheduled-worker secret. Decode values only into a private shell/process when restoring.
- `manifests/source-inventory.txt`: exact source counts/config/security metadata.
- `manifests/SHA256SUMS`: checksum of every backup artifact except the checksum file itself.
- `manifests/verification.txt`: dump parse, file count, permissions, and checksum verification results.
- `manifests/dump-row-counts.txt` and `manifests/live-row-counts.txt`: non-secret evidence that the dump contains every comparable source row at capture time.
- `clerk/development-users-public.json` and `clerk/production-users-public.json`: owner-only before/after inventories used by the account-continuity audit. The password-hash CSV joins this folder only after the Dashboard export passes the audit below.

Do not put the private backup or secret file in Git, Slack, Linear, a PR, or a shared cloud folder.

The logical dump contains encrypted Vault rows, but Supabase owns the encryption root key. Prefer the native physical restore-to-new-project path because it transfers that root key. Do not claim a manual logical restore can decrypt Vault secrets unless that is explicitly proven on the target.

Hosted Edge Function secret values cannot be read back after creation. The approved local key store plus the Vault export cover the recoverable app/provider and worker values. The APNs values (`APNS_KEY_ID`, `APNS_PRIVATE_KEY`, `APNS_TEAM_ID`, and `APNS_TOPIC`) are not present in that local store; obtain the authoritative Apple key material or rotate to a new APNs key before target validation. Until that succeeds, the source project is the only verified running copy of those Edge secrets and must remain untouched.

## Create and verify the source backup

All database commands are read-only against the source. Use the Supabase session pooler and the database password from the private key store; never paste credentials into this document.

1. Run the full custom dump and role dump.
2. Run `scripts/production-cutover-inventory.sql` against the source and save its output.
3. Read the bucket inventory, then download every Storage bucket recursively. Never assume the historical two-bucket list is complete.
4. Archive the source-controlled backend/configuration files.
5. Export deployed function inventory and secret names/digests.
6. Generate SHA-256 checksums.
7. Validate the dump with `pg_restore --list`; extract data-only SQL into a private temporary file and compare exact per-table row counts; verify checksums; compare remote and local Storage object counts and total bytes.
8. Copy the entire private backup directory to a second encrypted location before traffic cutover. A single disk copy is not disaster recovery.

Completed 2026-08-14: all source checksums passed before encryption; the decrypted stream produced a valid complete tar inventory; the encrypted 169 MB archive passed its SHA-256 sidecar; and iCloud Drive reported caught up after the copy.

## Create the green production project

Preferred database path: Supabase Dashboard → source project → Backups → restore to a new project. Review the exact project name, organization, region, selected backup/PITR point, and displayed recurring cost before confirming. The action creates a second paid project and requires explicit confirmation at that screen.

2026-08-14 creation checkpoint: the CLI refused to create `recme-production` before provisioning because both organization administrators already hold Supabase's maximum two active free projects. No target was created and no source project changed. Supabase's public pricing currently lists Pro at $25/month with $10/month of compute credits for one Micro project and additional Micro projects from $10/month. Keeping the two current active projects and adding green therefore appears to be about $45/month before overages, not the earlier ~$10 estimate; verify the checkout total before purchase. Creating the green target now requires either upgrading the existing organization at the exact displayed plan price or an explicitly approved alternative. Do not pause/delete another Grayline project to free a slot.

Supabase's database clone does not finish the application clone. After the target exists:

1. Record the target ref, database password, API URL, anon key, and service-role key in the private key store.
2. Confirm hosted migration parity and run `scripts/production-cutover-inventory.sql` on source and target.
3. Recreate/copy every inventoried Storage bucket and upload every backed-up object; compare object paths, counts, byte sizes, and sampled SHA-256 hashes.
4. Deploy every Edge Function from source control with its existing `verify_jwt` setting.
5. Re-enter each Edge Function secret from its authoritative private source; compare names and hosted digests where available.
6. Recreate scheduled jobs, Auth/Third-Party Auth settings, Realtime/API limits, network restrictions, and any dashboard-only settings.
7. Configure the production Clerk issuer/domain, signed `canonical_user_id` claim, and production Clerk webhook. Import the six verified development users only through the lossless procedure below; never create replacements by email alone.
8. Run focused pgTAP metadata assertions and the full hosted rollback smoke test against the target.
9. Validate production tokens through profile mirror, save/sync, visibility, follow/block, Storage, notifications, and account deletion using non-production fixtures inside rolled-back transactions where supported.

## Lossless Clerk account migration gate

The six active Clerk development users all have passwords and verified email addresses. Their source records are now tagged with public metadata `canonical_user_id` equal to the existing Clerk ID. This tag is non-destructive and leaves the current app unchanged.

Do not import any production user until all of these steps pass:

1. Sign into the correct Clerk owner workspace and export all development users from **Settings → User Exports**. Save the CSV only under the owner-only `clerk/` backup folder; never commit, upload to Slack/Linear, or paste it into chat.
2. Build the audited private JSON input with `node scripts/clerk-account-continuity-audit.mjs --export-csv <private-export.csv> --source-json <development-users-public.json> --prepare-import-json <new-private-import.json> --expected-count 6`. It must report six password digests, six verified primary emails, and six matching stable-ID tags. The builder restores public/private/unsafe metadata from the source API inventory as JSON objects, because Dashboard CSV exports may omit metadata and CSV strings are not a safe metadata input to the migration tool. It refuses to overwrite an existing output file and sets mode `0600`. Any missing hash, hasher, verified email, source match, or ID is a hard stop.
3. Use Clerk's official `migration-tool` pinned to commit `bbf75584668e9f10a239b545adbce57e1308c974` with that audited private JSON file. Its Clerk transformer sets each production user's `external_id` to the exported development `id` and imports the password digest/hasher plus object metadata. Target only the empty production instance and require passwords.
4. OAuth connections are not copied. Because the one current Google-linked account also has a migrated password, it retains immediate email/password access; verify Clerk's verified-email account linking lets the same person reconnect Google without creating a second account.
5. Export fresh source/production public inventories and run `node scripts/clerk-account-continuity-audit.mjs --source-json <dev.json> --target-json <prod.json> --expected-count 6`. It must prove 6/6 external-ID mappings, metadata mappings, password-enabled accounts, and email matches.
6. On the green target, verify each production identity resolves to its existing profile and exact owned-data counts. Check user places, visits, lists/memberships, follows, activity comments/likes, notification state, source artifacts, and Storage visibility. A count mismatch is a hard stop.
7. Keep the development Clerk instance and source Supabase project intact for rollback. Do not delete development users after launch.

## Go/no-go gate before traffic

Do not change Release configuration until every item is true:

- Source backup and second encrypted copy verify.
- Source remains healthy and unchanged except for explicitly reviewed compatibility settings.
- Target database counts/security metadata match the intended migration policy.
- Every Storage object in the latest source inventory is present; object counts, total bytes, and sampled hashes match. The 2026-08-14 snapshot contains 53 objects across three buckets.
- Functions, secrets, scheduled jobs, Auth, Realtime, API, and network settings are inventoried and recreated.
- Clerk production tokens work against target RLS/RPC paths.
- The six active Clerk users pass the lossless export and 6/6 production mapping audits above; no email-only or guessed ID matching is allowed.
- A rollback build/config exists and has passed the same smoke tests.
- A short write-freeze window and an owner for monitoring are scheduled.

## Cutover sequence

1. Announce the write-freeze window to current testers.
2. Stop source writes using a separately reviewed maintenance/grant change; verify mutations fail while reads remain available.
3. Take a final database and Storage delta snapshot and verify its checksums.
4. Reconcile any delta into the target and rerun parity checks.
5. Build Release with production Clerk plus the target Supabase URL/key. Do not change Debug unless explicitly intended.
6. Run signed-in device smoke tests, then release through the normal TestFlight/App Store procedure.
7. Monitor auth, RLS/sync, webhooks, functions, notifications, crashes, and provider spend.
8. Keep the source project and all backups for at least 30 days after stable production launch. Do not delete them as part of cutover.

## UNDO procedure

When Joe says **undo**, immediately stop forward changes and classify the boundary:

### A. No target production writes yet

1. Do not ship or distribute the target-configured build.
2. Keep/restore Release configuration to the source URL/key and current Clerk config.
3. Remove any source write freeze only by applying the reviewed inverse grant/config change.
4. Run the hosted smoke test against the source.
5. Mark the target inactive; do not delete it until its backup and incident review are complete.

### B. Target has accepted production writes

1. Freeze writes on the target; do not delete, reset, or overwrite either project.
2. Take and verify a fresh target database dump plus Storage backup.
3. Record the exact cutover and freeze timestamps.
4. Diff source and target rows/objects created or updated since cutover; reconcile them into the chosen recovery project with an idempotent, reviewed script.
5. Configure the recovery project for production Clerk, functions, secrets, jobs, and Storage.
6. Run the complete hosted smoke suite and signed-in device tests.
7. Ship the rollback/recovery build through TestFlight/App Store. The embedded endpoint means existing installed clients do not switch instantly.
8. Reopen writes only after validation; retain both projects and all incident backups.

Never run `supabase db reset`, restore over the source project, delete a project, or overwrite Storage as an undo shortcut.
