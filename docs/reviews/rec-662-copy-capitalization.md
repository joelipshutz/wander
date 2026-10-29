# REC-662: Natural Sentence Casing

Use natural sentence case at the beginning of sentences, titles, section headings,
and standalone controls or labels. Preserve normal casing within sentences,
proper nouns, acronyms, and intentional brand casing. Examples: “Add a place”,
“Privacy and trust”, and “Your map is still here”.

## Coverage

Reviewed the prior full app-owned copy inventory across main navigation, Map,
Add/check-in questions, Discover, Feed/Live, lists, profiles, invitations,
messages, onboarding/auth, settings, errors, accessibility, App Clip, widgets,
share extension, permissions, and local reminders. Most of these strings were
already correctly sentence-cased and now have no diff. Shared production
components in historical Mockup/Prototype files are included.

Correct lowercase title/section/control starts at their source. Format built-in
question choices and taxonomy labels at presentation only. The small formatter
uppercases only a standalone label's initial; it does not title-case words or
rewrite subsequent characters. Storage, matching, search terms, user/provider
content, and analytics contracts stay unchanged. Composed phrases such as
“3 places”, “Alex checked in”, and “Connect with your people” retain lowercase
continuations, including when rendered as separate text views.

## Count

The earlier **14,296** count described the superseded every-word capitalization
patch and does not describe this revision. The revised count is **255 changed word occurrences across 38 app source files**.
Count repeated source occurrences separately;
exclude tests, documentation, generated mirrors, and newly added formatter code.
Runtime formatting has no finite rendered-word count and is excluded.

Reproduce the source count:

```sh
python3 scripts/audit-copy-capitalization.py \
  --base 0947576af1fb01aa27667f157f5b0c79dd366106 --json
```

The audit parses Swift interpolation as code and verifies that changed existing
literal segments differ only by capitalization. The residual review checks
lowercase literal starts in display calls and copy fields, internal sentence
starts, and display-time lowercasing. Remaining lowercase examples are composed
sentence fragments, username/URL examples, or standalone development mockups.

## Flags And Deliberate Exceptions

- User/provider text (names, notes, messages, personal tags, custom questions,
  list titles, imported captions) remains verbatim. Mixed personal/built-in tags
  lack reliable ownership metadata for blanket formatting.
- Hosted notification templates, incoming notification text, hosted pages,
  system/SDK controls, date/list formatters, and external diagnostic errors can
  retain their own casing. No remote templates or historical rows are changed.
- Identifiers, URLs, SF Symbols, date formats, search terms, storage values,
  brands such as iPhone, and conventional units remain intact.
- Embedded image/video text, spoken content, sample user notes, and standalone
  development mockups are outside this source-copy change.
- Existing title-case/all-caps design treatments are retained where intentional;
  this change does not mechanically lowercase proper nouns or existing titles.

## Validation And Handoff

The final sentence-case native run passed all **3,229 tests, zero failures**,
on iPhone 17 Pro / iOS 26.5. The first pass exposed stale copy assertions; these
were corrected and the entire native suite rerun. Formatter tests cover initial-only
casing, Unicode, contractions, brands, numeric phrases, and storage/custom-value
preservation. All **four targeted UI tests passed**, zero failures: Map, place
detail, default-filter selection, and Live Settings appearance controls.

Final place-detail screenshots were inspected on iPhone 17e (1170 × 2532) and
iPhone 17 Pro (1206 × 2622); sentence-cased copy wraps cleanly and controls fit.
Final evidence is outside Git in `/private/tmp/rec662-evidence/` as
`compact-sentence-case.png` and `large-sentence-case.png`.
The final result bundle is `/private/tmp/rec662-sentence-final.xcresult`.

The literal audit and whitespace checks pass. App Clip, share-extension, permission,
and local-notification copy already used sentence case and now have no source diff.
Earlier every-word validation is not claimed as validation of this revision.

The earlier live-auth launch crashed twice inside `Clerk.configure` and the
walkthrough stalled after Map-to-Feed. Their cause was not established against
baseline. Those remain explicit validation gaps; the full broad UI suite is
not claimed as passing.

Branch: `codex/word-capitalization`; worktree:
`/private/tmp/wander-word-capitalization`; PR: #764. The main checkout is untouched.
The unchanged canonical founders video is hydrated locally for bundle tests and
excluded from commits. No merge or TestFlight upload is included.
