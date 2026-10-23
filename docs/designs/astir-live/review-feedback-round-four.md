# Live review, fourth feedback round

REC-636 · PR #736 · `codex/rec636-review-feedback`

This checklist covers only this round’s changed behavior. Focused native validation is complete; the seven checks below are the next physical-device review. The edited [round-two feedback](review-feedback-round-two.md) remains intact.

## Changed behavior to review

1. **Drawer gestures.** Start at each drawer height. Flick up and down from the left, middle and right of the header, then try a slow drag and a direction reversal before release. Short flicks should move to the next stop in the release direction; only a longer physical drag should cross an intermediate stop. Repeat with a populated, scrolling Feed and while photos load. Check for a jump at release or a pause caused by the Feed resizing.
2. **Dense photo pins and preview.** Return to the busy LA area from the report, with at least 11 expanded photo pins. Available images should appear progressively without waiting for the slowest place or tapping each pin. Zoom dense dots into photo pins, then open a place while other pins are loading: its preview should have its own loading path. Switch between places and return to a previously opened one. A missing or inaccessible image may retain a placeholder; the app must not borrow another place’s photo.
3. **Hours without a photo.** Open places with known provider hours, including one whose photo is unavailable. Hours/open status should load independently of the image and remain after the entry animation. Background and return, then switch places: expired or unavailable facts must not masquerade as a current open/closed status or carry over to another place. Unknown hours remain unknown.
4. **Remove from Wanna control.** Open Check-in for a place with an existing Wanna. Verify the crossed-bookmark icon and the shorter explanation: “Remove your existing Wanna for this place. New Wannas will not be impacted.” Compare its styling with Silent and Stealth. No new save/deletion exercise is needed for this presentation-only change.
5. **Shared postcard and photos.** Open an accepted shared check-in. Expect one header with slightly overlapping profile avatars and “[source name] checked-in with [companion name],” both authorized notes, one combined photo pile, and one set of actions. There should be no View activity dropdown or visible “Comments” label beside the comment icon. Open the pile, page through photos from both contributors, and return to the same postcard.
6. **Invitation changes and discussion.** As the inviting account, inspect an invited companion’s identity without an “invitation pending” label; pending invitees’ notes/photos must remain absent. Decline using the designated second test account, refresh, and verify the declined identity disappears. Repeat with comments open. For the photo viewer, background/return or close/reopen and verify revoked contributions disappear; inspect companion identity on the postcard/comments. Open comments: the original plain comment list and bottom composer should surround the same enhanced postcard. Both originals’ readable comments appear once with their original authors and controls, without extra “On …’s check-in” labels. Use only designated test accounts for a new comment; it must appear once after refresh.
7. **Repeated list notes in the preview.** Use a place whose same save/note appears in multiple lists. Its compact preview should avoid repeating that note; a matching original check-in/Wanna takes precedence among the hydrated candidates. Distinct visits, authors, source saves, notes, or photo sets remain distinct. List additions with no note retain their list names. This affects the preview’s three-row selection, not underlying activity or list records.

## Implementation boundaries

- Photo metadata and downloads remain bounded and account-scoped. Pins publish independently, and the tapped preview does not wait behind their queue. Provider hours use a separate metadata request. Missing photos and provider failures remain possible; image availability is not guaranteed.
- Photo delivery includes client and `place-photo` service changes. The service update is installed as version 23; its source was read back and both missing/invalid authentication probes returned 401. Authenticated real-place image/hour confirmation remains for the device retest. Synthetic tests do not prove that a particular venue currently has a usable provider image.
- Shared presentation reuses existing authorized shared-post and companion reads. Pending identity remains restricted to the source owner; only accepted/readable originals supply contributions. Membership refreshes invalidate the shared card, discussion and photo viewer. The comments screen tracks membership as soon as its header is published, while comment pages may still be loading.
- Shared grouping requires explicit provenance. Unlinked historical check-ins are not inferred to be one visit. Original posts/comments are retained; new comments use the established canonical original. No record rewrite is part of this round.
- Duplicate-note suppression is limited to list echoes from the same actor, place and source save with matching normalized note and media IDs. Hydration considers up to 20 stable candidates and refills until three distinct authorized rows are found. Deduplication runs again against fresh notes/photos without changing the hydration task identity. It does not merge separate visits or change Feed totals.

## Completed validation and remaining device review

| Check | Result |
| --- | --- |
| Current Simulator build | Passed, including the final hydration correction |
| Focused unit coverage | 101 unique tests passed; final preview follow-up passed 14 cases |
| Native drawer stress | Passed on large and compact phones: 52 real drag/flick gestures total across the full-width header, including slow long drags |
| Shared card, combined photos and comments | Same native UI flow passed on both phone sizes |
| Screenshot review | Large/compact shared postcard, combined-photo viewer, comments and drawer inspected; final preview and crossed-bookmark control inspected |
| Photo-service behavior | 20 tests passed; deployed version 23 source readback matched; missing/invalid authentication rejected |
| Real-provider photos/hours and invitation changes | Await the seven changed-only physical-device checks above |

Evidence is kept once outside worktrees in `outputs/rec636-evidence/v76-feedback-round-four` under the shared workspace. Native screenshots use sample data and do not establish actual venue or account behavior. Service tests use the Node behavioral adapter; no Deno type/lint pass is claimed. The two native UI flows passed on both sizes; the final preview-only correction did not change either tested flow.

Global Live remains Off. This checklist does not claim a new full-suite pass or release.
