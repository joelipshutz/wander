import Foundation
import XCTest
@testable import Wander

final class ImportSnapshotTextComparisonTests: XCTestCase {
    func testExactTextComparisonMatchesUTF8ForNativeAndBridgedRepresentations() {
        let decomposed = "Cafe\u{0301}"
        let composed = "Caf\u{00E9}"
        let mutable = NSMutableString(string: "Bridged \(decomposed) \u{0000} 🗺️")
        let bridged = mutable as String
        let values: [String?] = [nil, "", "a", "A", "\u{0000}", "a\u{0000}b", composed, decomposed,
            "🗺️", "🗺", "👩‍👩‍👧‍👦", "中文", "עברית", String(repeating: "長い文字列", count: 100),
            bridged, String(decoding: Array(bridged.utf8), as: UTF8.self)]
        for lhs in values {
            for rhs in values {
                let expected: Bool
                switch (lhs, rhs) {
                case (.none, .none): expected = true
                case let (.some(left), .some(right)): expected = left.utf8.elementsEqual(right.utf8)
                default: expected = false
                }
                XCTAssertEqual(PlaceImportSnapshotFileEncoding.sameText(lhs, rhs), expected)
            }
        }
        XCTAssertEqual(composed, decomposed)
        XCTAssertFalse(PlaceImportSnapshotFileEncoding.sameText(composed, decomposed))
    }

    func testPerformanceExactTextComparisonAgainstByteIteration() {
        let values = (0..<1_500).map { index in
            "Fictional imported row \(index): Café \(String(repeating: "place-address ", count: 8))"
        }
        // Independent storage prevents this workload from measuring only pointer identity.
        let copies = values.map { String(decoding: Array($0.utf8), as: UTF8.self) }
        var reference: [Double] = []
        var optimized: [Double] = []
        for _ in 0..<5 {
            var matches = 0
            var start = ProcessInfo.processInfo.systemUptime
            for _ in 0..<10 {
                for index in values.indices {
                    if values[index].utf8.elementsEqual(copies[index].utf8) { matches += 1 }
                }
            }
            reference.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            XCTAssertEqual(matches, 15_000)
            matches = 0
            start = ProcessInfo.processInfo.systemUptime
            for _ in 0..<10 {
                for index in values.indices {
                    if PlaceImportSnapshotFileEncoding.sameText(values[index], copies[index]) { matches += 1 }
                }
            }
            optimized.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            XCTAssertEqual(matches, 15_000)
        }
        let attachment = XCTAttachment(string: "REC675 import_exact_text comparisons=15000 reference_ms=\(reference) optimized_ms=\(optimized) reference_median_ms=\(reference.sorted()[2]) optimized_median_ms=\(optimized.sorted()[2])")
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
