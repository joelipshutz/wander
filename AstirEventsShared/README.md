# Events contract v1

T01 implements the small Foundation-only package used by the future full app and
App Clip, and a matching TypeScript decoder in `events-web/src/events`. These are
contracts and client checks, not an Events backend, completed user journey, or
App Clip/provider proof. The package is deliberately not wired into the shipping
app yet; that membership and host integration belong to T03.

## Run

From the repository root, with Swift 6 and Node 24 available:

```sh
swift test --package-path AstirEventsShared
pnpm --dir events-web install --frozen-lockfile --ignore-scripts
pnpm --dir events-web typecheck
pnpm --dir events-web test:contracts
```

Both test suites consume `tests/fixtures/events/event-contracts.json`. These are
fictional deterministic response examples, not evidence of live identities or
an executed backend command. Valid/invalid examples include failed versus empty
lookup, explicit missing-name/current-phone proof, current and expired offers,
admission versus completion, deleted post, and independent exact-place rights.

## Host and server obligations

- Decode through `EventReadResponse.decode` / `decodeEventRead`, then deliver
  through the captured `EventRequestContext.accept` / `acceptResponse`. Replace
  the host's session epoch on account/session replacement, including sign-out
  then return to the same account. Fence refresh results and pending drafts too.
- Keep requests/operations scoped to the original account and event. A lost
  mutation result is `completion_unknown`; preserve the exact command and resolve
  it rather than create a second operation. The server scopes operation keys to
  verified actor + kind, and compares event/generation/payload fingerprints.
- Replays return the historical effect **and current authorized state**. An old
  confirmation may now be canceled; a completed post may now be deleted. Neither
  replay recreates it. Rebooking is a deliberate new generation with current rules.
- Runtime decoders reject unknown enum/rights values and unsupported major
  contract versions. Additive unknown object fields are discarded, including
  when re-encoding a decoded projection; they cannot automatically become UI or
  analytics fields. Missing `booking` is invalid; explicit null is a successful
  authenticated no-match. This client stripping does **not** excuse server leaks.
- Wire timestamps are UTC RFC3339 with 0–6 fractional digits. Preserve the raw
  value and compare integer microseconds for response consistency. The server's
  fresh clock after transaction locks remains the sole eligibility authority.
- Pages are bounded to 1–100 items; cursors are opaque and bind query/filter,
  account, stable sort and tie-breaker at the server. `has_more` agrees with cursor
  presence. A page does not authorize guest list access by itself.
- `permission_version` detects changes, not identity. Protected cache entries
  require account/event/current permission plus expiry/source version where
  applicable. Do not render cached private data after uncertain/denied refresh.
- Guest and Team admin APIs/projections are distinct. Current server membership
  authorizes one `team_admin` role. No URL, client role or installation hint proves
  membership or native entry. The native route helper only selects an affordance.
- Queue persistence precedes offline success UI. `durable_pending`, `syncing` or
  `unknown` never grants canonical admission/recap. An acknowledged result still
  requires current server admission. Provider acceptance similarly is not delivery.
- Analytics has a typed surface/action/outcome allowlist. No raw response,
  identifier, credential, feedback, phone, location or text can be forwarded.

The guest `EventView` contains event metadata and viewer-state projections, never
guest phones, private feedback or protected gallery/comment bytes. Approximate
home centers must be displaced by the server; coordinate-range validation cannot
prove anonymization. Exact-home access may arise from an independent place right,
so the client does not equate it to a confirmed booking.

T02 supplies schema/RLS/transactions and canonical history. T03–T06 supply real
provider/session/host continuity. Open policy groups in
`docs/designs/astir-events/engineering-open-decisions.md` remain unresolved; no
withdrawal, reentry, offer-cutoff, publication editor or privacy policy is selected
by these contracts. Operational enum/field names are v1 implementation choices.
