# Quick Check-in and Wanna capture

Status: proposal for review, not approved production behavior.
Tracking: [REC-680](https://linear.app/recme/issue/REC-680/explore-quick-check-in-and-wanna-capture-with-optional-details-later).
Source baseline: `743e990b05`. Native harness: `preview/rec-680/`.

## Native mockups

![Quick capture, optional details and later editing](rec-680/quick-capture-proposal.jpg)

![Retrospective visit, Wanna and saved visit](rec-680/other-capture-paths.jpg)

![Dark appearance and compact phone layouts](rec-680/adaptive-capture.jpg)

These are native SwiftUI simulator captures, assembled into review sheets.
They are an isolated prototype, not screenshots of a changed production app.

Validation: the standalone arm64 iOS simulator app compiles and runs; standard
and expanded layouts were captured on iPhone 17 Pro and iPhone 17e with iOS 26.5.
Light and Dark captures were inspected. Python capture-script syntax and shell
build-script syntax passed. Production app tests and hosted save checks were
not run because the production target is unchanged. Larger-text capture timing
was unreliable in this simulator session; accessibility readiness is not claimed.

## Recommendation

Make a visit easy to record and easy to enrich. A check-in with no rating,
photo, note, friends, tags, answers or lists is a complete, valid check-in.
It is not a draft or an overdue task. Optional detail is valuable but never
the price of admission.

Use one compact capture sheet, shared with the existing detailed editor:

1. Place identity, already resolved by search, nearby selection or place profile.
2. Editable visit time and visible audience/notification controls.
3. Primary **Check in** or **Save to Wanna**.
4. Secondary **Add details**, expanding to the complete editor in place.

After saving, return to the original map/place context with a modest success
message and **Add details** / **Undo**. Do not insert another required screen.
The exact saved visit is also editable from its history/activity card and
place profile. No completion percentage, missing-rating warning or reminder
notification in the first version.

Target: one confirmation tap and roughly 3–5 seconds after the intended place
has been resolved. This is a usability target, not a measured result. Place
search, permissions, authentication and poor connectivity can take longer.

## Scenario matrix

| Situation | Recommended path | What persists |
|---|---|---|
| At a place, no time for details | Add → nearby place or existing place card → Check in | Place + new visit + time + current audience; rating null |
| At a place, wants details now | Same sheet → Add details → fill any subset → Check in | One visit with only deliberately entered details |
| Logging a visit an hour later | Search/select place → time control → An hour ago or specific date/time → Check in | Actual visit time separate from record creation time |
| Logging a past visit with a full memory | Select place → time → Add details → Check in | One backdated visit with optional details |
| Adding details after a quick save | Open that visit → Add details → Save changes | Update the same visit ID and original time, not a new visit |
| Returning to a place | New Check in action | A new visit, with no assumed new rating or reused note/photos/friends |
| Keeping a place for later | Explicit Wanna action → Save to Wanna | Wanna event; no rating or visited timestamp; planned date optional |
| Wanna with plans | Add details before or after saving | Notes, tags, lists, planned date, people and existing Wanna-specific fields |
| Existing Wanna, now visiting | Check in → save a new visit | Preserve Wanna unless explicitly removed through the existing choice |
| Offline or slow save | Durable local save, then clearly indicate pending sync | Stable ID and retry state; no claim of server confirmation |

Do not force another mode-choice step after an explicit Check in or Wanna
action. Preserve REC-354's independent mode drafts if an ambiguous entry
still exposes the mode switch. Location denial must leave search usable.
Nearby suggestions should never silently choose a venue or create a visit.

## Field hierarchy

| Data | Compact sheet | Optional editor | Meaning |
|---|---|---|---|
| Place | Name, area, inferred type | Type/name correction where supported | Required resolved identity; no repeated categorization task |
| Visit time | Visible and editable | Same date/time control | Required visit context; editable after capture |
| Audience | Visible account default | Same setting | Existing Everyone/Friends/Self semantics |
| Silent notification choice | Audience menu, status shown when silent | Explicit toggle | Independent from audience; never a privacy substitute |
| Rating | Absent | Not rated → explicit selection; remove available | Nullable; no 0/3 placeholder score |
| Note | Absent | Optional text with existing mentions support | Belongs to the selected visit or Wanna |
| Photos | Absent | Existing add/remove/upload controls | Preserve per-visit ownership |
| Friends | Absent | Existing invitation and acceptance flow | No automatic tagging or copied participants |
| Lists | Absent | Existing multi-list picker | Organizes place; list failure must not create duplicate visit |
| Tags/personal labels | Absent | Existing taxonomy and custom labels | Preserve established ownership and privacy contracts |
| Useful details | Absent | Existing questions, Customize and per-answer visibility | Full catalog remains; no default answers |
| Wanna plans | No date required | Planned date, people and existing supported detail | No false visit or rating |

The native harness groups these controls to demonstrate hierarchy. It does
not replace the production question catalog, media picker or friend chooser.
Those should be reused during implementation. The rating picker shown is one
possible optional-input treatment; the existing liquid slider can remain if
opening it does not commit its initial position. Choosing 3/5 must be as
deliberate as choosing 5/5.

## Alternatives and tradeoffs

| Approach | Benefit | Cost / risk | Recommendation |
|---|---|---|---|
| Compact sheet with expandable details | Fast default, visible privacy/date, full editor one tap away | Optional features less prominent | Start here |
| Immediate one-tap commit from every place tile | Absolute fewest taps | Easier wrong venue/time/audience, harder recovery | Consider later for an explicitly labeled shortcut |
| Separate Quick and Full buttons/modes | Makes both paths explicit | Adds a decision on every save; duplicates navigation/drafts | Avoid |
| Keep the full form but make fields optional | Small implementation | Visual workload still implies work; rating defaults remain dangerous | Insufficient |
| Save, then require a details screen | Captures the visit early | Still feels like a multi-step obligation | Avoid; offer Add details without forcing it |

Benefits: more moments captured, less interruption while with friends,
honest ratings, support for casual and meticulous users, and reuse of the
existing detailed editor.

Costs: fewer immediate ratings/answers, possible sparse social cards, delayed
details forgotten, more accidental saves if confirmation is removed, and more
complex distinction between create/edit/retry. Preserve searchable visit
history, recognizable later-edit entry points and Undo; measure enrichment
without making it mandatory. A visit says someone went there, not that they
recommend it. Never style an unrated visit as a positive recommendation.

## Source findings and engineering requirements

The current editor already has one screen (REC-354). The remaining burden is
the amount of information presented before saving. `detailsContent` includes
rating, note, date, place type, questions, participation, more options, silent
controls and visibility. Changing screen count alone will not solve that.

The rating issue crosses layers:

- `MapPlaceSaveEditor.selectedRatingScore`, mode drafts and
  `PlaceSaveDraftForm.selectedRatingScore` are nonoptional.
- Editor initialization and mode resets fall back to `PlaceRating.defaultScore`.
- `PlaceRating.scoreForSave(status:score:)` converts nil to 3 for Been saves;
  `WanderLocalStore` calls it for creating and updating visits and saving places.
- Several persisted models and remote request/response properties are optional.
  This is useful groundwork, not proof the full hosted path preserves null.
- REC-628 explicitly accepted previous ratings as repeat-visit defaults. This
  proposal supersedes that behavior only for an unconfirmed new visit rating.

Required invariants for implementation:

1. A new visit starts with `rating = nil`; quick saves and untouched full forms
   retain nil end to end. Showing a previous score must not submit it. Optional
   **Use previous rating** is acceptable only after an explicit tap.
2. Editing an existing rated visit preserves its rating. Removing a rating is
   a distinct write from leaving it unchanged. Specify omitted vs null vs
   explicit clear in the RPC payload, including backward compatibility.
3. Never erase all historical 3.0 values. Some are genuine ratings; without
   trustworthy provenance, an automatic cleanup would destroy user input.
4. Visit cards show Not rated (or omit the score) and never fall back to another
   visit's or parent-place rating. A newer unrated visit does not erase the
   history of an earlier explicit rating.
5. Rating averages/counts exclude missing values. A check-in count can rise
   without a rating count rising. Audit Featured, filters, pins, recommendation
   language and search; retain existing aggregation semantics otherwise.
6. Enrichment targets the original visit ID. Retries and repeated taps are
   idempotent. Editing must not create another core action, change visit time,
   reorder a historical visit as new, or resend a fresh check-in notification.
7. Adding friends later retains consent and acceptance rules. New invitations
   may notify their recipients; ordinary edits must not notify the whole audience
   again. Silent changes cannot retract already delivered notifications.
8. Respect account-scoped defaults and private answers. The sample audience
   in the mockup is Friends; it is not a change to the app's default privacy.
9. Only show local success after durable local persistence. Show pending sync
   honestly and provide retry/error recovery. A failed enrichment leaves the
   original quick visit intact; list/photo failures remain recoverable separately.
10. Draft restoration and mode switching preserve nil vs explicit rating, notes,
    photos and choices without leaking values between Wanna and Check-in.
11. Store visit time separately from creation/update times. Do not assert live
    presence from a manually selected or historical visit. If date-only input is
    supported, define precision rather than inventing a confident exact time.
12. Review the existing full-screen daily streak celebration: a quick capture
    should not force an additional dismissal. Prefer a nonblocking cue in this
    path, with an explicit product decision before changing the existing contract.

Suggested structure: reuse `MapPlaceSaveEditor` and its submission/repository
boundary, add a compact presentation state, and bind both compact and full
surfaces to the same draft. Avoid a second save service or model. Route later
editing by stable visit/Wanna identity, not merely by place ID.

```text
Nearby / Search / Place / explicit shortcut
             ↓ resolved place + explicit intent
       Compact capture sheet
         ↕ same unsaved draft
       Optional full details
             ↓ existing save boundary
       Durable local event → pending sync → confirmed
             ↓ stable event ID
       Later enrichment → update same event
```

## Design review and validation plan

Hierarchy: resolved place, time/audience, primary save. Details are discoverable
without competing with save. Keep the primary action above the home indicator;
large text expands the sheet and scrolls instead of shrinking text. Existing
typography, coral action color and adaptive paper/ink surfaces remain.

Interaction coverage: initial/expanded/edit states, dismiss with entered data,
save-in-progress, local pending, failure/retry, success/undo, duplicate taps,
changed audience, denied location, ambiguous nearby candidates and no results.
The mockups demonstrate layout and local interactions; production failure,
offline, draft and privacy behavior require separate implementation tests.

Accessibility: minimum 44pt controls, explicit audience labels, VoiceOver
Not rated and selected score announcements, dynamic labels, no color-only
state, keyboard-safe save and scrolling. Verify Reduce Motion, VoiceOver and
largest supported text during production QA. The static screenshot set is
not a substitute for those checks.

Production regression plan: unrated new/repeat create, explicit midpoint,
fractional score, remove rating vs unchanged edit, legacy draft decode, mode
round-trip, delayed enrichment, retry/idempotency, offline restore, account
switch, Wanna independence, historical time/order, visibility/invitations,
aggregate null exclusion and list/photo partial failures. Run the full native
suite plus hosted rolled-back save/RLS checks for any touched RPC contract.

## Measure the tradeoff

Use current `save_flow_opened/submitted/completed` events as a baseline. Any
new properties/events need the existing analytics privacy review and tests.
Suggested aggregate measurements: time to local save after resolved place,
completion/abandonment, quick vs expanded route, explicitly rated share,
optional-field-group usage, enrichment within 24 hours / 7 days, edits versus
new visits, duplicate/undo rate and sync failures. Compare cohort quality and
total useful contributions, not just ratings per check-in.

Never log notes, precise visit times/coordinates, place or person content,
raw queries, photo data, friends or lists. Timings should be coarse buckets;
field usage should be booleans/counts without content.

Usability check: observe testers performing quick now, retrospective, full
now, enrich later and Wanna tasks. Verify they recognize quick capture as
finished and can find details later. Launch behind the shared feature-flag
platform after null-rating contracts and checks pass; keep the full editor
available. Rollout metrics are a proposal, not instrumentation added here.

## Decisions to settle before production

- Accept compact capture as the default and retain a single optional full editor.
- Require explicit rating selection for each new visit, including repeats.
- Use current account audience defaults and keep silent-save controls reachable
  before committing; do not silently widen visibility.
- Keep later enrichment free of unsolicited reminders in the first version.
- Make existing celebration behavior nonblocking on the quick path.
- Define historical date precision if adding date-only or approximate inputs.

This exploration does not change production SwiftUI, schemas, analytics,
notifications or account data, and does not authorize a TestFlight release.

## External design reference

Apple recommends minimizing manual input, using appropriate system context
and offering choices where practical. The compact capture recommendation
applies those principles while leaving subjective ratings unfilled.
[Apple HIG: Entering data](https://developer.apple.com/design/human-interface-guidelines/entering-data).
