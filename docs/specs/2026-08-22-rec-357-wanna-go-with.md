# REC-357 — Event-based Wanna and Wanna Go With

Status: implementation-ready product and interaction specification for the first SwiftUI prototype slice.

Linear: [REC-357](https://linear.app/recme/issue/REC-357/make-wanna-event-based-and-add-wanna-go-with-planning)

## Summary

A Wanna is an immutable moment: a user said they wanted to go to a place at a particular time. It also contributes to the user's current relationship with the place while it remains active.

The product must stop treating `Been` and `Wanna` as mutually exclusive historical facts. A person may have been somewhere and still actively want to return. Feed and activity preserve every Wanna and check-in event; map filters and place actions use a derived current relationship.

Wanna Go With adds an optional planning layer to an ordinary Wanna:

> I wanna go to Gnarwhal Coffee with Joe and Maia on August 28.

People and date are optional. The ordinary Wanna flow stays lightweight. Planning controls live in a progressive disclosure and reuse the existing friend picker, invitation inbox, notification, visibility, date, reminder, Feed ticket, and map-pin systems.

## What already exists

- The ordinary Wanna and Been save paths, including optional planned date and reminder UI.
- The map's owner/social and solid/dashed visual grammar, which must remain the primary place-state encoding.
- Feed tickets and immutable Feed event concepts.
- Shared Visit's multi-person picker, invitation inbox, participant shelf, and independent-save privacy principles.
- Everyone/Friends/Self visibility, account privacy, blocks, and stealth behavior.
- Place profile, activity, and notification deep-link surfaces.

The prototype reuses that language, but not Shared Visit's visit-anchored backend contract.

## NOT in scope

- Production Supabase tables, migrations, RPCs, RLS, or hosted smoke changes.
- Production notification delivery, reminder scheduling, or analytics dashboard changes.
- Automatically deciding whether a participant attended after the planned date.
- Open joining, public event discovery, group chat, reservations, payments, or calendar sync.
- Enabling the feature for TestFlight or Release builds before prototype approval.

## Information architecture

```text
Place / Add flow
  └─ Wanna
      ├─ Save Wanna → ordinary immutable Wanna event
      └─ More Options
          ├─ Go with people → multi-select friend picker
          ├─ When? → optional date
          └─ Sharing → Share on Feed | Private
              └─ Save & invite → creator Wanna + one plan + N invitations

Invitation inbox
  ├─ I'm in → invitee-owned Wanna + accepted participant
  └─ Not this time → declined participant, no Wanna

Active plan
  ├─ Feed / Activity ticket
  ├─ Additive map halo
  └─ Plan detail → participants, date, sharing, cancel/leave

Repeat check-in while Wanna is active
  └─ Save check-in → Keep in Wanna | Remove from Wanna
```

## Product principles

1. **Moments are immutable; current state is derived.** Historical activity never disappears because a later event changed the relationship.
2. **Been and active Wanna may coexist.** `hasVisited` and `hasActiveWanna` are independent facts.
3. **Every participant owns their own place state.** An invitation cannot copy notes, tags, ratings, answers, photos, or stealth state into another person's save.
4. **One plan, independent invitations.** A group plan coordinates people without merging their personal records.
5. **Ordinary Wanna remains ordinary.** No required invitee, date, visibility decision, or RSVP step is added to the base case.
6. **Social by default, private when chosen.** A normal plan is a statement to the creator's allowed Feed audience. A Private plan stays among its participants.
7. **Stealth fails closed.** Stealth users and stealth saves never leak through plan tiles, participant counts, notifications, map decoration, or attribution.

## Vocabulary

| Term | Meaning |
|---|---|
| Wanna event | An immutable record that a user wanted to go to a place at a moment in time. It may be active or fulfilled. |
| Active Wanna | A Wanna event that still contributes to the user's Wanna filter. |
| Visit event | An independent check-in event. Multiple visits are allowed. |
| Relationship | Derived facts about a user and place: `hasVisited`, `hasActiveWanna`, and any active plans. |
| Plan | Optional coordination attached to the creator's Wanna event: place, optional date, visibility, lifecycle, and invitees. |
| Participant | Creator or invitee with an independent RSVP state. Acceptance creates the invitee's own Wanna event. |

## Relationship projection

The presentation layer must be able to express all four combinations:

| `hasVisited` | `hasActiveWanna` | Meaning | Filters |
|---|---|---|---|
| No | No | No current relationship | Neither Been nor Wanna |
| No | Yes | Wants to go, never checked in | Wanna |
| Yes | No | Has been and has no active return intent | Been |
| Yes | Yes | Has been and actively wants to return | Both Been and Wanna |

`PlaceStatus` may remain as a compatibility projection during migration, but new UI and APIs must not use it as the sole source of truth.

## Condition and outcome table

### Wanna and check-in events

| Starting condition | Event | Historical result | Current relationship | User-facing result |
|---|---|---|---|---|
| No visit, no active Wanna | Add Wanna | Create active Wanna event | Wanna | Normal save confirmation |
| Active Wanna exists | Add Wanna again | Create another active Wanna event | Still Wanna | New activity moment; no duplicate-state warning |
| No visit, one or more active Wannas | First check-in | Create visit; fulfill all active Wannas | Been, not Wanna | Save completes with no extra prompt |
| Visit exists, no active Wanna | Add Wanna | Create active Wanna event | Been and Wanna | Place appears in both relevant filters |
| Visit exists, active Wanna exists | Repeat check-in | Create visit first | Temporarily Been and Wanna | Post-save speed bump asks whether to keep it in Wanna |
| Repeat check-in speed bump: Keep | Confirm Keep | No Wanna event is changed | Been and Wanna | Dismiss; place stays in Wanna filter |
| Repeat check-in speed bump: Remove | Confirm Remove | Fulfill all active Wanna events | Been, not Wanna | Dismiss; history remains in activity |
| Last visit deleted, active Wanna exists | Delete visit | Delete only that visit | Wanna, plus any remaining visits if applicable | Never reopen a fulfilled Wanna automatically |
| Active Wanna manually removed | Remove from Wanna | Fulfill active Wanna events | Been only if visits remain; otherwise no current relationship | Historical Wanna moments remain visible |

The post-check-in prompt appears only after the visit has saved successfully:

> Keep Gnarwhal Coffee in Wanna?
>
> You checked in, but you can keep it saved for another time.
>
> **Keep in Wanna** · **Remove from Wanna**

Dismissal defaults to Keep so a network interruption or accidental swipe cannot silently remove intent.

### Plan creation and invitation

| Starting condition | Event | Creator outcome | Invitee outcome | Feed/inbox outcome |
|---|---|---|---|---|
| Any relationship | Add Wanna with no people/date | Create ordinary active Wanna | None | Ordinary Wanna Feed event according to save visibility |
| Any relationship | Add one or more people | Create active Wanna plus one plan | Pending invitation per person | Plan tile on creator Feed if shared; invitation in every invitee inbox |
| Plan has no date | Pick date later | Update plan date and creator Wanna date | Notify pending/accepted invitees | Feed update only if material and shared; avoid duplicate spam |
| Pending invite | Accept | Plan unchanged | Create invitee-owned active Wanna and accepted participant row | Acceptance notification; invitee may publish their own accepted Wanna according to plan visibility and stealth |
| Pending invite | Decline | Plan remains for others | No Wanna created | Creator sees declined state; no public decline event |
| Accepted participant | Leave plan | Plan remains for others | Participant row becomes left; independently owned Wanna remains active | Notify creator privately; no public leave event |
| Creator | Cancel plan | Plan becomes cancelled | Invitees are notified; independently owned accepted Wannas remain active | Shared plan card becomes cancelled in activity; no place state is deleted |
| Creator | Remove one invitee | New invitation generation is cancelled | That person's independent Wanna remains | Private notification only |
| Creator | Add another invitee | Existing participant states remain | New independent pending invitation | Same plan, not a duplicate plan |
| Any participant | Check in | Only that person's active Wanna is fulfilled using the check-in rules | Other participants unchanged | Plan remains active in this iteration |

## Multiple people

One plan supports one creator and zero or more invitees. Joe and Maia receive separate invitation records with separate lifecycle, notification, retry, and acceptance state.

The creator sees a compact participant shelf:

- **Going:** creator plus accepted invitees.
- **Invited:** pending invitees.
- **Declined/left:** visible only in plan management, not on the primary card.

Participants can see the other non-stealth participants in the same plan. Pending invitee identities are visible only to the creator and other direct participants, never to the creator's follower Feed. A stealth participant is omitted entirely from every public rendering, including counts that would reveal their presence.

Acceptance creates an independent Wanna using only safe shared defaults:

- place identity;
- plan reference;
- optional planned date;
- place category/subcategory when already canonical.

It does not copy note, tags, answers, ratings, photos, personal labels, or the creator's visibility.

## Visibility and stealth

The planning disclosure contains a two-option control:

| Option | Helper copy | Behavior |
|---|---|---|
| Share on Feed | “People who can see your saves can see this plan.” | Creates a plan event on the creator's follower/friend audience according to the underlying save visibility. |
| Private | “Only you and the people invited can see this.” | No follower Feed event. Plan is available only through participant activity, inbox, notifications, and direct plan/place surfaces. |

This is not a global public feed. Existing Everyone/Friends/Self and block rules remain authoritative.

Stealth behavior:

- If the creator or underlying Wanna is stealth, Share on Feed is disabled and Private is selected.
- A stealth invitee can receive and accept a private invitation, but is never named, counted, or attributed on a public plan tile.
- If a plan is shared and a participant later turns on stealth, public projections are recomputed without that participant. The plan remains available privately.
- Blocks cancel affected pending invitations and remove cross-user visibility without deleting independently owned Wanna or visit history.
- Turning a save or account private never causes a public “visibility changed” event.

## Save flow

The ordinary form is unchanged through the primary Wanna action.

Inside **More Options**, add one planning row above note/tags:

1. **Go with people** — opens the reusable friend picker and shows selected avatars inline.
2. **Pick a date** — existing optional calendar; copy becomes “When?” when people are selected.
3. **Sharing** — appears only after at least one person is selected. Defaults to Share on Feed unless stealth or Self visibility forces Private.

The footer remains one primary action:

- No people: **Save Wanna**
- People selected: **Save & invite 2**

Saving is atomic from the user's perspective: the creator's Wanna is durable before invitations are dispatched. Partial invitation failures show per-person retry state and never roll back the creator's save.

## Invitation flow

Reuse the existing Shared Visit invitation infrastructure and visual language, but do not reuse its visit-anchored data contract.

Invitation card content:

- inviter avatar/name;
- “wants to go with you”;
- place name/category/area;
- optional date;
- accepted and pending participant avatars that the viewer may see;
- **I’m in** and **Not this time** actions;
- privacy label: **On Feed** or **Private plan**.

Accepting is one tap. The new personal Wanna is created with blank personal fields, then the card changes to **You’re going** with **Open plan** and **Leave plan** actions.

## Map

Do not introduce a third place status color. Preserve the existing owner/status outline:

- owner remains terracotta;
- social remains sky;
- Been remains solid;
- Wanna remains dashed;
- a place may render both Been and Wanna relationship segments.

An active plan adds a separate, accessible planning adornment:

- thin sun/gold outer halo;
- small `person.2.fill` badge for participants;
- optional compact date badge only on selection, never at map overview density;
- accessibility label includes “planned with 2 people” and the date when visible.

The halo is additive, so color is not the only signal and plan state never overwrites preservation of Been/Wanna status. Private plans render only for participants. Public plans render only when the viewer may see the underlying plan event.

Clusters keep the existing ownership/status breakdown. A small planning glyph may appear only when at least one visible member place has an active plan; the cluster never exposes hidden participant counts.

## Feed and activity

Feed events remain immutable facts. Do not derive event kind or copy from a mutable current row.

### Shared plan tile

- Creator avatar and statement: **Joe wants to go to Gnarwhal Coffee**.
- Secondary line: **with Maia · Aug 28**, using only accepted, non-stealth participants the viewer may see.
- Pending invitee names never appear on follower Feed.
- If no accepted participant may be named, use **planning for Aug 28** rather than leaking a count.
- Ticket accent uses the existing Wanna sun treatment plus the small planning glyph; it does not invent a new dominant Feed color.
- Primary action opens the place/plan. Eligible viewers may save their own Wanna, but cannot join without an invitation in this iteration.

### Participant activity

Private and shared plans both appear in the creator's and accepted participants' personal activity. Invitation, acceptance, date update, cancellation, and leave are distinct events with idempotent event IDs.

Declines and delivery failures are never follower Feed events.

## Notifications and deep links

| Event | Recipient | Channel | Deep link |
|---|---|---|---|
| Invited | Each invitee | Inbox + push when enabled | Invitation card |
| Accepted | Creator | In-app + push when enabled | Plan detail |
| Declined | Creator | In-app only | Plan management |
| Date changed | Pending and accepted invitees | Inbox update + push when enabled | Plan detail |
| Invitee removed / plan cancelled | Affected participants | Inbox + push when enabled | Cancelled plan activity |
| Reminder | Creator and accepted participants with reminders enabled | Existing local/server reminder path | Place/plan detail |
| Participant checked in | Other participants | No notification in first iteration | Deferred |

Copy must not expose a private place or participant on a lock screen when the recipient lacks current access. Existing account-switch and APNs token isolation rules apply.

## Plan lifecycle

First iteration lifecycle:

`active → cancelled`

Participant lifecycle:

`pending → accepted | declined | cancelled`

`accepted → left | cancelled`

A passed date does not automatically complete or delete the plan. It becomes **Date passed** and remains editable.

Later iteration: after the planned date, ask each accepted participant **“Did you end up going with Ryan?”**. A Yes response may connect the participant's check-in to the plan; No keeps the plan/history without fabricating a visit. This follow-up is explicitly deferred from the first implementation but the plan/event schema must leave room for it.

## Proposed data contracts

Names are provisional; semantics are required.

### `place_wanna_events`

- `id`, `user_id`, `place_id`
- `created_at`
- `planned_date` nullable
- `state`: `active | fulfilled | removed`
- `fulfilled_at`, `fulfilled_by_visit_id` nullable
- `source`: `direct | plan_acceptance | import | restored`
- immutable content snapshot needed for Feed/activity

There may be multiple rows for one user/place. Current Wanna state is `exists(active event)`.

### `place_plans`

- `id`, `creator_user_id`, `place_id`, `creator_wanna_event_id`
- `planned_date` nullable
- `sharing`: `feed | private`
- `status`: `active | cancelled`
- timestamps and server operation identity

### `place_plan_participants`

- `id`, `plan_id`, `user_id`, `role`: `creator | invitee`
- `state`: `pending | accepted | declined | left | cancelled`
- invitation generation and idempotency key
- `participant_wanna_event_id` nullable until accepted
- timestamps

RLS must authorize plan reads from either the creator's Feed audience or direct participation, then apply profile privacy, save visibility, stealth, and blocks. All accept/decline/cancel mutations must use narrow RPCs with caller identity derived from authenticated claims.

## Analytics

Add privacy-safe raw events and normalized engagement events where applicable:

- `wanna_created` with booleans/count buckets only: `has_date`, `invitee_count_bucket`, `sharing`;
- `wanna_repeated`;
- `wanna_post_visit_created`;
- `wanna_checkin_resolution_presented` and `resolved_keep | resolved_remove`;
- `place_plan_created`, `place_plan_invitation_sent`, `place_plan_invitation_accepted`, `place_plan_invitation_declined`;
- `place_plan_date_updated`, `place_plan_cancelled`, `place_plan_left`;
- `place_plan_opened` with source enum.

Never log place, participant, profile, note, date, coordinate, invitation, notification, or plan identifiers. Use coarse counts and enum metadata only. Update `docs/analytics.md`, the dashboard script when a metric changes, and privacy contract tests before production wiring.

## Offline, sync, and failure rules

- Creator Wanna saves local-first with a stable client operation ID.
- Plan creation and each invitation are independently idempotent.
- The UI may show **Saved — 1 invite still sending**; it must not pretend failed invitations succeeded.
- Acceptance is server-authoritative and atomic: participant acceptance plus personal Wanna creation succeed or fail together.
- Duplicate pushes, retries, or multi-device acceptance cannot create duplicate participant Wanna events.
- Server cancellation or a block wins over stale offline accept intent.
- Local plan projections are identity-scoped and cleared on confirmed sign-out/account switch under existing rules.

## SwiftUI prototype surfaces

The deterministic debug prototype must include:

1. Wanna More Options with Joe and Maia selected, date optional, and sharing choice.
2. Multi-person friend picker with selected, pending, and stealth-aware states.
3. Public and private Feed/activity tickets.
4. Invitation inbox card and accepted state.
5. Map pin with additive plan halo, including Been + active Wanna.
6. Post-repeat-check-in Keep/Remove speed bump.
7. Plan detail/management with Going, Invited, and declined/left disclosure.

Mockups must be interactive enough to exercise selection, privacy, accept/decline, and keep/remove decisions without touching production backend data.

## First implementation slice

This branch should land:

- this specification and durable decision record;
- pure, testable relationship/plan presentation contracts;
- deterministic SwiftUI mockup launch pages for the material UI changes;
- unit tests for relationship projection, participant visibility, stealth, and check-in resolution defaults;
- simulator screenshots on the current test phone and one smaller phone;
- no production migration or remotely enabled feature until the mockups are approved.

The production slice that follows must include Supabase migrations, RLS/RPC regression coverage, hosted smoke tests, local persistence/sync integration, notifications, analytics, and end-to-end UI wiring in the same feature branch or a linked implementation issue.

## Acceptance criteria

- Multiple Wanna moments can exist without overwriting history.
- Been and active Wanna can be represented simultaneously.
- First check-in fulfills active Wanna without a pre-save speed bump.
- Repeat check-in saves first and then offers Keep/Remove, defaulting safely to Keep.
- A plan supports multiple invitees with independent RSVP and Wanna state.
- Date is optional and may be added or changed later.
- Share on Feed and Private are explicit, understandable choices.
- Stealth and block rules fail closed with no identity or count leakage.
- Map treatment does not replace existing owner/Been/Wanna encoding.
- Public Feed never exposes pending or stealth invitees.
- Private plans remain visible to direct participants in inbox/activity/map surfaces.
- Mockups pass Dynamic Type and 44-point tap-target checks and are testable in Xcode via deterministic launch arguments.

## Interaction state matrix

| Surface | Loading | Empty | Error | Success | Partial / special |
|---|---|---|---|---|---|
| Save Wanna | Existing save progress treatment | No people/date is a valid ordinary Wanna | Save remains editable with retry | Wanna is durable | “Saved — 1 invite still sending”; creator save is never rolled back |
| People picker | Skeleton rows only if remote graph is unavailable | “No people found” with search reset | Retry graph load | Selected shelf updates immediately | Stealth contacts are selectable but clearly private-only |
| Invitation | Existing inbox loading treatment | Removed/cancelled invite resolves to activity copy | Accept/decline remains retryable | Accepted creates a personal Wanna atomically | Stale accept loses to block/cancel and explains why |
| Feed / activity | Existing feed placeholders | No new empty state | Existing retry treatment | Immutable plan ticket | Public projection omits pending and stealth people without leaking counts |
| Map | Existing map loading | No visible plan means ordinary pin | Existing map error | Additive halo + participant badge | Private/stealth filtering happens before clustering |
| Repeat check-in | Check-in saves before prompt | No active Wanna means no prompt | Failed check-in never shows prompt | Keep or Remove applies after save | Dismiss/network interruption defaults to Keep |
| Plan detail | Existing detail loading | Cancelled plan becomes read-only activity | Per-action retry, no optimistic identity leaks | Participant/date/sharing changes reconcile | Mixed accepted, pending, declined, left, and stealth states remain independent |

## Journey storyboard

| Beat | User experience | Product proof |
|---|---|---|
| 1. Intent | Ryan taps Wanna at Gnarwhal; the familiar base flow is unchanged. | The common path does not get denser. |
| 2. Coordination | In More Options, Ryan selects Joe and Maia, optionally adds Aug 28, and chooses Feed or Private. | A Wanna becomes a plan only when the user asks for it. |
| 3. Statement | Saving creates Ryan's immutable Wanna and one shared plan. A Feed plan appears only when sharing is allowed. | History and current state are separate; privacy is explicit. |
| 4. Independent replies | Joe accepts and gets his own Wanna. Maia remains pending or declines without affecting Joe or Ryan. | One plan can contain independent people and place relationships. |
| 5. Retrieval | Participants see the plan halo on Gnarwhal while Been and Wanna remain legible underneath. | Planning is additive, not a new place status. |
| 6. Visit | Ryan checks in. Only Ryan's active Wanna resolves; the plan and other people remain untouched. | Attendance is personal until a later explicit reconciliation flow exists. |

## Responsive and accessibility behavior

- iPhone-first vertical flow; selected people wrap or horizontally scroll rather than compressing names and controls.
- All primary rows and actions preserve a 44-point minimum target, including privacy choices, RSVP actions, and the map legend toggle.
- Dynamic Type may turn horizontal button pairs into vertical full-width actions; no important copy is truncated to one line.
- The map halo is paired with a `person.2.fill` badge and an accessibility label, so color is never the sole plan signal.
- VoiceOver announces place, Been/Wanna relationship, plan privacy, visible participant state, and optional date in that order.
- Reduce Motion removes decorative transitions but preserves selection and save feedback.
- Private and stealth filtering occurs before UI counts, labels, map clusters, and notification copy are constructed.

## Implementation Tasks

### Prototype slice in REC-357

- [x] T1. Write the event/state, privacy, invitation, surface, and failure contracts in this specification.
- [x] T2. Add pure relationship, check-in-resolution, and participant-visibility projections with unit coverage.
- [x] T3. Add deterministic DEBUG SwiftUI pages for save, people, Feed, invitation, map, check-in, and plan management.
- [x] T4. Compile, run focused/full tests, and capture the current and smaller-phone simulator screenshots.
- [ ] T5. Push the branch, open the isolated worktree in Xcode, and hand off exact launch arguments and a tester checklist.

### Linked production slice after prototype approval

- [ ] P1. Replace the mutually exclusive local/backend Wanna projection with event-based storage and migration/backfill rules.
- [ ] P2. Add plan and participant tables plus authenticated invitation/acceptance/cancellation RPCs and RLS regression coverage.
- [ ] P3. Wire local-first save, sync, retries, identity isolation, blocks, stealth, notifications, reminders, and deep links.
- [ ] P4. Wire approved SwiftUI into production surfaces, add privacy-safe analytics, and run hosted smoke plus end-to-end simulator QA.
- [ ] P5. Add the deferred passed-date question, “Did you end up going with Ryan?”, only after the base plan loop is validated.

## Validation record

- Simulator build passed on iOS 18.6 with the iPhone 16 Plus and iPhone 16e active architectures.
- All 11 focused `WannaPlanModelsTests` passed, including launch argument/environment resolution, Been + Wanna projection, first/repeat check-in behavior, independent participant visibility, Feed filtering, and stealth/private coercion.
- The repository-wide suite ran 1,461 tests: 1,448 passed, 1 skipped, and 12 failed. The failures are outside REC-357: three stale source-contract assertions in untouched Map/Profile code and nine existing Map/Onboarding UI failures. No failure references the new model, mockup, app launch branch, or tests.
- Visual QA covered save, Feed, invitation, plan management, and the additive map treatment on iPhone 16 Plus, plus save and map on iPhone 16e.
- Small-phone QA found and fixed a large-Dynamic-Type overflow in the compact system date picker. The final design uses a stable responsive date summary row that opens the full calendar in a sheet; the place subtitle now wraps instead of truncating.

## GSTACK REVIEW REPORT

Design review date: 2026-08-22

| Pass | Score | Result |
|---|---:|---|
| Information architecture | 9/10 | Planning is progressive disclosure under Wanna, with one canonical plan detail and no new top-level destination. |
| Interaction states | 9/10 | Loading, empty, error, success, partial delivery, stale invitation, cancellation, and safe-dismiss behavior are specified. |
| Journey coherence | 9/10 | Creation, invitation, acceptance, retrieval, and personal check-in form one end-to-end story. |
| Visual restraint / AI-slop resistance | 9/10 | Existing rec.me tickets, controls, colors, and map grammar are reused; no dashboard/card-grid design direction was introduced. |
| Design-system fidelity | 10/10 | SwiftUI mockups use the existing design tokens and components; planning is an additive sun/gold adornment. |
| Responsive / accessibility | 9/10 | Small-phone, Dynamic Type, tap target, non-color encoding, VoiceOver, and Reduce Motion rules are explicit. |

Initial draft: 7/10. Final design-spec review: 9/10.

Verdict: **DESIGN CLEAR** for the DEBUG prototype and contract slice. The production schema/RLS/sync implementation requires its own engineering review before shipping.

NO UNRESOLVED DECISIONS
