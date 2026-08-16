# Design System - rec.me

Status: Draft
Created: 2026-06-01
Skill: design-consultation

This is the project-level design source of truth for rec.me. Read it before making visual or UI decisions.

## Sources

- Product spec: `docs/specs/wander-ios-product-spec.md`
- Design handoff source: `preview/follow-profile-settings-mocks/`
- Canonical design tokens: `preview/follow-profile-settings-mocks/tokens.css`
- Design-system reference: `preview/follow-profile-settings-mocks/index.html`
- Annotated screen mocks: `preview/follow-profile-settings-mocks/screens.html`
- Handoff IA feedback: `preview/follow-profile-settings-mocks/wander-ia-feedback.md`
- Original mock PDF: `docs/source/wander-mocks.pdf`
- Original rendered mocks: `docs/source/wander-mocks-pages/`
- Onboarding research: `research/screensdesign/2026-05-30-social-map-onboarding/report.md`

## Product Context

- **What this is:** rec.me is a native iOS social map for remembering places worth returning to and discovering places through trusted people.
- **Who it is for:** People who save places from daily life, travel, people they follow, TikTok/Instagram links, photos, and memory, then want useful answers later.
- **Space/industry:** Social maps, place memory, trusted recommendations, lightweight local/travel discovery.
- **Project type:** Native iOS app, map-first, SwiftUI, iPhone-first for v0.1.
- **North Star:** When I need a place, rec.me shows me where my trusted people have actually been, what they thought, and whether it fits the moment.
- **Wedge:** rec.me turns trusted people's place memories into a searchable map you can actually use.

## Aesthetic Direction

- **Direction:** Warm utility map with a playful editorial edge.
- **Decoration level:** Intentional. The map, pins, sheets, profiles, and social proof carry the visual system. Avoid decorative filler.
- **Mood:** Useful before social. Informal but not slangy. Warm, sharp, low-friction, and privacy-aware.
- **Visual anchor:** Map first. No generic landing page, no card-grid marketplace feel, no public influencer feed language.

Principles:

- Map first, not list first.
- Trusted people, not strangers.
- Capture must feel faster than organizing.
- Privacy must be visible before social value expands.
- Discovery should answer the user's current place question.
- Do not use live-location language.
- Do not bring back manual lists.

Copy examples:

- Good: "worth a detour", "where's it from?", "a few quick details", "saved from Ryan", "people you follow have been".
- Avoid: generic travel-app language, cute slang, gamified check-in language, public feed language, long onboarding lectures.

## Information Architecture

Bottom navigation:

```text
map        add (+)        discover        profile
```

No `your world` / `social world` grouping labels. The former `you` surface is folded into `profile`; `add (+)` is a terracotta-accented tab, not a raised center FAB.

Screen hierarchy rule:

- Each main screen gets at most three primary elements above the fold.
- Everything else moves into a sheet, secondary row, or edit state.

Map:

1. Search: place, vibe, area, contact, or username.
2. Map viewport with filtered pins and clusters.
3. Filter chips: you, social/following, friends, been, wanna go.
4. Selected place sheet.
5. Bottom nav.

Add:

1. Source picker.
2. Candidate confirmation.
3. Been/wanna and visibility.
4. Contextual questions.
5. Save confirmation.

Discover:

1. Search.
2. People row.
3. Smart filters.
4. Follow-powered result cards.
5. Save-to-my-map action.

Profile:

1. Identity header with avatar, name, handle/city, bio, and edit action.
2. Stats for been, wanna, and friends; stats deep-link to filtered place lists and followers/following.
3. This-month activity recap and recent check-ins.
4. Saved places, unresolved drafts, edit controls, and filters by status, city, category, attributes, and custom tags.
5. Role-based visibility: owner sees all; other viewers see only follower/mutual-accessible content.
6. Followers/following entry points and settings gear.

Settings:

Entry: gear in Profile, not a bottom tab.

1. Profile/account basics.
2. Privacy defaults and blocked users.
3. Contacts, notifications, data/account controls.

## Design Coverage

The active design source of truth is the handoff package in `preview/follow-profile-settings-mocks/`. Use `tokens.css` as the literal token source and recreate the HTML references natively in SwiftUI; the HTML/CSS is a design reference, not production code.

Current handoff covers:

- Map with search, filters, pins, and selected place sheet.
- Add/source picker for current location, link, manual, and photo.
- Candidate/contextual question flow.
- Saved confirmation.
- Merged Profile surface with identity header, stats, monthly recap, recent check-ins, and settings gear.
- Bottom nav: `map`, `add (+)`, `discover`, `profile`.
- Pin legend for you/social and been/wanna go.
- Core token layer, component classes, iPhone frame, motion guidance, and SwiftUI component mapping.

Original Lovable mocks still provide useful reference for Discover smart filters and some social/planning breadth, but they are no longer the primary visual source.

Still needs a later visual pass:

- Other-user profile with follow/unfollow, follows-you, mutual/friend, and block actions.
- Followers and Following lists.
- Username search and Contacts search results.
- Discover smart filters and result cards in the final handoff style.
- Block confirmation, blocked profile, and blocked users settings.
- Settings detail rows beyond the Profile gear entry.
- Non-follower profile shell with no visible places.
- Social place detail states when follow/block/visibility changes mid-flow.

Before implementation, run design review against the handoff package and the missing-pass list, then convert the chosen screens into native SwiftUI specs. The handoff follows the warm Rodeo-ish direction: cream/sand surfaces, espresso text, terracotta user pins, sky social pins, chunky rounded controls, and casual travel-buddy copy.

## Typography

- **Display/Hero:** Native editorial serif for first-run onboarding; Funnel Display direction, or equivalent playful grotesque, for other major empty states and top-level screen headings.
- **Display family:** Lil Grotesk is the current rec.me exploration: circular, friendly, and geometric without feeling like generic app chrome. The initial rollout is limited to primary tab headers; semantic hero, section, and card roles are defined so broader branches can be compared before adoption.
- **Body:** Funnel Sans direction, or equivalent legible sans. Use for body, controls, sheets, cards, and settings.
- **UI/Labels:** Same as body, medium weight.
- **Data/Tables:** Same as body with tabular numerals where counts or distances align.
- **Code:** SF Mono if needed for internal/debug surfaces.
- **Loading:** Prefer bundled app fonts. If custom font licensing/package choice is not finalized, use iOS system font temporarily but keep metrics close.

Type scale, iPhone:

| Token | Size | Weight | Use |
|---|---:|---|---|
| `type.display.lg` | 36pt | 700 | First-run headline only |
| `type.display.md` | 28pt | 700 | Major screen heading or empty state |
| `type.title.lg` | 22pt | 700 | Sheet title, place title |
| `type.title.md` | 18pt | 650 | Section/card title |
| `type.body` | 16pt | 400 | Default readable body |
| `type.body.sm` | 14pt | 400 | Secondary body, helper copy |
| `type.label` | 13pt | 600 | Chips, tabs, metadata |
| `type.caption` | 12pt | 500 | Attribution, counts, quiet labels |

Rules:

- No negative letter spacing.
- Do not scale fonts with viewport width.
- Dynamic Type must not break chips, controls, or bottom sheets.
- Reserve display-scale type for true onboarding or major hierarchy moments.

## Color

Color values come from `preview/follow-profile-settings-mocks/tokens.css`, which is the source of truth for implementation. Promote these 1:1 into SwiftUI color tokens.

| Token | Hex | Use |
|---|---|---|
| `color.canvas.warm` | `#F3DFCA` | App background, map-adjacent surfaces |
| `color.surface.bone` | `#FFF7EA` | Cards, sheets, forms |
| `color.surface.raised` | `#FFFFFF` | Inputs, selected cards, elevated controls |
| `color.surface.sand` | `#EFE3D0` | Recessed wells, pressed chips |
| `color.text.ink` | `#2C2118` | Primary text |
| `color.text.muted` | `#7B6555` | Secondary text |
| `color.text.faint` | `#A8957F` | Tertiary text and placeholders |
| `color.text.onAction` | `#FFF7EA` | Text on terracotta |
| `color.border.hairline` | `#DBC2AA` | Dividers, card outlines, chip borders |
| `color.border.strong` | `#C9AC8F` | Strong dividers and sheet grabs |
| `color.action.terracotta` | `#D46F4D` | Primary CTA, user pins |
| `color.action.terracottaDark` | `#A94F35` | Pressed/strong CTA state |
| `color.action.terracottaTint` | `#F6E0D2` | Terracotta wash backgrounds |
| `color.surface.sunTint` | `#F4E8C9` | Wanna stat tile background |
| `color.surface.skyTint` | `#DBEAF1` | Friends stat tile background |
| `color.pin.youBeen` | `#D46F4D` | Solid user been pin |
| `color.pin.youWanna` | `#D46F4D` | Dashed user wanna-go pin |
| `color.pin.socialBeen` | `#69B8D7` | Solid visible social been pin |
| `color.pin.socialWanna` | `#69B8D7` | Dashed visible social wanna-go pin |
| `color.category.moss` | `#6F8F5F` | Outdoors/nature |
| `color.category.sun` | `#E3B64B` | Warm highlight/category marker |
| `color.category.sage` | `#A0B98A` | Calm/supporting category |
| `color.state.success` | `#3F8F64` | Saved/confirmed |
| `color.state.warning` | `#B98528` | Needs attention |
| `color.state.error` | `#B84A3A` | Error/destructive |
| `color.state.info` | `#4F8EAD` | Informational/system |

Rules:

- Color must never be the only status indicator.
- Pin state uses owner color plus fill/dash pattern.
- Avoid palettes that drift into all-beige, all-slate, all-purple, or generic travel blue.
- Dark mode is not required for v0.1 unless explicitly prioritized.

## Spacing

- **Base unit:** 8px.
- **Density:** Comfortable for consumer iOS, compact enough for repeat map use.
- **Scale:** 4, 8, 12, 16, 24, 32, 48, 64.
- **Minimum tap target:** 44px.
- **Safe areas:** Bottom nav, plus action, and sheets must respect home indicator and keyboard.

## Layout

- **Approach:** Map-first, sheet-driven, iPhone-first.
- **Grid:** Use native SwiftUI layout primitives with 8px spacing. Do not invent a desktop-style grid for v0.1.
- **Max content width:** iPhone viewport. If iPad is allowed later, use a map plus side-panel pattern rather than stretching phone cards.
- **Border radius:**
  - `radius.sm`: 8px, compact controls and thumbnails.
  - `radius.md`: 12px, repeated result cards.
  - `radius.lg`: 16px, larger cards and grouped panels.
  - `radius.sheet`: 24px, bottom sheets.
  - `radius.pill`: 999px, chips and compact buttons.

Rules:

- Do not nest cards inside cards.
- Do not use floating page sections as decorative cards.
- Stabilize fixed-format UI with explicit dimensions or responsive constraints.
- Long text must wrap or truncate predictably without overlapping controls.

## Motion

- **Approach:** Minimal-functional.
- **Easing:** Use native iOS sheet/map transitions where possible.
- **Duration:** Micro 80-120ms, short 150-250ms, medium 250-400ms.

Allowed:

- Pin appears after save.
- Sheet changes height.
- Button press and saved confirmation.
- Small loading/progress indicators for extraction and search.

Avoid:

- Cinematic onboarding.
- Decorative motion that slows capture.
- Map movement that disorients users.

## Core Components

### App Shell

- Bottom nav has `map`, `add (+)`, `discover`, and `profile`; Settings opens from a gear in Profile.
- The plus is an inline terracotta-accented tab and remains the primary capture affordance.
- No `your world` / `social world` grouping labels.

### Search Field

Used on Map and Discover.

States:

- default
- focused
- loading
- empty result
- error
- active filter summary

Placeholder direction: "search a place, vibe, or username..."

### Filter Chips

Multi-select:

- you
- social
- friends
- been
- wanna go

Rules:

- Up to four pin states can show at once.
- Selected state must be readable by color, fill, and accessibility label.
- Filter selection must not shift the layout.

### Pin System

Pin states:

- You + Been: solid terracotta.
- You + Wanna go: dashed terracotta.
- Social + Been: solid sky.
- Social + Wanna go: dashed sky.

Rules:

- Clusters preserve owner/status breakdown.
- Mixed clusters open a grouped sheet.
- Recency may later use opacity/tone, not a new primary color.
- VoiceOver labels include owner, status, category, and place name.

### Place Sheet

Content order:

1. Place name, category, distance/area.
2. Been/wanna state.
3. Social proof.
4. Top attributes.
5. Primary action.
6. Attribution/privacy details.

Primary actions:

- Save to my map.
- Edit.
- Add details.
- Change visibility.

### Source Picker

Rows:

- I'm here right now.
- Paste a link.
- Add manually.
- From a photo.

Rules:

- One clear source per row.
- Current location may show detected place when available.
- Every source resolves into candidate confirmation.

### Candidate Confirmation

States:

- High confidence: candidate selected, one-tap continue.
- Medium confidence: show two or three candidates.
- Low confidence: ask for place name/area.
- None: unresolved draft, no map pin.

### Contextual Question Block

Question types:

- emoji scale
- single choice
- multi-tag
- price scale
- short note

Rules:

- Category templates ship with defaults.
- Users can add custom tags.
- Do not ship a full schema editor in v0.1.
- Optional questions never block saving.

Starter categories:

- Coffee shop
- Restaurant
- Hike
- Bar
- Park/nature
- Wellness
- Work-friendly cafe
- Event/pop-up

### Visibility Pill

Locked by plan-eng-review.

Recommended states:

- Everyone
- Friends
- Self
- Pending sync
- Error / retry

Rules:

- New normal places default to Everyone, meaning followers can see them.
- Friends means mutual follows only.
- Self means only me.
- Helper copy: "People who follow you can see this."
- Everyone is not a global public feed in v0.1.
- Users can switch visibility in add/edit before save.
- Do not bury privacy in settings.
- Do not use live-location language.
- Sensitive places may default Self even if normal places default Everyone.

### Profile Avatar Row

Used in Discover, place sheets, and social proof.

Rules:

- Use avatar circles or initials.
- Show place counts where useful.
- Do not expose content the viewer cannot access under follower/friend/self visibility.

### Follow/Profile Card

States:

- suggested
- following
- follows you
- mutual/friend
- not following
- blocked
- unavailable

### Followers / Following Lists

Rules:

- Separate Followers and Following tabs.
- Show follow state inline.
- Allow unfollow from Following.
- Allow block from overflow/profile actions.
- Blocked users should disappear from both users' visible graph lists.

### Settings Tab

Rows:

- Profile/account.
- Default place visibility.
- Blocked users.
- Contacts.
- Notifications.
- Data/sync.
- Sign out / account deletion later.

### Empty State Panel

Rule: short context plus one action. No explanation essays.

Examples:

- "No places here yet." + Add place.
- "Nothing from your people yet." + Find people.
- "This link needs a little help." + Add manually.

## M2 Social And State Surface Specs

These specs close the surfaces not fully mocked in `screens.html`. They must extend the handoff style rather than introduce a new visual direction.

### Discover

Hierarchy:

1. Search field with active query/filter summary.
2. People row for contact matches, exact/near-exact username matches, and visible profile links.
3. Big smart-filter pills, not curation cards.
4. Follow-attributed result rows/cards with visible social proof and one save-to-my-map action.
5. Parser fallback/editable filter chips.

Rules:

- No global people directory.
- People results appear only through contacts, exact/near-exact username search, or visible profile links.
- Smart filters use casual query labels like "hikes in LA", "coffee to work from", "patio bars", and "friends liked".
- Result cards must earn card treatment by containing a place, trusted attribution, useful attributes, and a direct save action.
- Parser failure falls back to static smart filters and keeps the raw query visible.
- Blocked or unavailable profiles are hidden, not shown as broken rows.

States:

- Loading: inline spinner in the search field plus quiet placeholder rows.
- Empty: "Nothing from your people yet" with Find people or broaden filters.
- Error: "Search hit a snag" with Retry.
- Partial/offline: cached results are labeled as saved earlier; no stale social claim should look fresh.

### Other-User Profile

Hierarchy:

1. Identity shell: avatar, display name, handle/city, bio, counts.
2. Relationship row: Follow, Following, Follows you, Friend, or Blocked.
3. Visible places section filtered by status/category/area.
4. Followers/following entry points.
5. Overflow actions, including Block.

Role-based views:

- Non-follower: profile shell and counts only; primary action is Follow.
- One-way follower: follower-visible places plus Following state.
- Follows-you: shell plus follow-back affordance.
- Mutual/friend: follower-visible and friend-visible places.
- Blocked/unavailable: no place data; quiet explanation and unblock only where owner initiated block.

Rules:

- The owner Profile and other-user Profile share the same visual shell. Owner-only edit/settings controls are replaced by relationship and safety actions.
- Long names and handles truncate before they collide with the follow button.
- Block is available from overflow and never hidden behind Settings.

### Followers And Following Lists

Hierarchy:

1. Segmented Followers / Following control.
2. Search within the current list.
3. Profile rows with avatar, display name, handle, relationship badge, and inline follow/unfollow.
4. Overflow block action.

Rules:

- Rows use the Profile avatar row vocabulary, not a new card style.
- Blocked users disappear from both users' visible graph lists.
- Empty Followers: "No followers yet" with profile-sharing or Find people CTA.
- Empty Following: "Not following anyone yet" with Find people CTA.

### Settings

Entry: Profile gear only.

Hierarchy:

1. Profile/account basics.
2. Default place visibility with Everyone/Friends/Self pills and helper copy.
3. Blocked users.
4. Contacts status and native Contacts affordance.
5. Notifications.
6. Data/sync.
7. Sign out / account deletion later.

Rules:

- Use grouped rows on canvas/surface tokens; do not add a fifth bottom tab.
- Default visibility copy must say what Everyone means: "People who follow you can see this."
- Contacts can show current authorization state and may request native permission only after an explicit user CTA.
- Data/sync shows pending, failed, retrying, and synced states without exposing backend jargon.

### Block And Access-Changed States

Block confirmation:

- Title: "Block this person?"
- Body: "You won't see each other's profiles, places, or search results."
- Primary destructive action: Block.
- Secondary action: Cancel.

After block:

- Profile/search/list entries disappear where possible.
- If the user is already on a stale profile/place sheet, show a quiet access-changed state with a single close/back action.
- Blocking deletes follow edges both ways in the product model.

Access changed:

- If unfollow or block revokes access while a detail is open, do not leave private place details visible.
- Show "This place isn't available anymore" and return to Map/Profile.

### Authentication Boundary

Logged-out launches first show the three-slide value carousel, then Clerk sign-up
or log-in. The main app is available only after Clerk confirms an active signed-in
session and required first-run identity setup is complete.

Rules:

- Launch and foreground activation show a blocking session-check state until the current Clerk client is authoritatively refreshed.
- Signed-out sessions show the native Clerk sign-in/sign-up surface without a dismiss path; authenticated tabs and cached profile metadata must not remain visible underneath it.
- Session revocation, account deletion, logout, or an account switch removes the authenticated surface immediately and clears account-scoped presentation, widget, analytics, and person metadata.
- A cached device profile is never proof of authentication and must not be inherited by a different account.
- If session verification fails, show a retryable unavailable state instead of entering the app with cached identity state.
- Contextual auth-gate copy may remain for transitions already in flight, but it cannot provide a path around the root authentication boundary.
- Do not show the auth sheet before the value carousel has explained the product.

## Onboarding Rules

Flow:

1. Three-slide real-map value carousel: place diary, friends, trusted discovery.
2. Clerk sign-up or log-in.
3. Required name and username; profile photo is optional.
4. Location pre-prompt and native request, with Skip.
5. Contacts pre-prompt and native request, with Skip.
6. Trusted friend suggestions with multiselect, with Skip.
7. Notifications pre-prompt and native request, with Skip.
8. Main app. Phase B moves steps 4–7 into contextual tutorial moments.

Rules:

- Auth-first after the value carousel.
- Returning users go directly from validated session resolution to their prior app state.
- No paywall during first-run onboarding.
- Native permission prompts only after explicit CTA.
- Every permission screen has a skip path.
- Auto-advance carousel slides every seven seconds, pauses for VoiceOver,
  Reduce Motion, and backgrounding, and always supports manual paging.

## Interaction States

Every major surface must define:

- loading
- empty
- error
- success
- partial/offline

Required partial states:

- cached map while sync catches up
- some social pins hidden by privacy
- local custom tags pending sync
- extraction needs confirmation
- follow/block/visibility changes while detail is open

## Accessibility

- 44px minimum tap targets.
- VoiceOver labels for pins include owner, status, category, and place name.
- Dynamic Type must not break chips.
- Long tags truncate predictably.
- Reduce Motion disables decorative pin drops and long transitions.
- Color is not the only state indicator.
- Permission skips and secondary paths are accessible.
- Visibility controls must have explicit labels, not icon-only meaning.

## Remaining Architecture-Sensitive Areas

Plan-eng-review locked the backend/auth, visibility, block, share-extension, places, username, delete, and high-level extraction direction. These areas still need implementation-detail validation:

- Sync/offline states.
- Contacts and follow matching states.
- Clerk auth gate mechanics.
- Extraction confidence states and backend job details.
- Paywall trigger configuration.
- Analytics instrumentation surfaces.

## Do Not Do

- No Lists tab.
- No public global feed in v0.1.
- No live-location affordances.
- No public badges, mayorships, leaderboards, or ranking people. The private
  save streak is limited to a once-daily celebration and a compact Profile row;
  it must not become a persistent app-shell fixture.
- No auth sheet before the logged-out value carousel.
- No early paywall.
- No generic card-grid marketplace feel.

## Decisions Log

| Date | Decision | Rationale |
|---|---|---|
| 2026-06-01 | Initial design system created | Created from the product spec, Lovable mocks, onboarding research, and mock-backed plan-design-review. |
| 2026-06-01 | iPhone-first v0.1 | The mocks, onboarding, and native map interactions are phone-centered. iPad can run phone-compatible unless explicitly prioritized. |
| 2026-06-01 | Use Strava-style follow graph | Following is one-way; friends are mutual follows; profiles, followers/following lists, and blocking are required surfaces. |
| 2026-06-01 | Use Everyone/Friends/Self visibility | Everyone means followers can see it, Friends means mutual follows, Self means only me. Helper copy must prevent global-public confusion. |
| 2026-06-01 | Contacts-first lookup, native Contacts planned later | People can be found through contacts or username; v0.1 uses `FakeContactProvider` and username search, with native Contacts planned behind the same provider contract after the core graph loop is validated. |
| 2026-06-01 | Adopt design handoff package as visual source of truth | `preview/follow-profile-settings-mocks/tokens.css` owns tokens; `index.html` and `screens.html` are the SwiftUI recreation references. |
| 2026-07-25 | Allow a private save streak | Saving a Check-in or Wanna can trigger one daily full-screen celebration; the durable indicator stays compact in Profile and never becomes a public rank or persistent shell element. |
| 2026-06-01 | Collapse `you` into Profile and keep four tabs | Current nav is `map`, `add (+)`, `discover`, `profile`; settings opens from Profile and there are no grouping labels. |
| 2026-06-01 | Use Clerk + Supabase | Clerk owns identity/account surfaces; Supabase owns social data, RLS, PostGIS, functions, and storage. |
| 2026-06-01 | Defer share extension | In-app add, map, and social loop ship first; share extension is a later TODO. |
| 2026-06-01 | Ship lightweight LLM Discover parsing | Natural-language Discover parses into visible structured filter chips using a cheap/swappable model path; it is not a broad agent. |
| 2026-06-01 | Defer private profiles, iPad-specific layouts, and extra design variants | Open follow plus hard block, phone-first compatibility, and current handoff source of truth are enough for eng planning. |
| 2026-06-01 | Use simple v0.1 sync conflict handling | Local retry queue plus `updated_at`/server-wins behavior is enough for v0.1; no field-level multi-device merge. |
| 2026-06-01 | Keep analytics vendor-neutral | Define event names now behind an interface, choose provider later. |
| 2026-06-01 | Complete refreshed design review gate for M2 | Missing Discover, other-user profile, followers/following, Settings, auth gate, block, and access-changed states are now specified in the handoff style. |
| 2026-07-25 | Require authentication at the app boundary | Logged-out or unverifiable sessions must never render the authenticated app or cached person metadata; Clerk sign-in is the non-dismissable root until a session is confirmed. This supersedes the earlier guest-first/no-account-wall rules. |
| 2026-07-22 | Ship auth-first Phase A onboarding | User-approved flow starts with a three-slide real-map carousel, then Clerk auth, required identity, and skippable location, Contacts, trusted-friend, and notification steps. Editorial serif is reserved for this first-run narrative. Phase B moves permission education into contextual tutorials without redesigning the reusable steps. |
