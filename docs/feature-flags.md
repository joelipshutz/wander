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
   bundled default, and an integer range when applicable.
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
and reopen it. To stop testing a local value, choose Remote or use **Reset all to
remote values**, then fully quit and reopen again.
