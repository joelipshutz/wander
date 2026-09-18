# REC-542 Events launch interest

The Events screen's **Keep me posted** control saves an explicit request for Events launch updates. It does not enable OS notifications or change the existing notification preferences.

Production storage is `public.events_launch_interest`: one canonical profile ID (`user_id`, primary key) and the first confirmed opt-in time (`created_at`). Repeat taps preserve that time. Account deletion cascades; soft-deleted profiles cannot register or retrieve their state.

Authenticated clients use `own_events_launch_interest()` and `register_events_launch_interest()`. Both derive identity from the signed session. The roster has RLS enabled and no anonymous/authenticated table grants. The zero-argument definer RPCs have a pinned search path and authenticated-only execution grants.

Operations can retrieve the roster with an authorized database connection:

```sql
select interest.user_id, profile.handle, profile.display_name, interest.created_at
from public.events_launch_interest interest
join public.profiles profile on profile.id = interest.user_id
where profile.deleted_at is null
order by interest.created_at;
```

The client restores confirmation from the server, turns the button white only after a successful save, and keeps failed saves orange with a retry alert. Concurrent taps share a single in-flight write. Old-account completions and a stale initial read cannot overwrite a newer state.

## Hosted validation — September 18, 2026

- Verified isolated Astir project `rugmtlgufrhlxwfkumhw` using `supabase-astir`.
- Installed pinned smoke dependencies with `npm --prefix scripts ci --ignore-scripts`.
- Generated the full rollback-only linked suite using `scripts/supabase-smoke-test.mjs --migration-preview supabase/migrations/20260918094000_events_launch_interest.sql --write-linked-sql …` and executed it through the isolated launcher. Passed.
- Applied only `20260918094000_events_launch_interest.sql` plus its migration-ledger entry in one transaction. This targeted application avoided unrelated historical local/hosted migration-ledger discrepancies.
- Verified exactly one migration-ledger entry, RLS enabled, authenticated execution allowed, anonymous execution denied, and zero remaining smoke opt-ins. Refreshed the PostgREST schema cache.
- Executed the full rollback-only linked suite again against the deployed schema. Passed. The new SQL regression covers first registration, repeat registration, canonical identity, owner-only hydration, blocked raw roster access/writes, missing/deleted profiles, missing identity, anonymous access, RLS and RPC metadata.
- Corrected an existing smoke-runner role leak before the Repeat Wanna fixture setup; it previously attempted fixture inserts as `authenticated`.

Native tests and visual acceptance are still pending; this document is not a simulator sign-off. Swift parsing and `git diff --check` passed. The final full unit + Events UI test command was attempted through `.tools/ios-work.py`, which refused to start at 49.4 GiB free (50 GiB minimum). Approved helper cleanup found 0 eligible bytes. Automatic approval review rejected manual clearing of this task's Build/Index cache under the weekly-cleanup rule; a scoped user approval is pending.

The recording's right-hand simulator confirmed a real dark/light regression. The first root-owned material attempt still rendered light-mode inactive icons white over gray glass. Setting the native bar's background effect also failed direct visual inspection. The current unverified repair places one stable thin material behind the native bar in its parent, follows the window appearance and native bar visibility/geometry, and retains native controls. It must pass both tap and long-press/scrub transitions, live light/dark changes, Profile navigation, and large/compact layout checks before merge.

Worktree: `wander-events-vhs`; branch: `codex/rec-542-translucent-tabs`; draft PR: #669. Resume with the full `WanderTests` suite plus `WanderUITests/EventsComingSoonUITests` on iPhone 17 Pro Max `26F9BBC5-6855-4F6C-87D4-6C46041A2272`, then the Events suite on the existing compact iPhone 16e. Recheck available/owned simulators first; other tasks are active. The large simulator was shut down after a stalled test runner and is safe to boot for this task. No device data was erased.
