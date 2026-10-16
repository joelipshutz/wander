#!/usr/bin/env python3
"""Read generated phlibwebp build metadata only; invokes no build/tool/process."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shlex

def sha(data):
    return hashlib.sha256(data).hexdigest()

def collect(derived):
    base = derived / 'Build/Intermediates.noindex'
    responses = list(base.glob('PostHog.build/Debug-iphonesimulator/phlibwebp.build/Objects-normal/arm64/*common-args.resp'))
    manifests = list(base.glob('XCBuildData/*.xcbuilddata/manifest.json'))
    assert len(responses) == len(manifests) == 1, 'Require one current Debug-arm64 response/manifest'
    response, manifest = responses[0], manifests[0]
    assert not response.is_symlink() and not manifest.is_symlink()
    assert 0 < response.stat().st_size <= 4 * 1024 * 1024
    assert 0 < manifest.stat().st_size <= 64 * 1024 * 1024
    response_bytes, manifest_bytes = response.read_bytes(), manifest.read_bytes()
    arguments = shlex.split(response_bytes.decode())
    document = json.loads(manifest_bytes)
    tasks = [task for name, task in document['commands'].items()
             if 'phlibwebp' in name and task.get('tool') == 'ccompile']
    assert tasks and all(str(response) in task['inputs'] for task in tasks), 'C tasks do not bind this response'
    c_files = sorted({Path(item).name for task in tasks for item in task['inputs']
                      if '/vendor/libwebp/' in item and item.endswith('.c')})
    assert len(c_files) == len(tasks)
    opt = [arg for arg in arguments if re.fullmatch(r'-O(?:[0-3szg]|fast)?', arg)]
    assert opt, 'No observed optimization argument'
    known = {'-fno-inline', '-finline-functions', '-fomit-frame-pointer', '-fno-omit-frame-pointer',
             '-fstrict-aliasing', '-fno-strict-aliasing', '-fvectorize', '-fno-vectorize',
             '-fslp-vectorize', '-fno-slp-vectorize', '-funroll-loops', '-fno-unroll-loops', '-flto', '-flto=thin'}
    result = {
        'state': 'generated-C-response-and-task-binding-recorded', 'target': 'phlibwebp',
        'configuration': 'Debug-iphonesimulator', 'architecture': 'arm64',
        'responseRelativePath': str(response.relative_to(derived)), 'responseSHA256': sha(response_bytes),
        'manifestRelativePath': str(manifest.relative_to(derived)), 'manifestSHA256': sha(manifest_bytes),
        'optimizationArgumentsInResponseOrder': opt,
        'otherKnownOptimizationArguments': [arg for arg in arguments if arg in known],
        'debugInfoArgumentPresent': '-g' in arguments,
        'DEBUGDefinePresent': any(arg in ['-DDEBUG', '-DDEBUG=1'] for arg in arguments),
        'NDEBUGDefinePresent': any(arg in ['-DNDEBUG', '-DNDEBUG=1'] for arg in arguments),
        'PLCR_PRIVATEDefinePresent': any(arg.startswith('-DPLCR_PRIVATE') for arg in arguments),
        'cCompileTasksBoundToResponse': len(tasks), 'cSourceBasenameInventorySHA256': sha(('\n'.join(c_files) + '\n').encode()),
        'completeCompilerCommandCaptured': False, 'optimizationChanged': False,
        'limits': ['These are actual generated response arguments bound as inputs to the saved C compilation tasks.',
                   'The manifest omits full compiler argument vectors; separate command-only overrides and per-task execution are not proved by this read.',
                   'No raw response/command/environment is copied into this receipt. No build or compiler process is invoked.'],
    }
    assert response.read_bytes() == response_bytes and manifest.read_bytes() == manifest_bytes
    return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--derived-data', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    assert not args.output.exists() and not args.output.is_symlink(), 'Preserve existing observation'
    result = collect(args.derived_data.resolve())
    with args.output.open('x') as stream:
        json.dump(result, stream, indent=2)
        stream.write('\n')
    print(json.dumps({'state': result['state'], 'CCompileTasks': result['cCompileTasksBoundToResponse'],
                      'optimizationArguments': result['optimizationArgumentsInResponseOrder']}))

if __name__ == '__main__':
    main()
