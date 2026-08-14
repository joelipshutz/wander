# rec.me App Review account — lossless setup

Updated: 2026-08-14

This runbook creates a dedicated fictional production account for Apple App Review. It is additive: it must not migrate, merge, delete, unlink, rename, or change credentials for any existing rec.me account.

## Stop conditions

Stop before any mutation unless all of these are true:

- The selected Clerk application is the verified rec.me **production** instance, not the development instance at `growing-pheasant-22.clerk.accounts.dev` and not another Grayline product.
- The pre-cutover backup at `/Users/joelipshutz/.private_backups/recme/2026-08-14-pre-launch-cutover/` still exists and the six source users still match its canonical identity map.
- The Clerk and Supabase project identifiers match the production-cutover manifest.
- Password sign-in can be enabled alongside Apple, Google, and email-code sign-in. None of those existing strategies will be disabled or reconfigured.
- The proposed reviewer email is not attached to any existing Clerk user or Supabase profile.

If any identifier or user count differs, stop. Do not repair the mismatch by deleting, merging, or recreating users.

## Create the isolated account

1. Enable password sign-in in the verified production Clerk instance without changing the existing Apple, Google, or email-code strategies. Do not enable Clerk test mode.
2. Create one new reviewer-only user with a fictional identity and a unique address reserved for App Review.
3. Give that user a long random password. Store the email and password only in `/Users/joelipshutz/.openclaw/workspace/.env.keys` as `ASC_REVIEW_DEMO_ACCOUNT_NAME` and `ASC_REVIEW_DEMO_ACCOUNT_PASSWORD`; never commit them or print them in logs.
4. Confirm the reviewer user has its own new Clerk user ID and its own new Supabase profile. It must not reuse, replace, merge with, or alias one of the six existing identities.
5. Populate only fictional places, memories, comments, lists, and social connections. Do not copy private notes, coordinates, photos, email addresses, handles, or relationship data from real users.
6. Keep reviewer fixtures distinguishable by the dedicated reviewer user ID so they can be audited or removed later without targeting existing users.

## Clean-device acceptance test

Use the exact release candidate on a freshly erased simulator or a device with rec.me removed:

1. Open the signed-out flow and choose **Use a password**.
2. Enter the private reviewer credentials.
3. Confirm the app opens the populated fictional account without requesting an email code, phone code, client-trust verification, MFA, or access to an external inbox.
4. Verify Map, Feed, Search, Add, Lists, reporting, blocking, Settings, and the account-deletion entry point.
5. Sign out, relaunch, and sign in again with the same credentials.
6. Re-run the six-user identity audit and confirm their Clerk IDs, Supabase profile IDs, content ownership, and sign-in methods are unchanged.

Any extra verification step, empty graph, cross-account content, or identity drift is a blocker. Do not put credentials into App Store Connect until this test passes.

## App Store Connect handoff

After the clean-device test passes:

```bash
node scripts/app-store-review-release.mjs
node scripts/app-store-review-release.mjs --apply
```

The first command is the required redacted dry run. Apply only after verifying its resolved app/version and confirming the monitored review contact. Read the record back after apply; do not paste the password into a PR, Linear, Mission Control, Slack, or documentation.

## Rollback boundary

If the review account must be replaced, target only its exact new Clerk user ID and Supabase profile ID after exporting its fixture inventory. Never use an email-domain filter, wildcard, bulk user operation, database reset, or source-project migration as cleanup. Existing rec.me accounts and content remain out of scope.
