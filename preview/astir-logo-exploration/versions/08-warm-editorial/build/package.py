"""Build the round-08 portable archive only after its page and assets are ready."""
from pathlib import Path
from html.parser import HTMLParser
import hashlib
import json
import re
import zipfile

round_dir = Path(__file__).resolve().parent.parent
zip_name = 'ASTIR-exploration-08.zip'
zip_path = round_dir / zip_name
prefix = 'Astir-exploration-08/versions/08-warm-editorial/'
hub_name = 'Astir-exploration-08/START-HERE.html'

for required in ('index.html', 'review.js', 'styles.css', 'README.md',
                 'assets/metadata.json', 'qa/page-validation.json',
                 'build/portable-start.html'):
    assert (round_dir / required).is_file(), f'Not ready: missing {required}'
validation = json.loads((round_dir / 'qa/page-validation.json').read_text())
assert validation.get('passed') is True, 'Static validation must pass before packaging'
files = sorted(p for p in round_dir.rglob('*') if p.is_file()
               and p.suffix not in {'.zip', '.pyc'} and '__pycache__' not in p.parts
               and p.name not in {'ARCHIVE-MANIFEST.json', 'package-validation.json'})

def record(relative, data):
    return {'path': str(relative), 'bytes': len(data),
            'sha256': hashlib.sha256(data).hexdigest()}

def portable_page(text):
    """Replace self-download and absent round-07 anchors in the portable copy."""
    count = 0
    previous_count = 0
    def replacement(match):
        nonlocal count, previous_count
        attrs, label = match.group(1), match.group(2)
        href = re.search(r'\bhref\s*=\s*([\"\'])(.*?)\1', attrs, re.I)
        if href and href.group(2) == '../07-sculpted-identity/index.html':
            previous_count += 1
            return '<span>Previous rounds remain in the full Astir archive.</span>'
        if not href or href.group(2) != zip_name:
            return match.group(0)
        count += 1
        if re.search(r'\bid\s*=\s*([\"\'])download-bundle\1', attrs):
            return '<span id="download-bundle">Editable assets included in this folder</span>'
        return '<span>Portable saved copy</span>'
    output = re.sub(r'<a\b([^>]*)>(.*?)</a>', replacement, text,
                    flags=re.I | re.S)
    assert count == 2, f'Expected two round-08 bundle links; found {count}'
    assert previous_count == 1, f'Expected one round-07 return link; found {previous_count}'
    return output

manifest = {'round': 8, 'date': '2026-09-09', 'files': [
    record(p.relative_to(round_dir), p.read_bytes()) for p in files]}
(round_dir / 'ARCHIVE-MANIFEST.json').write_text(json.dumps(manifest, indent=2) + '\n')
portable_files = []
hub = (round_dir / 'build/portable-start.html').read_bytes()
with zipfile.ZipFile(zip_path, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
    bundle.writestr(hub_name, hub)
    for path in files:
        relative = str(path.relative_to(round_dir))
        content = path.read_bytes()
        if relative == 'index.html':
            content = portable_page(content.decode('utf-8')).encode('utf-8')
        bundle.writestr(prefix + relative, content)
        portable_files.append(record(relative, content))
    bundle.writestr(prefix + 'ARCHIVE-MANIFEST.json',
                    json.dumps({**manifest, 'files': portable_files}, indent=2) + '\n')

class LocalLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
    def handle_starttag(self, tag, attrs):
        for name, value in attrs:
            if name in ('href', 'src') and value:
                self.links.append(value)

import posixpath
from urllib.parse import unquote, urlsplit
with zipfile.ZipFile(zip_path) as bundle:
    assert bundle.testzip() is None, 'ZIP CRC verification failed'
    names = set(bundle.namelist())
    for item in portable_files:
        assert hashlib.sha256(bundle.read(prefix + item['path'])).hexdigest() == item['sha256']
    for html_name in (hub_name, prefix + 'index.html'):
        parser = LocalLinks()
        parser.feed(bundle.read(html_name).decode('utf-8'))
        for link in parser.links:
            parts = urlsplit(link)
            if parts.scheme or not parts.path:
                continue
            destination = posixpath.normpath(posixpath.join(posixpath.dirname(html_name), unquote(parts.path)))
            assert destination in names, f'Broken portable link: {html_name} -> {link}'
    assert f'href="{zip_name}"'.encode() not in bundle.read(prefix + 'index.html')

result = {'archive': zip_name, 'bytes': zip_path.stat().st_size,
          'fileCount': len(portable_files) + 2, 'crcVerified': True,
          'sha256Verified': True, 'portableLocalLinksVerified': True,
          'selfDownloadLinksRemoved': True, 'previousRoundLinkReplaced': True,
          'hubSha256': hashlib.sha256(hub).hexdigest()}
(round_dir / 'qa/package-validation.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
