"""Local, deterministic export of the unchanged Events shader over founders footage."""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from fractions import Fraction
import hashlib, io, json, threading
import av
ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'founders-vhs'; PORT=8788
PROFILES={'a':.62,'b':.82,'c':1.0}; FPS=24; COUNT=192
writers={};lock=threading.Lock()
def mux_audio(key):
    silent=OUT/(key+'-picture.mp4'); final=OUT/(key+'.mp4')
    picture=av.open(str(silent)); original=av.open(str(ROOT/'founders-video/founders-welcome-cleaned.mp4'))
    dest=av.open(str(final),'w',options={'movflags':'+faststart'})
    vo=dest.add_stream_from_template(picture.streams.video[0]);ao=dest.add_stream_from_template(original.streams.audio[0]);packets=[]
    for p in picture.demux(picture.streams.video[0]):
        if p.dts is not None:p.stream=vo;packets.append((float(p.dts*p.time_base),p))
    for p in original.demux(original.streams.audio[0]):
        if p.dts is not None and float(p.pts*p.time_base)<8:
            p.stream=ao;packets.append((float(p.dts*p.time_base),p))
    for _,p in sorted(packets,key=lambda row:row[0]):dest.mux(p)
    dest.close();picture.close();original.close()
    check=av.open(str(final));assert len(check.streams.video)==len(check.streams.audio)==1;check.close()
    silent.unlink()
    return {'file':final.name,'damage':PROFILES[key],'durationSeconds':8,'frames':COUNT,'shaderSha256':hashlib.sha256((OUT/'events-tape-shader.js').read_bytes()).hexdigest(),'sourceSha256':hashlib.sha256((ROOT/'founders-video/founders-welcome-cleaned.mp4').read_bytes()).hexdigest(),'sha256':hashlib.sha256(final.read_bytes()).hexdigest(),'audio':'unchanged cleaned-source AAC packets','higgsfieldCredits':0}
class Handler(SimpleHTTPRequestHandler):
    def __init__(self,*args,**kwargs):super().__init__(*args,directory=str(ROOT),**kwargs)
    def log_message(self,*args):pass
    def do_POST(self):
        if self.headers.get('Origin')!=f'http://127.0.0.1:{PORT}':self.send_error(403);return
        try:
            _,action,key,*rest=self.path.split('/')
            assert key in PROFILES
            with lock:
                if action=='start':
                    assert key not in writers
                    path=OUT/(key+'-picture.mp4');c=av.open(str(path),'w');s=c.add_stream('libx264',rate=FPS);s.width=540;s.height=960;s.pix_fmt='yuv420p';s.options={'crf':'18','preset':'fast'};s.codec_context.thread_count=1
                    writers[key]={'container':c,'stream':s,'count':0};result={'started':key}
                elif action=='frame':
                    n=int(rest[0]);w=writers[key];assert n==w['count'] and n<COUNT
                    size=int(self.headers['Content-Length']);assert 0<size<5_000_000
                    data=self.rfile.read(size);im=av.open(io.BytesIO(data));f=next(im.decode(video=0));assert (f.width,f.height)==(540,960)
                    f.pts=n;f.time_base=Fraction(1,FPS)
                    for packet in w['stream'].encode(f):w['container'].mux(packet)
                    w['count']+=1;im.close()
                    if n in (0,43):(OUT/f'{key}-{n}.png').write_bytes(data)
                    result={'frame':n}
                elif action=='finish':
                    w=writers.pop(key);assert w['count']==COUNT
                    for p in w['stream'].encode():w['container'].mux(p)
                    w['container'].close();result=mux_audio(key);(OUT/(key+'.json')).write_text(json.dumps(result,indent=2)+'\n')
                else:raise ValueError('Unsupported action')
            body=json.dumps(result).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
        except Exception as e:self.send_error(400,str(e))
print(f'Local VHS render studio: http://127.0.0.1:{PORT}/founders-vhs/render.html',flush=True)
ThreadingHTTPServer(('127.0.0.1',PORT),Handler).serve_forever()
