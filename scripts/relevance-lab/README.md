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

## Decision rule

Vectors earn a pgvector follow-up only when the hybrid pipeline improves semantic-query nDCG@5 by at least 0.05 over explicit reranking and does not regress named-person nDCG@5 by more than 0.02. That follow-up still needs anonymized real judgments before app integration.

This lab tests place/query embeddings, not learned people embeddings. Personalization uses explicit, inspectable taste and relationship features. A people-vector experiment is deferred until real interaction data can support honest offline judgments.

The seams are deliberate: query plan, candidate providers, ranker, and evaluation are separate. Replacing exact vector retrieval with pgvector or adding an LLM query planner should not require rewriting the ranker or scorecard.
