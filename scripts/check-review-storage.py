#!/usr/bin/env python3
"""Reject review-media dumps, including the true sizes behind Git LFS pointers."""
import argparse
from pathlib import PurePosixPath
import re
import subprocess

FILE_LIMIT = 1024 * 1024
CHANGE_LIMIT = 5 * FILE_LIMIT
ARCHIVE = 'docs/designs/onboarding-2026-09/'
ARCHIVE_INDEX = {ARCHIVE + 'README.md', ARCHIVE + 'run.py'}
DUMPS = {'.mp4', '.mov', '.m4v', '.avi', '.mkv', '.webm', '.ktrace', '.trace',
         '.xcresult', '.xcarchive', '.bundle', '.zip', '.tar', '.gz', '.7z'}
IMAGES = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.heic', '.tif', '.tiff', '.pdf'}


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args])


def logical_size(data, stored_size):
    if not data.startswith(b'version https://git-lfs.github.com/spec/v1\n'):
        return stored_size
    match = re.search(rb'^size ([0-9]+)$', data, re.MULTILINE)
    if not match:
        raise ValueError('Malformed Git LFS pointer')
    return int(match[1])


def is_app_resource(path):
    return path.startswith('Wander/Resources/')


def is_review(path):
    parts = PurePosixPath(path).parts
    return (parts[0] in {'docs', 'preview', 'evidence', 'recordings', 'review-media'}
            or any(part.endswith('-evidence') for part in parts)
            or PurePosixPath(path).suffix.lower() in IMAGES | DUMPS)


def inspect(repo, base, head='HEAD', staged=False):
    if staged:
        tracked = git(repo, 'ls-files', '-z')
        changed = git(repo, 'diff', '--cached', '--no-renames', '--name-only', '--diff-filter=ACM', '-z', base, '--')
    else:
        tracked = git(repo, 'ls-tree', '-r', '--name-only', '-z', head)
        changed = git(repo, 'diff', '--no-renames', '--name-only', '--diff-filter=ACM', '-z', base, head, '--')
    errors = []
    for raw in tracked.split(b'\0'):
        path = raw.decode()
        if path.startswith(ARCHIVE) and path not in ARCHIVE_INDEX:
            errors.append('Archived payload reintroduced: ' + path)
    total = 0
    for raw in changed.split(b'\0'):
        if not raw:
            continue
        path = raw.decode()
        if is_app_resource(path):
            continue
        spec = ':' + path if staged else head + ':' + path
        size = int(git(repo, 'cat-file', '-s', spec))
        data = git(repo, 'cat-file', 'blob', spec) if size <= 1024 else b''
        if not is_review(path) and not data.startswith(b'version https://git-lfs.github.com/spec/v1\n'):
            continue
        try:
            size = logical_size(data, size)
        except ValueError as error:
            errors.append(path + ': ' + str(error))
            continue
        total += size
        if any(PurePosixPath(part).suffix.lower() in DUMPS for part in PurePosixPath(path).parts):
            errors.append('Recording/result/archive belongs in shared evidence storage: ' + path)
        if size > FILE_LIMIT:
            errors.append(f'Review file exceeds 1 MiB ({size} bytes): {path}')
    if total > CHANGE_LIMIT:
        errors.append(f'Changed review evidence totals {total} bytes; limit is 5 MiB per change.')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', default='.')
    parser.add_argument('--base', required=True)
    parser.add_argument('--head', default='HEAD')
    parser.add_argument('--staged', action='store_true')
    args = parser.parse_args()
    errors = inspect(args.repo, args.base, args.head, args.staged)
    if errors:
        raise SystemExit('\n'.join(errors[:20]) + '\nUse shared evidence and link it from docs/review-media/README.md.')
    print('Review storage check passed: no archived payload restored; changed evidence is within budget.')


if __name__ == '__main__':
    main()
