# REC-97 Multi-Source Place Imports Engineering Plan

Date: 2026-07-15
Status: Approved for implementation planning
Linear: REC-97
Branch: `codex/rec-97-place-imports`
Product design: `/Users/ryanlieblein/.gstack/projects/joelipshutz-wander/ryanlieblein-codex-rec-97-place-imports-design-20260714-233505.md`

## Goal

Add four owner-only Profile import entry points for Google Maps, Instagram, TikTok, and Text/Notes. Inputs become private, durable import candidates. Profile shows a persistent import-progress button that becomes `Review Import` when candidates are ready. The review page presents the complete import as one cursor-paginated list. Choosing Been or Wanna for an item opens the same regular save flow used elsewhere in rec.me; only completing that flow creates a save.

The first complete release includes all four adapters and iOS Share Extension capture. Implementation is split into stacked PRs behind a disabled `import_places_v1` capability flag. The flag cannot be enabled until every adapter, the hosted backend, the Share Extension, and physical-device acceptance pass.

## Locked Decisions

1. Use one durable, owner-private Unified Import Inbox with `import_batches` and `import_items`.
2. Keep Google Maps, Instagram, TikTok, Text/Notes, and Share Extension capture in the complete release.
3. Use Apple Maps Server API in the backend worker for place resolution. iOS handles ambiguity and manual correction.
4. Schedule bounded worker claims with Supabase Cron, `pg_net`, and Vault.
5. Store raw archives/files in an owner-scoped private bucket and delete them seven days after parsing, completion, or cancellation.
6. Use a new item-level import commit RPC. It must recheck duplicates atomically and never overwrite existing personal save data.
7. Extract one shared save-flow feature from Add. Imports pass a candidate, selected status, and import-specific commit closure into that exact flow.
8. Keep import state in a dedicated `ImportStore`, not the 5,881-line `WanderStore`.
9. Implement provider adapters as modules behind one normalized manifest contract and one import-worker orchestrator.
10. Use redacted golden fixtures in PR CI plus a scheduled live provider smoke.
11. Add a `WanderUITests` target for the complete Profile-to-save journey.
12. Review items use cursor pagination with pages of approximately 40 to 50 rows.
13. Profile polls batch summaries every 3 to 5 seconds only while visible and processing, then stops on background or completion.
14. Use constrained server-side structured AI to extract place-name/area hints from captions and prose. Apple Maps remains canonical, model storage is disabled, and evals gate prompt changes.

## What Already Exists

| Existing capability | Location | REC-97 use |
|---|---|---|
| Single-source artifacts and extraction jobs | `Wander/Models`, `Wander/Services`, Supabase extraction migrations | Reuse extraction concepts and safe error vocabulary; do not stretch unresolved drafts into batch review. |
| Authenticated and service-role extraction claims | `supabase/functions/extraction-worker`, extraction RPCs | Reuse leasing/security patterns in the import worker. |
| Apple device-side place search | `Wander/Services/MapKitPlaceResolver.swift` | Reuse candidate models and manual correction UI; background matching moves to Apple Maps Server API. |
| Regular Add save form and questions | `Wander/Features/Add/AddScreen.swift`, `AddQuestionTemplates.swift` | Extract into one shared save-flow component used by Add and Import. |
| Local-first save state and canonical place models | `Wander/Services/WanderLocalStore.swift`, repository protocols | Reuse successful-save reconciliation; import staging remains outside the global store. |
| `save_own_place` and user/place uniqueness | Supabase save migrations | Reuse canonical place payload validation, but add a non-destructive import commit contract. |
| Private Supabase Storage patterns | Profile avatar and visit-photo storage | Reuse signed upload and owner-path policy patterns for raw import artifacts. |
| Scheduled push worker | `20260712112000_schedule_push_notification_worker.sql` | Reuse `pg_cron` + `pg_net` + Vault setup for import processing and cleanup. |
| XcodeGen | `project.yml` | Add Share Extension, App Group entitlements, and `WanderUITests`; regenerate instead of editing membership manually. |
| Feature/capability gating | `Wander/App/WanderBackend.swift` and build configuration patterns | Add `import_places_v1`; keep Profile section hidden until backend and signed targets are ready. |

## NOT in Scope

- Provider-account login or private saved-library synchronization. Instagram and TikTok accept explicit public URLs only.
- Scraping private, embed-disabled, age-restricted, deleted, or authenticated social content.
- Importing ratings, Been/Wanna status, visibility, notes, visits, tags, or list membership without explicit confirmation in the regular save flow.
- Auto-saving extracted candidates or showing them on Map, Profile counts, Calendar, Discover, feeds, lists, notifications, or recommendations before promotion.
- Permanent archival of social posts, captions, notes, or Google Takeout files.
- OCR/photo import. The existing honest unresolved state remains until a separate photo-extraction contract is approved.
- New universal-link web pages or outbound rec.me sharing changes.
- Contact import.
- Enabling the feature flag, merging to `main`, or creating a TestFlight release in the planning PR.

## User Experience Contract

### Profile Section

Place the owner-only section immediately after Visit Invitations and before Been/Wanna. Other-member profiles never show it.

```text
IMPORT PLACES

+------------+ +------------+ +------------+ +------------+
| map.fill   | | reels icon | | music.note | | note.text  |
| Google     | | Instagram  | | TikTok     | | Text /     |
| Maps       | | Reels      | |            | | Notes      |
+------------+ +------------+ +------------+ +------------+

[ spinner  Importing 126 of 300                 42%  > ]
```

Normal Dynamic Type uses four stable equal-width tiles. Accessibility sizes may use a 2x2 grid. Every tile and action has a 44-point minimum target, a VoiceOver source label, a distinct non-gradient accent, and rec.me design tokens.

The full-width state button is always actionable:

- No batch: `Import Inbox` with `No imports waiting`.
- Processing: `Importing N of M`; tap opens batch progress/details.
- Ready: `Review Import` with remaining count.
- Mixed: `Review Import` as the command with a secondary `Importing N of M` progress line.
- Partial failure: `Review Import` with `X ready, Y need help`.

### Review List

```text
<  Review Import                         18 remaining

[All] [Needs review] [Duplicates] [Saved] [Failed]

Maru Coffee
Santa Monica, CA                 Google Maps
[checkmark Been]                 [bookmark Wanna]

Night + Market
2 possible matches               Instagram
[Review match]

Gjusta
Already saved                    Existing save >
```

- Use a native `List`/lazy row composition with cursor pagination.
- Rows preserve a stable server item ID and scroll anchor.
- Been and Wanna are 44-point icon-plus-text commands, not a permanent selection control.
- Selecting either opens the shared regular save flow with candidate and status prefilled.
- Save success returns to the same row, marks it Saved, and advances remaining counts.
- Cancel returns to the same row unchanged.
- Ambiguous rows require candidate selection before Been/Wanna becomes available.
- Existing-save duplicates open the existing place and never offer destructive replacement.

### Source Entry

**Google Maps**

- Offer `Paste shared list link` and `Choose Google Takeout file`.
- Takeout is the reliable bulk path. Confirm real archive/file formats from the golden corpus before selecting a ZIP parser.
- Shared-list links use provider-permitted public metadata. Unsupported lists immediately explain the Takeout route.

**Instagram**

- Accept one or more pasted public Reel/post URLs and Share Extension URLs.
- Use approved public embed/media metadata only.
- Private, unavailable, or embed-disabled links become `Needs source help` with screenshot/text/manual hint rescue choices; they never fabricate candidates.

**TikTok**

- Accept one or more pasted public video URLs and Share Extension URLs.
- Use TikTok public oEmbed metadata.
- Private/deleted/unsupported videos receive the same explicit rescue path.

**Text / Notes**

- Accept pasted text, shared selected text, and verified `.txt`, `.md`, `.rtf`, and `.csv` inputs.
- Preserve unrecognized lines for review. Never silently discard source content.
- Apple Notes is supported through explicit share/export, not library access.

## System Architecture

```text
IN-APP TILE                      IOS SHARE EXTENSION
paste/file picker                URL/text/file attachment
      |                                  |
      |                           App Group envelope
      |                           (hash + local ref)
      +------------------+---------------+
                         |
                         v
                 AppGroupImportInbox
                         |
                         v
                 ImportRepository
                         |
              signed artifact upload
                         |
                         v
        import_batches + import_items + private storage
                         |
                Supabase Cron / pg_net
                         |
                         v
                    import-worker
       +-----------------+--------------------+
       |                 |                    |
 provider adapter   structured hint      Apple Maps
 / manifest parser  extraction           Server API
       |                 |                    |
       +-----------------+--------------------+
                         |
                         v
                 reviewable import items
                         |
          Profile poll -> ImportStore -> Review List
                         |
                  Been / Wanna command
                         |
                         v
                   SharedSaveFlow
                         |
                 commit_import_item RPC
                         |
              user_places / visits / attributes
```

Inline ASCII comments should accompany the state transitions in the import model, worker lease loop, App Group drain, and item commit RPC migration. Presentation views do not need architecture comments.

## Backend Data Contracts

### `import_batches`

Owner-only durable batch metadata:

- `id uuid primary key`
- `owner_user_id text not null`
- `source_kind text`: `google_maps`, `instagram`, `tiktok`, `text_notes`
- `status text`: queued/ingesting/extracting/partially_ready/ready_for_review/failed/cancelled/completed
- `title text`
- `artifact_storage_path text null`
- `artifact_sha256 text not null`
- `manifest_version integer not null`
- aggregate counters for total, processing, ready, needs_review, duplicate, failed, saved, skipped
- `state_version bigint` incremented on summary-visible changes
- lease/cancel/completion and audit timestamps

Do not store raw source text in analytics columns. The batch may retain minimal source label/provenance needed for review.

### `import_items`

- `id uuid primary key`
- `batch_id uuid not null`
- `owner_user_id text not null`, derived from the batch and protected against mismatch
- `ordinal integer`
- `source_item_key text` and deterministic `source_item_hash text`
- minimal owner-visible source context JSON
- extracted hint JSON with evidence spans
- bounded candidate JSON and selected candidate payload
- confidence and resolver version
- state: queued/resolving/ready/ambiguous/needs_source_help/duplicate_batch/duplicate_existing/failed_retryable/failed_final/committing/saved/skipped/cancelled
- duplicate linkage to import item or existing user-place
- stable operation ID/request hash and resulting user-place ID
- lease, attempts, error code, and timestamps

Unique constraints prevent duplicate batch items and repeated operation IDs. Candidate arrays and source context have explicit size limits.

### Storage

- Create an owner-private `place-import-artifacts` bucket.
- Object keys include authenticated owner and batch UUID; clients cannot choose another owner prefix.
- Signed upload is created through a narrow authenticated RPC/repository boundary.
- A cleanup function deletes raw objects seven days after parse, completion, or cancellation.
- Active/review items survive artifact cleanup because normalized manifests are durable.
- Completed/cancelled batch history defaults to 30 days; unfinished review batches remain until the user discards them.

### RPCs

Expected narrow public contracts:

- `create_import_batch`
- `get_import_batch_summaries`
- `get_import_batch`
- `get_import_items_page`
- `select_import_candidate`
- `retry_import_item`
- `cancel_import_batch`
- `discard_import_batch`
- `commit_import_item`

Service-role-only contracts:

- `claim_next_import_items`
- `complete_import_item_resolution`
- `fail_import_item`
- `cleanup_import_artifacts`

Owner RPCs derive identity with `app.current_user_id()`. Security-definer functions pin `search_path`, grant only required roles, validate batch/item ownership, and never accept a caller-selected owner ID. Worker functions use service role and leased claims. Every created/replaced RPC gets metadata, grant, RLS, cross-user, anonymous, and hosted rollback smoke coverage.

### Non-Destructive Promotion

`commit_import_item` receives the item ID, stable operation ID, request hash, selected status, normal save payload, and attributes emitted by `SharedSaveFlow`.

In one transaction it:

1. Locks the item and validates owner/state/selected candidate.
2. Returns the prior result for the same operation ID and request hash.
3. Rejects operation-ID reuse with changed content.
4. Rechecks `(viewer_id, place_id)` before any personal-field write.
5. If a save exists, marks the item `duplicate_existing`, links the existing user-place, and returns `already_saved` without calling the destructive upsert branch.
6. Otherwise creates/updates canonical place metadata, inserts the new user-place and attributes, and creates visit behavior only according to the regular save contract.
7. Marks the import item Saved and increments batch counters.

Do not change existing `save_own_place` conflict behavior inside REC-97. Isolating the safer import contract avoids a broad regression surface.

## Worker Design

Create one `import-worker` Edge Function and modular adapters, not one deployment per provider.

```text
cron tick
  -> claim page with SKIP LOCKED + lease
  -> adapter.parse(source)
       -> normalized manifest items
       -> deterministic evidence
       -> optional structured AI hints [store:false]
  -> Apple Maps Server API search
       -> exact/high confidence -> ready
       -> multiple plausible -> ambiguous
       -> none -> needs_source_help
       -> provider timeout -> failed_retryable
  -> complete item + update aggregate counters
  -> release lease / retry with backoff
```

Adapter contract:

- validates source kind and size
- parses into deterministic source item IDs
- emits bounded source evidence and one or more place hints
- maps provider-specific errors to shared safe codes
- never creates places or user-places
- never logs raw captions, text, private URLs, filenames, or exact imported payloads

The structured AI layer receives only bounded source text and an extraction schema. It returns candidate hints and evidence, never a canonical place or save. Reject unsupported output, confidence without evidence, or place names not grounded in input. Run with model storage disabled.

Apple Maps Server API credentials stay in Supabase secrets/Vault. Add token creation/rotation documentation and a live credential smoke. Apply rate limiting, bounded concurrency, jittered retry, and a circuit breaker that moves items to retryable state instead of spinning.

## iOS Architecture

### Shared Save Flow

Extract Add's private details state into a reusable feature:

- `SharedPlaceSaveFlow`
- `PlaceSaveSession` state/value model
- input: candidate, preselected status, source context, optional source suggestions
- output: validated normal save payload and attributes
- commit closure: Add uses existing save path; Import uses `commit_import_item`
- completion/cancellation callbacks

Preserve Add behavior with regression tests for Been/Wanna question templates, rating, visibility/private-profile lock, note, attributes, toast, auth gating, photo attachment behavior, and reset. Imports must not render a second metadata form.

### `ImportStore`

An `@MainActor ObservableObject` owns:

- active batch summaries and poll lifecycle
- cursor-paginated review pages and filters
- scroll anchors per batch/filter
- item retry/candidate-selection mutations
- App Group envelope drain and signed batch creation
- import-specific save commit and local retry state
- app foreground/background cancellation
- safe user-facing errors

It does not publish every staged item through `WanderStore`. After successful promotion, it asks the existing store/repository boundary to reconcile the resulting user-place and refresh affected owner projections.

### Share Extension

- Add one extension target and App Group through `project.yml`.
- Accept URLs, plain text, and supported files via `NSItemProvider`.
- Perform bounded type/size validation only.
- Write an atomic envelope containing source kind, content hash, attachment reference, created timestamp, and delivery ID.
- Never embed Supabase service credentials, parse large archives, call social APIs, or run long network work in the extension.
- The host app drains envelopes idempotently. Signed-out envelopes survive authentication and cannot leak across accounts; ownership is assigned only after authenticated batch creation.
- Add expiration and corrupt-envelope quarantine so a bad payload cannot block the inbox.

## Progress and Pagination

- Poll summaries every 4 seconds only when Profile is visible and at least one batch is processing.
- Cancel the polling task on disappearance/background/completion and refresh immediately on foreground.
- Use `state_version`/ETag-style comparison so unchanged polls do not republish UI state.
- Review RPC uses a stable cursor `(ordinal, id)` plus filter and page size capped at 50.
- Prefetch near the final 10 rows; prevent duplicate concurrent page requests.
- Cache a bounded number of pages and preserve a row anchor when returning from save flow.
- Support multiple batches. Profile aggregates progress; Review Import groups rows by batch/source without merging provenance.

## Failure Modes

| Path | Production failure | Handling and user result | Test |
|---|---|---|---|
| Share Extension | duplicate delivery or host crash during drain | content hash/delivery ID makes drain idempotent; envelope remains until acknowledged | App Group integration + UI test |
| Signed-out share | no authenticated owner | preserve local envelope and show sign-in gate without upload | UI test |
| Raw upload | network dies mid-file | resumable/retryable batch creation; no processing until verified hash | repository integration |
| Archive parse | unsupported/corrupt Takeout shape | batch becomes Needs Help and preserves a safe format explanation | golden fixture unit |
| Social URL | private/deleted/embed-disabled | Needs Source Help; no fabricated candidate | adapter unit + live smoke |
| Structured AI | hallucinated place not in source | evidence validation rejects output to manual rescue | eval |
| Apple Maps | rate limit/token expiry/timeout | leased retry with backoff and visible retry state | worker unit + live smoke |
| Worker | process dies after claim | lease expires; next worker reclaims without duplicate item | SQL/worker integration |
| Batch counters | concurrent item completions race | database-owned atomic counters/state version | pgTAP concurrency contract |
| Review pagination | row saved while another page loads | stable item IDs/cursor and state merge preserve row/anchor | ImportStore unit + UI test |
| Duplicate race | place saved after review but before commit | commit RPC returns Already Saved without overwriting | pgTAP + hosted smoke |
| Offline save | connection disappears on submit | preserve form/item state and retry operation ID; no double save | UI/repository test |
| Account change | App Group envelope created under prior session | envelope has no owner until authenticated claim; sign-out cancels polls/cache | security + UI test |
| Artifact cleanup | raw file expires before review | normalized manifest/items remain reviewable | SQL integration |
| App upgrade | local cache schema changes | versioned envelope/manifest decode with quarantine fallback | migration/unit test |

No planned path is allowed to fail silently. Every failure has a safe error code, recovery action, and test.

## Test Coverage Diagram

```text
CODE PATHS                                           USER FLOWS
[+] Capture                                          [+] Start imports
  +-- [GAP -> UNIT] tile input validation              +-- [GAP -> E2E] each of four tiles
  +-- [GAP -> E2E] Share Extension envelope            +-- [GAP -> E2E] Files and share sheet
  +-- [GAP -> UNIT] duplicate/corrupt envelope          +-- [GAP -> E2E] signed-out handoff

[+] Batch backend                                   [+] Observe progress
  +-- [GAP -> INTEGRATION] create/upload/RLS           +-- [GAP -> E2E] loading button
  +-- [GAP -> INTEGRATION] lease/retry/cancel           +-- [GAP -> E2E] background/foreground
  +-- [GAP -> INTEGRATION] cleanup retention            +-- [GAP -> E2E] partial failure

[+] Provider adapters                               [+] Review import
  +-- [GAP -> UNIT] Google Takeout/shared list          +-- [GAP -> E2E] lazy pagination/filter
  +-- [GAP -> UNIT] Instagram/TikTok metadata            +-- [GAP -> E2E] ambiguous correction
  +-- [GAP -> UNIT] Text/Notes manifest                  +-- [GAP -> E2E] duplicate opens existing
  +-- [GAP -> EVAL] grounded structured hints            +-- [GAP -> E2E] retry failed item
  +-- [GAP -> LIVE] provider/API credential drift

[+] Shared save flow                                [+] Save one item
  +-- [CRITICAL GAP -> UNIT] existing Add behavior      +-- [GAP -> E2E] Been -> regular flow
  +-- [GAP -> UNIT] import commit closure                +-- [GAP -> E2E] Wanna -> regular flow
  +-- [GAP -> INTEGRATION] duplicate-safe RPC            +-- [GAP -> E2E] cancel/return anchor
  +-- [GAP -> INTEGRATION] idempotent retry               +-- [GAP -> E2E] save/row becomes Saved

CURRENT COVERAGE: existing extraction invocation and save substrate only.
SHIP TARGET: all listed gaps implemented; critical Add regressions block every stacked PR that changes save flow.
```

Legend: UNIT = pure deterministic test, INTEGRATION = SQL/repository/worker contract, E2E = `WanderUITests`, EVAL = golden-corpus quality gate, LIVE = scheduled hosted canary.

## Test Files and Gates

### Swift unit and repository tests

- `WanderTests/ImportStoreTests.swift`: poll lifecycle, paging, dedupe merge, anchors, retries, cancellation, user/session changes, unchanged state versions.
- `WanderTests/ImportEnvelopeTests.swift`: atomic envelope encoding, hashes, duplicate delivery, version migration, corrupt quarantine, size/type rejection.
- `WanderTests/SharedPlaceSaveFlowTests.swift`: **CRITICAL regression** for all existing Add Been/Wanna details and validation branches plus import commit closure/cancellation.
- `WanderTests/RemoteImportRepositoryTests.swift`: RPC payloads, cursor pages, safe errors, auth/configuration failures.
- Update navigation/profile contract tests for owner-only placement, loading/review states, and feature-flag hiding.

### iOS UI tests

- Add `WanderUITests` in `project.yml` with deterministic `-WanderImportFixture` launch modes.
- Cover each tile, progress transition, mixed failure, complete review list, pagination, candidate correction, duplicates, Been/Wanna save, cancellation, retry, scroll restoration, background/foreground, Dynamic Type, and signed-out capture handoff.
- Physical iPhone acceptance covers real Files imports, system share sheets from Safari/Instagram/TikTok/Notes where available, App Group delivery, extension memory/time behavior, and VoiceOver.

### Worker, SQL, and hosted tests

- Deno adapter unit tests for every golden fixture and safe error code.
- Structured-output evals measure grounded extraction recall, hallucination rate, evidence validity, city disambiguation, duplicate separation, and no-place behavior. Prompt/model changes compare against the checked-in baseline.
- `supabase/tests/place_imports.sql`: schema constraints, RLS, grants, function metadata, ownership, leases, retries, counters, idempotency, duplicate race, cancellation, cleanup.
- Extend `scripts/supabase-smoke-test.mjs` to run authenticated owner/cross-user/anonymous import flows inside the rollback transaction and inspect `prosecdef`, `proconfig`, and grants.
- Scheduled live smoke uses redacted public test URLs and a tiny Apple Maps query; it never mutates tester saves or logs private source text.

Required implementation validation:

```bash
npm --prefix scripts ci --ignore-scripts
node scripts/supabase-smoke-test.mjs
xcodegen generate
xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Wander.xcodeproj -scheme Wander -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

Run local pgTAP where available; an unavailable local Supabase stack is a recorded gap, not a pass. Any iOS-called RPC change must pass the hosted rollback smoke before handoff.

## Observability and Privacy

Record non-PII events for import started, source kind, batch/item counts, processing duration, state transition, confidence bucket, safe error code, review opened, Been/Wanna selected, save completed/cancelled, and artifact cleanup. Do not record captions, notes, filenames, account handles, raw URLs with tokens, precise coordinates, candidate payloads, or personal save fields.

PostHog and Supabase evidence should use internal user IDs and coarse states when investigating failures. The UI must expose enough safe batch/item IDs for support without showing secrets.

## Distribution and Operations

- Add Share Extension and App Group entitlements through `project.yml`; regenerate and audit `Wander.xcodeproj`.
- Configure both app and extension signing/provisioning for Debug, Archive, and TestFlight.
- Add Apple Maps Server API identifier/key and token rotation without committing secrets.
- Configure Meta/TikTok production provider prerequisites and document unsupported states.
- Apply and verify migrations before worker deployment.
- Deploy `import-worker`, install Cron/Vault schedule, and verify scheduled HTTP success.
- Keep `import_places_v1` disabled until hosted smoke, full Swift tests, UI tests, current/smaller-iPhone screenshots, and physical-device share/file QA pass.
- A later explicit release request must package latest `main`, increment the build once, archive/upload with build management disabled, run the TestFlight helper, and post tester-facing Slack notes.

## Stacked PR Plan

### PR 1: Contracts, schema, and security

- Add import models/repository protocols and feature flag with no visible UI.
- Add batch/item/storage schema, owner/service RPCs, RLS, cleanup, pgTAP, and hosted smoke coverage.
- Establish deterministic fixtures and normalized manifest contract.

### PR 2: Worker and four provider adapters

- Add modular Google, Instagram, TikTok, and Text/Notes adapters.
- Add constrained AI hint extraction/evals and Apple Maps Server API client.
- Add import worker, leases/retries, Cron/Vault migration, Deno tests, live smoke, and operations docs.

### PR 3: Shared regular save flow

- Extract Add details/validation into `SharedPlaceSaveFlow` with no visual or behavioral drift.
- Add critical Add regression coverage.
- Add import commit closure support and duplicate-safe repository response handling.

### PR 4: ImportStore, Profile, and review UI

- Add import repository implementation/cache/store.
- Add four owner-only Profile tiles and persistent progress/review button.
- Add source entry, progress, cursor-paginated review, correction, duplicates, retry, and return-anchor behavior.
- Add Swift unit, navigation, accessibility, and visual tests.

### PR 5: Share Extension and UI automation

- Add App Group inbox, Share Extension target/entitlements/signing, host drain, signed-out behavior, and corruption/expiration handling.
- Add `WanderUITests` and deterministic launch fixtures.
- Complete physical iPhone/system-surface QA and update design review evidence.

### PR 6: Integrated acceptance and flag readiness

- Rebase over latest `main`, run all local/hosted/eval/live gates, validate all four sources and 300-place fixture, verify privacy cleanup and account deletion, and prepare flag-enable/release notes.
- Do not enable or release without an explicit user request.

Each PR remains independently buildable and keeps the flag disabled. PRs may merge incrementally, but the feature is not a complete release until PR 6 passes.

## Worktree Parallelization

| Lane | Modules | Depends on |
|---|---|---|
| A1 Contracts/security | `Wander/Models`, `Wander/Services` protocols, `supabase/migrations`, `supabase/tests`, `scripts` | - |
| A2 Worker/adapters | `supabase/functions`, worker docs | A1 manifest/schema contract |
| B Shared save flow | `Wander/Features/Add`, shared save components, `WanderTests` | - |
| C Import UI/store | `Wander/Features/Profile`, `Wander/Features/Imports`, import services/tests | A1 and B |
| D Share Extension/UI tests | extension target, App Group services, `project.yml`, UI tests | A1 and C navigation contract |
| E Integration | all affected modules | A2, C, D |

Launch Lane A1 and Lane B in separate worktrees. After A1 lands, start A2. Merge A1+B before Lane C. Keep `project.yml`/Xcode target work in Lane D only to avoid generated-project conflicts. Lane E is sequential integration.

Conflict flags:

- `docs/agent-log.md` is append-only but high conflict in every lane; rebase and preserve all entries.
- `Wander/Features/Profile/ProfileOwnerHome.swift` belongs only to Lane C.
- `Wander/Services/WanderLocalStore.swift` should receive only narrow successful-save reconciliation changes in Lane C; do not add import collections.
- `project.yml` and generated project membership belong only to Lane D.
- Supabase migrations are sequentially timestamped; Lane A2 rebases after A1 before adding Cron/worker migrations.

## Implementation Tasks

- [ ] **T1 (P1, human: ~2d / CC: ~4h)** - Backend contracts - Add import batch/item schema, private storage, owner/service RPCs, RLS, cleanup, pgTAP, and hosted smoke.
  - Surfaced by: Architecture - durable owner-private batches and seven-day raw-artifact recovery.
  - Files: `supabase/migrations`, `supabase/tests/place_imports.sql`, `scripts/supabase-smoke-test.mjs`, import models/protocols.
  - Verify: local pgTAP when available plus hosted rollback smoke and metadata/grant assertions.
- [ ] **T2 (P1, human: ~3d / CC: ~6h)** - Import worker - Implement modular four-source adapters, structured hint extraction, Apple Maps Server API resolution, leases/retries, Cron, fixtures, evals, and live smoke.
  - Surfaced by: Architecture and code quality - foreground resolution and monolithic worker risk.
  - Files: `supabase/functions/import-worker`, shared adapter modules, worker migration/config/docs.
  - Verify: Deno tests, eval baseline, scheduled hosted smoke, rate-limit/retry tests.
- [ ] **T3 (P1, human: ~1.5d / CC: ~3h)** - Save flow - Extract one shared regular save flow and add import-specific idempotent commit support without Add regressions.
  - Surfaced by: Code quality - private Add state/details/save methods cannot be reused.
  - Files: `Wander/Features/Add`, new shared save feature, `WanderTests/SharedPlaceSaveFlowTests.swift`.
  - Verify: critical focused regressions and full Swift suite.
- [ ] **T4 (P1, human: ~3d / CC: ~6h)** - iOS import experience - Add `ImportStore`, repositories, Profile tiles, progress button, source entry, paginated review, candidate rescue, duplicates, and regular-save navigation.
  - Surfaced by: Code quality and performance - avoid global-store staging and full-batch rendering.
  - Files: `Wander/Features/Imports`, `Wander/Features/Profile`, import services/models/tests.
  - Verify: unit/navigation tests, simulator screenshots, memory/scroll profiling with 300-item fixture.
- [ ] **T5 (P1, human: ~2d / CC: ~4h)** - Share Extension - Add App Group capture envelope, extension target, host drain, signing, and signed-out/idempotent behavior.
  - Surfaced by: Complete all-four capture scope.
  - Files: `project.yml`, app/extension entitlements, extension sources, App Group service/tests.
  - Verify: regenerated project, archive target inspection, real Files/share-sheet QA.
- [ ] **T6 (P1, human: ~2d / CC: ~4h)** - UI and integration coverage - Add `WanderUITests`, deterministic fixtures, full journey coverage, hosted security checks, physical-device acceptance, and feature-flag readiness.
  - Surfaced by: Test review - no current UI target or provider-level worker coverage.
  - Files: `project.yml`, `WanderUITests`, fixture launch routing, QA docs.
  - Verify: full test/build commands, 300-place acceptance, current and small iPhone, physical iPhone.
- [ ] **T7 (P2, human: ~2h / CC: ~30m)** - Durable documentation - Update backend setup, privacy/retention, provider credentials, scheduler, failure recovery, Linear, and agent log after each stack.
  - Surfaced by: Distribution and operations review.
  - Files: `docs/setup.md`, backend docs, privacy/support docs, `docs/agent-log.md`.
  - Verify: operational dry run by a clean checkout/agent.

## Completion Criteria

- Four source tiles and the loading/review button match the design review on current and smaller iPhones.
- A real/redacted 300-place Takeout batch survives background, kill, retry, partial failure, and cross-device review without UI freeze or lost progress.
- Every source yields grounded review items or honest rescue states.
- Every Been/Wanna action uses the regular save flow; imports never bypass personal metadata confirmation.
- Duplicate races cannot overwrite existing saves.
- Raw artifacts delete on schedule; normalized review remains intact.
- Add behavior is unchanged after save-flow extraction.
- Full Swift, UI, Deno, eval, SQL, hosted smoke, live provider smoke, archive-target, accessibility, and physical-device gates pass.
- Feature remains disabled until an explicit flag/release decision.

## GSTACK REVIEW REPORT

- Step 0: Scope Challenge - complete four-source scope accepted as-is, partitioned into stacked PRs behind a disabled flag.
- Architecture Review: 4 issues found and resolved: server-first Apple resolution, duplicate-safe item commit, scheduled background worker, private seven-day artifact storage.
- Code Quality Review: 3 issues found and resolved: shared save flow, dedicated `ImportStore`, modular provider adapters.
- Test Review: coverage diagram produced; 3 primary gaps identified and planned: provider fixtures/live smoke, UI automation, structured AI evals.
- Performance Review: 2 issues found and resolved: cursor pagination and bounded foreground polling.
- NOT in scope: written.
- What already exists: written.
- TODOS.md updates: 2 approved stale-entry updates.
- Failure modes: 0 critical gaps left unplanned.
- Outside voice: skipped; independent reviewer tooling was unavailable.
- Parallelization: 5 implementation lanes; A1+B can start in parallel, later lanes are dependency-ordered.
- Lake Score: 13/13 complete recommendations selected.
- Review status: CLEAN, 0 unresolved engineering decisions, external provider credentials and real fixture acquisition remain execution dependencies rather than architecture ambiguity.
