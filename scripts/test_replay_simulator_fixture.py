"""Offline fixtures only: these tests never invoke simctl or native app code."""
from pathlib import Path
import copy
import importlib.util
import json
import os
import tempfile
import unittest
from unittest import mock

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

    def test_only_postboot_inventory_gets_the_readiness_deadline(self):
        f=Fake();f.fixture.prepare();f.fixture.cleanup(lambda:{})
        for event,(argv,timeout) in zip(f.state['commands'],f.calls):
            expected=180 if event['operation']=='confirm_fixture_boot' or argv[2]=='bootstatus' else (
                30 if argv[2]=='list' else 60)
            with self.subTest(operation=event['operation']):
                self.assertEqual(timeout,expected)
                self.assertEqual(event['timeoutSeconds'],expected)

    def test_command_records_monotonic_duration_on_completion_only(self):
        f=Fake()
        with mock.patch.object(F.time,'monotonic',side_effect=[100.0,102.125]):
            f.fixture.inventory('initial_inventory')
        self.assertNotIn('elapsedSeconds',f.saved[0]['commands'][0])
        self.assertEqual(f.state['commands'][0]['elapsedSeconds'],2.125)
        self.assertEqual(f.saved[-1]['commands'][0],f.state['commands'][0])

    def test_failed_commands_retain_monotonic_duration(self):
        for result,category in [({'returncode':1},'inventory_command_failed'),
                ({'returncode':None,'timedOut':True},'command_timeout_outcome_uncertain'),
                ({'returncode':None,'permissionDenied':True},'command_permission_denied')]:
            f=Fake();f.failure=('initial_inventory',result)
            with self.subTest(category=category),mock.patch.object(F.time,'monotonic',side_effect=[50.0,80.25]):
                with self.assertRaisesRegex(F.FixtureError,'^'+category+'$'):
                    f.fixture.inventory('initial_inventory')
            self.assertEqual(f.state['commands'][0]['elapsedSeconds'],30.25)
            self.assertEqual(f.state['commands'][0]['state'],'completed')
            self.assertEqual(len(f.calls),1)

    def test_postboot_inventory_timeout_is_terminal_without_retry(self):
        f=Fake();f.failure=('confirm_fixture_boot',{'returncode':None,'timedOut':True})
        with self.assertRaisesRegex(F.FixtureError,'^command_timeout_outcome_uncertain$'):
            f.fixture.prepare()
        self.assertFalse(f.state['admitted'])
        self.assertEqual(f.calls[-1],(['/usr/bin/xcrun','simctl','list','--json'],180))
        self.assertEqual(sum(x['operation']=='confirm_fixture_boot' for x in f.state['commands']),1)
        before=len(f.calls)
        with self.assertRaises(F.FixtureError):f.fixture.prepare()
        with self.assertRaises(F.FixtureError):f.fixture.cleanup(lambda:{})
        self.assertEqual(len(f.calls),before)

    def test_postboot_inventory_keeps_fresh_identity_and_product_guards(self):
        for change,category in [('name','fixture_boot_identity_mismatch'),
                ('runtime','fixture_boot_identity_mismatch'),
                ('source_state','fixture_boot_identity_mismatch'),
                ('products','test_products_changed')]:
            f=Fake();original_run=f.run
            def changed_run(argv,timeout):
                if f.saved[-1]['commands'][-1]['operation']=='confirm_fixture_boot':
                    if change=='name':f.devices[NEW]['name']='Changed name'
                    elif change=='runtime':f.changed_runtime=True
                    elif change=='source_state':f.devices[OLD]['state']='Booted'
                    else:f.fingerprint['filesSHA256']='d'*64
                return original_run(argv,timeout)
            f.fixture.run=changed_run
            with self.subTest(change=change),self.assertRaisesRegex(F.FixtureError,'^'+category+'$'):
                f.fixture.prepare()
            self.assertFalse(f.state['admitted'])

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

    def test_product_fingerprint_changes_and_rejects_absolute_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory);(p/'Info.plist').write_text('fixture');(p/'test.xctestrun').write_text('fixture')
            before=F.product_fingerprint(p);(p/'test.xctestrun').write_text('changed')
            self.assertNotEqual(before,F.product_fingerprint(p))
            (p/'link').symlink_to(p/'Info.plist')
            with self.assertRaises(F.FixtureError):F.product_fingerprint(p)


class PortableProductFingerprintTests(unittest.TestCase):
    def product(self, root):
        (root/'Info.plist').write_bytes(b'portable product')
        (root/'Tests/0').mkdir(parents=True)
        (root/'Tests/0/Wander.xctestrun').write_bytes(b'unchanged configuration')
        binary=root/'Binaries/0/Debug-iphonesimulator/Wander.app/Wander'
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b'unchanged native binary')
        alias=root/'Tests/0/Debug-iphonesimulator'
        alias.symlink_to('../../Binaries/0/Debug-iphonesimulator')
        return alias,binary

    def test_xcode_portable_directory_alias_is_admitted_without_following_it(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);alias,binary=self.product(root)
            # This real Xcode layout was rejected as product_directory_symlink
            # before the compatibility repair. Only the three real files count.
            original=Path.open;opened=[]
            def record(path,*args,**kwargs):
                opened.append(path)
                return original(path,*args,**kwargs)
            with mock.patch.object(Path,'open',record):result=F.product_fingerprint(root)
            self.assertEqual(result['fileCount'],3)
            self.assertEqual(result['bytes'],sum(path.stat().st_size for path in opened))
            self.assertEqual(len(opened),len(set(opened)))
            self.assertEqual(set(opened),{root/'Info.plist',root/'Tests/0/Wander.xctestrun',binary})
            self.assertEqual(set(result['configurationSHA256']),{'Info.plist','Tests/0/Wander.xctestrun'})
            self.assertTrue(alias.is_symlink())

    def test_link_identity_and_target_bytes_both_affect_fingerprint(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);alias,binary=self.product(root)
            first=F.product_fingerprint(root)
            alias.unlink();alias.symlink_to('../../Binaries/0/./Debug-iphonesimulator')
            second=F.product_fingerprint(root)
            self.assertNotEqual(first['filesSHA256'],second['filesSHA256'])
            self.assertEqual(first['bytes'],second['bytes'])
            binary.write_bytes(b'changed native binary')
            self.assertNotEqual(second['filesSHA256'],F.product_fingerprint(root)['filesSHA256'])

    def test_fingerprint_is_relocation_independent(self):
        with tempfile.TemporaryDirectory() as left,tempfile.TemporaryDirectory() as right:
            self.product(Path(left));self.product(Path(right))
            self.assertEqual(F.product_fingerprint(Path(left)),F.product_fingerprint(Path(right)))

    def test_bounded_internal_file_and_directory_link_chains_are_supported(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);self.product(root)
            (root/'binary-alias').symlink_to('Tests/0/Debug-iphonesimulator/Wander.app/Wander')
            (root/'chained-alias').symlink_to('binary-alias')
            self.assertEqual(F.product_fingerprint(root)['fileCount'],3)

    def test_invalid_links_fail_before_any_file_content_read(self):
        cases={
            'escape':('../outside', 'product_link_escape'),
            'absolute':('/outside', 'invalid_product_link_target'),
            'dangling':('missing', 'product_link_dangling'),
            'file_as_directory':('Info.plist/child', 'invalid_product_link_target'),
            'self_cycle':('bad-link', 'product_link_cycle'),
            'ancestor_cycle':('.', 'product_link_cycle'),
        }
        for name,(target,category) in cases.items():
            with self.subTest(name=name),tempfile.TemporaryDirectory() as directory:
                root=Path(directory);self.product(root);(root/'bad-link').symlink_to(target)
                with mock.patch.object(Path,'open',side_effect=AssertionError('content read before admission')):
                    with self.assertRaisesRegex(F.FixtureError,'^'+category+'$'):
                        F.product_fingerprint(root)

    def test_nested_escape_and_multi_link_cycles_are_rejected_before_reads(self):
        for cycle in [False,True]:
            with self.subTest(cycle=cycle),tempfile.TemporaryDirectory() as directory:
                root=Path(directory);self.product(root)
                (root/'first').symlink_to('second')
                (root/'second').symlink_to('first' if cycle else '../outside')
                with mock.patch.object(Path,'open',side_effect=AssertionError('foreign content read')):
                    with self.assertRaisesRegex(F.FixtureError,'product_link_cycle' if cycle else 'product_link_escape'):
                        F.product_fingerprint(root)

    def test_cross_directory_alias_cycle_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);self.product(root)
            (root/'A').mkdir();(root/'B').mkdir()
            (root/'A/to-b').symlink_to('../B');(root/'B/to-a').symlink_to('../A')
            with mock.patch.object(Path,'open',side_effect=AssertionError('content read before admission')):
                with self.assertRaisesRegex(F.FixtureError,'product_link_cycle'):F.product_fingerprint(root)

    def test_nonregular_link_target_is_rejected_before_any_content_read(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);self.product(root)
            os.mkfifo(root/'fifo');(root/'bad-link').symlink_to('fifo')
            with mock.patch.object(Path,'open',side_effect=AssertionError('nonregular content read')):
                with self.assertRaisesRegex(F.FixtureError,'invalid_product_file'):F.product_fingerprint(root)

    def test_link_count_and_resolution_depth_are_bounded(self):
        for count,chain,category in [(257,False,'products_link_limit'),(65,True,'product_link_depth_limit')]:
            with self.subTest(category=category),tempfile.TemporaryDirectory() as directory:
                root=Path(directory);self.product(root)
                for i in range(count):
                    target='link%03d'%(i+1) if chain and i+1<count else 'Info.plist'
                    (root/('link%03d'%i)).symlink_to(target)
                with self.assertRaisesRegex(F.FixtureError,category):F.product_fingerprint(root)


if __name__=='__main__':unittest.main()
