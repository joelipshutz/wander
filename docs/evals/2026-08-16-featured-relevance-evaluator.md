# REC-225 Featured offline relevance gate

Status: **AWAITING DIRECTIONAL BLIND JUDGMENTS — COMMUNITY EVIDENCE INSUFFICIENT FOR PROMOTION**

Automated preflight on the first real snapshot found 90 eligible canonical
places, of which 84 are the viewer's own or trusted-network places and only six
(6.7%) are real community-only places. No actual sparse viewport returns a
network/community mix. The grader remains useful for comparing ordering and
the bounded place-semantic signal, but every policy is forced to `DEFER` until
the real corpus clears the community-evidence gate below.

This is the separate evaluation required by the REC-225 relevance architecture for Map Featured. The completed 12-query Search benchmark cannot answer whether a network-first map should backfill from the wider community, whether the blend should change with viewport density, or whether pins stay useful and stable while panning.

## What is being compared

| Policy | Purpose |
|---|---|
| Shipped Featured baseline | Reproduce the current relationship + taste + support + rating ordering. |
| Trusted network only | Measure the value and failure mode of refusing wider-community backfill. |
| Fixed blend | Test one network/community mixture regardless of local density. |
| Density-aware blend | Continuously move weight from network to anonymous community evidence as trusted viewport confidence falls. |
| Density-aware + place semantics | Add a bounded candidate/ranking signal from canonical-place similarity to the viewer's explicit positive/Wanna taste profile. |

The experiment does not include an LLM ranker or learned people vectors. The LLM has no role because Featured has no text query. Graph relationships and explicit taste remain inspectable inputs; the semantic experiment embeds places, not people.

## Real scenario construction

The generator requires an explicit real viewer handle. It reads in one hosted read-only transaction and derives:

- privacy-eligible Been/check-in candidates inside real mapped areas;
- the viewer's own positive ratings and Wanna saves as the taste profile;
- opaque trusted-contributor membership for network density and diversity;
- anonymous place-level community support, aggregate rating, and recency;
- dense real-network viewports and at least one genuinely sparse real viewport;
- when a second genuine sparse viewport does not exist, one explicitly marked
  simulated-thin relationship mask over a real viewport rather than a dense
  viewport mislabeled as sparse;
- simulated empty-network and cold-start variants over the same real eligible place corpus; and
- an overlapping viewport pair for small-pan stability.

The blind page exposes place name, category, and coarse area so the judge can assess usefulness. It hides policy order, source membership, network density, contributor identity, and rank provenance.

Generation fails closed through an automated preflight. Every dense/sparse
label is checked against the confidence calculated from all candidates actually
inside that viewport, rather than the locality bucket that proposed the
viewport. The preflight also requires complete top-five judgment coverage,
policy ordering separation, at least one sparse mixed-source result, complete
pan pairs, zero privacy/duplicate failures, and ranking p95 below 50 ms. It
reports real community-only corpus coverage separately so simulated thin/empty
slices cannot be mistaken for organic network/community evidence.

## Data boundary

- The hosted transaction is read-only and always rolls back.
- Blocks, deleted rows, status, visibility, and private-profile eligibility are applied before candidates are aggregated.
- Named/full evidence is not part of the judgment model. Non-followed saves contribute only anonymous canonical-place aggregates.
- Stranger identity, notes, free-text answers, personal labels, photos, addresses,
  emails, and other save content are not selected into the local candidate
  model or sent to the embedding provider. Featured place vectors contain only
  reusable canonical facts: name, category, subcategory, and coarse
  locality/region. The viewer's approved structured tags remain in the explicit
  local taste scorer; they do not make the place vector viewer-specific.
- Coordinates remain local for viewport membership, pan overlap, and geographic-dispersion metrics. They are not embedded.
- Tracked files contain the evaluator and sanitized methodology only. Viewer-specific keys, embeddings, rankings, and judgments stay ignored local artifacts.

## Metrics

Judged top-five metrics:

- nDCG@5;
- ideal result at rank one;
- useful top-five slots, where grades 2–3 are useful; and
- wrong-result rate, where grade 0 is wrong.

Full bounded-output guardrails:

- network/community source share at 24;
- distinct trusted contributors at 24;
- geographic pair-distance dispersion at 24;
- duplicate and privacy/filter failures;
- top-10 overlap across the small pan; and
- local ranking p95 over five warmups and 30 measured runs per scenario.

Offline latency excludes network transport and SwiftUI/MapKit rendering. Any implementation trial must add RPC p50/p95, cancellation, stale-result, and pin-swap observability before rollout.

## Promotion rule locked before grading

A density-aware policy earns a bounded implementation trial only when all are true:

1. The snapshot has at least 20 real community-only canonical places, they are
   at least 20% of the eligible corpus, and at least one actual sparse viewport
   returns a real network/community mix. Simulated thin/empty slices cannot
   satisfy this evidence-readiness gate.
2. Zero privacy or hard-filter failures.
3. Zero duplicate canonical-place failures.
4. Local ranking p95 remains below 50 ms.
5. Sparse + empty + cold-start nDCG@5 improves by at least 0.05 over the shipped baseline.
6. Dense-network nDCG@5 regresses by no more than 0.02.
7. Top-10 overlap across the small pan regresses by no more than 0.10.

The place-semantic policy must independently clear the same incremental quality and stability thresholds over the density-aware policy. A pass approves only a feature-flagged provider/policy implementation and another evaluation round. It does not approve fixed weights, people embeddings, an LLM ranker, schema deployment, or a TestFlight release.

## Runbook

```bash
npm --prefix scripts ci --ignore-scripts
npm --prefix scripts run test:relevance
npm --prefix scripts run relevance:prepare-featured-real -- \
  --viewer-handle <your-recme-handle>
npm --prefix scripts run relevance:preflight-featured-real -- \
  scripts/relevance-lab/output/featured-pool-key.json
```

After all blind grades are copied into `scripts/relevance-lab/output/featured-scores.txt`:

```bash
npm --prefix scripts run relevance:score-featured-real -- \
  --key scripts/relevance-lab/output/featured-pool-key.json \
  --scores scripts/relevance-lab/output/featured-scores.txt \
  --write-report scripts/relevance-lab/output/featured-scorecard.md \
  --write-json scripts/relevance-lab/output/featured-scorecard.json
```

The scored result must replace the status at the top of this document and be summarized in `docs/decisions.md`, `docs/agent-log.md`, PR #427, and REC-225 before any product implementation begins.
