---
name: recme-linear-log-triage
description: |
  Conditional rec.me/Wander Linear issue evidence triage using PostHog,
  Supabase, and attached screenshots/logs. Use when logs or hosted data can
  materially reduce guesswork for auth, save/sync, visibility, backend, data,
  or timestamped tester reports.
triggers:
  - rec.me logs
  - wander logs
  - posthog triage
  - linear log triage
  - check logs for issue
  - auth sync issue
  - save sync issue
  - visibility bug
---

# rec.me Linear Log Triage

Use this skill to add evidence to a rec.me/Wander Linear issue when logs or
hosted data are likely to change the diagnosis. This skill is intentionally
conditional: do not run it for every issue.

## When To Use

Use this skill when at least one is true:

- The issue mentions auth, sign-in, Clerk, Supabase, RLS, RPCs, save/sync,
  local-only state, backfill, follows, social visibility, map/discover/profile
  data mismatch, missing saved places, or TestFlight/backend regressions.
- The issue has a useful timestamp, screenshot, Slack permalink, or tester
  comment such as "just happened", "right now", "after I saved", or "after I
  reopened".
- Joe or Ryan asks whether logs, PostHog, Supabase, or the database show what
  happened.
- A screenshot shows state that depends on remote data, auth state, user id,
  build number, map filters, or sync state.

Skip this skill when logs are unlikely to change the next action:

- Pure copy changes, static visual polish, obvious local SwiftUI layout bugs, or
  design preference feedback.
- A report with no actionable time window and no user/account clue, unless the
  issue is severe enough to justify asking for missing context.
- Implementation-only tasks where the bug is already reproduced locally and
  remote evidence would not alter the fix.

## Required Inputs

Collect as many of these as available from the Linear issue and attachments:

- Linear issue id, title, description, comments, labels, status, created time,
  and updated time.
- Tester identity. Prefer internal Clerk user id when available; otherwise use
  handle/display name only to resolve the profile in Supabase.
- Approximate event time. Default to issue creation time or the attached Slack
  message time when no better timestamp exists.
- Build number, device, and app surface if provided.
- Screenshot text and visible app state.
- Slack permalink content if attached to Linear.

Known tester handles to resolve first in hosted Supabase:

- Joe: `jolipshutz`
- Ryan: `ryan_lieblein`
- Demo account: `recme_demo`

Do not assume these ids are stable without checking `public.profiles`.

## Privacy Rules

- Never paste auth tokens, API keys, session JWTs, raw request headers, full
  private payloads, emails, or precise coordinates into Linear, Slack, or PRs.
- Prefer internal user ids, event names, timestamps, build numbers, enum values,
  sync states, counts, RPC names, HTTP status codes, and coarse error kinds.
- Place names can be mentioned only when the user already named the place in the
  issue or the diagnosis requires confirming a specific saved-place row. Do not
  paste notes or freeform user text unless Joe explicitly asks.
- Screenshots may contain private context. Summarize relevant UI state instead
  of copying all text.

## Evidence Workflow

1. Read the Linear issue and attachments first. Identify the exact question the
   evidence should answer.
2. Decide whether this skill is helpful. If not, say why and continue with the
   normal feedback workflow.
3. Resolve tester profiles in Supabase when the bug involves user/account data:
   - Query `public.profiles` by known handle/display name.
   - Summarize saved-place counts from `public.user_places`.
   - For social visibility bugs, query `public.follows` in both directions.
   - For specific places, join `public.user_places` to `public.places` by owner
     and `canonical_name ilike`.
4. Check PostHog only when the issue has an account clue and useful time window:
   - Use a narrow default window: issue time +/- 15 minutes.
   - Expand to +/- 60 minutes only if the first query has no events and the
     report is still actionable.
   - Prefer event names and properties from the app's non-PII diagnostics:
     `own_place_sync_attempted`, `own_place_sync_succeeded`,
     `own_place_sync_failed`, `own_place_sync_skipped`,
     `own_place_sync_batch_started`, `own_place_sync_batch_completed`,
     `own_place_sync_batch_skipped`, auth/session state logs if available,
     build/app version properties if present.
5. For Supabase RPC/security issues, verify hosted metadata directly:
   - Use `supabase migration list --linked`.
   - Use `supabase db query --linked` against `pg_proc`, `pg_namespace`, grants,
     or the relevant table rows.
   - For sensitive fixes, run a rollback-only smoke query when possible.
6. Compare evidence to the user's report. Separate facts from inferences.
7. Comment in Linear with the compact evidence report below.
8. If implementation follows, keep only the decision-relevant evidence and
   reproducible commands in Linear and the PR. Do not duplicate routine
   read-only checks in a repo-wide log.

## Useful Commands

Run from a linked rec.me/Wander worktree. If the worktree is not linked to
Supabase, copy ignored `supabase/.temp` metadata from a linked local worktree or
run the standard Supabase link flow. Never commit `supabase/.temp`.

Supabase profile/count summary:

```bash
npx supabase db query --linked -o json \
  "select p.id, p.handle, p.display_name, count(up.id) as saved_count
   from public.profiles p
   left join public.user_places up on up.user_id = p.id
   group by p.id, p.handle, p.display_name
   order by saved_count desc, p.handle nulls last;"
```

Supabase saved places for one profile:

```bash
npx supabase db query --linked -o json \
  "select pr.handle, pl.canonical_name, up.status, up.visibility,
          up.rating_score, up.created_at, up.updated_at
   from public.user_places up
   join public.profiles pr on pr.id = up.user_id
   join public.places pl on pl.id = up.place_id
   where up.user_id = '<clerk_user_id>'
   order by up.created_at desc;"
```

Supabase follow relationship:

```bash
npx supabase db query --linked -o json \
  "select follower_user_id, followed_user_id, source, created_at
   from public.follows
   where (follower_user_id = '<viewer_id>' and followed_user_id = '<owner_id>')
      or (follower_user_id = '<owner_id>' and followed_user_id = '<viewer_id>')
   order by created_at;"
```

PostHog event query template:

```bash
set -a
source /Users/joelipshutz/.openclaw/workspace/.env.keys
set +a

curl -sS "$WANDER_POSTHOG_HOST/api/projects/$POSTHOG_PROJECT_ID/query/" \
  -H "Authorization: Bearer $POSTHOG_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "query": {
      "kind": "HogQLQuery",
      "query": "select event, timestamp, distinct_id, properties from events where distinct_id = '\''<clerk_user_id>'\'' and timestamp >= toDateTime('\''<start_iso>'\'') and timestamp <= toDateTime('\''<end_iso>'\'') order by timestamp desc limit 100"
    }
  }'
```

Before using the PostHog template, confirm the env points at the rec.me/Wander
PostHog project. Do not reuse Coupley or other app tokens.

## Linear Evidence Comment Format

Use this format when evidence was checked:

```markdown
Evidence checked for <time window>:

- Reporter/account: <handle or internal id only>
- Build/device: <if known, otherwise "not provided">
- PostHog: <events found or "not checked because ...">
- Supabase: <profile/place/follow/RPC facts>
- Screenshot/log attachments: <relevant visible state>

Conclusion:
- Facts: <what the evidence directly proves>
- Inference: <likely cause, marked as inference>
- Missing: <exact missing context, if any>
- Next action: <fix path, repro ask, or no-op>
```

Keep the comment short. Link to the PR or follow-up issue if implementation is
opened from the evidence.

## Completion

This skill is complete when one of these is true:

- Linear has a comment with useful evidence and the next action is clear.
- You explicitly skipped log triage because it would not change the action.
- You identified missing context and asked for it in Linear or the current
  Codex thread.

Do not merge PRs, upload TestFlight builds, or move issues to `Done` from this
skill. Use `recme-pr-review-merge-release` for merge/release work.
