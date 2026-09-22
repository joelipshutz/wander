import CoreGraphics
import Foundation

enum MapPinDetail: String {
    case dot
    case category
}

/// Changes marker detail, never membership. Every candidate still has an
/// annotation; IDs outside the returned set use the compact gray-dot image.
struct MapAdaptivePinDetailPolicy {
    struct Candidate {
        let id: String
        let point: CGPoint
        var isSelected = false
    }

    static let allCategoryMetersPerPoint = 3.0
    static let adaptiveMetersPerPoint = 4.0
    private(set) var showsAllCategories = false
    private(set) var categoryIDs: Set<String> = []

    mutating func resolve(
        _ candidates: [Candidate],
        metersPerPoint: Double,
        viewport: CGRect
    ) -> Set<String> {
        guard metersPerPoint.isFinite, metersPerPoint > 0 else {
            categoryIDs = Set(candidates.map(\.id))
            return categoryIDs
        }
        // A different exit threshold prevents flicker during small pinch changes.
        showsAllCategories = metersPerPoint <= (showsAllCategories
            ? Self.adaptiveMetersPerPoint : Self.allCategoryMetersPerPoint)
        if showsAllCategories {
            categoryIDs = Set(candidates.map(\.id))
            return categoryIDs
        }

        let spacing = CGFloat(min(120, 48 + 20 * log2(max(1, metersPerPoint / 4))))
        let ranked = candidates.filter {
            $0.point.x.isFinite && $0.point.y.isFinite && viewport.contains($0.point)
        }.map { candidate in
            (candidate: candidate, retained: categoryIDs.contains(candidate.id),
             rank: Self.stableRank(candidate.id))
        }.sorted { lhs, rhs in
            if lhs.candidate.isSelected != rhs.candidate.isSelected { return lhs.candidate.isSelected }
            if lhs.retained != rhs.retained { return lhs.retained }
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.candidate.id < rhs.candidate.id
        }

        var occupied: [Cell: [CGPoint]] = [:]
        var next = Set(candidates.filter(\.isSelected).map(\.id))
        for entry in ranked {
            let candidate = entry.candidate
            let cell = Cell(candidate.point, size: spacing)
            // Existing category pins can get slightly closer before shrinking.
            let minimumDistance = spacing * (entry.retained ? 0.82 : 1)
            var overlaps = false
            if !candidate.isSelected {
                for x in (cell.x - 1)...(cell.x + 1) {
                    for y in (cell.y - 1)...(cell.y + 1) {
                        if occupied[Cell(x: x, y: y), default: []].contains(where: {
                            hypot($0.x - candidate.point.x, $0.y - candidate.point.y) < minimumDistance
                        }) { overlaps = true }
                    }
                }
            }
            guard !overlaps else { continue }
            next.insert(candidate.id)
            occupied[cell, default: []].append(candidate.point)
        }
        categoryIDs = next
        return next
    }

    private struct Cell: Hashable {
        let x: Int
        let y: Int

        init(x: Int, y: Int) { self.x = x; self.y = y }
        init(_ point: CGPoint, size: CGFloat) {
            x = Int(floor(point.x / size))
            y = Int(floor(point.y / size))
        }
    }

    /// Swift's Hasher varies per process; stable ranks keep representatives
    /// deterministic across data reorderings and fresh map presentations.
    private static func stableRank(_ id: String) -> UInt64 {
        id.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }
}
