# Live feedback review — October 2026

This revision covers the new map, Feed, place-preview and navigation changes for [REC-636](https://linear.app/recme/issue/REC-636) and [draft PR #736](https://github.com/joelipshutz/wander/pull/736). It replaces the earlier UI walkthrough for this feedback round. Implementation coverage below is not a claim that native or physical-device checks passed; the PR records the exact published candidate, build and completed checks.

**Wait for the testing-ready handoff, then start only when Ryan prompts.** Live remains globally Off. Review uses only the designated internal accounts. Stay on the first account until the guided messaging switch. Publishing this branch does not merge, release or enable Live globally.

## Coverage

| Request | Result in this revision | Manual coverage |
| --- | --- | --- |
| A | The three unresolved cases and diagnostic gap remain open. Use bounded manual stress checks for functional confirmation; do not reinterpret historical runs as new passes. | S1–S3; limits below |
| B1 | Remove the rectangular map-search outline. Use a hovering Liquid Glass Search this area action only in full-map mode after map movement. | R1 |
| B2; D10 pagination | Load current-filter history automatically, separate older matching activity, then continue beyond the discovery filters with an explicit small-print warning and another divider. | R4 |
| C1–C7 | Earlier U15/U18/U12/U19–21/U33 and appearance/accessibility slots are superseded by the changed-interaction checks below. No outcome is prefilled. | R-series; A1–A8 |
| C8 | Real private messaging remains untested. Prepare a fresh isolated fixture and guided two-account session separately. | M1–M10 |
| D1, D1a | Reset filters is at the top of Filters. | R2 |
| D2, D2a | Use Following and activity All. | R2 |
| D3 | A floating Map button remains available in full Feed and returns to full map. | R3 |
| D4 | Nearby directly selects a 10 km area instead of opening Filters. | R2 |
| D5 | Center the smaller place-update count above its smaller time-range label. Remove the former Following/time summary; collapsed Feed retains only the handle and compact summary. | R3 |
| D6, D6a | Smaller distinct check-in, Wanna and list-addition pins; list-only activity is not presented as a Wanna or visit. | R5 |
| D6b | Viewed pins become muted for an account-scoped 24-hour interval. | R5; policy checks |
| D6c | Crowded individual pins become dots, then expand when zoom provides room. The selected pin remains identifiable. | R5 |
| D7 | Keep one stable map geometry while Search is presented; eliminate the exposed frozen map strip. | R9 |
| D8, D8a | Pin selection replaces Feed with the photo-led place preview; coordinated entry uses the requested overshoot and settles, with Reduce Motion respected. | R6; A7 |
| D8b, D8b1–D8b4, D8c | Place name sits at the photo bottom. Text below contains compact ratings, available opening status/time, the specific category, and up to three filtered recent activities with avatars, type emoji, note highlights and available photo piles. Followed people are prioritized without a label. | R6 |
| D8d, D8e | Small circular glass Save, Share, List and Close actions run down the right; Save uses Signal. Close/downward dismissal restores the minimized Feed. | R6–R7 |
| D9a | A selected visible pin does not recenter. A pin covered by the card receives only the movement needed to expose it. | R7 |
| D9b | Closing the card or collapsing the Feed restores the original map focus. | R7–R8 |
| D9c | Moving from full map to half Feed fits the same map content in the smaller exposed window; reversing restores its framing. | R8 |
| D9d, D9d1 | Cold launch and ordinary destination returns default to half map/half Feed. | R9 |
| D9d2 | An actually scrolled Feed can restore its position for 30 minutes after leaving it. | R9; policy checks |
| D9e | A map drag collapses the open Feed or selected-place card. | R7–R8 |
| D10 | First/expired list action opens the picker. A recent list selection or newly created list enables direct add; the toast names the destination and offers Change. Replacement preserves existing membership when the new addition has not synced. | R10 |
| D11 | Remove the selected-place Signal rectangle from Feed; selection belongs to the new place preview. | R6 |
| D12a | Messages moves to the owner Profile header beside Notifications. Contextual private replies remain with activity. | M2–M5 |
| D12b | Filters joins the top bar; the separate circular glass Add button sits at its upper right. | R2; A1 |
| D12c | Draw area becomes a same-size circular control beneath Following on the left. Existing drawing behavior remains. | R2 |
| D12d | Selected Following/Nearby uses bold Signal styling. | R2; A8 |
| D13a | Plans is first in the full place-profile action row and enters the existing plan flow. | R11 |
| D13b | Mutual friends are ranked by currently authorized shared-place activity. | R11 |
| D14 | Notifications explicitly restores its navigation-bar safe area so the title is not clipped. | R9; A6 |
| E | Preserve completed freehand drawing, the three-tab shell, routine activity toggles and ordinary Feed/Profile behavior. Test only their changed entry, return and layout interactions here. | R2, R7–R9; no baseline rerun |
| F | Publish the review branch, open its isolated project in Xcode, verify the selected branch, then announce readiness. Exact branch/build receipt belongs in the PR. | Handoff; not yet a test result |

## Product policies

- **History stages:** selected time range and filters → older matching activity → all authorized activity. Before the last stage, small print explicitly says those posts are outside the selected location, people, category and activity filters. Privacy, blocks, account authorization and the existing social-content freshness limit continue to apply. Broadening Feed history does not silently change the committed map/count selection.
- **Continuity:** viewed-pin muting lasts 24 hours; Feed-position retention and recent-list convenience last 30 minutes. These are explicit Astir review defaults, not universal industry standards. Review immediate behavior on the phone; do not wait hours just to exercise timer expiry. Boundary checks belong to the focused policy tests.
- **List convenience:** use the latest valid, writable list for the current account/session. Change must not remove older pre-existing membership. If replacing a just-added membership cannot safely finish, report that state rather than claim the move completed.
- **Reference:** the supplied Airbnb recording informs the image/text preview and map/list navigation. It is not copied into Git. Airbnb documents its [mini-pin map treatment](https://news.airbnb.com/product-releases/airbnb-2023-summer-release); Apple provides the [custom Liquid Glass API](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views). Astir keeps its own activity meanings, accessibility labels and older-iOS fallback.

## Changed UI: R1–R11

The historical U1–U35 source-to-number mapping is not established here, so these new cases use **R** identifiers instead of silently reassigning old U numbers. Leave outcomes blank until exercised. Record the case ID, observed issue and screenshot/short recording when useful; do not capture credentials.

Before starting, the agent identifies the installed candidate and supplies any needed internal fixture locations/lists. Keep the first designated account signed in. A missing fixture is **unexercised**, not a pass. Share/plan checks stop before sending; list tests use disposable private test lists.

| ID | Actions and expected result | Outcome |
| --- | --- | --- |
| R1 — Search this area | Collapse Feed to full map. Pan to a different area: the glass button appears, with no orange boundary rectangle. Before tapping, the committed count/results stay unchanged. Tap once: pins, count and selected Feed results update together. Raise Feed to half/full: the button is hidden. A later real pan may offer it again; resizing alone must not. | |
| R2 — Header, Nearby, Filters | Tap Nearby: it applies 10 km directly and becomes bold Signal. Following reverses that scope and receives the same selected treatment. Open Filters: Reset is at the top and the activity choice reads All. Change two filters, Cancel and confirm no change; reopen, Reset and Apply. Confirm the separate top-right Add and lower-left Draw controls are reachable. Open Draw and Cancel only; do not repeat the completed freehand drawing suite. | |
| R3 — Feed summary and Map return | From half view, read the centered place-update count and small time label. Collapse: no extra Following/time summary remains. Expand to full Feed and scroll: the floating Map button stays available. Tap it: return to full map, with no stale selected-place rectangle inside Feed. | |
| R4 — Progressive history | Use a supplied filter set with known current, older matching and outside-filter activity. Scroll to the actual bottom and continue normally. Observe Loading more activities, then Showing older activity before older matching posts. Continue: small print warns that the next posts are outside the filters, followed by Showing all activity and the broader posts. Check no duplicated cards, no silent mix before its divider, no endless loading, and no silent broadening of map/count. If a stage has no authorized examples, record it unexercised. | |
| R5 — Pins and density | In the supplied area, compare check-in, Wanna and list-only pins; each has its own symbol/treatment. Open then dismiss one: it becomes muted. Zoom out over a dense group: overlapping pins reduce to dots. Zoom in: they expand individually and remain tappable. A selected pin must not disappear into dots. | |
| R6 — Place preview | Tap a pin with known filtered activity/photos. Feed moves away as the card enters and settles. Confirm name at photo bottom; below it the specific category, available rating/hours and up to three recent activity rows. Check actor/avatar, activity emoji, note highlight and photo pile against the known examples. Followed people should appear first without an explanatory badge. Open the full place page and return. | |
| R7 — Preview actions and camera | Select a pin already clear of the card: the map should not jump. Select one near the card's covered edge: only the necessary reveal movement occurs. Try Close, then reopen and dismiss downward: minimized Feed returns and the prior focus is restored. Reopen and drag the map: the card collapses. Open Save and cancel; open Share and cancel. List is covered separately in R10. | |
| R8 — Map/Feed framing | Start full map with recognizable pins/landmarks. Raise Feed to half: the same content fits the smaller exposed map. Lower it: the prior focus/framing returns. Raise it again, then drag the map: Feed collapses. Confirm there is no jump to an unrelated region or accidental committed search. | |
| R9 — Search, Notifications and return | From half view, open Search and close it three times: no frozen map strip or clipped top area. Open Notifications: read the entire title and back control, then return to half view. Expand Feed, scroll to a recognizable card, open Search and return promptly: the scrolled place is retained. Visit another tab and return to check this changed retention behavior, not basic tab navigation. A fresh normal launch should start half map/half Feed. | |
| R10 — Recent-list add and Change | With a fresh/cleared review session, use the card's List action: choose private test list A. On another supplied place, tap List again: it adds to A and names A in the toast. Tap Change, choose B, and verify the resulting memberships; canceling Change must retain A. Repeat the recent-list action from the full place page. Include one previously unsaved search-result place so candidate-to-saved identity is exercised. Create a disposable private list and confirm it becomes the recent destination. Pending/failed sync must be stated; do not remove an existing real membership. | |
| R11 — Plans | Open the full place page: Plans is the first action before directions/site/call. Open it; inspect the ranked mutual-friend list and choose an eligible internal friend. Confirm the correct place/person in the existing composer, then close without sharing. On an unsaved test place, confirm a usable Save Wanna recovery rather than a dead end. Record unavailable shared-place data separately. | |

## Accessibility and appearance: A1–A8, October revision

These are the revised checks for changed controls, not assertions that earlier A-number definitions are identical. Turn VoiceOver off and restore prior appearance/text settings after this block.

| ID | Actions and expected result | Outcome |
| --- | --- | --- |
| A1 | With VoiceOver, traverse Following/Nearby, Search, Notifications, Filters, Add and Draw. Labels, selected state and order are clear; every new control activates. | |
| A2 | Focus the drawer handle and use its adjustable actions. Reach half/full/collapsed states and activate the floating Map button without trapped focus. | |
| A3 | Open a pin preview with VoiceOver. Read place metadata/activity rows and invoke Close, Save, Share and List independently. Action labels distinguish them; photo content does not duplicate every spoken row. Cancel mutations. | |
| A4 | Open Filters with VoiceOver. Reach top Reset, change one choice, then Cancel; reopen and Apply a deliberate choice. Focus returns to a useful Live control. | |
| A5 | Traverse the known progressive-history fixture. Both stage dividers and the outside-filter warning are spoken before the corresponding posts. Loading/retry controls remain usable. | |
| A6 | At the largest accessibility text size, inspect the header, summary, preview metadata/actions, list toast/Change and Notifications header. Scroll longer content; no essential action may be clipped or unreachable. Use both Light and Dark. | |
| A7 | Enable Reduce Motion. Select/dismiss a pin, raise/lower Feed and return with Map. The transitions remain understandable and the card's overshoot is suppressed. | |
| A8 | Enable Reduce Transparency and Increased Contrast. Inspect glass controls, selected scope, all three pin types and muted viewed pins in Light/Dark. Labels and symbols remain readable; meaning must not depend only on color. | |

## Unpassed functional stress checks: S1–S3

These specifically replace further attempts to diagnose the retained cases. Do not perform a full baseline regression or repeat completed drawing tests.

| ID | Manual workload | Confirmation and remaining limit | Outcome |
| --- | --- | --- | --- |
| S1 — First drawer drag | On a compact layout, return to collapsed Live and perform one normal upward drag. Repeat five independent collapse/first-drag cycles; include one normal relaunch. | Each first drag reaches the expected next drawer state. Record any missed first drag. This confirms observed device behavior, not the historical automation failure's cause. | |
| S2 — Large-text Dark save editor | Set maximum accessibility text and Dark. Open the test place's Save editor, expand it and scroll to the bottom; confirm all controls remain reachable. Cancel. Repeat three times, including Silent on/off without submitting. | No lost expansion, stuck scrolling or unreachable control. Do not save incidental test content or infer a performance measurement from a smooth interaction. | |
| S3 — Appearance return to Settings | Change Light → Dark → Light through the existing appearance controls. After each change, return to Profile and reopen Settings normally. Repeat the cycle three times; compare actual screen appearance with the selection. | Every Settings opening completes and rendered appearance matches. Record delay/stall and its step. Restore the original appearance afterward. | |

The remaining diagnostic evidence gap is **still open**: the previous diagnostic did not supply its required internal measurements. A successful manual workload provides functional confirmation only. It is not an Instruments/Replay measurement, a reconstructed automated pass, or proof of the old failure's root cause.

## Private messaging: M1–M10, October revision

**Prepared instructions only; no fresh fixture or real-account pass is claimed.** The agent must first admit a new isolated source fixture and the two designated ordinary signed-in sessions, confirm their mutual access/account-specific admission and global Live Off, and identify the exact test activity. Do not reuse the aborted trial. Do not contact ordinary users. No account switch or message send happens until the agent guides that step.

This revision uses the reviewed single-phone sequence: the second account sends the first contextual message to the first account; the first replies once; the second reads it. Those are the only two planned sends. Unexpected outcomes pause for inspection instead of resend.

| ID | Guided action and expected result | Outcome |
| --- | --- | --- |
| M1 — Admit session/fixture | Stay on the first account while the agent confirms the installed candidate and fresh private fixture. Confirm the expected Profile identity; no credentials enter evidence. | |
| M2 — Guided second-account switch | Only when prompted, sign out normally and sign into the second account. Its Profile shows Messages beside Notifications. No first-account inbox, draft or private preview carries across. | |
| M3 — Contextual entry | Open the agent-designated synthetic activity and Reply privately. Confirm the other participant and quoted place/activity context. Opening alone must not send a message. | |
| M4 — First send | Enter the prepared short test text and tap Send once. Leave the screen open for the agent to verify acknowledgment and exactly one message. A spinner/uncertain state is not confirmation and is not a reason to tap Send again. | |
| M5 — Profile inbox | Close the thread, open Profile → Messages and return to the conversation. It appears once and contains the same acknowledged message/context. Check keyboard/composer reachability without another send. | |
| M6 — Guided first-account read | After the first send is verified, switch back only when prompted. Open Profile → Messages and visibly read the incoming message. Leave it visible for the agent's read-state check; badges alone do not prove read status. | |
| M7 — Reply | After that read is verified, send the prepared reply once from the inbox thread. Wait for acknowledgment and the agent's exactly-once check before switching. | |
| M8 — Guided second-account read | Switch only when prompted, open the thread and visibly read the reply. Close/reopen it: both messages remain once, in order. Do not send a third message. | |
| M9 — Controlled access change | Stay on the designated screen while the agent announces each permitted fixture access change. Refresh and confirm unavailable context/access is presented without a stale send path; confirm the restored state afterward. Source, mutual-follow, block and participant-admission cases are separate and are marked unexercised until their specific controlled step occurs. Do not alter unrelated relationships yourself. | |
| M10 — Privacy and cleanup | Background the inbox/thread and inspect the app-switcher privacy cover; return and refresh. Finish the guided account/draft-isolation observation. Wait for the agent to confirm cleanup of only the new trial's owned records. UI observation does not establish concurrent-send, quota, replay-masking or cleanup database evidence. | |

The implementation handoff and each test block have separate statuses. A pushed branch or successful install does not mark these blank outcomes complete.
