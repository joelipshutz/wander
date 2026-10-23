"""Local-only preview server; export writes two named videos and four stills."""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse
import argparse

ROOT = Path(__file__).resolve().parents[2]
MEDIA = ROOT / 'preview/splash-vhs/media'
NAMES = {'splash-v2.mp4', 'account-v2.mp4', 'splash-v2.webm', 'account-v2.webm',
         'splash-static.png', 'account-static.png', 'logo-static.png', 'logo-tear.png'}
class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)
    def do_POST(self):
        name = urlparse(self.path).path.removeprefix('/__export/')
        origin = self.headers.get('Origin')
        expected = f'http://127.0.0.1:{self.server.server_port}'
        length = int(self.headers.get('Content-Length', '0'))
        if not self.path.startswith('/__export/') or name not in NAMES or origin != expected or not 0 < length <= 32_000_000:
            self.send_error(403); return
        MEDIA.mkdir(exist_ok=True)
        (MEDIA / name).write_bytes(self.rfile.read(length))
        self.send_response(201); self.end_headers(); self.wfile.write(b'saved')
    def log_message(self, fmt, *args):
        if args and str(args[0]).startswith('POST'): super().log_message(fmt, *args)
if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--port', type=int, default=65364)
    args = parser.parse_args()
    print(f'Preview: http://127.0.0.1:{args.port}/preview/splash-vhs/', flush=True)
    ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
