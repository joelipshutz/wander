#!/usr/bin/env python3
"""One unchanged private Replay test, with a bounded first-draw stack sample."""
from pathlib import Path
from contextlib import contextmanager
import argparse, copy, hashlib, json, math, os, plistlib, re, runpy, signal
import subprocess, sys, tempfile, threading, time, uuid

ROOT = Path(__file__).resolve().parents[2]
SUPPORT = runpy.run_path(str(Path(__file__).with_name('replay-diagnostic-support.py')))
need, bounded_bytes, curate = (SUPPORT[k] for k in ('need', 'bounded_bytes', 'curate'))
FLAG = '-REC636ReplayDiagnosticDirectory'
METHOD = 'WanderTests/ReplayMaskingTests/testPrivateMessageContentIsMaskedInActualReplayImage'
BUNDLE = 'com.grayline.wander'
SDK = 'ee5b5705b0038f0c44646cde5fe972bb65387596'
PHASES = ('ready-began', 'first-ready-draw', 'first-snapshot', 'ready-ended')
MARKER_PREFIX = 'REC636-ReplayDiagnostic-'
BIND_TOTAL_SECONDS = 120
LOOKUP_MAX_SECONDS = 10
LOOKUP_CLEANUP_SECONDS = 15  # stop_owned: at most 10s TERM grace plus 5s reap.
UNBOUND_POLL_SECONDS = 1


def marker_basename(nonce):
    need(isinstance(nonce, str) and str(uuid.UUID(nonce)).upper() == nonce, 'marker_nonce')
    return MARKER_PREFIX + nonce


def marker_directory(container, nonce):
    temporary = (container / 'tmp').resolve()
    need(temporary.parent == container and temporary.is_dir(), 'app_tmp_scope')
    directory = temporary / marker_basename(nonce)
    need(not directory.is_symlink(), 'marker_directory_symlink')
    return directory


def current_container(device, kind, output, name, timeout=2):
    need(kind in ('data', 'app'), 'container_kind')
    path = Path(checked(['xcrun', 'simctl', 'get_app_container', device, BUNDLE, kind],
                        output, name, timeout=timeout).decode().strip()).resolve()
    root = (Path.home() / 'Library/Developer/CoreSimulator/Devices' / device / 'data/Containers').resolve()
    scope = root / ('Data/Application' if kind == 'data' else 'Bundle/Application')
    need(path.is_relative_to(scope) and (kind != 'app' or path.name == 'Wander.app'), 'app_container_scope')
    return path


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def save(path, value):
    with Path(path).open('x') as stream:
        json.dump(value, stream, indent=2, sort_keys=True); stream.write('\n')


def stop_owned(proc):
    """Only the process group created by this wrapper; never the sampled app."""
    def alive():
        proc.poll()
        try: os.killpg(proc.pid, 0); return True
        except ProcessLookupError: return False
    if alive():
        os.killpg(proc.pid, signal.SIGTERM)
        deadline = time.monotonic() + 10
        while alive() and time.monotonic() < deadline: time.sleep(.05)
        if alive(): os.killpg(proc.pid, signal.SIGKILL)
    proc.wait(timeout=5)
    need(not alive(), 'owned_process_cleanup_unconfirmed')


def command(argv, output, name, timeout=120, collect=True):
    """Retain scalar process facts; never raw stdout/stderr or command arguments."""
    proc = subprocess.Popen(argv, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            start_new_session=True)
    started = time.monotonic(); complete = False
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
        need(len(stdout) + len(stderr) <= 64 * 1024 * 1024, 'process_output_bound')
        denied = any(x in (stdout + stderr).lower() for x in
                     (b'permission denied', b'operation not permitted', b'not permitted to sample'))
        save(output / (name + '-process.json'), {
            'exitCode': proc.returncode, 'elapsedSeconds': time.monotonic() - started,
            'stdoutBytes': len(stdout), 'stderrBytes': len(stderr),
            'stdoutSHA256': hashlib.sha256(stdout).hexdigest(),
            'stderrSHA256': hashlib.sha256(stderr).hexdigest(), 'rawOutputSaved': False,
            'permissionDenied': denied})
        if denied: raise PermissionError('process_permission_denied')
        complete = True
        return proc.returncode, stdout if collect else b''
    finally:
        if not complete and proc.poll() is None: stop_owned(proc)


def checked(argv, output, name, timeout=120):
    code, data = command(argv, output, name, timeout)
    need(code == 0, name + '_failed')
    return data


def host_target(document):
    configs = document.get('TestConfigurations')
    rows = ([t for c in configs for t in c['TestTargets']] if configs is not None else
            [t for n, t in document.items() if not n.startswith('__') and isinstance(t, dict)])
    return [t for t in rows if t.get('BlueprintName') == 'WanderTests' and not t.get('IsUITestBundle', False)]


@contextmanager
def diagnostic_arguments(products, name, receipt):
    """Runtime tmp basename; the existing inner helper admits inert mode unchanged."""
    need(isinstance(name, str) and name.startswith(MARKER_PREFIX)
         and name == marker_basename(name[len(MARKER_PREFIX):]), 'marker_basename_required')
    products = products.resolve()
    info = plistlib.loads((products / 'Info.plist').read_bytes())
    originals, docs, targets = {}, {}, []
    for entry in info['Tests']:
        candidate = products / entry['xctestrun']; path = candidate.resolve()
        need(not candidate.is_symlink() and path.is_relative_to(products), 'configuration_path')
        if path in docs: continue
        originals[path] = path.read_bytes(); docs[path] = plistlib.loads(originals[path])
        targets.extend((path, t) for t in host_target(docs[path]))
    need(len(targets) == 1, 'one_unit_host_required')
    path, target = targets[0]; before = copy.deepcopy(docs)
    old_args = target.get('CommandLineArguments', []); had_key = 'CommandLineArguments' in target
    need(isinstance(old_args, list) and all(isinstance(x, str) for x in old_args), 'host_arguments')
    need(not any(x == FLAG or x.startswith(FLAG + '=') for x in old_args), 'duplicate_diagnostic_argument')
    target['CommandLineArguments'] = [*old_args, FLAG, name]
    effective = copy.deepcopy(docs); restored = copy.deepcopy(effective)
    row = host_target(restored[path])[0]
    if had_key: row['CommandLineArguments'] = old_args
    else: row.pop('CommandLineArguments', None)
    need(restored == before, 'unrelated_configuration_change')
    record = {'allOtherValuesUnchanged': True, 'restored': False,
              'beforeSHA256': {str(p.relative_to(products)): hashlib.sha256(b).hexdigest() for p, b in originals.items()}}
    try:
        for p, doc in effective.items(): p.write_bytes(plistlib.dumps(doc))
        need(all(plistlib.loads(p.read_bytes()) == doc for p, doc in effective.items()), 'configuration_write')
        yield
        need(all(plistlib.loads(p.read_bytes()) == doc for p, doc in effective.items()), 'configuration_native_drift')
    finally:
        for p, data in originals.items(): p.write_bytes(data)
        record['restored'] = all(p.read_bytes() == b for p, b in originals.items())
        save(receipt, record)
        need(record['restored'], 'configuration_restore_failed')


def read_marker(directory, phase, nonce, earliest):
    path = directory / (phase + '.json')
    if not path.exists(): return None
    value = json.loads(bounded_bytes(path, 512))
    need(set(value) == {'schema', 'phase', 'nonce', 'pid', 'systemUptime', 'epoch'}, 'marker_schema')
    need(type(value['schema']) is int and value['schema'] == 1 and value['phase'] == phase
         and value['nonce'] == nonce and type(value['pid']) is int and 1 < value['pid'] < 2**31, 'marker_identity')
    need(all(type(value[k]) in (int, float) and math.isfinite(value[k]) and value[k] > 0
             for k in ('systemUptime', 'epoch')), 'marker_clock')
    need(earliest - 2 <= value['epoch'] <= time.time() + .25
         and value['systemUptime'] <= time.monotonic() + .25, 'stale_or_future_marker')
    need(abs((time.time() - value['epoch']) - (time.monotonic() - value['systemUptime'])) <= 2,
         'marker_clock_domain')
    return value


def process_identity(pid, installed_app, earliest, marker_epoch):
    ctypes, errno, BsdInfo = (SUPPORT[k] for k in ('ctypes', 'errno', 'BsdInfo'))
    lib = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
    lib.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    lib.proc_pidpath.restype = ctypes.c_int
    lib.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_int]
    lib.proc_pidinfo.restype = ctypes.c_int
    buf = ctypes.create_string_buffer(4096)
    count = lib.proc_pidpath(pid, buf, len(buf))
    if count <= 0 and ctypes.get_errno() in (errno.EACCES, errno.EPERM): raise PermissionError('pid_path_denied')
    need(count > 0 and Path(buf.value.decode()).resolve() == installed_app / 'Wander', 'pid_path_mismatch')
    info = BsdInfo(); count = lib.proc_pidinfo(pid, 3, 0, ctypes.byref(info), ctypes.sizeof(info))
    if count <= 0 and ctypes.get_errno() in (errno.EACCES, errno.EPERM): raise PermissionError('pid_info_denied')
    need(count == ctypes.sizeof(info) and info.pid == pid and info.uid == os.getuid()
         and info.ruid == os.getuid(), 'pid_uid_mismatch')
    started = info.start_sec + info.start_usec / 1e6
    need(earliest - 2 <= started <= marker_epoch, 'pid_start_mismatch')
    return hashlib.sha256(f'{pid}:{info.uid}:{info.start_sec}:{info.start_usec}'.encode()).hexdigest()


class Observer:
    def __init__(self, output, device, nonce):
        self.output, self.device, self.nonce = output, device, nonce
        self.directory, self.installed_app = None, None
        self.earliest = time.time(); self.stop = threading.Event(); self.thread = None
        self.report = {'status': 'Pending', 'sampleAttempts': 0, 'acceptanceClaimed': False}

    def lookup(self, kind, attempt, timeout):
        return current_container(self.device, kind, self.output, f'rebind-{kind}-{attempt:03d}', timeout=timeout)

    def bind(self):
        """Only successful unchanged state is polled; failed lookups stop sampling."""
        started = time.monotonic(); deadline = started + BIND_TOTAL_SECONDS
        self.report['bindingPolicy'] = {'totalSeconds': BIND_TOTAL_SECONDS, 'lookupMaximumSeconds': LOOKUP_MAX_SECONDS,
            'cleanupReserveSeconds': LOOKUP_CLEANUP_SECONDS, 'successfulUnboundPollSeconds': UNBOUND_POLL_SECONDS}
        def lookup(kind, attempt):
            # A single synchronous call owns its process through completion or cleanup.
            # Do not start another call when its cleanup cannot fit in the admission budget.
            timeout = min(LOOKUP_MAX_SECONDS, deadline - time.monotonic() - LOOKUP_CLEANUP_SECONDS)
            need(not self.stop.is_set() and timeout > 0, 'native_ended_or_rebind_deadline')
            if kind == 'data': self.report['dataContainerQueries'] = attempt
            return self.lookup(kind, attempt, timeout=timeout)
        for attempt in range(1, 121):
            container = lookup('data', attempt)
            directory = marker_directory(container, self.nonce)
            if directory.is_dir():
                installed = lookup('app', attempt)
                self.directory, self.installed_app = directory, installed
                self.report['binding'] = {'beganUptime': started, 'endedUptime': time.monotonic(),
                    'dataPathSHA256': hashlib.sha256(str(container).encode()).hexdigest(),
                    'appPathSHA256': hashlib.sha256(str(installed).encode()).hexdigest()}
                return
            remaining = deadline - time.monotonic() - LOOKUP_CLEANUP_SECONDS
            need(remaining > 0, 'native_ended_or_rebind_deadline')
            self.stop.wait(min(UNBOUND_POLL_SECONDS, remaining))
        raise SUPPORT['Gap']('marker_container_not_bound')

    def markers(self):
        if self.directory is None: return dict.fromkeys(PHASES)
        rows = {p: read_marker(self.directory, p, self.nonce, self.earliest) for p in PHASES}
        present = [x for x in rows.values() if x is not None]
        need(len({x['pid'] for x in present}) <= 1, 'marker_pid_mismatch')
        return rows

    def start(self):
        self.thread = threading.Thread(target=self.watch, daemon=True); self.thread.start()

    def watch(self):
        try:
            self.bind()
            deadline = time.monotonic() + 120
            while time.monotonic() < deadline:
                need(not self.stop.is_set(), 'native_ended_before_trigger')
                marks = self.markers()
                need(marks['first-snapshot'] is None and marks['ready-ended'] is None, 'capture_completed_before_sample')
                if marks['ready-began'] and marks['first-ready-draw']: break
                self.stop.wait(.05)
            else: raise RuntimeError('first_draw_marker_timeout')
            begin, draw = marks['ready-began'], marks['first-ready-draw']
            need(begin['systemUptime'] <= draw['systemUptime'] and
                 time.monotonic() <= draw['systemUptime'] + 2, 'sample_trigger_late')
            before = process_identity(draw['pid'], self.installed_app, self.earliest, draw['epoch'])
            marks = self.markers()
            need(marks['first-snapshot'] is None and marks['ready-ended'] is None, 'capture_completed_before_sample')
            with tempfile.TemporaryDirectory(prefix='rec636-replay-sample-') as tmp:
                scratch = Path(tmp) / 'sample.txt'
                started = time.monotonic(); self.report['sampleAttempts'] = 1
                proc = subprocess.Popen(['/usr/bin/sample', str(draw['pid']), '2', '10', '-mayDie', '-file', str(scratch)],
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
                interruption = None
                try:
                    while proc.poll() is None:
                        marks = self.markers()
                        if marks['first-snapshot'] or marks['ready-ended'] or self.stop.is_set():
                            interruption = 'capture_or_native_ended_during_sample'; break
                        if time.monotonic() - started > 15:
                            interruption = 'sample_watchdog'; break
                        if scratch.exists(): need(scratch.stat().st_size <= SUPPORT['MAX_PROFILE'], 'profile_size')
                        self.stop.wait(.05)
                    if interruption: stop_owned(proc)
                    stdout, stderr = proc.communicate(timeout=2)
                    need(len(stdout) + len(stderr) <= 1024 * 1024, 'sample_output_bound')
                    denied = any(x in (stdout + stderr).lower() for x in
                                 (b'permission denied', b'operation not permitted', b'cannot examine process'))
                    if denied: raise PermissionError('sample_permission_denied')
                    ended = time.monotonic()
                    self.report['sample'] = {'startUptime': started, 'endUptime': ended, 'requestedSeconds': 2,
                        'intervalMilliseconds': 10, 'exitCode': proc.returncode, 'interruption': interruption}
                    need(scratch.is_file(), 'sample_profile_missing')
                    profile = curate(bounded_bytes(scratch, SUPPORT['MAX_PROFILE']))
                    save(self.output / 'static-profile.json', profile)
                    self.report['profileSHA256'] = sha(self.output / 'static-profile.json')
                    need(profile['retainedStaticRows'] > 0, 'no_static_stack_rows')
                    after = process_identity(draw['pid'], self.installed_app, self.earliest, draw['epoch'])
                    need(before == after, 'pid_identity_changed')
                    self.report['pidIdentitySHA256'] = before
                    need(not interruption and proc.returncode == 0, 'sample_partial_or_failed')
                finally:
                    if proc.poll() is None: stop_owned(proc)
                    proc.stdout.close(); proc.stderr.close()
            self.report['status'] = 'SampledAwaitingGateEnd'
        except BaseException as error:
            self.report.update(status='Gap', category=type(error).__name__,
                reason=str(error) if isinstance(error, (SUPPORT['Gap'], PermissionError)) else type(error).__name__,
                permissionDenied=isinstance(error, PermissionError))

    def finish(self):
        self.stop.set(); self.thread.join(30)
        need(not self.thread.is_alive(), 'sampler_thread_cleanup_unconfirmed')
        try:
            marks = self.markers(); self.report['markers'] = marks
            sample = self.report.get('sample'); begin, draw = marks['ready-began'], marks['first-ready-draw']
            ends = [m['systemUptime'] for m in (marks['first-snapshot'], marks['ready-ended']) if m]
            valid = bool(sample and begin and draw and ends and
                         begin['systemUptime'] <= draw['systemUptime'] <= sample['startUptime'] <= sample['endUptime'] <= min(ends))
            self.report['intervalVerifiedBeforeFirstSnapshotAndGateEnd'] = valid
            if self.report['status'] == 'SampledAwaitingGateEnd':
                self.report['status'] = 'SampledPendingProductVerification' if valid else 'Gap'
        except (OSError, ValueError, SUPPORT['Gap']) as error:
            self.report.update(status='Gap', category=type(error).__name__,
                reason=str(error) if isinstance(error, SUPPORT['Gap']) else type(error).__name__)
        save(self.output / 'sample-observation.json', self.report)
        return self.report


def app_hashes(app):
    names = ('Wander', 'Wander.debug.dylib', 'Info.plist')
    need(all((app / n).is_file() and not (app / n).is_symlink() for n in names), 'app_product_missing')
    return {n: sha(app / n) for n in names}


def verify_profile_product(observer, profile, app, hashes):
    """A failed/denied binding is not retried after native completes."""
    if profile.get('permissionDenied') or observer.directory is None or observer.installed_app is None:
        return None, {'verificationPerformed': False, 'hashesMatchSealedProduct': False,
                      'sampleBindingStillCurrent': False, 'acceptanceClaimed': False}
    current_data = current_container(observer.device, 'data', observer.output, 'post-native-data')
    current_app = current_container(observer.device, 'app', observer.output, 'post-native-app')
    directory = marker_directory(current_data, observer.nonce)
    return directory, {'verificationPerformed': True,
        'hashesMatchSealedProduct': app_hashes(current_app) == hashes and app_hashes(app) == hashes,
        'sampleBindingStillCurrent': directory == observer.directory and current_app == observer.installed_app,
        'hashingPerformedAfterNative': True,
        'dataPathSHA256': hashlib.sha256(str(current_data).encode()).hexdigest(),
        'appPathSHA256': hashlib.sha256(str(current_app).encode()).hexdigest(), 'acceptanceClaimed': False}


def native_accounting(summary, tests, native, device):
    """A diagnostic profile cannot substitute for the exact original test result."""
    need(native in (0, 65), 'native_infrastructure_failure')
    expected = 'Passed' if native == 0 else 'Failed'
    counts = {'totalTestCount': 1, 'passedTests': int(native == 0),
              'failedTests': int(native == 65), 'skippedTests': 0, 'expectedFailures': 0}
    need(all(type(summary.get(k)) is int and summary[k] == v for k, v in counts.items())
         and summary.get('result') == expected, 'native_summary_count_mismatch')
    rows = summary.get('devicesAndConfigurations', [])
    need(len(rows) == 1 and rows[0].get('device', {}).get('deviceId', '').upper() == device.upper(),
         'native_device_mismatch')
    need(all(type(rows[0].get(k)) is int and rows[0][k] == v for k, v in counts.items() if k != 'totalTestCount'),
         'native_device_count_mismatch')
    cases = []
    def walk(value):
        if isinstance(value, dict):
            if value.get('nodeType') == 'Test Case': cases.append(value)
            for child in value.values(): walk(child)
        elif isinstance(value, list):
            for child in value: walk(child)
    walk(tests)
    need(len(cases) == 1 and cases[0].get('nodeIdentifierURL') == 'test://com.apple.xcode/Wander/' + METHOD
         and cases[0].get('result') == expected, 'native_case_mismatch')
    return {'exactMethod': METHOD, 'device': device, 'nativeExitCode': native,
            'nativeResult': expected, **counts, 'acceptanceClaimed': False}


def main(args):
    products = args.products.resolve(); output = args.output.absolute(); result = args.result.absolute()
    need(os.environ.get('GITHUB_ACTIONS') == 'true', 'CI_owned_simulator_required')
    owned = Path(os.environ['RUNNER_TEMP']).resolve()
    need(all(p.resolve().is_relative_to(owned) for p in (products, output, result)), 'CI_owned_output_required')
    need(not output.exists() and not output.is_symlink() and not result.exists(), 'preserve_previous_attempt')
    need(not args.products.is_symlink() and products.is_dir(), 'products_missing')
    need(str(uuid.UUID(args.device)).upper() == args.device.upper(), 'device_uuid')
    output.mkdir(parents=True)
    head = checked(['git', 'rev-parse', 'HEAD'], output, 'head').decode().strip()
    need(head == args.expected_head, 'head_changed')
    paths = ['WanderTests/ReplayMaskingTests.swift', 'Wander/App/WanderApp.swift', 'scripts/diagnostics', 'scripts/run-parent-regression.py']
    need(not checked(['git', 'status', '--porcelain', '--', *paths], output, 'source-status'), 'source_dirty')
    sdk = args.sdk_checkout.resolve()
    need(args.expected_sdk == SDK and checked(['git', '-C', str(sdk), 'rev-parse', 'HEAD'], output, 'sdk-head').decode().strip() == SDK, 'sdk_revision')
    need(not checked(['git', '-C', str(sdk), 'status', '--porcelain'], output, 'sdk-status'), 'sdk_dirty')
    app = products / 'Binaries/0/Debug-iphonesimulator/Wander.app'; hashes = app_hashes(app)
    listing = checked(['xcrun', 'simctl', 'listapps', args.device], output, 'owned-device-apps')
    # simctl supplies an Apple plist, including OpenStep on some Xcode releases.
    try: apps = plistlib.loads(listing)
    except plistlib.InvalidFileException:
        converted = subprocess.run(['plutil', '-convert', 'json', '-o', '-', '-'], input=listing, capture_output=True, check=True)
        apps = json.loads(converted.stdout)
    existing = apps.get(BUNDLE)
    if existing:
        from urllib.parse import urlparse, unquote
        path = existing.get('Path') or unquote(urlparse(existing['Bundle']).path)
        need(app_hashes(Path(path).resolve()) == hashes, 'existing_app_not_current_owned_product')
    checked(['xcrun', 'simctl', 'install', args.device, str(app)], output, 'preinstall')
    installed = current_container(args.device, 'app', output, 'installed-app', timeout=120)
    need(app_hashes(installed) == hashes, 'installed_app_mismatch')
    nonce = str(uuid.uuid4()).upper()
    save(output / 'admission.json', {'head': head, 'sdkHead': SDK, 'sdkClean': True, 'nonce': nonce,
        'device': args.device, 'appPresentBefore': bool(existing), 'installedAppHashes': hashes,
        'markerLocation': 'runtime-app-tmp-basename', 'method': METHOD, 'diagnosticOnly': True,
        'sourceHashes': {p: sha(ROOT / p) for p in paths if (ROOT / p).is_file()}, 'acceptanceClaimed': False})
    observer = Observer(output, args.device, nonce); native = None; profile = None
    directory = None
    try:
        with diagnostic_arguments(products, marker_basename(nonce), output / 'configuration-restoration.json'):
            observer.start()
            try:
                native, _ = command([sys.executable, '-B', 'scripts/run-parent-regression.py', '--suite', 'replay-private',
                    '--test-products', str(products), '--destination', args.device, '--result-bundle', str(result),
                    '--selection-file', str(output / 'selection.json'), '--replay-fixture-host', 'inert',
                    '--replay-host-receipt', str(output / 'host-admission.json')], output, 'native', timeout=1500, collect=False)
            finally: profile = observer.finish()
        need(native in (0, 65), 'native_infrastructure_failure')
        # Preserve official native reports without promoting a diagnostic sample to acceptance.
        for name, argv in [('summary', ['get', 'test-results', 'summary']), ('tests', ['get', 'test-results', 'tests'])]:
            data = checked(['xcrun', 'xcresulttool', *argv, '--path', str(result), '--compact'], output, 'export-' + name)
            save(output / (name + '.json'), json.loads(data))
        summary = json.loads((output / 'summary.json').read_text())
        accounting = native_accounting(summary, json.loads((output / 'tests.json').read_text()), native, args.device)
        save(output / 'native-accounting.json', accounting)
        # Resolve and hash only after the original native result is retained, outside its 30-second gate.
        directory, verification = verify_profile_product(observer, profile, app, hashes)
        save(output / 'post-native-product.json', verification)
        sample_status = ('Profiled' if verification['hashesMatchSealedProduct'] and verification['sampleBindingStillCurrent']
                         and profile.get('status') == 'SampledPendingProductVerification' else 'Gap')
        save(output / 'diagnostic-summary.json', {'head': head, 'nativeExitCode': native,
            'nativeResult': summary.get('result'), 'passed': summary.get('passedTests'), 'failed': summary.get('failedTests'),
            'sampleStatus': sample_status, 'sample': profile.get('sample'), 'acceptanceClaimed': False})
        print(json.dumps({'nativeExitCode': native, 'sampleStatus': sample_status, 'acceptanceClaimed': False}))
        return native if native else (0 if sample_status == 'Profiled' else 2)
    finally:
        # Markers are scalar original diagnostic evidence; raw sampler scratch was deleted above.
        if directory is None: directory = observer.directory
        for phase in PHASES:
            if directory is None: break
            try:
                value = read_marker(directory, phase, nonce, observer.earliest)
                if value is not None: save(output / (phase + '.json'), value)
            except (OSError, ValueError, SUPPORT['Gap']) as error:
                save(output / (phase + '-gap.json'), {'category': type(error).__name__,
                    'reason': str(error) if isinstance(error, SUPPORT['Gap']) else type(error).__name__})


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('products', 'result', 'output', 'sdk-checkout'): parser.add_argument('--' + name, type=Path, required=True)
    for name in ('device', 'expected-head', 'expected-sdk'): parser.add_argument('--' + name, required=True)
    raise SystemExit(main(parser.parse_args()))
