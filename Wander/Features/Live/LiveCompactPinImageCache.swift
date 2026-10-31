import SwiftUI
import UIKit

/// Compact pins have no glyph, badge or animated viewed treatment. Share their
/// existing SwiftUI artwork without retaining a hosting tree for every dot.
@MainActor
final class LiveCompactPinImageCache {
    static let shared = LiveCompactPinImageCache()
    typealias Renderer = @MainActor (LiveNativeHostedPin, CGFloat, UITraitCollection) -> UIImage?

    private struct Key: Hashable {
        let ownership: [String]
        let brand: String
        let scale: CGFloat
        let contrast: Int
        let gamut: Int
    }
    private struct Entry {
        let image: UIImage
        let cost: Int
    }
    private let maximumCount: Int
    private let maximumCost: Int
    private let renderer: Renderer
    private var entries: [Key: Entry] = [:]
    private var recency: [Key] = []
    private(set) var retainedCost = 0
    var count: Int { entries.count }

    init(maximumCount: Int = 32, maximumCost: Int = 4 * 1_024 * 1_024,
         renderer: @escaping Renderer = LiveCompactPinImageCache.render) {
        self.maximumCount = max(0, maximumCount)
        self.maximumCost = max(0, maximumCost)
        self.renderer = renderer
    }

    func image(for root: LiveNativeHostedPin, scale: CGFloat, traits: UITraitCollection) -> UIImage? {
        guard root.compact, !root.selected, scale.isFinite, scale > 0,
              44 * scale <= 1_024 else { return nil }
        // Current compact colors are explicit sRGB tokens. Keep brand and
        // display traits in the key as well as the actual ordered rail colors.
        let key = Key(ownership: root.state.rails.map { $0.ownership.key }, brand: root.brand.rawValue,
                      scale: scale, contrast: traits.accessibilityContrast.rawValue, gamut: traits.displayGamut.rawValue)
        if let entry = entries[key] {
            recency.removeAll { $0 == key }
            recency.append(key)
            return entry.image
        }
        guard let image = renderer(root, scale, traits), image.size == CGSize(width: 44, height: 44),
              let pixels = image.cgImage else { return nil }
        let cost = pixels.bytesPerRow * pixels.height
        guard maximumCount > 0, cost <= maximumCost else { return image }
        while entries.count >= maximumCount || retainedCost > maximumCost - cost {
            guard let oldest = recency.first else { break }
            recency.removeFirst()
            if let removed = entries.removeValue(forKey: oldest) { retainedCost -= removed.cost }
        }
        entries[key] = Entry(image: image, cost: cost)
        recency.append(key)
        retainedCost += cost
        return image
    }

    private static func render(_ root: LiveNativeHostedPin, scale: CGFloat, traits: UITraitCollection) -> UIImage? {
        var result: UIImage?
        traits.performAsCurrent {
            let renderer = ImageRenderer(content: root
                .environment(\.displayScale, scale))
            renderer.proposedSize = ProposedViewSize(width: 44, height: 44)
            renderer.scale = scale
            result = renderer.uiImage
        }
        return result
    }
}
