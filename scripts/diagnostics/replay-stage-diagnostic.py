#!/usr/bin/env python3
"""One diagnostic-only SDK stage probe; unchanged original private Replay test."""
import argparse
from contextlib import contextmanager
import copy
import hashlib
import json
import math
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[2]
SDK = 'ee5b5705b0038f0c44646cde5fe972bb65387596'
SWIFT_SHA = '80df366480648684a88923b4b2a954206507943465f3a0c02b52f1186be2afa4'
METHOD = 'WanderTests/ReplayMaskingTests/testPrivateMessageContentIsMaskedInActualReplayImage'
FILES = {
    'PostHog/Replay/PostHogReplayIntegration.swift': '5da5f38816fce2582bddc5cfef80f4ae7e6f51b55b48c268e60b03b69f517d2b',
    'PostHog/PostHogSDK.swift': 'ceeeaf0bf964cc3ca2ba7f6f99067eda375a6802c488d67f64164dce9a1f84b3',
}
FLAG = '-REC636ReplayStageProbe'


def need(value, message):
    if not value:
        raise ValueError(message)


def sha(value):
    return hashlib.sha256(value).hexdigest()


def save(path, value):
    with path.open('x') as f:
        json.dump(value, f, indent=2, sort_keys=True)
        f.write('\n')


def read_command(args, timeout=30):
    result = subprocess.run(args, capture_output=True, timeout=timeout, check=False)
    need(result.returncode == 0, 'read_command_failed:' + args[0])
    need(len(result.stdout) <= 8 * 1024 * 1024 and len(result.stderr) <= 1024 * 1024, 'read_output_bound')
    return result.stdout


def owned(path):
    root = Path(os.environ['RUNNER_TEMP']).resolve()
    value = path.resolve()
    need(os.environ.get('GITHUB_ACTIONS') == 'true' and value.is_relative_to(root), 'fresh_CI_scope_required')
    return value


def once(source, before, after):
    need(source.count(before) == 1, 'patch_anchor_not_unique')
    return source.replace(before, after, 1)


def patched_sources(sources, helper):
    need(set(sources) == set(FILES), 'SDK_file_roster')
    need(all(sha(sources[p]) == digest for p, digest in FILES.items()), 'SDK_source_hash_mismatch')
    replay = sources[next(iter(FILES))].decode()
    replay = once(replay, '                if let image = window.toImage(), image.size.hasSize() {',
        '                let image = window.toImage()\n'
        '                REC636ReplayStageProbe.record(1, frame: timestampDate, image: image)\n'
        '                if let image, image.size.hasSize() {')
    replay = once(replay, '            PostHogReplayIntegration.dispatchQueue.async {\n                // always make sure',
        '            PostHogReplayIntegration.dispatchQueue.async {\n'
        '                REC636ReplayStageProbe.record(2, frame: timestampDate)\n                // always make sure')
    replay = once(replay, '                let wireframeDict = autoreleasepool { wireframe.toDict() }',
        '                let wireframeDict = autoreleasepool { wireframe.toDict() }\n'
        '                REC636ReplayStageProbe.record(3, frame: timestampDate, image: wireframe.image)')
    replay += '\n' + helper
    sdk = sources['PostHog/PostHogSDK.swift'].decode()
    sdk = once(sdk, '        let resultEvent = config.runBeforeSend(event)',
        '        #if os(iOS)\n'
        '        if eventName == "$snapshot" { REC636ReplayStageProbe.record(4, frame: timestamp) }\n'
        '        #endif\n        let resultEvent = config.runBeforeSend(event)')
    sdk = once(sdk, '    @objc public func close() {\n',
        '    @objc public func close() {\n'
        '        #if os(iOS)\n        defer { REC636ReplayStageProbe.finish() }\n        #endif\n')
    return {list(FILES)[0]: replay.encode(), list(FILES)[1]: sdk.encode()}


def sdk_identity(sdk):
    need(read_command(['git', '-C', str(sdk), 'rev-parse', 'HEAD']).decode().strip() == SDK, 'SDK_revision_mismatch')


def admit_patch_paths(sdk, temporary):
    """Only the two files in this fresh CI checkout; no aliases or shared inodes."""
    expected = temporary / 'ReplayPackages/checkouts/posthog-ios'
    need(sdk == expected and sdk.is_absolute(), 'exact_disposable_checkout_required')
    for relative in FILES:
        target = sdk / relative
        for path in [temporary, *target.relative_to(temporary).parents]:
            # Relative parents are inspected below through the actual temporary root.
            if path == temporary: candidate = path
            elif str(path) == '.': continue
            else: candidate = temporary / path
            value = candidate.lstat()
            need(stat.S_ISDIR(value.st_mode) and value.st_uid == os.getuid(), 'checkout_directory_type_or_owner')
        value = target.lstat()
        need(stat.S_ISREG(value.st_mode) and value.st_uid == os.getuid() and value.st_nlink == 1,
             'SDK_source_type_owner_or_links')
    return [sdk / relative for relative in FILES]


def apply_source_patch(sdk, originals, changes, record):
    """Temporarily add only owner-write, then restore exact original modes."""
    need(set(originals) == set(changes) == set(FILES), 'SDK_patch_roster')
    opened = []
    record['sourceModes'] = {}
    try:
        # Admit both files and bytes before changing either mode or source.
        for relative in FILES:
            path = sdk / relative
            fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
            value = os.fstat(fd)
            opened.append((relative, fd, value))
            need(stat.S_ISREG(value.st_mode) and value.st_uid == os.getuid() and value.st_nlink == 1,
                 'SDK_opened_source_type_owner_or_links')
            need(os.read(fd, len(originals[relative]) + 1) == originals[relative], 'SDK_source_changed_before_patch')
            record['sourceModes'][relative] = {'before': stat.S_IMODE(value.st_mode), 'restored': False}
        for relative, fd, before in opened:
            original_mode = stat.S_IMODE(before.st_mode)
            if not original_mode & stat.S_IWUSR:
                os.fchmod(fd, original_mode | stat.S_IWUSR)
            writer = os.open(sdk / relative, os.O_WRONLY | os.O_NOFOLLOW)
            try:
                actual = os.fstat(writer)
                need((actual.st_dev, actual.st_ino, actual.st_uid) == (before.st_dev, before.st_ino, before.st_uid), 'SDK_source_identity_drift')
                os.ftruncate(writer, 0)
                remaining = memoryview(changes[relative])
                while remaining:
                    count = os.write(writer, remaining)
                    need(count > 0, 'SDK_source_short_write')
                    remaining = remaining[count:]
            finally:
                os.close(writer)
    finally:
        restoration_errors = []
        for relative, fd, before in reversed(opened):
            try:
                original_mode = stat.S_IMODE(before.st_mode)
                if stat.S_IMODE(os.fstat(fd).st_mode) != original_mode:
                    os.fchmod(fd, original_mode)
                matched = stat.S_IMODE(os.fstat(fd).st_mode) == original_mode
                if relative in record['sourceModes']:
                    record['sourceModes'][relative].update(after=stat.S_IMODE(os.fstat(fd).st_mode), restored=matched)
                if not matched: restoration_errors.append(relative)
            except OSError:
                restoration_errors.append(relative)
            finally:
                os.close(fd)
        record['modeRestorationFailed'] = restoration_errors
        # Preserve an original patch error; restoration failure remains separately visible.
        if restoration_errors and sys.exc_info()[0] is None:
            raise ValueError('SDK_mode_restoration_failed')


def patch(args):
    sdk = owned(args.sdk); receipt = owned(args.receipt)
    need(sdk.name == 'posthog-ios' and not receipt.exists(), 'disposable_checkout_or_new_receipt_required')
    need(args.sdk.absolute() == sdk, 'SDK_checkout_alias')
    admit_patch_paths(sdk, Path(os.environ['RUNNER_TEMP']).resolve())
    sdk_identity(sdk)
    need(not read_command(['git', '-C', str(sdk), 'status', '--porcelain']), 'SDK_not_clean')
    originals = {p: (sdk / p).read_bytes() for p in FILES}
    helper = (Path(__file__).with_name('ReplayStageProbe.swift')).read_text()
    changes = patched_sources(originals, helper)
    record = {'sdkRevision': SDK, 'before': FILES, 'helperSHA256': sha(helper.encode()),
              'diagnosticOnly': True, 'dependencyPinChanged': False, 'status': 'Prepared'}
    try:
        apply_source_patch(sdk, originals, changes, record)
        need(all((sdk/p).read_bytes() == data for p,data in changes.items()), 'patched_source_bytes_mismatch')
        record.update(status='Applied', after={p: sha(data) for p, data in changes.items()})
    except BaseException as error:
        record.update(status='Failed', errorType=type(error).__name__)
        raise
    finally:
        save(receipt, record)


def targets(document):
    configs = document.get('TestConfigurations')
    rows = ([t for c in configs for t in c['TestTargets']] if configs is not None else
            [t for n, t in document.items() if not n.startswith('__') and isinstance(t, dict)])
    return [t for t in rows if t.get('BlueprintName') == 'WanderTests' and not t.get('IsUITestBundle', False)]


@contextmanager
def diagnostic_argument(products, nonce, receipt):
    need(str(uuid.UUID(nonce)).upper() == nonce, 'nonce_invalid')
    need(not products.is_symlink(), 'products_symlink')
    products = products.resolve()
    originals, documents, hosts = {}, {}, []
    for entry in plistlib.loads((products / 'Info.plist').read_bytes())['Tests']:
        candidate = products / entry['xctestrun']; path = candidate.resolve()
        need(not candidate.is_symlink() and path.is_relative_to(products), 'configuration_path')
        if path in documents: continue
        originals[path] = path.read_bytes(); documents[path] = plistlib.loads(originals[path])
        hosts.extend((path, t) for t in targets(documents[path]))
    need(len(hosts) == 1, 'exactly_one_test_host_required')
    path, target = hosts[0]; before = copy.deepcopy(documents)
    previous = target.get('CommandLineArguments', []); had_key = 'CommandLineArguments' in target
    need(isinstance(previous, list) and all(isinstance(x, str) for x in previous)
         and not any(x == FLAG or x.startswith(FLAG + '=') for x in previous), 'conflicting_argument')
    target['CommandLineArguments'] = [*previous, FLAG, nonce]
    restored = copy.deepcopy(documents); row = targets(restored[path])[0]
    if had_key: row['CommandLineArguments'] = previous
    else: row.pop('CommandLineArguments')
    need(restored == before, 'unrelated_configuration_change')
    try:
        for p, doc in documents.items(): p.write_bytes(plistlib.dumps(doc))
        yield
        need(all(plistlib.loads(p.read_bytes()) == doc for p, doc in documents.items()), 'configuration_drift')
    finally:
        for p, data in originals.items(): p.write_bytes(data)
        matched = all(p.read_bytes() == data for p, data in originals.items())
        save(receipt, {'restored': matched, 'otherValuesUnchanged': True,
            'beforeSHA256': {str(p.relative_to(products)): sha(data) for p, data in originals.items()}})
        need(matched, 'configuration_restore_failed')


def native_accounting(summary, tests, code, device):
    need(code in (0, 65), 'native_infrastructure_failure')
    status = 'Passed' if code == 0 else 'Failed'
    counts = {'totalTestCount': 1, 'passedTests': int(code == 0), 'failedTests': int(code == 65),
              'skippedTests': 0, 'expectedFailures': 0}
    need(summary.get('result') == status and all(type(summary.get(k)) is int and summary[k] == v for k, v in counts.items()), 'native_counts')
    configs = summary.get('devicesAndConfigurations', [])
    need(len(configs) == 1 and configs[0].get('device', {}).get('deviceId', '').upper() == device.upper(), 'native_device')
    need(all(configs[0].get(k) == v for k, v in counts.items() if k != 'totalTestCount'), 'native_device_counts')
    cases = []
    def walk(node):
        if isinstance(node, dict):
            if node.get('nodeType') == 'Test Case': cases.append(node)
            for child in node.values(): walk(child)
        elif isinstance(node, list):
            for child in node: walk(child)
    walk(tests)
    need(len(cases) == 1 and cases[0].get('nodeIdentifierURL') == 'test://com.apple.xcode/Wander/' + METHOD
         and cases[0].get('result') == status, 'native_method')
    return {'method': METHOD, 'result': status, **counts, 'acceptanceClaimed': False}


def stage_records(directory):
    need(directory.is_dir() and not directory.is_symlink(), 'stage_directory_missing')
    paths = sorted(directory.iterdir())
    need(len(paths) <= 129 and all(p.is_file() and not p.is_symlink() and p.stat().st_size <= 512 for p in paths), 'stage_file_bound')
    footer_path = directory / 'footer.json'
    footer = json.loads(footer_path.read_bytes()) if footer_path.exists() else None
    if footer is not None:
        need(set(footer) == {'attempted', 'written', 'failed', 'capped', 'closed', 'pid', 'uptime'}
             and footer['closed'] is True
             and all(type(footer[k]) is int and footer[k] >= 0 for k in ('attempted','written','failed','capped','pid'))
             and type(footer['uptime']) in (int,float) and math.isfinite(footer['uptime']), 'recorder_footer')
    rows = []
    for path in paths:
        if path.name == 'footer.json': continue
        need(re.fullmatch(r'\d{3}\.json', path.name), 'unexpected_stage_file')
        row = json.loads(path.read_bytes())
        need(set(row) == {'stage', 'sequence', 'frame', 'uptime', 'epoch', 'pid', 'image', 'width', 'height'}, 'stage_schema')
        need(type(row['image']) is bool and all(type(row[k]) is int for k in ['stage','sequence','frame','pid','width','height'])
             and row['stage'] in (1,2,3,4) and 1 <= row['sequence'] <= 128
             and int(path.stem) == row['sequence']
             and (not rows or row['sequence'] > rows[-1]['sequence'])
             and (footer is None or row['pid'] == footer['pid']) and 1 < row['pid'] < 2**31
             and 0 <= row['frame'] < 2**64 and 0 <= row['width'] <= 20000 and 0 <= row['height'] <= 20000
             and all(type(row[k]) in (int,float) and math.isfinite(row[k]) and row[k] > 0 for k in ['uptime','epoch']), 'stage_values')
        rows.append(row)
    observed = {row['sequence'] for row in rows}
    expected_end = min(footer['attempted'] if footer else max(observed, default=0), 128)
    missing = sorted(set(range(1, expected_end + 1)) - observed)
    contiguous = [row['sequence'] for row in rows] == list(range(1, len(rows) + 1))
    complete = bool(rows and footer and contiguous and not missing
                    and footer['attempted'] == footer['written'] == len(rows)
                    and footer['failed'] == footer['capped'] == 0)
    return {'rows': rows, 'footer': footer, 'missingSequences': missing,
        'recorderComplete': complete, 'acceptanceClaimed': False,
        'stageLegend': {'1':'image returned', '2':'serial block entered', '3':'toDict returned', '4':'beforeSend reached'},
        'limitations': ['image-to-queue interval includes synchronous enqueue preparation',
                        'queue-to-toDict interval includes session lookup and possible early return',
                        'diagnostic IO overhead; no performance or unmodified-product acceptance']}


def app_hashes(app):
    return {name: sha((app / name).read_bytes()) for name in ('Wander', 'Wander.debug.dylib', 'Info.plist')}


def run(args):
    products, result, output, sdk, receipt = [owned(p) for p in (args.products,args.result,args.output,args.sdk,args.receipt)]
    need(not output.exists() and not result.exists(), 'preserve_previous_attempt')
    need(str(uuid.UUID(args.device)).upper() == args.device.upper(), 'device_uuid')
    need(read_command(['git','rev-parse','HEAD']).decode().strip() == os.environ['GITHUB_SHA'], 'candidate_head')
    need(sha((ROOT/'WanderTests/ReplayMaskingTests.swift').read_bytes()) == SWIFT_SHA, 'original_test_changed')
    patch_receipt = json.loads(receipt.read_text()); sdk_identity(sdk)
    need(patch_receipt['sdkRevision'] == SDK and patch_receipt['before'] == FILES
         and set(patch_receipt['after']) == set(FILES), 'patch_receipt_identity')
    need(all(sha((sdk/p).read_bytes()) == h for p,h in patch_receipt['after'].items()), 'patched_SDK_drift')
    changed = read_command(['git','-C',str(sdk),'diff','--name-only']).decode().splitlines()
    need(set(changed) == set(FILES), 'unexpected_SDK_source_changes')
    output.mkdir(parents=True)
    nonce = str(uuid.uuid4()).upper()
    app = products/'Binaries/0/Debug-iphonesimulator/Wander.app'; hashes = app_hashes(app)
    save(output/'admission.json', {'head':os.environ['GITHUB_SHA'], 'originalReplaySHA256':SWIFT_SHA,
        'sdkPatchReceiptSHA256':sha(receipt.read_bytes()), 'nonce':nonce, 'device':args.device,
        'productHashes':hashes, 'diagnosticOnly':True, 'acceptanceClaimed':False})
    with diagnostic_argument(products, nonce, output/'configuration-restoration.json'):
        native = subprocess.run([sys.executable,'-B','scripts/run-parent-regression.py','--suite','replay-private',
            '--test-products',str(products),'--destination',args.device,'--result-bundle',str(result),
            '--selection-file',str(output/'selection.json'),'--replay-fixture-host','inert',
            '--replay-host-receipt',str(output/'host-admission.json')], cwd=ROOT, check=False).returncode
    for name in ('summary','tests'):
        save(output/(name+'.json'), json.loads(read_command(['xcrun','xcresulttool','get','test-results',name,'--path',str(result),'--compact'],120)))
    save(output/'native-accounting.json',native_accounting(json.loads((output/'summary.json').read_text()),json.loads((output/'tests.json').read_text()),native,args.device))
    # One post-native lookup per exact bundle kind; no live polling, retries, sampler or process signals.
    try:
        need(all(sha((sdk/p).read_bytes()) == h for p,h in patch_receipt['after'].items()), 'postnative_SDK_drift')
        data = Path(read_command(['xcrun','simctl','get_app_container',args.device,'com.grayline.wander','data'],30).decode().strip()).resolve()
        installed = Path(read_command(['xcrun','simctl','get_app_container',args.device,'com.grayline.wander','app'],30).decode().strip()).resolve()
        need(app_hashes(app) == app_hashes(installed) == hashes, 'postnative_product_mismatch')
        directory = data/'tmp'/('REC636-ReplayStage-'+nonce)
        need(directory.resolve().parent == (data/'tmp').resolve(), 'stage_path_escape')
        records = stage_records(directory)
        save(output/'stages.json', records)
        save(output/'diagnostic-summary.json',{'nativeExitCode':native,'stageCount':len(records['rows']),
            'productVerified':True,'recorderComplete':records['recorderComplete'],
            'diagnosticOnly':True,'acceptanceClaimed':False})
        return native or (0 if records['recorderComplete'] else 2)
    except Exception as error:
        save(output/'diagnostic-gap.json',{'nativeExitCode':native,'category':type(error).__name__,
            'reason':str(error) if isinstance(error,ValueError) else 'post_native_read_failed',
            'acceptanceClaimed':False})
        return native or 2


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest='command',required=True)
    for action in ('patch','run'):
        sub = commands.add_parser(action)
        sub.add_argument('--sdk',type=Path,required=True); sub.add_argument('--receipt',type=Path,required=True)
        if action == 'run':
            for name in ('products','result','output'): sub.add_argument('--'+name,type=Path,required=True)
            sub.add_argument('--device',required=True)
    args = parser.parse_args()
    sys.exit(patch(args) if args.command == 'patch' else run(args))
