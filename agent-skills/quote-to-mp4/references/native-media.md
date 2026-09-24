# Native macOS media helpers

The renderer needs macOS 13+ and a Swift toolchain with the macOS 15+ SDK
(Xcode 16+). The optional
on-device transcriber needs macOS 26+, a macOS 26 SDK, and an already-installed
speech model for the requested language. Neither helper downloads anything,
requests microphone access, or sends media to a service.

Run from the skill directory. Resolve that directory from the loaded `SKILL.md`,
including when it is symlinked. Compile into a task-specific scratch directory:

```bash
QUOTE_WORK=$(mktemp -d)
xcrun swiftc -parse-as-library scripts/render.swift -o "$QUOTE_WORK/render"
```

Write a UTF-8 JSON request in scratch storage. File paths are absolute. The input
may be an audio file or a video file with an audio track. Times refer to this exact
local source file, after checking for inserted ads:

```json
{
  "input": "/absolute/path/source.mp3",
  "output": "/absolute/path/soundbite.mp4",
  "start": 123.4,
  "duration": 28.6,
  "speaker": "Speaker name",
  "title": "Short topic",
  "source": "Show or publisher",
  "date": "Published YYYY-MM-DD",
  "layout": "landscape"
}
```

`layout` is `landscape` (default) or `portrait`. `date` can be omitted if unknown.
The title card contains metadata, not a transcript. Keep the full source URL in
the delivery message or a companion source note. Output paths must be unused;
the renderer will not overwrite an existing MP4 or its adjacent `.png` preview.

```bash
"$QUOTE_WORK/render" "$QUOTE_WORK/request.json"
```

The renderer checks the requested interval, writes an MP4, verifies H.264/AAC
tracks, decodes a frame to an adjacent PNG, and prints a JSON summary of duration,
dimensions, codecs, and track counts.
Open that PNG for visual inspection. A successful encode alone does not verify
that the correct words were selected.

## Transcription and word times

Compile only when the required SDK and operating system are available:

```bash
xcrun swiftc -parse-as-library scripts/transcribe.swift -o "$QUOTE_WORK/transcribe"
```

The helper accepts a local audio file, an unused output JSON path, and an optional
locale (default `en-US`). It refuses to download missing language models.
If the input format needs conversion, use the system audio converter:

```bash
afconvert -f WAVE -d LEI16@16000 -c 1 "$QUOTE_WORK/source.mp3" "$QUOTE_WORK/source.wav"
"$QUOTE_WORK/transcribe" "$QUOTE_WORK/source.wav" "$QUOTE_WORK/words.json" en-US
```

For long episodes, first extract a bounded candidate audio window with available
media tools, and record its offset from the source. The returned word times are
relative to the transcribed file. Add that offset when selecting a source cut.
For final verification, decode and transcribe the exported MP4 itself:

```bash
afconvert -f WAVE -d LEI16@16000 -c 1 "$QUOTE_WORK/soundbite.mp4" "$QUOTE_WORK/final.wav"
"$QUOTE_WORK/transcribe" "$QUOTE_WORK/final.wav" "$QUOTE_WORK/final-words.json"
```

The JSON contains `text`, `locale`, and `words` with start/end times in seconds.
Read the complete `text`, check wording against the audio where possible, and
save the final transcript as UTF-8 text. Do not replace it with a shorter quote.

If system media services are unavailable in the execution environment, report
the failure and use the environment's approval mechanism for the same scoped
local operation when needed. Do not repeatedly retry, alter system settings, or
switch to a remote transcription service implicitly.

## Maintainer checks

Compile both helpers. Run `python3 scripts/test_render.py /path/to/render` to
exercise real landscape/portrait exports and invalid-range/overwrite handling
using a generated tone fixture. It decodes the exports and checks the audio
frequencies at the start and end to verify the source offset was applied.
The check writes only to a temporary directory; it does not use a real person's
recording or require network access. Inspect the
generated frame from a real quote separately before delivering that quote.
