#!/usr/bin/env python3
"""Restore historical review evidence once per repository family, outside worktrees."""
import argparse
import contextlib
import ctypes
import fcntl
import functools
import hashlib
from http.server import ThreadingHTTPServer
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tempfile


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args])


def relative_name(value):
    path = PurePosixPath(value)
    if not value or path.is_absolute() or '..' in path.parts or str(path) != value or '\\' in value:
        raise ValueError('Unsafe archive path: ' + value)
    return path


def checksum(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def safe_directory(path):
    """Refuse symlink ancestors; never follow a cache path outside its location."""
    for part in reversed((path, *path.parents)):
        if part.is_symlink():
            raise ValueError('Symlink in archive directory: ' + str(part))
        part.mkdir(mode=0o700, exist_ok=True)
        if not part.is_dir():
            raise ValueError('Expected directory: ' + str(part))


class Archive:
    def __init__(self, repo, manifest):
        self.repo = Path(repo).resolve()
        self.manifest = manifest
        if manifest.get('format') != 1 or not re.fullmatch(r'[a-z0-9-]+', manifest['id']):
            raise ValueError('Invalid archive format or id')
        if not re.fullmatch(r'[a-f0-9]{40}', manifest['source_commit']):
            raise ValueError('Archive requires an immutable source commit')
        relative_name(manifest['source_prefix'])
        self.files = manifest['files']
        paths = set()
        for row in self.files:
            path = str(relative_name(row['path']))
            if path in paths or row['mode'] not in ('100644', '100755'):
                raise ValueError('Duplicate path or unsupported file mode')
            paths.add(path)
            if not re.fullmatch(r'[a-f0-9]{64}', row['sha256']) or not re.fullmatch(r'[a-f0-9]{40}', row['git_blob']):
                raise ValueError('Invalid archive checksum')
            if type(row['bytes']) is not int or row['bytes'] < 0 or type(row['lfs']) is not bool:
                raise ValueError('Invalid archive size or LFS flag')
        for path in paths:
            if any(str(parent) in paths for parent in PurePosixPath(path).parents):
                raise ValueError('Archive file/directory collision')
        if manifest['entry'] not in paths:
            raise ValueError('Entry page is not in archive')
        common = Path(git(self.repo, 'rev-parse', '--path-format=absolute', '--git-common-dir').decode().strip())
        self.common = common.resolve()
        self.base = self.common.parent.parent / '.review-media' / 'astir'
        self.root = self.base / (manifest['id'] + '-' + manifest['source_commit'][:12])

    @contextlib.contextmanager
    def lock(self):
        safe_directory(self.base)
        lock = self.base / (self.root.name + '.lock')
        fd = os.open(lock, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        try:
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
                raise ValueError('Unsafe archive lock')
            fcntl.flock(fd, fcntl.LOCK_EX)
            yield
        finally:
            os.close(fd)

    def path(self, row):
        result = self.root / row['path']
        for part in (result, *result.parents):
            if part.is_symlink():
                raise ValueError('Symlink in archive path: ' + str(part))
        return result

    def valid(self, row):
        path = self.path(row)
        return path.is_file() and path.stat().st_size == row['bytes'] and checksum(path) == row['sha256']

    def verify(self):
        failed = [row['path'] for row in self.files if not self.valid(row)]
        if failed:
            raise ValueError('Missing or changed archive files: ' + ', '.join(failed[:8]) +
                             '. Run prepare for missing files; preserve changed files before recovery.')
        return len(self.files)

    def source_tree(self, download):
        source = self.manifest['source_commit']
        try:
            git(self.repo, 'cat-file', '-e', source + '^{commit}')
        except subprocess.CalledProcessError:
            if not download:
                raise ValueError('Source commit missing; run prepare --download to fetch the pinned archive.')
            subprocess.run(['git', '-C', str(self.repo), 'fetch', '--no-tags', 'origin', source], check=True)
        prefix = self.manifest['source_prefix'] + '/'
        tree = {}
        for item in git(self.repo, 'ls-tree', '-r', '-z', source, '--', prefix).split(b'\0'):
            if item:
                metadata, name = item.split(b'\t', 1)
                mode, kind, oid = metadata.decode().split()
                name = name.decode()
                if not name.startswith(prefix) or kind != 'blob':
                    raise ValueError('Unexpected source tree entry')
                tree[name[len(prefix):]] = (mode, oid)
        expected = {r['path']: (r['mode'], r['git_blob']) for r in self.files}
        if tree != expected:
            raise ValueError('Manifest does not exactly match the pinned historical tree')

    def prepare(self, download=False):
        with self.lock():
            self.source_tree(download)
            needed = []
            for row in self.files:
                path = self.path(row)
                if path.exists():
                    if not self.valid(row):
                        raise ValueError('Existing archive file changed; refusing to overwrite: ' + row['path'])
                else:
                    needed.append(row)
            if not needed:
                return 0
            media = None
            if any(row['lfs'] for row in needed):
                env = git(self.repo, 'lfs', 'env').decode()
                values = [line.split('=', 1)[1] for line in env.splitlines() if line.startswith('LocalMediaDir=')]
                if len(values) != 1:
                    raise ValueError('Cannot locate the shared Git LFS cache')
                media = Path(values[0])
                missing = [r for r in needed if r['lfs'] and not (media / r['sha256'][:2] / r['sha256'][2:4] / r['sha256']).is_file()]
                if missing:
                    if not download:
                        raise ValueError(f'{len(missing)} LFS objects missing. Use prepare --download to fetch the pinned archive once.')
                    subprocess.run(['git', '-C', str(self.repo), 'lfs', 'fetch', 'origin',
                                    self.manifest['source_commit'], '--include=' + self.manifest['source_prefix'] + '/**',
                                    '--exclude='], check=True)
            for index, row in enumerate(needed, 1):
                target = self.path(row)
                safe_directory(target.parent)
                data = git(self.repo, 'cat-file', 'blob', row['git_blob'])
                if row['lfs']:
                    expected = ('version https://git-lfs.github.com/spec/v1\n'
                                f'oid sha256:{row["sha256"]}\nsize {row["bytes"]}\n').encode()
                    if data != expected:
                        raise ValueError('LFS pointer differs from archive manifest')
                    source = media / row['sha256'][:2] / row['sha256'][2:4] / row['sha256']
                    if not source.is_file() or source.is_symlink():
                        raise ValueError('Missing regular LFS object')
                fd, temporary = tempfile.mkstemp(prefix='.restoring-', dir=target.parent)
                os.close(fd)
                temporary = Path(temporary)
                try:
                    if row['lfs']:
                        temporary.unlink()
                        cloned = False
                        if sys.platform == 'darwin':
                            lib = ctypes.CDLL('/usr/lib/libSystem.B.dylib', use_errno=True)
                            lib.clonefile.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
                            lib.clonefile.restype = ctypes.c_int
                            cloned = lib.clonefile(os.fsencode(source), os.fsencode(temporary), 0) == 0
                        if not cloned:
                            shutil.copyfile(source, temporary)
                    else:
                        temporary.write_bytes(data)
                    if temporary.stat().st_size != row['bytes'] or checksum(temporary) != row['sha256']:
                        raise ValueError('Archive checksum mismatch: ' + row['path'])
                    temporary.chmod(0o555 if row['mode'] == '100755' else 0o444)
                    # Atomic installation without replacing a concurrent user-created file.
                    # This link exists only until the staging name is unlinked below; it
                    # never links distinct archive files or links to the LFS object.
                    os.link(temporary, target, follow_symlinks=False)
                finally:
                    temporary.unlink(missing_ok=True)
                if index % 250 == 0:
                    print(f'Restored and verified {index}/{len(needed)} archive files.', flush=True)
            return len(needed)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['path', 'prepare', 'verify', 'serve'])
    parser.add_argument('archive', nargs='?', default='onboarding-2026-09')
    parser.add_argument('--download', action='store_true', help='Allow prepare to fetch missing historical Git/LFS objects')
    parser.add_argument('--port', type=int, default=8776)
    args = parser.parse_args(argv)
    if not re.fullmatch(r'[a-z0-9-]+', args.archive):
        parser.error('Invalid archive id')
    repo = Path(__file__).resolve().parent.parent
    manifest = json.loads((repo / 'docs/review-media' / (args.archive + '.json')).read_text())
    archive = Archive(repo, manifest)
    if args.command == 'path':
        print(archive.root)
    elif args.command == 'prepare':
        print(f'One shared archive: {sum(r["bytes"] for r in archive.files)/1024**3:.2f} GiB at {archive.root}', flush=True)
        count = archive.prepare(args.download)
        print(f'Restored {count} files; existing verified files reused.')
    elif args.command == 'verify':
        print(f'Verified {archive.verify()} archive files at {archive.root}')
    else:
        archive.verify()
        server_file = archive.root / 'review/serve_review.py'
        spec = importlib.util.spec_from_file_location('historical_review_server', server_file)
        server = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(server)
        handler = functools.partial(server.ReviewHandler, directory=str(archive.root / 'review'))
        entry = str(PurePosixPath(manifest['entry']).relative_to('review'))
        print(f'Open http://127.0.0.1:{args.port}/{entry}', flush=True)
        ThreadingHTTPServer(('127.0.0.1', args.port), handler).serve_forever()


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
