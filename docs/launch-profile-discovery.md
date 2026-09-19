# Launch profile discovery

REC-548 adds administrator-owned controls in `app.profile_discovery_settings`.
The profile IDs were checked against the Astir database on September 19, 2026.
The table is separate from self-editable profiles. Signed-in clients can read
the ranking fields for the invoker RPC but cannot change them; anonymous access
is denied. Use an authorized administrator or service-role process for changes.

## Behavior

- New profile inserts follow the two configured founder profiles once. Existing
  accounts are not backfilled. Webhook upserts, login, profile updates and
  onboarding completion do not reapply defaults after a manual unfollow.
- Default targets must exist, be active/public, not be excluded, and not be
  blocked in either direction. Self follows are excluded. An absent target is
  skipped instead of creating a substitute account.
- Automatic edges have source `signup_default`. They do not emit follow push or
  inbox notifications, and they do not emit the client `follow_created`
  engagement event. Manual follow behavior is unchanged. Existing clients
  already fall back to the ordinary profile source for unknown source values.
- Suggestion priority applies before the existing graph ranking, after normal
  eligibility checks. It never overrides privacy, blocks, self exclusion or an
  existing follow. Relationship explanations remain based on actual graph data.
- Hiding an account excludes it from this recommendation RPC, used by Feed and
  onboarding. It does not delete anything, change sign-in, alter search/profile
  access, remove existing follows, or remove its content from other surfaces.
- The iOS change omits generic suggestion text; real follows-you and shared-follow
  copy stays unchanged. Older installed apps retain their existing generic copy.

## Initial configuration

| Purpose | Canonical profile ID |
| --- | --- |
| Default follow | `user_3EhATWssjvHxwGiUaoWR5VTgeoy` |
| Default follow | `user_3EsQ6OZGVoIBhjfDUUfDhpa0PLc` |
| First eligible suggestion | `user_3InBzTuUhmItvfKyvQJdoelfseQ` |

The migration hides seventeen verified test/review profiles by exact ID: the original
demo account, six profiles from `scripts/seed-discover-demo-people.sql`, the two
App Review friend fixtures, the previously verified dedicated review login,
and seven additional accounts Joe confirmed as tests on September 19, 2026.
It does not infer test status from a person's name, low activity, or an email
pattern. All seven candidates raised in this task are confirmed. No wildcard
rule automatically hides future real users.

## Reversible administration

Inspect the row before changing it and record the prior value in the task.
Hiding an additional verified test profile does not require a new app release:

```sql
insert into app.profile_discovery_settings(profile_id, hidden_from_suggestions)
values ('<verified-profile-id>', true)
on conflict(profile_id) do update set hidden_from_suggestions=true;
```

To show that account again, set `hidden_from_suggestions=false`. Set
`suggestion_priority=0` to stop prioritizing a profile. Set `follow_on_signup=false`
to stop future default follows. These configuration changes do not rewrite
existing follow edges. Any backfill or removal of existing follows is a separate
data operation that needs its own scope and validation.

## Validation and rollout

The rollback-only `supabase/tests/launch_profile_discovery.sql` suite exercises
authenticated profile creation, upsert retries, manual unfollows, notification
suppression and preservation, private/deleted/hidden targets, priority, forward
and reverse blocks, search preservation, reversibility, grants and search paths.
It is included in both transports of `scripts/supabase-smoke-test.mjs`.
Historical graph/feed suites explicitly isolate their fictional follow graphs
from production launch configuration.

Generate the full migration preview without loading credentials, then execute
it through the isolated Astir launcher:

```sh
node scripts/supabase-smoke-test.mjs \
  --migration-preview supabase/migrations/20260919160000_launch_profile_discovery.sql \
  --write-linked-sql /private/tmp/rec-548-full-smoke.sql
/Users/joelipshutz/.local/bin/supabase-astir db query \
  --workdir "$PWD" --file /private/tmp/rec-548-full-smoke.sql
```

Every preview/test transaction rolls back, including generated notifications.
Before rollout, finish native tests and compact/standard layout checks, reconcile
the target IDs and exclusions, review/apply only this migration, verify its
security metadata and repeat hosted smoke checks. The server controls work for
existing clients; generic-copy removal requires a later app build.
