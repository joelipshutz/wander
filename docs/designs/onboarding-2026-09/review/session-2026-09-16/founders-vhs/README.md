# Founders VHS clip study — September 19, 2026

Separate from the approved release video. Three eight-second options reuse the exact Events 03C shader: A 0.62, B 0.82, C 1.0 damage. No Higgsfield credits or remote generation; no face or voice replacement.

## Reproduce

Use Python 3 with PyAV (`pip install av`). From this directory run `python3 extract_frames.py`, then `python3 render_server.py`. Open `http://127.0.0.1:8788/founders-vhs/render.html` and press Render the three clips. Source frames are decoded from `../founders-video/founders-welcome-cleaned.mp4` at 24 fps; WebGL applies the unmodified `events-tape-shader.js`. The server encodes 540×960 H.264 CRF18 and copies the first eight seconds of cleaned AAC packets unchanged. It writes a.mp4/b.mp4/c.mp4 and hash/provenance JSON.

The initial implementation seeking a hidden HTML video produced a frozen input texture in WebKit; it was discarded. Decoded PNG inputs avoid that browser behavior. `source-frames/` is disposable/reproducible intermediate output and does not need to be archived. The original Events shader clock offset and three tracking-fault windows per eight seconds are preserved. The output keeps the founders' original colors; app UI/text stay native and unchanged.

## Selected full movie — C

Joe approved C on September 19. `render_full.py` and `render-full.html` apply the exact same shader, damage 1.0 and clock offset +0.17, to all 2,184 frames at 24 fps. Run the local Python server with PyAV available, open its printed localhost URL and click Render full C. The source frames stream in memory; no multi-gigabyte PNG cache is needed. H.264 uses the same CRF18/fast settings as the approved clip. All cleaned AAC packets are copied unchanged, with only the final picture held for approximately 34 milliseconds to complete a 24 fps frame. `full-c.json` records hashes and verifies the complete audio, including the final outtake.
