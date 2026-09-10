# Featured relevance scorecard — 2026-08-16

## Decision

**Retain the current explicit Featured baseline. Defer the proposed
density-aware blend and the place-semantic Featured provider.**

This decision is specific to queryless Featured. It does not revoke the
separately validated semantic candidate provider for conversational/text Search.

## Blind result

One viewer graded candidates for personal usefulness in each map area without
seeing policy or source provenance. The run captured 65 numeric judgments and
one explicit unknown. Eight of nine scenarios were scoreable; the incomplete
actual-sparse scenario was excluded rather than treating unfamiliarity as
irrelevance.

| Policy | nDCG@5 | Ideal at #1 | Useful top 5 |
|---|---:|---:|---:|
| Current explicit baseline | **82.9%** | **100.0%** | **92.5%** |
| Trusted network only | 49.5% | 62.5% | 52.5% |
| Fixed network/community blend | 77.1% | 62.5% | 90.0% |
| Density-aware blend | 79.5% | 62.5% | 90.0% |
| Density-aware + place semantics | 73.0% | 62.5% | 85.0% |

Density-aware ranking regressed the baseline by 3.2 nDCG points on the
scoreable sparse/empty/cold-start aggregate and 2.4 points on dense scenarios.
Adding place semantics regressed density-aware by another 2.5 and 11.8 points
respectively. Every policy had 100% top-10 overlap across the small pan. Local
ranking p95 was 0.61 ms, with zero privacy failures and zero ID-level duplicate
failures in the original key.

## What the result means

- Network-only is not a viable product policy. It loses almost half the useful
  top-five coverage and returns nothing in empty-network or cold-start modes.
- The current explicit relationship, structured taste, aggregate support/rating,
  and recency score is the best tested Featured ranker for this corpus.
- A vector's broad semantic similarity to a viewer taste centroid is too blunt
  for queryless Featured. It moved personally weaker places upward, especially
  in dense areas.
- The provider/ranker architecture is still correct: Featured and Search share
  hard filters, candidate interfaces, canonical place projections, explicit
  graph/taste features, bounded ranking, and evaluation, while using different
  versioned policies.
- The personal-versus-best dial remains an explicit ranker control. This run
  says not to replace it with vector similarity or automatically calibrate its
  weights from the current small corpus.

## Why this is `DEFER`, not a final calibration

The eligible snapshot had only six real community-only places (6.7%) and no
actual sparse viewport containing both network and community candidates. It
missed the locked minimum of 20 community-only places, 20% corpus share, and
one actual sparse mixed-source viewport. Most judgments were 2 or 3, with no
zeros, so this pool measured ordering among plausible places better than bad
candidate rejection.

The human grading pass also exposed two evaluator limits:

1. One unknown candidate made the only actual-sparse scenario unscoreable.
   Unknown is now represented as `X`; the scenario is excluded and policy
   promotion remains blocked.
2. One place appeared under conflicting provider identities despite sharing a
   name and coordinate. The evaluator now matches the app's physical-place
   behavior by grouping same-name records in the same nearby-coordinate bucket
   before contributor aggregation. A same-name trail also appeared at two
   materially different coordinates and remains distinct pending stronger
   physical-place identity data.

## Production direction

1. Keep the current Featured policy and the shared deterministic retrieval
   platform.
2. Keep anonymous wider-community fallback; do not ship network-only.
3. Keep place vectors feature-flagged for text Search, not Featured.
4. Do not add people embeddings.
5. Rerun Featured only after the real community corpus and judge coverage meet
   the locked gate, ideally across multiple viewers and geographies.

The detailed viewer-specific judgments, machine key, embeddings, and rankings
remain ignored local artifacts. Only this aggregate, privacy-safe result is
tracked.
