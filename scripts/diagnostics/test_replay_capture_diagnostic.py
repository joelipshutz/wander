"""Pure contracts; never invokes Simulator, xcodebuild, libproc, or sample."""
from pathlib import Path
import copy, importlib.util, json, os, plistlib, re, runpy, tempfile, time, unittest, uuid
from unittest.mock import Mock, call, patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('replay_diagnostic', HERE / 'replay-capture-diagnostic.py')
diagnostic = importlib.util.module_from_spec(spec); spec.loader.exec_module(diagnostic)
NONCE = '801556D6-F35A-4E9B-B1CE-AF19FECC01C2'
MARKER = diagnostic.marker_basename(NONCE)


class FakeClock:
    def __init__(self): self.now, self.waits = 1000.0, []
    def monotonic(self): return self.now
    def advance(self, seconds): self.now += seconds
    def wait(self, seconds): self.waits.append(seconds); self.advance(seconds); return False


class ConfigurationTests(unittest.TestCase):
    def fixture(self, root, modern=False, arguments=None):
        target = {'BlueprintName': 'WanderTests', 'IsUITestBundle': False, 'Unrelated': ['keep', 1]}
        if arguments is not None: target['CommandLineArguments'] = arguments
        document = ({'TestConfigurations': [{'TestTargets': [target]}]} if modern else {'WanderTests': target})
        config = root / 'Wander.xctestrun'; config.write_bytes(plistlib.dumps(document, fmt=plistlib.FMT_BINARY))
        (root / 'Info.plist').write_bytes(plistlib.dumps({'Tests': [{'xctestrun': config.name}]}))
        return config

    def test_legacy_restores_exact_bytes_after_exception(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); config = self.fixture(root); original = config.read_bytes()
            with self.assertRaisesRegex(RuntimeError, 'simulated'):
                with diagnostic.diagnostic_arguments(root, MARKER, root / 'receipt.json'):
                    target = diagnostic.host_target(plistlib.loads(config.read_bytes()))[0]
                    self.assertEqual(target['CommandLineArguments'], [diagnostic.FLAG, MARKER])
                    self.assertEqual(target['Unrelated'], ['keep', 1])
                    raise RuntimeError('simulated')
            self.assertEqual(config.read_bytes(), original)
            self.assertTrue(json.loads((root / 'receipt.json').read_text())['restored'])

    def test_modern_preserves_existing_arguments(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); config = self.fixture(root, modern=True, arguments=['ordinary'])
            original = config.read_bytes()
            with diagnostic.diagnostic_arguments(root, MARKER, root / 'receipt.json'):
                self.assertEqual(diagnostic.host_target(plistlib.loads(config.read_bytes()))[0]['CommandLineArguments'][0], 'ordinary')
            self.assertEqual(config.read_bytes(), original)

    def test_current_inert_helper_nests_and_restores(self):
        host = runpy.run_path(str(HERE.parent / 'run-parent-regression.py'))['replay_fixture_host']
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); config = self.fixture(root, arguments=[]); original = config.read_bytes()
            with diagnostic.diagnostic_arguments(root, MARKER, root / 'receipt.json'):
                outer = config.read_bytes()
                with host(root) as admission:
                    self.assertEqual(diagnostic.host_target(plistlib.loads(config.read_bytes()))[0]['CommandLineArguments'][-2:], ['-WanderReplayFixtureHost', 'inert'])
                self.assertTrue(admission['restored']); self.assertEqual(config.read_bytes(), outer)
            self.assertEqual(config.read_bytes(), original)

    def test_conflicting_argument_rejected_before_write(self):
        for arguments in ([diagnostic.FLAG, '/tmp/a'], [diagnostic.FLAG + '=/tmp/a']):
            with tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp); config = self.fixture(root, arguments=arguments); original = config.read_bytes()
                with self.assertRaises(RuntimeError):
                    with diagnostic.diagnostic_arguments(root, MARKER, root / 'receipt.json'): pass
                self.assertEqual(config.read_bytes(), original)

    def test_native_configuration_drift_still_restores(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); config = self.fixture(root); original = config.read_bytes()
            with self.assertRaises(RuntimeError):
                with diagnostic.diagnostic_arguments(root, MARKER, root / 'receipt.json'):
                    value = plistlib.loads(config.read_bytes()); value['changed'] = True
                    config.write_bytes(plistlib.dumps(value))
            self.assertEqual(config.read_bytes(), original)

    def test_configuration_escape_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'products'; root.mkdir()
            outside = Path(tmp) / 'outside'; outside.write_bytes(plistlib.dumps({}))
            (root / 'Info.plist').write_bytes(plistlib.dumps({'Tests': [{'xctestrun': '../outside'}]}))
            with self.assertRaises(RuntimeError):
                with diagnostic.diagnostic_arguments(root, MARKER, root / 'receipt.json'): pass

    def test_absolute_relative_and_noncanonical_marker_arguments_rejected_before_write(self):
        invalid = ['/tmp/' + MARKER, '../' + MARKER, MARKER.lower(), MARKER + '/child', 'arbitrary']
        for name in invalid:
            with tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp); config = self.fixture(root); original = config.read_bytes()
                with self.assertRaises((RuntimeError, ValueError)):
                    with diagnostic.diagnostic_arguments(root, name, root / 'receipt.json'): pass
                self.assertEqual(config.read_bytes(), original)


class ContainerBindingTests(unittest.TestCase):
    def container(self, root, name, marker=False):
        container = root / name; (container / 'tmp').mkdir(parents=True)
        if marker: (container / 'tmp' / MARKER).mkdir()
        return container

    def observer(self, root, sequence):
        observer = diagnostic.Observer(root, 'owned-device', NONCE)
        observer.lookup = Mock(side_effect=sequence)
        observer.stop.wait = Mock(return_value=False)
        return observer

    def test_relocated_container_binds_only_runtime_nonce_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve()
            old = self.container(root, 'preinstalled')
            new = self.container(root, 'runtime', marker=True)
            app = root / 'runtime-app/Wander.app'
            observer = self.observer(root, [old, new, app]); observer.bind()
            self.assertEqual(observer.directory, new / 'tmp' / MARKER)
            self.assertEqual(observer.installed_app, app)
            self.assertEqual(observer.lookup.call_args_list,
                [call('data', 1, timeout=10), call('data', 2, timeout=10), call('app', 2, timeout=10)])
            self.assertFalse((old / 'tmp' / MARKER).exists())

    def test_unchanged_container_is_admitted_without_waiting_for_relocation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve(); container = self.container(root, 'same', marker=True)
            app = root / 'same-app/Wander.app'
            observer = self.observer(root, [container, app]); observer.bind()
            self.assertEqual(observer.directory, container / 'tmp' / MARKER)
            self.assertEqual(observer.lookup.call_count, 2)

    def test_failed_or_denied_lookup_is_not_retried(self):
        for error in (PermissionError('denied'), diagnostic.SUPPORT['Gap']('lookup_failed'), TimeoutError()):
            with tempfile.TemporaryDirectory() as tmp:
                observer = self.observer(Path(tmp), [error])
                with self.assertRaises(type(error)): observer.bind()
                self.assertEqual(observer.lookup.call_count, 1)
                self.assertIsNone(observer.directory)

    def test_symlinked_nonce_directory_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve(); container = self.container(root, 'data')
            other = root / 'other'; other.mkdir()
            (container / 'tmp' / MARKER).symlink_to(other, target_is_directory=True)
            observer = self.observer(root, [container])
            with self.assertRaisesRegex(RuntimeError, 'marker_directory_symlink'): observer.bind()
            self.assertEqual(observer.lookup.call_count, 1)

    def test_successful_unchanged_polls_are_bounded(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve(); container = self.container(root, 'data')
            observer = self.observer(root, [container] * 120)
            clock = FakeClock(); observer.stop.wait = clock.wait
            with patch.object(diagnostic.time, 'monotonic', clock.monotonic):
                with self.assertRaisesRegex(RuntimeError, 'native_ended_or_rebind_deadline'): observer.bind()
            self.assertEqual(observer.lookup.call_count, 105)
            self.assertEqual(clock.waits, [1] * 105)
            self.assertEqual(clock.now, 1105)
            self.assertEqual(observer.report['dataContainerQueries'], 105)

    def test_slow_successful_lookup_is_admitted_with_sequential_one_second_spacing(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve(); old = self.container(root, 'old'); new = self.container(root, 'new', marker=True)
            app = root / 'new-app/Wander.app'; clock = FakeClock(); active = 0; maximum = 0; calls = []
            responses = iter([(5.43, old), (.3, new), (.1, app)])
            def lookup(kind, attempt, timeout):
                nonlocal active, maximum
                active += 1; maximum = max(maximum, active)
                try:
                    elapsed, result = next(responses); self.assertLessEqual(elapsed, timeout)
                    calls.append((kind, attempt, clock.now, timeout)); clock.advance(elapsed)
                    return result
                finally: active -= 1
            observer = self.observer(root, []); observer.lookup = lookup; observer.stop.wait = clock.wait
            with patch.object(diagnostic.time, 'monotonic', clock.monotonic): observer.bind()
            self.assertEqual(maximum, 1); self.assertEqual(active, 0)
            self.assertEqual(clock.waits, [1]); self.assertAlmostEqual(calls[1][2] - calls[0][2], 6.43)
            self.assertEqual([row[3] for row in calls], [10, 10, 10])
            self.assertEqual(observer.installed_app, app)

    def test_timeout_budget_reserves_cleanup_inside_total_admission_and_never_retries(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve(); old = self.container(root, 'old'); clock = FakeClock(); budgets = []
            def lookup(kind, attempt, timeout):
                budgets.append(timeout); clock.advance(timeout)
                if attempt == 10:
                    clock.advance(15)  # Worst-case owned-process TERM grace and reap.
                    raise TimeoutError('simulated lookup timeout')
                return old
            observer = self.observer(root, []); observer.lookup = Mock(side_effect=lookup); observer.stop.wait = clock.wait
            with patch.object(diagnostic.time, 'monotonic', clock.monotonic):
                with self.assertRaises(TimeoutError): observer.bind()
            self.assertEqual(budgets, [10] * 9 + [6])
            self.assertEqual(observer.lookup.call_count, 10); self.assertEqual(clock.now, 1120)
            self.assertEqual(clock.waits, [1] * 9); self.assertIsNone(observer.directory)

    def test_app_lookup_shares_the_same_remaining_budget_and_cleanup_reserve(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve(); old = self.container(root, 'old'); new = self.container(root, 'new', marker=True)
            clock = FakeClock(); calls = []
            def lookup(kind, attempt, timeout):
                calls.append((kind, attempt, timeout))
                if kind == 'app':
                    clock.advance(timeout + 15); raise TimeoutError('simulated app lookup timeout')
                clock.advance(10 if attempt < 10 else 4)
                return old if attempt < 10 else new
            observer = self.observer(root, []); observer.lookup = lookup; observer.stop.wait = clock.wait
            with patch.object(diagnostic.time, 'monotonic', clock.monotonic):
                with self.assertRaises(TimeoutError): observer.bind()
            self.assertEqual(calls[-2:], [('data', 10, 6), ('app', 10, 2)])
            self.assertEqual(len(calls), 11); self.assertEqual(clock.now, 1120)
            self.assertIsNone(observer.directory); self.assertIsNone(observer.installed_app)

    def test_failed_lookup_has_no_success_spacing_or_additional_app_lookup(self):
        for error in (PermissionError('denied'), diagnostic.SUPPORT['Gap']('lookup_failed'), TimeoutError()):
            observer = self.observer(Path('/unused'), [error]); clock = FakeClock(); observer.stop.wait = clock.wait
            with patch.object(diagnostic.time, 'monotonic', clock.monotonic):
                with self.assertRaises(type(error)): observer.bind()
            self.assertEqual(observer.lookup.call_args_list, [call('data', 1, timeout=10)])
            self.assertEqual(clock.waits, [])

    def test_late_first_draw_still_cannot_start_sampler(self):
        observer = self.observer(Path('/unused'), []); observer.bind = Mock()
        observer.markers = Mock(return_value={'ready-began': {'systemUptime': 90},
            'first-ready-draw': {'systemUptime': 97}, 'first-snapshot': None, 'ready-ended': None})
        with patch.object(diagnostic.time, 'monotonic', return_value=100), \
             patch.object(diagnostic, 'process_identity') as identity, patch.object(diagnostic.subprocess, 'Popen') as process:
            observer.watch()
            identity.assert_not_called(); process.assert_not_called()
        self.assertEqual(observer.report['reason'], 'sample_trigger_late')
        self.assertEqual(observer.report['sampleAttempts'], 0)

    def test_post_native_verification_does_not_retry_denied_or_unbound_lookup(self):
        for denied in (True, False):
            observer = diagnostic.Observer(Path('/unused'), 'owned-device', NONCE)
            if denied:
                observer.directory = Path('/known-marker')
                observer.installed_app = Path('/known-app')
            with patch.object(diagnostic, 'current_container') as lookup, patch.object(diagnostic, 'app_hashes') as hashes:
                directory, report = diagnostic.verify_profile_product(observer, {'permissionDenied': denied}, Path('/sealed'), {})
                lookup.assert_not_called(); hashes.assert_not_called()
            self.assertIsNone(directory)
            self.assertFalse(report['verificationPerformed'])


class MarkerTests(unittest.TestCase):
    def fixture(self, directory, **changes):
        nonce = str(uuid.uuid4()).upper()
        value = dict(schema=1, phase='first-ready-draw', nonce=nonce, pid=12345,
                     systemUptime=time.monotonic(), epoch=time.time())
        value.update(changes); (directory / 'first-ready-draw.json').write_text(json.dumps(value))
        return nonce, value

    def test_valid_marker(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); nonce, value = self.fixture(root)
            self.assertEqual(diagnostic.read_marker(root, 'first-ready-draw', nonce, time.time() - 1), value)

    def test_missing_marker_is_not_inferred(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertIsNone(diagnostic.read_marker(Path(tmp), 'first-ready-draw', 'missing', time.time()))

    def test_nonce_mismatch(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); self.fixture(root)
            with self.assertRaises(RuntimeError): diagnostic.read_marker(root, 'first-ready-draw', 'wrong', time.time() - 1)

    def test_stale_marker(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); nonce, _ = self.fixture(root, epoch=time.time() - 60, systemUptime=time.monotonic() - 60)
            with self.assertRaises(RuntimeError): diagnostic.read_marker(root, 'first-ready-draw', nonce, time.time())

    def test_nonfinite_and_extra_fields_rejected(self):
        for changes in ({'epoch': float('nan')}, {'systemUptime': float('inf')}, {'extra': 'unapproved'}):
            with tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp); nonce, _ = self.fixture(root, **changes)
                with self.assertRaises(RuntimeError): diagnostic.read_marker(root, 'first-ready-draw', nonce, time.time() - 1)

    def test_marker_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); target = root / 'other'; target.write_text('{}')
            (root / 'first-ready-draw.json').symlink_to(target)
            with self.assertRaises(OSError): diagnostic.read_marker(root, 'first-ready-draw', 'n', time.time())


class CuratorTests(unittest.TestCase):
    def test_static_symbols_only(self):
        raw = b'Process: private-header\nCall graph:\n    20 Thread_private\n    + 20 PHWebPEncode (in phlibwebp) + 12 [0x1234]\n    +   10 semaphore_wait_trap (in libsystem_kernel.dylib) + 1 [0xabcd]\n    unexpected secret/path\nBinary Images:\n/path/private\n'
        result = diagnostic.curate(raw)
        self.assertEqual(result['retainedStaticRows'], 2)
        serialized = json.dumps(result)
        for private in ('private-header', 'Thread_private', 'secret/path', '/path/private', '0x1234'):
            self.assertNotIn(private, serialized)
        self.assertFalse(result['sampleCountsAreCPUOrRunnableTime'])

    def test_unrecognized_profile_not_reported_as_complete(self):
        result = diagnostic.curate(b'unknown profile')
        self.assertEqual(result['retainedStaticRows'], 0)
        self.assertFalse(result['completeCallTreeClaimed'])


class NativeAccountingTests(unittest.TestCase):
    def fixture(self, native=0):
        result = 'Passed' if native == 0 else 'Failed'
        counts = dict(passedTests=int(native == 0), failedTests=int(native == 65), skippedTests=0, expectedFailures=0)
        summary = dict(result=result, totalTestCount=1, **counts,
                       devicesAndConfigurations=[dict(device={'deviceId': 'TEST-DEVICE'}, **counts)])
        tests = {'children': [{'nodeType': 'Test Case', 'result': result,
            'nodeIdentifierURL': 'test://com.apple.xcode/Wander/' + diagnostic.METHOD}]}
        return summary, tests

    def test_exact_original_method_pass_and_failure_retained(self):
        for native in (0, 65):
            summary, tests = self.fixture(native)
            report = diagnostic.native_accounting(summary, tests, native, 'TEST-DEVICE')
            self.assertEqual(report['nativeExitCode'], native)
            self.assertFalse(report['acceptanceClaimed'])

    def test_zero_case_infrastructure_failure_cannot_be_assertion_failure(self):
        summary, tests = self.fixture(65); tests['children'] = []
        with self.assertRaisesRegex(RuntimeError, 'native_case_mismatch'):
            diagnostic.native_accounting(summary, tests, 65, 'TEST-DEVICE')

    def test_wrong_method_device_count_and_exit_are_rejected(self):
        for change in ('method', 'device', 'count', 'exit'):
            summary, tests = self.fixture()
            if change == 'method': tests['children'][0]['nodeIdentifierURL'] += 'Another'
            if change == 'device': summary['devicesAndConfigurations'][0]['device']['deviceId'] = 'OTHER'
            if change == 'count': summary['totalTestCount'] = 2
            with self.assertRaises(RuntimeError):
                diagnostic.native_accounting(summary, tests, 65 if change == 'exit' else 0, 'TEST-DEVICE')


if __name__ == '__main__': unittest.main()
