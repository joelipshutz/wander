# Signup notifications

REC-561 streams new Astir accounts to private `#signups` in the existing rec.me
Slack workspace (`T0B9DS16JS2`, channel `C0C40Q02EHW`). Example:

```text
John Smith signed up
Email: john@example.test
```

The existing signature-verified Clerk profile webhook records `user.created`.
A database trigger queues future creation events once per canonical profile.
No existing accounts are backfilled. Profile updates and sign-ins do not queue
messages. The cron worker runs every minute, claiming up to five accounts per
invocation, resolving canonical identity mappings, and looking up the production
Clerk account. It requires production account creation time to match the event,
so development events cannot announce an old linked production account.

The displayed name is the latest Clerk first/last name, falling back to the Astir
profile name, then username. Only the verified primary email is displayed. Apple
Hide My Email uses the relay address supplied by Apple. Missing email is shown
as `Not provided`. Customer text is literal Slack text and cannot create mentions.
Emails and names are not persisted in the outbox or written to worker logs.

## Configuration

Use the isolated Astir Supabase launcher. Deploy migration
`20260920170000_signup_slack_delivery.sql` and `signup-slack-worker`. Required
Edge secrets (private registry references, never committed values):

- `ASTIR_SIGNUP_SLACK_WEBHOOK_URL`: incoming webhook restricted to `#signups`.
- `ASTIR_SIGNUP_SLACK_WORKER_SECRET`: dedicated random worker credential.
- `ASTIR_SIGNUP_CLERK_SECRET_KEY`: existing Astir production Clerk secret key.

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided by the Edge runtime.
Vault must contain `recme_project_url` and `astir_signup_slack_worker_secret`.
The schedule is inert until the dedicated Vault credential is configured.
The new webhook can use the existing Astir Feedback Slack app; the message
itself clearly identifies a signup. Its feedback webhook stays separate.

## Validation and operations

Run `node --test supabase/functions/signup-slack-worker/handler.test.mjs` and
the transaction-rolled-back `supabase/tests/signup_slack_delivery.sql`.
For hosted checks, use `supabase-astir db query --file <sql-path>`.
Verify end-to-end with a clearly labeled fictional signup notification.

Query only aggregate delivery state for routine health checks:

```sql
select status, count(*) from public.signup_slack_deliveries group by status;
```

Delivery retries use exponential backoff, stop after twelve attempts, and use
claim tokens plus five-minute leases to prevent concurrent sends. `failed`
requires operator review. `skipped` means the account was deleted, could not be
found in production after a mapping grace period, or its creation time did not
match. Webhook replay normally cannot create a duplicate notification. Incoming
Slack webhooks have no idempotency key: a timeout after Slack accepts a message,
or a database outage before acknowledgment, can still produce a duplicate on
retry. Do not represent delivery as mathematically exactly-once.

To pause delivery, unschedule `astir-signup-slack-worker`; account creation and
outbox queuing continue. Fix configuration and restore the minute schedule to
resume. Never retarget or rotate the independent feedback webhook.
