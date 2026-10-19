import hashlib, importlib.util, json, os, re, stat, tempfile, unittest
from pathlib import Path
from unittest.mock import patch, Mock

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('stage_runner',HERE/'rec636-replay-stages.py')
M=importlib.util.module_from_spec(spec);spec.loader.exec_module(M)
def digest(b):return hashlib.sha256(b).hexdigest()

class SourceContractTests(unittest.TestCase):
    def test_proof_and_patch_pins(self):
        proof=HERE/'replay-stages-proof.json'
        self.assertEqual(M.sha(proof),M.PROOF_SHA)
        rows=json.loads(proof.read_text())['files']
        self.assertEqual([(r['role'],r['path']) for r in rows],[('sdk','PostHog/Replay/PostHogReplayIntegration.swift'),('test','WanderTests/ReplayMaskingTests.swift')])
        for row in rows:self.assertEqual(M.sha(HERE/row['patch']),row['patchSHA256'])
    def test_only_additive_diagnostic_blocks(self):
        # Diff removals are forbidden: original behavior must remain byte-identical.
        for name in ['replay-stages-sdk.patch','replay-stages-test.patch']:
            lines=(HERE/name).read_text().splitlines()
            self.assertFalse(any(x.startswith('-') and not x.startswith('---') for x in lines))
            added='\n'.join(x[1:] for x in lines if x.startswith('+') and not x.startswith('+++'))+'\n'
            remainder=re.sub(r'^[ \t]*// REC636_STAGE_BEGIN\n.*?^[ \t]*// REC636_STAGE_END\n','',added,flags=re.M|re.S)
            self.assertEqual(remainder,'')
    def test_no_timing_or_render_treatments(self):
        added='\n'.join(x for n in ['replay-stages-sdk.patch','replay-stages-test.patch'] for x in (HERE/n).read_text().splitlines() if x.startswith('+') and not x.startswith('+++'))
        for forbidden in ['Task.sleep','CADisplayLink','setNeedsLayout','layoutIfNeeded','compressionQuality','throttleDelay','PHWebPEncode','DispatchQueue(']:self.assertNotIn(forbidden,added)
        self.assertEqual(added.count('REC636ReplayStageObserver.install {'),1)
        self.assertEqual(added.count('events.count < 128'),1)
    def test_missing_dispatch_identity_is_rejected_before_paths(self):
        with patch.dict(os.environ,{'GITHUB_ACTIONS':'true','GITHUB_REPOSITORY':'joelipshutz/wander'},clear=True):
            with self.assertRaisesRegex(RuntimeError,'dispatch_head_mismatch'):M.context()
    def test_second_run_attempt_is_rejected_before_paths(self):
        with patch.dict(os.environ,{'GITHUB_ACTIONS':'true','GITHUB_REPOSITORY':'joelipshutz/wander','DIAGNOSTIC_HEAD':'a'*40,'GITHUB_SHA':'a'*40,'GITHUB_RUN_ATTEMPT':'2','GITHUB_RUN_ID':'123'},clear=True):
            with self.assertRaisesRegex(RuntimeError,'first_attempt_required'):M.context()

class PrivateFixtureScopeTests(unittest.TestCase):
    def invoke(self,exported):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);source=root/'source';out=root/'out';source.mkdir();out.mkdir()
            (out/'fixture-env').touch()
            if exported:M.save(out/'export-receipt.json',{'complete':True})
            observed={}
            class Fake:
                SUITES=('replay-private','replay-credentials')
                def main(self):
                    observed.update(suites=self.SUITES,exported=os.environ['REPLAY_EVIDENCE_EXPORTED'],argv=list(M.sys.argv))
            module=Fake();cwd=Path.cwd()
            try:
                with patch.object(M,'load_fixture',return_value=module),patch.dict(os.environ,{},clear=True),patch.object(M.sys,'argv',[]):
                    M.fixture_phase(source,out,'cleanup')
            finally:os.chdir(cwd)
            return observed
    def test_cleanup_requires_only_the_actual_private_evidence_scope(self):
        observed=self.invoke(True)
        self.assertEqual(observed['suites'],('replay-private',))
        self.assertEqual(observed['exported'],'true')
        self.assertEqual(observed['argv'][-1],'cleanup')
    def test_missing_export_cannot_claim_success(self):
        self.assertEqual(self.invoke(False)['exported'],'false')

class SourceRestorationTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
        self.source=self.root/'source';self.sdk=self.root/'sdk';self.out=self.root/'out'
        for p in [self.source,self.sdk,self.out]:p.mkdir()
        self.rows=[];self.patched={};self.original={}
        for role,root in [('sdk',self.sdk),('test',self.source)]:
            p=root/'file.swift';before=(role+' original\n').encode();after=(role+' instrumented\n').encode();p.write_bytes(before);p.chmod(0o444)
            self.rows.append({'role':role,'path':'file.swift','originalSHA256':digest(before),'patchedSHA256':digest(after),'patch':role+'.patch'})
            self.patched[root]=after;self.original[p]=before
    def tearDown(self):self.temp.cleanup()
    def apply(self,root,patchfile):(root/'file.swift').write_bytes(self.patched[root])
    def verify(self):
        for p,b in self.original.items():self.assertEqual(p.read_bytes(),b);self.assertEqual(stat.S_IMODE(p.stat().st_mode),0o444)
        self.assertTrue(all(r['bytesRestored'] and r['modeRestored'] for r in M.read(self.out/'source-restoration.json')['files']))
    def execute(self,apply=None,build=lambda:0):return M.instrumented_build(self.rows,self.source,self.sdk,self.out,apply or self.apply,build)
    def test_success_restores_bytes_and_readonly_modes(self):
        self.assertEqual(self.execute(),0);self.verify()
    def test_failed_build_restores_without_reclassifying(self):
        self.assertEqual(self.execute(build=lambda:65),65);self.verify()
    def test_exception_during_second_patch_restores_both(self):
        calls=[]
        def apply(root,p):
            calls.append(root)
            if len(calls)==2:raise OSError('simulated patch failure')
            self.apply(root,p)
        with self.assertRaises(OSError):self.execute(apply=apply)
        self.verify()
    def test_interrupt_during_build_restores_both(self):
        def build():raise KeyboardInterrupt()
        with self.assertRaises(KeyboardInterrupt):self.execute(build=build)
        self.verify()
    def test_build_source_drift_fails_and_restores(self):
        def build():(self.sdk/'file.swift').write_text('unexpected');return 0
        with self.assertRaisesRegex(RuntimeError,'source_changed_during_build'):self.execute(build=build)
        self.verify()
    def test_wrong_original_rejected_before_any_patch(self):
        p=self.source/'file.swift';p.chmod(0o644);p.write_text('foreign');p.chmod(0o444)
        with self.assertRaisesRegex(RuntimeError,'original_source_changed'):self.execute(apply=lambda *_:self.fail('must not patch'))
        self.assertEqual((self.sdk/'file.swift').read_bytes(),self.original[self.sdk/'file.swift'])
        self.assertEqual(stat.S_IMODE(p.stat().st_mode),0o444)
        self.assertFalse((self.out/'source-transaction-start.json').exists())
    def test_one_restore_error_still_restores_the_other_file_and_fails(self):
        original=Path.write_bytes
        sdk_path=self.sdk/'file.swift'
        def write(path,data):
            if path==sdk_path and data==self.original[sdk_path]:raise OSError('simulated restore denial')
            return original(path,data)
        with patch.object(Path,'write_bytes',write):
            with self.assertRaisesRegex(RuntimeError,'restoration_failed'):self.execute()
        test_path=self.source/'file.swift'
        self.assertEqual(test_path.read_bytes(),self.original[test_path])
        self.assertEqual(stat.S_IMODE(test_path.stat().st_mode),0o444)
        rows=M.read(self.out/'source-restoration.json')['files']
        self.assertFalse(rows[0]['bytesRestored']);self.assertTrue(rows[1]['bytesRestored'])

class OwnedGroupTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.out=Path(self.temp.name);self.stop_file=self.out/'process-cleanup-stop.json'
    def tearDown(self):self.temp.cleanup()
    def test_reap_precedes_group_probe_even_after_leader_exit(self):
        order=[];process=Mock(pid=123)
        process.poll.side_effect=lambda:order.append('reap')
        with patch.object(M.os,'killpg',side_effect=lambda *_:order.append('probe')):
            self.assertTrue(M.group_alive(process))
        self.assertEqual(order,['reap','probe'])
    def test_surviving_descendant_receives_bounded_kill(self):
        process=Mock(pid=123)
        with patch.object(M,'group_alive',side_effect=[True,True,False]), \
             patch.object(M.os,'killpg') as kill, \
             patch.object(M.time,'monotonic',side_effect=[0,6,6,12]):
            self.assertTrue(M.stop_group(process))
        self.assertEqual(kill.call_args_list,[unittest.mock.call(123,M.signal.SIGTERM),unittest.mock.call(123,M.signal.SIGKILL)])
        process.wait.assert_not_called()
    def test_cleanup_permission_error_preserves_original_timeout(self):
        error=M.subprocess.TimeoutExpired(['fixed'],1);process=Mock(pid=123)
        process.wait.side_effect=error
        with patch.object(M.subprocess,'Popen',return_value=process), \
             patch.object(M,'stop_group',side_effect=PermissionError):
            with self.assertRaises(M.subprocess.TimeoutExpired) as result:M.run(['fixed'],HERE,1,self.stop_file)
        self.assertIs(result.exception,error)
        self.assertEqual(error.rec636_cleanup_error,'owned_group_cleanup_PermissionError')
        process.wait.assert_called_once_with(timeout=1)
    def test_unstopped_group_preserves_interruption_and_marks_failure(self):
        error=KeyboardInterrupt();process=Mock(pid=123);process.wait.side_effect=error
        with patch.object(M.subprocess,'Popen',return_value=process),patch.object(M,'stop_group',return_value=False):
            with self.assertRaises(KeyboardInterrupt) as result:M.run(['fixed'],HERE,1,self.stop_file)
        self.assertIs(result.exception,error)
        self.assertEqual(error.rec636_cleanup_error,'owned_process_group_not_stopped')

    def test_initiating_permission_error_never_probes_or_signals(self):
        error=PermissionError();process=Mock(pid=123);process.wait.side_effect=error
        with patch.object(M.subprocess,'Popen',return_value=process),patch.object(M,'stop_group') as stop:
            with self.assertRaises(PermissionError) as result:M.run(['fixed'],HERE,1,self.stop_file)
        self.assertIs(result.exception,error);stop.assert_not_called()
        self.assertEqual(M.read(self.stop_file)['category'],'native_process_PermissionError')
        with self.assertRaisesRegex(RuntimeError,'process_cleanup_stop_recorded'):M.require_process_cleanup_known(self.out)
    def test_unknown_native_outcome_stops_later_simulator_cleanup(self):
        M.save(self.out/'native-intent.json',{'executions':1})
        with self.assertRaisesRegex(RuntimeError,'native_process_outcome_unknown'):M.require_process_cleanup_known(self.out)
    def test_completed_failed_native_outcome_still_allows_evidence_cleanup(self):
        M.save(self.out/'native-intent.json',{'executions':1})
        M.save(self.out/'native-result.json',{'exitCode':65,'acceptance':False})
        M.require_process_cleanup_known(self.out)
    def test_unknown_outcome_stops_cleanup_even_if_stop_receipt_write_fails(self):
        M.save(self.out/'native-intent.json',{'executions':1})
        error=KeyboardInterrupt();process=Mock(pid=123);process.wait.side_effect=error
        with patch.object(M.subprocess,'Popen',return_value=process),patch.object(M,'stop_group',return_value=False),patch.object(M,'save',side_effect=PermissionError):
            with self.assertRaises(KeyboardInterrupt) as result:M.run(['fixed'],HERE,1,self.stop_file)
        self.assertIs(result.exception,error)
        with self.assertRaisesRegex(RuntimeError,'native_process_outcome_unknown'):M.require_process_cleanup_known(self.out)

class CurrentSourceAndProductTests(unittest.TestCase):
    def test_sdk_checkout_rejects_external_root_and_parent_symlinks(self):
        with tempfile.TemporaryDirectory() as folder:
            base=Path(folder);out=base/'out';out.mkdir();external=base/'external';external.mkdir()
            good=out/'owned';good.mkdir();M.validate_sdk_checkout(good,out)
            linked=out/'linked';linked.symlink_to(external,target_is_directory=True)
            for bad in [external,linked]:
                with self.assertRaisesRegex(RuntimeError,'sdk_not_job_owned'):M.validate_sdk_checkout(bad,out)
            child=external/'child';child.mkdir()
            with self.assertRaisesRegex(RuntimeError,'sdk_not_job_owned'):M.validate_sdk_checkout(linked/'child',out)
    def test_current_product_bytes_are_rechecked_before_native(self):
        with tempfile.TemporaryDirectory() as folder:
            out=Path(folder);expected={'fingerprint':'original'};M.save(out/'product-fingerprint.json',expected)
            module=Mock();module.product_fingerprint.return_value={'fingerprint':'changed'}
            with patch.object(M,'load_fixture',return_value=module):
                with self.assertRaisesRegex(RuntimeError,'current_products_changed_before_native'):
                    M.require_current_products(HERE,out,{'productsBefore':expected})
            module.product_fingerprint.assert_called_once_with(out/'Replay.xctestproducts')
    def test_equal_stored_and_current_products_are_admitted(self):
        with tempfile.TemporaryDirectory() as folder:
            out=Path(folder);expected={'fingerprint':'original'};M.save(out/'product-fingerprint.json',expected)
            module=Mock();module.product_fingerprint.return_value=expected
            with patch.object(M,'load_fixture',return_value=module):
                M.require_current_products(HERE,out,{'productsBefore':expected})
            module.product_fingerprint.assert_called_once()
    def test_registered_workflow_is_dispatch_only_with_read_permission(self):
        root=HERE.parents[1];workflows=root/'.github/workflows'
        base='ddb188a12b6b7cbadb86ce7242a94318fbfc7f44'
        feed='.github/workflows/feed-checkin-validation.yml'
        baseline=M.subprocess.check_output(['git','ls-tree','-r','--name-only',base,'--','.github/workflows'],cwd=root,text=True).splitlines()
        current=sorted(p.relative_to(root).as_posix() for p in workflows.rglob('*') if p.is_file())
        self.assertEqual(current,sorted(baseline))
        self.assertIn(feed,baseline)
        for name in baseline:
            if name!=feed:
                original=M.subprocess.check_output(['git','show',base+':'+name],cwd=root)
                self.assertEqual((root/name).read_bytes(),original,'unrelated workflow changed: '+name)
        content=(root/feed).read_text()
        self.assertIn('  workflow_dispatch:',content)
        self.assertIn('permissions:\n  contents: read\n',content)
        self.assertNotIn('  pull_request:',content);self.assertNotIn('  push:',content)
        self.assertNotIn('actions: write',content)
        self.assertEqual(content.count('    runs-on:'),1)

if __name__=='__main__':unittest.main()
