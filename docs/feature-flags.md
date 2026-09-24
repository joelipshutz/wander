# Feature flags

rec.me has one feature-flag platform for remote rollout and on-device testing.
Boolean and integer flags use the same registry, resolution path, Settings UI,
and restart behavior.

## Runtime contract

Resolution order is:

1. device override captured when the app process launched;
2. current account's remote override, when the flag permits one;
3. remote global value;
4. bundled fail-closed default after remote resolution finishes or fails.

Settings writes the desired value for the next process. It never mutates the
launch snapshot. Fully quit and reopen rec.me after changing or clearing an
override. Resetting an override selects the remote value on the next launch.

Overrides are scoped to the signed-in account and stored only on that device.
They are not uploaded. Debug Settings access is visible in the registry but is
read-only on-device because it gates access to the control panel itself.

## “Put this behind a flag” checklist

When Joe or Ryan says **put this behind a flag**, the implementation is not
complete until all of these land together:

1. Add a `FeatureFlagKey` case and its complete `FeatureFlagDefinition` in
   `Wander/App/FeatureFlags.swift`. Choose Boolean or integer, a fail-closed
   bundled default, and a bounded range for every integer flag.
2. Add or update the Supabase migration. The hosted `feature_flags` key check
   must list the key, and a global row must exist. A remote-only key is invalid.
3. Read the value through `WanderBackend.featureFlag`,
   `integerFeatureFlag`, or `resolvedFeatureFlag`. Feature code must not read
   `UserDefaults`, Supabase, build configuration, or a one-off preference helper.
4. Do not force-enable the feature merely because the app is a Debug or
   Simulator build. An explicit launch argument may exist for isolated UI
   automation, but ordinary developer and TestFlight runs use the registry.
5. Verify the automatically generated Settings row supports Remote/On/Off or
   a bounded integer override, shows the active source, and displays the restart
   requirement after a change.
6. Add tests for the consumer behavior and update the registry, remote decoding,
   persistence/restart, Settings completeness, and SQL contract tests as needed.

`FeatureFlagKey.allCases` drives both the remote query and the Settings list.
Never add a separate flag toggle or an unregistered hosted row.

## Tester workflow

Open Profile → Settings → Feature flags. Choose Remote, On, Off, or an integer
value. When the restart message appears, fully quit rec.me from the app switcher
and reopen it. To stop testing local values, choose Remote for one flag or use
**Reset all to defaults** for every flag, then fully quit and reopen again. This
clears device overrides, so each flag resolves from its remote value or bundled
fallback on the next launch.

## Remote notification re-prompts

`notification_reprompt_campaign` is an integer control, from 0 through 1,000,000.
0 disables requests. Set a new, higher positive campaign number to re-prompt
notification-disabled users at their next authenticated app open or foreground.
Remote values refresh at those boundaries; this does not wake a closed app or
interrupt users immediately while they remain in an active session.

The global row targets everyone eligible. An account row targets that user and
takes precedence over the global row; an account override of 0 excludes that
account. Device test overrides retain the platform's next-launch precedence.
Use increasing campaign numbers across global and account targeting. Reusing or
lowering a number does not re-prompt an account that already saw that version or
a newer one. Record the last issued version in the campaign's operations ticket,
including when setting a global or account row back to 0.

Example operator SQL, after the migration and supporting app build are deployed:

```sql
-- Target a specific account. Replace the user id and campaign number deliberately.
insert into public.feature_flags(key, user_id, enabled, value_type, integer_value)
values ('notification_reprompt_campaign', 'user_target', false, 'integer', 1)
on conflict (key, user_id) where user_id is not null
do update set value_type = excluded.value_type, integer_value = excluded.integer_value;

-- Or target everyone eligible with a fresh campaign number.
update public.feature_flags set integer_value = 2
where key = 'notification_reprompt_campaign' and user_id is null;

-- Stop further global requests; existing per-account overrides still take precedence.
update public.feature_flags set integer_value = 0
where key = 'notification_reprompt_campaign' and user_id is null;
```

The app records exposure only when the primer becomes visible, once per campaign
per account **on that device**. The record survives app relaunch, but is not a
server receipt and does not deduplicate across devices or a fresh installation.
An already visible notification primer satisfies the current campaign without
stacking another dialog. Blocked requests are reconciled from the current flag
after the competing UI clears; disabling a campaign leaves no obsolete queued
prompt. On each main-app visit, remote presentation waits for that account’s feature-flag refresh to finish so a cached campaign cannot outrun a newly fetched off value. Automatic reminders do not wait for remote campaign loading. Remote impressions use a separate campaign counter and do not consume
or depend on the three automatic return reminders or the onboarding allowance.
Automatic reminders appear on the first three eligible main-app visits,
including an existing user’s first visit after updating, replacing the save/follow
triggers. Completing the onboarding prompt satisfies that visit, so a second
prompt does not stack immediately afterward. Blocked opens defer the opportunity
without consuming a reminder. Both cold launches
and returns from the background count, while permission-alert interruptions do
not. The sequence starts on first use of the supporting build and persists per
account/device. A primer already shown in the current open prevents another
automatic or remote primer immediately after dismissal; a newly arriving remote
campaign waits for the next open if that open already showed a primer.

The current account's notification preferences and iOS permission must still
indicate notifications are off. Normal presentation blockers apply. A previously
denied iOS permission offers Open Settings and Not now; the app cannot force
Apple's permission alert to appear again. Creating the dormant control does not
authorize activating a live campaign.

### Test one account, then roll out the same campaign

After the supporting app and migration ship, keep the global value at 0 and
set only the test account's override to a fresh campaign number (1 for the
first campaign). The account must have notifications disabled and device test
overrides reset to **Follow remote**. Reopen or foreground the app after
onboarding; the new example-notification dialog appears once when presentation
blockers clear. Use a higher campaign number for each additional test.

Once that test is accepted, promote the same tested number globally and remove
only that account's temporary override in one transaction. For a first campaign:

```sql
begin;
update public.feature_flags set integer_value = 1
where key = 'notification_reprompt_campaign' and user_id is null;

delete from public.feature_flags
where key = 'notification_reprompt_campaign' and user_id = 'user_target';
commit;
```

Other eligible accounts see that campaign on their next open. The test account
does not see it again on the same installation, because its last-seen version
already matches. Removing the temporary override lets that account follow
later global campaigns; preserve any other accounts' intentional overrides or
exclusions. Set the global value back to 0 to stop new global requests, and
clear any positive account overrides separately when stopping targeted tests.
For another round, use a number higher than every previously issued test or
global campaign. Turning 1 off and back on does not replay campaign 1.

Each actual presentation records `product_upsell_shown` with campaign, trigger,
and impression number; taps and outcomes share its `presentation_id`. The
Notification Operations dashboard includes raw presentation counts and button
conversion. Staff/test traffic is excluded from production rates, so inspect
the test account's raw events when validating a release build. Counts and
last-seen campaign versions persist per account/device and reset on reinstall.
The same redesigned component replaces the former bell-style prompt in
onboarding, return reminders, and remote campaigns; the former automatic
save/follow prompts are no longer consumed, and reminders cannot stack during
one app open.
