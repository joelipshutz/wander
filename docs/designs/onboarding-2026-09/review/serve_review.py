"""Local review server with byte-range support for native simulator movies."""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
import argparse, functools, os, re

class ReviewHandler(SimpleHTTPRequestHandler):
    def send_head(self):
        self.byte_range = None
        path = self.translate_path(self.path)
        if not os.path.isfile(path):
            return super().send_head()
        try:
            stream = open(path, 'rb')
        except OSError:
            self.send_error(404, 'File not found'); return None
        info = os.fstat(stream.fileno()); size = info.st_size
        start, end = 0, size - 1
        header = self.headers.get('Range')
        if header:
            match = re.fullmatch(r'bytes=(\d*)-(\d*)', header.strip())
            if match and (match[1] or match[2]):
                if match[1]:
                    start = int(match[1]); end = min(int(match[2]), end) if match[2] else end
                else:
                    start = max(0, size - int(match[2]))
                if start > end or start >= size:
                    stream.close(); self.send_response(416)
                    self.send_header('Content-Range', f'bytes */{size}')
                    self.send_header('Content-Length', '0'); self.end_headers(); return None
                self.byte_range = (start, end)
        self.send_response(206 if self.byte_range else 200)
        self.send_header('Content-Type', self.guess_type(path))
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Content-Length', str(end - start + 1))
        self.send_header('Last-Modified', self.date_time_string(info.st_mtime))
        if self.byte_range: self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
        self.end_headers(); stream.seek(start); return stream

    def copyfile(self, source, outputfile):
        if self.byte_range is None:
            try: return super().copyfile(source, outputfile)
            except (BrokenPipeError, ConnectionResetError): return
        remaining = self.byte_range[1] - self.byte_range[0] + 1
        try:
            while remaining:
                chunk = source.read(min(256 * 1024, remaining))
                if not chunk: break
                outputfile.write(chunk); remaining -= len(chunk)
        except (BrokenPipeError, ConnectionResetError): pass

if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--port', type=int, default=8766)
    options = parser.parse_args()
    handler = functools.partial(ReviewHandler, directory=str(Path(__file__).resolve().parent))
    ThreadingHTTPServer(('127.0.0.1', options.port), handler).serve_forever()
