# Profile Pictures Plan

Date: 2026-06-28
Branch: `codex/profile-pictures`
Status: implemented with local Swift tests passing; hosted/Supabase CLI migration test still needs an environment with `supabase` installed

## Goal

Let the profile owner tap the avatar circle on the Profile tab and use native iOS photo UI to set or remove a profile picture.

The selected image persists locally immediately, uploads to Supabase Storage when the user is signed in, stores a durable profile avatar URL on `profiles.avatar_url`, renders anywhere Wander shows a profile avatar, and can be deleted. Other installs see the new photo after their normal remote profile/place/social graph refreshes.

## Current System Facts

- `ProfileScreen.ownerHeader` renders `WanderAvatar(initials:size:color:)` at [Wander/Features/Profile/ProfileScreen.swift](/Users/ryanlieblein/Developer/wander/Wander/Features/Profile/ProfileScreen.swift:60).
- `WanderAvatar` only renders initials today at [Wander/DesignSystem/WanderTheme.swift](/Users/ryanlieblein/Developer/wander/Wander/DesignSystem/WanderTheme.swift:261).
- `LocalProfile.avatarURL` already exists and persists through `WanderStoreSnapshot.ProfileRecord` at [Wander/Models/LocalModels.swift](/Users/ryanlieblein/Developer/wander/Wander/Models/LocalModels.swift:11) and [Wander/Services/WanderStorePersistence.swift](/Users/ryanlieblein/Developer/wander/Wander/Services/WanderStorePersistence.swift:115).
- Remote profile shells already carry `avatar_url`; this branch adds `current_profile`, `update_profile_avatar`, Storage upload/delete, and owner avatar propagation through visible-place DTOs.
- `AuthSession` has no avatar URL field, so sign-in refresh currently rebuilds `currentUser` without preserving a local avatar at [Wander/Services/WanderLocalStore.swift](/Users/ryanlieblein/Developer/wander/Wander/Services/WanderLocalStore.swift:1205).
- Add already uses native photo import and image decoding patterns in [Wander/Features/Add/AddScreen.swift](/Users/ryanlieblein/Developer/wander/Wander/Features/Add/AddScreen.swift:256).
- `project.yml` currently has location usage copy but no camera usage description, so camera capture requires adding `NSCameraUsageDescription`.

## Design Review Summary

`plan-design-review` result: 8/10 -> 10/10.

- Designer tool: unavailable in this shell, so no visual mockups were generated.
- DESIGN.md status: present. The review calibrates against the Profile identity hierarchy, profile avatar row vocabulary, warm utility style, and no-extra-explanation copy rule.
- Review focus accepted by Ryan: run all seven passes because this media action pattern will likely be reused for place photos later.
- Design classifier: app UI, not landing/marketing.

## Proposed User Experience

The owner avatar in the Profile identity header becomes a plain button with no extra visible text. The avatar keeps the same 56 pt identity position and adds a small camera/edit badge so it reads as tappable without cluttering the header.

Tap behavior:

1. User taps the avatar circle.
2. A native `confirmationDialog` titled `Profile photo` opens.
3. Actions:
   - `Take Photo` when camera hardware is available.
   - `Choose from Library`.
   - `Delete Photo` as a destructive option only when a local/avatar image exists.
   - `Cancel`.
4. Camera and library choices present native iOS pickers.
5. After selecting or taking an image, the avatar updates in place and persists locally.
6. If import fails, the header shows a short inline error below the identity row.
7. Delete removes the stored local image file and falls back to initials.

No visible instructional paragraph is added to the Profile page. The affordance lives in the avatar button and accessibility label.

Future reuse constraint:

- The presentation should establish a native "photo action" pattern that can later support place photos: a compact trigger, a native options dialog, camera only when available, library import, delete when existing media exists, and inline recoverable errors.
- This PR should not build place-photo upload. It should avoid hard-coding names like `ProfileOnlyPhotoDialog` for shared concepts that would make reuse awkward later.

## Design Details

Information hierarchy:

```text
Profile tab
  profile title
  identity header
    avatar button  -> profile photo dialog
    display name
    handle/home area
    settings button
  stats
  monthly recap
  drafts
  recent
  people
```

Avatar states:

| State | What the user sees | Primary action |
| --- | --- | --- |
| No photo | Initials in current terracotta avatar with small camera badge | Tap avatar |
| Has photo | Circular profile image with subtle ring and small edit badge | Tap avatar |
| Importing | Existing avatar remains visible; dialog/picker owns progress | Wait |
| Import failed | Existing avatar remains visible; short inline error under header | Try again |
| Delete | Initials avatar returns immediately | Re-add if desired |

Edit affordance:

- The badge sits at the avatar circle's lower trailing edge.
- No-photo state uses `camera.fill` because the action is add.
- Has-photo state uses `pencil` or `camera.fill` in the same badge shell because the action is change.
- Badge size is 20-22 pt inside a warm raised circle with a 2 pt bone/surface ring so it is visible on both initials and photos.
- Badge is decorative for VoiceOver.

Accessibility:

- Avatar button has a 56 pt visible circle and a minimum 44 pt target.
- Labels:
  - No photo: `Add profile photo`.
  - Has photo: `Change profile photo`.
  - Delete action: `Delete profile photo`.
- Camera badge is decorative and hidden from VoiceOver.
- If camera is unavailable, do not show a disabled `Take Photo` action.
- Inline import error is announced as text near the header and clears after a successful set/delete.

Interaction state coverage:

| Feature | Loading | Empty | Error | Success | Partial |
| --- | --- | --- | --- | --- | --- |
| Avatar button | Existing avatar remains visible while picker is open | Initials avatar with add badge | Inline copy: `Could not use that photo. Try another one.` | Photo appears immediately | If image load later fails, fall back to initials |
| Options dialog | Native dialog owns presentation | Delete hidden when no photo exists | Native cancel/dismiss returns unchanged | Selected action opens picker/delete | Camera action hidden if unavailable |
| Library picker | Native picker owns loading | Cancel returns unchanged | Inline recoverable error | Processed image persists | Large image is cropped/compressed |
| Camera picker | Native camera owns loading | Camera action hidden without hardware | Inline recoverable error | Processed image persists | User cancel returns unchanged |
| Delete photo | No spinner needed | Not shown without photo | If file deletion fails, clear profile reference and log only | Initials return immediately | Orphan file cleanup can happen later |

User journey:

| Step | User does | User feels | Plan support |
| --- | --- | --- | --- |
| 1 | Opens Profile | Oriented: this is my identity | Avatar remains first item in identity header |
| 2 | Notices badge | Invited, not lectured | Small native edit cue, no instructional paragraph |
| 3 | Taps avatar | In control | Native dialog with familiar actions |
| 4 | Chooses/takes photo | Trusting iOS privacy UI | Uses native picker/camera surfaces |
| 5 | Sees avatar update | Rewarded quickly | Immediate local render and persistence |
| 6 | Deletes photo later | Safe recovery | Destructive delete only appears when relevant |

AI-slop and subtraction guardrails:

- No new card, hero, empty-state panel, or decorative explanation.
- No centered promotional copy.
- No extra settings section for this first slice.
- The avatar action earns its pixels because the avatar itself is the interaction.

Design-system alignment:

- Use existing `WanderAvatar` circle, `WanderTheme.surfaceBone`, `surfaceRaised`, `terracotta`, `textOnAction`, and 2 pt surface ring vocabulary.
- Keep owner Profile and other-user Profile visually aligned; only the owner avatar is tappable.
- Other profile rows inherit image rendering only through the shared avatar component, without gaining owner edit controls.

## Engineering Plan

Use built-in iOS pickers, local app-support storage for instant preview/offline behavior, and a Supabase Storage + profile RPC path for signed-in cross-device behavior.

`plan-eng-review` result: clean with one correction folded in. The local avatar update must not mark the profile as pending remote sync until a real profile-avatar upload pipeline exists.

```text
Tap avatar
  |
  v
confirmationDialog
  |-- Take Photo -----------> UIImagePickerController(.camera)
  |                              |
  |                              v
  |                         normalize/crop/compress JPEG
  |
  |-- Choose from Library --> SwiftUI PhotosPicker presentation
  |                              |
  |                              v
  |                         normalize/crop/compress JPEG
  |
  |-- Delete Photo ---------> delete local file
                                |
                                v
                         store.updateCurrentUserAvatarURL(...)
                                |
                                v
                         persist snapshot + rerender avatars
                                |
                                v
                         if signed in: upload Storage object
                                |
                                v
                         public.update_profile_avatar(...)
                                |
                                v
                         replace local file URL with remote avatar URL
```

Implementation choices:

- Add a small reusable photo-action presentation in the Profile feature, using:
  - `UIImagePickerController` for camera.
  - SwiftUI `PhotosPicker` presentation for library, preserving the privacy-friendly photo picker path and reusing the same framework already used by Add.
- Add a testable `WanderImageProcessor` helper that:
  - Decode `UIImage`.
  - Center-crop to square.
  - Resize to a bounded avatar size, target 512x512.
  - Write JPEG data at controlled quality, target around 0.85.
- Add a profile-specific `ProfileAvatarStorage` helper that:
  - Owns the current-user avatar file URL.
  - Writes processed image data atomically.
  - Deletes the local avatar file on delete.
- Store the processed image under Application Support:
  - `Application Support/Wander/profile-photos/current-user-avatar.jpg`.
  - Save the resulting `file://` URL string in `currentUser.avatarURL`.
- Extend `WanderStore` with a small explicit API:
  - `updateCurrentUserAvatarURL(_ urlString: String?)`
  - The method updates `currentUser`, the matching entry in `profiles`, timestamps, and persistence.
  - It preserves the current profile sync state and does not increment pending remote sync count; remote avatar upload is attempted directly when the picker flow has processed image bytes.
- Update `apply(session:)` to preserve the previous local avatar URL when the Clerk session does not provide one.
- Update `WanderAvatar` to render either:
  - local file URL image,
  - remote URL image if supported by `AsyncImage`,
  - initials fallback.
- Add `ProfileAvatarRepository`:
  - Uploads `image/jpeg` bytes to `profile-avatars/<user-id>/avatar.jpg` with upsert.
  - Builds a public Storage URL with a cache-busting `?v=...`.
  - Calls `public.update_profile_avatar(avatar_url, storage_path)` to store/clear the durable profile avatar reference.
  - Deletes the stable Storage object and clears the profile URL on delete.
- Add `current_profile` hydration on signed-in app start so a fresh install can fetch the user's existing remote avatar.
- Add `owner_avatar_url` to `visible_places_in_view` and `profile_visible_places` return shapes so map/place cards can render remote owner photos.
- Protect app-selected avatars from later Clerk webhook overwrites with `profiles.avatar_url_source = 'app'`.
- Add `NSCameraUsageDescription` in `project.yml` and regenerate the Xcode project after implementation.

## Testing Plan

Unit tests:

- `WanderStoreTests`:
  - setting a current-user avatar updates `currentUser` and the current profile shell.
  - deleting clears `avatarURL` and persists.
  - signed-in auth refresh preserves a locally selected avatar when session has no avatar.
  - persisted avatar URL restores across store reload.
  - avatar changes and remote current-profile hydration do not increase pending sync count.
- Image helper tests if helper logic is factored outside SwiftUI:
  - oversized portrait image produces square bounded JPEG data.
  - invalid image data returns a recoverable failure.
- Storage helper tests:
  - writing avatar data creates a file URL under Application Support.
  - deleting succeeds when the file is already missing.
- Remote repository tests:
  - current profile maps remote avatar URL.
  - avatar upload writes the stable Storage path and calls `update_profile_avatar`.
  - avatar delete removes the stable Storage object and clears `update_profile_avatar`.
  - visible place/profile-place DTOs hydrate `owner.avatarURL`.
- SQL/pgTAP tests:
  - profile avatar bucket and Storage policies exist.
  - `update_profile_avatar` and `current_profile` are security invoker with expected grants.
  - callers can update/clear only their own stable Storage path.
  - Clerk profile mirroring preserves app-selected avatars.

Build/manual checks:

- Build app after `xcodegen generate`.
- Simulator: Profile avatar tap opens dialog.
- Library import updates avatar.
- Delete returns to initials.
- Camera action is hidden on simulator when no camera is available, or works on device.
- VoiceOver labels are meaningful for add/change/delete.

## Engineering Review Coverage Diagram

```text
CODE PATHS                                             USER FLOWS
[+] ProfileScreen.ownerHeader                          [+] Edit profile picture
  ├── [GAP] tap avatar opens options dialog               ├── [MANUAL] tap avatar -> dialog
  ├── [GAP] choose library -> PhotosPicker                 ├── [MANUAL] choose library -> avatar updates
  ├── [GAP] take photo -> camera picker                    ├── [MANUAL] take photo on device -> avatar updates
  ├── [GAP] delete -> clear local avatar                   ├── [MANUAL] delete -> initials return
  └── [GAP] import failure -> inline error                 └── [MANUAL] unavailable camera is hidden

[+] WanderImageProcessor
  ├── [GAP] valid large image -> square bounded JPEG
  └── [GAP] invalid image -> recoverable nil/error

[+] ProfileAvatarStorage
  ├── [GAP] write processed data atomically
  └── [GAP] delete missing/existing local file

[+] WanderStore.updateCurrentUserAvatarURL
  ├── [GAP] set avatar updates current user + profiles
  ├── [GAP] clear avatar updates current user + profiles
  ├── [GAP] persistence restores avatar URL
  ├── [GAP] auth refresh preserves local avatar
  └── [GAP] pending sync count unchanged

COVERAGE BEFORE IMPLEMENTATION: 0/14 planned paths tested.
IMPLEMENTED COVERAGE: focused unit coverage for processor, storage, persistence, auth preservation, non-sync store behavior, remote repository upload/delete/current-profile mapping, remote visible-place avatar propagation, and current-profile hydration; simulator screenshot QA on iPhone 17 Pro and iPhone 17e.
REMAINING DEVICE/HOSTED QA: physical camera capture path, because simulator camera availability is gated off; pgTAP profile-avatar SQL test execution, because this shell does not have the `supabase` CLI installed.
```

## Failure Modes

| Codepath | Realistic failure | Test/error handling requirement | User impact |
| --- | --- | --- | --- |
| Library import | Picker returns unsupported/empty data | Show inline error, keep old avatar | User can retry |
| Camera capture | Camera unavailable on simulator/iPad restrictions | Hide action when unavailable | No dead action |
| Image processing | Huge or rotated image decodes incorrectly | Processor test covers square output | Avatar should not distort |
| File write | Application Support write fails | Show inline error, keep old avatar | User sees retryable failure |
| Delete | File already missing | Clear profile reference anyway | User gets desired initials fallback |
| Auth refresh | Clerk session rebuild drops local avatar | Store test preserves previous local avatar | Photo does not disappear after sign-in refresh |
| Remote upload | Storage or profile RPC fails after local preview | Keep local photo and show inline sync error | User sees photo on this phone and can retry |
| Remote hydration | Fresh install has no local avatar file | `current_profile` fetch updates `currentUser.avatarURL` | User sees their synced photo on a new device |

## Worktree Parallelization Strategy

Sequential implementation, no parallelization opportunity. The work touches the Profile UI, shared avatar rendering, store state, image/storage helpers, tests, and project metadata in one tightly coupled flow.

## Implementation Tasks

Synthesized from `plan-design-review` and `plan-eng-review`.

- [x] **T1 (P1, human: ~45min / CC: ~10min)** — Profile avatar — Make the owner avatar a native photo action trigger.
  - Surfaced by: Design pass 1/4/5.
  - Files: `Wander/Features/Profile/ProfileScreen.swift`, `Wander/DesignSystem/WanderTheme.swift`.
  - Verify: simulator tap opens the native options dialog.
- [x] **T2 (P1, human: ~1h / CC: ~15min)** — Media action pattern — Keep picker actions native and reusable for future place photos.
  - Surfaced by: Design pass 2/3/7 and Ryan's future place-photo reuse constraint.
  - Files: `Wander/Features/Profile/ProfileScreen.swift`, any small shared/Profile media helper.
  - Verify: library import, camera availability gating, delete, and cancel states.
- [x] **T3 (P1, human: ~1h / CC: ~20min)** — Local avatar persistence — Store processed avatar files locally and keep pending sync state honest.
  - Surfaced by: Eng architecture review.
  - Files: `Wander/Services/WanderLocalStore.swift`, new storage/helper file, `WanderTests/WanderStoreTests.swift`.
  - Verify: focused store/storage tests and pending sync count unchanged.
- [x] **T4 (P2, human: ~30min / CC: ~5min)** — Accessibility — Add meaningful avatar edit accessibility labels and inline errors.
  - Surfaced by: Design pass 6.
  - Files: `Wander/Features/Profile/ProfileScreen.swift`.
  - Verify: labels for add/change/delete and visible import error copy.
- [x] **T5 (P1, human: ~2h / CC: ~35min)** — Backend avatar sync — Upload signed-in profile avatars to Supabase Storage and store profile avatar URLs.
  - Surfaced by: Ryan's cross-device requirement.
  - Files: `Wander/Services/Remote/*`, `Wander/App/WanderBackend.swift`, `Wander/App/WanderRootView.swift`, `supabase/migrations/`, `supabase/tests/`.
  - Verify: focused remote/store tests, full iOS suite, pgTAP test authored.
- [x] **T6 (P1, human: ~45min / CC: ~15min)** — Remote avatar propagation — Include owner avatar URLs in remote place DTOs and hydrate current profile on sign-in.
  - Surfaced by: Ryan's “everywhere my icon is present” requirement.
  - Files: `Wander/Services/Remote/SupabaseDTOs.swift`, `Wander/Services/WanderLocalStore.swift`, Supabase visible-place RPCs.
  - Verify: remote repository and store hydration tests.

## NOT In Scope

- Cropping UI beyond the native capture/library picker; this slice uses automatic center-crop.
- Editing other users' avatars.
- Real-time avatar refresh while another device changes the same profile; current behavior refreshes through startup/current profile and existing social/profile/place fetches.
- Hosted migration application and pgTAP execution from this shell; the CLI is not installed here.

## What Already Exists

- Profile identity header, settings gear, and avatar position in `ProfileScreen`.
- `LocalProfile.avatarURL` and snapshot persistence.
- Remote `avatar_url` decoding for profile shells.
- Native Add-photo import patterns and existing image metadata/OCR code.
- `WanderAvatar` as the shared avatar visual vocabulary.
- `DESIGN.md` profile hierarchy and avatar-row vocabulary.

## Review Notes

Design review should stress:

- Whether the avatar edit affordance is obvious enough without adding explanatory copy.
- Whether delete belongs in the same dialog or in Settings.
- Whether the inline sync-failure copy is honest without overexplaining backend state.

Engineering review should stress:

- Whether overloading `avatarURL` with local `file://` and remote `https://` URLs remains acceptable now that the backend path exists.
- Whether the picker wrapper belongs in Profile only or a shared media-picking utility.
- Whether camera capture is worth including now given it requires a camera privacy string and device-only QA.
- Whether the profile avatar Storage pattern is the right reusable template for future place photos, or whether place photos should get a richer media table.

Resolved by review:

- `avatarURL` may carry a local `file://` URL in this local-first slice, but rendering code must handle schemes explicitly and this must not create a fake pending remote sync.
- The media picker pattern should be reusable, but the storage path remains profile-specific.
- Camera capture stays in scope because the user requested native options like take photo; it is hidden when unavailable and must add `NSCameraUsageDescription`.
- Signed-in profile avatars now upload to a public Supabase Storage bucket at a stable per-user path and store a versioned public URL in `profiles.avatar_url`.
- Clerk mirroring preserves app-selected avatars so a later Clerk `user.updated` event does not clobber the in-app profile photo.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | - | Not run |
| Codex Review | `/codex review` | Independent 2nd opinion | 0 | - | Not run |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | CLEAR | 1 architecture correction folded in, 0 unresolved |
| Design Review | `/plan-design-review` | UI/UX gaps | 1 | CLEAR | score: 8/10 -> 10/10, 3 decisions |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | - | Not run |

**VERDICT:** DESIGN + ENG CLEARED - ready to implement.
NO UNRESOLVED DECISIONS
