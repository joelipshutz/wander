# Circle Questions

Implementation branch: `codex/circle-questions`.

The Live plus menu opens **Ask your circle**. The composer uses the existing
category taxonomy with Everything, multiple primary categories, and a separate
optional subcategory selector. A searchable city/state/country supplies the pin
center. Supporting text is optional. The ask is the largest text on the feed card;
map duration and expiration do not appear there.

Tags direct notifications. Normal questions are visible to followers and explicit
tag recipients. Stealth questions are visible only to their author and tagged
recipients. Blocks revoke access. The current hometown selector uses the existing
public profile home-area field; private contact details are not exposed.

Question pins use a lilac tile and plum footing, with a question mark. Duration is
1–30 days, default seven. Expiration removes the map pin while retaining the
question and conversation in the feed.

Recommendations use one deduplicated basket across place search, quick picks from
the person's map, and saved lists. A list can supply all its places or a subset.
The following page, **A little local knowledge**, contains the entire selection,
optional notes per place, and an optional overall note. No list title, visibility,
or private list note is copied into a recommendation. The maximum batch is 50.

## Implementation and review

Production views live in `Wander/Features/Questions`. They are connected to Add,
Feed, Live map annotations, notifications, deep links, and private-message context.
The repository boundary uses authenticated Supabase RPCs. The database owns
visibility, tag validation, likes, replies, expiration and idempotency. Client
success is shown only after a repository acknowledgment.

The migration is additive and has not been deployed. Its test runs through
`scripts/supabase-smoke-test.mjs --migration-preview ... --migration-test
supabase/tests/circle_questions.sql`; the transaction is rolled back. Real
cross-account and APNs delivery testing requires deploying the reviewed migration
and using eligible test accounts. Existing private messaging retains its mutual
friend and account-enablement rules.

For isolated UI review, launch the Wander scheme with
`-WanderCircleQuestionReview -CircleQuestionScene composer` and
`-WanderAuthenticatedUITest -WanderUseDemoFixtures`. Other scenes: `feed`,
`preview`, `question`, `recommend`, `knowledge`, `expired`.

To test the real Live-plus entry and local posting loop, select the
**Circle Questions Review** Xcode scheme and the **Astir Circle Review** simulator.
The scheme supplies
`-WanderAuthenticatedUITest -WanderUseDemoFixtures -WanderDisableWalkthroughs
-WanderUnifiedLiveUITest -WanderCircleQuestionLocalTest -WanderInitialTab discover`.
The local-test argument selects an explicit in-memory repository in simulator test
sessions only. It sends no push notifications or remote mutations.

Linear tracking and release classification are deferred until the later tracking
pass. This branch is not approved to merge or release.

## Validation — November 4, 2026

- Native app builds on iOS 26.5. The full WanderTests target plus the original
  four question UI tests ran: 3,603 passed, three initially failed. The sharing
  contract was fixed to use WanderShareButton; the Live-plus test now completes
  the existing startup notification prompt. The feed replay benchmark passed
  when rerun in isolation. The final focused run passed all 19 tests: 12 question
  unit tests, five UI flows, the sharing contract, and the replay benchmark.
- UI checks cover opening from Live plus, multi-place selection across navigation,
  selecting and editing a whole list, submitting recommendations back to a
  question, and keeping expiry/duration/Wanna copy out of the feed.
- Native captures inspected on iPhone 17 Pro and iPhone 17e, including dark mode
  and accessibility text size. Local evidence is under
  `outputs/circle-question/implementation-captures/` in the primary checkout;
  result bundles remain outside this worktree.
- Hosted migration-preview smoke passed. Tests cover normal/Stealth visibility,
  blocked users, reply/like/publish retries, changed-recipient retry rejection,
  push-source authorization, private-message context, expiry, RLS and grants.
  A subsequent query confirmed that both schema and fixture rows rolled back.
- Analytics dashboard contract checks and all 12 dashboard tooling tests passed.
  Review storage and whitespace checks passed.

Before shared-account testing, review and deploy the additive migration, run the
normal hosted smoke test again, and verify actual APNs delivery with test accounts.
The local review scheme exercises an in-memory repository; data resets on launch.
The initial question feed fetch is capped at the newest 100 authorized questions.
