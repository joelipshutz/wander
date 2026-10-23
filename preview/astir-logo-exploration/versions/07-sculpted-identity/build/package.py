"""Package this immutable exploration with a portable entry and verified hashes."""
from pathlib import Path
import hashlib
import json
import zipfile

round_dir = Path(__file__).resolve().parent.parent
zip_path = round_dir / 'ASTIR-exploration-07.zip'
files = sorted(p for p in round_dir.rglob('*') if p.is_file()
               and p.suffix not in {'.zip', '.pyc'} and '__pycache__' not in p.parts
               and p.name not in {'ARCHIVE-MANIFEST.json', 'package-validation.json'})

def record(relative, data):
    return {'path': str(relative), 'bytes': len(data),
            'sha256': hashlib.sha256(data).hexdigest()}

manifest = {'round': 7, 'date': '2026-09-09', 'files': [
    record(p.relative_to(round_dir), p.read_bytes()) for p in files]}
(round_dir / 'ARCHIVE-MANIFEST.json').write_text(json.dumps(manifest, indent=2) + '\n')
portable_files = []
prefix = 'Astir-exploration-07/versions/07-sculpted-identity/'
with zipfile.ZipFile(zip_path, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
    bundle.writestr('Astir-exploration-07/START-HERE.html',
                    (round_dir / 'build/portable-start.html').read_bytes())
    for path in files:
        relative = str(path.relative_to(round_dir))
        content = path.read_bytes()
        if relative == 'index.html':
            content = content.replace(
                b'<a id="download-composition" href="ASTIR-exploration-07.zip" download>Editable bundle \xe2\x86\x93</a>',
                b'<span>Editable assets included in this folder</span>')
            content = content.replace(
                b'<a href="ASTIR-exploration-07.zip" download>Save this round \xe2\x86\x93</a>',
                b'<span>Portable saved copy</span>')
        if relative == 'review.js':
            content = content.replace(b"$('#download-composition').href='ASTIR-exploration-07.zip';", b'')
        bundle.writestr(prefix + relative, content)
        portable_files.append(record(relative, content))
    bundle.writestr(prefix + 'ARCHIVE-MANIFEST.json',
                    json.dumps({**manifest, 'files': portable_files}, indent=2) + '\n')
with zipfile.ZipFile(zip_path) as bundle:
    assert bundle.testzip() is None
    assert b'href="ASTIR-exploration-07.zip"' not in bundle.read(prefix + 'index.html')
    for item in portable_files:
        assert hashlib.sha256(bundle.read(prefix + item['path'])).hexdigest() == item['sha256']
result = {'archive': zip_path.name, 'bytes': zip_path.stat().st_size,
          'fileCount': len(portable_files) + 2, 'crcVerified': True,
          'sha256Verified': True, 'selfDownloadLinksRemoved': True}
(round_dir / 'qa/package-validation.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result))
