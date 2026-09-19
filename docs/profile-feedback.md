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

The entry point is gated by `profile_feedback_v1`, with bundled and remote global
defaults off. Ordinary Debug, Simulator, and release builds use the same registry.
Authorized testers can use the existing Feature flags Settings row and restart,
or use an account rollout after deployment. Isolated UI tests require both
`-WanderAuthenticatedUITest` and `-WanderFeedbackUITest` to show the entry point
with a fake repository. Keep the flag off until the delivery acceptance below
passes; merging the code does not deploy the service or enable the button.

Submit reserves a private server draft, uploads its declared attachments, then
atomically finalizes the report into a durable email outbox. The UI celebrates
server confirmation with the existing save confetti, respecting Reduce Motion.
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

## Enable delivery

Implementation does not provision an email account or verify a sender domain.
Before launch:

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
5. Submit a fictional report with a photo and voice note from an authenticated
   test account. Verify one server row, private attachments, `email_status=sent`,
   actual receipt at the requested mailbox, playable audio, and retry behavior.
   Provider acceptance alone does not establish inbox delivery.
6. Confirm App Store privacy disclosures include optional feedback audio and
   customer-support content, linked to the account for app functionality. The
   app privacy manifest includes Audio Data and the microphone purpose string.
   Run the normal explicit app-release process to put the button in a binary.
7. Enable `profile_feedback_v1` for the intended rollout only after these checks.

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
node --test supabase/functions/feedback-email-worker/handler.test.mjs
```

The main `scripts/supabase-smoke-test.mjs` includes the feedback security suite.
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
