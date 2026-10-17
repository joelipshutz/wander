"""Bounded PID identity and static stack curator reused from V45. No import-time IO."""
from pathlib import Path
from collections import Counter
import ctypes, errno, hashlib, json, os, re, stat, time
MAX_PROFILE = 16 * 1024 * 1024

class Gap(RuntimeError):
    pass

def need(value, code):
    if not value:
        raise Gap(code)

def bounded_bytes(path, limit):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        st = os.fstat(fd)
        need(stat.S_ISREG(st.st_mode) and st.st_size <= limit and (st.st_uid == os.getuid()), 'input_type_size_or_owner')
        raw = bytearray()
        while True:
            chunk = os.read(fd, min(65536, limit + 1 - len(raw)))
            if not chunk:
                break
            raw.extend(chunk)
            need(len(raw) <= limit, 'input_size')
        return bytes(raw)
    finally:
        os.close(fd)

class BsdInfo(ctypes.Structure):
    _fields_ = [(n, ctypes.c_uint32) for n in ('flags', 'status', 'xstatus', 'pid', 'ppid', 'uid', 'gid', 'ruid', 'rgid', 'svuid', 'svgid', 'reserved')] + [('comm', ctypes.c_char * 16), ('name', ctypes.c_char * 32)] + [(n, ctypes.c_uint32) for n in ('nfiles', 'pgid', 'jobc', 'tdev', 'tpgid')] + [('nice', ctypes.c_int32), ('start_sec', ctypes.c_uint64), ('start_usec', ctypes.c_uint64)]

def curate(raw):
    """Retain static call-tree rows only. Unknown lines are counted, never echoed."""
    need(len(raw) <= MAX_PROFILE, 'profile_size')
    text = raw.decode('utf-8', errors='replace')
    active = False
    rows = []
    stack = []
    unknown = 0
    omitted = 0
    threads = 0
    pattern = re.compile('^([ +!|:]*)(\\d+)\\s+(.+?)\\s+\\(in ([A-Za-z0-9_.+\\-]{1,80})\\)(?:\\s+\\+\\s+\\d+)?(?:\\s+\\[0x[0-9a-fA-F]+\\])?\\s*$')
    for line in text.splitlines():
        if line.strip() == 'Call graph:':
            active = True
            continue
        if active and (line.startswith('Total number in stack') or line.startswith('Sort by top') or line.startswith('Binary Images:')):
            active = False
            continue
        if not active:
            omitted += 1
            continue
        if not line.strip():
            continue
        if re.match('^[ +!|:]*\\d+\\s+Thread_', line):
            threads += 1
            stack = []
            continue
        match = pattern.fullmatch(line)
        if not match:
            unknown += 1
            continue
        symbol = match[3]
        plain = re.fullmatch('[A-Za-z_$][A-Za-z0-9_.$<>:,() ?!&*+\\-=#\\[\\]]{0,511}', symbol)
        objc = re.fullmatch('[-+]\\[[A-Za-z_$][A-Za-z0-9_.$]*(?:\\([A-Za-z0-9_.$]+\\))? [A-Za-z_$][A-Za-z0-9_$]*(?::[A-Za-z0-9_$]*)*\\]', symbol)
        if not (plain or objc) or re.search('\\b0x[0-9a-fA-F]+\\b', symbol):
            unknown += 1
            continue
        depth = len(match[1])
        count = int(match[2])
        need(0 < count < 10 ** 9 and len(rows) < 100000, 'profile_row_bound')
        while stack and stack[-1][0] >= depth:
            stack.pop()
        rows.append({'symbol': symbol, 'module': match[4], 'count': count, 'indent': depth, 'parent': stack[-1][1] if stack else None, 'threadOrdinal': threads})
        stack.append((depth, len(rows) - 1))
    totals = Counter()
    for row in rows:
        totals[row['symbol'], row['module']] += row['count']
    ordered = totals.most_common()
    selected = []
    preferences = [('webp', lambda s, m: 'webp' in (s + m).lower()), ('posthog', lambda s, m: 'posthog' in (s + m).lower()), ('layout_draw', lambda s, m: any((t in (s + m).lower() for t in ['swiftui', 'attributegraph', 'layout', 'drawhierarchy', 'uikit']))), ('wait_lock', lambda s, m: any((t in s.lower() for t in ['wait', 'lock', 'semaphore', 'mach_msg'])))]
    for (category, predicate) in preferences:
        hit = next(((key, n) for (key, n) in ordered if predicate(*key) and key not in [x[0] for x in selected]), None)
        if hit:
            selected.append((hit[0], hit[1], category))
    for (key, n) in ordered:
        if len(selected) == 8:
            break
        if key not in [x[0] for x in selected]:
            selected.append((key, n, 'count_fill'))
    return {'selectionRule': 'one representative each WebP, PostHog, UI layout/draw, wait/lock; fill by inclusive node observation count; not CPU percent', 'rawSHA256': hashlib.sha256(raw).hexdigest(), 'rawBytes': len(raw), 'rows': rows, 'retainedStaticRows': len(rows), 'unknownCallTreeLines': unknown, 'omittedNonTreeLines': omitted, 'threadHeadersCounted': threads, 'completeCallTreeClaimed': False, 'parentMeaning': 'nearest retained ancestor by indentation; unknown rows omitted', 'sampleCountsAreCPUOrRunnableTime': False, 'topSymbols': [{'symbol': s, 'module': m, 'count': n, 'category': c} for ((s, m), n, c) in selected]}
