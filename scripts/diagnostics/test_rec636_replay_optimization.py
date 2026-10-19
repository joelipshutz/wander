import importlib.util, json, tempfile, unittest
from pathlib import Path

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('optimization_runner',HERE/'rec636-replay-stages.py')
M=importlib.util.module_from_spec(spec);spec.loader.exec_module(M)

class CompilerFlagEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.out=Path(self.temp.name)
        for name in ['admission.json','source-restoration.json']:(self.out/name).write_text('{}')
        self.base=self.out/'DerivedData/Build/Intermediates.noindex'
    def tearDown(self):self.temp.cleanup()
    def response(self,target='phlibwebp',flags='-Os -DDEBUG=1'):
        p=self.base/('PostHog.build/Debug-iphonesimulator/'+target+'.build/Objects-normal/arm64/abc-common-args.resp')
        p.parent.mkdir(parents=True,exist_ok=True);p.write_text(flags);return p
    def test_records_observed_c_and_labels_swift_as_requested(self):
        p=self.response();self.response('PHPLCrashReporter')
        M.record_compiler_flags(self.out);r=M.read(self.out/'compiler-flags.json')
        self.assertTrue(r['observedCFlagsVerified']);self.assertFalse(r['acceptance'])
        self.assertEqual(r['requestedSwiftOptimization'],'-Onone');self.assertFalse(r['swiftCompilerCommandObserved'])
        self.assertEqual(r['treatmentScope'],'all C-family targets')
        self.assertEqual({x['target'] for x in r['responses']},{'phlibwebp','PHPLCrashReporter'})
        row=next(x for x in r['responses'] if x['target']=='phlibwebp')
        self.assertEqual(row['sha256'],M.sha(p));self.assertEqual(row['optimizationFlags'],['-Os'])
        self.assertEqual(r['admissionSHA256'],M.sha(self.out/'admission.json'))
        self.assertEqual(r['sourceRestorationSHA256'],M.sha(self.out/'source-restoration.json'))
    def rejected(self):
        with self.assertRaisesRegex(RuntimeError,'actual_c_optimization_not_verified'):M.record_compiler_flags(self.out)
        self.assertFalse(M.read(self.out/'compiler-flags.json')['observedCFlagsVerified'])
    def test_o0_is_preserved_as_failure_not_claimed_optimized(self):self.response(flags='-O0 -DDEBUG=1');self.rejected()
    def test_conflicting_optimization_flags_rejected(self):self.response(flags='-Os -O0 -DDEBUG=1');self.rejected()
    def test_missing_phlibwebp_cannot_pass(self):self.response('PHPLCrashReporter');self.rejected()
    def test_other_c_target_scope_mismatch_rejected(self):
        self.response();self.response('PHPLCrashReporter','-O0 -DDEBUG=1');self.rejected()
    def test_missing_debug_macro_rejected(self):self.response(flags='-Os');self.rejected()
    def test_external_response_symlink_rejected(self):
        p=self.response();p.unlink();external=self.out/'foreign';external.write_text('-Os -DDEBUG=1');p.symlink_to(external)
        with self.assertRaisesRegex(RuntimeError,'compiler_response_path'):M.record_compiler_flags(self.out)
    def test_release_response_cannot_be_mislabelled_debug(self):
        p=self.response();q=Path(str(p).replace('Debug-iphonesimulator','Release-iphonesimulator'));q.parent.mkdir(parents=True);p.rename(q)
        with self.assertRaisesRegex(RuntimeError,'compiler_response_configuration'):M.record_compiler_flags(self.out)

if __name__=='__main__':unittest.main()
