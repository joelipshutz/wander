"""Offline fixtures only: these tests never invoke simctl or native app code."""
from pathlib import Path
import copy
import importlib.util
import json
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('fixture', Path(__file__).with_name('replay-simulator-fixture.py'))
F = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(F)
OLD = '11111111-1111-4111-8111-111111111111'
NEW = '22222222-2222-4222-8222-222222222222'
OTHER = '33333333-3333-4333-8333-333333333333'
RUNTIME = 'com.apple.CoreSimulator.SimRuntime.iOS-26-5'
TYPE = 'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro'
NAME = 'REC636 Replay 123-1'
PRODUCTS = {'fileCount':3, 'bytes':42, 'filesSHA256':'a'*64,
            'configurationSHA256':{'Info.plist':'b'*64, 'fixture.xctestrun':'c'*64}}


class Fake:
    def __init__(self, source_state='Booted'):
        self.state = dict(sourceDeviceID=OLD, requestedName=NAME, admitted=False, blocked=False)
        self.devices = {OLD:self.device(OLD,'iPhone 17 Pro',source_state)}
        self.saved, self.calls = [], []
        self.failure = None
        self.create_output = (NEW+'\n').encode()
        self.changed_runtime = False
        self.fingerprint = copy.deepcopy(PRODUCTS)
        self.fixture = F.Fixture(self.state,self.save,self.run,lambda:copy.deepcopy(self.fingerprint))

    def device(self, identity, name, state):
        return dict(udid=identity,name=name,state=state,isAvailable=True,deviceTypeIdentifier=TYPE)

    def save(self, value):
        self.saved.append(copy.deepcopy(value))

    def inventory(self):
        return {'devices':{RUNTIME:list(self.devices.values())},
                'devicetypes':[{'identifier':TYPE,'name':'iPhone 17 Pro'}],
                'runtimes':[{'identifier':RUNTIME,'isAvailable':True,'version':'26.5',
                             'buildversion':'changed' if self.changed_runtime else '23F77'}]}

    def run(self, argv, timeout):
        self.calls.append((argv,timeout))
        assert self.saved[-1]['commands'][-1]['state']=='dispatched'
        args=argv[2:]
        result={'returncode':0,'stdout':b'','stderr':b''}
        if args[0]=='list':result['stdout']=json.dumps(self.inventory()).encode()
        elif args[0]=='shutdown':self.devices[args[1]]['state']='Shutdown'
        elif args[0]=='create':
            self.devices[NEW]=self.device(NEW,args[1],'Shutdown')
            result['stdout']=self.create_output
        elif args[0]=='bootstatus':self.devices[args[1]]['state']='Booted'
        elif args[0]=='delete':self.devices.pop(args[1])
        else:raise AssertionError('unexpected command')
        if self.failure and self.failure[0]==self.saved[-1]['commands'][-1]['operation']:
            result.update(self.failure[1])
        return result

    def mutations(self):
        return [args[2:] for args,_ in self.calls if args[2]!='list']


class ReplaySimulatorFixtureTests(unittest.TestCase):
    def test_prepare_and_cleanup_exact_owned_device_once(self):
        f=Fake();self.assertEqual(f.fixture.prepare(),NEW)
        self.assertTrue(f.state['admitted']);self.assertTrue(f.state['sourceShutdownConfirmed'])
        self.assertEqual(f.state['productsBefore'],f.state['productsAfterPrepare'])
        f.fixture.cleanup(lambda:{'retained-evidence':'d'*64})
        self.assertTrue(f.state['cleanupCompleted'])
        self.assertEqual(f.mutations(),[['shutdown',OLD],['create',NAME,TYPE,RUNTIME],
            ['bootstatus',NEW,'-b'],['shutdown',NEW],['delete',NEW]])
        self.assertIn(OLD,f.devices);self.assertNotIn(NEW,f.devices)

    def test_source_already_shutdown_is_confirmed_without_shutdown_retry(self):
        f=Fake('Shutdown');f.fixture.prepare()
        self.assertNotIn(['shutdown',OLD],f.mutations())
        self.assertIn('confirm_source_shutdown',[x['operation'] for x in f.state['commands']])

    def test_source_shutdown_failure_stops_before_create(self):
        f=Fake();f.failure=('shutdown_source',{'returncode':1})
        with self.assertRaises(F.FixtureError):f.fixture.prepare()
        self.assertEqual(f.mutations(),[['shutdown',OLD]])

    def test_denied_command_never_retries_or_cleans_up(self):
        f=Fake();f.failure=('create_owned_device',{'returncode':1,'stderr':b'Operation not permitted'})
        with self.assertRaises(F.FixtureError):f.fixture.prepare()
        self.assertEqual(f.state['failure'],'command_permission_denied')
        before=len(f.calls)
        with self.assertRaises(F.FixtureError):f.fixture.cleanup(lambda:{})
        self.assertEqual(len(f.calls),before)

    def test_partial_create_nonzero_never_claims_ownership(self):
        f=Fake();f.failure=('create_owned_device',{'returncode':1})
        with self.assertRaises(F.FixtureError):f.fixture.prepare()
        self.assertIn(NEW,f.devices);self.assertNotIn('ownershipVerified',f.state)
        before=len(f.calls)
        with self.assertRaises(F.FixtureError):f.fixture.cleanup(lambda:{})
        self.assertEqual(len(f.calls),before)

    def test_create_timeout_preserves_uncertainty_and_refuses_cleanup(self):
        f=Fake();f.failure=('create_owned_device',{'returncode':None,'timedOut':True})
        with self.assertRaises(F.FixtureError):f.fixture.prepare()
        self.assertEqual(f.state['failure'],'command_timeout_outcome_uncertain')
        before=len(f.calls)
        with self.assertRaises(F.FixtureError):f.fixture.cleanup(lambda:{})
        self.assertEqual(len(f.calls),before)

    def test_boot_timeout_has_owned_id_but_no_admission_or_cleanup(self):
        f=Fake();f.failure=('boot_owned_device',{'returncode':None,'timedOut':True})
        with self.assertRaises(F.FixtureError):f.fixture.prepare()
        self.assertTrue(f.state['ownershipVerified']);self.assertFalse(f.state['admitted'])
        before=len(f.calls)
        with self.assertRaises(F.FixtureError):f.fixture.cleanup(lambda:{})
        self.assertEqual(len(f.calls),before)

    def test_ambiguous_or_foreign_create_output_rejected(self):
        for output in [(NEW+'\n'+OTHER).encode(),(OLD+'\n').encode(),b'not a uuid']:
            f=Fake();f.create_output=output
            with self.subTest(output=output),self.assertRaises(F.FixtureError):f.fixture.prepare()
            self.assertNotIn('ownershipVerified',f.state)

    def test_cleanup_foreign_uuid_refused_before_any_command(self):
        for identity in [OLD,OTHER]:
            f=Fake();f.fixture.prepare();f.state['createdDeviceID']=identity;before=len(f.calls)
            with self.subTest(identity=identity),self.assertRaises(F.FixtureError):f.fixture.cleanup(lambda:{})
            self.assertEqual(len(f.calls),before)

    def test_cleanup_foreign_name_or_runtime_refused_without_mutation(self):
        for change in ['name','runtime']:
            f=Fake();f.fixture.prepare();before=len(f.mutations())
            if change=='name':f.devices[NEW]['name']='Someone else'
            else:f.changed_runtime=True
            with self.subTest(change=change),self.assertRaises(F.FixtureError):f.fixture.cleanup(lambda:{})
            self.assertEqual(len(f.mutations()),before)

    def test_cleanup_denial_stops_before_delete(self):
        f=Fake();f.fixture.prepare();f.failure=('shutdown_owned_device',{'permissionDenied':True})
        with self.assertRaises(F.FixtureError):f.fixture.cleanup(lambda:{})
        self.assertNotIn(['delete',NEW],f.mutations())

    def test_missing_export_refuses_cleanup_before_device_commands(self):
        f=Fake();f.fixture.prepare();before=len(f.calls)
        def missing():raise F.FixtureError('missing export')
        with self.assertRaises(F.FixtureError):f.fixture.cleanup(missing)
        self.assertEqual(len(f.calls),before)

    def test_changed_products_refuse_cleanup_before_device_commands(self):
        f=Fake();f.fixture.prepare();f.fingerprint['filesSHA256']='changed';before=len(f.calls)
        with self.assertRaises(F.FixtureError):f.fixture.cleanup(lambda:{})
        self.assertEqual(len(f.calls),before)

    def test_no_second_prepare_or_cleanup(self):
        f=Fake();f.fixture.prepare();before=len(f.calls)
        with self.assertRaises(F.FixtureError):f.fixture.prepare()
        self.assertEqual(len(f.calls),before)
        f.fixture.cleanup(lambda:{'proof':'d'*64});before=len(f.calls)
        with self.assertRaises(F.FixtureError):f.fixture.cleanup(lambda:{})
        self.assertEqual(len(f.calls),before)

    def test_command_timeouts_are_bounded(self):
        f=Fake();f.fixture.prepare();f.fixture.cleanup(lambda:{})
        self.assertTrue(all(0 < timeout <= 180 for _,timeout in f.calls))

    def test_local_or_other_repository_context_rejected(self):
        for env in [{},{'GITHUB_ACTIONS':'true','RUNNER_OS':'macOS','GITHUB_REPOSITORY':'other/repo'}]:
            with self.subTest(env=env),self.assertRaises(F.FixtureError):F.ci_context(env)

    def test_checkout_provenance_binds_actual_commit_tree_and_both_sources(self):
        calls=[]
        def run(argv, timeout):
            calls.append((argv,timeout))
            return {'returncode':0,'stdout':(('a'*40)+'\n'+('b'*40)+'\n').encode(),'stderr':b''}
        value=F.checkout_provenance(run,Path(F.__file__))
        self.assertEqual(calls,[(['/usr/bin/git','rev-parse','HEAD','HEAD^{tree}'],10)])
        self.assertEqual(value['commit'],'a'*40);self.assertEqual(value['tree'],'b'*40)
        self.assertEqual(set(value['sourceSHA256']),{'scripts/replay-simulator-fixture.py',
                         'scripts/test_replay_simulator_fixture.py'})

    def test_checkout_failure_timeout_denial_and_ambiguous_output_are_terminal(self):
        for result in [{'returncode':1}, {'returncode':0,'timedOut':True},
                       {'returncode':0,'permissionDenied':True},
                       {'returncode':0,'stdout':b'not a sha'},
                       {'returncode':0,'stdout':b'\xff'},
                       {'returncode':0,'stdout':b'a'*257}]:
            with self.subTest(result=result), self.assertRaises(F.FixtureError):
                F.checkout_provenance(lambda *_:result,Path(F.__file__))

    def test_product_fingerprint_changes_and_rejects_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory);(p/'Info.plist').write_text('fixture');(p/'test.xctestrun').write_text('fixture')
            before=F.product_fingerprint(p);(p/'test.xctestrun').write_text('changed')
            self.assertNotEqual(before,F.product_fingerprint(p))
            (p/'link').symlink_to(p/'Info.plist')
            with self.assertRaises(F.FixtureError):F.product_fingerprint(p)


if __name__=='__main__':unittest.main()
