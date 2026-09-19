from pathlib import Path
import json, re
p=Path(__file__).resolve().parent
source=p/'review.template.html'
data=json.loads((p/'revisions.json').read_text())
base=json.loads((p.parent/'content.json').read_text())
brand=json.loads((p.parent/'brand.json').read_text())
copy_lines=['# Astir onboarding — recording copy deck', '\nAll alternatives are proposals unless marked accepted baseline copy. No app implementation is implied. Choose in the review room and export decisions.\n']
for card in data['cards']:
    copy_lines += [f"## {card['id']} — {card['title']}", f"\nBaseline: {', '.join(card['baseline']) or 'new experience'} · Tasks: {', '.join(card['tasks'])}", f"\nDirection: {card['decision']}"]
    if card.get('dependency'):
        copy_lines.append(f"\nDependency: {card['dependency']}")
    for variant_index, variant in enumerate(card['variants']):
        copy_lines += [f"\n### {variant['label']}\n", variant.get('note', ''), '']
        for line_index, line in enumerate(variant['lines']):
            copy_lines.append(f"- **{card['id']}.{chr(65 + variant_index)}.{line_index + 1:02d}** · {line['role']}: {line['text']}")
    copy_lines.append('')
(p/'COPY-DECK.md').write_text('\n'.join(copy_lines))
docs={f.name:f.read_text() for f in p.glob('*.md')}
def script_json(v): return json.dumps(v,ensure_ascii=False).replace('</','<\\/')
s=source.read_text()
for tag,value in [('__DATA__',data),('__BASELINE__',base),('__DOCS__',docs),('__BRAND__',brand)]: s=s.replace(tag,script_json(value))
(p/'index.html').write_text(s)
js=re.search(r'<script>(.*?)</script>',s,re.S).group(1)
(p/'review-check.js').write_text(js)
print(f'{len(data["cards"])} cards / {sum(len(c["variants"]) for c in data["cards"])} variants / {len(docs)} docs; {len(s):,} characters')
