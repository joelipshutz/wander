# rec.me

rec.me, formerly Wander, is a native iOS social map for remembering places worth returning to and discovering places through trusted people.

This repo contains the product spec, design system, research, planning-grade mocks, and the native iOS implementation.

## Key Files

- `AGENTS.md` - durable repo guidance for agents/developers
- `docs/codex-handoff.md` - catch-up summary for new Codex/developer instances
- `docs/agent-log.md` - frozen historical archive; current work lives in Linear and PRs
- `docs/roadmap.md` - current milestones and next steps
- `docs/decisions.md` - durable product/engineering/design decisions
- `docs/open-questions.md` - unresolved questions, risks, and deferred decisions
- `docs/setup.md` - local setup, build, test, and visual QA commands
- `docs/specs/wander-ios-product-spec.md` - product spec and current decisions
- `docs/plans/2026-06-01-wander-ios-eng-plan.md` - implementation plan and sequencing
- `docs/plans/2026-06-01-wander-m1-5-contract-lock.md` - schema/RLS/sync/UI contract lock
- `DESIGN.md` - design system and UI guardrails
- `preview/follow-profile-settings-mocks/` - current design handoff source of truth
- `preview/follow-profile-settings-mocks/tokens.css` - canonical visual tokens for SwiftUI implementation
- `preview/follow-profile-settings-mocks/screens.html` - annotated core screen mocks
- `docs/source/wander-mocks.pdf` - original mock PDF
- `research/screensdesign/2026-05-30-social-map-onboarding/` - onboarding research and previews
- `TODOS.md` - planning TODOs

## Current Direction

- Map-first iOS app
- Follow graph, with mutual follows treated as friends
- Visibility states: Everyone, Friends, Self
- Four tabs: Map, Add, Discover, Profile
- Profile merges personal place memory with public/self profile
- Settings as a gear from Profile
- Contacts and username search for finding people
- Contextual add flows by category

## Development

`project.yml` is the Xcode project source of truth.

Generate the Xcode project:

```bash
xcodegen generate
```

Build:

```bash
xcodebuild build -project Wander.xcodeproj -scheme Wander -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```

Test:

```bash
xcodebuild test -project Wander.xcodeproj -scheme Wander -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
```
