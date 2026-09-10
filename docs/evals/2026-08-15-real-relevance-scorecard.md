# Real rec.me relevance scorecard

Generated: 2026-08-16T06:23:29.441Z

Blind pool: 74 judgments across 12 real-corpus queries. Source snapshot: 210 active saves and 114 ratings.

## Outcome

Place-vector decision: **KEEP**. Place vectors earned a bounded pgvector follow-up behind the existing candidate-source interface.

People-vector decision: **DEFER**. Only 2 profiles have five or more ratings, so learned person affinity is not yet an honest experiment.

Keep place vectors only if semantic-query nDCG@5 improves by at least 0.05 and non-semantic nDCG@5 regresses by no more than 0.02.

Observed semantic nDCG@5 gain over explicit reranking: 8.4%. Non-semantic guardrails improved by 0.4%.

This gate keeps vectors as an optional candidate source; it does not approve the current fixed hybrid weights for production.

## Aggregate scorecard

| Pipeline | nDCG@5 | MRR | Ideal result at #1 | Top-5 filled | Useful top-5 slots | Wrong among returned |
|---|---:|---:|---:|---:|---:|---:|
| Supabase lexical | 56.9% | 66.7% | 50.0% | 56.7% | 51.7% | 1.7% |
| Lexical + explicit rerank | 77.7% | 94.4% | 66.7% | 90.0% | 63.3% | 12.5% |
| Hybrid vector + rerank | 84.1% | 95.8% | 66.7% | 96.7% | 70.0% | 10.0% |

## Intent slices

| Intent | Queries | Lexical nDCG@5 | Reranked nDCG@5 | Hybrid nDCG@5 | Hybrid vs reranked |
|---|---:|---:|---:|---:|---:|
| lexical | 1 | 88.6% | 89.5% | 88.6% | -0.9% |
| semantic | 9 | 56.1% | 73.3% | 81.7% | 8.4% |
| constraint | 1 | 0.0% | 95.9% | 100.0% | 4.1% |
| community | 1 | 89.5% | 87.7% | 85.9% | -1.8% |

## Per-query nDCG@5

| Query | Intent | Lexical | Reranked | Hybrid |
|---|---|---:|---:|---:|
| coffee shop in Santa Monica | lexical | 88.6% | 89.5% | 88.6% |
| date-night restaurant in Los Angeles | semantic | 92.3% | 46.6% | 40.9% |
| quiet coffee shop where I can work | semantic | 86.9% | 100.0% | 100.0% |
| cocktails in West Hollywood | constraint | 0.0% | 95.9% | 100.0% |
| outdoor drinks in Santa Monica | semantic | 0.0% | 67.7% | 84.2% |
| bakery or dessert worth a trip | semantic | 93.9% | 95.9% | 100.0% |
| special-occasion restaurant in Los Angeles | semantic | 0.0% | 28.6% | 39.4% |
| healthy lunch in Santa Monica | semantic | 0.0% | 70.0% | 98.3% |
| casual group dinner in Los Angeles | semantic | 71.3% | 80.7% | 92.5% |
| hike or nature escape | semantic | 73.1% | 80.6% | 80.6% |
| the community's favorite restaurant in Santa Monica | community | 89.5% | 87.7% | 85.9% |
| cozy coffee or tea for a rainy afternoon | semantic | 87.2% | 89.5% | 99.1% |

## Architecture read

- The largest hybrid gain was **healthy lunch in Santa Monica** (28.3% versus explicit reranking).
- The largest hybrid regression was **date-night restaurant in Los Angeles** (lost 5.7%). The production ranker needs intent-dependent source weights and must preserve strong lexical evidence.
- Keep lexical, semantic, explicit taste/social, and community retrieval as separate bounded candidate providers. Hard filters run before their union; one deterministic ranker owns the final order and the personal ↔ community dial.
- Let the conversational LLM produce a typed query plan. Do not put an LLM in the synchronous ranking loop.
- Add pgvector only behind the semantic provider seam and feature flag, then rerun this same blind scorecard after weight changes.

## Limits

- This is one judge and 12 queries, so it is a directional architecture gate, not a statistically stable relevance benchmark.
- This historical run used approved aggregate structured tags in the lab's semantic place document. Production document version 1 is stricter and contains only canonical name, category, subcategory, and coarse locality/region. The maintained lab now mirrors that production contract; rerun the blind pool before treating these figures as validation of exact production weights.
- Every top-five result from every pipeline was judged, but results outside that pooled candidate set were not. This compares ordering and candidate recovery inside the tested pool; it does not establish absolute corpus recall.
- The scorecard tests place/query embeddings. It does not test learned people embeddings or an LLM ranker.
