"""Static round-08 file/reference/preservation checks. This is not a browser test."""
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import unquote, urlsplit
import datetime
import hashlib
import json
import re
import struct
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
archive = root.parent.parent
failures = []
pending = []

def check(condition, message):
    if not condition:
        failures.append(message)
    return condition

def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()

def local_reference(value, directory, label, allow_zip=False):
    parts = urlsplit(value)
    if parts.scheme or not parts.path:
        return
    target = directory / unquote(parts.path)
    if allow_zip and target.suffix == '.zip' and not target.is_file():
        pending.append(str(target.relative_to(root)))
        return
    check(target.is_file(), f'{label}: missing local reference {value}')

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
check(len(page.ids) == len(set(page.ids)), 'Duplicate HTML IDs')
for link in page.links:
    if link.startswith('#') and len(link) > 1:
        check(unquote(link[1:]) in page.ids, f'Missing page anchor {link}')
    local_reference(link, root, 'index.html', allow_zip=True)
script = (root / 'review.js').read_text()
selectors = set(re.findall(r"\$\('#([\w-]+)'\)", script))
selectors.update(re.findall(r'''querySelector\(["']#([\w-]+)["']\)''', script))
check(selectors <= set(page.ids), 'Script refers to absent HTML IDs: ' + ', '.join(sorted(selectors - set(page.ids))))
check('download-bundle' in page.ids, 'The bundle download control is missing')
for value in re.findall(r'''url\(\s*["']?([^\)"']+)["']?\s*\)''', (root / 'styles.css').read_text()):
    local_reference(value.strip(), root, 'styles.css')

wordmarks = [f'{number}-tall-{palette}' for number in (46, 54, 55)
             for palette in ('signal', 'oxide')]
icon_configs = [f'{family}-{base}-{palette}' for family in ('34', '36', '36-warm')
                for base in ('long', 'compact') for palette in ('signal', 'oxide')]
icon_configs += [f'{family}-none' for family in ('34', '36', '36-warm')]
expected = [(name, (1600, 764), True) for name in wordmarks]
expected += [(f'{kind}-{config}', (1024, 1024), False)
             for kind in ('icon', 'social') for config in icon_configs]
png_checks = []
svg_checks = []
for stem, dimensions, expect_alpha in expected:
    png = root / 'assets' / f'{stem}.png'
    svg = root / 'assets' / f'{stem}.svg'
    if check(png.is_file(), f'Missing asset {png.name}'):
        header = png.read_bytes()[:29]
        valid = len(header) == 29 and header[:8] == b'\x89PNG\r\n\x1a\n' and header[12:16] == b'IHDR'
        if check(valid, f'Invalid PNG header: {png.name}'):
            width, height, depth, color_type = struct.unpack('>IIBB', header[16:26])
            check((width, height) == dimensions, f'Unexpected PNG dimensions: {png.name} = {width}x{height}')
            if expect_alpha:
                check(color_type in (4, 6), f'Wordmark PNG declares no alpha channel: {png.name}')
            png_checks.append({'file': png.name, 'size': [width, height], 'bitDepth': depth,
                               'colorType': color_type, 'alphaChannelDeclared': color_type in (4, 6)})
    if check(svg.is_file(), f'Missing asset {svg.name}'):
        try:
            document = ET.parse(svg)
            refs = []
            for element in document.iter():
                for key, value in element.attrib.items():
                    if key == 'href' or key.endswith('}href'):
                        if value.startswith(('data:', '#')):
                            continue
                        refs.append(value)
                        check(not urlsplit(value).scheme, f'SVG depends on a remote resource: {svg.name}: {value}')
                        local_reference(value, svg.parent, svg.name)
            svg_checks.append({'file': svg.name, 'validXml': True, 'localDependencies': refs})
        except ET.ParseError as exc:
            failures.append(f'Invalid SVG XML: {svg.name}: {exc}')

metadata = json.loads((root / 'assets/metadata.json').read_text())
direction_ids = [item['id'] for item in metadata.get('directions', [])]
check(sorted(direction_ids) == [46, 54, 55], f'Unexpected metadata direction IDs: {direction_ids}')
check(len(metadata.get('icons', [])) == 15, 'Metadata must describe 15 icon configurations')

reference_checks = []
for palette in ('signal', 'oxide'):
    for extension in ('png', 'svg'):
        name = f'46-tall-{palette}.{extension}'
        original = root.parent / '07-sculpted-identity/assets' / name
        copy = root / 'assets' / name
        identical = original.is_file() and copy.is_file() and digest(original) == digest(copy)
        check(identical, f'Direction 46 reference is not byte-identical: {name}')
        reference_checks.append({'file': name, 'identical': identical})

baseline = json.loads((root / 'qa/prior-versions-before.json').read_text())
expected_prior = {entry['path']: entry for entry in baseline['files']}
changed = []
missing = []
for relative, entry in expected_prior.items():
    path = archive / relative
    if not path.is_file():
        missing.append(relative)
    elif digest(path) != entry['sha256']:
        changed.append(relative)
current_prior = {str(path.relative_to(archive)) for folder in baseline['scope']
                 for path in (archive / folder).rglob('*') if path.is_file()}
added = sorted(current_prior - set(expected_prior))
check(not changed, 'Earlier-round files changed: ' + json.dumps(changed))
check(not missing, 'Earlier-round files missing: ' + json.dumps(missing))
check(not added, 'Earlier-round files added after baseline: ' + json.dumps(added))

native_sheets = ['qa/splash-comparison.png', 'qa/icon-comparison-signal.png',
                 'qa/icon-comparison-oxide.png']
for relative in native_sheets:
    check((root / relative).is_file(), f'Missing native comparison sheet: {relative}')

result = {
    'checkedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'passed': not failures,
    'scope': 'Static local references, SVG XML/dependencies, expected files, PNG headers, reference copies and archive preservation. Not browser interaction or visual QA; alpha pixel extrema and geometry are checked separately by the asset build.',
    'failures': failures, 'pendingPackaging': sorted(set(pending)),
    'uniqueHtmlIds': len(page.ids) == len(set(page.ids)),
    'literalJsIdSelectorsPresent': selectors <= set(page.ids),
    'directions': direction_ids, 'wordmarkPngs': len(wordmarks), 'wordmarkSvgs': len(wordmarks),
    'blackIconOptions': len(icon_configs), 'socialOptions': len(icon_configs),
    'pngChecks': png_checks, 'svgChecks': svg_checks,
    'reference46Copies': reference_checks,
    'priorVersions': {'fileCount': len(expected_prior), 'changed': changed, 'missing': missing, 'added': added},
    'nativeComparisonSheets': {'files': native_sheets, 'kind': 'Native-rendered composition studies',
                              'browserScreenshots': False, 'liveAppScreenshots': False,
                              'visualReviewRecord': 'qa/visual-review.json'},
    'interactiveBrowserVerified': False
}
(root / 'qa/page-validation.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({key: result[key] for key in ('passed', 'failures', 'pendingPackaging', 'directions',
                                               'wordmarkPngs', 'blackIconOptions', 'socialOptions', 'priorVersions')}, indent=2))
raise SystemExit(0 if result['passed'] else 1)
