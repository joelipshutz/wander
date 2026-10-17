# REC-636 first-capture profile diagnostic

This disposable carrier starts from canonical review commit
`22e7c6d9efd4ac0957ed25cd60e8cc26a05bc7f7`. Its existing Privacy workflow is
manual-only. This six-path carrier, its workflow/tooling and marker-only
diagnostic blocks are not final production-review changes. The V44 branch and
its one private failure/one credential pass remain preserved separately.

The tracked Replay test retains V44's fixture-window hiding, ownership checks
and exact hidden/key-state restoration. Three additional marked blocks write
at most two 512-byte markers in the current test host's own standard temporary
directory, `REC636-FirstCaptureProfile/{ready-began,ready-ended}.json`. The five
fixed fields are schema, phase, own PID, monotonic uptime and wall-clock epoch.
All original assertions, both 30-second capture gates, fixture data and credential
method remain unchanged. Marker IO is diagnostic overhead inside the original
ready deadline; unavailable markers produce an explicit gap.

The ordinary application, checked-in project and clean canonical PostHog SDK
at `ee5b5705b0038f0c44646cde5fe972bb65387596` remain unchanged. The fixed 448
Swift, 150 build-input and 2 tooling maps update only Replay's source hash.
No SDK/host/CPU patch, root mode, codec, image resolution or queue QoS change is
applied. One fresh signed build produces the recorded product/configuration
identity used by the runner.

Only `ReplayMaskingTests/testPrivateMessageContentIsMaskedInActualReplayImage`
runs, once, through canonical `run-parent-regression.py` with its original 600/900-second
allowances. The credential method is not repeated. Before dispatch, the runner
verifies any installed app belongs to these CI-owned synthetic products and
removes only that app; no simulator/system/keychain reset is performed.

Exactly one installed-tool sample may start at ready-began +6 seconds, no later
than +8 seconds, after verifying the current own test-host PID and original gate.
It requests 5 seconds at 10 ms intervals with a 15-second sampler wall bound.
Missed timing, identity mismatch, denied access or incomplete output remains an
explicit sampling gap with no retry. Sampling may affect observed timing;
recorded gate/sample overlap determines which interval the profile represents.
The independent original native result is never promoted by a sampling result.

Unchecked raw sampler scratch is a fresh job-owned sibling outside every upload
path. Only the full curated static call tree, bounded scalar profile receipts,
and native/source/product/configuration evidence are retained. Original result
Info hashes, exact selector/device, modern reports, selected root/build/action
legacy issues and original attachments remain mandatory. Product identity is
recorded by source/product guards; archived binaries are not supplied.

After exports the runner prints one bounded authored JSON line prefixed
`REC636_FIRST_CAPTURE_PROFILE_V1`; the workflow validates the same fixed summary
before writing it to the GitHub job summary. It contains no raw sampler/header,
private content, command, environment or URL. Logs alone establish neither native
acceptance nor original pixels/artifact provenance. Historical failures and final
uninstrumented published-candidate CI remain separate gates; this single method
does not reproduce the prior full shard sequence or prove a unique cause.
