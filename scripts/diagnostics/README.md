# REC-636 diagnostic branch

This disposable branch observes the ten failed native executions on candidate
`22e7c6d9efd4ac0957ed25cd60e8cc26a05bc7f7`. It is not a release candidate or a
replacement for the failed result bundles. Do not merge its instrumentation.

The existing App Clip workflow keeps its complete regression jobs by default.
Only a manual dispatch with `observed_diagnostics=true` selects these two jobs:

- **Replay:** verify the pinned PostHog 3.61.0 revision and source hashes, apply
  the two additive patches in a job-owned package checkout, build once, and run
  the original private Replay case once. The 30-second gates, public markers,
  private masking assertions and SDK capture cadence remain unchanged. Bounded
  scalar stage observations separate draw, image creation, queue, mask, WebP,
  event construction and callback work. No alternative ready fixture is used.
- **Native inputs:** use the canonical, unmodified SDK. Build once, then run
  selected-pan, drawer, combined filters, Search, warm source switching and film
  autoplay once each on the large phone. Run drawer, combined filters and Search
  once each on the compact phone. Each invocation retains its own result and
  copies only the three explicitly named synthetic-fixture trace files after
  input ends. A failed case does not suppress the other distinct selections.

Both jobs require Xcode 26.6 / 17F113 and iOS 26.5 / 23F77. They use existing
simulators and do not reproduce the preceding full shard/unit sequence from the
failed CI jobs. No device erasure, real account, preference reset, retry or
threshold change is part of this experiment.

The native recipient recorder is enabled only by an explicit DEBUG simulator
argument together with the existing synthetic fixture arguments. Its observer
never recognizes, prevents or delays a gesture. It records UIKit's actual
`UITouch.view` ancestry and public gesture states without performing another
hit test. Map inventory is bounded and cached between touch starts. Fixed app
stage timestamps identify Search routing and map-source selection. The
onboarding recorder observes reading timers, animation completions and account
presentation without driving those transitions.

Tracing adds overhead. The asynchronous writers can lose their final pending
snapshot when a process exits; missing, stale, truncated or incomplete data is
an observation gap. A diagnostic pass alone does not explain or clear an
original failure. Keep native outcomes, trace completeness, exact source/device
identity and original screenshots separate when interpreting a result.

`source-proof.json` binds the SDK and Replay test patches to canonical source
hashes. Removing their marked diagnostic blocks restores those files exactly.
The UI instrumentation has equivalent source-strip proofs in the issue's
durable evidence directory. The reviewed production branch remains separate.
