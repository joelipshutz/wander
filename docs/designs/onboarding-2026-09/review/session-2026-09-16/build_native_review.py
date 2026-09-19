from pathlib import Path
import argparse, json, re, shutil, struct

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--publish', action='store_true')
options = parser.parse_args()
source = json.loads((ROOT / 'native-copy.json').read_text())
opening_options = json.loads((ROOT / 'opening-current.json').read_text())['takes']
cards = []
pending = []
motion = {
    'W01': ('V01', 'Earlier welcome → create account', 'welcome-to-account.mp4', 'W01'),
    'N06': ('V02', 'Login and email transitions', 'native-auth.mp4', 'N06'),
    'N08': ('V03', 'Live profile setup', 'native-profile.mp4', 'N08'),
    'N09': ('V07', 'Your map comes into view', 'native-location.mp4', 'N09'),
    'N11': ('V04', 'Search and follow', 'native-follow.mp4', 'N11'),
    'N12': ('V05', 'Notification cards arrive', 'native-notifications.mp4', 'N12'),
    'M01': ('V06', 'Full native map overview', 'native-map-overview.mp4', 'M01'),
}
for original in source['cards']:
    card = dict(original)
    image = ROOT / card.get("image", f"native-captures/{card['id']}.png")
    if not image.exists():
        card.update(capturePending=True, originalGroup=card['group'],
                    group='Copy appendix · capture pending')
        card['source'] = card['source'].split('/')[-1]
        pending.append(card)
        continue
    card['image'] = str(image.relative_to(ROOT))
    # Reserve the capture's exact shape before lazy images load. Otherwise a
    # short-copy card grows after layout and overlaps the next canvas row.
    with image.open('rb') as capture:
        header = capture.read(24)
    if header[:8] != b'\x89PNG\r\n\x1a\n' or len(header) < 24:
        raise ValueError(f'Invalid native capture: {image.name}')
    card['imageWidth'], card['imageHeight'] = struct.unpack('>II', header[16:24])
    card['source'] = card['source'].split('/')[-1]
    card.setdefault('captureNote', 'Actual Swift app · iPhone 17 Pro · September 17 review build.')
    card.setdefault('sampleData', card['id'] in ['W02', 'N09', 'N11', 'N12', 'N28', 'N29', 'N32'] or card['id'].startswith(('M', 'C')))
    if card['id'] == 'W00' and not source.get('filmSelected'):
        for take in opening_options:
            key = take['mode']
            movie = ROOT / 'native-captures' / f'opening-{key}.mp4'
            if not movie.exists():
                continue
            clip = dict(card)
            clip.update(id='V00' + take['id'], title=f"Earlier opening {take['id']} · {take['name']}",
                        image=f'native-captures/opening-{key}.png',
                        video=f'native-captures/opening-{key}.mp4',
                        note='Earlier native uppercase baseline: the lead-in was inside the board. Current plain Signal text slides are linked from the Opening review above. Retained for comparison.',
                        lines=[{'role': 'Fixed lead', 'text': take['stableText']},
                               {'role': 'Word sequence', 'text': ' → '.join(take['words'])},
                               {'role': 'Supporting line', 'text': take['description']},
                               {'role': 'Entrance', 'text': take['timing']},
                               {'role': 'Whole headline becomes', 'text': take['finalLockup']}],
                        coverage='Earlier native baseline · superseded by opening-explorations.html', sampleData=False)
            cards.append(clip)
    if card['id'] in motion and ('motionVideo' not in card or card['motionVideo']):
        identifier, title, filename, poster = motion[card['id']]
        movie = ROOT / card.get('motionVideo', 'native-captures/' + filename)
        if movie.exists():
            clip = dict(card)
            clip.update(id=identifier, title=title, video=str(movie.relative_to(ROOT)),
                        note=('Earlier welcome/account baseline; current recordings are in Opening review above.' if identifier=='V01' else 'Play, pause or scrub this recording of the native app. Its animation and transitions run in Swift.'),
                        lines=[{'role':'Review focus', 'text':title}],
                        coverage='Native motion recording')
            cards.append(clip)
            card['motion'] = identifier
    cards.append(card)

# Keep source-backed copy reachable even while simulator captures are pending.
# These appendix entries have no image and must never appear as native captures.
cards.extend(pending)

data = dict(build='REC-547 · actual Swift review · September 19, 2026', cards=cards,
    pending=pending, expectedScreens=len(source['cards']),
    omissions='The former forced save tour (N13–N24) is replaced by the short Map overview. The second-launch import lesson (N26) is removed. The opening shows the selected copy in light and dark mode; prior alternatives remain archived. Plans/Events, contact matching and curated starter lists remain separate work. The complete transcript register preserves the remaining tasks and choices.')
serialized = json.dumps(data, ensure_ascii=False).replace('</', '<\\/')
html = (ROOT / 'native-review.template.html').read_text().replace('__NATIVE_DATA__', serialized)
target = ROOT / ('index.html' if options.publish else 'native-staging.html')
if options.publish:
    archive = ROOT / 'proposal-archive.html'
    if not archive.exists() and (ROOT / 'index.html').exists():
        shutil.copy2(ROOT / 'index.html', archive)
target.write_text(html)
(ROOT / 'native-review-data.json').write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
(ROOT / 'native-review-check.js').write_text(re.search(r'<script>(.*?)</script>', html, re.S).group(1))
if options.publish:
    archive = ROOT / 'motion-proposal-archive.html'
    if not archive.exists() and (ROOT / 'motion-lab.html').exists():
        shutil.copy2(ROOT / 'motion-lab.html', archive)
    (ROOT / 'motion-lab.html').write_text('<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="refresh" content="0;url=./?motion=1"><title>Native Swift motion</title></head><body><a href="./?motion=1">Open the native Swift recordings</a></body></html>')
print(f'{target.name}: {len(cards) - len(pending)} native screens/recordings, '
      f'{len(pending)} source-copy appendix entries, {sum(len(c["lines"]) for c in cards)} copy lines')
if pending:
    print('Capture coverage pending: ' + ', '.join(card['id'] for card in pending))

# A focused recording-session path uses the same pan/zoom and stable line IDs.
# The complete board and archived experiments remain linked above.
order = ['W00','W01','W02','N04','N08','N09','N10','N11','N12','N71','N31','N32','N33','N34','N35','N67','N36']
focused = [next((c for c in cards if c['id'] == key), None) for key in order]
focused = [c for c in focused if c is not None and not c.get('capturePending')]
focused_data = dict(data, cards=focused, pending=[], expectedScreens=len(focused), omissions='Current opening, account setup, welcome video and their related states. Ryan owns the following NUX. Use the complete board for historical screen IDs; use Archives for previous explorations.')
focused_json = json.dumps(focused_data, ensure_ascii=False).replace('</', '<\\/')
focused_html = (ROOT / 'native-review.template.html').read_text().replace('__NATIVE_DATA__', focused_json)
(ROOT / 'device-onboarding-review.html').write_text(focused_html)
