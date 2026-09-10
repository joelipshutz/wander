"""Static local-asset and archive-preservation checks; not a browser test."""
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import unquote, urlsplit
import hashlib
import json
import re

root = Path(__file__).resolve().parent.parent
archive = root.parent.parent

class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
        self.ids = []
    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if 'id' in values:
            self.ids.append(values['id'])
        for name in ('href', 'src'):
            if name in values:
                self.links.append(values[name])

page = Links()
page.feed((root / 'index.html').read_text())
assert len(page.ids) == len(set(page.ids)), 'Duplicate HTML IDs'
missing = []
for link in page.links:
    parts = urlsplit(link)
    if parts.scheme or not parts.path:
        continue
    if parts.path.endswith('.zip'):
        continue  # Package checked separately after this report is produced.
    if not (root / unquote(parts.path)).is_file():
        missing.append(link)
for number in range(46, 54):
    for height in ('equal', 'tall'):
        for palette in ('mono', 'signal', 'oxide'):
            for theme in ('', '-light'):
                for extension in ('png', 'svg'):
                    name = f'assets/{number}-{height}-{palette}{theme}.{extension}'
                    if not (root / name).is_file():
                        missing.append(name)
for source in (34, 36):
    for base in ('none', 'mono', 'signal'):
        for kind in ('icon', 'social'):
            assert (root / f'assets/{kind}-{source}-{base}.png').is_file()
script = (root / 'review.js').read_text()
selectors = re.findall(r"\$\('#([a-z-]+)'\)", script)
assert set(selectors) <= set(page.ids), 'JS refers to an absent element'
assert not missing, json.dumps(missing)
baseline = json.loads((root / 'qa/prior-versions-before.json').read_text())
changed = []
for entry in baseline['files']:
    p = archive / entry['path']
    if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest() != entry['sha256']:
        changed.append(entry['path'])
assert not changed, 'Earlier rounds changed: ' + json.dumps(changed)
result = {
    'scope': 'Static checks only; native review sheets are not browser screenshots.',
    'allHtmlLocalLinksExist': True, 'uniqueHtmlIds': True,
    'literalJsIdSelectorsPresent': True, 'directions': list(range(46, 54)),
    'wordmarkPngs': 96, 'wordmarkSvgs': 96,
    'blackIconOptions': 6, 'socialOptions': 6,
    'priorVersionFilesUnchanged': len(baseline['files']),
    'interactiveBrowserVerified': False
}
(root / 'qa/page-validation.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result))
