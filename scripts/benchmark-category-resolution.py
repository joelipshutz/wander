#!/usr/bin/env python3
"""Compare actual classifier sources and results on this Mac, not device FPS.

python3 scripts/benchmark-category-resolution.py --baseline 1666093fb
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
path = 'Wander/Services/WanderPlaceCategory.swift'
before = subprocess.check_output(['git', 'show', f'{args.baseline}:{path}'], cwd=root, text=True)
after = (root / path).read_text()


def classifier(source):
    # Retain the actual assignment, taxonomy, normalization, and inference code.
    # Omit unrelated UI/LocalPlace conveniences so the host harness needs only MapKit.
    source = source[:source.index('enum PlaceMemoryAttributeKeys')] + source[source.index('struct PlaceCategoryTaxonomyEntry'):]
    for start, end in [
        ('    static func restaurantCuisineInference(for candidate:', '    private static func cuisineAliasGuess'),
        ('    static func emoji(', '    static func broadEmoji'),
    ]:
        a = source.index(start)
        b = source.index(end, a)
        source = source[:a] + source[b:]
    return source


runner = r'''
@main struct Benchmark {
    static func main() throws {
        let coldStart = ContinuousClock.now
        _ = PlaceCategoryAssignment(primaryCategory: "restaurants_food", subcategory: "Thai",
                                    rawProviderType: "thai_restaurant")
        let cold = coldStart.duration(to: .now).components
        var inputs = ["", " \n ", "Café & thé", "東京 レストラン", "İstanbul", "１２３", "🏞️",
                      "unknown category", "coffee & restaurant", "custom taco restaurant bar"]
        for entry in WanderPlaceCategory.taxonomy {
            for value in [entry.id, entry.group] + entry.aliases + entry.subcategories {
                inputs += [value, value.uppercased(), " \t" + value + "\n", "nearby " + value + " place"]
            }
        }
        inputs += WanderPlaceCategory.supportedMapKitProviderTypes
        let sources = ["provider", "deterministic", "ai", "user", "snapshot", "consensus", "legacy", "unknown"]
        var outputs: [[String]] = []
        for input in inputs {
            for source in sources {
                let value = PlaceCategoryAssignment(primaryCategory: "restaurants_food", subcategory: input,
                                                    source: source, rawProviderType: input)
                outputs.append([input, source, value.primaryCategory, value.subcategory ?? "",
                                WanderPlaceCategory.primaryCategory(for: input),
                                WanderPlaceCategory.broadCategory(for: input)])
            }
        }
        let data = try JSONEncoder().encode(outputs)
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        let cases = ["thai_restaurant", "park", "coffee_shop", "hospital", "shopping", "mkpoicategorymuseum",
                     "italian_restaurant", "custom category", "coffee_tea_sweets", "hotel"]
        var samples: [Double] = []
        var checksum = 0
        for _ in 0..<5 {
            let start = ContinuousClock.now
            for index in 0..<1_500 {
                let input = cases[index % cases.count]
                let value = PlaceCategoryAssignment(primaryCategory: "restaurants_food", subcategory: input,
                                                    source: "legacy", rawProviderType: input)
                checksum += value.primaryCategory.utf8.count + (value.subcategory?.utf8.count ?? 0)
            }
            let elapsed = start.duration(to: .now).components
            samples.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
        }
        let result: [String: Any] = ["samples_ms": samples, "checksum": checksum, "cases": outputs.count,
            "first_assignment_ms": Double(cold.seconds) * 1_000 + Double(cold.attoseconds) / 1e15]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''

results = {}
with tempfile.TemporaryDirectory(prefix='rec484-category-') as temporary:
    directory = Path(temporary)
    for label, source in [('before', before), ('after', after)]:
        swift = directory / f'{label}.swift'
        swift.write_text(classifier(source) + runner)
        executable = directory / label
        subprocess.run(['xcrun', 'swiftc', '-O', '-parse-as-library', '-module-cache-path', str(directory / 'modules'),
                        str(swift), '-o', str(executable)], check=True)
        results[label] = json.loads(subprocess.check_output([str(executable), str(directory / f'{label}.json')], text=True))
        results[label]['median_ms'] = statistics.median(results[label]['samples_ms'])
    old_outputs = json.loads((directory / 'before.json').read_text())
    new_outputs = json.loads((directory / 'after.json').read_text())
    if old_outputs != new_outputs:
        differences = [(old, new) for old, new in zip(old_outputs, new_outputs) if old != new]
        raise SystemExit(f'Classification changed: {differences[:5]}')
    assert results['before']['checksum'] == results['after']['checksum']
results['equivalent_cases'] = len(old_outputs)
results['improvement_percent'] = 100 * (1 - results['after']['median_ms'] / results['before']['median_ms'])
results['method'] = 'macOS Swift -O, actual classifier code; 5 samples of 1,500 assignments; not iOS startup or FPS.'
print(json.dumps(results, indent=2))
