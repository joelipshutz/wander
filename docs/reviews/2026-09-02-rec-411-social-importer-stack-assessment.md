# REC-411 social importer stack assessment

Date: 2026-09-02

Status: First live 24-post acquisition benchmark and 23-post frozen-input model
comparison complete; repeated reliability and canonical POI resolution remain
open

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

The first live comparison now supports advancing Gemini 3.8 Flash at
`MEDIUM/HIGH` to the repeatability and resolver gates. It exceeded Gemini 3.5
Flash at `HIGH/HIGH` on operational completion, source-adjudicated extraction,
elapsed run time, and measured model cost. This is not yet authorization to
remove the runtime model switch or declare the composed importer launch-ready:
the result is one pass, only eight cases currently have adjudicated labels, and
the final POI identity stage was deliberately excluded.

Fable is useful as a ceiling test on the hard failures, not as the first
production candidate. Claude and OpenAI models accept images but not native
video, so a fair test must give them normalized keyframes plus a transcript.
That adds a preprocessing system and makes their token, latency, and accuracy
figures non-comparable with a direct-video Gemini run unless both are reported.

## 2026-09-04 live benchmark

### Corpus and controls

The acquisition corpus contains 24 public Instagram URLs selected for difficult
caption handles, single-image text, long carousels, native reel text, speech,
city-versus-venue context, natural features, and long declared lists. Eight are
known acceptance cases and 16 were independently sourced before provider calls.
The candidate corpus and raw provider payloads remain private evaluation
artifacts. They are not production data or committed fixtures.

Both model configurations received the same 23 Apify-usable acquisition
envelopes, profile aliases, and byte-identical frozen media inputs. The frozen
set contained approximately 241 MiB of images and video. Input hashes matched
before and after every replay. The initial 8,192-token diagnostic ceiling caused
artificial truncation, so only failed cases were retried with the production
16,384-token ceiling. Transport-only failures received one bounded clean retry.
Final metrics below merge a successful retry only into the case that originally
failed; they do not rerun or cherry-pick already successful cases.

### Acquisition: Bright Data versus Apify

| Metric | Bright Data | Apify |
|---|---:|---:|
| Usable records | 24/24 | 23/24 |
| Shared captions matching after whitespace normalization | 23/23 | 23/23 |
| Shared ordered media counts matching | 23/23 | 23/23 |
| Shared reel bytes matching by length and prefix digest | 11/11 | 11/11 |
| Shared image cases with the higher first-image resolution | 0/12 | 12/12 |
| Measured acquisition charge | Dashboard reported $0 consumed | $0.0621 for the 24-URL batch |

Apify's only acquisition miss was a restricted reel that Bright Data returned
with usable video. Bright Data returned more tagged-user metadata in three
carousels. Apify returned a platform location on five shared reels where Bright
Data did not. Bright Data's inspected carousel images were capped at a 640-pixel
side while Apify returned 1,080-4,096-pixel originals; the actual reel media was
the same from both providers.

This does not support choosing one provider for every media type. Use Bright
Data first for reels and fall back to Apify because their shared reel bytes were
identical while Bright recovered the only provider-level miss. For `/p/` posts,
run both acquisitions in parallel and merge Bright caption, slide-scoped tag,
and accessibility metadata with Apify's higher-resolution image assets. Either
successful result may carry the import when the other fails. This preserves the
measured strengths of both providers without paying for a second Gemini pass.

### Reasoning: Gemini 3.5 versus 3.8

| Metric after bounded failed-case retries | Gemini 3.5 Flash HIGH/HIGH | Gemini 3.8 Flash MEDIUM/HIGH |
|---|---:|---:|
| Operationally completed | 19/23 (82.6%) | 22/23 (95.7%) |
| Cases returning at least one grounded place | 20/23 (87.0%) | 20/23 (87.0%) |
| Grounded place hints | 159 | 226 |
| Measured Gemini spend | $4.093 | $1.979 |
| Measured Gemini spend per input post | $0.178 | $0.086 |

The 3.5 run retained three deadline failures and one invalid-schema failure.
The 3.8 run retained one deadline failure. An operational completion is not an
accuracy claim: two completed 3.8 cases produced no final grounded place and
remain outside the scored subset. One caption explicitly recommends 7even Seas
Coffee Co., so that zero-place result is already a likely extraction miss rather
than a valid no-result.

The strict source-reviewed subset currently committed in this branch contains
three cases and 80 required mentions. On those cases, 3.8 returned 80/80 required
mentions and three exact sets; 3.5 returned 17/80 and two exact sets because the
63-place stress case timed out. An extended eight-case acceptance subset,
combining those source reviews with prior user-adjudicated failures and explicit
caption expectations, contains 114 required mentions. It produced:

| Extraction metric | Gemini 3.5 Flash HIGH/HIGH | Gemini 3.8 Flash MEDIUM/HIGH |
|---|---:|---:|
| Required mention recall | 38/114 (33.3%) | 113/114 (99.1%) |
| Place-name precision | 100% | 100% |
| Posts with at least one correct place | 6/8 (75.0%) | 7/8 (87.5%) |
| Exact place sets | 5/8 (62.5%) | 7/8 (87.5%) |

The eight-case score is encouraging but provisional: it is a known hard-case
slice, not the independently labeled 50-100-post launch gate, and the 63-place
post dominates mention-weighted recall. Gemini 3.8's one miss was the explicitly
captioned 7even Seas Coffee Co. Exact-set and post-success rates therefore remain
the primary comparison.

### Controlled Bright Data to Gemini 3.8 replay

The same seven acceptance cases were replayed through the production normalizer
and Gemini 3.8 using Bright Data media. All seven model calls completed. The
final grounding returned 112/113 required mentions, 100% place-name precision,
seven posts with a useful result, and six exact sets. The single miss was Miya
Miya on the Community Goods popup post. Gemini had recognized Miya Miya as a
destination candidate from the identical caption, but the final deterministic
grounding pass retained only Community Goods. That is evidence of a grounding
decision difference, not missing scraper text, and it does not establish that
Bright Data's lower image resolution caused the miss.

The Bright replay cost $0.633 in Gemini usage. Across all runs in this benchmark,
measured Gemini spend was $6.705. Apify's rounded account usage increased by
approximately $0.36, including the batch acquisition and profile-alias
enrichment; Bright Data still displayed $0 consumed. Total observed provider
spend was therefore approximately $7.06, below the approved $10 cap.

### Provisional gate decision

1. Advance Gemini 3.8 Flash `MEDIUM/HIGH`; it has reached and exceeded 3.5 on
   the available extraction evidence while costing about 52% less per corpus
   post after retries.
2. Use content-aware acquisition: Bright Data primary with Apify fallback for
   reels, and parallel Bright-plus-Apify evidence merging for `/p/` posts.
   Acquisition differences are real, but they do not explain the large
   3.5-versus-3.8 gap on shared inputs.
3. Independently label the remaining 16 candidate posts before treating the
   23-post completion rate as place accuracy.
4. Repeat the finalists three times, then run the same frozen hints through the
   locality-aware top-three Google Places resolver. No model choice can repair a
   correct LA hint that the resolver maps to Texas.

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

1. Independently adjudicate the remaining 16 candidate posts, including branch,
   locality, entity type, and explicit no-result expectations where appropriate.
2. Repeat Gemini 3.8 `MEDIUM/HIGH` three times on both frozen Apify and Bright
   evidence. Keep 3.5 `HIGH/HIGH` as the control; do not expand weaker model
   variants unless 3.8 regresses.
3. Benchmark Google Places, locality-aware top-three behavior, MapKit, and the
   experimental Resolution API on the same frozen 3.8 hints.
4. Add the bounded content-aware Bright Data/Apify router to production, then
   compose and repeat the two winning end-to-end stacks.
5. Expand to the independently labeled 50-100-post launch gate. Run Terra, Sol,
   Opus, or Fable only if Gemini 3.8 or the resolver misses the gate in a way a
   challenger can plausibly fix.

The live runs require provider credentials in the local process environment.
The evaluator never writes those credentials into manifests or result files.
