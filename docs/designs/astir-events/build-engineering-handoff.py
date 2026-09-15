"""Validate and render planning tasks; does not execute implementation work."""
import json
import subprocess
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

root = Path(__file__).resolve().parent
tasks = json.loads((root / 'implementation-tasks.source.json').read_text())
by_id = {task['id']: task for task in tasks}
assert len(by_id) == len(tasks)
state = {}
order = []
def visit(key):
    assert key in by_id, key
    assert state.get(key) != 'visiting', f'Cycle at {key}'
    if state.get(key) == 'done': return
    state[key] = 'visiting'
    for dep in by_id[key]['depends_on']: visit(dep)
    state[key] = 'done'
    order.append(key)
for task in tasks:
    for key in ('id','priority','component','title','source_finding','files','modules','stage','lane','verify','exit_criteria'):
        assert task[key], (task['id'],key)
    assert task['lane'] in ('A','B','shared','joined')
    assert task['priority'] in ('P1','P2','P3')
    for prefix in ('human','agent'):
        assert 0 <= task[f'{prefix}_hours_min'] <= task[f'{prefix}_hours_max']
    visit(task['id'])

run_id = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
common = {'phase':'eng-review','run_id':run_id,'branch':'codex/rec-467-events-engineering-handoff',
          'commit':'f8493c0','planning_only':True}
jsonl = []
for task in tasks:
    # One jq -nc invocation per task, per the gstack aggregation contract.
    args = ['jq','-nc']
    for key,value in {**common,**task}.items():
        args += ['--argjson',key,json.dumps(value,ensure_ascii=False)]
    fields = ','.join(f'{key}:${key}' for key in {**common,**task})
    jsonl.append(subprocess.check_output(args+['{'+fields+'}'],text=True).rstrip())
(root/'implementation-tasks.jsonl').write_text('\n'.join(jsonl)+'\n')

def scheduled(prefix, bound):
    available={'A':0,'B':0}; finish={}; rows=[]
    for key in order:
        task=by_id[key]; lanes=['A','B'] if task['lane'] in ('shared','joined') else [task['lane']]
        start=max([finish[x] for x in task['depends_on']]+[available[x] for x in lanes])
        end=start+task[f'{prefix}_hours_{bound}']
        for lane in lanes:available[lane]=end
        finish[key]=end;rows.append({'id':key,'lane':task['lane'],'start':start,'finish':end})
    return {'elapsed_active_hours':max(available.values()),'order':rows}

totals={prefix:{bound:sum(t[f'{prefix}_hours_{bound}'] for t in tasks) for bound in ('min','max')} for prefix in ('human','agent')}
schedule={prefix:{bound:scheduled(prefix,bound) for bound in ('min','max')} for prefix in ('human','agent')}
metadata={'planning_only':True,'task_count':len(tasks),'unique_ids':True,'dag_acyclic':True,
          'topological_order':order,'totals_alternative_active_hours':totals,
          'illustrative_fixed_lane_schedule':schedule,
          'schedule_limits':'Estimates, not measurements. Shared/joined steps reserve both lanes; elapsed model conservatively treats their effort as full-stage time. Dedicated test devices/fixtures and serialized shared-file reviews are required. Human and agent models are alternatives, not additive; human supervision and external/provider/review waits are not estimated by dividing these totals.'}
(root/'implementation-task-verification.json').write_text(json.dumps(metadata,indent=2)+'\n')

lines=['# Astir Events — implementation tasks','',
       '**Planning handoff only. No task is started or approved for production execution by this document.** Each task derives from the reviewed findings and approved journey. Open policies remain task dependencies; default UI/mechanics are documented separately.','',
       '## Effort interpretation','',
       f"Alternative active effort: **human-led {totals['human']['min']}–{totals['human']['max']} engineer-hours**, or **agent execution/iteration {totals['agent']['min']}–{totals['agent']['max']} hours**. These are rough bottom-up estimates, not additive totals, fixed AI compression ratios or calendar promises. The repo has no AI-compression table. Agent ranges include coding, tests and iteration; people still own product decisions, review, device/provider operations and release approval. External waits are excluded.",'',
       'The 22 items are work packages, not necessarily one PR each. Write tests with each feature, integrate small PRs, and use the joined test tasks for cross-system evidence rather than deferring tests until then. Shared integration/migration ownership stays serialized. Assignment of Joe/Ryan to A/B happens at kickoff without assuming specialties.','',
       '## Dependency and ownership table','',
       '| Task | Lane / stage | Modules touched | Depends on | Agent active hours |','| --- | --- | --- | --- | --- |']
for t in tasks:
    lines.append(f"| {t['id']} — {t['title']} | {t['lane']} / {t['stage']} | {', '.join('`'+m+'`' for m in t['modules'])} | {', '.join(t['depends_on']) or '—'} | {t['agent_hours_min']}–{t['agent_hours_max']} |")
lines += ['', '## Implementation Tasks','',
          'Synthesized from this review. Checkbox only when the stated exit criteria have actual evidence. Proposed repository paths may be refined within the approved module boundaries.','']
for t in tasks:
    lines += [f"- [ ] **{t['id']} ({t['priority']}, human: ~{t['human_hours_min']}–{t['human_hours_max']}h / agent: ~{t['agent_hours_min']}–{t['agent_hours_max']}h)** — {t['component']} — {t['title']}",
              f"  - Surfaced by: {t['source_finding']}",
              '  - Files: '+', '.join('`'+p+'`' for p in t['files']),
              f"  - Owner/dependencies: lane {t['lane']}; {', '.join(t['depends_on']) or 'no predecessor'}."]
    lines += ['  - Verify: '+v for v in t['verify']]
    lines += ['  - Exit: '+v for v in t['exit_criteria']]
    lines += ['  - Conditional: '+v for v in t['approval_dependencies']]
    if t.get('open_decision_groups'):
        lines += ['  - Open groups (affected clauses only): '+', '.join(t['open_decision_groups'])+'; see [decision inventory](engineering-open-decisions.md).']
    lines += ['']
lines += ['## Machine-readable handoff','',
          '[JSONL for gstack/autoplan](implementation-tasks.jsonl), [editable task source](implementation-tasks.source.json), and [DAG/estimate validation](implementation-task-verification.json). Dependency validation checks document consistency only; no implementation tests ran.','']
(root/'implementation-tasks.md').write_text('\n'.join(lines))
print(json.dumps({'tasks':len(tasks),'totals':totals,'fixed_lane_elapsed_active_hours':{p:{b:schedule[p][b]['elapsed_active_hours'] for b in ('min','max')} for p in ('human','agent')}},indent=2))
