"""Build and validate the Events planning map, not application test coverage."""
import csv
import hashlib
import json
import re
import subprocess
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

root = Path(__file__).resolve().parent.parent
out = root / 'test-review'
source = root / 'events-exit-criteria.md'
repo = next((p for p in root.parents if (p / '.git').exists()), root.parent / 'wander-events-flowchart-review')
evidence_commit = 'f8d258e869503a28d70518a050dff36a344134c6'
sources = {}
for line in source.read_text().splitlines():
    if not re.match(r'^\| [LIBMAPVHCE]\d{2} \|', line):
        continue
    cells = [part.strip() for part in line.strip('|').split('|')]
    if len(cells) != 4:
        raise ValueError(f'Unexpected source row: {cells[0]}')
    case_id, start, expected, authority = cells
    if case_id in sources:
        raise ValueError(f'Duplicate source ID: {case_id}')
    sources[case_id] = dict(start=start, expected=expected, authority=authority)
assert len(sources) == 121, f'Acceptance count changed: {len(sources)}'

fragments = ['native-entry.json', 'booking-door.json', 'recap-history.json', 'cross-cutting.json']
cases = {}
risks = {}
provenance = []
evidence_refs = set()
for filename in fragments:
    path = out / filename
    data = json.loads(path.read_text())
    evidence = data.get('framework_evidence', []) + [entry for item in data['cases'] + data['additional_risks'] for entry in item.get('existing_evidence', [])]
    for entry in evidence:
        evidence_line = int(entry['line'])
        evidence_source = subprocess.check_output(['git', 'show', f"{evidence_commit}:{entry['file']}"], cwd=repo, text=True)
        assert 0 < evidence_line <= len(evidence_source.splitlines()), (filename, entry)
        evidence_refs.add((entry['file'], evidence_line))
    provenance.append(dict(file=filename, sha256=hashlib.sha256(path.read_bytes()).hexdigest(), baseline=data['baseline']))
    for kind, items in [('acceptance', data['cases']), ('technical_risk', data['additional_risks'])]:
        target = cases if kind == 'acceptance' else risks
        for original in items:
            item = dict(original)
            case_id = item['id']
            assert case_id not in cases and case_id not in risks, f'Duplicate mapping: {case_id}'
            for key in ('layers', 'planned_files', 'assertions'):
                assert isinstance(item[key], list) and item[key], (case_id, key)
                assert all(isinstance(value, str) and value.strip() for value in item[key]), (case_id, key)
            assert item['owner_package'], case_id
            assert isinstance(item['requires_real_device'], bool), case_id
            for planned in item['planned_files']:
                assert not planned.startswith('/') and '..' not in Path(planned).parts, (case_id, planned)
            item.update(kind=kind, implementation_status='not_implemented', execution_status='not_run', fragment=filename)
            if kind == 'acceptance':
                assert case_id in sources, f'Unknown acceptance mapping: {case_id}'
                item['source'] = sources[case_id]
                item['authority_status'] = 'inherit_source_trace; mapping grants no new product approval'
                item['has_explicit_proposed_clause'] = bool(re.search(r'propos|unresolved|remain.*review|design work', sources[case_id]['authority'], re.I))
            else:
                assert item.get('description'), case_id
            target[case_id] = item

assert set(cases) == set(sources), f'Missing acceptance mappings: {sorted(set(sources) - set(cases))}'
for item in cases.values():
    for evidence in item.get('existing_evidence', []):
        assert evidence.get('file') and int(evidence['line']) > 0 and evidence.get('note'), item['id']

ordered = [cases[case_id] for case_id in sources]
additional = [risks[case_id] for case_id in sorted(risks)]
metadata = dict(
    schema_version=1,
    generated_at=datetime.now(timezone.utc).isoformat(),
    title='Astir Events planned acceptance-to-test map',
    status='planning_only_not_implemented_not_run',
    source='events-exit-criteria.md',
    source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
    source_case_count=len(sources),
    mapped_case_count=len(cases),
    additional_risk_count=len(risks),
    mapping_completeness='121/121 named scenarios mapped; not runtime/code coverage',
    implemented_events_cases=0,
    executed_events_cases=0,
    cases_with_explicit_proposed_clauses=sum(i['has_explicit_proposed_clause'] for i in ordered),
    fragments=provenance,
)
(out/'coverage-map.json').write_text(json.dumps({**metadata, 'cases': ordered, 'additional_risks': additional}, indent=2, ensure_ascii=False)+'\n')

lines = ['# Astir Events — planned test mapping', '',
         '**Planning only. No listed Events test has been implemented, executed or passed by this review.**', '',
         f'{len(cases)}/121 acceptance IDs mapped, plus {len(risks)} technical risk cases. Mapping completeness is not measured code or runtime coverage.', '',
         'The source authority trace is retained verbatim. Proposed clauses remain unapproved; planned test paths do not yet exist unless explicitly identified as adjacent existing evidence.', '']
for item in ordered + additional:
    case_id = item['id']
    title = item['source']['start'] if item['kind'] == 'acceptance' else item['description']
    lines += [f'## {case_id} — {title}', '',
              f"Owner: {item['owner_package']}. Layers: {', '.join(item['layers'])}. Real-device evidence required: {'yes' if item['requires_real_device'] else 'no' }.", '',
              'Planned files: '+', '.join(f'`{p}`' for p in item['planned_files'])+'.', '']
    lines += [f'- {assertion}' for assertion in item['assertions']]
    if item['kind'] == 'acceptance':
        lines += ['', 'Source authority: '+item['source']['authority']]
    if item.get('existing_evidence'):
        lines += ['', 'Adjacent existing evidence (not implemented Events coverage):']
        lines += [f"- `{e['file']}:{e['line']}` — {e['note']}" for e in item['existing_evidence']]
    lines += ['']
(out/'coverage-map.md').write_text('\n'.join(lines))

with (out/'coverage-map.tsv').open('w', newline='') as file:
    writer = csv.writer(file, delimiter='\t')
    writer.writerow(['ID','Kind','Owner','Layers','Planned files','Assertions','Authority','Implementation','Execution'])
    for item in ordered + additional:
        writer.writerow([item['id'],item['kind'],item['owner_package'],'; '.join(item['layers']),'; '.join(item['planned_files']),' | '.join(item['assertions']),item.get('source',{}).get('authority','technical requirement derived from engineering plan'),item['implementation_status'],item['execution_status']])

report = {**metadata, 'case_family_counts': dict(Counter(i[0] for i in cases)),
          'existing_source_locations_checked': len(evidence_refs),
          'all_ids_unique': True, 'every_case_has_files_layers_assertions_owner': True,
          'proposed_authority_preserved': True, 'application_tests_run': False}
(out/'mapping-verification.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps({k:report[k] for k in ['mapped_case_count','additional_risk_count','cases_with_explicit_proposed_clauses','all_ids_unique','application_tests_run']}, indent=2))
