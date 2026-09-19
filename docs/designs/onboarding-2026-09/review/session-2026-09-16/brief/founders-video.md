# Founders’ welcome — native review candidate

Status: implemented in Swift; combined build/device verification and Joe’s listening approval pending. Main and TestFlight are held at Joe’s request. This extends the selected native film C; it does not replace Ryan’s first-use walkthrough.

## The supplied take

The original portrait movie is 114.465 seconds. It contains camera setup, an uninterrupted welcome from Joe and Ryan, and outtakes after the welcome. Preserve the original. Joe approved including the outtake after “We love you,” through the final “Cut.” The current cut uses **23.5–114.465 seconds**, **90.965 seconds (1:31)**. The earlier 75-second cut remains archived. Review the audio before shipping.

The message explains Astir’s origin, saving and discovering places through people you trust, spending time out in the world, connection, and how to send feedback. The transcript was produced locally using faster-whisper-tiny.en. It contains recognition errors (including Astir and the Sequoia sentence); it is timing evidence, not approved captions or copy.

## Recommended experience

**Profile → Location → Contacts → Following → Notifications → a quick hello from Joe & Ryan → Ryan’s first-use walkthrough.**

1. Show a good still of both founders in a full-height, portrait player, on the same dark Astir background. Native intro copy: “A quick hello” and “From Joe & Ryan · 1:31”. Avoid an extra splash or mandatory countdown.
2. One deliberate tap on Play starts the video with sound. Keep Skip intro visible from the first frame, including before playback. Do not unexpectedly interrupt someone’s music on entry.
3. Tapping the picture shows/hides normal playback controls: pause/resume, scrubber with elapsed/remaining time, mute. Captions are not implemented in this review candidate; the machine transcript is not accurate enough to publish. A picture tap must never dismiss the video. Use standard native playback controls without custom social controls or looping. Preserve the whole portrait frame; do not crop either founder to fill a differently shaped phone.
4. End or Skip uses the same short fade into the first-use Map. Release the walkthrough only after the video has gone away; its clocks/highlights must not run behind the video. No extra “Now learn the app” interstitial. An optional replay later can live in Settings/About.

This is an optional personal welcome. The 91-second video is optional. The entry card offers Play and Skip; the video itself never blocks reaching the app.

## State contract for native implementation

| State | Behavior | Exit |
| --- | --- | --- |
| Ready | Poster, duration, Play, Skip; player prepared locally; walkthrough held | Play → playing; Skip → completed |
| Playing | Live native player; Skip stays visible; tap reveals controls | Pause, interruption, end, or Skip |
| Paused/interrupted | Hold position. Backgrounding pauses audio and video. Returning stays paused, with Resume and Skip | Resume → playing; Skip → completed |
| Completed/skipped | Record this intro version as handled for this newly onboarded account, cancel observers/audio, release walkthrough once | Enter Ryan’s flow |
| Cannot play | Clear fallback with Retry and Skip; never strand signup | Retry or enter Ryan’s flow |

Keep replay separate from first-run completion. Existing onboarded users should not be forced through this after an update. Restoring the app halfway through should offer Resume or Skip, without replaying profile/permission steps. Completion must follow account/session persistence so process death cannot repeat the handoff. Preserve pending invite/deep-link routing and the existing NUX eligibility rules.

## Film and logo requirement remains

Astir’s logo should share the original Coming Soon treatment: ongoing fine jitter and sparse larger tracking distortion, with one continuous clock across the opening transitions. Keep Signal and Ink app colors. On Create your account, animate **only the logo**; the heading, fields, legal copy, and native button colors stay still. Film C at `1155ca4` is the starting point; logo motion still needs final visual acceptance for the release candidate. Do not apply VHS filtering to the founders’ faces or to native video controls by default.

## Before shipping

Review the cut and playback entry, verify captions against the actual audio, implement the handoff in Swift, then exercise skip before/during playback, normal ending, scrubbing to the end, background/audio interruption, asset failure/offline, account changes, deep links, VoiceOver, Reduce Motion, and compact screen layout. Confirm Ryan’s walkthrough starts exactly once after the player leaves. Validate current film/control responsiveness on the exact main candidate. Build number and TestFlight upload remain unselected and on hold.

## Wind cleanup and reproduction

The cleaned version uses local DeepFilterNet 0.5.6 with a conservative 18 dB attenuation limit, delay compensation, no postfilter and no gain boost. No Higgsfield credits were used. Stereo audio and the original H.264 picture packets are retained; only audio is replaced. The output has no clipped samples, and exact timing is preserved with 30 ms of trailing silence after the final word. This does not substitute for listening approval.

The HTML listening page switches cleaned/original audio at the same position. Original recording, earlier cut and current unprocessed cut are linked. Reproduction: `tools/clean-founders-audio.py`; model binary provenance and checksums: `founders-video/deep-filter-provenance.json`; output report: `founders-video/founders-welcome-cleaned.json`.
