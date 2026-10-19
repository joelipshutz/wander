#!/usr/bin/env python3
"""One fixed diagnostic. No acceptance replacement or automatic retry."""
from pathlib import Path
import argparse, hashlib, importlib.util, json, os, re, shlex, signal, stat, subprocess, sys, time

HEAD='6f149bff202b839425ea7b6469c77813709070c4'
TREE='5881d6224f0e7f8e04d58bebec30e95cec8a0118'
SDK_REV='ee5b5705b0038f0c44646cde5fe972bb65387596'
PROOF_SHA='7899d4ec2a694e77ee4d700e5502580d888f1e6281ec428f3ec37f7118d04ca5'
FIXTURE_SHA='85c70ff4f8f1645ad0162b2f5efd0d592a73519441906e32b4961ca25b6d4ab0'
METHOD='WanderTests/ReplayMaskingTests/testPrivateMessageContentIsMaskedInActualReplayImage'
HERE=Path(__file__).resolve().parent
def need(ok,why):
    if not ok:raise RuntimeError(why)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text())
def save(p,value):
    with p.open('x') as f:json.dump(value,f,indent=2,sort_keys=True);f.write('\n')
def capture(command,cwd):
    return subprocess.check_output(command,cwd=cwd,text=True,timeout=30).strip()
def group_alive(process):
    # Reap the leader before probing; its exit alone does not prove group absence.
    process.poll()
    try:os.killpg(process.pid,0);return True
    except ProcessLookupError:return False

def stop_group(process):
    for sig,grace in [(signal.SIGTERM,5),(signal.SIGKILL,5)]:
        if not group_alive(process):return True
        try:os.killpg(process.pid,sig)
        except ProcessLookupError:return True
        deadline=time.monotonic()+grace
        while time.monotonic()<deadline:
            if not group_alive(process):return True
            time.sleep(min(0.1,max(0,deadline-time.monotonic())))
    return not group_alive(process)

def note_cleanup_error(error,category,stop_file):
    error.rec636_cleanup_error=category
    print(category,file=sys.stderr)
    try:save(stop_file,{'stop':True,'category':category,'diagnosticOnly':True})
    except FileExistsError:pass  # Preserve the first terminal reason.
    except OSError:print('process_stop_receipt_write_failed',file=sys.stderr)

def require_process_cleanup_known(out):
    need(not (out/'process-cleanup-stop.json').exists(),'process_cleanup_stop_recorded')
    need(not (out/'native-intent.json').exists() or (out/'native-result.json').is_file(),
         'native_process_outcome_unknown')

def run(command,cwd,limit,stop_file):
    # Native output stays in the ordinary CI job log, never in source/receipts.
    process=subprocess.Popen(command,cwd=cwd,start_new_session=True)
    try:return process.wait(timeout=limit)
    except BaseException as error:
        if isinstance(error,PermissionError):
            note_cleanup_error(error,'native_process_PermissionError',stop_file)
            raise
        try:
            if not stop_group(process):note_cleanup_error(error,'owned_process_group_not_stopped',stop_file)
        except BaseException as cleanup_error:
            # Permission failures stop cleanup; never widen access or mask cause.
            note_cleanup_error(error,'owned_group_cleanup_'+type(cleanup_error).__name__,stop_file)
        raise

def load_fixture(source):
    p=source/'scripts/replay-simulator-fixture.py'
    need(sha(p)==FIXTURE_SHA,'fixture_source_changed')
    spec=importlib.util.spec_from_file_location('fixed_fixture',p)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module

def validate_sdk_checkout(sdk,out):
    need(sdk.is_dir() and not sdk.is_symlink()
         and sdk.resolve().is_relative_to(out.resolve()),'sdk_not_job_owned')

def require_current_products(source,out,fixture):
    expected=read(out/'product-fingerprint.json')
    need(fixture['productsBefore']==expected,'fixture_not_bound_to_build')
    need(load_fixture(source).product_fingerprint(out/'Replay.xctestproducts')==expected,
         'current_products_changed_before_native')

def instrumented_build(rows, source, sdk, out, apply, build):
    """Apply only the two admitted files; restore bytes/modes on every exit."""
    saved=[]
    for row in rows:
        root=sdk if row['role']=='sdk' else source
        p=root/row['path']
        need(p.is_file() and not p.is_symlink() and p.resolve().is_relative_to(root.resolve()),'source_path')
        need(sha(p)==row['originalSHA256'],'original_source_changed')
        saved.append((p,p.read_bytes(),stat.S_IMODE(p.stat().st_mode),row))
    save(out/'source-transaction-start.json',{'files':[{'role':r['role'],'path':r['path'],'sha256':r['originalSHA256'],'mode':m} for _,_,m,r in saved]})
    result=None
    try:
        for p,_,mode,row in saved:
            # Only owner-write on these two disposable checkout files.
            p.chmod(mode | stat.S_IWUSR)
            apply(sdk if row['role']=='sdk' else source,HERE/row['patch'])
            need(sha(p)==row['patchedSHA256'],'patched_source_changed')
        save(out/'instrumented-source.json',{'files':rows,'diagnosticOnly':True})
        result=build()
        need(all(sha(p)==r['patchedSHA256'] for p,_,_,r in saved),'source_changed_during_build')
        return result
    finally:
        restoration=[]
        for p,data,mode,row in saved:
            errors=[]
            try:
                p.chmod(mode | stat.S_IWUSR)
                p.write_bytes(data)
            except OSError as error:errors.append(type(error).__name__)
            finally:
                try:p.chmod(mode)
                except OSError as error:errors.append(type(error).__name__)
            try:bytes_ok=sha(p)==row['originalSHA256'];mode_ok=stat.S_IMODE(p.stat().st_mode)==mode
            except OSError as error:errors.append(type(error).__name__);bytes_ok=mode_ok=False
            restoration.append({'role':row['role'],'path':row['path'],'bytesRestored':bytes_ok,'modeRestored':mode_ok,'errors':errors})
        save(out/'source-restoration.json',{'files':restoration,'buildExitCode':result})
        need(all(x['bytesRestored'] and x['modeRestored'] for x in restoration),'restoration_failed')

def context():
    need(os.environ.get('GITHUB_ACTIONS')=='true' and os.environ.get('GITHUB_REPOSITORY')=='joelipshutz/wander','ci_only')
    need(re.fullmatch('[0-9a-f]{40}',os.environ.get('DIAGNOSTIC_HEAD','')) and os.environ.get('DIAGNOSTIC_HEAD')==os.environ.get('GITHUB_SHA'),'dispatch_head_mismatch')
    need(os.environ.get('GITHUB_RUN_ATTEMPT')=='1' and re.fullmatch('[0-9]+',os.environ.get('GITHUB_RUN_ID','')),'first_attempt_required')
    source=Path(os.environ['GITHUB_WORKSPACE'])/'native'
    out=Path(os.environ['RUNNER_TEMP'])/'rec636-replay-stages'
    need(source.is_dir() and not source.is_symlink(),'source_directory')
    need(capture(['git','rev-parse','HEAD','HEAD^{tree}'],source)==HEAD+'\n'+TREE,'candidate_changed')
    need(sha(HERE/'replay-stages-proof.json')==PROOF_SHA,'proof_changed')
    proof=read(HERE/'replay-stages-proof.json')
    need(proof['candidate']==HEAD and proof['sdkRevision']==SDK_REV,'proof_identity')
    for row in proof['files']:need(sha(HERE/row['patch'])==row['patchSHA256'],'patch_changed')
    return source,out,proof

def fixture_phase(source,out,operation):
    # Diagnostic-only evidence scope. The normal helper and all class-level
    # source/device/product/ownership/cleanup checks stay byte-for-byte intact.
    module=load_fixture(source)
    need(module.SUITES==('replay-private','replay-credentials'),'normal_fixture_scope_changed')
    module.SUITES=('replay-private',)
    os.environ['RUNNER_TEMP']=str(out)
    env_file=out/'fixture-env'
    if operation=='prepare':env_file.touch(exist_ok=False)
    os.environ['GITHUB_ENV']=str(env_file)
    os.environ['REPLAY_EVIDENCE_EXPORTED']='true' if (out/'export-receipt.json').is_file() and read(out/'export-receipt.json')['complete'] else 'false'
    sys.argv=[str(source/'scripts/replay-simulator-fixture.py'),operation]
    if operation=='prepare':sys.argv+=['--source-device',read(out/'admission.json')['sourceDeviceID']]
    os.chdir(source)
    module.main()

def record_compiler_flags(out):
    # Observe only generated compiler options; never persist paths/env/command text.
    base=out/'DerivedData/Build/Intermediates.noindex'
    paths=sorted(base.rglob('*-common-args.resp'))
    need(0 < len(paths) <= 128,'compiler_response_count')
    rows=[]
    for path in paths:
        need(path.is_file() and not path.is_symlink() and path.resolve().is_relative_to(base.resolve())
             and path.stat().st_size <= 262144,'compiler_response_path')
        relative=path.relative_to(base).as_posix()
        match=re.fullmatch(r'([A-Za-z0-9_.-]+)\.build/Debug-iphonesimulator/([A-Za-z0-9_.-]+)\.build/Objects-normal/arm64/[A-Za-z0-9_-]+-common-args\.resp',relative)
        need(match is not None,'compiler_response_configuration')
        tokens=shlex.split(path.read_text())
        flags=[x for x in tokens if re.fullmatch(r'-O(?:[0-3szg]|fast)?',x)]
        rows.append({'project':match[1],'target':match[2],'relativeResponse':relative,
                     'sha256':sha(path),'bytes':path.stat().st_size,'optimizationFlags':flags,
                     'debugDefine':'-DDEBUG=1' in tokens})
    phlibwebp=[r for r in rows if r['project']=='PostHog' and r['target']=='phlibwebp']
    verified=bool(phlibwebp) and all(r['optimizationFlags']==['-Os'] and r['debugDefine'] for r in rows)
    save(out/'compiler-flags.json',{'diagnosticOnly':True,'acceptance':False,
         'candidate':HEAD,'admissionSHA256':sha(out/'admission.json'),
         'sourceRestorationSHA256':sha(out/'source-restoration.json'),
         'configuration':'Debug','platform':'iphonesimulator','architecture':'arm64',
         'requestedCOptimization':'s','observedCFlagsVerified':verified,
         'requestedSwiftOptimization':'-Onone','swiftCompilerCommandObserved':False,
         'treatmentScope':'all C-family targets','responses':rows})
    need(verified,'actual_c_optimization_not_verified')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase',choices=['admit','build','prepare','test','export','cleanup','verify-restoration'])
    phase=parser.parse_args().phase
    source,out,proof=context()
    if phase=='admit':
        out.mkdir()
        toolchain=capture(['xcodebuild','-version'],source)
        need(toolchain=='Xcode 26.6\nBuild version 17F113','toolchain_mismatch')
        module=load_fixture(source)
        inventory=json.loads(capture(['xcrun','simctl','list','--json'],source))
        candidates=[d for runtime,rows in inventory['devices'].items() if runtime=='com.apple.CoreSimulator.SimRuntime.iOS-26-5' for d in rows if d.get('name')=='iPhone 17 Pro' and d.get('isAvailable')]
        need(len(candidates)==1,'source_device_count')
        device=module.locate(inventory,candidates[0]['udid'])
        need(device['runtimeVersion']=='26.5' and device['runtimeBuild']=='23F77','runtime_mismatch')
        save(out/'admission.json',{'candidate':HEAD,'tree':TREE,'workflowHead':os.environ['GITHUB_SHA'],'runID':os.environ['GITHUB_RUN_ID'],'attempt':os.environ['GITHUB_RUN_ATTEMPT'],'toolchain':toolchain,'sourceDeviceID':device['deviceID'],'sourceDevice':device,'diagnosticOnly':True,'acceptance':False,'retries':0})
    elif phase=='build':
        sdk=out/'SourcePackages/checkouts/posthog-ios'
        validate_sdk_checkout(sdk,out)
        need(capture(['git','rev-parse','HEAD'],sdk)==SDK_REV,'sdk_revision_changed')
        save(out/'build-intent.json',{'diagnosticOnly':True,'runs':1})
        device=read(out/'admission.json')['sourceDeviceID']
        def apply(root,patch):
            subprocess.run(['git','apply','--check',str(patch)],cwd=root,check=True,timeout=30)
            subprocess.run(['git','apply',str(patch)],cwd=root,check=True,timeout=30)
        command=['xcodebuild','build-for-testing','-quiet','-project','Wander.xcodeproj','-scheme','Wander','-configuration','Debug','-destination','platform=iOS Simulator,id='+device,'-derivedDataPath',str(out/'DerivedData'),'-clonedSourcePackagesDirPath',str(out/'SourcePackages'),'-disableAutomaticPackageResolution','-onlyUsePackageVersionsFromResolvedFile','-jobs','2','-parallel-testing-enabled','NO','-testProductsPath',str(out/'Replay.xctestproducts'),'-only-testing:WanderTests/ReplayMaskingTests','CODE_SIGNING_ALLOWED=YES','CODE_SIGN_IDENTITY=-','GENERATE_INFOPLIST_FILE=YES','GCC_OPTIMIZATION_LEVEL=s','SWIFT_OPTIMIZATION_LEVEL=-Onone']
        code=instrumented_build(proof['files'],source,sdk,out,apply,lambda:run(command,source,1500,out/'process-cleanup-stop.json'))
        save(out/'build-result.json',{'exitCode':code,'diagnosticOnly':True})
        if code:raise SystemExit(code)
        record_compiler_flags(out)
        save(out/'product-fingerprint.json',load_fixture(source).product_fingerprint(out/'Replay.xctestproducts'))
    elif phase=='verify-restoration':
        if not (out/'source-transaction-start.json').exists():return
        restored=read(out/'source-restoration.json')
        need(all(x['bytesRestored'] and x['modeRestored'] for x in restored['files']),'source_restoration_incomplete')
        for row,original in zip(proof['files'],read(out/'source-transaction-start.json')['files']):
            p=(out/'SourcePackages/checkouts/posthog-ios' if row['role']=='sdk' else source)/row['path']
            need(sha(p)==row['originalSHA256'] and stat.S_IMODE(p.stat().st_mode)==original['mode'],'source_or_mode_not_restored')
    elif phase in ('prepare','cleanup'):
        if phase=='cleanup':
            require_process_cleanup_known(out)
            if not (out/'replay-simulator-fixture/receipt.json').exists():return
        if phase=='prepare':
            need(read(out/'build-result.json')['exitCode']==0,'build_not_successful')
            need(load_fixture(source).product_fingerprint(out/'Replay.xctestproducts')==read(out/'product-fingerprint.json'),'built_products_changed')
        fixture_phase(source,out,phase)
    elif phase=='test':
        need(read(out/'build-result.json')['exitCode']==0,'build_not_successful')
        fixture=read(out/'replay-simulator-fixture/receipt.json')
        need(fixture['admitted'] and not fixture['blocked'],'fixture_not_admitted')
        require_current_products(source,out,fixture)
        save(out/'native-intent.json',{'identifier':METHOD,'executions':1,'retries':0,'diagnosticOnly':True})
        device=fixture['actualDevice']['deviceID']
        command=['python3','scripts/run-parent-regression.py','--suite','replay-private','--destination',device,'--test-products',str(out/'Replay.xctestproducts'),'--result-bundle',str(out/'replay-private.xcresult'),'--selection-file',str(out/'selection.json'),'--replay-fixture-host','inert','--replay-host-receipt',str(out/'replay-private-host.json')]
        code=run(command,source,900,out/'process-cleanup-stop.json')
        save(out/'native-result.json',{'identifier':METHOD,'exitCode':code,'diagnosticOnly':True,'acceptance':False})
        raise SystemExit(code)
    elif phase=='export':
        bundle=out/'replay-private.xcresult'
        if not (bundle/'Info.plist').is_file():return
        evidence=out/'evidence';evidence.mkdir()
        results=[];before=sha(bundle/'Info.plist')
        for kind in ['summary','tests']:
            with (evidence/('replay-private-'+kind+'.json')).open('xb') as f:
                code=subprocess.run(['xcrun','xcresulttool','get','test-results',kind,'--path',str(bundle)],stdout=f,timeout=120).returncode
                results.append({'kind':kind,'exitCode':code})
        code=run(['xcrun','xcresulttool','export','attachments','--path',str(bundle),'--output-path',str(evidence/'replay-private')],source,120,out/'process-cleanup-stop.json')
        results.append({'kind':'attachments','exitCode':code})
        complete=all(x['exitCode']==0 for x in results) and sha(bundle/'Info.plist')==before
        save(out/'export-receipt.json',{'complete':complete,'exports':results,'resultInfoSHA256':before,'diagnosticOnly':True})
        need(complete,'exports_incomplete')

if __name__=='__main__':
    signal.signal(signal.SIGTERM,lambda *_:(_ for _ in ()).throw(KeyboardInterrupt()))
    main()
