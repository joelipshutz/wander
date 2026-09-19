# REC-543 — notification post navigation

Branch: `codex/notification-post`. Base: `916a6b7`.

## Behavior

Comment/like notifications open the existing full-screen post view with Feed underneath. Followed check-ins retain their exact visit identity even though existing pushes include a place URL. An activity ID takes precedence over a legacy place link. Visit-only payloads use the existing access-checked per-parent summaries lookup, then load the exact activity. Missing or inaccessible posts show a retryable state; they never silently open another visit.

Notification routing uses the root dismissal handoff. Feed profile/place/save presentations and activity share/photo/report/save presentations acknowledge physical dismissal before the latest notification activates. Local drafts reset when a different post opens. Back and edge swipe return to Feed. The comments title and empty-state prompt are removed; the composer has a 44-point up-arrow action with a Send comment accessibility label.

## Performance design

Direct post -> exact detail -> comments. Legacy check-in -> one parent lookup -> exact detail -> comments. No full Feed hydration or separate engagement-summary request blocks post resolution. Authenticated notification draining precedes calendar and permission refresh work. Existing lazy List, bounded image decode/cache and transient read retry remain in use.

## Validation checkpoint

- XcodeGen, Swift source parsing and `git diff --check` passed.
- First helper-managed build compiled app source, then failed compiling a new test because its Task returned non-Sendable FeedActivity. The test now returns the ID, following the existing account-race test pattern. No native test pass is claimed.
- Subsequent read-only review found a direct-Feed-share cover gap; the same handoff now covers action-row-owned presentations. Latest changes have passed parsing, not a complete rebuild.
- Automatic approval review blocked the rerun at 48.8 GiB free, below the user-required 50 GiB build floor. A one-time cleanup of three verified inactive rebuildable caches is awaiting Joe's approval; do not bypass the helper or delete caches without it.
- Native screenshots, cold/warm OS notification acceptance and measured UI/performance results remain pending. Do not merge based on this checkpoint.

## Resume

Worktree: `/Users/joelipshutz/Documents/ChatGPT/New project/wander-notification-post`.
Evidence: `/Users/joelipshutz/Documents/ChatGPT/New project/notification-post-evidence`.
Existing standard device: `FD6770B4-AF24-4435-BD3F-301C706D51E2`; compact: `6CB5D49F-FA87-4D3E-9C2E-F9A1296F257C` (iOS 26.3). Both were already booted; do not shut down another task's device.

After approved cleanup/headroom verification:

```sh
python3 "/Users/joelipshutz/Documents/ChatGPT/New project/.tools/ios-work.py" build -- test \
  -project Wander.xcodeproj -scheme Wander \
  -destination 'platform=iOS Simulator,id=FD6770B4-AF24-4435-BD3F-301C706D51E2' \
  -only-testing:WanderTests/ActivityEngagementTests \
  -only-testing:WanderTests/RemoteRepositoryTests \
  -only-testing:WanderTests/WanderWidgetIntegrationTests \
  -only-testing:WanderTests/NavigationContractTests \
  -only-testing:WanderUITests/FeedActivityGroupingUITests \
  -resultBundlePath '../notification-post-evidence/NotificationPost-Final.xcresult' \
  CODE_SIGNING_ALLOWED=NO
```

Run the two new notification UI scenarios on compact, capture screenshots and inspect appearance, keyboard and footer. Exercise a warm notification while the direct Feed share cover is open. The `-WanderNotificationPostUITest` DEBUG fixture injects a fictional response into the authenticated queue after loading local fixtures; it does not claim OS/APNs delivery coverage. No backend migration or deployment is required.
