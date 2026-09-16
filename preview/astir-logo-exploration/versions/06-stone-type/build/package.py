"""Package the saved exploration with a self-contained archive entry."""
from pathlib import Path
import hashlib
import json
import zipfile

round_dir = Path(__file__).resolve().parent.parent
zip_path = round_dir / 'ASTIR-exploration-06.zip'
files = sorted(p for p in round_dir.rglob('*') if p.is_file()
               and p.suffix not in {'.zip', '.pyc'} and '__pycache__' not in p.parts
               and p.name != 'ARCHIVE-MANIFEST.json')

def record(relative, data):
    return {'path': str(relative), 'bytes': len(data),
            'sha256': hashlib.sha256(data).hexdigest()}

manifest = {'round': 6, 'date': '2026-09-09', 'files': [
    record(p.relative_to(round_dir), p.read_bytes()) for p in files]}
(round_dir / 'ARCHIVE-MANIFEST.json').write_text(json.dumps(manifest, indent=2) + '\n')
portable_files = []
with zipfile.ZipFile(zip_path, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
    bundle.writestr('Astir-exploration-06/START-HERE.html',
                    (round_dir / 'build/portable-start.html').read_bytes())
    for path in files:
        relative = path.relative_to(round_dir)
        content = path.read_bytes()
        if str(relative) == 'index.html':
            content = content.replace(
                b'<a href="ASTIR-exploration-06.zip" download>Download this round \xe2\x86\x93</a>',
                b'<span>Portable saved copy</span>')
        bundle.writestr(str(Path('Astir-exploration-06/versions/06-stone-type') / relative), content)
        portable_files.append(record(relative, content))
    portable_manifest = {**manifest, 'files': portable_files}
    bundle.writestr('Astir-exploration-06/versions/06-stone-type/ARCHIVE-MANIFEST.json',
                    json.dumps(portable_manifest, indent=2) + '\n')
with zipfile.ZipFile(zip_path) as bundle:
    assert bundle.testzip() is None
    index = bundle.read('Astir-exploration-06/versions/06-stone-type/index.html')
    assert b'href="ASTIR-exploration-06.zip"' not in index
print(json.dumps({'archive': str(zip_path), 'bytes': zip_path.stat().st_size,
                  'fileCount': len(portable_files) + 2, 'crcVerified': True}))
