# REC-120 Instagram and TikTok importer technical evaluation

Date: 2026-08-27
Status: Phase 1 complete; credentialed vendor/model trials still gated
Scope: evaluation tooling only; no production app, backend, or account mutation

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

No credentialed Bright Data, Apify, Gemini, Google Cloud, AWS, or Azure trial was
run. Provider credentials were absent, the required operations service registry
was not readable from this workspace, and Apify's current terms require a human
to create a personal account. Vendor rows below therefore separate documented
capability from measured rec.me results.

## What was built

`scripts/social-import-eval/` is a repeatable Node/Swift benchmark that:

- acquires the same public post through `current`, `current-improved`, Bright
  Data, or Apify adapters;
- preserves the untouched provider response as raw JSON in a gitignored run;
- normalizes captions, tagged POIs, accessibility text, ordered images, video,
  transcript text produced by an understanding adapter, and scene descriptions
  into one evidence contract;
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

The committed corpus has 8 public posts, 121 required labels, 4 acceptable
mentions, and 3 forbidden attribution/distractor labels. It covers captions,
single images, a carousel itinerary, a dense 100-place image guide, reels,
TikTok platform sticker text, multiple venues in a video, and a caption-free
venue diagnostic.

## Measured live results

These results were collected against the public posts on 2026-08-27. They are a
diagnostic sample, not a vendor selection benchmark. `current` and
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
  mirror. The committed v3 helper additionally ports production's LA/Georgia
  ambiguity rules and District of Columbia region handling with executable
  parity fixtures. It still copies evaluation logic rather than invoking the
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

## Option evaluation

| Option | Acquisition coverage | Visible slide text | Visible video text | Speech | rec.me live measurement | Assessment |
|---|---|---|---|---|---|---|
| Current approximation, unchanged | Captions and some still media | Partial | No | No | Yes | Fails the launch problem: 16/121 micro recall without OCR and 6/8 posts with any hit. |
| Current-improved approximation + Apple Vision | Matching embedded media, TikTok stickers/POI, public covers | Strong on sampled posts | Poor/noisy keyframes | No | Yes | Ship-worthy foundation hypothesis, not a complete reel solution or production Swift measurement. |
| Bright Data scrapers | Documented captions, Instagram carousel children, reel/TikTok video URLs | Requires downstream OCR | Requires downstream OCR/model | Not documented in selected schemas | No | Strong Instagram transport candidate. Bright Data's documented TikTok row does not show slideshow or understanding fields. |
| Apify scrapers | Documented posts/reels, persisted reel video, TikTok video/slideshow assets | Requires downstream OCR | Optional TikTok AI description; still benchmark it | Documented STT, not requested or ingested here | No | Broadest documented social acquisition candidate, especially TikTok. Transcription is audio, not on-screen OCR. |
| Google Video Intelligence | Requires actual media bytes or GCS | N/A; use still OCR | Timestamped OCR | Timestamped en-US transcription | Adapter only | Good deterministic evidence service; expensive relative to Gemini and not a semantic POI extractor. |
| Gemini video understanding | Requires acquired media bytes, Files/GCS, or a fetchable media URL | Joint image understanding | Joint visual/audio understanding | Yes | Adapter only | Best semantic candidate. Default 1 FPS sampling is a known fast-overlay risk, so pair it with deterministic OCR/keyframes and require evidence. |
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
  "sourceURL": "https://www.tiktok.com/@creator/video/123",
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
  "rawText": "Dinner at Lilia",
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

### 4. Provider order to benchmark

The first full credentialed matrix should be:

1. `current-improved -> Apple Vision stills + Gemini video`
2. `Bright Data Instagram -> Apple Vision stills + Gemini video`
3. `Apify Instagram/TikTok -> Apple Vision stills + Gemini video`
4. Repeat 2 and 3 with Google Video Intelligence instead of Gemini.
5. Run Azure Video Indexer on only the video cases as the fourth managed option.
6. Run AWS only if Azure/Google/Gemini miss a material class or an AWS platform
   constraint dominates the production choice.

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

## Credentialed trial gate and restart steps

The runner found none of `BRIGHTDATA_API_TOKEN`, `APIFY_TOKEN`,
`GEMINI_API_KEY`, or `GOOGLE_CLOUD_ACCESS_TOKEN`. Hosted account/project setup
was intentionally stopped because the project-required service-account registry
could not be read. In addition, Apify's [current general terms](https://docs.apify.com/legal/general-terms-and-conditions)
say that personal accounts must be created by humans rather than automated
signup. TikTok's [current US terms](https://t.tiktok.com/legal/page/us/terms-of-service/en)
also restrict automated extraction without approval; production use needs legal
review regardless of vendor capability.

To resume without putting secrets in Git:

1. Make the operations service registry readable or supply the existing
   organization/project identifiers through the approved internal channel.
2. Have the owner manually create/confirm the Apify personal account and accept
   its terms; create or confirm Bright Data and Google projects under the
   registered organization.
3. Put tokens only in the approved secret store or shell environment. Do not
   create a repo `.env` file.
4. From `scripts/`, run:

   ```bash
   npm run eval:social-import -- \
     --providers brightdata,apify \
     --understanders deterministic,apple-vision,gemini,google-video \
     --resolve mapkit
   ```

5. Inspect `runs/<timestamp>/summary.md`, `results.json`, and each raw provider
   envelope. Verify media byte fetches, label misses, false positives, provider
   usage/billing, and POI candidates before naming a winner.

## Decision today

Do not launch the current importer unchanged, and do not commit to a single
scraper from documentation alone. The evidence supports implementing the
bounded current-parser fixes and full still OCR immediately, while running the
credentialed Bright Data-versus-Apify acquisition matrix and Gemini-versus-
Google video understanding matrix. Apify plus Gemini is the leading documented
end-to-end hypothesis for reels/TikTok; Bright Data plus the same understanding
layer is the leading documented Instagram-carousel hypothesis. Neither is yet a
measured winner.
