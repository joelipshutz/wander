# Relevance lab

This is the smallest useful architecture test for rec.me search and Discover. It runs outside the iOS app and leaves the hosted Supabase schema and data unchanged.

It compares three pipelines over 40 fictional places and 15 fixed relevance judgments:

1. Supabase weighted full-text search.
2. The same lexical candidates plus explicit trusted-person/community candidate sources and a deterministic reranker.
3. Exact semantic candidates plus the same reranker.

The OpenAI model only creates embeddings. It does not decide ranking, parse filters, or see production data. Embeddings are cached under the ignored `.cache/` directory. Both lexical and exact-vector retrieval execute against a temporary PostgreSQL table in a transaction that always rolls back.

## Run

```bash
npm --prefix scripts ci --ignore-scripts
npm --prefix scripts run test:relevance
npm --prefix scripts run relevance:run -- \
  --write-report docs/evals/2026-08-14-relevance-evaluator.md \
  --write-json scripts/relevance-lab/output/latest.json
```

The runner reads `OPENAI_API_KEY`, `WANDER_SUPABASE_DB_PASSWORD`, and `WANDER_SUPABASE_PROJECT_REF` from the current environment or `~/.openclaw/workspace/.env.keys`. It never prints them.

## Prepare a real-data judgment pool

```bash
npm --prefix scripts run relevance:prepare-real
```

This reads the hosted corpus in a read-only transaction and writes ignored local artifacts under `scripts/relevance-lab/output/`: a blind click-to-grade HTML page, a Markdown fallback, and the machine scoring key. The embeddings contain canonical name, category, subcategory, coarse locality/region, and approved aggregated structured tags. Notes, free-text answers, personal labels, profile identity, addresses, photos, emails, and coordinates are neither selected nor sent to the embedding provider.

The pool unions candidates from all three pipelines, randomizes their presentation, and hides which system returned each place. Replace every `?` in `real-judgments.md` with `0`, `1`, `2`, or `3`; the completed file becomes the real qrels input for the next scorecard.

Score the completed blind pool without querying Supabase or regenerating embeddings:

```bash
npm --prefix scripts run relevance:score-real -- \
  --key scripts/relevance-lab/output/real-pool-key.json \
  --scores scripts/relevance-lab/output/real-scores.txt \
  --write-report scripts/relevance-lab/output/real-scorecard.md \
  --write-json scripts/relevance-lab/output/real-scorecard.json
```

The scorer requires one response for every pooled candidate and reconstructs each hidden top-five ranking from the machine key. Use `0`–`3` for a real judgment or `X` when the judge does not know the place well enough to grade it. A scenario containing `X` is excluded from judged ranking metrics rather than treating unknown as irrelevant, and incomplete coverage blocks policy promotion. The scorer reports nDCG@5 plus simple top-result and wrong-result guardrails. Scoring is entirely local; the judgments and machine key remain ignored.

## Decision rule

On the real blind pool, vectors earn a pgvector follow-up only when the hybrid pipeline improves semantic-query nDCG@5 by at least 0.05 over explicit reranking and does not regress non-semantic nDCG@5 by more than 0.02. Passing this gate keeps vectors as an optional candidate source; it does not approve fixed hybrid weights for production.

This lab tests place/query embeddings, not learned people embeddings. Personalization uses explicit, inspectable taste and relationship features. A people-vector experiment is deferred until real interaction data can support honest offline judgments.

The seams are deliberate: query plan, candidate providers, ranker, and evaluation are separate. Replacing exact vector retrieval with pgvector or adding an LLM query planner should not require rewriting the ranker or scorecard.

## Prepare a real Featured judgment pool

Featured is evaluated separately because it has no text query. Its unit is a real viewer plus a real map viewport. The generator reads one explicit viewer's privacy-eligible corpus in a read-only transaction, creates dense, sparse, simulated-empty-network, cold-start, and overlapping-pan scenarios, then compares five hidden policies. At least one sparse scenario must be a genuinely sparse real viewport. If the corpus does not contain a second honest sparse viewport, the generator uses an explicitly recorded `thin` relationship mask over a real dense viewport instead of falsely labeling another dense area as sparse.

1. The shipped Featured scoring baseline.
2. Trusted-network-only retrieval.
3. A fixed network/community blend.
4. A viewport-density-aware blend.
5. The density-aware blend plus place-semantic similarity to the viewer's explicit positive/Wanna taste profile.

Run it with the handle of the person who will grade the pool:

```bash
npm --prefix scripts run relevance:prepare-featured-real -- \
  --viewer-handle <your-recme-handle>
```

The ignored output folder receives `featured-judgments.html`, a Markdown fallback, and `featured-pool-key.json`. Candidate order is randomized and policy/source order is hidden. Grade each place according to the viewer's taste and whether it is a useful Featured pin in the named map area; there is deliberately no query. Use `X` when the judge genuinely does not know a place. The scorer excludes that whole scenario from judged ranking metrics and prevents a `KEEP` decision until coverage is complete, instead of silently turning uncertainty into a zero.

Generation fails closed unless the machine-readable preflight confirms honest density labels, at least one actual sparse viewport, a mixed network/community sparse result, complete blind coverage of every policy's top five, policy separation, complete pan pairs, zero privacy/duplicate failures, and local ranking p95 below 50 ms. Re-run that check without Supabase or embedding calls at any time:

```bash
npm --prefix scripts run relevance:preflight-featured-real -- \
  scripts/relevance-lab/output/featured-pool-key.json
```

The preflight also warns when the real community-only corpus is thin. A policy cannot earn `KEEP` unless the snapshot contains at least 20 real community-only canonical places, those places are at least 20% of the eligible corpus, and at least one actual sparse viewport returns a network/community mix. Simulated thin/empty slices remain directional and are reported separately; they are not misrepresented as organic community coverage.

The loader never writes hosted data. Non-followed contributions become anonymous canonical-place aggregates before leaving the loader: contributor identifiers are one-way opaque labels used only for diversity counts, and stranger notes, prose, tags, answers, photos, and identities are not selected into the benchmark model. Featured place embeddings contain only global canonical facts: name, category, subcategory, and coarse locality/region. Personal structured tags stay in the explicit local taste scorer and never alter the reusable place vector; simulated community candidates lose self-only tags as well as relationship evidence. Coordinates remain local and are used only for viewport membership and geographic metrics.

After copying the completed scores into `featured-scores.txt`, score without Supabase or embedding calls:

```bash
npm --prefix scripts run relevance:score-featured-real -- \
  --key scripts/relevance-lab/output/featured-pool-key.json \
  --scores scripts/relevance-lab/output/featured-scores.txt \
  --write-report scripts/relevance-lab/output/featured-scorecard.md \
  --write-json scripts/relevance-lab/output/featured-scorecard.json
```

The predeclared promotion gate is intentionally harder than “wins overall”: zero privacy/duplicate failures, local ranking p95 below 50 ms, at least +0.05 nDCG@5 on sparse/empty/cold-start slices, no more than 0.02 nDCG@5 regression on dense-network slices, and no more than 0.10 top-10 overlap regression across the small-pan pair. Place semantics must independently clear the same incremental gate over density-aware ranking. A pass earns only a feature-flagged implementation trial, not production rollout.
