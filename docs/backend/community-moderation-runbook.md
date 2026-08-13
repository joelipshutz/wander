# Community moderation runbook

Last reviewed: 2026-08-13

Applies to: rec.me iOS user-generated profiles, place memories, activity, comments, user photos, and shared lists

## Launch contract

rec.me must not ship user-generated content without all of the following operating together:

- deterministic client and server text guards for obvious prohibited language;
- an in-app report action on every shared-content surface;
- the existing hard-block action, which removes blocked people from search, profiles, lists, activity, map results, and stale local views;
- a private, service-role-only moderation queue with immutable status history;
- a human owner who checks the queue and acts within the service levels below; and
- live Community Guidelines and Support links.

The public endpoints were verified to return HTTP 200 on 2026-08-13:

- `https://getrec.me/community`
- `https://getrec.me/support`
- `https://getrec.me/privacy`
- `https://getrec.me/terms`

The Support page publishes `support@getrec.me`. Before submission, the launch owner must send and receive a test message and confirm the mailbox is monitored during the coverage window.

The text guard is intentionally a narrow first pass. It does not replace human review, and image moderation is report-driven in this launch version.

## Ownership and coverage

Before App Review submission, record one named primary Safety Owner and one named backup in the private launch roster. Do not put personal contact information in this repository.

- Primary role: rec.me Safety Owner
- Backup role: on-duty rec.me release engineer
- Queue coverage: at least twice each business day and once each weekend day while external testing or App Review is active
- Escalation channel: the private Grayline incident channel; never copy report details, photos, notes, precise locations, email addresses, or other private content into Slack or Linear

If no named person is covering the queue, user-generated sharing must remain disabled and the App Store build must not be submitted.

## Service levels

| Priority | Examples | Acknowledge | Decide and act |
| --- | --- | ---: | ---: |
| Urgent | credible threats, sexual exploitation, immediate safety risk, doxxing or sensitive-location exposure | 4 hours | 24 hours |
| Normal | spam, harassment, hate or abuse, impersonation, other guideline violations | 1 business day | 2 business days |

`dangerous_content` and `sexual_content` enter the queue as `urgent`. The reviewer may raise any other report to urgent when the snapshot or pattern warrants it.

## Queue access

Only a trusted server-side or operator tool using the Supabase `service_role` may read or update `public.content_reports`. Authenticated app users can submit a report through `public.submit_content_report`; they cannot list reports, inspect snapshots, see the reporter, or read the audit trail.

The RPC deduplicates the same reporter, subject, and reason for 24 hours and rejects more than 30 accepted submissions from one reporter in an hour. Rate limiting protects the queue; it does not replace an abuse investigation when a repeated pattern is legitimate.

Never:

- expose the service-role key to the app or a browser;
- paste raw queue rows into tickets or chat;
- download reported photos to personal storage;
- contact the reported person before evidence is preserved; or
- reveal the reporter's identity to the reported person.

The standard queue order is urgent first, then oldest first:

```sql
select
  id,
  subject_kind,
  subject_id,
  reported_user_id,
  reason,
  status,
  priority,
  assigned_to,
  created_at
from public.content_reports
where status in ('queued', 'reviewing')
order by (priority = 'urgent') desc, created_at asc;
```

Open the private `content_snapshot` only when needed to make the decision. Use internal user IDs in operational notes.

## Review procedure

1. Claim the report by setting `assigned_to` to the operator's internal identifier and `status` to `reviewing`.
2. Check the captured snapshot first. If more context is necessary, inspect only the reported subject and closely related reports for the same person.
3. Check for duplicate or coordinated reports. A duplicate report is evidence, not an automatic violation.
4. Compare the content with the Community Guidelines. Consider context, severity, pattern, and the risk of continued exposure.
5. Take the narrowest action that protects people:
   - remove the specific content;
   - warn the account;
   - suspend the account;
   - remove the account; or
   - dismiss with `no_violation`.
6. Set `resolution_action`, add a concise non-PII `resolution_notes` summary, then move the report to `resolved` or `dismissed`.
7. Confirm the generated row in `moderation_report_events` records assignment and closure. Never edit or delete audit events.
8. When user communication is appropriate, send it through the support workflow. Do not identify the reporter.

Closing a report without `resolution_action` is rejected by the database.

## Action guidance

- `content_removed`: remove or tombstone the reported profile text, place memory, visit photo, comment, activity source, or list. Confirm the content is absent from fresh remote reads and any storage object is no longer served.
- `warning_issued`: use for a lower-severity first violation when content is removed and the person can safely remain in the community.
- `account_suspended`: disable sign-in and sharing for a defined investigation or cooling-off period. Confirm existing shared content is hidden where policy requires.
- `account_removed`: use for severe exploitation, credible threats, repeated serious abuse, or ban evasion. Follow the account-deletion and evidence-retention policy.
- `no_violation`: document why the reported content remains allowed; do not use it merely because context was inconvenient to inspect.

Blocking is an immediate user-controlled safety measure and does not resolve the report. A person can report first and then block from the confirmation screen.

## Emergencies and legal concerns

For credible imminent harm, exploitation of a minor, or a valid legal preservation request:

1. mark the report urgent and preserve the original snapshot and audit trail;
2. notify the Safety Owner immediately through the private incident channel;
3. restrict exposure while review proceeds when doing so is safe and lawful;
4. direct a reporting user facing immediate danger to local emergency services; and
5. do not promise law-enforcement contact, disclose private data, or make a legal determination without the authorized owner.

## Release verification

The migration is code-reviewed locally but must not be applied merely by merging the app PR. Before enabling the feature in a production build:

1. confirm the target Supabase project and take a schema backup;
2. apply `supabase/migrations/20260813010000_community_moderation.sql` through the approved release workflow;
3. verify the migration list and the security posture of `public.submit_content_report`;
4. run `node scripts/supabase-smoke-test.mjs` against the linked project after extending the smoke path for this RPC if needed;
5. submit a report from a non-production tester account and confirm it appears privately in the operator queue;
6. resolve that test report and confirm the audit events; and
7. confirm the named primary and backup are actively covering the queue.

If the migration cannot be applied or the queue cannot be staffed, do not ship the iOS reporting UI. The client must not imply that a report was accepted when there is no operating backend.

## Rollback

If submissions fail after release, preserve the queue and audit tables. Roll back the app exposure or disable user-generated sharing; do not drop moderation data. Fix forward with a reviewed migration. Content filtering triggers should remain active unless a replacement protection is already deployed.
