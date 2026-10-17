import importlib.util
from contextlib import contextmanager
import json
from pathlib import Path
import plistlib
import os
import stat
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('stage', Path(__file__).with_name('replay-stage-diagnostic.py'))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)


class StageTests(unittest.TestCase):
    def sdk_fixture(self, root):
        sdk=root/'ReplayPackages/checkouts/posthog-ios'
        originals={p:('original-'+str(i)).encode() for i,p in enumerate(m.FILES)}
        for name,data in originals.items():
            path=sdk/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
        return sdk, originals, {p:b'patched-'+data for p,data in originals.items()}

    @contextmanager
    def simulated_modes(self, initial=0o444):
        # These tests NEVER call chmod/fchmod or change actual filesystem modes.
        real_fstat=os.fstat; modes={}; calls=[]
        def fstat(fd):
            value=real_fstat(fd); key=(value.st_dev,value.st_ino)
            mode=modes.setdefault(key,initial)
            return SimpleNamespace(st_dev=value.st_dev,st_ino=value.st_ino,st_uid=value.st_uid,
                st_nlink=value.st_nlink,st_mode=stat.S_IFMT(value.st_mode)|mode)
        def fchmod(fd, mode):
            value=real_fstat(fd);key=(value.st_dev,value.st_ino)
            calls.append((key,mode));modes[key]=mode
        with patch.object(m.os,'fstat',side_effect=fstat), patch.object(m.os,'fchmod',side_effect=fchmod):
            yield calls,modes

    def test_only_owner_write_is_temporary_and_original_modes_restored(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp).resolve();sdk,before,after=self.sdk_fixture(root)
            actual={p:stat.S_IMODE((sdk/p).stat().st_mode) for p in before}
            m.admit_patch_paths(sdk,root);record={}
            with self.simulated_modes() as (calls,modes):
                m.apply_source_patch(sdk,before,after,record)
            self.assertEqual([mode for _,mode in calls],[0o644,0o644,0o444,0o444])
            self.assertTrue(all(value==0o444 for value in modes.values()))
            self.assertTrue(all(value['restored'] for value in record['sourceModes'].values()))
            self.assertEqual(actual,{p:stat.S_IMODE((sdk/p).stat().st_mode) for p in before})
            self.assertEqual({p:(sdk/p).read_bytes() for p in before},after)

    def test_write_failure_restores_modes_and_preserves_original_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            sdk,before,after=self.sdk_fixture(Path(tmp).resolve());record={};real_write=os.write;count=0
            def write(fd,data):
                nonlocal count
                count+=1
                if count==2: raise PermissionError('synthetic write denial')
                return real_write(fd,data)
            with self.simulated_modes() as (calls,modes), patch.object(m.os,'write',side_effect=write):
                with self.assertRaisesRegex(PermissionError,'synthetic'):
                    m.apply_source_patch(sdk,before,after,record)
            self.assertEqual([mode for _,mode in calls],[0o644,0o644,0o444,0o444])
            self.assertTrue(all(value==0o444 for value in modes.values()))
            self.assertEqual(record['modeRestorationFailed'],[])

    def test_existing_owner_write_needs_no_permission_change(self):
        with tempfile.TemporaryDirectory() as tmp:
            sdk,before,after=self.sdk_fixture(Path(tmp).resolve())
            with self.simulated_modes(0o640) as (calls,modes):m.apply_source_patch(sdk,before,after,{})
            self.assertEqual(calls,[]);self.assertEqual(set(modes.values()),{0o640})

    def test_permission_denial_stops_without_retry_or_source_write(self):
        with tempfile.TemporaryDirectory() as tmp:
            sdk,before,after=self.sdk_fixture(Path(tmp).resolve())
            with self.simulated_modes(), patch.object(m.os,'fchmod',side_effect=PermissionError('synthetic')) as change:
                with self.assertRaises(PermissionError):m.apply_source_patch(sdk,before,after,{})
            self.assertEqual(change.call_count,1)
            self.assertEqual({p:(sdk/p).read_bytes() for p in before},before)

    def test_changed_bytes_fail_before_any_permission_change(self):
        with tempfile.TemporaryDirectory() as tmp:
            sdk,before,after=self.sdk_fixture(Path(tmp).resolve());(sdk/list(before)[1]).write_bytes(b'drift')
            with self.simulated_modes() as (calls,_):
                with self.assertRaisesRegex(ValueError,'changed_before'):m.apply_source_patch(sdk,before,after,{})
            self.assertEqual(calls,[])

    def test_wrong_scope_symlink_and_foreign_owner_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp).resolve();sdk,before,_=self.sdk_fixture(root)
            with self.assertRaisesRegex(ValueError,'exact_disposable'):m.admit_patch_paths(sdk,root/'wrong')
            path=sdk/list(before)[0];path.unlink();path.symlink_to(sdk/list(before)[1])
            with self.assertRaisesRegex(ValueError,'source_type'):m.admit_patch_paths(sdk,root)
            path.unlink();path.write_bytes(before[list(before)[0]])
            real_lstat=Path.lstat
            def lstat(p):
                value=real_lstat(p)
                if p==path:return SimpleNamespace(st_mode=value.st_mode,st_uid=os.getuid()+1,st_nlink=value.st_nlink)
                return value
            with patch.object(Path,'lstat',lstat):
                with self.assertRaisesRegex(ValueError,'source_type'):m.admit_patch_paths(sdk,root)

    def test_patch_rejects_wrong_pinned_bytes(self):
        with self.assertRaisesRegex(ValueError, 'hash'):
            m.patched_sources({p:b'wrong' for p in m.FILES}, '')

    def test_replacement_requires_unique_anchor(self):
        for value in ('none', 'xx'):
            with self.assertRaises(ValueError): m.once(value, 'x', 'y')

    def test_no_local_SDK_mutation_admitted(self):
        with patch.dict(m.os.environ, {'GITHUB_ACTIONS':'false','RUNNER_TEMP':'/tmp'}):
            with self.assertRaises(ValueError): m.owned(Path('/tmp/checkout'))

    def test_argument_restores_exact_bytes_on_exception(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); config=root/'run.xctestrun'
            doc={'WanderTests':{'BlueprintName':'WanderTests','CommandLineArguments':['original']}}
            raw=plistlib.dumps(doc);config.write_bytes(raw)
            (root/'Info.plist').write_bytes(plistlib.dumps({'Tests':[{'xctestrun':config.name}]}))
            with self.assertRaisesRegex(RuntimeError, 'native'):
                with m.diagnostic_argument(root,'00000000-0000-0000-0000-000000000001',root/'receipt.json'):
                    args=plistlib.loads(config.read_bytes())['WanderTests']['CommandLineArguments']
                    self.assertEqual(args[:2],['original',m.FLAG])
                    raise RuntimeError('native')
            self.assertEqual(config.read_bytes(),raw)
            self.assertTrue(json.loads((root/'receipt.json').read_text())['restored'])

    def native(self, failed=False):
        status='Failed' if failed else 'Passed'
        counts={'totalTestCount':1,'passedTests':int(not failed),'failedTests':int(failed),'skippedTests':0,'expectedFailures':0}
        summary={'result':status,**counts,'devicesAndConfigurations':[{'device':{'deviceId':'ABC'},**counts}]}
        tests={'nodeType':'Test Case','nodeIdentifierURL':'test://com.apple.xcode/Wander/'+m.METHOD,'result':status}
        return summary,tests

    def test_native_failure_remains_failure(self):
        summary,tests=self.native(True)
        self.assertEqual(m.native_accounting(summary,tests,65,'ABC')['result'],'Failed')

    def test_wrong_native_case_and_skip_rejected(self):
        summary,tests=self.native();tests['nodeIdentifierURL']+='Wrong'
        with self.assertRaises(ValueError):m.native_accounting(summary,tests,0,'ABC')
        summary,tests=self.native();summary['skippedTests']=1
        with self.assertRaises(ValueError):m.native_accounting(summary,tests,0,'ABC')

    def fixture(self, root, failed=0):
        row={'stage':1,'sequence':1,'frame':1,'uptime':1.5,'epoch':2.5,'pid':123,'image':False,'width':0,'height':0}
        footer={'attempted':1,'written':1,'failed':failed,'capped':0,'closed':True,'pid':123,'uptime':3.5}
        (root/'001.json').write_text(json.dumps(row));(root/'footer.json').write_text(json.dumps(footer))

    def test_nil_image_is_retained_without_false_acceptance(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);self.fixture(root);result=m.stage_records(root)
            self.assertFalse(result['rows'][0]['image']);self.assertFalse(result['acceptanceClaimed'])

    def test_recorder_failure_not_misclassified_as_stall(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);self.fixture(root,1)
            result=m.stage_records(root)
            self.assertFalse(result['recorderComplete']);self.assertEqual(len(result['rows']),1)

    def test_missing_footer_preserves_scalar_evidence_as_gap(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);self.fixture(root);(root/'footer.json').unlink()
            result=m.stage_records(root)
            self.assertFalse(result['recorderComplete']);self.assertEqual(len(result['rows']),1)

    def test_extra_payload_or_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);self.fixture(root)
            p=root/'001.json';value=json.loads(p.read_text());value['private']='forbidden';p.write_text(json.dumps(value))
            with self.assertRaisesRegex(ValueError,'schema'):m.stage_records(root)
            p.unlink();p.symlink_to(root/'footer.json')
            with self.assertRaisesRegex(ValueError,'bound'):m.stage_records(root)

    def test_leading_middle_and_trailing_gaps_preserve_valid_rows(self):
        for missing in (1,2,3):
            with self.subTest(missing=missing), tempfile.TemporaryDirectory() as tmp:
                root=Path(tmp);self.fixture(root)
                row=json.loads((root/'001.json').read_text());(root/'001.json').unlink()
                for sequence in range(1,4):
                    if sequence != missing:
                        (root/f'{sequence:03d}.json').write_text(json.dumps({**row,'sequence':sequence}))
                footer=json.loads((root/'footer.json').read_text())
                (root/'footer.json').write_text(json.dumps({**footer,'attempted':3,'written':2,'failed':1}))
                result=m.stage_records(root)
                self.assertEqual(result['missingSequences'],[missing])
                self.assertEqual(len(result['rows']),2)
                self.assertFalse(result['recorderComplete'])

    def test_filename_sequence_mismatch_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);self.fixture(root);(root/'001.json').rename(root/'002.json')
            with self.assertRaisesRegex(ValueError,'values'):m.stage_records(root)


if __name__=='__main__': unittest.main()
