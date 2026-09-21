# Joint check-ins acceptance and regression matrix

REC-566 · Baseline `fb1bad2` · September 21, 2026

This is the required implementation test plan, not a claim that v2 tests already pass. The planning turn read source/tests, queried aggregate production counts read-only, and checked an interactive fictional preview. It did not change the app/database or run native builds. Use only synthetic accounts/content in automated tests.

## Coverage map

```text
Server create/invite/accept -> version + consent + capacity + owned visit
        |                      [V01–V08]       [L01–L17, D01–D08]
        v
Readable contributions -> canonical projection -> every surface
       [P01–P14]           [F01–F10]               [U01–U10]
        v
One engagement identity -> comments/likes/share/push
       [E01–E10] + privacy/alias cases above
        v
Rollout / old clients / rollback / performance [R01–R08]
```

Layers: **SQL** = pgTAP and direct authenticated RPC fixtures; **race** = separate simultaneous database transactions, not sequential mocks; **store** = Swift unit/repository tests; **UI** = native UI tests/manual accessibility evidence; **ops** = controlled internal rollout evidence. Every denied path must assert absence of rows/notifications/stat changes as well as its error.

## Version and historical compatibility

| ID | Fixture/action | Required result | Layer |
| --- | --- | --- | --- |
| V01 | Upgrade schema over v1 groups with existing comments, likes and terminal invitations | IDs, values, authors, timestamps, statuses and engagement unchanged; default version legacy | SQL |
| V02 | Accept an old pending invitation after rollout | Legacy independent visit/thread behavior; no retroactive shared audience | SQL, store |
| V03 | Create a joint draft through v2 | Personal visit/event, group and distinct canonical group event commit together; no intermediate legacy publication | SQL |
| V04 | Add people to an already published solo check-in | Legacy behavior; no comment migration or canonical reparenting | SQL, UI |
| V05 | Two unrelated people visit the same venue/minute | Remain separate groups/visits; no inference | SQL, store |
| V06 | Legacy group has 20 people; new group reaches 10 including pending | Legacy remains intact; v2 accepts tenth and rejects eleventh atomically | SQL, race |
| V07 | Generic unrelated list/contact invitation picker | Existing maximum/behavior unchanged | store, UI |
| V08 | Retry create after lost response | One group/canonical event and invitation generation, no duplicate pushes | SQL, store |

## Personal data preservation

| ID | Fixture/action | Required result | Layer |
| --- | --- | --- | --- |
| D01 | Invitee already has a Friends saved place with labels/answers/attribution | Acceptance inherits Friends and preserves metadata and unrelated visits | SQL, store |
| D02 | Invitee already has Self save; choose Save privately | No visibility widening; independent visit, declined invitation, no accepted membership/alias; atomic/idempotent | SQL, store, UI |
| D03 | Private profile reviews invitation | Join unavailable with explanation; decline/private save work; inbox not discarded | store, UI, SQL |
| D04 | New place acceptance | Note/rating start blank; explicit Everyone/Friends; Self selects private-save alternative | store, UI |
| D05 | Historical joint visit older than latest personal visit | Latest summary remains latest by existing chronology; new historical visit visible at original date | SQL, store |
| D06 | Existing Wanna → Been | Preserve historical want and its data; one new actual visit, correct counts | SQL, store |
| D07 | Saved place/visit deleted after draft or successful accept | No stale replay resurrection; explicit fresh save/restore only | SQL, store |
| D08 | Repeat venue visits and equivalent/merged place IDs | Correct canonical venue parent; distinct occasions stay distinct; one visit counted for this membership | SQL, store |

## Lifecycle, concurrency and recovery

| ID | Fixture/action | Required result | Layer |
| --- | --- | --- | --- |
| L01 | Pending/declined/cancelled/expired invite on feed and both profiles | Only accepted people in attribution; no stats/activity for pending; terminal links honest | SQL, UI |
| L02 | Two accept requests on different devices, same operation | One visit, membership, stats mutation, notification; same committed IDs | race, store |
| L03 | Different operations target same participant/generation | Uniqueness/locking prevent two accepted visits; deterministic conflict or existing result | race |
| L04 | Tenth-seat accept races invite/set/remove | Total owner+pending+accepted never above ten; no partial writes | race |
| L05 | Accept races removal/cancel/source delete | Transaction order yields one valid final state; no orphan accepted membership or revived thread | race |
| L06 | Cross-account operation ID replay | No result/identifier disclosure and no state mutation | SQL |
| L07 | Authorized replay after membership removed, generation replaced or group closed | Terminal/stale result; no resurrection or old-generation acceptance | SQL, store |
| L08 | Invitation revision changed while drafting | Review required, typed personal draft retained, new snapshot shown | SQL, store, UI |
| L09 | Leave/remove accepted nonowner | Owned visit retained at old date, contribution/alias removed, no feed rebump, no copied comments | SQL, store, UI |
| L10 | Reinvite/reaccept surviving visit | New generation, same surviving visit, no doubled stats/activity | SQL, store |
| L11 | Rejoin after standalone visit gains its own engagement | Standalone thread/links retained; no merging/retargeting; group tile uses canonical group thread | SQL, UI |
| L12 | Delete nonowner visit | Only that membership detaches; others and group conversation survive | SQL, UI |
| L13 | Starter deletes, switches Self/private, or account/source disappears | Permanent group closure, thread unavailable, pending cancelled, others’ visits survive; surviving starter visit retains its already-distinct personal event while the canonical group thread stays closed | SQL, UI |
| L14 | Restore starter visibility/account/visit after closure | No implicit group resurrection, old links remain closed | SQL |
| L15 | Edit place/date after acceptance | Explicit detach/close flow; stale/legacy field update denied safely; note/photo edits still work | SQL, UI |
| L16 | App killed/offline during accept, then response lost and retry | Per-account durable op ID, retained draft, server-confirmed accepted state only | store, UI |
| L17 | Switch accounts with in-flight response; two owned edits conflict | No cross-account application; no overwritten unrelated contributions; revision conflict preserves draft | store |

## Privacy, blocking and media

| ID | Fixture/action | Required result | Layer |
| --- | --- | --- | --- |
| P01 | Viewer follows both, one or neither; mutuals differ | Exact per-contribution eligibility; group card only if eligible, no hidden names/counts | SQL, UI |
| P02 | Profile subject hidden but another group member readable | No group card on hidden subject’s activity | SQL, UI |
| P03 | One readable person out of ten | Single-person rendering; no “+9”, hidden photo totals or accessibility hints | SQL, UI |
| P04 | Pending invite visible to source owner | Private management list only; never accepted face pile/coauthor projection | SQL, UI |
| P05 | Block starter ↔ viewer/member | No alternate-member bypass to thread; preserved owned visit independently readable | SQL |
| P06 | Block between two nonowner participants | Mutual identity/media/comment exclusion; unrelated memberships unaffected | SQL, UI |
| P07 | Block/delete a comment or like author | Body, preview, count, liker list, push snippet all consistently filtered | SQL |
| P08 | Nonowner becomes Self/private | Detach public contribution; own visit survives; cache and signed media invalidated | SQL, store |
| P09 | Everyone ↔ Friends, follow/unfollow while thread open | Reauthorize reads/writes and purge stale projection; unauthorized input draft retained locally | SQL, store, UI |
| P10 | Hidden private answers/labels and source snapshot | Absent from every serialized feed/detail/share payload | SQL, store |
| P11 | Hidden owner photo had been selected hero | Replace with readable photo/placeholder; no stale signed URL leaks | SQL, UI |
| P12 | Upload failure, deleted/repeated asset, missing avatar | Accurate ownership, retry by asset ID, correct photo count/fallback, no duplicate upload attribution | store, UI |
| P13 | External share and old cached token after revocation | Venue-only default; no others’ content; authenticated post resolution still filters; explicit export limits stated | SQL, UI |
| P14 | Notification queued before privacy/block/closure change | Reauthorize before send/open; cancel ineligible deliveries, generic safe copy | SQL, ops |

## Engagement

| ID | Fixture/action | Required result | Layer |
| --- | --- | --- | --- |
| E01 | Like/comment from feed, Joe activity, Ryan activity, place history | Same canonical IDs, counts and thread; one like per viewer | SQL, UI |
| E02 | Comment before second participant accepts, then accept | Composer disclosed changing audience at publication; later eligible readers see original thread | UI, SQL |
| E03 | Viewer sees Joe but not Ryan | Ryan’s hidden contribution remains absent; shared comments visible by disclosed union policy except blocked/deleted authors | SQL |
| E04 | Lost comment response/retry, repeated like-set | Idempotent create key; one comment, stable like state, no duplicate notifications | race, store |
| E05 | Comment whitespace, Unicode, exactly 1,000 chars and over limit | Existing server contract respected, no empty/over-limit write, accurate validation | SQL, UI |
| E06 | Child event deep link while grouped then detached | Active authorized alias resolves group; detach terminates alias; never leaks old thread through standalone visit | SQL, UI |
| E07 | Nonowner edits/deletes starter or another person’s content | Denied; own note/rating/photo/comment permissions preserved | SQL |
| E08 | Leave after commenting | Contribution removed; authored comments stay in canonical thread unless individually deleted; confirmation matches behavior; authors can still delete their own comment after losing thread access | SQL, UI |
| E09 | Close canonical thread | No new writes/reads via aliases or legacy RPCs; retained records not reassigned to survivors | SQL |
| E10 | Report group, contribution or comment | Correct target/author and authorized content; existing moderation routes functional | UI, SQL |

## Surface consistency and accessibility

| ID | Fixture/action | Required result | Layer |
| --- | --- | --- | --- |
| U01 | Two accepted people | Two faces, both ratings/notes, one engagement row | UI |
| U02 | Ten accepted people, profile subject accepted last | Own contribution included first when collapsed; stable header/conversation; expand all ten | UI, store |
| U03 | Switch feed ↔ each profile ↔ details after edit | Same contribution values, IDs and engagement; no per-surface copies | UI |
| U04 | Accepted with no rating/note/photos | Appears without fabricated values; self gets optional add prompt | UI |
| U05 | Large Dynamic Type, VoiceOver, long/localized/RTL names, emoji-only note | Readable attribution/ratings/controls, no overlap, sensible traversal and announcements | UI |
| U06 | iPhone 17 Pro, compact iPhone 16e, iPad Air | Fits native layout/safe areas; no clipped action row, keyboard or ten-person list | UI |
| U07 | Light/dark, reduced motion, enlarged text/contrast | Existing Astir design and accessible states retained; no color-only status | UI |
| U08 | Accept/decline error, capacity full, upgrade required | Clear recovery copy, no double submit, personal draft retained | UI |
| U09 | No-photo hero / text-only group / ten long notes | Bounded collapsed card, expansion preserves context and scroll position | UI |
| U10 | Pending invitation on own activity and recipient decline | Private inbox/banner separated from activity; no phantom personal check-in | UI |

## Pagination, rollout and operations

| ID | Fixture/action | Required result | Layer |
| --- | --- | --- | --- |
| F01 | Viewer follows every participant | One canonical card, no repeated visits per feed page | SQL |
| F02 | Canonical candidates span page boundary | Dedupe before keyset cursor; no duplicates/gaps on stable fixture | SQL |
| F03 | Accept/edit after original publication | Original sort date, no rebump; expected refresh only | SQL, store |
| F04 | Detach while paginating | No new event storm; consistent canonical/standalone identities on refresh | SQL, store |
| F05 | Mixed legacy bundles, solo events and joint groups | Legacy grouping intact; same-actor/time bundler never swallows canonical joint identity | store |
| F06 | Ten members each with photos and long notes across a full page | Bounded payload and batch hydration, no per-person request loop | SQL, store |
| F07 | Query plan on realistic synthetic volume | Indexed associations, keyset paging; no full-table repeated scan per card | SQL |
| F08 | Compare feed scrolling/page latency to baseline fixture | Record actual timings/request counts; investigate material regression before flag enablement | UI, ops |
| F09 | Profile/stats/place counts across join/leave/rejoin | One owned visit per occasion; group size does not inflate visits/unique places/streak | SQL, store |
| F10 | Two groups same venue, concurrent updates | Independent stable identity; no cache key collision | SQL, store |
| R01 | Each legacy accept/set/invite/engagement RPC targets v2 | Upgrade-required, no mutation; v1 unchanged | SQL |
| R02 | Old client reads v2 social feed/child links | No misleading shared thread or private payload; unsupported social projection excluded | SQL |
| R03 | Old client edits own note/photo or deletes source/child | Owned operation reconciles membership server-side; no bypass of locked occasion | SQL |
| R04 | Migration deployed with creation flag off | Zero new v2 creates; v1 works | ops, SQL |
| R05 | Turn new-v2 creation off after successful internal groups | Existing v2 reads, edits, leave/delete remain supported; no split conversation | ops |
| R06 | Roll forward after flag off / failed client rollout | Version data retained and valid; no replay/new-generation corruption | ops, SQL |
| R07 | Anonymous/session-expired/direct REST access to tables and RPCs | Existing RLS/grants remain narrow; no credential or content leak | SQL |
| R08 | Metrics and alerts under failures | Aggregate allowed fields only; duplicate visit/card and denial signals useful without private text | ops |

## Execution and evidence gate

Read and extend the existing `supabase/tests/shared_visits.sql`, repository/shared-visit tests in `WanderTests/RemoteRepositoryTests.swift`, store tests in `WanderTests/WanderStoreTests.swift`, activity engagement tests and profile/feed UI fixtures. Keep meaningful assertions on database state and authorization; a screenshot alone cannot verify identity or privacy. Add multi-transaction tests for L02–L05 instead of calling a mock twice.

Run SQL against a local/isolated test database with fictional accounts using the project’s supported test runner. Never seed or mutate production to exercise cases. Validate grants and SECURITY DEFINER search paths as well as successful responses. For iOS, inspect exact existing device UDIDs and run through the mandatory helper:

```sh
python3 ../.tools/ios-work.py status
xcrun simctl list devices --json
python3 ../.tools/ios-work.py build -- test -quiet -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,id=<existing-device-UDID>' -only-testing:WanderTests -only-testing:WanderUITests CODE_SIGNING_ALLOWED=NO
```

Select focused test identifiers as the implementation adds them; do not treat the placeholder command as a completed run. Use the existing standard/compact/iPad devices, comply with free-space/build limits, and preserve the final relevant results/screenshots. Do not launch new simulators or bypass reservations.

Before rollout, attach: all case IDs and pass/fail/waiver reason, SQL run output and race results, native result bundle, light/dark/large-text screenshots, request/query measurements, legacy fixture before/after comparison, and flag-off/rollback evidence. Any privacy leak, duplicate visit, merged historical engagement, lost parent metadata, inconsistent surface conversation or silent audience change blocks release. A deliberate scope change requires updating the plan and tests together.
