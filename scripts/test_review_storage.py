"""Behavioral checks for shared evidence recovery and repository size enforcement."""
import copy
from concurrent.futures import ThreadPoolExecutor
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(file))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


media = load('review_media', 'review-media.py')
guard = load('review_guard', 'check-review-storage.py')


class RepositoryTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name) / 'repo'
        self.repo.mkdir()
        patch = mock.patch.dict(os.environ, {'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': os.devnull})
        patch.start()
        self.addCleanup(patch.stop)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.test')
        self.git('config', 'core.hooksPath', os.devnull)

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], stderr=subprocess.PIPE)

    def write(self, name, data):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def commit(self):
        self.git('add', '.')
        self.git('commit', '-qm', 'Fixture')
        return self.git('rev-parse', 'HEAD').decode().strip()


class ArchiveTests(RepositoryTest):
    def setUp(self):
        super().setUp()
        self.prefix = 'docs/designs/archive'
        self.payload = b'fictional movie' * 100
        self.sha = hashlib.sha256(self.payload).hexdigest()
        pointer = f'version https://git-lfs.github.com/spec/v1\noid sha256:{self.sha}\nsize {len(self.payload)}\n'.encode()
        self.write(self.prefix + '/review/index.html', b'<html>Archived fixture</html>')
        self.write(self.prefix + '/review/movie.mp4', pointer)
        source = self.commit()
        rows = []
        for name, data, lfs in [('review/index.html', b'<html>Archived fixture</html>', False),
                                ('review/movie.mp4', self.payload, True)]:
            oid = self.git('rev-parse', 'HEAD:' + self.prefix + '/' + name).decode().strip()
            rows.append(dict(path=name, git_blob=oid, sha256=hashlib.sha256(data).hexdigest(),
                             bytes=len(data), lfs=lfs, mode='100644'))
        self.manifest = dict(format=1, id='fixture', source_commit=source, source_prefix=self.prefix,
                             entry='review/index.html', files=rows)
        self.objects = self.repo / '.git/lfs/objects'
        self.object = self.objects / self.sha[:2] / self.sha[2:4] / self.sha
        self.object.parent.mkdir(parents=True)
        self.object.write_bytes(self.payload)
        original_git = media.git

        def fixture_git(repo, *args):
            if args == ('lfs', 'env'):
                return ('LocalMediaDir=' + str(self.objects) + '\n').encode()
            return original_git(repo, *args)

        patch = mock.patch.object(media, 'git', fixture_git)
        patch.start()
        self.addCleanup(patch.stop)
        self.archive = media.Archive(self.repo, self.manifest)

    def test_restore_hashes_and_reuse_across_worktrees(self):
        self.assertEqual(self.archive.prepare(), 2)
        self.assertEqual(self.archive.verify(), 2)
        self.assertEqual(self.archive.prepare(), 0)
        other = Path(self.tmp.name) / 'second'
        self.git('worktree', 'add', '-qb', 'second', str(other))
        sibling = media.Archive(other, self.manifest)
        self.assertEqual(sibling.root, self.archive.root)
        self.assertEqual(sibling.prepare(), 0)
        movie = self.archive.root / 'review/movie.mp4'
        self.assertEqual(movie.read_bytes(), self.payload)
        self.assertNotEqual(movie.stat().st_ino, self.object.stat().st_ino)
        self.assertEqual(movie.stat().st_nlink, 1)

    def test_changed_archive_is_not_overwritten(self):
        self.archive.prepare()
        movie = self.archive.root / 'review/movie.mp4'
        movie.chmod(0o600)
        movie.write_bytes(b'new user changes')
        with self.assertRaisesRegex(ValueError, 'refusing to overwrite'):
            self.archive.prepare()
        self.assertEqual(movie.read_bytes(), b'new user changes')

    def test_corrupt_object_never_installs(self):
        self.object.write_bytes(b'corrupt')
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            self.archive.prepare()
        self.assertFalse((self.archive.root / 'review/movie.mp4').exists())
        self.assertFalse(list(self.archive.root.rglob('.restoring-*')))

    def test_missing_object_is_offline_by_default(self):
        self.object.unlink()
        with self.assertRaisesRegex(ValueError, 'LFS objects missing'):
            self.archive.prepare()

    def test_manifest_must_match_pinned_tree(self):
        changed = copy.deepcopy(self.manifest)
        changed['files'][0]['git_blob'] = 'a' * 40
        with self.assertRaisesRegex(ValueError, 'pinned historical tree'):
            media.Archive(self.repo, changed).prepare()

    def test_path_traversal_is_rejected(self):
        for path in ['../escape', '/absolute', 'a/../../escape', 'a\\escape']:
            changed = copy.deepcopy(self.manifest)
            changed['files'][0]['path'] = path
            with self.assertRaises(ValueError):
                media.Archive(self.repo, changed)

    def test_symlink_cache_is_rejected(self):
        self.archive.root.parent.mkdir(parents=True)
        outside = Path(self.tmp.name) / 'outside'
        outside.mkdir()
        self.archive.root.symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'Symlink'):
            self.archive.prepare()
        self.assertEqual(list(outside.iterdir()), [])

    def test_partial_restore_resumes(self):
        self.archive.prepare()
        (self.archive.root / 'review/movie.mp4').unlink()
        self.assertEqual(self.archive.prepare(), 1)
        self.assertEqual(self.archive.verify(), 2)

    def test_concurrent_preparation_reuses_one_archive(self):
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: self.archive.prepare(), range(2)))
        self.assertEqual(sorted(results), [0, 2])
        self.assertEqual(self.archive.verify(), 2)


class GuardTests(RepositoryTest):
    def setUp(self):
        super().setUp()
        self.write('README.md', b'Fixture')
        self.base = self.commit()

    def errors(self):
        self.commit()
        return guard.inspect(self.repo, self.base)

    def test_lfs_declared_size_is_enforced(self):
        pointer = b'version https://git-lfs.github.com/spec/v1\noid sha256:' + b'a' * 64 + b'\nsize 200000000\n'
        self.write('docs/final.png', pointer)
        self.assertTrue(any('1 MiB' in e for e in self.errors()))

    def test_recording_dump_is_rejected_even_if_small(self):
        self.write('docs/capture.mp4', b'small recording')
        self.assertTrue(any('shared evidence' in e for e in self.errors()))

    def test_lfs_size_cannot_be_hidden_under_an_unusual_extension(self):
        pointer = b'version https://git-lfs.github.com/spec/v1\noid sha256:' + b'a' * 64 + b'\nsize 200000000\n'
        self.write('misc/capture.bin', pointer)
        self.assertTrue(any('1 MiB' in e for e in self.errors()))

    def test_aggregate_screenshots_are_bounded(self):
        for i in range(6):
            self.write(f'docs/shot-{i}.png', b'x' * guard.FILE_LIMIT)
        self.assertTrue(any('5 MiB' in e for e in self.errors()))

    def test_large_inline_html_is_bounded(self):
        self.write('preview/board.html', b'x' * (guard.FILE_LIMIT + 1))
        self.assertTrue(any('1 MiB' in e for e in self.errors()))

    def test_small_final_evidence_and_app_media_are_allowed(self):
        self.write('docs/final.png', b'small final screenshot')
        self.write('Wander/Resources/FoundersWelcome/founders-welcome.mp4', b'required production media')
        self.assertEqual(self.errors(), [])

    def test_restored_archive_is_rejected_regardless_of_size(self):
        self.write(guard.ARCHIVE + 'review/index.html', b'old review')
        self.assertTrue(any('reintroduced' in e for e in self.errors()))

    def test_result_bundle_is_rejected(self):
        self.write('evidence/run.xcresult/Data/1', b'result')
        self.assertTrue(any('shared evidence' in e for e in self.errors()))

    def test_result_bundle_outside_evidence_directories_is_bounded(self):
        self.write('artifacts/Test.xcresult/Data/1', b'x' * (6 * guard.FILE_LIMIT))
        errors = self.errors()
        self.assertTrue(any('shared evidence' in e for e in errors))
        self.assertTrue(any('1 MiB' in e for e in errors))
        self.assertTrue(any('5 MiB' in e for e in errors))

    def test_staged_check_reads_index_not_unstaged_files(self):
        self.write('docs/final.png', b'small')
        self.git('add', '.')
        self.write('docs/final.png', b'x' * (guard.FILE_LIMIT + 1))
        self.assertEqual(guard.inspect(self.repo, self.base, staged=True), [])


if __name__ == '__main__':
    unittest.main()
