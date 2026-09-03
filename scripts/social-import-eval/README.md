# REC-120 social importer evaluator

This is an isolated, non-production benchmark for public Instagram and TikTok
place extraction. It preserves provider responses as raw JSON, converts them to
one evidence contract, extracts grounded place hints, optionally resolves those
hints with Apple MapKit, and scores only manually labeled cases.

The evaluator intentionally separates two different jobs:

1. **Acquisition** collects captions, ordered carousel assets, reel/video
   assets, accessibility text, and provider location metadata, then measures
   transport separately from strict completeness.
2. **Understanding** reads that evidence and returns grounded place mentions.

A scraper can succeed at acquisition while still missing text shown only in a
video. A video model can understand a downloaded video while being unable to
fetch the Instagram or TikTok URL. End-to-end variants must compose both jobs.

## Safety and data handling

- Inputs are explicit public URLs only. Private/account-library scraping is out
  of scope.
- API credentials are read from the process environment and are never written
  to output.
- Swift helpers compile in process-private temporary directories and receive a
  minimal environment that excludes provider credentials.
- Live run directories are ignored by Git. They can contain public captions,
  creator metadata, expiring media URLs, transcripts, and provider JSON; review
  them before sharing.
- The committed corpus stores URLs and place labels, not downloaded media or
  raw provider payloads.
- The runner never creates cloud projects, enables billing, or accepts provider
  terms.

## Quick start

From `scripts/`:

```bash
npm run test:social-import-eval
npm run eval:social-import -- --providers current,current-improved --resolve none
```

Compare current published token prices against usage from a completed run:

```bash
npm run eval:social-import:cost -- \
  --input-tokens 44348 \
  --output-tokens 22548 \
  --imports 8
```

The calculator reads `model-pricing.json`, whose prices and official source
links are dated. Its result is deliberately a same-token comparison, not a
prediction that every provider will use the same number of tokens. Native video
support, frame extraction, transcription, retries, caching, acquisition, and
POI resolution must be measured separately in live runs.

After a scoring-only change, regenerate an existing run's `results.json` and
summaries without reacquiring social media or rerunning understanding. Every
invocation appends a `score-contract-v4` transform and chained input/output
result hashes to the run manifest:

```bash
npm run eval:social-import:rescore -- social-import-eval/runs/<run>
```

To rerun only MapKit against saved understanding hints, without reacquiring a
post or making a paid model call:

```bash
npm run eval:social-import:rescore -- \
  social-import-eval/runs/<run> --reresolve-mapkit
```

The source run must have been created with `--resolve mapkit`; the command fails
closed for resolver-none runs. Batch replays pace MapKit requests and retry only
transient server/throttling errors so replay pressure is not counted as POI
candidate-quality loss.

To rebuild hints from saved Gemini structured candidates and rerun MapKit, with
no new scraper or model request:

```bash
npm run eval:social-import:rescore -- \
  social-import-eval/runs/<run> \
  --rebuild-understanding-hints \
  --reresolve-mapkit
```

For a MapKit-backed run, hint rebuilding requires re-resolution so stale POI
results cannot be reported against changed extraction output. The run manifest
records both replay operations, the exact applied transforms, chained input/output
result hashes, the fallback-assisted case count, and that they made no paid
acquisition or understanding calls.

Add `--resolve mapkit` to use the same POI provider and a scoring mirror of
`ManualPlaceSearchPlan` / `PlaceImportCandidateMatcher` from the iOS app. The
first run compiles a credential-isolated Swift helper in a private temporary
directory.

Useful options:

```text
--cases <comma-separated case ids>
--providers <current,current-improved,brightdata,apify>
--understanders <deterministic,apple-vision,apple-vision-keyframes,gemini,google-video,
                 aws-rekognition-transcribe,azure-video-indexer>
--resolve <none|mapkit>
--corpus <path to corpus JSON; defaults to the committed corpus.json>
--out <directory>
--fixture-dir <directory of saved acquisition JSON; offline by default>
--allow-network-after-fixture
                 explicitly allow media/model/MapKit network after fixture load
```

Use a separate corpus for a private launch-gate or one-off live evaluation
without editing the committed benchmark. The selected corpus path and SHA-256
are recorded in the run manifest:

```bash
npm run eval:social-import -- \
  --corpus /private/tmp/rec120-launch-gate.json \
  --providers apify \
  --understanders gemini \
  --resolve mapkit \
  --out /private/tmp/rec120-launch-gate-run
```

Keep private corpora and their live outputs outside the repository. The runner
does not copy API credentials into the manifest, but source captions, provider
payloads, and expiring media URLs remain sensitive run artifacts.

### Production-parity diagnostic

`production-parity.ts` is the narrow diagnostic for the current server pipeline.
Unlike the historical provider comparator above, it directly composes the
production source parser, Apify acquisition and profile enrichment, media
ingestion, Gemini understanding, and grounding modules. Cases run serially and
use the production 112-second per-case deadline.

Supply credentials through the process environment, create a new private output
directory, and run:

```bash
deno run \
  --allow-env=APIFY_TOKEN,GEMINI_API_KEY,GEMINI_MODEL \
  --allow-read \
  --allow-write=/private/tmp/rec120-production-parity \
  --allow-net \
  scripts/social-import-eval/production-parity.ts \
  --corpus /private/tmp/rec120-launch-gate.json \
  --out /private/tmp/rec120-production-parity \
  --fixture-dir /private/tmp/rec120-launch-gate.vUN2Dx \
  --model gemini-3.8-flash \
  --thinking medium \
  --reconciliation-thinking high
```

The model and thinking flags are optional. Omitting them preserves the
production baseline of `gemini-3.5-flash`, `LOW` initial thinking, and `MEDIUM`
reconciliation thinking. The manifest records the selected configuration, and
each successful case records bounded prompt, cached-prompt, response, thinking,
and total token counts. This makes model quality, latency, and actual cost
comparable without changing the app or the deployed Edge Function.

`--fixture-dir` accepts either an evaluator run directory or its `raw/`
subdirectory. It reuses each case's validated `apify.json` acquisition envelope
and passes the saved raw dataset through the current production Apify normalizer.
It never falls back to a new post scrape when a fixture is missing or failed.
Private Apify key-value-store media remains usable because the production media
ingestor reconstructs its narrowly scoped authorization header from the
in-memory `APIFY_TOKEN`; that header is never serialized. Profile-handle
enrichment and Gemini are still live provider calls. Omit `--fixture-dir` only
when a fresh main acquisition is intentionally wanted.

The output directory must be new or already private to its owner. The runner
refuses to overwrite an existing manifest or result set. It writes only:

- `manifest.json`: corpus hash, bounded case IDs, and completion counts;
- `results.json`: source kind, acquisition/media/profile stage summaries,
  structured Gemini candidates and post context, grounded hints, and bounded
  error codes.

It deliberately omits source URLs, raw captions and titles, profile aliases,
media URLs, media bytes, and provider responses. Candidate and hint strings that
look like URLs are redacted, and every write fails closed if either provider
credential appears in the serialized output. The diagnostic does not run
MapKit; final POI resolution remains the iOS trust-boundary stage.

Media or Gemini failures preserve the same deterministic fallback hints returned
by the production handler. Score a completed diagnostic offline with:

```bash
node scripts/social-import-eval/score-production-parity.mjs \
  --corpus /private/tmp/rec120-launch-gate.json \
  --results /private/tmp/rec120-production-parity/results.json \
  --manifest /private/tmp/rec120-production-parity/manifest.json \
  --out /private/tmp/rec120-production-parity/score-summary.json
```

The scorer verifies the exact corpus SHA-256, requires the manifest and results
to contain the complete corpus case-ID set, and refuses older media/Gemini
failure records that omitted their production fallback hints. It joins cases by
ID and applies the evaluator's existing name/alias and forbidden-label scoring
contract to final `grounding.hints`. The new output file is owner-only and is
never overwritten. It contains bounded per-case scores and aggregate macro,
micro, post-success, forbidden-hit, and exact-set metrics, but no source URLs,
raw evidence, prediction strings, provider payloads, or credentials. This is
server hint accuracy only; it does not claim final MapKit POI identity accuracy.

The committed corpus currently contains eight manually labeled public posts and
121 required place mentions. Summary JSON includes both macro metrics (every
post has equal weight) and micro metrics (every place mention has equal weight),
plus post-level at-least-one and exact-set rates. Ground-truth matching accepts a
full labeled name embedded in a longer hint, but never accepts a truncated
prediction merely because it is a substring of the label.

Acquisition transport means the provider returned usable evidence. Strict
completeness additionally requires every expected modality and the corpus's
minimum media count by kind to survive a bounded HTTPS/redirect/byte/MIME probe.
The runner attempts every acquired media asset relevant to the case and records
every probe, even though the strict gate uses the declared minimum rather than
requiring every extra asset to succeed. Understanding and extraction are scored
separately from both acquisition measures.

Runs with `--resolve none` report extraction/hint metrics only. Their MapKit
selected-name precision, recall, post-success, and exact-set fields are
deliberately `null`; an unresolved hint is not silently treated as a selected
candidate. Even in MapKit mode the corpus currently verifies only the selected
name/alias, not physical branch identity, address, provider ID, or coordinates.
Expected-modality summaries group whole cases, can overlap, and do not claim
that a particular modality produced each correct label.

The default output is `scripts/social-import-eval/runs/<timestamp>/`:

```text
manifest.json                 exact corpus/provider configuration
raw/<case>/<provider>.json    untouched JSON response or local adapter record
results.json                  normalized evidence, hints, POI candidates, timing, errors
summary.json                  aggregate and per-modality metrics
summary.md                    compact human-readable comparison
```

## Verified credentialed run

The gitignored `apify-gemini-smoke-2026-08-28-verified` run exercised two cases
through Apify acquisition, Gemini understanding, and MapKit resolution. It
reached 100% transport, strict completeness, understanding success, and
required-place recall. Hint exact-set success was 0/2, and MapKit selected a
candidate for 50% of hints.

The subsequent eight-case `apify-gemini-full-2026-08-28` run measured:

- 100% acquisition transport and strict completeness;
- 87.5% understanding success after one case exhausted three HTTP 503 attempts;
- 39.7%/87.3% macro and 75.5%/92.6% micro hint precision/recall;
- 7/8 posts with at least one required hint and 0/8 exact hint sets;
- 50.0%/53.8% selected-name macro precision/recall;
- 61.4% MapKit lookup health and 19.9% candidate selection; and
- 151.715 seconds mean end-to-end latency.

Those POI figures are a v4 re-resolution of the frozen Gemini hints, not a new
paid acquisition/model run. The helper paces batch searches and retries only
transient MapKit server/throttling errors; an unpaced replay was discarded
because its bulk pressure produced 136 `loadingThrottled` failures.

The selected-name score verifies only names/aliases, not physical branch
identity. One initial transport timeout and one initial HTTP 503 recovered via
retry, while the three-503 case remained failed in the frozen benchmark.
Neither run establishes launch readiness.

A later no-paid-call replay, saved as
`apify-gemini-grounded-replay-2026-08-28`, rebuilt hints from the frozen Gemini
structured candidates, used bounded deterministic evidence only for the one
failed Gemini case, required matching successful media ingestion for model-only
image/video/speech claims, and reran MapKit with the v5 resolver mirror. The
final rebuild is recorded as `grounded-hints-v3`. It measured:

- 93.8%/100% macro and 97.7%/100% micro hint precision/recall;
- 121/121 required mentions, 3 scored extras, and 6/8 exact hint sets;
- 100% video-text and speech scenario-group recall, including the failed
  multi-place TikTok request recovered from its numbered caption;
- 64.8% MapKit lookup health and 17.2% candidate selection; and
- 86.4%/14.0% micro selected-name precision/recall, with 17/121 required names
  surviving selection and 4/8 exact selected-name sets.

The three scored extras are `Castle Crags Wilderness`, `Shasta-Trinity National
Forest`, and `Wind River Brewing`; all are plausible destinations present in
the source evidence, so they also expose corpus-label ambiguity. This replay is
strong evidence for grounded filtering and failure fallback, not a new live
Gemini reliability result. Its 87.5% understanding-success rate and original
model latency are unchanged, and the corpus still cannot verify branch identity.

## Provider environment variables

Provider adapters fail closed with a structured `not_configured` result when
their requirements are absent.

```text
BRIGHTDATA_API_TOKEN
BRIGHTDATA_INSTAGRAM_DATASET_ID
BRIGHTDATA_INSTAGRAM_REELS_DATASET_ID
BRIGHTDATA_TIKTOK_DATASET_ID

APIFY_TOKEN
APIFY_INSTAGRAM_ACTOR_ID
APIFY_INSTAGRAM_REEL_ACTOR_ID
APIFY_TIKTOK_ACTOR_ID

GEMINI_API_KEY
GEMINI_MODEL                  optional; adapter default is documented in code
GEMINI_MAX_ATTEMPTS           optional; default 3, hard maximum 5
GEMINI_RETRY_BASE_MS          optional bounded retry-backoff base
GEMINI_RETRY_MAX_MS           optional bounded retry-backoff ceiling

GOOGLE_CLOUD_ACCESS_TOKEN
```

No `.env` file is required or read by the runner. This keeps credentials out of
the repository and makes CI/provider injection explicit.

The Apify adapter invokes actor runs through `/v2/actors`, disables the actor's
AI video description, and does not request, fetch, ingest, or score vendor
transcript artifacts. Apify STT remains a documented capability to evaluate
separately, not a measured feature of this harness. If a vendor nevertheless
returns an AI scene description, it is retained as separately typed vendor-model
evidence and cannot feed deterministic extraction or independently ground
Gemini output.

Private Apify key-value-store media can require the same process token used for
acquisition. The runner attaches that Bearer header only to the exact Apify API
host, keeps it non-enumerable so it cannot enter JSON output, and removes it on
cross-host redirects.

## Media understanding behavior

- Every acquired image/video gets an ingestion attempt and per-asset diagnostic
  where the selected understanding adapter accepts that media kind.
- Gemini attempts every acquired image and video, but sends only successful
  fetches within bounded per-item sizes and one bounded inline-request total.
  Media parts precede the untrusted creator-text prompt.
- Gemini uses the current nested JSON `responseFormat`. The schema intentionally
  omits `maxItems`: a synthetic A/B request changed from HTTP 400 with
  `maxItems: 150` to HTTP 200 after removing it. A JSON response that does not
  match the required candidate schema is a recorded model failure and invokes
  deterministic fallback.
- Gemini retries transport failures and HTTP 408, 429, and 5xx responses with a
  bounded attempt count and jittered/`Retry-After`-aware backoff. Attempt
  metadata is preserved without credentials.
- A successful Gemini response contributes only schema-validated destination or
  itinerary candidates. Caption and tagged-location candidates must match
  evidence that exists independently outside the model's own evidence sentence.
  Image-, video-, and speech-only candidates may instead carry explicit
  `model_attested_media_evidence` only when a matching image/video asset was
  successfully ingested into the model request; the model's evidence text alone
  is insufficient. Independent name matching uses token boundaries so `Park`
  cannot be grounded by `parking`. Raw heuristic hints are not merged into a
  successful model result. A failed Gemini response uses bounded deterministic
  extraction from acquired evidence and records that fallback explicitly.
- Google Video Intelligence attempts every acquired video child, issuing one
  annotation operation per successfully fetched video. It does not stop after
  the first video. Stills remain the responsibility of a still-image path.
- A partial ingestion remains visible as `partial` or `failed`; media transport,
  strict completeness, understanding, hint extraction, and POI selection are
  distinct result stages.

## Relationship to production code

- `current` approximates the observable behavior of
  `PublicSocialImportMetadataProvider`: Instagram public HTML plus selected
  embedded JSON, and TikTok oEmbed. It is JavaScript evaluation code, not an
  execution of the production Swift importer.
- `current-improved` tests a bounded parser hypothesis: accept matching single
  posts and reels, preserve video URLs, and traverse all matching media rather
  than requiring `carousel_media`. It is also an evaluation approximation.
- `apple-vision` mirrors the app's accurate still-image OCR settings.
  `apple-vision-keyframes` adds 250 ms video sampling (bounded to 240 frames) as
  a local, zero-API-cost comparator; it is evaluation code, not app code.
- Deterministic hint extraction approximates the production evidence ordering
  and trust model in `SocialPlaceHintExtractor`.
- The v5 MapKit benchmark mirror adds production-style provider-name query
  variants, coordinate/region hints, exact-country and area-conflict filters,
  production pre-limit result ranking, OCR-specific near-spelling handling,
  creator-qualified venue-name matching, and the candidate clear-lead threshold.
  It also ports the production LA/Georgia ambiguity rules and District of
  Columbia region handling, covered by executable parity fixtures. It remains
  copied evaluation logic; production Swift regression fixtures are the
  authoritative parity check.

The evaluator does not mutate Supabase, provider accounts, or user place data.
The production path is separate and feature-flagged: an authenticated iOS
import may call the `social-import-understand` Supabase Edge Function, which
acquires bounded Instagram or TikTok evidence with Apify and asks Gemini for
grounded place hints. The app still resolves those hints through its existing
MapKit trust boundary before presenting or saving a place. Missing
configuration, quota admission, acquisition, media, model, or deadline failures
fall back to the existing device-side parser instead of treating a provider
guess as a canonical POI.
