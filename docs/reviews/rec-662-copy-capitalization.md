# REC-662: App Copy Capitalization

Capitalize each word's first letter in app-owned visible copy, including body
text, small words, and hyphenated words. Preserve the remainder of each word,
contractions, acronyms, intentional brand casing, and conventional units.

## Coverage

- Main app: navigation, Map, Add/check-in questions, Discover, Feed/Live,
  lists, profiles, invitations, messages, onboarding/auth, settings, errors,
  empty/loading states, placeholders, and accessibility copy.
- Shared live invitation and profile-map surfaces are included even where
  their source files retain historical `Mockup` or `Prototype` names.
- App Clip, widgets and controls, share extension, app permission explanations,
  and locally generated reminders.
- Built-in question choices, saved-answer summaries, and known category labels
  receive display casing without changing their persisted values or search
  terms. User-authored/custom values remain verbatim.
- Copy assertions and UI lookups are updated alongside the implementation.

## Count

The reproducible source count is **14,296 changed word occurrences in 156
source files**. Repeated copy counts at each source location; hyphen-separated
word components count separately. Tests, comments,
generated plist mirrors, documentation, and added implementation files are
excluded. Dynamic display transformations and new display branches have no
finite rendered-word count and are not added to this number.

```sh
python3 scripts/audit-copy-capitalization.py \
  --base 0947576af1fb01aa27667f157f5b0c79dd366106 --json
```

The audit parses Swift interpolation as code and rejects changes in wording.
New literal segments in presentation branches are listed separately rather
than counted as changed words.

## Flags And Deliberate Exceptions

1. **Incoming server copy:** activity notification titles/bodies can mix
   app-authored wording with names and private content. Existing remote text
   is preserved. This change does not update historical notification rows,
   push workers, hosted pages, or server templates.
2. **User and provider content:** names, notes, messages, custom questions,
   personal labels, list titles, imported captions, and provider place names
   retain their original casing. Mixed built-in/personal tag suggestions need
   reliable ownership metadata before uniform display casing can be applied.
3. **System and SDK UI:** Apple permission buttons, photo/share pickers, maps,
   date/list formatters, authentication-provider UI, and third-party error
   messages can supply their own casing. App-owned permission explanations and
   error fallbacks are covered; external strings are not rewritten. Raw
   diagnostic/backend errors surfaced by generic error handling can also retain
   their source casing and need a separate friendly-error mapping.
4. **Non-copy contracts:** identifiers, SF Symbols, URLs/handles, filenames, date formats,
   analytics values, enum storage values, parsing terms, and matching rules
   retain their original spelling. Units such as `km`, `min`, and `ft`, and
   brands such as `iPhone`, retain conventional casing.
5. **Review-only content and media:** standalone development mockups/fixtures,
   sample personal notes/comments, text embedded in images/videos, and spoken
   content are outside the text source change. Shared components used by the live app are included.

These flags bound the audit to the reviewed app-owned text sources. Strings
supplied by a user, service, or iOS can still appear in their original style.

## Validation

The post-rebase native suite and all four affected UI checks pass. App Clip
and broader focused UI results below were established before the rebase; their
source changes are unchanged by integration.

- Xcode project regeneration and whitespace checks passed.
- Focused formatter checks passed for contractions, acronyms, Unicode,
  hyphens, units, and preserved storage/custom values.
- Audit parser checks passed for nested interpolation, raw strings, comments,
  and rejection of wording changes.
- Post-rebase main-app native suite: **3,229 tests passed, zero failures**, on iPhone
  17 Pro / iOS 26.5. Earlier copy-expectation, replay-image and performance
  failures were resolved and verified in the final sequential run.
- App Clip: **33 unit tests passed, zero failures**, and **both UI flows passed**.
- Post-rebase UI: **four tests passed, zero failures**: Map, place detail,
  legacy default-filter selection, and Live Settings appearance controls.
- Pre-rebase main-app UI: **12 focused tests passed** across the final runs: seven
  screenshot/navigation flows, accessibility-size answer controls, optional
  list selection, dietary/stealth persistence, repeated Settings navigation,
  and linked map sharing. The corrected four-flow rerun passed with zero failures.
- Final place-detail layouts were captured and inspected on iPhone 17e
  (1170 × 2532) and iPhone 17 Pro (1206 × 2622). Capitalized rating subtitles
  wrap cleanly and the visible controls remain readable and within bounds.
- **Unresolved validation flags:** normal live-auth launch crashed twice inside
  `Clerk.configure`. The walkthrough automation waited for app idleness across
  the Map-to-Feed transition and was manually interrupted; its displayed copy
  was inspected, but the interaction test is not a pass. The wider UI suite was
  interrupted to rebuild final copy and is not claimed as fully passing.
- The canonical founders video was retrieved from GitHub LFS and verified
  against its committed SHA-256/size for native bundle validation. Its content
  is unchanged and is not part of the patch.

## Integration And Handoff

Branch: `codex/word-capitalization`. Worktree:
`/private/tmp/wander-word-capitalization`.

Reconciled REC-661, REC-663 and REC-463 through
`0947576af1fb01aa27667f157f5b0c79dd366106`. The Settings conflict preserves
main's condition hiding the legacy default filter in Live mode. The new
Colored Map label and accessibility explanation are included in the count.
Xcode's Branch Chooser was verified as `codex/word-capitalization` in this
worktree's project. The unchanged hydrated founders video is excluded from
the patch.

The PR remains draft while the live-auth and walkthrough validation flags
remain unresolved. There is no merge or TestFlight upload in this task.
