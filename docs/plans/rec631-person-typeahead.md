# REC-631 — Person typeahead

## Scope and existing behavior

The shared input supports activity comments, Map/Feed people search, and the
common Check-in/Wanna note editor. An explicit `@` opens a compact list with
avatars, full names, and secondary handles. Selecting a row inserts `@Full Name`
in bold Signal text and retains the keyboard. Another `@` opens the picker again.

Reuse `WanderStore`'s mutual/follow graph and `WanderBackend.peopleRecommendations`
(REC-587), preserving that service's contact consent checks and ranked order.
Mutual/follow connections lead because the shared recommender deliberately excludes
existing follows; its ranked results fill the remaining suggestions.
Existing profile RPCs retain responsibility for server-side visibility. Results
are deduplicated by account ID and filtered by first name, surname, or handle.

Notification delivery is outside this branch: REC-609 retains that responsibility
and its dependency on the sender Silent policy. Selecting text does not add an
invitee, change an audience, or grant access to a saved place.

## Engineering review

Use the native attributed text input APIs available on iOS 17. A small value
model stores the text plus selected account spans in UTF-16 units. Typed `@text`
never acquires an account identity without a selection. Changing a selected
name invalidates that span; edits before it shift the offset. Search uses the
selected account's handle while the field displays the full name.

```text
native cursor/text edit
  -> active @ range -> cached graph results
                   -> debounced shared ranking + profile search
                   -> account/visibility check + ID deduplication
  -> selected row -> replace active range + record account span
                  -> bold Signal rendering + dismiss results
                  -> canonical handle when submitted as a search
```

The query generation and owner ID reject delayed responses after dismissal,
query changes, or account changes. A ranking failure must still allow explicit
search. Cached results remain usable during a network error, with Retry shown.
No query text, display name, handle, or mention content is sent to analytics.
Existing successful save/comment analytics remain at their current domain layer.

This pass implements the approved picker/editor/search scope. Comments and notes
save the inserted name as text through their existing contracts. Permanent
account links and styling after save remain separate from this editor work and
REC-609's notification delivery. The shared input exposes account spans for a
future persisted tag contract; it does not claim those spans are stored remotely.

## Design review

The supplied interaction is the visual reference. Use Astir's adaptive raised
background, border, Avenir Next identity text, and contrast-safe Signal text token.
The result panel is capped at roughly three and a half rows with visible scrolling;
each row has a minimum 44-point tap target. Full names wrap when needed. Selection
is indicated by bold weight as well as color. VoiceOver announces the full name,
handle, and insertion action. The editor keeps native selection, dictation,
composition, paste, keyboard, and Dynamic Type behavior.

Empty queries show ranked people; unmatched queries show “No people found.”
Network errors keep available matches and offer Retry. The panel collapses when
input loses focus or no valid `@` query remains. Notes and comments anchor the
panel above input; top search fields place it below.

## Validation

- Pure model tests: bare `@`, first-letter/name/handle/surname matches, duplicate
  matches, multiple selections, emoji offsets, edits inside/before tokens, email
  exclusion, cursor-in-middle replacement, and stale selection rejection.
- Async tests: ranking failure, explicit search, delayed response after dismissal,
  owner changes, block changes, and retry behavior.
- SQL regression: one-character matching, surname matching, one row per account,
  literal punctuation, empty query, deleted/private/blocked profiles, authenticated
  grants, invoker posture, and pinned search path.
- Native tests on current and smaller iPhones: actual comment, Map/Feed search,
  Check-in and Wanna fields; scrolling, selection, multiple tags, submission,
  keyboard retention, and screenshots of open/selected states.
- Run the complete unit suite and relevant existing search/save/comment UI checks.

Sequential implementation: the editor, query model, and integration share one
contract. Keep notification code untouched while the independent dependency is active.

## Validation results

The hosted migration preview and `person_typeahead_search.sql` regression pass
inside a rolled-back transaction. The full hosted smoke suite stops at the
existing share-card payload assertion; running `share_card_previews.sql` without
this migration reproduces that failure. Deployment approval is pending; no hosted
migration has been applied.

The iPhone 16 Plus run passed 2,573 unit tests and all four typeahead UI cases
(comments, Feed search, Map search, and both note modes). The native input now
defers autofocus until after SwiftUI updates and rejects stale parent text
snapshots while typing. These fixes prevent a Feed responder graph cycle and
lost characters in the note form. The save button reserves bottom space, and
growing suggestions scroll the focused note into view on smaller phones.

Xcode has opened this isolated worktree and its Branch Chooser shows
`codex/rec-631-person-typeahead`. Native validation uses the installed iOS 26.5
runtime because the prescribed 18.6 runtime is unavailable. All four typeahead UI cases also pass on iPhone SE (3rd generation), including
keyboard Send and a geometry assertion keeping the note above the save button.
Existing combined-search/profile navigation and note-draft preservation UI tests
pass. Screenshots cover light and dark appearances across the two sizes.
