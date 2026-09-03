# REC-411 social importer stack assessment

Date: 2026-09-02

Status: Benchmark design and cost instrumentation complete; new live provider
runs await credentials

Scope: Instagram/TikTok acquisition, multimodal understanding, and POI
resolution

## Decision

Do not start post-training yet, and do not replace the whole stack at once.
First run a staged benchmark that changes one layer at a time.

The highest-value first experiment is Gemini 3.8 Flash with `MEDIUM` initial
thinking and `HIGH` reconciliation, using the same saved Apify evidence and the
same production prompt, grounding, and scorer. The production baseline is still
Gemini 3.5 Flash with `LOW` initial thinking and `MEDIUM` reconciliation. That
means the existing results do not answer whether more inference-time reasoning
alone fixes the observed city/place splitting, count reconciliation, caption
handle coverage, and local-geography errors.

Gemini 3.8 Flash keeps native video input and is currently less expensive per
input and reasoning-inclusive output token than Gemini 3.5 Flash. At the token
volume reported by the last eight-import run, the same-token estimate falls
from $0.269454 to $0.117816 for the run, or from $0.03368175 to $0.014727 per
import. Actual cost may differ because stronger reasoning changes billed
thinking/output tokens.

Google released Gemini 3.8 Flash on the date of this assessment and documents it
as its most intelligent Flash model. Gemini 3.7 Flash remains in the matrix as a
same-price stability control so a launch decision does not rest on release-day
claims alone.

Fable is useful as a ceiling test on the hard failures, not as the first
production candidate. Claude and OpenAI models accept images but not native
video, so a fair test must give them normalized keyframes plus a transcript.
That adds a preprocessing system and makes their token, latency, and accuracy
figures non-comparable with a direct-video Gemini run unless both are reported.

## What the prior run already establishes

The grounded eight-case Apify/Gemini replay acquired all eight posts and found
121/121 required mentions after one deterministic fallback. Six of eight hint
sets were exact. Gemini itself succeeded on seven of eight cases. This is enough
evidence that the problem is tractable and that a wholesale acquisition rewrite
is not the first move.

POI resolution is the clearest measured bottleneck. Only 17/121 required names
survived the MapKit selection stage in the prior replay. That result mixes
provider lookup quality with rec.me's matching threshold and ambiguity rules,
so the next resolver benchmark must persist top candidates and separately score
lookup availability, correct top-one, correct top-three, accepted selection,
and false acceptance.

The committed corpus is only eight posts. It is useful for regression and hard
case debugging, but it is too small and too concentrated around one 100-place
post to select a provider or justify post-training.

## Benchmark architecture

Run the evaluation in four stages. Do not multiply every scraper by every model
by every resolver.

### Stage 1: understanding and reasoning

Freeze one validated acquisition envelope per post and replay identical media,
caption, accessibility text, platform location, and profile-handle aliases.
Score candidates before POI resolution.

| Variant | Input treatment | Purpose |
|---|---|---|
| Gemini 3.5 Flash, LOW/MEDIUM | Native images/video | Production baseline |
| Gemini 3.5 Flash, MEDIUM/MEDIUM | Native images/video | Isolate reasoning level |
| Gemini 3.7 Flash, MEDIUM/HIGH | Native images/video | Same-price stability control |
| Gemini 3.8 Flash, LOW/MEDIUM | Native images/video | Isolate model generation |
| Gemini 3.8 Flash, MEDIUM/HIGH, static 2 FPS | Native images/video | Primary drop-in candidate |
| Gemini 3.8 Flash, HIGH/HIGH, static 2 FPS | Native images/video | Gemini quality ceiling |
| Gemini 3.8 Flash, MEDIUM/HIGH, agentic video | Native video through Interactions API | Video architecture challenger |
| GPT-5.6 Terra, high | Keyframes plus transcript | Non-native-video challenger |
| GPT-5.6 Sol, high/max | Keyframes plus transcript | OpenAI quality ceiling |
| Claude Opus 5, high | Keyframes plus transcript | Claude production challenger |
| Claude Fable 5.1 | Hard-case slice only | Capability ceiling |

Run the six static Gemini configurations over the full corpus. Run agentic video
on the reel/video subset because it requires the Interactions API rather than a
drop-in model-name change. Google reports that agentic processing can improve
long-form quality and reduce video tokens, but also says static processing is
better for short clips or frame-level precision. Social reels with briefly
flashed place names therefore need measurement, not a default assumption.
Advance only the best two Gemini configurations and the baseline. Run Terra,
Sol, Opus, and Fable first on the hard slice; expand only a challenger that
materially beats the best Gemini configuration after preprocessing cost and
latency are included.

Required understanding metrics:

- exact place set per post;
- place-level precision and recall;
- at-least-one useful place per post;
- false city/region/hashtag/attribution rate;
- declared-count compliance without truncating real distinct destinations;
- correct pairing of venue plus locality;
- caption-handle recovery;
- native-video or keyframe/transcript evidence coverage;
- p50/p95 latency, attempts, failures, input tokens, output tokens, thinking
  tokens, and dollars;
- dollars per exact post and dollars per post with at least one correct place.

Use deterministic temperature/settings, record the exact model ID and thinking
level, and run each finalist three times. One run cannot measure variance or
provider reliability.

### Stage 2: acquisition

Compare Apify's current broad Instagram/TikTok actors with Bright Data on the
same public URLs. The understanding model must be disabled for this stage.

Measure ordered media count, carousel completeness, downloadable video,
caption completeness, platform POI/location fields, profile-handle identity
data, HTTP success, p50/p95 latency, and provider cost. Run each URL three times
because scraper tail reliability matters more than the published per-record
price.

Keep Apify unless Bright Data materially improves strict evidence completeness
or p95 reliability. The prior corpus already showed 8/8 strict Apify acquisition
success, and the measured Apify spend was $0.1387 across eight imports. A small
catalog price difference cannot compensate for missing a reel or carousel
asset.

### Stage 3: POI resolution

Replay the same grounded place hints and geography into each resolver. No model
or scraper calls belong in this stage.

Test:

1. current Google Places Text Search and current rec.me matcher;
2. Google Places with a revised locality-aware query and top-three review
   behavior;
3. Apple MapKit as a fallback or challenger;
4. Google's experimental Maps Resolution API on a non-production track; and
5. Gemini with Google Maps grounding only if its returned place references can
   be scored and attributed independently from the extraction answer.

The corpus labels must add expected branch identity, place ID where known,
city/region, and coordinates. Name-only scoring cannot detect the Texas result
for an LA post or distinguish a landmark from a similarly named business.

Required resolver metrics are correct top-one, correct top-three, physical
branch accuracy, null precision, false-city rate, lookup failure rate, accepted
selection rate, query count, latency, and cost per correct resolved POI.

### Stage 4: end to end

Run only the two or three winning composed stacks over a 50-100 post launch-gate
corpus. Stratify it by caption-only, single image text, carousel text, native
video text, speech, handles, explicit place plus city, city-list posts,
attributions, natural features, and ambiguous branches.

The launch gate should require high per-post usefulness and exact-set quality,
not only aggregate place recall. A 100-place post must not hide repeated failure
on ordinary one-to-eight-place imports.

## Current token-price comparison

Prices are USD per one million tokens, checked against official provider pages
on 2026-09-02. Output prices include billed reasoning/thinking tokens where the
provider groups them that way. They exclude batch discounts, cache discounts,
media preprocessing, scraper calls, retries, and POI lookup.

| Model | Input | Output including reasoning | Native video |
|---|---:|---:|:---:|
| Gemini 3.5 Flash | $1.50 | $9.00 | Yes |
| Gemini 3.8 Flash | $0.75 | $3.75 | Yes |
| Gemini 3.7 Flash | $0.75 | $3.75 | Yes |
| GPT-5.6 Luna | $0.20 | $1.20 | No |
| GPT-5.6 Terra | $2.00 | $12.00 | No |
| GPT-5.6 Sol | $4.00 | $20.00 | No |
| Claude Sonnet 5 | $2.00 | $10.00 | No |
| Claude Opus 5 | $5.00 | $25.00 | No |
| Claude Fable 5.1 | $10.00 | $50.00 | No |

Gemini 3.8 and 3.7 Flash pricing is promotional through 2026-12-31; the listed
standard price then becomes $1.50 input and $7.50 output. The checked-in
`model-pricing.json` retains dated official source links, and
`model-cost-comparison.mjs` turns recorded run usage into a reproducible
same-token table.

At the historical workload of 44,348 input tokens and approximately 22,548
output/thinking tokens across eight imports:

| Model | Same-token cost per import |
|---|---:|
| Gemini 3.5 Flash | $0.03368175 |
| Gemini 3.8 Flash | $0.01472700 |
| Gemini 3.7 Flash | $0.01472700 |
| GPT-5.6 Luna | $0.00449090 |
| GPT-5.6 Terra | $0.04490900 |
| GPT-5.6 Sol | $0.07854400 |
| Claude Sonnet 5 | $0.03927200 |
| Claude Opus 5 | $0.09818000 |
| Claude Fable 5.1 | $0.19636000 |

These rows do not rank end-to-end cost. The non-Gemini models require frame and
speech preprocessing and can consume a different number of image and reasoning
tokens. Actual run accounting is authoritative.

## Non-token costs that can dominate

The current Google Places Text Search Pro fields are billed at $32 per 1,000
requests after the 5,000-request monthly free cap. Eight independent hint
queries would therefore be $0.256 per import after the cap, before retries. That
is much larger than the historical Gemini model cost. Reducing duplicate or
geography-only hints, batching where supported, and measuring resolver queries
per accepted POI are direct cost work, not cleanup.

Gemini Maps grounding and Google Maps Grounding Lite have separate per-query
pricing and may issue or represent more than one search operation. Their billing
unit must be recorded from actual responses rather than assumed to equal one
import.

## Post-training decision gate

Consider tuning only after the 50-100 post corpus shows a stable, repeated error
class that remains after the strongest prompt/model/reasoning configuration and
is supported by enough clean examples. Candidate classes include city-versus-
venue classification, declared-count reconciliation, or attribution handling.

Do not train on final Google/MapKit selections as if they were truth. Store
source evidence, the intended extracted mention, locality, physical POI label,
adjudication reason, and model output separately. Otherwise resolver mistakes
will become extraction training data.

## Immediate execution order

1. Run the six static Gemini configurations against the saved eight-case
   acquisition fixtures, recording quality, latency, attempts, and token usage.
   Run 3.8 agentic processing on the video subset as a separate API-path test.
2. Adjudicate the known Ojai/LA failures and add branch/locality truth.
3. Expand the corpus to 50-100 posts before provider selection.
4. Run the hard slice through Terra, Sol, Opus, and Fable using one frozen
   keyframe/transcript package.
5. Benchmark Apify versus Bright Data acquisition separately.
6. Benchmark Google Places, locality-aware top-three behavior, MapKit, and the
   experimental Resolution API separately.
7. Compose only the winning layers and repeat each finalist three times.

The live runs require provider credentials in the local process environment.
The evaluator never writes those credentials into manifests or result files.
