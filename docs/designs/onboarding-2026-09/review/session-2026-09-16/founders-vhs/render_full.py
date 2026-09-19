"""Stream real decoded frames through the approved C shader, without disk PNGs.
Run with PyAV installed, open localhost:8789/founders-vhs/render-full.html, click Render.
"""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from fractions import Fraction
import hashlib, io, json, threading
import av
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'founders-vhs'
SOURCE = ROOT / 'founders-video/founders-welcome-cleaned.mp4'
PORT, FPS, COUNT = 8789, 24, 2184
state = {}; lock = threading.Lock()
def digest(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda:f.read(1024*1024), b''): h.update(chunk)
    return h.hexdigest()
def audio_packets(path):
    with av.open(str(path)) as c:
        return [hashlib.sha256(bytes(p)).hexdigest() for p in c.demux(audio=0) if p.dts is not None]
def finish():
    w = state
    assert w['count'] == COUNT
    for p in w['stream'].encode(): w['container'].mux(p)
    w['container'].close(); w['source'].close()
    silent = OUT / 'full-c-picture.mp4'; final = OUT / 'full-c.mp4'
    with av.open(str(silent)) as picture, av.open(str(SOURCE)) as source, av.open(str(final), 'w', options={'movflags': '+faststart'}) as dest:
        vo = dest.add_stream_from_template(picture.streams.video[0])
        ao = dest.add_stream_from_template(source.streams.audio[0]); packets = []
        for c, stream, target in [(picture, picture.streams.video[0], vo), (source, source.streams.audio[0], ao)]:
            for p in c.demux(stream):
                if p.dts is not None:
                    p.stream = target; packets.append((float(p.dts*p.time_base), p))
        for _, p in sorted(packets, key=lambda x: x[0]): dest.mux(p)
    with av.open(str(final)) as c:
        frames = sum(1 for _ in c.decode(video=0)); duration = c.duration / av.time_base
    assert frames == COUNT
    assert audio_packets(final) == audio_packets(SOURCE), 'Cleaned audio packets must remain identical'
    result = dict(file=final.name, selected='C / Events 03C', damage=1.0, shaderClockOffset=.17, frames=frames,
                  fps=FPS, durationSeconds=duration, resolution=[540,960], encoding='H.264 CRF18 preset fast (same as approved C clip)',
                  sourceSha256=digest(SOURCE), shaderSha256=digest(OUT/'events-tape-shader.js'), sha256=digest(final),
                  audio='All cleaned-source AAC packets unchanged, including the outtake through Cut',
                  finalPictureHoldMilliseconds=34, higgsfieldCredits=0)
    (OUT/'full-c.json').write_text(json.dumps(result, indent=2)+'\n')
    silent.unlink(); print(json.dumps(result), flush=True)
    return result
class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs): super().__init__(*args, directory=str(ROOT), **kwargs)
    def log_message(self, *args): pass
    def respond(self, data, mime='application/json'):
        self.send_response(200); self.send_header('Content-Type', mime); self.send_header('Content-Length', str(len(data))); self.send_header('Cache-Control','no-store'); self.end_headers(); self.wfile.write(data)
    def do_GET(self):
        if not self.path.startswith('/source-frame/'): return super().do_GET()
        try:
            with lock:
                n = int(self.path.split('/')[-1]); assert n == state['count'] and n < COUNT
                while float(state['current'].time) < n/FPS:
                    try: state['current'] = next(state['frames'])
                    except StopIteration: break
                f = state['current'].reformat(format='rgb24')
                enc = av.CodecContext.create('png', 'w'); enc.width=f.width; enc.height=f.height; enc.pix_fmt='rgb24'
                data = b''.join(bytes(p) for p in enc.encode(f))
            self.respond(data, 'image/png')
        except Exception as e: self.send_error(400, str(e))
    def do_POST(self):
        if self.headers.get('Origin') != f'http://127.0.0.1:{PORT}': return self.send_error(403)
        try:
            with lock:
                if self.path == '/start':
                    assert not state
                    c=av.open(str(OUT/'full-c-picture.mp4'), 'w'); s=c.add_stream('libx264',rate=FPS)
                    s.width=540; s.height=960; s.pix_fmt='yuv420p'; s.options={'crf':'18','preset':'fast'}; s.codec_context.thread_count=1
                    source=av.open(str(SOURCE)); frames=iter(source.decode(video=0))
                    state.update(container=c,stream=s,count=0,source=source,frames=frames,current=next(frames)); result={'frames':COUNT}
                elif self.path.startswith('/frame/'):
                    n=int(self.path.split('/')[-1]); assert n==state['count'] and n<COUNT
                    size=int(self.headers['Content-Length']); assert 0<size<5_000_000
                    data=self.rfile.read(size)
                    with av.open(io.BytesIO(data)) as im:
                        f=next(im.decode(video=0)); assert (f.width,f.height)==(540,960)
                        f.pts=n; f.time_base=Fraction(1,FPS)
                        for p in state['stream'].encode(f): state['container'].mux(p)
                    if n in (0,43,1800,2183): (OUT/f'full-c-{n}.png').write_bytes(data)
                    state['count']+=1
                    if n%240==0: print(f'{n+1}/{COUNT}', flush=True)
                    result={'frame':n}
                elif self.path == '/finish': result=finish()
                else: raise ValueError('Unknown route')
            self.respond(json.dumps(result).encode())
        except Exception as e: self.send_error(400,str(e))
print(f'http://127.0.0.1:{PORT}/founders-vhs/render-full.html', flush=True)
ThreadingHTTPServer(('127.0.0.1',PORT), Handler).serve_forever()
