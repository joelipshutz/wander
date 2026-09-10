# rec.me relevance evaluator

Generated: 2026-08-15T07:12:40.519Z

Fixture: 2026-08-14-v1; 40 fictional places; 15 fixed queries.

## Outcome

Vector decision: **KEEP**. Vectors earned the next experiment: add pgvector behind the same candidate-source interface, then rerun this scorecard on anonymized real judgments before product integration.

People-vector decision: **DEFER**. Synthetic fixtures cannot validate learned person-to-place affinity. Use explicit taste and relationship features until real interaction judgments exist.

Keep vectors only if semantic nDCG@5 gains at least 0.05 without more than 0.02 named-person nDCG@5 regression.

Observed semantic nDCG@5 gain over explicit reranking: 5.5%. Named-person regression: 0.0%.

This is an architecture gate, not a production-quality claim: the dataset is fictional and intentionally small.

## Aggregate scorecard

| Pipeline | nDCG@5 | MRR | Semantic nDCG@5 | Named-person nDCG@5 | Community nDCG@5 | Constraint failures | Mean query time |
|---|---:|---:|---:|---:|---:|---:|---:|
| Supabase lexical | 56.9% | 66.7% | 36.5% | 100.0% | 73.6% | 0 | 49.4 ms |
| Lexical + explicit rerank | 95.3% | 100.0% | 92.9% | 100.0% | 97.2% | 0 | 50.8 ms |
| Hybrid vector + rerank | 98.1% | 100.0% | 98.5% | 100.0% | 100.0% | 0 | 109.3 ms |

## Per-query results

| Query | Intent | Lexical top 5 | Reranked top 5 | Hybrid top 5 | nDCG@5 (L / R / H) |
|---|---|---|---|---|---:|
| coffee shops | lexical | North Star Coffee → Ember Window → Juniper Desk → Paper Moon Cafe → Signal Roasters | North Star Coffee → Juniper Desk → Paper Moon Cafe → Ember Window → Garden Cup | North Star Coffee → Juniper Desk → Paper Moon Cafe → Ember Window → Signal Roasters | 93.1% / 94.1% / 99.4% |
| cool coffee shops based on what I like | personal | North Star Coffee → Ember Window → Juniper Desk → Paper Moon Cafe → Signal Roasters | North Star Coffee → Juniper Desk → Paper Moon Cafe → Ember Window → Garden Cup | North Star Coffee → Juniper Desk → Paper Moon Cafe → Ember Window → Signal Roasters | 76.0% / 85.0% / 85.0% |
| Joe's favorite coffee shops | named-person | North Star Coffee → Ember Window | North Star Coffee → Ember Window | North Star Coffee → Ember Window | 100.0% / 100.0% / 100.0% |
| quiet place to work on my laptop in Williamsburg | semantic | Juniper Desk | Juniper Desk → North Star Coffee | Juniper Desk → North Star Coffee | 91.7% / 100.0% / 100.0% |
| romantic dinner tonight in the West Village | constraint | — | Candle & Vine → Little Hearth → Marble Room | Candle & Vine → Little Hearth → Marble Room | 0.0% / 100.0% / 100.0% |
| late night noodles near the East Village | constraint | Red Bowl → Midnight Crane | Midnight Crane → Red Bowl → Joe's Square → Sora Counter | Midnight Crane → Red Bowl → Joe's Square → Sora Counter → Copper Lantern | 95.8% / 95.8% / 95.8% |
| group dinner where vegetarians won't be an afterthought | semantic | — | Orchard Table → Common Ground | Orchard Table → Common Ground | 0.0% / 100.0% / 100.0% |
| outdoor drinks for a sunny afternoon | semantic | Roof Fern | Roof Fern → Pocket Garden → Canal Patio → Highline Social | Roof Fern → Pocket Garden → Canal Patio → Highline Social | 52.4% / 96.1% / 96.1% |
| an underrated bakery worth crossing town for | semantic | — | Flour Thief → Blue Apron Bakes → Daily Crumb → Pearl Oven | Flour Thief → Blue Apron Bakes → Daily Crumb → Pearl Oven | 0.0% / 100.0% / 100.0% |
| the community's goated pizza spot | community | Stone & Basil → Borough Slice → Joe's Square → Metro Pie | Borough Slice → Stone & Basil → Joe's Square → Metro Pie → Sora Counter | Borough Slice → Joe's Square → Stone & Basil → Metro Pie → Sora Counter | 73.6% / 97.2% / 100.0% |
| cozy date night that isn't wildly expensive | semantic | Little Hearth | Little Hearth → Roof Fern → Pocket Garden → Orchard Table → Joe's Square | Little Hearth → Pocket Garden → Roof Fern → Orchard Table → Midnight Crane | 74.5% / 90.5% / 94.7% |
| healthy lunch near SoHo | constraint | Mint & Grain → Green Hour | Mint & Grain → Green Hour → Deli Standard → Kite Sushi | Mint & Grain → Green Hour → Deli Standard → Kite Sushi | 95.8% / 100.0% / 100.0% |
| special occasion omakase | lexical | Sora Counter → Moon Gate | Sora Counter → Moon Gate → Joe's Square → Orchard Table → Golden Broth | Sora Counter → Moon Gate → Orchard Table → Marble Room → Candle & Vine | 100.0% / 100.0% / 100.0% |
| kid friendly brunch in Park Slope | constraint | — | Sunday Seed → Bramble Brunch → Stone & Basil | Sunday Seed → Bramble Brunch → Stone & Basil | 0.0% / 100.0% / 100.0% |
| a cozy bookish cafe for a rainy afternoon | semantic | — | Juniper Desk → Paper Moon Cafe → North Star Coffee → Ember Window → Signal Roasters | Paper Moon Cafe → Juniper Desk → North Star Coffee → Ember Window → Garden Cup | 0.0% / 71.0% / 100.0% |

## What ran

- Supabase PostgreSQL held the fictional corpus in a temporary table inside one transaction.
- PostgreSQL `simple` full-text search produced lexical candidates using the same weighted-field shape as REC-225.
- OpenAI produced embeddings once; exact cosine retrieval ran in PostgreSQL over temporary arrays. No pgvector extension or persistent vector table was required.
- A deterministic ranker blended lexical, semantic, explicit viewer-taste, trusted-person, community, and proximity features. Hard constraints were applied before candidate ranking.
- The transaction rolled back and the database connection closed after evaluation. No production rows, functions, indexes, or schema objects persisted.

## Cost and timing

- Embedding model: `text-embedding-3-small`
- Embedding cache: 55 hits, 0 misses
- Embedding request/cache time: 17.7 ms
- Total evaluator time: 2874.6 ms

## Maintainable production boundary

Keep four separable modules: query plan, candidate sources, deterministic ranker, and evaluation. The LLM may translate conversation into a typed query plan, but it does not rank places. Candidate sources can be enabled independently, and one set of weights controls the personal ↔ community dial.
