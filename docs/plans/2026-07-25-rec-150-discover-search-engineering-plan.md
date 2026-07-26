# REC-150 Discover search engineering plan

Status: approved interaction direction; ready for implementation review.

Linear: [REC-150](https://linear.app/recme/issue/REC-150)

Design handoff: draft PR [#219](https://github.com/joelipshutz/wander/pull/219)
and the finalized local prototype at
`~/.gstack/projects/joelipshutz-wander/designs/discover-search-20260725/finalized.html`.

## Goal

Fix the Discover place-search trap and make natural-language search legible,
cheap, and trustworthy.

Tapping the search field enters a temporary search mode with the field pinned
to the top and an explicit Back control. Before a query is submitted, the
screen teaches plain-language search through polished examples. After submit,
the app shows how it interpreted the query and why each place matched.

The LLM is a bounded query translator, not a recommender. It runs once per
submitted, uncached query. It never receives the social graph or place records,
and it never writes free-form explanations for individual places. Deterministic
code resolves people, filters visible records, ranks results, and produces every
displayed match reason from evidence actually present in those records.

## Locked decisions

| Decision | Chosen approach |
|---|---|
| Search navigation | Search is a temporary state inside `DiscoverScreen`, not a pushed destination. Back always cancels work and restores the prior Discover idle state. |
| Search placement | On activation, hide the normal Discover tabs/body and pin Back + search field at the top safe area. |
| Clear vs Back | Clear empties the draft/results but stays in search mode. Back exits search mode, dismisses the keyboard, clears transient search state, and restores Discover. |
| Search trigger | Submit-driven only: keyboard Search or tapping an example. Typing does not call the LLM. |
| Teaching state | Four static, tappable natural-language examples with static intent metadata such as `Ryan · favorites · coffee`. No model call is needed to render examples. |
| Model boundary | Extend the existing authenticated `parse-discover-query` Edge Function and shared structured-JSON provider layer. Do not add a second provider, dependency, or endpoint. |
| Calls per query | At most one remote parse for a normalized, schema-versioned cache miss. Never one call per result. |
| Model output | Strict typed query plan only: existing filters plus opinion/ranking intent and bounded unsupported concepts. |
| Result explanations | Deterministically derive `Matched:` evidence from the exact visible owner-place row. The LLM cannot emit card copy or claim evidence. |
| Favorite meaning | `Been` plus either the queried person's rating of 4.0+ or that person's explicit personal label containing `favorite`; sort by that person's rating first. Wanna Go is excluded. |
| Zero-result truth | Never broaden silently. Show zero exact matches and offer an explicit relaxation such as `Show Ryan's visited coffee spots`. |
| Person resolution | Resolve the parsed owner text against eligible visible profiles locally by exact normalized handle/name first. Ambiguity requires a choice before claiming results. |
| Privacy | Continue sending only the raw query and allowed schema. Never send profiles, place names, notes, coordinates, contacts, or graph edges to the model. |
| Provider/model | Keep the provider and model environment-configurable. Benchmark the current `gpt-5.4-nano` path against a golden query set before pinning a production snapshot. |
| Failure mode | Use a typed deterministic fallback plan with the same semantic post-validation rules and show a quiet `Using basic matching` status when it was needed. |
| Rollout | Deploy the backward-compatible Edge Function response first, validate it, then ship the tolerant iOS decoder and UI. No database migration or RPC change is required. |

## What already exists

| Existing capability | Reuse in REC-150 |
|---|---|
| `DiscoverSearchField`, query ticker, place results, owner disambiguation, and save actions in `DiscoverScreen.swift` | Preserve the field styling and current result-card anatomy while replacing the interaction state machine. |
| `LLMFilterParser` and `DeterministicFilterParser` | Evolve both to return the same typed query plan; do not create parallel parser semantics. |
| `parse-discover-query` Edge Function | Extend its strict JSON schema, examples, semantic validator, and diagnostics. |
| `_shared/ai/structured-json.ts` | Keep provider swapping, server-side API keys, timeout handling, `store: false`, and strict Structured Outputs. |
| `SupabaseDiscoverFilterRepository` and `RemoteDiscoverFilterParser` | Rename/evolve the filter-only boundary to carry the full query plan and explicit parse source. |
| `WanderStore.parseDiscover` in-memory cache | Replace the unbounded query-only dictionary with a bounded, schema-versioned plan cache. |
| `VisiblePlace`, `VisiblePlaceGroup`, ratings, statuses, attributes, owner profiles, and visibility filtering | Use these as the sole evidence source for filtering, ranking, and `Matched:` metadata. |
| `discover_query_parsed` / `discover_parse_failed` analytics | Expand them with non-PII source, latency, intent, fallback, and result-count buckets. |

## Current gaps this plan closes

1. `DiscoverScreen` currently starts a debounced parse on every query change.
   Cancellation protects the final assignment, but an already-sent remote call
   can still incur cost.
2. Focus changes the keyboard but does not create an explicit, reversible
   search mode. There is no durable Back affordance.
3. `DiscoverFilters` cannot represent favorite/opinion or ranking intent, so
   `Ryan's coffee spots` and `Ryan's favorite coffee spots` can converge.
4. The remote validator admits schema-valid but semantically wrong results.
   The deterministic fallback also reduces `favorite` to only `Been`.
5. Owner matching uses substring containment, and `LA` currently bypasses area
   filtering entirely.
6. Result groups default their primary row to the current user's save. That can
   show the wrong person's note/status/rating for an owner-scoped query.
7. The current result line lists generic metadata, but it does not distinguish
   evidence that actually satisfied the submitted query.
8. The successful parse cache is unbounded and keyed only by normalized query,
   so a future schema change can reuse stale semantics during the same session.

## Not in scope

- A general recommendation or embedding system.
- Sending the user's place corpus or social graph to any LLM.
- LLM-written place summaries, generated reviews, or per-result model calls.
- Map-distance, current-location radius, hours/open-now, live pricing,
  reservations, or inferred accessibility. These remain unsupported until an
  authoritative data contract exists.
- Semantic search over arbitrary note prose beyond the existing bounded tag and
  attribute matching.
- Redesigning People search, changing the four bottom tabs, or changing the
  place-profile/save flows.
- A Supabase schema migration, RLS change, or new public RPC.
- TestFlight release work. Implementation becomes eligible for the next
  explicitly requested release batch after merge.

## Architecture

```text
Discover idle
    |
    | tap search
    v
temporary search mode -> Back cancels task and restores idle
    |
    | type locally (zero remote calls)
    | keyboard Search / example tap
    v
submitted query + request generation
    |
    +--> schema-versioned session cache hit -------------------------+
    |                                                               |
    `--> authenticated parse-discover-query Edge Function           |
             | raw query + allowed enums only                       |
             v                                                      |
         gpt-5.4-nano / configured provider                         |
             | strict JSON query plan                               |
             v                                                      |
         server validation + semantic invariant repair              |
             | failure/timeout -> deterministic plan                |
             +-------------------------------------------------------+
                                                                     v
                                              local owner resolution + RLS-visible records
                                                                     |
                                                                     v
                                           deterministic filter, grouping, evidence, ranking
                                                                     |
                                                                     v
                                            Understood as + exact answer + Matched metadata
```

There is one semantic handoff: the model identifies the user's requested
facets; code proves which records satisfy them. Keeping that boundary prevents
an explanation from becoming more confident than the data.

## Cross-layer query contract

Replace the filter-only return value with a versioned plan shared by the Edge
Function, repository, remote parser, deterministic parser, store, and tests.

```text
DiscoverQueryPlan
  schemaVersion: Int                 // 2 for REC-150
  query: String                      // added from trusted request input, not model output
  categories: Set<String>
  area: String?
  statuses: Set<PlaceStatus>
  relationship: ViewerRelationship?
  ownerQuery: String?
  tags: Set<String>
  opinion: none | favorite
  sort: relevance | ownerRatingDescending
  unsupportedConcepts: Set<DiscoverUnsupportedConcept>

DiscoverUnsupportedConcept
  nearMe | distance | openNow | hours | price | recency
```

All model-returned keys are required and `additionalProperties` remains false.
Free-form `reason`, `summary`, `place`, `ownerID`, and `profile` fields are
forbidden. `ownerQuery` and `area` stay bounded sanitized text because the model
is only copying/normalizing parts of the raw phrase; the client resolves them to
real data.

### Server semantic post-validation

JSON Schema proves shape, not meaning. After decoding, the Edge Function must
apply deterministic invariants before returning a plan:

- If `opinion == favorite`, force `statuses = [.been]` and
  `sort = .ownerRatingDescending`; remove Wanna Go even if the model returned it.
- If the raw query contains a high-risk favorite synonym (`favorite`, `best`,
  `loved`, `highly rated`) but the model omitted favorite intent, repair it or
  reject the parse into the deterministic fallback. Test every synonym.
- If the raw query contains an explicit Want-to-go phrase, require only
  `.wannaGo`. If it contains an explicit Been phrase, require only `.been`.
- Never accept a category, relationship, status, tag, sort, opinion, or
  unsupported concept outside the provided enum.
- Normalize and length-bound copied text, reject control characters, and keep
  the existing 160-character query limit.
- Treat a plan with no recognized facets for a non-empty query as
  `semantic_empty`; do not record it as a successful intelligent parse.
- Do not log the raw query or copied owner/area text.

The deterministic parser must call the same normalization/invariant function in
iOS terms. Remote and fallback plans may differ in recall, but they cannot
disagree on favorite/Been/Wanna safety rules.

### Parser source and cache contract

`DiscoverQueryPlan` describes meaning. Source is local execution metadata:

```text
DiscoverQueryInterpretation
  plan: DiscoverQueryPlan
  source: remote | deterministicFallback | cache
  resolvedOwner: ProfileShell?
  ownerResolution: none | exact | ambiguous | notFound
```

Use a session-only LRU cache with capacity 50. Key it by:

```text
schemaVersion + normalizedQuery + stableFilterSchemaFingerprint
```

Do not persist raw queries to SwiftData/UserDefaults. Do not cache invalid or
cancelled parses. A cache hit changes `source` to `cache` while retaining the
underlying plan. Clear the cache on account change/sign-out as the store already
does for search state.

## Deterministic execution and explanation contract

### 1. Resolve the requested person

Resolve `ownerQuery` only against profiles the viewer may currently discover:

1. normalized exact `@handle`;
2. normalized exact display name;
3. unique normalized prefix/token match;
4. otherwise `ambiguous` or `notFound`.

Normalization removes `@`, possessive punctuation, and a trailing possessive
`s` only at a token boundary. It must not use arbitrary substring containment.
`Ryan`, `Ryan's`, and `Ryans` may resolve to Ryan; `bar` must not resolve to
Barbara. An ambiguous result renders choices before any place answer is shown.

### 2. Select the evidence-bearing owner row

Filtering still begins from `store.visiblePlaces(...)`, which already applies
the local projection of backend visibility/block rules. For an owner-scoped
query, the queried person's matching `VisiblePlace` must become the result
group's evidence row and display row. A current-user duplicate may appear as
secondary context, but it must not replace Ryan's rating, status, label, or note
in an answer about Ryan.

### 3. Enforce exact favorite semantics

A row satisfies favorite only when all are true:

- its owner is in the requested owner/relationship scope;
- `userPlace.status == .been`;
- either `userPlace.ratingScore >= 4.0`, or a decoded
  `PlaceMemoryAttributeKeys.personalLabels` value contains the standalone word
  `favorite` case-insensitively.

Do not use the group's aggregate `recommendedScore` to qualify an owner-scoped
favorite. Do not infer favorite from a positive note, category popularity, or
another person's rating. Sort qualifying rows by the evidence owner's rating
descending, then `savedAt` descending, then stable place id. Label-backed rows
without a numeric rating follow rated favorites and retain their explicit label
as evidence.

### 4. Match area and tags against authoritative local fields

- Replace the `area == "LA"` bypass with tokenized aliases (`LA` ->
  `Los Angeles`) checked against locality, region, and normalized address.
- A tag match records the exact source category: structured attribute,
  personal label, or note token. Do not claim a tag merely because another row
  in the group contains it.
- Category evidence uses the evidence row's effective category assignment.
- Unsupported concepts affect interpretation copy only and never create a
  filter that the app cannot execute.

### 5. Produce typed match evidence

```text
DiscoverMatchEvidence
  kind: owner | opinion | rating | personalLabel | category |
        status | area | tag | relationship
  displayValue: String              // formatted from verified local data
  sourceOwnerID: String?

DiscoverPlaceMatch
  group: VisiblePlaceGroup
  evidencePlace: VisiblePlace       // exact row used to prove the match
  evidence: [DiscoverMatchEvidence]
  rank: DiscoverMatchRank

DiscoverSearchResponse
  interpretation: DiscoverQueryInterpretation
  placeMatches: [DiscoverPlaceMatch]
  profiles: [ProfileShell]
```

Evidence is presentation-safe data, not prose generated by the model. The
renderer orders it by query discriminativeness: owner, opinion/rating or label,
category, tag, status, area, relationship. It renders a wrapping line such as:

```text
Matched: Ryan · favorite (4.5) · Coffee · Silver Lake
```

Every hard facet that admitted the result must be represented; do not truncate
away a required facet. VoiceOver combines the same typed evidence into one
sentence. Generic metadata such as aggregate rating or locality may remain in
the existing title/subtitle, but only verified query evidence appears after
`Matched:`.

## Query truth table

| Query | Required plan/execution | Example verified metadata | Forbidden behavior |
|---|---|---|---|
| `Ryan's favorite coffee spots` | Ryan + Coffee + Been + favorite + Ryan-rating sort | `Ryan · favorite (4.5) · Coffee` | A Wanna Go save, another person's rating, or broad visited fallback. |
| `Ryans favorite coffee spots` | Resolve `Ryans` to one eligible Ryan, then the same favorite contract | Same as above | Silently dropping the person because the apostrophe is absent. |
| `Ryan's coffee spots` | Ryan + Coffee; allow Been and Wanna Go, with status visible | `Ryan · Coffee · Wanna Go` | Presenting a Wanna result as a favorite. |
| `friends' sunset hikes` | Mutuals + Outdoors + sunset | `Friends · Outdoors · sunset` | A stranger's place or an unverified sunset claim. |
| `quiet work cafes with wifi` | Coffee + quiet + work/wifi tags | `Coffee · quiet · wifi` | Matching because a different owner row mentions wifi. |
| `coffee open now` | Coffee + unsupported `openNow` | `Coffee`; interpretation says open-now was not applied | Claiming live hours or filtering on absent hours data. |

## Search interaction and UI states

Represent the flow explicitly rather than inferring it from focus and non-empty
text:

```text
DiscoverSearchState
  idle
  activeEmpty
  drafting(text)
  loading(submissionID, query)
  loaded(submissionID, response)
  fallback(submissionID, response)
```

| State | Required behavior |
|---|---|
| Idle | Preserve the normal Discover surface and its scroll state. Tapping the field activates search. |
| Active empty | Back + focused field at top; rich teaching copy and four example-query cards. Each example includes static intent metadata and is a 44 pt minimum target. |
| Drafting | Edit locally. No LLM call and no stale result claim. Keyboard return label is Search. |
| Loading | Capture an immutable submission id/query, dismiss or retain keyboard per native behavior, preserve the query, show result-shaped skeletons, and keep Back/Clear usable. |
| Loaded | Show read-only `Understood as` facets, exact count/summary, and evidence-bearing result cards. |
| Basic fallback | Show the same result structure with quiet `Using basic matching`; never imply the full phrase was understood if concepts were dropped. |
| Exact zero | Explain what was understood, say there are no exact matches, and offer a clearly labeled relaxation that submits a new query/plan. |
| Unsupported concept | Show `We couldn't use open now yet` beside the understood facets. Do not hide the limitation in a card footer. |
| Clear | Cancel current work, empty the field/results, remain in `activeEmpty`, and refocus the field. |
| Back | Cancel current work, increment the submission generation, dismiss keyboard, clear transient query/result/owner selection, and restore the exact prior Discover state. |

The initial teaching examples are static product content:

| Example | Static metadata |
|---|---|
| `Ryan's favorite coffee spots` | `Ryan · favorites · coffee` |
| `quiet cafes for getting work done` | `coffee · quiet · work` |
| `friends' sunset hikes` | `friends · outdoors · sunset` |
| `date-night spots in Silver Lake` | `date · Silver Lake` |

Selecting one copies the phrase and submits it. These labels teach the grammar
of the search without spending tokens before the user asks for an answer.

## Concurrency and stale-result protection

- Hold the current search `Task` in the view model/state container and cancel it
  on a new submit, Clear, Back, mode change, sign-out, or account change.
- Assign a monotonically increasing `submissionID` before starting work.
- After every suspension point, require both `!Task.isCancelled` and equality
  with the active submission id before mutating UI/store-visible search state.
- Do not key remote work directly to every `placesQuery` edit. Remove the
  `.task(id: placesQuery)` LLM path for place search.
- Profile/member search may retain its existing debounced behavior because it
  does not invoke the Discover LLM.
- A completed old parse may populate only a schema-versioned cache if the
  request was not cancelled; it can never replace a newer visible response.

## Model, latency, and cost budget

The existing default, `gpt-5.4-nano`, is designed for simple high-volume work
such as classification and data extraction, supports the Responses API and
Structured Outputs, and is currently priced at $0.20 per million input tokens
and $1.25 per million output tokens. See the official
[model reference](https://developers.openai.com/api/docs/models/gpt-5.4-nano)
and [launch/pricing note](https://openai.com/index/introducing-gpt-5-4-mini-and-nano/).

REC-150 should keep `max_output_tokens <= 220`. At an illustrative 500 input
tokens and the full 220 output-token cap, one parse is about $0.000375, or
$0.375 per 1,000 uncached searches at current list pricing. Actual billed
tokens and price can change, so this is a planning envelope, not a fixed quote.

Before rollout:

- build a versioned golden set of at least 40 queries covering people,
  apostrophe-less possessives, categories, favorite/Been/Wanna, areas, tags,
  ambiguity, unsupported concepts, and prompt injection;
- compare the configured alias and a pinned snapshot on exact-plan accuracy,
  hard-invariant violations, p50/p95 latency, fallback rate, and tokens/cost;
- set `WANDER_AI_DISCOVER_MODEL` to the winning snapshot without changing the
  provider interface;
- keep the existing 3.5-second hard timeout initially and target p95 parse
  latency below 1.5 seconds on warm Edge Function requests;
- make no automatic client retry. A timeout falls back once; a new paid call
  happens only after an explicit user resubmit;
- target fewer than 1% hard-invariant repairs and fewer than 5% fallbacks in
  alpha. Exceeding either pauses rollout and triggers prompt/model review.

## Privacy, security, and observability

The Edge Function remains authenticated. API keys stay in server environment
variables. The OpenAI adapter keeps `store: false` and strict JSON schema
output. The model payload remains raw query + allowed enum schema only.

Record no raw query, copied owner/area text, handle, profile name, place name,
note, label value, address, coordinates, or token. Safe analytics properties:

| Event | Non-PII properties |
|---|---|
| `discover_search_opened` | entry surface |
| `discover_search_example_selected` | stable example id |
| `discover_search_submitted` | query-length bucket, source `typed|example`, schema version |
| `discover_query_parsed` | source `remote|cache|fallback`, latency bucket, recognized-facet count, opinion enum, unsupported count |
| `discover_search_results` | result-count bucket, exact-zero boolean, parse source |
| `discover_parse_failed` | bounded error code, retryable boolean, latency bucket |
| `discover_search_exited` | state `empty|draft|loading|results`, cancelled boolean |

Edge logs may include provider, model, bounded error code, latency, schema
version, and token usage when the provider exposes it. They must not include
request bodies. Extend the shared result type to carry input/output usage if the
provider response supplies it; do not block REC-150 on usage telemetry if the
adapter cannot expose it safely in the first slice.

## File-level implementation map

| File | Planned change |
|---|---|
| `supabase/functions/parse-discover-query/index.ts` | Return schema-v2 query plans; add opinion/sort/unsupported enums, semantic audit/repair, bounded logging, and backward-compatible fields. Export a handler/validator for tests. |
| `supabase/functions/parse-discover-query/index_test.ts` | Add request/auth/method tests, strict validation, prompt-injection cases, favorite/status invariants, semantic-empty behavior, and provider error mapping with a fake fetcher/parser seam. |
| `supabase/functions/_shared/ai/types.ts` and provider adapter only if needed | Optionally carry safe token usage; do not change provider selection or introduce a dependency. |
| `Wander/Services/DiscoverModels.swift` | Add `DiscoverQueryPlan`, intent/sort/unsupported enums, interpretation/source/owner-resolution types, typed match evidence, matches, and response. |
| `Wander/Services/Remote/SupabaseRepositories.swift` | Decode tolerant schema-v2 responses, preserve v1 compatibility defaults, and return explicit remote/fallback source. |
| `Wander/Services/WanderLocalStore.swift` | Add bounded schema-keyed cache, exact owner resolver, semantic enforcement, area matcher, favorite filter/ranker, evidence builder, and cancellation-safe response assembly. |
| `Wander/Features/Discover/DiscoverScreen.swift` | Add explicit search state, top Back/search layout, rich examples, submit-only task, Understood-as row, exact/fallback/unsupported/zero states, and typed `Matched:` metadata. Preserve save/place routes. |
| `Wander/Services/AnalyticsEvent.swift` | Add the search lifecycle events above. |
| `WanderTests/DiscoverParserTests.swift` | Golden deterministic-plan and invariant tests. |
| `WanderTests/RemoteRepositoryTests.swift` | Schema-v1/v2 decoding, source, fallback, invalid plan, timeout, and cancellation tests. |
| `WanderTests/WanderStoreTests.swift` | Owner resolution, favorite truth, evidence ownership, area/tag matching, ordering, exact zero, cache version/capacity, and stale-submission tests. |
| Discover UI/navigation contract tests | Assert Back/Clear/submit semantics, no parse-on-type path, teaching examples, state copy, Dynamic Type, and accessibility labels. |
| `docs/decisions.md` / `docs/open-questions.md` | Lock the LLM/evidence boundary and mark the cheap-parser path resolved. |

## Safe deployment order

1. **Golden corpus and typed contract**
   - Add query-plan enums, semantic invariants, fixtures, and deterministic
     expected outputs before changing runtime behavior.
   - Treat the golden corpus as source-controlled test data without real user
     queries, names beyond fixtures, or private place content.
2. **Backward-compatible Edge Function**
   - Return all existing filter keys plus new schema-v2 keys.
   - Existing app builds ignore unknown JSON keys, so deploy this superset first.
   - Run Deno tests and an authenticated alpha invocation using synthetic input.
3. **Tolerant native parser and executor**
   - Decode missing v2 keys to safe v1 defaults so the app also works during an
     Edge rollback.
   - Land deterministic owner/favorite/area/evidence logic and store tests.
4. **Search interaction UI**
   - Add the reversible state machine, static examples, submit-only behavior,
     result interpretation, typed metadata, and zero/fallback states.
5. **Alpha validation and model pin**
   - Run the golden corpus against the hosted configured model, record accuracy,
     latency, fallback, token, and cost results, then pin the selected snapshot.
   - Do not expose provider/model names in product UI.
6. **Visual and accessibility QA**
   - Capture active-empty, loading, populated, exact-zero, fallback, ambiguous
     owner, and Dynamic Type states on iPhone 17 Pro Max and iPhone 17e.
   - Verify keyboard Search, interactive keyboard dismissal, VoiceOver reading
     order, 44 pt targets, Back while loading, and Clear from results.

## Required tests

### Edge Function / model boundary

- Missing auth -> 401; wrong method -> 405; empty query -> local empty plan with
  no provider call.
- Query and copied short-text bounds remain enforced.
- Strict schema rejects extra fields and out-of-enum values.
- Prompt-injection text is treated as raw data and cannot change the response
  shape or request model/provider data.
- Each favorite synonym forces Been + favorite + owner-rating sort.
- Want-to-go synonyms cannot retain Been; explicit Been cannot retain Wanna.
- Schema-valid semantic-empty model output is repaired/rejected, not accepted as
  an intelligent parse.
- Provider missing, timeout, invalid JSON, missing output, 429, and 5xx map to
  bounded errors without leaking raw query.
- Synthetic golden queries meet the chosen accuracy threshold on the hosted
  alpha model before pinning.

### Native parser/store

- Remote, deterministic fallback, and cache produce the same hard invariants.
- `Ryan's`, `Ryans`, `@ryan`, exact display name, ambiguous Ryan, missing Ryan,
  and substring false-positive cases.
- Favorite admits only the evidence owner's Been row with rating >=4 or explicit
  favorite personal label; excludes 3.5, unrated/unlabeled, Wanna, and another
  owner's qualifying duplicate.
- Rating order uses the evidence owner's score, not group average; label-only
  ties use saved date then stable id.
- `LA` matches Los Angeles data rather than acting as no filter.
- Tags and every evidence item come from the same evidence row.
- Exact zero remains zero and carries an explicit relaxation query.
- Cache normalization, schema fingerprint invalidation, capacity eviction,
  account reset, and no caching of cancelled/invalid work.
- Older submission completion cannot mutate `lastDiscover...` or visible results.
- Existing people/member search, place selection, and social-save flows remain
  unchanged.

### UI and accessibility

- Tap search -> top Back/search mode; Back from empty, draft, loading, results,
  zero, and fallback always returns to Discover.
- Typing alone produces zero parser invocations; Return/example produces one;
  repeated normalized submit uses cache.
- Clear cancels and returns to active empty without exiting.
- Example cards show their static metadata and submit the exact associated query.
- `Understood as` and `Matched:` render only typed plan/evidence values.
- Hard evidence wraps instead of being silently truncated at Dynamic Type sizes.
- VoiceOver labels explain Back, Clear, Search, example intent, understood facets,
  result evidence, save, and add-visit actions without duplicate speech.
- Place-profile navigation and save/edit actions still use the existing paths.

### Validation commands for implementation

```bash
deno test --allow-env --allow-net supabase/functions/_shared/ai/structured-json.test.ts \
  supabase/functions/parse-discover-query/index_test.ts

xcodebuild test \
  -project Wander.xcodeproj \
  -scheme Wander \
  -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build \
  -project Wander.xcodeproj \
  -scheme Wander \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData-build \
  CODE_SIGNING_ALLOWED=NO
```

Use the exact available simulator OS at implementation time if the documented
18.6 runtime is unavailable.
The final implementation PR must record focused and full test counts plus the
hosted synthetic model-eval result. No database smoke-test claim is required
because this plan does not change schema/RLS/RPCs; an authenticated Edge
Function invocation is still required.

## Acceptance gates

- Search can be exited with one visible Back tap in every state, including while
  a parse is running.
- No LLM request is emitted until explicit submit/example selection.
- A cache miss emits no more than one provider request and no client auto-retry.
- Every result has evidence that proves each hard matched facet from one visible
  owner-place row.
- `Ryan's favorite coffee spots` cannot return Wanna Go, another owner's rating,
  or a silent broad fallback.
- Zero favorite results remain zero and offer only an explicit relaxation.
- No raw query or private place/social data appears in analytics or logs.
- Hosted golden-query accuracy, p95 latency, fallback, and invariant-repair gates
  pass before model snapshot pinning.
- Focused tests, full `xcodebuild test`, generic build, dual-device visual QA,
  Dynamic Type, and VoiceOver checks pass before merge.

## Implementation task breakdown

```jsonl
{"id":"REC150-E1","title":"Add Discover schema-v2 query plan and golden corpus","blocked_by":[],"deliverable":"Shared semantics, fixtures, favorite/status invariants, and deterministic expected plans"}
{"id":"REC150-E2","title":"Extend and test parse-discover-query","blocked_by":["REC150-E1"],"deliverable":"Backward-compatible strict Edge response, semantic audit, bounded failures, Deno tests"}
{"id":"REC150-E3","title":"Build native owner resolver, exact matcher, evidence, and ranking","blocked_by":["REC150-E1"],"deliverable":"Truthful DiscoverSearchResponse with bounded cache and store tests"}
{"id":"REC150-E4","title":"Implement reversible Discover search state and teaching empty state","blocked_by":["REC150-E3"],"deliverable":"Top Back/search mode, static examples, submit-only calls, Clear/Back behavior"}
{"id":"REC150-E5","title":"Render interpretation, exact zero, fallback, and per-result match evidence","blocked_by":["REC150-E2","REC150-E3","REC150-E4"],"deliverable":"Understood-as summary and verified Matched metadata in current result cards"}
{"id":"REC150-E6","title":"Run hosted eval, observability validation, and visual QA","blocked_by":["REC150-E2","REC150-E5"],"deliverable":"Pinned-model decision, cost/latency report, full tests/build, dual-device and accessibility evidence"}
```

REC-150 should remain `In Progress` through implementation, move to `In Review`
with the ready implementation PR and validation evidence, and move to `Done`
only after the requested behavior is merged. This plan itself does not mark the
feature complete.
