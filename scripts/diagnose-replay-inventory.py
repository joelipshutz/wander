#!/usr/bin/env python3
"""One disposable CI inventory comparison; never native-test acceptance."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re

BASE = '2ecd8df234d7da8629802a12b0c9a6a962258894'
BASE_TREE = '135f1334d8915ac2942f99be0701dd56cc27b1ca'
BRANCH = 'refs/heads/codex/rec636-v58-replay-inventory-diagnostic'
MODE = 'rec636-replay-inventory-v58'
WORKFLOW = '.github/workflows/feed-checkin-validation.yml'
SCRIPT = 'scripts/diagnose-replay-inventory.py'
PINS = {
    'scripts/replay-simulator-fixture.py': 'fca211d4179085efe24b2cd694005b3cb9ab9a4e58e9338a57f6dbbeb9b57da6',
    'scripts/test_replay_simulator_fixture.py': '0e0afee26a775859efedb8a94a22896ce9004cf6babd486d85efd8018732afdc',
    'project.yml': '3276c1f8efc5fd88ab1317b48da844487dc7877bdf771152202770e5c792836f',
    'Wander.xcodeproj/project.pbxproj': '5f93cdb938e369405570d5282f901cc8007ee284debe832e333e67956beb894e',
    'Wander.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved': 'ed0665b30b67be70370acad6ca584589e0b1e70b059a4c799628a270a0253ac3',
    'WanderTests/ReplayMaskingTests.swift': '80df366480648684a88923b4b2a954206507943465f3a0c02b52f1186be2afa4',
}
RUNTIME = 'com.apple.CoreSimulator.SimRuntime.iOS-26-5'


def require(value, category):
    if not value:
        raise RuntimeError(category)


def write_once(path, value):
    with path.open('x') as output:
        json.dump(value, output, indent=2, sort_keys=True)
        output.write('\n')
        output.flush()
        os.fsync(output.fileno())


def load_fixture():
    helper = Path('scripts/replay-simulator-fixture.py')
    require(hashlib.sha256(helper.read_bytes()).hexdigest() == PINS[str(helper)], 'helper_source_changed')
    spec = importlib.util.spec_from_file_location('replay_fixture', helper)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_command(F, argv):
    result = F.native_command(argv, 30)
    require(result.get('returncode') == 0 and not result.get('timedOut')
            and not result.get('permissionDenied'), 'admission_command_failed')
    raw = result.get('stdout', b'')
    require(len(raw) <= 8*1024*1024 and len(result.get('stderr', b'')) <= 65536, 'admission_output_limit')
    return raw.decode('utf-8').strip()


def source_admission(F):
    command = lambda *argv: read_command(F, list(argv))
    require(os.environ.get('GITHUB_REF') == BRANCH and os.environ.get('GITHUB_RUN_ATTEMPT') == '1', 'one_exact_branch_attempt_required')
    head, tree = command('/usr/bin/git', 'rev-parse', 'HEAD', 'HEAD^{tree}').splitlines()
    expected = [os.environ.get('EXPECTED_COMMIT', ''), os.environ.get('EXPECTED_TREE', '')]
    require(all(re.fullmatch('[0-9a-f]{40}', x) for x in expected), 'full_reviewed_commit_tree_required')
    require([head, tree] == expected and head == os.environ.get('GITHUB_SHA'), 'source_identity_mismatch')
    require(command('/usr/bin/git', 'show', '-s', '--format=%P', 'HEAD') == BASE, 'one_diagnostic_commit_required')
    require(command('/usr/bin/git', 'rev-parse', BASE+'^{tree}') == BASE_TREE, 'base_tree_mismatch')
    require(set(command('/usr/bin/git', 'diff', '--name-only', BASE, 'HEAD').splitlines()) == {WORKFLOW, SCRIPT}, 'diagnostic_scope_mismatch')
    require(not command('/usr/bin/git', 'status', '--porcelain'), 'checkout_dirty')
    pins = {name: hashlib.sha256(Path(name).read_bytes()).hexdigest() for name in PINS}
    require(pins == PINS, 'unchanged_source_pins_mismatch')
    require(command('/usr/bin/xcodebuild', '-version').splitlines() == ['Xcode 26.6', 'Build version 17F113'], 'reference_xcode_required')
    return {'baseCommit': BASE, 'baseTree': BASE_TREE, 'head': head, 'tree': tree, 'sourceSHA256': pins}


def comparison_fixture(F, state, save, run, fingerprint):
    class InventoryComparison(F.Fixture):
        def inventory(self, operation):
            if operation != 'confirm_fixture_boot':
                value = super().inventory(operation)
                if operation == 'initial_inventory':
                    source = self.checked_locate(value, self.state['sourceDeviceID'])
                    if not (F.same_platform(source, self.state['expectedSource'])
                            and source['name'] == self.state['expectedSource']['name']):
                        self.fail('admitted_source_platform_changed')
                return value
            combined = {}
            for component in ('devices', 'runtimes', 'devicetypes'):
                raw = self.command('postboot_'+component, ['list', component, '--json'], timeout=30)
                try:
                    value = json.loads(raw)
                    require(set(value) == {component}, 'component_inventory_keys_mismatch')
                    combined[component] = value[component]
                except (ValueError, TypeError, RuntimeError):
                    self.fail('component_inventory_invalid')
            created = self.checked_locate(combined, self.state['createdDeviceID'])
            source = self.checked_locate(combined, self.state['sourceDeviceID'])
            if not (created['state'] == 'Booted' and created['name'] == self.state['requestedName']
                    and source['state'] == 'Shutdown' and F.same_platform(created, self.state['source'])
                    and F.same_platform(source, self.state['source'])):
                self.fail('component_identity_mismatch')
            self.state['componentIdentities'] = {'created': created, 'source': source}
            self.save(self.state)
            # One original broad query AFTER component evidence; failure stays terminal.
            broad = super().inventory(operation)
            if self.checked_locate(broad, created['deviceID']) != created or self.checked_locate(broad, source['deviceID']) != source:
                self.fail('broad_component_identity_mismatch')
            self.state['broadAndComponentIdentityMatch'] = True
            self.save(self.state)
            return broad
    return InventoryComparison(state, save, run, fingerprint)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', choices=['admit', 'compare'])
    args = parser.parse_args()
    F = load_fixture()
    root, identity = F.ci_context(os.environ)
    out = root/'rec636-replay-inventory'
    if args.stage == 'admit':
        out.mkdir(mode=0o700)
    require(out.is_dir() and not out.is_symlink(), 'diagnostic_output_unavailable')
    write_once(out/(args.stage+'-attempt.json'), {'mode': MODE, 'identity': identity, 'nativeTests': 0})
    sources = source_admission(F)
    if args.stage == 'admit':
        inventory = json.loads(read_command(F, ['/usr/bin/xcrun', 'simctl', 'list', '--json']))
        choices = [row for row in inventory['devices'].get(RUNTIME, []) if row.get('name') == 'iPhone 17 Pro' and row.get('isAvailable') is True]
        require(len(choices) == 1, 'exact_unique_reference_device_required')
        device = F.locate(inventory, choices[0]['udid'])
        require(device['model'] == 'iPhone 17 Pro' and device['runtimeVersion'] == '26.5'
                and device['runtimeBuild'] == '23F77', 'reference_platform_required')
        write_once(out/'admission.json', {'identity': identity, 'sources': sources, 'device': device, 'diagnosticOnly': True})
        env = Path(os.environ['GITHUB_ENV'])
        require(env.is_file() and not env.is_symlink() and env.resolve().is_relative_to(root.resolve()), 'invalid_workflow_env')
        with env.open('a') as stream:
            stream.write('REPLAY_INVENTORY_SOURCE='+device['deviceID']+'\n')
        return
    admission = json.loads((out/'admission.json').read_text())
    require(admission['identity'] == identity and admission['sources'] == sources, 'admission_source_changed')
    products = root/'Replay.xctestproducts'
    state = {'schema': 1, 'identity': identity, 'checkout': sources, 'sourceDeviceID': admission['device']['deviceID'],
             'expectedSource': admission['device'],
             'requestedName': 'REC636 Inventory '+identity['runID']+'-'+identity['attempt'],
             'admitted': False, 'blocked': False, 'newNativeTests': 0, 'diagnosticOnly': True}
    snapshots = 0
    def save(value):
        nonlocal snapshots
        write_once(out/('state-%03d.json' % snapshots), value)
        snapshots += 1
    fixture = comparison_fixture(F, state, save, F.native_command, lambda: F.product_fingerprint(products))
    failure = None
    try:
        fixture.prepare()
    except (F.FixtureError, OSError, ValueError, KeyError, TypeError) as error:
        failure = str(error) if isinstance(error, F.FixtureError) else 'diagnostic_io_or_metadata_failure'
        state.update(blocked=True, primaryFailure=failure)
    finally:
        try:
            state['productsAfterDiagnostic'] = F.product_fingerprint(products)
            state['sourceAfterDiagnostic'] = source_admission(F)
            state['productBytesUnchanged'] = state.get('productsBefore') == state['productsAfterDiagnostic']
        except (RuntimeError, OSError, ValueError, KeyError, TypeError):
            state['postflightFailure'] = 'source_or_products_unverifiable'
        write_once(out/'result.json', state)
    require(failure is None and state.get('productBytesUnchanged') and not state.get('postflightFailure')
            and state['admitted'], failure or 'diagnostic_incomplete')
    # No host, app, tests, cleanup retry or acceptance. GitHub disposes this runner.


if __name__ == '__main__':
    main()
