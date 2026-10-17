"""Bounded PID identity and static stack curator reused from V45. No import-time IO."""
from pathlib import Path
from collections import Counter
import ctypes, errno, hashlib, json, os, re, stat, time
MAX_PROFILE = 16 * 1024 * 1024
MAX_SAMPLE_OUTPUT = 1024 * 1024
MAX_SAMPLE_LINE = 4096


class SampleOutput:
    """Consume bounded output; retain only counts, hashes and one fixed phase."""
    COMPLETED = b'Sampling completed, processing symbols...'
    DENIALS = (b'permission denied', b'operation not permitted',
               b'cannot examine process', b'not permitted to sample')

    def __init__(self):
        self.counts = dict.fromkeys(('stdout', 'stderr'), 0)
        self.hashes = {k: hashlib.sha256() for k in self.counts}
        self.pending = {k: bytearray() for k in self.counts}
        self.tails = {k: b'' for k in self.counts}
        self.completed_at = None
        self.completed_lines = 0
        self.other_lines = 0

    def line(self, channel, line, observed):
        if channel == 'stderr' and line.rstrip(b'\r') == self.COMPLETED:
            self.completed_lines += 1
            if self.completed_at is None: self.completed_at = observed
        else:
            self.other_lines += 1

    def feed(self, channel, data, observed):
        need(channel in self.counts and isinstance(data, bytes), 'sample_output_type')
        need(sum(self.counts.values()) + len(data) <= MAX_SAMPLE_OUTPUT, 'sample_output_bound')
        self.counts[channel] += len(data); self.hashes[channel].update(data)
        lower = self.tails[channel] + data.lower()
        if any(term in lower for term in self.DENIALS):
            raise PermissionError('sample_permission_denied')
        self.tails[channel] = lower[-(max(map(len, self.DENIALS)) - 1):]
        pieces = data.split(b'\n')
        for index, piece in enumerate(pieces):
            need(len(self.pending[channel]) + len(piece) <= MAX_SAMPLE_LINE, 'sample_line_bound')
            self.pending[channel].extend(piece)
            if index < len(pieces) - 1:
                self.line(channel, bytes(self.pending[channel]), observed)
                self.pending[channel].clear()

    def eof(self, channel, observed):
        if self.pending[channel]:
            self.line(channel, bytes(self.pending[channel]), observed)
            self.pending[channel].clear()

    def receipt(self):
        return {'stdoutBytes': self.counts['stdout'], 'stderrBytes': self.counts['stderr'],
                'stdoutSHA256': self.hashes['stdout'].hexdigest(),
                'stderrSHA256': self.hashes['stderr'].hexdigest(),
                'recognizedCompletionLines': self.completed_lines,
                'samplingCompletedObservedUptime': self.completed_at,
                'otherLines': self.other_lines, 'rawOutputSaved': False}


def sample_interval(sample, markers):
    """The observed phase is an upper bound, never an inferred sample duration."""
    begin, draw = markers.get('ready-began'), markers.get('first-ready-draw')
    gate, snapshot = markers.get('ready-ended'), markers.get('first-snapshot')
    output = (sample or {}).get('output', {})
    completed = output.get('samplingCompletedObservedUptime')
    reason = 'sampling_completion_phase_unverified'
    verified = False
    if sample and completed is not None and output.get('recognizedCompletionLines') == 1:
        reason = 'readiness_boundary_unverified'
        if begin and draw and gate:
            end = min(m['systemUptime'] for m in (gate, snapshot) if m)
            verified = (begin['systemUptime'] <= draw['systemUptime'] <= sample['startUptime']
                        <= completed <= end)
            reason = 'verified_observed_upper_bound' if verified else 'sampling_completion_not_before_boundary'
    return {'verified': verified, 'reason': reason,
            'acquisitionStartLowerBoundUptime': (sample or {}).get('startUptime'),
            'acquisitionEndUpperBoundUptime': completed,
            'boundSource': 'observed exact stderr completion line',
            'requestedDurationUsedAsEvidence': False,
            'reportCompletionUsedAsAcquisitionEnd': False}

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
