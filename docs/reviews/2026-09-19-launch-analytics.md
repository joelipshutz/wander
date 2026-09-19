# Astir launch analytics audit — September 19, 2026

Tracking: [REC-170](https://linear.app/recme/issue/REC-170). Audited latest main `0cce1b8`, live PostHog project 557259, and dashboard 1994904.

## What was wrong

1. Retention divided by every onboarded user, including people not yet old enough for D7/D30. It joined raw `distinct_id` and did not apply the project's internal-user exclusion. The live old result contained one onboarding cohort member; those percentages are not a useful launch baseline.
2. Activation required a follow before onboarding completion. Following is optional; people who followed later or created value without following were lost. `onboarding_auth_completed` also fires during remote profile resolution, so it is not a clean new-signup success event.
3. A first check-in can emit both `check_in_created` and `place_saved(been)`. Summing them overstates core actions. Human-need engagement includes profile views and streak celebrations, so it also cannot serve as the core-value numerator.
4. The dashboard did not distinguish new feature reach, core usage, save-editor abandonment, and backend sync. Events waitlist registration and In Common invitation creation/sharing/opening had no dedicated logging.
5. Debug/simulator traffic had no reliable build-environment property. The existing Internal / Test users cohort has **zero members**; checking “filter test accounts” alone does not solve this.

## Changes in this pass

- Keep all existing raw events; introduce schema 3 and an unduplicated `core_action_performed` event for Wanna creation and check-ins.
- Add immutable common environment metadata; suppress authenticated simulator fixtures and preserve existing no-autocapture/no-replay/GeoIP-disabled settings.
- Instrument the shared save editor's exposure, validated submission and result. Pending/local completion remains distinct from synced success. Failed validation before submission is not a network attempt. Account changes suppress late completion attribution.
- Instrument full place-profile exposure, Events waitlist request/result, and live In Common creation/native share completion/recipient opening. Existing cached registrations and stale-account completions do not inflate conversions.
- Preserve non-content analytics: no names, notes, query text, invitation tokens, recipient IDs, locations, photos, or raw errors. Strengthen case-insensitive filtering for known forbidden keys.
- Rebuild the same managed dashboard with active/core-active users, core volume, feature reach, save outcomes, discovery/import sources, waitlist conversion, independent invitation actors, mature retention, auth/sync diagnostics, and an ingestion inventory. Revenue remains blank; future Events RSVP/attendance is not presented as shipped.

## Current feature coverage

| Product area | Evidence / launch measurement | Limit |
|---|---|---|
| Signup and onboarding | Existing carousel/auth/step/permission/completion events; strict install funnel plus resumed-onboarding funnel | Provider auth result is Apple/Google only; required identity includes photo but no per-field drop-off |
| Map / Feed / Lists / Profile / Add | Existing `app_surface_viewed`; new full place-profile exposure | Exposure is not a feed impression, map-pin impression, or time-spent measure |
| Wanna / Check-in / repeat visits | Existing domain events plus derived core event and editor funnel | Local save creation is not cloud durability; inspect sync outcomes |
| Search / discovery | Existing search submit/results/provider/rank selection and new full profile exposure | Map search has selection coverage, not an equivalent submitted/results funnel; never record query text |
| Imports and review | Existing queued batch and local matching completion; source-type saves and extraction diagnostics | Matching is not successful review/save completion; unresolved-selection/recovery stages need their own follow-up contract |
| Lists and collaboration | Existing list-created and item-added events include owner/collaborator role, source surface, and companion save | No list-open/share/accept funnel yet |
| Follow / like / comment / shared visits | Existing domain success events and normalized human-need actions | No cross-person recommendation credit or viral coefficient claim |
| In Common | New created/shared/opened events | Sender and recipient are different people; shown as separate series, never a same-person funnel |
| Events | Existing teaser surface plus new server-confirmed waitlist request/result | No RSVP, payments, attendance or event retention until that feature ships |
| First-use guidance | Existing onboarding and resulting action events | Per-coach impressions, completion vs dismissal, and walkthrough version are a follow-up |
| Notifications / Calendar / streaks | Existing explicit client events and aggregate server operational dashboard | APNs acceptance is not display; open/accepted ratio is directional, not attributable delivery conversion |
| Feedback / settings | Existing feedback success/attachment counts; permission/upsell events | No content collection; no general settings clickstream |

Declared but currently unused legacy constants (`first_place_started`, `place_candidate_shown`, `check_in_started`, `discover_filter_used`, `social_place_saved`) must not be treated as live coverage. This pass uses explicit new editor events rather than repurposing undefined historical semantics.

## Launch interpretation and follow-ups

**Before interpreting launch metrics:** ship the instrumented binary, verify real test-account events, and classify known staff/review users in cohort 481950 or with `$internal_or_test_user=true`. The cohort's membership is not guessed from device/build, an email domain, or the current repository. Release device traffic includes TestFlight; use release build boundaries when evaluating App Store launch. The schema-3 baseline deliberately remains empty before deployment; older traffic is visible in the inventory.

**Next instrumentation priority:** import review/recovery outcomes, Map search submit/zero-results, list view/share/invitation acceptance, and contextual NUX viewed/completed/dismissed. Define these with owner/source and success boundaries, without private IDs or content. These gaps are explicit proposals, not claimed as completed in this pass.

**Later product decisions:** deferred install/referral attribution and downstream recommendation credit require a real attribution design. Monetization and full Events behavior require their actual product contracts.

## Verification and deployment state

- All 31 managed insights refreshed successfully through the Insights API (zero query errors). A temporary SQL-only fixture verified all four retention horizons: mature cohorts produced 50% and immature cohorts null; the fixture was soft-deleted without ingesting events. The checked-in `analytics:verify` command now supports repeatable saved-insight validation.
- Dashboard contract tests, syntax parsing of the 13 modified Swift files, and Git whitespace validation pass. Syntax parsing is not an iOS compilation or test pass. New native tests cover core-action cardinality, immutable environment context, forbidden-key aliases, editor exposure deduplication, waitlist failure/retry, and stale-account completion suppression.
- The Mac build helper refused the full unit run at **49.4 GiB free**, below the user-required 50 GiB floor. Its cleanup preview found **0.0 GiB eligible**. No unrelated data was deleted; no build limit was bypassed. Native compile/tests and live changed-event smoke remain outstanding.
- The existing scoped API key verified dashboard/insight read access, but returned HTTP 403 for project settings and direct query access. Existing Chrome access confirmed project settings; the account registry records the exact scope gap. No credentials were created, rotated, or broadened.
- App changes require PR review, native validation, merge, and a separately requested release. Applying dashboard definitions does not ship instrumentation or backfill historical events.

## Observed ingestion before this release

The 30-day inventory returned 148 event/build combinations across 46 named events. It includes unclassified historic/test activity and server operations, so these are coverage checks, not customer conversion rates: 242 sessions, 12 raw place saves, 9 check-ins, 33 own-place sync attempts (32 successes, 1 failure), and 1 onboarding completion. Recent event rows include builds 175 and 176. The server notification snapshots and seven frequency buckets are present. There are no schema-3 events yet; changed-event end-to-end acceptance is still required.
