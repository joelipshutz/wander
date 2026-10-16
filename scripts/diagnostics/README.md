# REC-636 diagnostic branch

This disposable branch investigates failed native executions on candidate
`22e7c6d9efd4ac0957ed25cd60e8cc26a05bc7f7`. It is not a release candidate or a
replacement for the failed result bundles. Do not merge its instrumentation.

The App Clip workflow keeps its complete regression jobs by default. A manual
`observed_diagnostics=true` dispatch selects bounded diagnostics instead.
`replay_only=true` selects Replay; `native_followup=true` selects the four-case
UI follow-up without Replay. These runs never clear the original failures.

## Replay comparison

The Replay job verifies pinned PostHog 3.61.0 source, applies three additive
SDK, host and test patches, and builds once. It then executes the original
private Replay method once with the ordinary root and once with a dormant
root. Both use identical binaries and service initializers; only the fixed
launch-mode argument differs. The dormant root omits ordinary root mounting,
not all process or service work. Actual requested, enabled and mounted-root
observations must agree before comparing the arms.

The original public fixture, 30-second gates, private-image assertions,
resolution, SDK queue, codec configuration and capture cadence are unchanged.
Bounded scalar observations locate pipeline stages. One encoder-thread right
and at most two CPU queries measure the first C encoding interval: entry and
the first encoder end or original readiness checkpoint. Wall time, CPU time,
endpoint races and trace context must be interpreted together.

The runner verifies source and product hashes before and after both arms.
It restores the original test configuration byte-for-byte in finally paths.
Each arm starts with only this CI-owned synthetic app removed, after verifying
any installed app matches the current product. It does not erase the device
or reset keychain or system settings. This symmetric app reset can still leave
system-cache and execution-order differences between arms.

Each native result, selection, original attachment, issue summary and process
receipt is retained. A completed assertion failure allows the planned second
arm. A non-boundary metadata-export failure stays Unverified and retains other
available exports. Unknown native completion, infrastructure failure, identity
drift or a permission boundary stops the sequence. There are no retries.

## Native inputs

The native-input job uses the canonical SDK. Its full selection runs selected
pan, drawer, combined filters, Search, warm source switching and film autoplay
on the large phone, plus drawer, combined filters and Search on the compact
phone. The follow-up selects large combined filters and warm switching, and
compact drawer and combined filters, once each. Every selection retains its
own native result and the explicitly named synthetic-fixture traces.

The recorder requires an explicit DEBUG simulator argument and synthetic
fixture arguments. It observes actual touch recipients, gesture states, fixed
app transitions and bounded map-update stages. It does not drive app state or
recognize, delay or prevent a gesture. The follow-up uses one slower physical
pan and one accessibility snapshot per drawer predicate; original acceptance
assertions and deadlines remain intact.

Both jobs require Xcode 26.6 / 17F113 and iOS 26.5 / 23F77. They use existing
CI-owned simulators and do not reproduce the preceding full-shard sequence.
No real account, device erasure, activation or release is part of these runs.
Tracing adds overhead; missing or incomplete observations remain evidence gaps.

`source-proof.json` binds the SDK, app-root and Replay test patches to canonical
source hashes. Removing the marked blocks restores those files exactly.
The UI instrumentation has equivalent source-strip proofs in the issue's
durable evidence directory. The production review branch remains separate.
