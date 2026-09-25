---
name: quote-to-mp4
description: Turn supplied quotes into downloadable MP4 soundbites using verified original recordings, with source attribution and a full clip transcript. Use for quote-to-video, quote-to-MP4, or extracting a speaker's soundbite.
---

# Quote to MP4

Deliver an actual downloadable MP4 of the quoted speaker's original voice.
Finding a source or returning a timestamped link is an intermediate step.

Invoke with `$quote-to-mp4`, the quote, and the speaker if known. A source link,
media attachment, or requested format such as "vertical Reel" can be included.

## Find and verify the recording

- Reuse a source or media file already supplied in the conversation. Otherwise
  search distinctive phrases and locate the original publisher, interview,
  podcast episode, or talk. Prefer publisher media or the episode's public RSS
  enclosure over third-party downloads. Use an available authorized download
  tool; do not assume a particular app, binary location, or account exists.
- Verify the speaker, spoken wording, title, and date. Distinguish a publication
  date from a recording date. If the supplied lines combine different sources,
  explain the mismatch and preserve each source's attribution. Do not splice
  passages into a purported continuous quote without the user's direction.
- If no original recording can be verified or retrieved, state the concrete
  missing input and ask for the source/media. Do not manufacture the speaker's
  voice or silently substitute narration. A narrated quote is a separate option
  only when the user requests it, clearly labeled as narration.

## Locate the actual words

1. Download the authorized source into a task-specific scratch directory outside
   the app checkout. Keep original media and working exports out of Git.
2. Treat published timestamps as search hints. Ads and different editions can
   shift the downloaded audio. Inspect or transcribe a short window around the
   candidate passage, expanding the window when needed.
3. Choose the shortest complete passage that includes the requested words and
   preserves their meaning. Keep natural sentence boundaries and original order.
   Do not impose a fixed duration or include unrelated host speech or ads.
4. Verify the beginning and end against the actual downloaded file. Use the
   original audio or word timestamps, not an edited article transcript alone.

## Export and verify

- Default to a simple, readable title card over the original audio: speaker,
  short topic, source, and verified publication date. Avoid putting the user's
  paraphrase on screen as a verbatim quote. Match any requested branding without
  inventing logos or making the speaker appear to endorse the brand.
- Default to landscape 1280×720. For an explicitly requested Reel/Story, use
  portrait 1080×1920 with text clear of the edges and app controls. Follow a
  supplied aspect ratio or visual brief. Use the source footage instead when
  requested; the still-card helper is optional for that case.
- Export H.264 video with AAC audio in an MP4 container. Preserve the spoken audio
  without background music or synthetic speech unless requested.
- On macOS, [the native media helpers](references/native-media.md) implement
  title-card export, frame verification, and optional on-device transcription.
  They use system frameworks rather than requiring FFmpeg. On other platforms,
  use available media tools with the same output and verification requirements.
- Inspect the rendered frame, confirm the final file has playable video and
  audio, and check its duration and both sentence boundaries. Transcribe the
  **final exported audio**, since decoding/encoding can shift the cut slightly.
  Automated transcripts still need a wording check; mark uncertain words instead
  of inventing them. If verification is blocked, report the gap rather than
  claiming a verified clip.
- Do not install dependencies, download speech models, upload media to a
  transcription service, or change permissions implicitly. Use existing approved
  capabilities and carry forward authorization already given in the task. Stop
  retrying unchanged access failures and surface the specific blocker.

## Deliver

Put the final MP4 in a durable, permitted artifact location and provide a clickable
download link plus an inline preview when supported. Include the duration and
source link. Also deliver the **full spoken transcript of the exported clip** as
a small `.txt` artifact; it must cover the whole clip, without silent shortening,
ellipses, or substitution of a cleaner published paraphrase. A concise social
caption is a separate deliverable only when requested.

Generating the MP4 does not authorize posting it, messaging it to anyone,
publishing it to a social account, or committing the media to the repository.
