#!/usr/bin/env python3
"""CI-only, one-attempt Simulator isolation for the two offline Replay proofs."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import stat
import subprocess
import uuid

REPOSITORY = "joelipshutz/wander"
MODELS = {"iPhone 17 Pro", "iPhone 17"}
SUITES = ("replay-private", "replay-credentials")


class FixtureError(RuntimeError):
    pass


def require(value, code):
    if not value:
        raise FixtureError(code)


def valid_uuid(value):
    try:
        return isinstance(value, str) and str(uuid.UUID(value)).upper() == value.upper()
    except (ValueError, AttributeError):
        return False


def locate(inventory, device_id):
    require(isinstance(inventory, dict) and isinstance(inventory.get("devices"), dict), "invalid_inventory")
    matches = [(runtime, row) for runtime, rows in inventory["devices"].items()
               for row in rows if row.get("udid") == device_id]
    require(len(matches) == 1, "missing_or_ambiguous_device")
    runtime, row = matches[0]
    types = [x for x in inventory.get("devicetypes", [])
             if x.get("identifier") == row.get("deviceTypeIdentifier")]
    runtimes = [x for x in inventory.get("runtimes", []) if x.get("identifier") == runtime]
    require(len(types) == len(runtimes) == 1, "missing_or_ambiguous_type_runtime")
    require(row.get("isAvailable") is True and runtimes[0].get("isAvailable") is True
            and types[0].get("name") in MODELS
            and runtime.startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
            and all(isinstance(runtimes[0].get(k), str) and runtimes[0][k] for k in ['version', 'buildversion'])
            and row.get("state") in {"Booted", "Shutdown"}, "unsupported_device")
    return {"deviceID": device_id, "name": row.get("name"), "model": types[0]["name"],
            "deviceTypeIdentifier": types[0]["identifier"], "runtimeIdentifier": runtime,
            "runtimeVersion": runtimes[0].get("version"),
            "runtimeBuild": runtimes[0].get("buildversion"), "state": row["state"]}


def same_platform(left, right):
    return all(left.get(k) == right.get(k) for k in
               ["model", "deviceTypeIdentifier", "runtimeIdentifier", "runtimeVersion", "runtimeBuild"])


class Fixture:
    """All mutations are journaled before dispatch; ambiguous outcomes are terminal."""
    def __init__(self, state, save, run, fingerprint):
        self.state, self.save, self.run, self.fingerprint = state, save, run, fingerprint

    def fail(self, code):
        self.state.update(blocked=True, failure=code)
        self.save(self.state)
        raise FixtureError(code)

    def command(self, operation, arguments, *, mutation=False, timeout=30):
        if self.state.get("blocked"):
            raise FixtureError("terminal_fixture_failure")
        event = {"operation": operation, "mutation": mutation, "state": "dispatched", "timeoutSeconds": timeout}
        self.state.setdefault("commands", []).append(event)
        self.save(self.state)
        result = self.run(["/usr/bin/xcrun", "simctl", *arguments], timeout)
        out, err = result.get("stdout", b""), result.get("stderr", b"")
        denied = result.get("permissionDenied", False) or any(
            x in err.lower() for x in [b"permission denied", b"operation not permitted", b"permission to save"])
        event.update(state="completed", exitCode=result.get("returncode"), timedOut=result.get("timedOut", False),
                     permissionDenied=denied, stdoutBytes=len(out), stderrBytes=len(err),
                     stdoutSHA256=hashlib.sha256(out).hexdigest(), stderrSHA256=hashlib.sha256(err).hexdigest(),
                     rawOutputRetained=False)
        self.save(self.state)
        if denied:
            self.fail("command_permission_denied")
        if event["timedOut"]:
            self.fail("command_timeout_outcome_uncertain")
        if result.get("returncode") != 0:
            self.fail("command_failed_outcome_uncertain" if mutation else "inventory_command_failed")
        if len(out) > 8 * 1024 * 1024 or len(err) > 64 * 1024:
            self.fail("command_output_limit")
        return out

    def inventory(self, operation):
        raw = self.command(operation, ["list", "--json"])
        try:
            return json.loads(raw)
        except (ValueError, UnicodeDecodeError):
            self.fail("invalid_inventory_json")

    def checked_locate(self, inventory, device_id):
        try:
            return locate(inventory, device_id)
        except (FixtureError, TypeError, KeyError, AttributeError):
            self.fail("device_identity_unverifiable")

    def prepare(self):
        require(not self.state.get("prepareStarted"), "prepare_already_attempted")
        self.state["prepareStarted"] = True
        self.save(self.state)
        inventory = self.inventory("initial_inventory")
        source = self.checked_locate(inventory, self.state["sourceDeviceID"])
        self.state["source"] = source
        self.state["productsBefore"] = self.fingerprint()
        self.save(self.state)
        if source["state"] == "Booted":
            self.command("shutdown_source", ["shutdown", source["deviceID"]], mutation=True, timeout=60)
        confirmed = self.checked_locate(self.inventory("confirm_source_shutdown"), source["deviceID"])
        if confirmed["state"] != "Shutdown" or not same_platform(source, confirmed):
            self.fail("source_shutdown_not_confirmed")
        self.state["sourceShutdownConfirmed"] = True
        self.save(self.state)
        raw = self.command("create_owned_device", ["create", self.state["requestedName"],
                           source["deviceTypeIdentifier"], source["runtimeIdentifier"]], mutation=True, timeout=60)
        try:
            created = raw.decode("ascii").strip()
        except UnicodeDecodeError:
            self.fail("create_identity_ambiguous")
        if not valid_uuid(created) or any(row.get("udid") == created
                for rows in inventory["devices"].values() for row in rows):
            self.fail("create_identity_ambiguous")
        self.state["createdDeviceID"] = created
        self.save(self.state)
        fresh = self.checked_locate(self.inventory("confirm_created_device"), created)
        if (fresh["name"] != self.state["requestedName"] or fresh["state"] != "Shutdown"
                or not same_platform(source, fresh)):
            self.fail("created_device_identity_mismatch")
        self.state.update(ownedDevice=fresh, ownershipVerified=True)
        self.save(self.state)
        self.command("boot_owned_device", ["bootstatus", created, "-b"], mutation=True, timeout=180)
        final = self.inventory("confirm_fixture_boot")
        ready = self.checked_locate(final, created)
        stopped = self.checked_locate(final, source["deviceID"])
        if (ready["name"] != self.state["requestedName"] or ready["state"] != "Booted"
                or not same_platform(source, ready) or stopped["state"] != "Shutdown"
                or not same_platform(source, stopped)):
            self.fail("fixture_boot_identity_mismatch")
        self.state["productsAfterPrepare"] = self.fingerprint()
        if self.state["productsBefore"] != self.state["productsAfterPrepare"]:
            self.fail("test_products_changed")
        self.state.update(admitted=True, actualDevice=ready)
        self.save(self.state)
        return created

    def cleanup(self, exported_evidence):
        require(not self.state.get("cleanupStarted"), "cleanup_already_attempted")
        self.state["cleanupStarted"] = True
        self.save(self.state)
        if (self.state.get("blocked") or not self.state.get("admitted")
                or self.state.get("ownershipVerified") is not True):
            self.fail("cleanup_refused_unadmitted_or_uncertain_fixture")
        created = self.state.get("createdDeviceID")
        if (not valid_uuid(created) or created == self.state["sourceDeviceID"]
                or created != self.state.get('ownedDevice', {}).get('deviceID')
                or created != self.state.get('actualDevice', {}).get('deviceID')):
            self.fail("cleanup_refused_foreign_identity")
        self.state["exportedEvidence"] = exported_evidence()
        self.state["productsBeforeCleanup"] = self.fingerprint()
        self.save(self.state)
        if self.state["productsBeforeCleanup"] != self.state["productsBefore"]:
            self.fail("cleanup_refused_changed_products")
        observed = self.checked_locate(self.inventory("cleanup_identity_inventory"), created)
        if (observed["name"] != self.state["requestedName"]
                or not same_platform(observed, self.state["ownedDevice"])):
            self.fail("cleanup_refused_foreign_identity")
        if observed["state"] == "Booted":
            self.command("shutdown_owned_device", ["shutdown", created], mutation=True, timeout=60)
        stopped = self.checked_locate(self.inventory("confirm_owned_shutdown"), created)
        if (stopped["state"] != "Shutdown" or stopped["name"] != self.state["requestedName"]
                or not same_platform(stopped, self.state["ownedDevice"])):
            self.fail("cleanup_shutdown_not_confirmed")
        self.command("delete_owned_device", ["delete", created], mutation=True, timeout=60)
        final = self.inventory("confirm_owned_deletion")
        if any(row.get("udid") == created for rows in final.get("devices", {}).values() for row in rows):
            self.fail("cleanup_deletion_not_confirmed")
        self.state["cleanupCompleted"] = True
        self.save(self.state)


def native_command(argv, timeout):
    try:
        r = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout, check=False)
        return {"returncode": r.returncode, "stdout": r.stdout, "stderr": r.stderr}
    except subprocess.TimeoutExpired as error:
        return {"returncode": None, "stdout": error.stdout or b"", "stderr": error.stderr or b"", "timedOut": True}
    except PermissionError:
        return {"returncode": None, "stdout": b"", "stderr": b"", "permissionDenied": True}


def product_fingerprint(products):
    require(products.is_dir() and not products.is_symlink(), "invalid_products_root")
    digest = hashlib.sha256()
    files, total, configurations = 0, 0, {}
    for directory, dirs, names in os.walk(products, followlinks=False):
        dirs.sort()
        for name in dirs:
            require(not (Path(directory)/name).is_symlink(), "product_directory_symlink")
        for name in sorted(names):
            path = Path(directory)/name
            info = path.lstat()
            require(stat.S_ISREG(info.st_mode) and info.st_size <= 2 * 1024**3, "invalid_product_file")
            files += 1
            total += info.st_size
            require(files <= 20000 and total <= 4 * 1024**3, "products_size_limit")
            h = hashlib.sha256()
            with path.open('rb') as stream:
                for data in iter(lambda: stream.read(1024*1024), b''):
                    h.update(data)
            rel = str(path.relative_to(products))
            value = h.hexdigest()
            digest.update((rel+'\0'+value+'\n').encode())
            if rel == 'Info.plist' or path.suffix == '.xctestrun':
                configurations[rel] = value
    require('Info.plist' in configurations and any(x.endswith('.xctestrun') for x in configurations),
            "products_configuration_missing")
    return {"fileCount": files, "bytes": total, "filesSHA256": digest.hexdigest(),
            "configurationSHA256": configurations}


def ci_context(env):
    require(env.get('GITHUB_ACTIONS') == 'true' and env.get('RUNNER_OS') == 'macOS'
            and env.get('GITHUB_REPOSITORY') == REPOSITORY, 'ci_only')
    require(re.fullmatch('[0-9a-f]{40}', env.get('GITHUB_SHA', ''))
            and re.fullmatch('[0-9]+', env.get('GITHUB_RUN_ID', ''))
            and re.fullmatch('[1-9][0-9]*', env.get('GITHUB_RUN_ATTEMPT', '')), 'ci_identity_missing')
    root = Path(env['RUNNER_TEMP'])
    require(root.is_absolute() and root.is_dir() and not root.is_symlink(), 'invalid_ci_temp')
    return root, {"repository": REPOSITORY, "headSHA": env['GITHUB_SHA'],
                  "runID": env['GITHUB_RUN_ID'], "attempt": env['GITHUB_RUN_ATTEMPT']}


def checkout_provenance(run, helper_path):
    """Measure the checkout, permitting an externally verified synthetic PR merge."""
    result = run(['/usr/bin/git', 'rev-parse', 'HEAD', 'HEAD^{tree}'], 10)
    out, err = result.get('stdout', b''), result.get('stderr', b'')
    require(result.get('returncode') == 0 and not result.get('timedOut')
            and not result.get('permissionDenied') and len(out) <= 256 and len(err) <= 4096
            and not any(x in err.lower() for x in [b'permission denied', b'operation not permitted']),
            'checkout_identity_unavailable')
    try:
        lines = out.decode('ascii').splitlines()
    except UnicodeDecodeError:
        raise FixtureError('checkout_identity_malformed') from None
    require(len(lines) == 2 and all(re.fullmatch('[0-9a-f]{40}', x) for x in lines),
            'checkout_identity_malformed')
    sources = {}
    for name in ['replay-simulator-fixture.py', 'test_replay_simulator_fixture.py']:
        path = helper_path.parent/name
        require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 1024*1024,
                'fixture_source_unavailable')
        sources['scripts/'+name] = hashlib.sha256(path.read_bytes()).hexdigest()
    return {'commit': lines[0], 'tree': lines[1], 'sourceSHA256': sources}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['prepare', 'cleanup'])
    parser.add_argument('--source-device')
    args = parser.parse_args()
    root, identity = ci_context(os.environ)
    folder = root/'replay-simulator-fixture'
    products = root/'Replay.xctestproducts'
    checkout = checkout_provenance(native_command, Path(__file__))
    require(not folder.is_symlink(), 'fixture_directory_symlink')
    if args.operation == 'prepare':
        require(valid_uuid(args.source_device), 'invalid_source_device')
        folder.mkdir(mode=0o700)
        state = dict(schema=1, identity=identity, checkout=checkout, sourceDeviceID=args.source_device,
                     requestedName='REC636 Replay '+identity['runID']+'-'+identity['attempt'],
                     admitted=False, blocked=False, newNativeTests=0)
    else:
        require(args.source_device is None and folder.is_dir(), 'cleanup_requires_existing_fixture')
        path = folder/'receipt.json'
        require(path.is_file() and not path.is_symlink(), 'missing_fixture_receipt')
        state = json.loads(path.read_text())
        require(state.get('identity') == identity and state.get('schema') == 1
                and state.get('checkout') == checkout, 'foreign_fixture_receipt')
    # Each operation is single-use, even after an interrupted or uncertain command.
    with (folder/(args.operation+'-attempt.json')).open('x') as f:
        json.dump({"operation": args.operation, "identity": identity}, f)

    writes_blocked = False
    def save(value):
        nonlocal writes_blocked
        require(not writes_blocked, 'receipt_writes_stopped')
        try:
            sequence = len(list(folder.glob('state-*.json')))
            data = json.dumps(value, indent=2, sort_keys=True)+'\n'
            snapshot = folder/('state-%03d.json' % sequence)
            with snapshot.open('x') as f:
                f.write(data)
                f.flush()
                os.fsync(f.fileno())
            pending = folder/'receipt.pending'
            with pending.open('x') as f:
                f.write(data)
                f.flush()
                os.fsync(f.fileno())
            os.replace(pending, folder/'receipt.json')
        except OSError:
            writes_blocked = True
            raise

    def exported_evidence():
        require(os.environ.get('REPLAY_EVIDENCE_EXPORTED') == 'true', 'cleanup_evidence_export_not_successful')
        result = {}
        for suite in SUITES:
            bundle = root/(suite+'.xcresult')
            # An unexecuted or incomplete method is not treated as completed evidence.
            paths = [bundle/'Info.plist', root/(suite+'-host.json'),
                     root/'evidence'/(suite+'-summary.json'), root/'evidence'/suite/'manifest.json']
            for path in paths:
                require(path.is_file() and not path.is_symlink() and path.stat().st_size > 0
                        and path.resolve().is_relative_to(root.resolve()), 'cleanup_evidence_missing')
                result[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
        return result

    fixture = Fixture(state, save, native_command, lambda: product_fingerprint(products))
    try:
        if args.operation == 'prepare':
            destination = Path(os.environ['GITHUB_ENV'])
            require(destination.is_file() and not destination.is_symlink()
                    and destination.resolve().is_relative_to(root.resolve()), 'invalid_github_env_file')
            device = fixture.prepare()
            with destination.open('a') as f:
                f.write('REPLAY_DEVICE_ID='+device+'\n')
            state['workflowEnvironmentPublished'] = True
            save(state)
        else:
            fixture.cleanup(exported_evidence)
    except (FixtureError, OSError, ValueError, KeyError, TypeError) as error:
        state.update(blocked=True, terminalError=type(error).__name__,
                     terminalCategory=str(error) if isinstance(error, FixtureError) else 'local_io_or_metadata_failure')
        if not writes_blocked:
            save(state)
        raise SystemExit(state['terminalCategory']) from None
    print(json.dumps({"operation": args.operation, "admitted": state['admitted'],
                      "cleanupCompleted": state.get('cleanupCompleted', False)}))


if __name__ == '__main__':
    main()
