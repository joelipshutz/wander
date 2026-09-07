#!/usr/bin/env python3
"""Compare the actual old/current Swift map cache on the host (not MapKit FPS).
Run: python3 scripts/benchmark-map-projection-cache.py --baseline c520292
"""
import argparse
import json
from pathlib import Path
import statistics
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline', required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source_path = 'Wander/Features/Map/MapScreen.swift'
old_source = subprocess.check_output(['git', 'show', f'{args.baseline}:{source_path}'], cwd=root, text=True)
new_source = (root / source_path).read_text()

def cache_source(source):
    start = source.index('@MainActor\nfinal class MapRenderProjectionCache')
    end = source.index('\nenum MapSearchPerformancePolicy', start)
    return source[start:end]

runner = '''
@main struct Benchmark {
    @MainActor static func main() {
        let cache = MapRenderProjectionCache<String, Int>()
        let key = CommandLine.arguments[1]
        _ = cache.value(for: key, partition: "friends") { 7 }
        for _ in 0..<5 {
            var checksum = 0
            let start = ContinuousClock.now
            for _ in 0..<1_000_000 {
                checksum += cache.value(for: key, partition: "friends") { -1 }
            }
            let elapsed = start.duration(to: .now).components
            let milliseconds = Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
            print("\\(milliseconds),\\(checksum)")
        }
    }
}
'''
results = {}
with tempfile.TemporaryDirectory(prefix='rec441-map-cache-') as temporary:
    directory = Path(temporary)
    for label, source in [('before', old_source), ('after', new_source)]:
        swift_file = directory / f'{label}.swift'
        executable = directory / label
        swift_file.write_text('import Foundation\n' + cache_source(source) + runner)
        subprocess.run(['xcrun', 'swiftc', '-O', '-parse-as-library', '-module-cache-path', str(directory / 'module-cache'), str(swift_file), '-o', str(executable)], check=True)
        output = subprocess.check_output([str(executable), 'unchanged-fixture-projection'], text=True)
        samples = []
        for line in output.splitlines():
            milliseconds, checksum = line.split(',')
            assert int(checksum) == 7_000_000
            samples.append(float(milliseconds))
        results[label] = {'samples_ms': samples, 'median_ms': statistics.median(samples)}
results['improvement_percent'] = 100 * (1 - results['after']['median_ms'] / results['before']['median_ms'])
results['method'] = 'Actual source extracted before/after; macOS Swift -O; 1,000,000 stable reads/sample; 5 samples. Microbenchmark, not device frame time.'
print(json.dumps(results, indent=2))
