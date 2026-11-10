# Quick Check-in and Wanna capture

Status: proposal for review, not approved production behavior.
Tracking: [REC-680](https://linear.app/recme/issue/REC-680/explore-quick-check-in-and-wanna-capture-with-optional-details-later).
Source baseline: `743e990b05`. Review routes: `Wander/Features/Add/QuickCaptureReviewHost.swift`.

## Actual app mockups

These review states run inside the real `Wander` app target. They use
`WanderRootView`, `MapPlaceSaveEditor`, the existing profile Activity navigation,
`PlaceProfileFullScreen`, check-in ticket cards, `PlaceRatingSlider`, and
`NotificationSettingsSheet`. The surrounding app layout, typography and controls
come from those shipping views. The earlier standalone prototype and its boards
are superseded; they were not a faithful visual reference for the app.

The proposed additions are a compact editor state, a neutral unrated slider,
a dismissible contextual invitation, an Add details action on an existing visit
ticket, and a reminder preference in existing notification settings. Everything
is gated by an explicit Debug simulator review route. Sample data and save
callbacks are local to the review host. No production persistence, push scheduler,
APNs delivery, analytics contract or backend schema is implemented by this PR.

![Refined date-only capture, horizontal invitation and reminder row](rec-680/actual-refinements.jpg)

![Current editor, quick capture and full editor](rec-680/actual-capture.jpg)

![Contextual invitation and existing activity history](rec-680/actual-return.jpg)

![Exact visit editing, optional details and reminder settings](rec-680/actual-details.jpg)

![Past visits and compact/expanded Wanna](rec-680/actual-wanna.jpg)

![Smaller iPhone](rec-680/actual-compact.jpg)

Reproduction commands live in `preview/rec-680/README.md`.

## Recommendation

Make a visit easy to record and easy to enrich. A check-in with no rating,
photo, note, friends, tags, answers or lists is a complete, valid check-in.
It is not a draft or an overdue task. Optional detail is valuable but never
the price of admission.

Use one compact capture sheet, shared with the existing detailed editor:

1. Place identity, already resolved by search, nearby selection or place profile.
2. A compact, date-only **When** control for Check-in.
3. **Add details** with its field summary and “You can add details anytime.”
4. Stealth mode beneath that disclosure and helper text.
5. Primary **Check in** or **Save to Wanna**.

Expanding replaces the entire compact section with the existing full editor.
The compact and expanded When controls share one date binding, so changes
carry forward and only one When section is visible at a time.

After saving, return to the original map/place context with a modest success
message and **Add details** / **Undo**. Do not insert another required screen.
The exact saved visit is also editable from its history/activity card and
place profile. No completion percentage or missing-rating warning. Pair a
private contextual invitation with an optional, bounded push reminder; details
remain optional and the saved visit remains complete.

Target: one confirmation tap and roughly 3–5 seconds after the intended place
has been resolved. This is a usability target, not a measured result. Place
search, permissions, authentication and poor connectivity can take longer.

## Scenario matrix

| Situation | Recommended path | What persists |
|---|---|---|
| At a place, no time for details | Add → nearby place or existing place card → Check in | Place + new visit + selected date + current audience; rating null |
| At a place, wants details now | Same sheet → Add details → fill any subset → Check in | One visit with only deliberately entered details |
| Logging a visit an hour later | Search/select place → leave today selected or change the date → Check in | Selected visit date; creation time remains separate |
| Logging a past visit with a full memory | Select place → date → Add details → Check in | One backdated visit with optional details |
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
| Visit date | Compact date-only control | Existing When section, using the same date | No duplicate compact row after expansion; existing check-in date bounds retained |
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

The app review reuses the existing question catalog, media picker, friend
chooser and list picker. Uploads, invitations and persistence still require
production integration and regression coverage. The revised native mock uses a
slider: neutral appearance and **Not rated** until the user interacts. The
visual thumb position is independent of the optional stored rating. Opening
the editor, scrolling past, or saving a note must not commit the midpoint. A
deliberate touch of the thumb at 3 selects 3; moving it selects half-point
scores. Remove rating restores nil. VoiceOver adjustment also counts as explicit
input. Editing an already rated visit preserves its prior score without a new
touch. This behavior must be verified in the production custom slider too.

## Returning to a specific visit

Use the navigation already in Astir. Profile has an Activity section and an
Activity history screen with Check-ins / Wanna filters. A row opens the place's
Check-in history. Each dated visit already has its own edit action. Both the
pencil and Add details call the same edit handler for that visit. The clear
**Add details** action appears on the owner's unrated visit ticket; there is no
parallel history hierarchy.

| Entry | Action | Destination |
|---|---|---|
| After save | Add details | Editor for the just-saved visit |
| Contextual map invitation | Add details | Editor for that exact visit |
| Profile | Activity → Check-ins → dated row | Existing place history with dated visit tickets |
| Place history | Add details or existing pencil | Existing editor for that ticket's visit |
| Push notification | Tap | Same exact-visit editor after auth and ownership checks |
| Settings → Notifications → Push types | Check-in reminders | A regular toggle in the existing list |
| Profile | Activity → Wanna | Existing place history and Wanna editing |

The review preserves the app's current edit labels and controls. It does not
introduce standalone Your visits, visit summary, or completion pages. During
production implementation, deep links and history navigation should scroll to
and highlight the referenced visit, especially when a place has many visits.
Edits must keep the original visit ID and time unless the user changes the time.

## Contextual invitation and push reminder

Recommended compact horizontal invitation, shown privately on the next eligible
Map return:

> Add details to your check-in at **Juniper Coffee** →

The place icon, two-line invitation, chevron and 44pt dismiss action share one
row. The invitation itself opens the exact visit. No separate timestamp or
second Add details button adds vertical height.

Do not auto-open the editor. One card at a time; no overdue badges or repeated
nagging for the same event. Dismiss suppresses that event's invitation and its
pending push. The permanent history routes remain available.

Push is a useful complementary experiment, particularly for someone who does
not reopen the app soon. Suggested copy:

> **Add details to your recent check-in**
>
> A rating, photo, or note—whenever you have a moment.

Keep venue, time and personal content out of lock-screen copy. The destination
shows the actual place/date after authorization. Never route a stale tap to the
most recent visit as a substitute. A deleted/unavailable visit should explain
that it is unavailable and offer history; signed-out users resume the same
reference only after sign-in and owner checks.

Proposed scheduling policy for review, not yet implemented:

- Eligible: a quick capture with no optional content, created recently, still
  owned by the user, with no prior invitation dismissal or detail edit. Missing
  rating by itself never qualifies a visit.
- Offer a separate Check-in reminders preference inside existing Notifications
  settings, as a regular **Push types** row. Respect both that preference and
  existing OS/app permission; do not ask for permission in the few-second check-in path. The mock shows an enabled
  example, not a decision to enable a new push type for all existing accounts.
- Initial experiment: one push a few hours after capture, not after a backdated
  visit timestamp. Timing is a product decision; the mock shows the preference
  only, without a separate section or scheduling control. Proposed push copy
  remains in this document.
- At most one reminder per visit and one per account per day, coordinated with
  the existing notification budget. Hold during quiet hours; expire instead of
  delivering a backlog. Exact delay, quiet hours and expiry need product approval.
- Cancel on enrichment, explicit dismissal, deletion, opt-out or account change.
  Recheck eligibility at send time, deduplicate across devices and never resend
  because the reminder was ignored. Saving an intentional no-change edit also
  suppresses further invitations for that visit.
- In-app invitation and push share suppression state. A push already delivered
  cannot be guaranteed retractable; a later tap must still resolve current state.
  Opening a delivered reminder must not manufacture another check-in or rating.

Benefit: more chances to capture useful memories while they are fresh. Cost:
additional interruption and notification fatigue. Evaluate both incremental
useful detail and opt-outs/dismissals against an in-app-only group. Low rating
coverage alone is not a reason to increase reminders. Wanna planning stays
separate from a visit-enrichment reminder.

## In-app review coverage

The launch routes cover the current editor for comparison, compact check-in,
past visit, full details, optional controls, compact and expanded Wanna,
contextual invitation, Profile Activity, place history, exact-visit editing,
and existing notification settings with a proposed reminder preference.

The real editor's save callback is intercepted by the isolated review host. It
updates a sample visit in memory, including an optional rating. No claim of
production durable saving, offline recovery, remote invitation delivery, or
scheduled reminders is made. Existing non-review behavior remains the baseline.

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
8. Respect account-scoped defaults and private answers. The sample review uses the existing Stealth mode control; it is not a change
   to account privacy defaults.
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

Hierarchy: resolved place, date, Add details, Stealth mode, primary save.
Details are discoverable without competing with save. Keep the primary action above the home indicator;
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

## Review validation

The actual Wander Debug app builds successfully. **22 focused native checks
are validated**: five review UI tests and 17 existing rating reaction/summary
tests. The initial refinement run passed 21 checks; the date test could not
dismiss the native calendar. After correcting its dismissal action, that test
passed on a focused rerun. No app change was needed for the date handoff.

UI coverage includes compact and expanded untouched saves, deliberate midpoint
selection, preserving an explicit rating on edit, removing it to nil, Wanna
without ratings, changing the compact date before expansion with no duplicate
When, and both visit-ticket edit actions opening the same unrated visit. The
sample save preserves nil and an explicit 3.0.

Screenshots were captured from the actual target on iPhone 17 Pro and iPhone
17e (iOS 26.5). The final boards cover all review surfaces and the smaller-phone
layout. Capture-script syntax, board composition and diff formatting also pass.
Raw images and test results remain in the issue's evidence directory outside
the worktree; only the six final boards are retained here.

This is development review tooling. The full app test suite, production
rating/save pipeline, hosted RPC checks and push delivery were not exercised.
Those remain required for feature implementation. The earlier standalone
model checks do not validate these actual app routes.

## Measure the tradeoff

Use current `save_flow_opened/submitted/completed` events as a baseline. Any
new properties/events need the existing analytics privacy review and tests.
Suggested aggregate measurements: contextual invitation impressions/dismissals,
reminder opt-outs, incremental enrichment versus an in-app-only group,
time to local save after resolved place,
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
- Untouched sliders remain unrated on new visits, including repeats. This is a
  confirmed design constraint; production end-to-end support is still required.
- Use current account audience defaults and keep silent-save controls reachable
  before committing; do not silently widen visibility.
- Settle reminder opt-in/defaults, delay, quiet hours and cross-channel frequency.
  The revised proposal includes contextual invitations and optional push.
- Make existing celebration behavior nonblocking on the quick path.
- Define historical date precision if adding date-only or approximate inputs.

This exploration adds explicit Debug simulator routes to the actual SwiftUI
target. It does not enable the proposed flows during ordinary app launches or
change schemas, analytics, notification delivery or account data. It does not
authorize a TestFlight release.

## External design reference

Apple recommends minimizing manual input, using appropriate system context
and offering choices where practical. The compact capture recommendation
applies those principles while leaving subjective ratings unfilled.
[Apple HIG: Entering data](https://developer.apple.com/design/human-interface-guidelines/entering-data).

The app has a custom rating track. The review calls its interaction callback
before checking whether the numeric value changed, so a deliberate midpoint tap
counts while untouched display state remains unrated.
