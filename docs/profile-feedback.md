# Profile feedback

REC-545 adds an owner-profile ladybug button and native Feedback sheet. The prompt
is “Drop us a line” with “(feature request, bug, or tell us you love us)” beneath it.
Voice and Text tabs preserve their drafts when switching; Voice opens by default.
Voice has a large record/stop control, live audio-level waveform, timer, and
play/pause/resume/replay controls. Stop rewinds playback. Replacing a note requires
confirmation. Text contains the editor and Add photos. Checkmarks and inclusion
copy make it clear when both tabs have content; Submit includes both drafts.
A report can contain text, up to three photos, and one voice note up to three minutes. At
least one of those is required. Photos are downsampled to 2,000 pixels without
cropping and re-encoded without source metadata. Each attachment is capped at
2 MiB; text is capped at 5,000 characters. Microphone access is requested only
after Record is tapped. Switching tabs or leaving the foreground stops and saves
an active recording and pauses playback. Pending permission cannot start a hidden
recording after a tab switch or dismissal.

The entry point is gated by `profile_feedback_v1`, with its bundled default off.
The remote global row starts off and is enabled separately after server acceptance.
Ordinary Debug, Simulator, and release builds use the same registry.
Authorized testers can use the existing Feature flags Settings row and restart,
or use an account rollout after deployment. Isolated UI tests require both
`-WanderAuthenticatedUITest` and `-WanderFeedbackUITest` to show the entry point
with a fake repository. Keep the flag off until server acceptance below passes;
merging the code does not deploy the service, enable the button, or publish a new
app binary.

Submit reserves a private server draft, uploads its declared attachments, then
atomically finalizes the report in private server storage. Slack and optional
email have independent delivery queues; neither is required for successful receipt.
The UI celebrates server confirmation with the existing save confetti, respecting Reduce Motion.
The success state confirms team receipt in server storage; it does not claim
mailbox delivery. Unconfirmed submissions keep the same immutable payload and
UUID for Retry. The form blocks duplicate taps and asks before discarding a note.

## Data and delivery

- `public.app_feedback` stores content, canonical account ID, app/build, media
  manifest, timestamps and delivery status. RLS is on; clients have no table
  access. `begin_own_feedback` and `submit_own_feedback` derive identity from the
  authenticated session. No caller-supplied owner is accepted.
- `feedback-attachments` is private. An authenticated owner may upload only the
  draft's declared paths. Finalization checks byte counts and content types.
  Clients cannot read or overwrite submitted files. Existing account deletion
  inventory includes feedback attachments before profile cascade deletion.
- Admission is serialized per account and limited to five drafts per hour and
  twenty per day, including abandoned drafts. Retrying an existing UUID does not
  consume quota. Drafts remain private until account deletion; automatic age-based
  retention is not configured in this change.
- `feedback-email-worker` sends plain-text email to the fixed destination
  `admin@HotchkissTechnologies.com`, attaching JPEG and M4A files directly. It
  includes the canonical account ID and app/build for follow-up. It does not
  attach an address book, analytics payload, or other app data.
- Worker claims are service-only, lease-bound, and settled by claim token.
  Delivery failures back off; provider requests use `astir-feedback/<UUID>` as
  their idempotency key. After twelve attempts or the 23-hour ambiguity window,
  reports stay stored in `failed` for operator reconciliation. Never reset an
  ambiguous job after the provider's 24-hour deduplication window without checking
  provider delivery history first. Existing email copies live in the team mailbox.
- Only `feedback_submitted` with photo count and a voice-note Boolean reaches
  analytics. Text, attachments, filenames and email addresses are excluded.

## Server-first rollout and team inbox

Email is optional. First apply `20260919033000_profile_feedback.sql` to the
confirmed Astir project using the isolated launcher. Review migration history
before applying anything so unrelated migrations are not deployed accidentally.
Submit a fictional authenticated report with JPEG and three-minute AAC uploads.
Verify one finalized row, byte-identical private downloads with service access,
idempotent retry, and denied public reads and submitted-file replacement. Then
`profile_feedback_v1` can be enabled for the intended rollout independently of
Slack or email. The next explicitly requested app release must include the client.
Before that release, verify physical microphone recording and playback and confirm
App Store privacy disclosures include optional feedback audio and customer-support
content linked to the account for app functionality.

The team's immediate inbox is `public.app_feedback` in the authenticated
[Astir Supabase dashboard](https://supabase.com/dashboard/project/rugmtlgufrhlxwfkumhw/editor).
Filter `submitted_at` to non-null and sort newest first; rows with a null timestamp
are unfinished drafts. Open `feedback-attachments` in Storage and use the report
UUID as its folder. Access requires the existing project/team permissions.
`email_status=pending` means email is deferred, not that server receipt failed.
The report's canonical `user_id` links to `profiles` and
`clerk_identity_mappings` for contact lookup in Clerk.

### Optional Slack notifications

1. Apply `20260919101700_feedback_slack_delivery.sql`. It adds an independent,
   service-only queue and backfills submitted reports; it does not notify drafts.
2. Install the Astir Feedback app in the rec.me Slack workspace with only the
   `incoming-webhook` posting scope. Select the private `#app-feedback` channel.
   Record the exact app, workspace, channel and webhook in the Astir secret
   registry. Never paste a webhook into a ticket, source file, log or command.
3. Configure `ASTIR_FEEDBACK_SLACK_WEBHOOK_URL`,
   `ASTIR_FEEDBACK_CLERK_SECRET_KEY` (the existing Astir production Clerk key), and
   a new random `ASTIR_FEEDBACK_SLACK_WORKER_SECRET` in Edge secrets. Store that
   same worker secret in Vault as `astir_feedback_slack_worker_secret`; the cron
   uses the existing `recme_project_url`. Deploy `feedback-slack-worker` using its
   checked-in `verify_jwt=false`. The dedicated secret header remains mandatory.
   Missing configuration fails before claiming reports, and the scheduler is
   inert until its dedicated Vault secret exists.
4. Verify a fictional notification in the actual private channel, including
   contact identity, photo and playable voice links, and `status=sent` in
   `feedback_slack_deliveries`. Newly generated links expire in 30 days; previously
   posted links retain their original expiry. Originals remain private on the
   server. Anyone holding a signed link can use it until expiry; only invite
   teammates who should see feedback and contact data.

Notifications use bold literal rich-text elements for sender/contact details and
the available Feedback text, Feedback photo, and Feedback voice note sections.
Submitted uses Slack's readable local date/time, with an explicit UTC fallback.
User content cannot create Slack mentions or markup. Account/report/app metadata
remains available for support; the server inbox button and explanatory footer are
omitted. The attachment links themselves are generated only by the worker.

The worker resolves the canonical account through Clerk and includes its current
verified primary email and, when present, a verified primary phone number. It
excludes phone numbers reserved for two-factor authentication. Neither contact
method is guaranteed: missing contact details are explicit and the account ID is
always included. Slack replies are internal; use the listed address or number to
contact the sender. The app does not collect a new phone number for feedback.

Slack delivery is **at least once**. A timeout after Slack accepts a message, or
a lost database settlement, may produce a duplicate notification with the same
report ID. The stored report itself stays idempotent. Leases and exponential
backoff bound retries; after twelve attempts a failed queue row remains available
for operator reconciliation. This does not change the independent email state.
Private-channel copies remain in Slack under its workspace retention settings.

### Optional email delivery

Implementation does not provision an email account or verify a sender domain.
Email can be enabled later without changing how the app submits feedback:

1. Select the Astir-owned transactional-email account. This implementation uses
   the Resend HTTP API. Register the chosen identity and scoped credential in the
   cross-project secret registry. Verify its sending domain and sender address.
2. Apply `20260919033000_profile_feedback.sql` after review, using the isolated
   Astir Supabase launcher and the confirmed Astir project. Review the pending
   migration list first so unrelated migrations are not deployed accidentally.
3. Configure Edge secrets `ASTIR_FEEDBACK_RESEND_API_KEY`,
   `ASTIR_FEEDBACK_EMAIL_FROM`, and a dedicated random
   `ASTIR_FEEDBACK_WORKER_SECRET` through the approved private credential process.
   Put the same worker secret in Vault as `astir_feedback_worker_secret`; the
   scheduler uses the existing `recme_project_url`. Never put values in source,
   command-line arguments, PRs, or logs. The cron entry remains inert without its
   Vault configuration, and an unconfigured worker never claims reports.
4. Deploy `feedback-email-worker` with its checked-in `verify_jwt=false`; the
   dedicated secret header is required and checked before any work. This endpoint
   is for cron only. Built-in service credentials remain on the server.
5. Before enabling the email scheduler, review already queued reports: enabling
   it will deliver stored pending reports as well as new ones. Submit a fictional
   report with a photo and voice note from an authenticated
   test account. Verify one server row, private attachments, `email_status=sent`,
   actual receipt at the requested mailbox, playable audio, and retry behavior.
   Provider acceptance alone does not establish inbox delivery.
6. Confirm App Store privacy disclosures include optional feedback audio and
   customer-support content, linked to the account for app functionality. The
   app privacy manifest includes Audio Data and the microphone purpose string.
   Run the normal explicit app-release process to put the button in a binary.
7. Email receipt is an acceptance requirement for claiming email works; it does
   not gate the server-first feature rollout.

## Validation

Native tests cover empty/media-only input, limits, duplicate taps, unavailable
backend, frozen retries, exactly-once success analytics, upload/finalize ordering,
and preserving photo aspect ratio. UI tests capture the profile, form, keyboard,
confirmation, tab/draft preservation, playback, replacement, and discard flow
using a simulator-only fake. Native AVAudioPlayer tests verify pause/resume,
completion, replay, stop, and corrupt-data handling with generated silent audio.
The extra `-WanderFeedbackVoiceUITest` argument seeds silent PCM only for UI
playback coverage; it does not exercise microphone capture or M4A encoding.
The fake requires
both `-WanderAuthenticatedUITest` and `-WanderFeedbackUITest` and cannot be used in
a release build.

Run worker tests with a Node runtime that supports TypeScript type stripping:

```sh
node --test supabase/functions/feedback-email-worker/handler.test.mjs \
  supabase/functions/feedback-slack-worker/handler.test.mjs
```

The main `scripts/supabase-smoke-test.mjs` includes the feedback and Slack queue
security suites. Slack worker tests cover contact ownership, unverified/MFA-only
contact exclusion, private media signing, notification injection, missing
configuration, provider failures, and lost-settlement duplicate behavior.
Before deploying, generate a focused rollback-only preview without reading any
credentials, then execute that file using the isolated Astir launcher:

```sh
node scripts/supabase-smoke-test.mjs --write-linked-sql /tmp/feedback-smoke.sql \
  --migration-preview supabase/migrations/20260919033000_profile_feedback.sql \
  --migration-test supabase/tests/profile_feedback.sql
```

The focused SQL uses fictional accounts and rolls back schema, storage metadata,
outbox claims, and fixtures. It sends no emails and uploads no actual files.

Provider contract: [Resend send-email API](https://resend.com/docs/api-reference/emails/send-email)
and [24-hour idempotency keys](https://resend.com/docs/dashboard/emails/idempotency-keys).

Slack contract: [incoming webhooks](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks).
