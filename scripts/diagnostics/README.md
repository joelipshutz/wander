# REC-636 canonical Replay fixture-window validation

This disposable carrier starts at canonical review commit
`22e7c6d9efd4ac0957ed25cd60e8cc26a05bc7f7`. It changes only the tracked Replay
test, this README, the runner/source proof and the existing Privacy workflow.
The branch-only Privacy replacement is manual-only so GitHub can dispatch an
existing workflow file. Never merge this carrier workflow or tooling into the
production review branch. App Clip's existing workflow remains byte-identical.

Both original Replay methods temporarily hide only the original host window
while their genuine native fixture is presented. Each snapshots its prior
hidden/key state, asserts fixture ownership and original-window hiding, and
uses defer to restore and assert the exact original hidden/key state on test
unwind. All original behavior/privacy assertions and capture deadlines remain.
Hiding a window does not establish that its tasks, video or all host work stop.
No production app, SDK source, host mode, queue QoS, image resolution or codec
quality is changed. The carrier contains no SDK/host/CPU diagnostic patch.

The workflow verifies committed and working test source `9cdf8c12…` against the
canonical `e20df909…` base. It does not apply a patch at runtime. The fixed
448 Swift,150 public build inputs and2 tooling maps retain the canonical
application/project/scheme bytes; only Replay's mapped hash changes. The
job-owned PostHog checkout must be clean at revision
`ee5b5705b0038f0c44646cde5fe972bb65387596`, with its five canonical source rows
and ordinary host `57c1964e…` checked before and after execution.

One fresh build uses the checked-in project because membership is unchanged.
The bounded runner then selects exactly the original private-message method
and credential method, once each in distinct test processes/results on the
admitted iPhone17Pro/iOS26.5. It uses the same signed products and unmodified
test configuration, canonical run-parent-regression.py and original600/900s
execution allowances. No root-mode argument is set. Before each invocation it
verifies any installed app matches this job's product, then removes only that
CI-owned synthetic app; it does not erase the simulator or reset system/keychain
state. Private-then-credentials order and persistent system state remain limits.

Each native exit, exact selector, device, complete modern/selected legacy
issues, original attachments, Info hash and source/product/configuration guard
receipt is retained. An accounted assertion failure preserves Failed and may
continue the already-planned second method. An ancillary export gap remains
Unverified; available contradictory reports still stop. Unknown completion,
crash/infrastructure, source identity drift or a permission boundary stops.
No rerun or fallback is automatic. Original screenshots require actual pixel
review; green counts alone are insufficient.

V43's valid ordered normal/dormant diagnostic pair remains1Passed/1Failed.
Its root association and worker CPU observations did not establish a unique
cause or an SDK repair. This canonical two-method trial likewise cannot clear
historical failures or replace final uninstrumented published-candidate CI,
ordinary auth, warning disposition and artifact/provenance acceptance. The
full previous shard sequence and real-account behavior are not reproduced.
