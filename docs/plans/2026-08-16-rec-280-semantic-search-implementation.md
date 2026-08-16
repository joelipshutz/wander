# REC-280 Semantic Discover Search Implementation

Status: implemented for Xcode Debug builds and behind a default-off global
Release flag; not yet deployed.

## Outcome

rec.me now has one retrieval platform with two independent Search candidate
providers:

1. the existing local and Postgres full-text providers, which remain the
   baseline and fallback;
2. an optional semantic provider over minimized canonical place documents.

The iOS client unions candidates by canonical place id and applies one
deterministic, versioned reciprocal-rank-fusion policy. Either remote provider
may fail without suppressing results from the other. Immediate on-device
results continue to render while remote work is in flight.

Map Featured is deliberately separate. It keeps its explicit self/followed
network, taste, anonymous community-support, rating, and recency ranker. It
does not call OpenAI or perform vector retrieval while the map moves.

This is the practical change from the original "vectorize places and people,
then let an LLM rank everything" idea: vectors are a bounded Search recall
tool, not the source of truth or the final ranker; people are not embedded;
privacy and product constraints remain deterministic SQL/code; and the LLM
parser only interprets submitted query intent.

## Runtime flow

```text
submitted Discover query
        |
        +--> immediate local search ---------------------------+
        |                                                       |
        +--> structured query plan                              |
                 |                                              |
                 +--> Postgres full-text candidates ----+       |
                 |                                      |       |
                 +--> semantic candidates (flagged) ----+       |
                                                        |       |
                                      canonical-id dedupe + RRF  |
                                                        |       |
                                      remote refinement +--------+
```

The semantic Edge Function embeds the complete submitted phrase, then calls a
Supabase RPC with the signed-in user's token. The lexical and semantic RPCs
both use `app.eligible_recme_place_search`, so category, area, favorite, social
scope, block, profile, visibility, and source rules cannot drift between the
two providers.

## Data and privacy contract

`public.place_search_embeddings` stores one 1,536-dimensional
`text-embedding-3-small` vector per canonical place. The embedding document is
versioned and contains only:

- canonical place name;
- broad category;
- subcategory;
- coarse locality;
- region.

It must never contain user/profile identity, notes, personal labels, question
answers, ratings, photos, precise coordinates, visit history, or people
embeddings. The search request sends the user's submitted query text to OpenAI;
it does not send candidate records or graph data. The application receives
canonical place facts only, never the stored vector or semantic score.

The table has RLS enabled and no client role privileges. A service-only worker
can read stale minimized documents and write vectors. Search runs through a
narrow authenticated security-definer RPC with an empty `search_path`, bounded
limit, dimensionality check, similarity floor, and statement timeout.

## Ranking policy

`search_rrf_v1` uses weighted reciprocal rank fusion:

- lexical weight: `1.0`;
- semantic weight: `0.9`;
- reciprocal-rank offset: `12`;
- output cap: the request limit, at most 20.

Lexical receives a small edge for exact names and explicit terms. Agreement
between providers is rewarded. Tie-breaking is deterministic. Provider
provenance is retained internally for aggregate measurement but is not exposed
as unverified explanation copy.

## Failure and performance behavior

- Xcode Debug build: semantic retrieval runs without an account flag.
- Release build with the global flag off: only the existing lexical path runs.
- Semantic failure or timeout: lexical results still render.
- Lexical failure: semantic results may recover the request when enabled.
- Both remote providers fail: existing Discover remote-error behavior applies;
  already-rendered local results are not fabricated or replaced.
- Every search is cancellation/stale-response guarded by submission id and
  normalized query.
- OpenAI query embedding has a four-second hard timeout; SQL has a three-second
  statement timeout. Aggregate latency and result-count buckets identify a
  slower provider without logging the query or a place.
- Exact cosine search is intentional for the current small corpus. Add an HNSW
  index only after production corpus/latency measurements justify its tuning
  and maintenance overhead.

## Refresh and staleness

`refresh-place-embeddings` requests at most 50 missing or stale documents per
run, sends them to OpenAI in one embedding batch, and upserts by place id. The
document hash includes model and document version, so changing canonical facts,
model, or document format makes the row eligible for refresh. A scheduled job
runs every ten minutes using the existing worker-secret boundary. Ineligible
places cannot be returned because current eligibility is always rechecked at
query time.

## Activation sequence

Do not enable the global Release flag before all of these steps complete:

1. review and merge REC-280;
2. set `OPENAI_API_KEY` for the two Edge Functions and deploy
   `semantic-place-search` plus `refresh-place-embeddings`;
3. apply migration `20260816120000_semantic_place_search.sql` to the linked
   Supabase project and verify migration/security metadata;
4. invoke the refresh worker until `remaining` is false;
5. run authenticated lexical/semantic smoke queries and confirm the response
   contains canonical place fields only;
6. test the deployed provider from an Xcode Debug build, which enables semantic
   retrieval without an account override;
7. compare aggregate result count, provider overlap, semantic failure, and
   latency buckets, then deliberately enable `semantic_place_search_v1`
   globally when the Release launch gate passes.

There is no Joe-specific semantic Search override or algorithm. Debug is a
build-time testing boundary; every Debug user runs the same policy against that
user's authorized corpus, network, and preferences. Release behavior changes
only through the global server flag.

Disable the global flag to roll back Release behavior immediately. The
embedding table and worker may remain in place without affecting Search or
Featured.

## Revisit gates

- Tune the semantic similarity floor or fusion weights only against saved
  judgments and version the policy when behavior changes.
- Consider HNSW after exact search approaches the SQL timeout or measured p95
  becomes material.
- Re-evaluate semantic retrieval for Featured only after rec.me has a genuinely
  mixed-source, sparse-network viewport corpus and real interaction outcomes.
  The existing small Joe/friend corpus is not evidence that vectorizing people
  or replacing the Featured ranker will help.
