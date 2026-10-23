# Native splash timing and the early bend

Measured September 20, 2026 for REC-557. This is a timing baseline for the branch
preview, not native adoption of the effect.

## What was measured

Three normal process launches of the already installed Astir **1.0 (177)** on
an existing **iPhone 16e simulator, iOS 26.3**. No launch arguments, forced delay,
new install, sign-out or app-data reset were applied. The destination was the
Map screen. The first trial followed simulator boot; the next two relaunched
the same process. These are not fresh-install tests or physical-device samples.

| Trial | First recognizable logo frame | First frame leaving splash | Approx. visible splash |
|---|---:|---:|---:|
| 1 | 3.153 s | 6.528 s | **3.38 s** |
| 2 | 1.662 s | 4.453 s | **2.79 s** |
| 3 | 1.985 s | 4.967 s | **2.98 s** |

Times in the middle columns are recording presentation timestamps, **not time
since launch**. The difference is the visible logo window. The simulator's black
system launch transition before the artwork appears is excluded. Median is
2.98 seconds; observed range is 2.79–3.38 seconds. This small sample is not a
population estimate or a promise about Joe's phone.

Method: `simctl io recordVideo --codec=h264`, followed by AVFoundation decoding
of every frame. Candidate splash frames had visible center artwork and a dark
surrounding field. The detector sampled every eighth pixel inside x 1/12–11/12,
y 1/8–7/8: more than 10% bright pixels in y 35–66%, less than 3% outside that
center band, with a maximum RGB component above 60/255 counted as bright.
Boundary frames and the destination screen were visually checked. Treat the
reported durations as approximate to a few hundredths of a second; screen
transitions and variable-rate capture are not exact lifecycle timestamps.

Raw recordings, decoded-frame measurements and screenshots are retained locally
in workspace `splash-timing-evidence-2026-09-20/`. They are not copied into the
public repository because captures can include app/session content. Only the
aggregate timings and method are saved here. The task-owned simulator was shut
down after capture; the other booted simulator was left alone.

## What the source establishes

On reviewed `origin/main` (`a787ca7`), `AppEntryView` displays `OnboardingLaunchView`
while `AppEntryCoordinator.state == .launching`. `start()` awaits
`auth.refreshSession()` and resolves auth/profile/local-completion state. There
is **no fixed splash duration or minimum animation hold** in this path. Cached
state, device speed and network readiness can make it shorter or longer.

Build 177 is an existing baseline and includes an older visual treatment. It is
not a fresh build of the restored static splash on latest main. A fresh native
build was not run: available storage was 31.6 GiB, below the workspace's 50 GiB
build floor. No exception was assumed and no caches or user data were deleted.
The browser change requires no native build. Fresh-device/native-performance
acceptance remains part of any later integration decision.

## Timing decision

- The preview's clock now starts at **0.00 seconds**. It does not secretly seek
  into the middle of an eight-second source film.
- Move the first tracking event to **0.50–0.70 seconds after the first rendered
  splash frame**, preserving the original 0.20-second waveform at normal speed.
- The shape previously liked at preview source 1.80 s is held by “Show a tear”
  at elapsed **0.60 s** (waveform time 1.78 s).
- Later faults stay at elapsed 4.55–4.71 and 6.76–7.01 seconds, only relevant to
  long holds. No additional early pulse or brightness flash is added.
- The 0.50-second onset fits all three measured windows and the deliberately
  shorter **0.8-second** and **1.2-second** browser previews. A **0.35-second**
  preview shows the faster case where the app leaves before the event.
- For native adoption, start the effect clock when the decorative view actually
  appears, and cancel when readiness removes it. **Never delay readiness to
  finish a tear.** If the splash is gone before 0.50 s, it may show no tear.
  This is how it can appear on some short launches without turning every launch
  into a required animation. No random omission is necessary.
- Reduce Motion remains static. Original logo/font bytes remain unchanged.

This revision changes only the browser proposal and saved videos. Main and the
native startup gate remain unchanged.
