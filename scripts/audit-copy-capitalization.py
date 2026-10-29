#!/usr/bin/env python3
"""Count changed copy word occurrences against a Git base, excluding tests/generated files.

Only literal text is counted: Swift interpolation expressions are parsed as code.
Each occurrence counts, including repeated copy. Runtime formatting has no finite
rendered-word count and is deliberately reported separately from this source count.
"""
import argparse
import difflib
import json
import re
import subprocess
from pathlib import Path

OPEN_STRING = re.compile(r'(#{0,8})("""|")')
WORDS = re.compile(r"[^\W\d_]+(?:['’][^\W\d_]+)*", re.UNICODE)


def literal_segments(source):
    segments = []

    def code(index, interpolation=False):
        depth = 1
        while index < len(source):
            if source.startswith('//', index):
                end = source.find('\n', index)
                index = len(source) if end == -1 else end
                continue
            if source.startswith('/*', index):
                comments = 1
                index += 2
                while index < len(source) and comments:
                    if source.startswith('/*', index):
                        comments += 1
                        index += 2
                    elif source.startswith('*/', index):
                        comments -= 1
                        index += 2
                    else:
                        index += 1
                continue
            opening = OPEN_STRING.match(source, index)
            if opening:
                index = string(opening)
                continue
            if interpolation:
                if source[index] == '(':
                    depth += 1
                elif source[index] == ')':
                    depth -= 1
                    if not depth:
                        return index + 1
            index += 1
        return index

    def string(opening):
        hashes, quotes = opening.groups()
        closing = quotes + hashes
        escape = '\\' + hashes
        index = start = opening.end()
        while index < len(source):
            if source.startswith(closing, index):
                segments.append((start, source[start:index]))
                return index + len(closing)
            if source.startswith(escape + '(', index):
                segments.append((start, source[start:index]))
                index = code(index + len(escape) + 1, True)
                start = index
            elif source.startswith(escape, index):
                index += len(escape) + 1
            else:
                index += 1
        raise ValueError('Unterminated Swift string')

    code(0)
    return [text for _, text in sorted(segments)]


def tokens(text):
    text = re.sub(r'\\(?:u\{[^}]*\}|[nrt0])|%[-+0-9.*]*[a-zA-Z@]', ' ', text)
    return WORDS.findall(text)


def count_changes(before, after):
    old, new = tokens(before), tokens(after)
    if len(old) != len(new) or any(a.casefold() != b.casefold() for a, b in zip(old, new)):
        raise ValueError('Literal change includes more than capitalization')
    return sum(a != b for a, b in zip(old, new))


def git(*args):
    return subprocess.check_output(['git', *args], text=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', default='HEAD')
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()
    root = Path(git('rev-parse', '--show-toplevel').strip())
    files = {}
    problems = []
    added_segments = {}
    for path in git('diff', '--name-only', '--diff-filter=M', args.base).splitlines():
        is_swift = path.startswith('Wander') and path.endswith('.swift') and 'Tests/' not in path
        if not is_swift and path != 'project.yml':
            continue
        old = git('show', f'{args.base}:{path}')
        new = (root / path).read_text()
        if is_swift:
            before, after = literal_segments(old), literal_segments(new)
        else:
            pattern = r'^\s+(?:NS\w+UsageDescription|CFBundleDisplayName): (.*)$'
            before = re.findall(pattern, old, re.MULTILINE)
            after = re.findall(pattern, new, re.MULTILINE)
        pairs = list(zip(before, after))
        if len(before) != len(after):
            # Presentation branches may add literals while retaining every old
            # literal. Align case-insensitively; never silently ignore deletions
            # or changes in wording. New copy has no changed-word baseline.
            matcher = difflib.SequenceMatcher(None, [s.casefold() for s in before],
                                             [s.casefold() for s in after], autojunk=False)
            pairs = []
            unmatched = False
            for tag, i, j, k, l in matcher.get_opcodes():
                if tag == 'equal':
                    pairs.extend(zip(before[i:j], after[k:l]))
                elif tag == 'insert':
                    added_segments[path] = added_segments.get(path, 0) + l - k
                else:
                    unmatched = True
            if unmatched:
                problems.append(f'{path}: existing literal structure changed; review separately')
                continue
        try:
            count = sum(count_changes(a, b) for a, b in pairs if a != b)
        except ValueError as error:
            problems.append(f'{path}: {error}')
            continue
        if count:
            files[path] = count
    result = {'changed_word_occurrences': sum(files.values()), 'files_with_copy_changes': len(files),
              'files': files, 'added_literal_segments_excluded': added_segments, 'review_required': problems}
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(f'{result["changed_word_occurrences"]:,} changed word occurrences in {len(files)} files')
        for problem in problems:
            print(problem)
    return bool(problems)


if __name__ == '__main__':
    raise SystemExit(main())
