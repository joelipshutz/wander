# Search and Featured Retrieval Platform

Status: canonical architecture and product contract
Last updated: 2026-09-04
Implementation issues: REC-280, REC-355, REC-384, REC-424

Read this document first before changing Discover Search retrieval, Map
Featured ranking, semantic embeddings, personalization/community blending, or
their monitoring and rollout controls.

## Product contract

rec.me has one retrieval platform with two different product modes:

- **Search** answers an explicit submitted query. It combines immediate local
  trusted-place matching, Postgres full-text candidates, and an optional
  semantic place-candidate provider, plus eligible Apple Maps fallback. Final
  ordering across the three corpora is deterministic.
- **Featured** answers the queryless question "what is worth showing in this
  map view?" It uses explicit relationship, personal-taste, community-support,
  rating, and recency signals. It does not call an LLM or vector store while the
  map moves.

These modes share canonical places, privacy eligibility, filters, analytics
conventions, and evaluation discipline. They do **not** share one universal
ranker or one universal personalization control.

This is intentionally narrower than the original idea to vectorize both places
and people and let an LLM rank everything. Vectors are a bounded Search recall
provider; people are not embedded; authorization and hard filters are
deterministic; and the LLM parser only interprets submitted query intent.

## System shape

```text
submitted Search query
        |
        +--> local trusted-memory groups --------------------------+
        +--> typed plan --> lexical --> immediate rec.me publish --+
        |              +--> semantic --> rec.me RRF refinement -----+
        +--> eligible Apple Maps fallback -------------------------+
                                                                   |
                           DiscoverPlaceSearchRankingPolicy <------+
                           physical dedupe + cross-corpus ordering

map viewport change
        |
        +--> privacy/filter-eligible saved places
                 |
                 +--> canonical-place grouping
                 +--> self/follow relationship signal
                 +--> viewer taste fit
                 +--> community support + rating + recency
                 |
                 +--> Featured groups for the current viewport
```

## Search retrieval

### Candidate providers

1. The local trusted-place matcher renders immediately and remains useful
   offline.
2. `public.search_recme_places` supplies Postgres full-text candidates.
3. `semantic-place-search` embeds the complete submitted phrase and calls
   `public.search_recme_places_semantic` for semantic candidates.
4. Apple Maps supplies visibly sourced external candidates for eligible queries.
   Owner, relationship, and explicit visit-status queries exclude this corpus.
5. Lexical and semantic providers both use
   `app.eligible_recme_place_search`, preventing privacy, block, source,
   category, area, favorite, and social-scope rules from drifting.

Either remote provider may fail without taking down the other. If both fail,
the existing local results remain honest; the client never fabricates a result.

Lexical and semantic requests start together, but delivery is progressive. A
successful lexical result is published as soon as it returns; it does not wait
behind the semantic provider's embedding timeout. If semantic then succeeds,
the same active submission is replaced by the deterministic fused ordering. If
lexical fails, semantic may still recover the remote result. Submission IDs,
cancellation, and query guards prevent a late refinement from replacing a newer
search.

The immediate deterministic filters also plan both remote corpora. When the
optional smart parser refines category, area, favorite, or relationship scope,
the client compares effective requests and restarts each affected provider with
the refined filters. Restarting clears the old rec.me candidates and provenance;
cancellation guards reject late results from the previous plan even within the
same submitted query. Named-owner and non-follower filters stop rec.me retrieval
because its API cannot enforce those constraints. Unchanged remote requests do
not restart just because local parsing metadata changed.

### Rec.me fusion and final cross-corpus ranking

`search_rrf_v1` deduplicates by canonical place id and applies weighted
reciprocal-rank fusion:

```text
score(place) = 1.0 / (12 + lexical_rank)
             + 0.9 / (12 + semantic_rank)
```

Missing provider ranks contribute zero. Agreement between providers is
rewarded. Lexical receives a small edge for exact names and literal intent.
Ties resolve by lexical rank, semantic rank, then stable canonical id. Results
are capped by the request limit, which is at most 20.

Each lexical partial or fused completion replaces only the rec.me input to
`DiscoverPlaceSearchRankingPolicy`. That policy composes trusted groups, rec.me,
and external candidates with physical-place deduplication. Exact external names
can beat weak trusted text matches; equally relevant trusted places win ties.
Apple Maps runs independently and preserves its own request ID as well as the
submission/query guards, including when parser refinement restarts external work.

### Semantic documents

Each canonical place may have one versioned 1,536-dimensional
`text-embedding-3-small` vector. Its document contains only:

- canonical place name;
- broad category;
- subcategory;
- coarse locality;
- region.

The document hash includes model and document version so changes become stale
and eligible for refresh. Exact cosine search is intentional for the current
small corpus. Add HNSW only after measured corpus size and p95 latency justify
its tuning and maintenance cost.

## Map Featured retrieval

Featured operates on Been/check-in candidates inside the current viewport and
applies the active Map refinements before ranking. It groups multiple people's
saves of the same canonical place and currently scores each group with:

- self relationship boost: `1.8`;
- followed-person relationship boost: `1.35`;
- viewer taste fit: category up to `1.1`, cuisine up to `0.75`, matching tags
  up to `0.75`;
- distinct/community support: logarithmic, capped at `2.4`;
- average rating: capped at `1.25`;
- recency and stable canonical key as deterministic tie-breakers.

For large viewports, candidate work is bounded to 480 rows while reserving up
to 240 rows for the viewer and followed people. Community rows fill the
remaining capacity. Consequently, a dense network receives explicit ranking
and capacity advantages, while sparse viewports can still surface useful
places from the wider rec.me pool.

Do not add embeddings or LLM calls to the map-pan path without a new evaluated
decision. The real-corpus Featured trial was too small and too dominated by the
current user/friends to justify replacing this explicit ranker.

## Personalization controls

Search and Featured require separate controls:

- Search may tune semantic recall versus lexical precision.
- Featured may tune relationship/taste evidence versus wider-community quality.

Do not create one slider that changes both. They answer different questions
and have different failure modes.

The current numeric policies are versioned in code. A future lightweight
control plane may add validated, versioned `retrieval_policies` rows with an
active version, last-known-good client caching, and a global kill switch. Safe
remote knobs are limited to weights, similarity floor, candidate limits, and a
Featured network-density/fallback threshold. The following must continue to
require reviewed code or migrations:

- authorization, RLS, visibility, and block rules;
- permitted embedding fields;
- source eligibility and canonical deduplication;
- explanation claims and query-parser schema;
- deterministic tie-breakers.

Never edit an active policy row in place. Create a new version, evaluate it,
activate it, emit its version in analytics, and preserve one-step rollback.

## Privacy invariants

OpenAI may receive:

- the user's submitted Search phrase for query embedding/parsing;
- the minimized canonical place document listed above for offline embedding.

OpenAI and stored vectors must never receive or encode:

- user/profile identity or people embeddings;
- notes, personal labels, answers, or visit history;
- ratings or relationship graph data;
- photos or precise coordinates.

The vector table is service-role-only. App responses contain canonical place
facts, never stored vectors or raw semantic scores. Analytics must not log raw
queries, place names, coordinates, notes, or candidate payloads.

## Performance and failure policy

- Debug, Simulator, TestFlight, and Release all honor the same resolved
  `semantic_place_search_v1` value. There is no Joe-specific runtime path.
- The global semantic flag was verified enabled on 2026-08-29. Typed per-device
  overrides from REC-355 can force On or Off in a developer Xcode build without
  changing the global value or special-casing an account.
- Query embedding has a four-second timeout; Search SQL has a three-second
  statement timeout.
- Lexical delivery is independent of semantic completion; semantic may refine
  it later under the active submission guard.
- Searches are cancellation- and stale-response-guarded by submission state.
- Semantic failure falls back to lexical; lexical failure may be recovered by
  semantic; local results render independently.
- Featured performs no network model call per pan and bounds large candidate
  sets before ranking.

## Monitoring

The canonical monitoring surface should be one PostHog dashboard plus Supabase
operational views—not a custom administration product.

Track by policy version, using privacy-safe counts and buckets:

- Search volume, result counts, zero-result rate, provider overlap, semantic
  success/failure, fallback rate, and p50/p95 latency;
- selected rank and provider provenance, then downstream save/check-in and
  query reformulation;
- Featured network density, network/community mix, fallback share, selected
  rank, save/check-in, and viewport latency;
- eligible-place embedding coverage, stale count, last successful refresh,
  worker failures, and OpenAI embedding usage/cost.

Search emits one random, opaque `search_request_id` per submitted query. It
records numeric and bucketed latency for local, parser, request-plan, lexical,
semantic, fusion, and total stages; provider counts/status; selected rank and
provider provenance; downstream save/check-in conversion; and reformulation.
Apple Maps latency remains on `trusted_place_search_remote_results` with
provider `mapkit`, the same opaque submission ID, and bounded numeric/bucketed
latency; it does not add a retrieval-stage enum. `total` measures the rec.me
request including its plan, not the duration of all three corpora. Selection
rank uses the combined displayed order; provenance is `trusted_memory`,
`lexical`, `semantic`, `lexical_semantic`, `mapkit`, or `unknown`.
The ID contains no user, query, or place data. The checked-in PostHog dashboard
definition owns the Search stage latency, provider/selected-rank, and
request-outcome views. Request outcomes exclude legacy events without a nonempty
opaque submission ID. Applying that dashboard remains a separate explicit
hosted operation.

## Evaluation and change process

Every material policy change follows this loop:

1. create a candidate policy version;
2. run the saved offline judgment corpus and compare nDCG@5, Recall@10,
   exact-name behavior, hard-filter correctness, and privacy constraints;
3. exercise the candidate through Xcode Debug;
4. activate progressively once traffic supports meaningful comparison;
5. compare reliability and outcome metrics by policy version;
6. promote or roll back explicitly.

Do not optimize Featured against the current tiny user/friend-only corpus.
Revisit it after real sparse-network and mixed-community viewports exist.

The maintained offline evidence currently says:

- Search blind pool: 74 judgments across 12 real-corpus queries. Lexical
  nDCG@5 was 56.9%, explicit reranking 77.7%, and hybrid 84.1%. That historical
  run used approved aggregate structured tags in its semantic lab document,
  while production document version 1 is stricter. It validates the bounded
  place-vector architecture, not the exact production document or weights; the
  maintained lab now mirrors production and must be rerun before a policy
  change.
- Featured blind pool: the explicit baseline scored 82.9% nDCG@5 while the
  semantic-taste variant scored 73.0%. Keep the explicit Featured ranker. The
  corpus is too small and self/friend-heavy to justify a vector rollout.
- People vectors remain deferred until there is enough multi-person behavior
  for an honest offline evaluation.

## Implementation map

| Concern | Source of truth |
|---|---|
| Search query planning | `Wander/Services/TrustedPlaceSearch.swift` |
| Search provider orchestration/fallback | `Wander/App/WanderBackend.swift` |
| Search fusion policy | `Wander/Services/RecmePlaceSearchFusion.swift` |
| Discover runtime and analytics | `Wander/Features/Discover/DiscoverScreen.swift` |
| Search analytics contract | `docs/analytics.md` and `Wander/Services/AnalyticsEvent.swift` |
| Managed Search dashboard definitions | `scripts/posthog-product-dashboard.mjs` |
| Offline Search/Featured evaluation | `scripts/relevance-lab/` and `docs/evals/` |
| Remote repositories/DTO boundary | `Wander/Services/Remote/SupabaseRepositories.swift` |
| Search schema, RLS, RPCs, refresh schedule | `supabase/migrations/20260816120000_semantic_place_search.sql` |
| Query embedding function | `supabase/functions/semantic-place-search/` |
| Place embedding worker | `supabase/functions/refresh-place-embeddings/` |
| Map Featured ranker | `Wander/Features/Map/MapScreen.swift` (`MapFeaturedSelection`) |
| Community Featured backend | `supabase/migrations/20260815210000_featured_community_places.sql` |
| Detailed REC-280 rollout/validation | `docs/plans/2026-08-16-rec-280-semantic-search-implementation.md` |
| Operational hardening and handoff | `docs/plans/2026-08-29-rec-384-search-platform-hardening.md` |

## Current deployed state and future change gate

Verified on 2026-08-29:

1. the semantic Search migration and both Edge Functions are deployed;
2. 135 eligible place embeddings exist and the current stale/missing backfill
   count is zero for `text-embedding-3-small`, document version 1;
3. the global `semantic_place_search_v1` flag is enabled;
4. the client uses the typed flag registry and supports device On/Off overrides;
5. the current Search and Featured blind scorecards are checked into the repo.

REC-384 changes only client delivery, analytics definitions, evaluation tooling,
and documentation until separately reviewed and merged. It does not mutate the
hosted flag, database, Edge Functions, or dashboard. Disabling the global switch
still restores lexical-only behavior, and Featured remains unaffected.

Before changing weights, embedding fields/model, candidate caps, or adding a
policy registry: rerun the saved offline corpus, compare the defined slices,
exercise the candidate in an Xcode build, and require an explicit activation
and rollback version. A database-backed policy registry is a follow-up, not part
of REC-384; authorization and privacy rules never become runtime tuning knobs.
