# REC-120 Instagram and TikTok importer technical evaluation

Date: 2026-08-28
Status: Grounded Apify + Gemini replay complete; extraction promising, launch gate not met
Scope: evaluation tooling plus bounded production fallback/matcher improvements; no backend or account mutation

## Executive conclusion

The problem is tractable, but it is not one API call and the current importer is
missing entire evidence channels.

The production path can usually read a public caption and a still image. It does
not reliably acquire every carousel child, does not inspect reel/video frames,
does not transcribe speech, and does not promote some already-parsed platform
metadata into place extraction. That is why caption-heavy posts can appear to
work while reels and text-only slides fail.

The best near-term architecture is an acquisition-and-understanding ensemble:

1. Keep a bounded first-party/public-page acquisition path for speed and cost.
2. Fall back to a scraper that returns the actual ordered media assets. Bright
   Data is the stronger documented Instagram-carousel transport; Apify is the
   stronger documented Instagram-reel and TikTok transport because it can
   persist video and return TikTok slideshow assets. Apify also documents
   transcript capabilities, but this harness does not request, ingest, or score
   its transcript artifacts.
3. Read every still with deterministic OCR. For video, combine timestamped OCR
   and speech evidence with Gemini semantic extraction. A model may propose a
   place only when it returns evidence; it never gets to create a final POI.
4. Send the grounded candidate names through the existing rec.me MapKit search,
   country checks, candidate matcher, deduplication, and review UI.

The local improvement is meaningful but not launch-ready. On eight live posts
with 121 required place labels, `current-improved + Apple Vision` found at least
one correct place in all 8 posts and 116/121 required mentions. It still emitted
50 false hints, produced the exact complete set on only 1/8 posts, and was
measured without POI resolution. Acquisition transport succeeded on 8/8 cases,
but strict completeness passed only 7/8 (87.5%). Local video keyframe OCR was
especially noisy and did not recover the hidden venue name in the diagnostic
reel; TikTok's embedded tagged-place metadata did.

A credentialed `Apify + Gemini + MapKit` run proves the complete evaluation
path can acquire, understand, and resolve real posts. A no-paid-call replay of
its frozen acquisition/model artifacts then applied schema validation, explicit
model-media attestation, deterministic failure fallback, geography filtering,
and the v5 MapKit mirror. That combined extraction found 121/121 required
mentions with 97.7% micro precision, 100% micro recall, three scored extras,
and 6/8 exact posts. The seven successful Gemini cases alone found 114/114
required mentions; the failed multi-place TikTok call was recovered from its
numbered caption, so 121/121 must not be described as Gemini-only.

The launch bar is still not met. Gemini understanding itself succeeded on only
7/8 cases, mean replay latency was 144.580 seconds, and MapKit retained just
17/121 required names. Selected-name micro precision/recall was 86.4%/14.0%; all
four single-place posts were exact after selection, but none of the four
multi-place posts were exact. Extraction is now promising on this small corpus;
physical POI resolution, repeated-run reliability, and corpus breadth are the
remaining blockers.

Bright Data, Google Video Intelligence, AWS, and Azure remain unmeasured with
credentials in this evaluation. Their rows below continue to distinguish
documented capability from rec.me measurements.

## What was built

`scripts/social-import-eval/` is a repeatable Node/Swift benchmark that:

- acquires the same public post through `current`, `current-improved`, Bright
  Data, or Apify adapters;
- preserves the untouched provider response as raw JSON in a gitignored run;
- normalizes captions, tagged POIs, accessibility text, ordered images, video,
  transcript text and scene descriptions produced by explicit understanding
  adapters into one evidence contract; vendor-model descriptions stay separately
  typed and cannot become deterministic evidence;
- probes every acquired media asset relevant to the case with bounded HTTPS,
  redirect, byte, and MIME checks; transport success remains separate from
  strict modality/media completeness;
- runs deterministic extraction, Apple Vision still OCR, Apple Vision video
  keyframes, Gemini, Google Video Intelligence, or setup-status adapters for AWS
  and Azure;
- optionally sends extracted hints through a Swift MapKit resolver mirroring
  `ManualPlaceSearchPlan` and `PlaceImportCandidateMatcher`;
- reports acquisition transport, strict completeness, understanding failures,
  hint extraction, and final POI selection as separate stages; and
- scores macro per-post quality, micro per-place quality, at-least-one success,
  exact-set success, forbidden mentions, latency, and provider errors.

The same branch also makes three conservative production-path improvements:
it parses proper names and action-grounded destinations from multi-line numbered
captions or per-slide OCR, demotes exact explicit geography already carried as a
durable venue's area, and recognizes distinctive creator-qualified venue names
such as `Caroline's Seaside Cafe by Giuseppe`. It does not wire Apify, Gemini,
reel frame sampling, or speech transcription into the iOS app.

The committed corpus has 8 public posts, 121 required labels, 4 acceptable
mentions, and 3 forbidden attribution/distractor labels. It covers captions,
single images, a carousel itinerary, a dense 100-place image guide, reels,
TikTok platform sticker text, multiple venues in a video, and a caption-free
venue diagnostic.

The credentialed trial also forced several adapter corrections:

- Apify actor runs use the current `/v2/actors` endpoint. Private key-value-store
  media receives Bearer authorization only on the exact Apify API host; the
  header is non-enumerable, never serialized, and stripped on cross-host
  redirects.
- Apify's own AI video description is disabled, so the benchmark measures the
  shared Gemini understanding layer. Apify transcript artifacts remain disabled
  and unscored. Any unexpected vendor-generated scene description is quarantined
  from deterministic extraction and independent model grounding.
- Gemini receives successfully fetched media parts before the untrusted-text
  prompt and uses the current nested JSON `responseFormat` contract. The
  unsupported `maxItems: 150` schema constraint was removed after a synthetic
  A/B request changed from HTTP 400 with the constraint to HTTP 200 without it.
- Gemini retries transport errors and HTTP 408, 429, and 5xx responses with
  bounded attempts and backoff. In the full run, retries recovered one initial
  transport timeout and one initial HTTP 503; the failed TikTok case returned
  HTTP 503 on all three attempts.
- Successful structured output is split between independently grounded text
  and model-attested image/video/speech evidence. Model-only media claims require
  a matching successfully ingested asset, and independent matching uses token
  boundaries. A model-authored evidence sentence cannot ground its own caption/
  tagged-location hallucination. Schema-invalid JSON and failed model calls use
  deterministic acquired evidence, and the result/summary mark that fallback
  explicitly instead of reporting it as model success.

## Measured live results

### Credentialed Apify + Gemini + MapKit

The two-case smoke established that the authenticated path works: transport,
strict completeness, understanding, and required-place recall were all 100%.
Its hint exact-set rate was still 0%, and MapKit selected a candidate for only
50% of hints. The eight-case run then exposed the reliability and resolution
limits hidden by that smoke.

| Run | Cases | Transport | Complete acquisition | Understanding | Fallback-assisted | MapKit lookup health | MapKit selection | Mean latency |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Verified smoke | 2 | 100% | 100% | 100% | 0% | 87.5% | 50.0% | 60.531 s |
| Original full corpus | 8 | 100% | 100% | 87.5% | 0% | 61.4% | 19.9% | 151.715 s |
| Grounded saved-artifact replay | 8 | 100% | 100% | 87.5% | 12.5% | 64.8% | 17.2% | 144.580 s |

| Run | Hint macro P / R | Hint micro P / R | Required hits | Posts with a hint hit | Exact hint set | Selected-name macro P / R | Selected-name micro P / R |
|---|---:|---:|---:|---:|---:|---:|---:|
| Verified smoke | 37.5% / 100% | 33.3% / 100% | 2/2 | 2/2 | 0/2 | 75.0% / 100% | 66.7% / 100% |
| Original full corpus | 39.7% / 87.3% | 75.5% / 92.6% | 112/121 | 7/8 | 0/8 | 50.0% / 53.8% | 65.2% / 12.4% |
| Grounded saved-artifact replay | 93.8% / 100% | 97.7% / 100% | 121/121 | 8/8 | 6/8 | 90.1% / 68.0% | 86.4% / 14.0% |

The grounded replay's selected-name post-success rate was 100% and exact-set
rate was 50%, with only 17/121 required names surviving MapKit selection. All
four single-place posts were exact; none of the four multi-place posts were.
Selected-name scoring checks names and aliases only; it does not verify physical
branch identity, address, provider ID, or coordinates.

The grounded row is a post-hoc `grounded-hints-v3` rebuild from saved live
acquisition and model artifacts plus a v5 MapKit re-resolution; it made no new
Apify or Gemini calls. The manifest chains input/output result hashes and lists
each transform that actually ran. The
batch helper applies production ranking and per-query-limit order, paces
searches, and retries only transient MapKit errors. The app's selection code
remains authoritative; this helper is still a mirror.

Of 128 grounded hint lookups, 83 were error-free (64.8%). The 45 errors were 37
`placemarkNotFound` results and 8 throttling errors; lookup health therefore is
not a pure provider-uptime metric. Seventy-six lookups returned at least one
candidate, but only 22 selected one. Of the 54 candidate-bearing unselected
hints, 47 were below the 0.82 threshold and 7 lacked the required 0.08 clear
lead. The dense 100-place guide caused 95/104 final name misses, but excluding
it still leaves selected-name recall at only 12/21 (57.1%).

Measured full-run Apify actor usage summed to $0.1387. The seven successful
Gemini responses reported 44,348 prompt tokens and 66,896 total tokens, implying
approximately 22,548 billed output/thinking tokens. At the documented Gemini
3.5 Flash Standard rates of $1.50/M input and $9/M output, that is an estimated
$0.2695 for Gemini and approximately $0.4082 combined. This excludes the failed
request, smoke run, diagnostic calls, and any unreported overhead, so it is a
run estimate rather than a production unit cost. See the official
[Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing).

The grounded replay by expected-modality scenario was:

| Expected-modality scenario | Cases | Complete acquisition | Hint micro P / R | Required hits | Posts with a hit | Exact hint set |
|---|---:|---:|---:|---:|---:|---:|
| Caption | 5 | 100% | 88.5% / 100% | 19/19 | 5/5 | 3/5 |
| Carousel image text | 2 | 100% | 99.1% / 100% | 108/108 | 2/2 | 1/2 |
| Speech | 1 | 100% | 100% / 100% | 7/7 | 1/1 | 1/1 |
| Tagged location | 1 | 100% | 100% / 100% | 1/1 | 1/1 | 1/1 |
| Video text | 4 | 100% | 100% / 100% | 10/10 | 4/4 | 4/4 |

These modality rows overlap and group whole cases; they do not attribute each
correct label to one evidence channel. In particular, the speech/video rows
include the failed TikTok case recovered from its caption, so 100% here does not
prove Gemini read every spoken or visible-video name. On the seven successful
Gemini cases only, extraction found 114/114 required mentions with 97.5% micro
precision and 100% recall; 1/8 cases was fallback-assisted.

### Current and local baselines

These baseline results were collected against the public posts on 2026-08-27.
They are a diagnostic sample, not a vendor selection benchmark. `current` and
`current-improved` are JavaScript evaluation approximations of the observable
Swift paths, not executions of the production importer itself. Social pages and
media URLs can change, and the 100-place guide makes micro metrics intentionally
much more demanding than ordinary single-place posts.

| Variant | Transport / complete acquisition | Extraction macro P / R | Extraction micro P / R | Required hits | Posts with a hit | Exact hint set | Mean latency |
|---|---:|---:|---:|---:|---:|---:|---:|
| Current + deterministic text | 100% / 50.0% | 49.0% / 67.9% | 44.7% / 13.2% | 16/121 | 6/8 | 2/8 | 351 ms |
| Current-improved + deterministic text | 100% / 87.5% | 43.5% / 87.5% | 35.5% / 17.4% | 21/121 | 7/8 | 1/8 | 495 ms |
| Current + Apple Vision still OCR | 100% / 50.0% | 50.7% / 79.7% | 76.7% / 91.7% | 111/121 | 7/8 | 1/8 | 1.246 s |
| Current-improved + Apple Vision still OCR | 100% / 87.5% | 51.7% / 99.4% | 70.1% / 95.9% | 116/121 | 8/8 | 1/8 | 1.308 s |
| Current-improved + Apple Vision keyframes, TikTok-only subset | 100% / 100% | 17.0% / 100% | 10.6% / 100% | 9/9 | 3/3 | 0/3 | 16.084 s |

All five rows above used `--resolve none`. Accordingly, they score unresolved
place hints only; MapKit selected-name precision, recall, post success, and
exact-set fields are intentionally blank in the raw summary instead of being
inferred from hint quality. The current corpus grounds names and aliases, not
physical branch identity, address, provider ID, or coordinates, so even a
MapKit-selected name score must not be read as physical-POI acceptance accuracy.

The summary also groups cases by each declared expected modality. This is the
`current-improved + Apple Vision still OCR` view:

| Expected-modality scenario | Cases | Complete acquisition | Micro P / R | Required hits | Posts with a hit | Exact hint set |
|---|---:|---:|---:|---:|---:|---:|
| Caption | 5 | 100% | 37.0% / 100% | 19/19 | 5/5 | 1/5 |
| Carousel image text | 2 | 100% | 79.2% / 95.4% | 103/108 | 2/2 | 0/2 |
| Speech | 1 | 100% | 35.0% / 100% | 7/7 | 1/1 | 0/1 |
| Tagged location | 1 | 0% | 33.3% / 100% | 1/1 | 1/1 | 0/1 |
| Video text | 4 | 75% | 35.7% / 100% | 10/10 | 4/4 | 0/4 |

These rows are overlapping scenario groups: one case can declare several
expected modalities, and its labels are not attributed to a single channel.
For example, 100% recall in a speech-expected row can come from caption or
platform metadata; it does not prove that speech was transcribed.

The most important observations are:

- Apify transported every corpus case and passed every strict modality/media
  completeness check. On this small corpus, acquisition moved from the dominant
  failure to the strongest measured stage.
- Gemini recovered from one transport timeout and one HTTP 503 elsewhere, but a
  multi-place TikTok case still failed after three HTTP 503 responses. A retry
  policy reduces transient loss; it does not turn repeated provider unavailability
  into success.
- The original raw-candidate pass recovered 112/121 required names. The grounded
  replay found 121/121: 114/114 on successful model cases plus 7/7 from explicit
  deterministic fallback. It emitted three scored extras, and 6/8 posts had an
  exact hint set.
- The three scored extras were `Castle Crags Wilderness`, `Shasta-Trinity
  National Forest`, and `Wind River Brewing`. All are named destinations in the
  source evidence, so they may be corpus-label omissions rather than extraction
  defects. They remain counted as false until the frozen labels are adjudicated.
- Model candidates are not all independently verified. Caption and tagged-
  location candidates must match source text outside the model's own evidence
  sentence; image/video/speech-only candidates can be retained as explicitly
  `model_attested_media_evidence` only when the run records a matching successful
  media ingestion. Those bytes may have no independent OCR/STT transcript, so
  this remains attestation rather than independent verification. POI validation
  remains mandatory.
- MapKit is the largest downstream attrition point: 64.8% of hint lookups were
  error-free, 17.2% selected a candidate, and selected-name micro recall was
  only 14.0%. This combines not-found results, eight throttles, confidence
  thresholds, ambiguity, and candidate quality; the corpus cannot validate
  physical branch identity.
- The current deterministic path found only 16 of 121 labeled mentions. A good
  post-level score can hide catastrophic multi-place recall.
- Promoting matching TikTok embedded JSON increased the Osaka case from 3/7 to
  7/7 and exposed the exact Caroline's Seaside Cafe tagged-place name even
  though the caption omitted it.
- Still-image OCR recovered 95 of 100 labels in the dense guide. The remaining
  misses were `ATTE FOR COFFEE`, `43.12 COFFEE`, `DITTA ARTIGIANALE SPECIALTY
  COFFEE ROASTERS`, `STORY AND SOIL COFFEE`, and `CASA BARISTA & CO., CASCO
  HISTORICO`.
- The improved still pipeline found 116/121 labels but also returned 50 false
  hints across the sample. Examples include geography, creator handles, generic
  itinerary instructions, and OCR fragments. Extraction recall is no longer the
  only problem; filtering and POI validation are equally important.
- Sampling video every 250 ms produced enough duplicate/noisy OCR that the
  TikTok subset fell to 10.6% micro precision and 16.084 seconds mean
  latency. In the caption-free diagnostic, OCR read variants of "a hidden gem"
  but not the business name. The correct venue came from TikTok's platform POI,
  so the subset's 9/9 recall is not evidence that keyframe OCR read every name.
- A separate two-caption-case MapKit v2 smoke reached 68.8%/100% macro hint
  precision/recall and 100%/75% macro selected-name precision/recall. Five of
  nine hint lookups were healthy (55.6%) and two selected a candidate (22.2%),
  at 3.835 seconds mean latency. Frank N Frank's was exact by selected name; the
  Cave Springs case selected Castle Crags but missed Cave Springs while four
  hint lookups returned `MKErrorDomain` failures. This is a useful resolution
  diagnostic, not physical-POI or launch proof. That measured run used the v2
  mirror. The committed v5 helper additionally ports production's pre-limit
  result ranking, per-query-limit-before-global-dedup order, LA/Georgia
  ambiguity rules, District of Columbia region handling, and distinctive
  creator-qualified venue matching with executable parity fixtures. It paces
  batch requests and retries transient MapKit errors to reduce replay-induced
  throttling. It still copies evaluation logic rather than invoking the
  production type directly, so production Swift remains authoritative.

## Root cause in the current app

The current flow is:

`Share Extension -> import inbox -> public metadata -> still OCR -> place hints -> MapKit -> candidate matcher`

The gaps are structural:

- Instagram acquisition accepts only a subset of embedded shapes and can fall
  back to one Open Graph cover instead of the full post.
- TikTok acquisition is oEmbed-only in production, which generally provides a
  caption and cover, not the original video or ordered slideshow.
- `accessibilityText` can be parsed without becoming extraction evidence.
- `SocialMediaTextRecognizing` is a still-image Apple Vision path. It does not
  inspect video frames or audio.
- The hint extractor is asked to infer places from incomplete evidence and then
  has to separate real destinations from attribution, hashtags, geography, and
  OCR noise.
- MapKit resolution is downstream. A successful scrape is not a successful
  import, and a correct visible name can still fail to resolve to a POI.

This branch improves the existing path where evidence already reaches the app:
numbered creator captions and numbered OCR text on an individual slide can now
produce multiple bounded, proper-name hints without promoting instructions or
incidental handles. Exact explicit geography duplicated as a venue's area is
demoted, and the matcher can reconcile a distinctive provider base name with a
creator-qualified form. These are safe local improvements, not the evaluated
Apify/Gemini architecture. Reels still have no production frame sampling,
speech transcript, persisted full-media manifest, or structured model evidence.

## Option evaluation

| Option | Acquisition coverage | Visible slide text | Visible video text | Speech | rec.me live measurement | Assessment |
|---|---|---|---|---|---|---|
| Current approximation, unchanged | Captions and some still media | Partial | No | No | Yes | Fails the launch problem: 16/121 micro recall without OCR and 6/8 posts with any hit. |
| Current-improved approximation + Apple Vision | Matching embedded media, TikTok stickers/POI, public covers | Strong on sampled posts | Poor/noisy keyframes | No | Yes | Useful foundation hypothesis, not a complete reel solution or production Swift measurement. |
| Bright Data scrapers | Documented captions, Instagram carousel children, reel/TikTok video URLs | Requires downstream OCR | Requires downstream OCR/model | Not documented in selected schemas | No | Strong Instagram transport candidate. Bright Data's documented TikTok row does not show slideshow or understanding fields. |
| Apify scrapers | Documented posts/reels, persisted reel video, TikTok video/slideshow assets | Requires downstream OCR/model | Actor AI description disabled; Gemini used downstream | Documented STT disabled and unmeasured here | Yes, acquisition | Reached 100% transport and strict completeness on 8/8, but this small public corpus is not a production reliability guarantee. |
| Google Video Intelligence | Requires actual media bytes or GCS | N/A; use still OCR | Timestamped OCR | Timestamped en-US transcription | Adapter only | Good deterministic evidence service; expensive relative to Gemini and not a semantic POI extractor. |
| Gemini video understanding | Requires acquired media bytes, Files/GCS, or a fetchable media URL | Joint image understanding | Joint visual/audio understanding | Yes | Yes, with Apify | Grounded replay reached 121/121 combined extraction and 6/8 exact hint sets, but Gemini itself was 7/8 and one case required caption fallback. Model-attested media evidence and tail reliability still need a larger benchmark. |
| AWS Rekognition + Transcribe | Requires S3 | N/A; separate still path | Timestamped OCR | Separate Transcribe job | Setup-status only | Viable comparator but operationally heaviest: two jobs, storage, queueing, and another semantic stage. Apply the AI-service data-use opt-out before real content. |
| Azure AI Video Indexer | Bytes or direct public/SAS media URL | N/A; separate still path | OCR on a shared timeline | Transcript and location named entities | Setup-status only | Best fourth managed comparator because OCR, speech, and location entities share one output timeline. Still needs business-POI resolution. |

### Bright Data and Apify are not place extractors

Bright Data documents ordered Instagram `post_content`, alt text/location
metadata, and reel/TikTok video URLs, but not reel OCR or transcript fields in
the selected datasets. See its [Instagram posts schema](https://docs.brightdata.com/api-reference/scrapers/social-media-apis/instagram-posts-collect-by-url),
[reels schema](https://docs.brightdata.com/api-reference/scrapers/social-media-apis/instagram-reels-collect-by-url),
and [TikTok posts schema](https://docs.brightdata.com/api-reference/scrapers/social-media-apis/tiktok-posts-collect-by-url).

Apify's broad Instagram actor documents carousel children. Its dedicated reel
actor documents retained video and speech transcripts, while the Clockworks
TikTok actor documents slideshow images, subtitles/STT, and an AI scene
description. The evaluator does not request, fetch, ingest, or score Apify
transcript artifacts; those remain an unmeasured documented capability. See the
[Instagram actor](https://apify.com/apify/instagram-scraper/input-schema),
[reel actor](https://apify.com/apify/instagram-reel-scraper/input-schema), and
[TikTok actor](https://apify.com/clockworks/tiktok-scraper/input-schema). None of
those capabilities removes the need for shared downstream place extraction and
POI resolution.

### Google, AWS, and Azure

Google Video Intelligence accepts base64 bytes or GCS input and can request
`TEXT_DETECTION` and `SPEECH_TRANSCRIPTION` together. At published list pricing,
the two features total $0.198 per started video minute after the feature-specific
free tier. See the [annotate API](https://docs.cloud.google.com/video-intelligence/docs/reference/rest/v1/videos/annotate)
and [pricing](https://cloud.google.com/products/video-intelligence/pricing).

Gemini accepts inline data up to 100 MB per request, temporary File API uploads,
registered GCS files, or supported external media URLs. Inline bytes are the
safest benchmark path for expiring/hotlink-protected social media. Gemini video
defaults to roughly one sampled frame per second and approximately 300 input
tokens per video second, so short text overlays can be missed. See the official
[file input guide](https://ai.google.dev/gemini-api/docs/file-input-methods),
[video guide](https://ai.google.dev/gemini-api/docs/video-understanding), and
[pricing](https://ai.google.dev/gemini-api/docs/pricing). At the documented token
rate, Gemini 3.5 Flash input is approximately $0.027/video minute and 3.5
Flash-Lite approximately $0.0054/video minute, before output tokens.

The Gemini adapter attempts every acquired image and video, records a per-asset
ingestion result, and sends only successfully fetched bytes within bounded
per-item and total inline limits. The Google adapter attempts every acquired
video child and runs a separate Video Intelligence annotation operation for
each successful bounded fetch; it does not silently analyze only the first
video.

AWS Rekognition Video returns timestamped text detections from S3 video, while
Amazon Transcribe is a separate async job. See [Rekognition video text](https://docs.aws.amazon.com/rekognition/latest/dg/text-detecting-video-procedure.html)
and [Transcribe data-use opt-out](https://docs.aws.amazon.com/en_en/transcribe/latest/dg/opt-out.html).
Azure Video Indexer provides OCR, transcript, and location named entities on a
common timeline and accepts uploaded bytes or a direct media URL; see its
[insights overview](https://learn.microsoft.com/en-us/azure/azure-video-indexer/insights-overview)
and [upload/index API](https://learn.microsoft.com/en-us/azure/azure-video-indexer/upload-index-media).

## Recommended production design

### 1. Acquisition manifest

Every adapter must emit a complete, ordered, durable-enough manifest rather than
one generic thumbnail:

```json
{
  "platform": "tiktok",
  "sourceURL": "<public-social-post-url>",
  "caption": "...",
  "taggedLocations": [{ "name": "...", "address": "..." }],
  "assets": [
    { "index": 0, "kind": "image", "sourceURL": "..." },
    { "index": 1, "kind": "video", "sourceURL": "...", "durationSeconds": 18 }
  ]
}
```

Persist authorized media immediately in the server job because social CDN URLs
expire. Record child count/order, HTTP status, MIME type, byte length, duration,
and a content hash. A green JSON job with an expired or incomplete media URL is
an acquisition failure.

### 2. Evidence, not guesses

Normalize all modalities into timestamped evidence:

```json
{
  "sourceAssetIndex": 1,
  "modality": "video_text",
  "rawText": "Venue name shown on screen",
  "startMs": 3200,
  "endMs": 4700,
  "provider": "google-video",
  "providerConfidence": 0.94
}
```

Use platform POIs, captions, accessibility text, still OCR, video OCR, speech,
and model candidates as independently attributable sources. A model candidate
must include modality and evidence text. Discard scenery-only guesses and
classify creator credits, comparisons, sponsors, and former employers as
non-destinations.

### 3. Existing POI pipeline remains authoritative

Feed grounded names and area hints into the existing MapKit query plan,
country-conflict checks, `PlaceImportCandidateMatcher`, and deduplication. Keep
the creator spelling for display, but require a selected provider POI or an
explicit user-review row before creating a final place.

### 4. Next provider matrix

The first credentialed `Apify + Gemini + MapKit` cell is complete. The next
matrix should be:

1. Repeat `Apify + Gemini` on the frozen larger corpus and across multiple runs
   to measure recurrent 5xx, latency, and cost distributions rather than one
   sample.
2. Run `Bright Data Instagram -> Apple Vision stills + Gemini` on the same
   Instagram cases.
3. Repeat Apify and Bright Data video cases with Google Video Intelligence to
   separate acquisition quality from Gemini availability/model behavior.
4. Keep `current-improved + Apple Vision` as the zero-vendor baseline.
5. Run Azure Video Indexer on only the video cases as the fourth managed option.
6. Run AWS only if Azure/Google/Gemini miss a material class or an AWS platform
   constraint dominates the production choice.

The grounded replay makes Apify + Gemini the front-runner worth hardening, but
it does not justify skipping the benchmark matrix. The next dollar and hour
should go first to the frozen 50-100-case corpus and repeated Apify + Gemini
runs, then to Bright Data transport and Google Video Intelligence on the same
assets. Azure remains the useful fourth video comparator; AWS can stay deferred
unless those tests expose a class it uniquely addresses.

Do not pay for every expensive analysis path on every import. A sensible cascade
is platform POI/caption/alt text -> still OCR -> cheap semantic extraction ->
video understanding only when no adequate place set is found.

## Launch gate and larger benchmark

Eight posts are enough to reject the current implementation, not enough to
select a vendor. Before shipping, freeze at least 50-100 authorized examples
across:

- caption-only, single still, multi-image, and mixed-media carousel;
- slow overlay, 100/250/500/1,000 ms overlay, speech-only, and multiple venues;
- ambiguous chain name requiring city/neighborhood context;
- native tagged POI, accessibility text, and slideshow-only TikTok;
- attribution/sponsor/creator distractors and true no-place negatives; and
- deleted, private, login-walled, geo/age-restricted, redirected, expired-media,
  and provider-error cases.

Recommended launch thresholds on the frozen corpus:

- at least 98% complete acquisition of every expected asset;
- at least 95% posts with one correct place;
- at least 90% micro required-place recall;
- at least 85% micro precision after POI validation;
- at least 80% exact-set success for multi-place posts;
- no silent green result when media acquisition or POI lookup failed; and
- p95 latency and cost that fit the product's async-import UX and budget.

Report each stage independently. Otherwise a scrape failure can look like model
failure, a model hallucination can look like MapKit failure, or a transient
MapKit outage can erase an otherwise correct extraction result.

## Credentialed trial status and repeat steps

The credentialed Apify/Gemini trial completed using process-scoped credentials;
the runner did not write them into the repository or run artifacts. Its verified
smoke and full-corpus outputs are in the gitignored
`runs/apify-gemini-smoke-2026-08-28-verified/` and
`runs/apify-gemini-full-2026-08-28/` directories. The post-review, no-paid-call
replay is in `runs/apify-gemini-grounded-replay-2026-08-28/`; its manifest
records chained result hashes, the exact applied transforms, fallback count, and the v5
resolver. The final hint transform is `grounded-hints-v3`. Bright Data, Google
Video Intelligence, AWS, and Azure still need
comparable credentialed cells before a provider decision.

Apify's [current general terms](https://docs.apify.com/legal/general-terms-and-conditions)
say that personal accounts must be created by humans rather than automated
signup. TikTok's [current US terms](https://t.tiktok.com/legal/page/us/terms-of-service/en)
also restrict automated extraction without approval; production use needs legal
review regardless of vendor capability.

To repeat the measured cell without putting secrets in Git:

1. Supply `APIFY_TOKEN` and `GEMINI_API_KEY` only through the approved secret
   store or process environment. Do not create a repo `.env` file.
2. From `scripts/`, run:

   ```bash
   npm run eval:social-import -- \
     --providers apify \
     --understanders gemini \
     --resolve mapkit
   ```

3. Inspect `summary.md`, `summary.json`, `results.json`, per-asset ingestion
   diagnostics, and Gemini request-attempt metadata. Confirm no secrets appear
   before sharing any raw provider envelope.
4. Record provider usage/billing, transient retries, label misses, false
   positives, and selected candidates. A successful repeat is evidence for the
   benchmark cell, not authorization to launch or scrape additional content.

## Decision today

Merge the bounded local parser, provenance, auth/retry, replay, and matcher
improvements after review; they improve evidence already available to the app
without committing rec.me to a vendor. Do not launch the importer or wire a
production scraper/model solely from this eight-post result. Apify is the
strongest measured acquisition option and the grounded Apify + Gemini path now
has excellent extraction on this sample, but one model call still failed,
multi-place POI selection was 0/4 exact, selected-name micro recall was 14.0%,
and mean latency was 144.580 seconds.

Proceed with the 50-100-case frozen benchmark and repeated Apify + Gemini runs,
then measure Bright Data and Google Video Intelligence on the same inputs before
the production-provider decision. Keep Azure as the fourth video comparator and
defer AWS unless the first three expose a material uncovered scenario. No option
is launch-ready or a measured overall winner yet.
