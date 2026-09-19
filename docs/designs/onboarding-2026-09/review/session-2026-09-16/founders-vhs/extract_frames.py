"""Decode source frames before shader rendering; avoids paused-video WebKit texture caching."""
from pathlib import Path
import av
ROOT=Path(__file__).resolve().parent
out=ROOT/'source-frames';out.mkdir(exist_ok=True)
source=av.open(str(ROOT.parent/'founders-video/founders-welcome-cleaned.mp4'))
frames=iter(source.decode(video=0));current=next(frames)
for n in range(192):
    while float(current.time)<n/24:
        current=next(frames)
    enc=av.CodecContext.create('png','w');enc.width=current.width;enc.height=current.height;enc.pix_fmt='rgb24'
    (out/f'{n:03d}.png').write_bytes(b''.join(bytes(p) for p in enc.encode(current.reformat(format='rgb24'))))
source.close()
print('192 source frames decoded at 24 fps')
