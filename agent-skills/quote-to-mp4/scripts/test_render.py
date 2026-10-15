#!/usr/bin/env python3
"""Exercise the compiled native renderer with local synthetic media only."""
import hashlib
import json
import math
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import wave


def read_pcm16_wave(path):
    # Core Audio writes WAVE_FORMAT_EXTENSIBLE; Python's wave reader supports
    # that only on 3.12+, while macOS still ships older Python toolchains.
    data = path.read_bytes()
    assert data[:4] == b"RIFF" and data[8:12] == b"WAVE"
    chunks = {}
    offset = 12
    while offset + 8 <= len(data):
        name, size = struct.unpack_from("<4sI", data, offset)
        chunks[name] = data[offset + 8:offset + 8 + size]
        assert len(chunks[name]) == size
        offset += 8 + size + (size % 2)
    fmt = chunks[b"fmt "]
    encoding, channels, rate, _, alignment, bits = struct.unpack_from("<HHIIHH", fmt)
    assert (channels, rate, alignment, bits) == (1, 16000, 2, 16)
    if encoding == 65534:
        assert fmt[24:40] == bytes.fromhex("0100000000001000800000aa00389b71")
    else:
        assert encoding == 1
    pcm = chunks[b"data"]
    return struct.unpack(f"<{len(pcm) // 2}h", pcm)


def main():
    renderer = str(Path(sys.argv[1]).resolve())
    with tempfile.TemporaryDirectory(prefix="quote-render-test-") as directory:
        root = Path(directory)
        audio = root / "tone.wav"
        rate = 16000
        with wave.open(str(audio), "wb") as stream:
            stream.setparams((1, 2, rate, 0, "NONE", "not compressed"))
            stream.writeframes(b"".join(
                struct.pack("<h", int(5000 * math.sin(
                    2 * math.pi * (250, 700, 1200)[i // rate] * i / rate)))
                for i in range(rate * 3)
            ))
        request = dict(input=str(audio), output=str(root / "landscape.mp4"),
                       start=1.25, duration=1.5, speaker="Fixture speaker",
                       title="A local rendering check", source="Synthetic tone fixture",
                       date="Test only", layout="landscape")

        def invoke(payload, succeeds=True):
            spec = root / "request.json"
            spec.write_text(json.dumps(payload))
            result = subprocess.run([renderer, str(spec)], capture_output=True,
                                    text=True, timeout=120)
            assert (result.returncode == 0) == succeeds, result.stderr
            return json.loads(result.stdout) if succeeds else result.stderr

        for layout, dimensions in [("landscape", (1280, 720)), ("portrait", (1080, 1920))]:
            request.update(layout=layout, output=str(root / f"{layout}.mp4"))
            result = invoke(request)
            assert (result["width"], result["height"]) == dimensions
            assert abs(result["duration"] - 1.5) < 0.1
            assert result["audio_tracks"] == result["video_tracks"] == 1
            assert result["video_codec"] == "h264" and result["audio_codec"] == "aac"
            assert Path(result["preview"]).read_bytes().startswith(b"\x89PNG\r\n\x1a\n")
            output = Path(result["output"])
            decoded = root / f"{layout}.wav"
            subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1",
                            str(output), str(decoded)], check=True, capture_output=True, timeout=30)
            samples = read_pcm16_wave(decoded)
            # Check the actual audio, including that the requested source offset
            # was applied: the cut must begin at 700 Hz and end at 1200 Hz.
            for seconds, expected in [(0.2, 700), (1.05, 1200)]:
                window = samples[int(seconds * rate):int((seconds + 0.25) * rate)]
                assert max(abs(value) for value in window) > 2000, "Exported audio is silent"
                crossings = sum(a <= 0 < b for a, b in zip(window, window[1:]))
                measured = crossings * rate / len(window)
                assert abs(measured - expected) < 12, (layout, measured, expected)
            digest = hashlib.sha256(output.read_bytes()).digest()
            assert "already exists" in invoke(request, succeeds=False)
            assert hashlib.sha256(output.read_bytes()).digest() == digest

        for start, duration in [(-1, 1), (0, 0), (2.5, 1)]:
            request.update(start=start, duration=duration, output=str(root / "invalid.mp4"))
            invoke(request, succeeds=False)
            assert not (root / "invalid.mp4").exists()
            assert not (root / "invalid.png").exists()
        request.update(start=0, duration=1, layout="unknown")
        assert "Unknown layout" in invoke(request, succeeds=False)
        print("PASS: landscape/portrait H.264/AAC exports, actual audio offset/content, dimensions, duration, preview, "
              "overwrite protection, invalid ranges, invalid layout")


if __name__ == "__main__":
    main()
