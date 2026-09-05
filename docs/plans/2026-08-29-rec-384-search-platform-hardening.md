# REC-384 Search Retrieval Platform Hardening

Status: implementation branch; no hosted mutation

Canonical product and architecture contract: [`docs/specs/search-featured-retrieval-platform.md`](../specs/search-featured-retrieval-platform.md)

## Why this work exists

Hybrid Search already outperforms lexical-only retrieval in the real-data blind evaluation, but the evaluation harness and scorecards were stranded on an old branch, Search waited for semantic retrieval before displaying remote results, and the live dashboard could not connect retrieval stages to selection or action.

This branch turns that prototype into a maintainable platform without changing the successful architecture:

- deterministic parsing and structured filters;
- PostgreSQL lexical and semantic candidate retrieval;
- deterministic reciprocal-rank fusion;
- explicit Featured ranking from network, taste, and community signals;
- no LLM in the ranking hot path and no semantic Featured rollout yet.

## Deliverables

1. Keep the real-data Search and Featured relevance labs in the repository with one-command tests and scoring.
2. Publish lexical Search results as soon as they arrive, then replace them with fused results when semantic retrieval completes.
3. Correlate each submitted Search request across parser, retrieval, selection, reformulation, and successful action using a random request ID.
4. Add privacy-safe Search Retrieval dashboard definitions for stage latency, provider/rank selection, and submitted-to-action outcomes.
5. Update the canonical spec and decisions so another maintainer can understand what is live, what was evaluated, and what remains intentionally deferred.

## Guardrails

- Never send raw queries, place or profile identifiers, candidate lists, addresses, notes, or coordinates to analytics.
- Preserve lexical-only behavior if semantic retrieval is disabled, unavailable, empty, or slow.
- Keep Featured on its explicit ranker until a blind evaluation shows a semantic alternative is better.
- Do not add people embeddings, an LLM reranker, a universal Search/Featured ranker, or a multi-turn chat surface as part of this work.
- Do not deploy functions, apply database migrations, apply the PostHog dashboard, or change global feature flags from this branch.

## Progressive-delivery contract

For a submitted place query, the app launches lexical and semantic retrieval concurrently. It awaits lexical retrieval first and may publish a `lexical` partial result while semantic work continues. The terminal result is one of:

- `fused`: lexical and semantic candidates were combined;
- `lexical_final`: lexical results remain authoritative because semantic retrieval was disabled, unavailable, failed, or empty;
- `semantic_recovery`: lexical retrieval failed or was empty and semantic retrieval supplied the terminal result.

The existing cancellation token still prevents an older request from replacing a newer query.

## Validation before review

- relevance-lab unit tests;
- analytics contract and privacy checks;
- focused `TrustedPlaceSearchTests`, including lexical-before-semantic delivery;
- full relevant iOS test suite when local disk capacity permits;
- `git diff --check` and a manual privacy review of every new analytics property.

## Progressive rollout after review

This branch does not alter the currently enabled global semantic Search default. If runtime behavior needs to be de-risked further, the same typed configuration can move through lexical-only, staff testing, cohort rollout, and global rollout without maintaining a Joe-specific server flag. The existing device override remains sufficient for local Xcode comparison.

Future ranker or embedding-policy changes should gain versioned configuration only when the first real operational need exists; a database-backed registry is deliberately deferred.

## Historical validation outcome (2026-08-29; before current-main integration)

- Search/retrieval unit tests: 20 passed, including lexical-before-semantic delivery and the existing 1,000-memory p95 guard.
- Analytics privacy test: passed; opaque request IDs remain allowed while candidate/place/profile IDs and raw queries are rejected.
- Managed dashboard checks: 6 passed across eight sections and 17 insights.
- Relevance lab: 27 passed after separating the richer lexical document from the minimized production semantic document.
- A read-only production-document pool refresh found 17 top-five-union query/candidate judgments that were not covered by the historical pool. No new quality score is claimed until those candidates are graded. The generated pool remains an ignored local artifact.
- The full iOS unit run executed 1,524 tests and reported eight failures in pre-existing Map/widget source-contract tests outside this branch's changed files. The focused Search and analytics gates pass; the unrelated failures are recorded rather than folded into REC-384.

## Previous-main integration (2026-09-04)

The branch was refreshed against `024ddb9` (build 170). REC-424's Apple Maps
fallback, eligibility, source labels, physical dedupe, and three-corpus ranking
remain authoritative. Each progressive rec.me response changes only the rec.me
input to that ranking policy. Selection rank reflects the combined list and
provider attribution includes MapKit; external timing stays on the existing
remote-results event with the opaque submission ID.

Cancellation is checked before lexical publication and final return, including
providers that complete after cancellation. A stale request-plan failure cannot
clear a newer request's loading/task state. Final empty responses end loading.
Conversion attribution is captured before a save suspends so a later selection
cannot receive the prior save's conversion.

Fresh-checkout relevance tests exercise synthetic fixtures. Historical real
scorecards still require private ignored pool keys and judgments to reproduce;
they are not newly validated quality claims. Hosted Supabase checks cannot run
on this Mac because its recorded operations credentials and registry are absent.
No hosted rollout or dashboard application has been performed.

Fresh validation of the integrated code completed 1,804 unit tests: 1,790 passed
and 14 test cases failed (17 assertions). All 51 Search tests passed, including
the 1,000-memory p95 gate. Clean `024ddb9` completed 1,798 unit tests and failed
the same 14 cases plus one list-projection case; no PR-only unit failures were
found. The standalone relevance suite passed 27 tests and dashboard checks
passed six tests (eight sections, 17 insights). The Search screenshot smoke
passed. The broader UI sweep was interrupted after the unit baseline comparison;
its remaining UI coverage is not represented as passing. The PR and Linear record
contain the final focused-UI outcomes and exact restart artifacts.

## Current-main integration (2026-09-05)

The branch now includes `c520292` (REC-409 import redesign). Smart-parser filter
refinement now replans rec.me as well as Apple Maps, clearing stale candidates
and preserving the existing remote eligibility restrictions. Effective request
equality avoids redundant restarts. The dashboard excludes legacy events without
a submission ID from request outcome counts.

See the [integration and benchmark report](../evals/2026-09-05-search-integration.md)
for controlled delivery measurements, a three-corpus query example, current-main
regression comparison, and the outstanding live-service verification.
