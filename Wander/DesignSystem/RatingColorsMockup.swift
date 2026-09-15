#if DEBUG
import SwiftUI

/// Design exploration only. The shipping slider continues to resolve its original colors.
enum RatingColorPreviewPalette: String, CaseIterable, Identifiable {
    case current = "Current"
    case brighter = "A · Brighter"
    case neon = "B · Neon"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .current: "Original blue, orange, and deep red."
        case .brighter: "Sky blue, warm orange, and softer bright red."
        case .neon: "Electric blue, vivid orange, and neon red."
        }
    }

    func applying(to state: PlaceRatingLiquidState) -> PlaceRatingLiquidState {
        guard self != .current else { return state }
        // Keep the same blue → orange → red anchors and interpolation boundary at 3/5.
        let low: SIMD3<Double>
        let middle: SIMD3<Double>
        let high: SIMD3<Double>
        switch self {
        case .current: return state
        case .brighter:
            low = SIMD3(0.40, 0.80, 1.00)
            middle = SIMD3(1.00, 0.69, 0.36)
            high = SIMD3(1.00, 0.35, 0.38)
        case .neon:
            low = SIMD3(0.12, 0.80, 1.00)
            middle = SIMD3(1.00, 0.55, 0.10)
            high = SIMD3(1.00, 0.18, 0.23)
        }
        let firstHalf = state.progress <= 0.5
        let start = firstHalf ? low : middle
        let end = firstHalf ? middle : high
        let fraction = firstHalf ? state.progress * 2 : (state.progress - 0.5) * 2
        let tone = start + (end - start) * fraction
        return PlaceRatingLiquidState(
            score: state.score, progress: state.progress, level: state.level,
            bubbleCount: state.bubbleCount, red: tone.x, green: tone.y, blue: tone.z
        )
    }
}

struct RatingColorsMockup: View {
    var palettes: [RatingColorPreviewPalette] = RatingColorPreviewPalette.allCases
    @State private var score = 5.0
    private let brand = AstirBrandMode.editorial

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rating colors")
                        .font(.system(.largeTitle, design: .serif, weight: .bold))
                    Text("Dark mode · Drag any slider to compare.")
                        .font(AstirTypography.body)
                        .foregroundStyle(brand.secondaryText)
                }

                ForEach(palettes) { palette in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(palette.rawValue)
                            .font(AstirTypography.cardTitle)
                        Text(palette.detail)
                            .font(AstirTypography.caption)
                            .foregroundStyle(brand.secondaryText)
                        PlaceRatingSlider(score: $score, previewPalette: palette)
                        HStack(spacing: 4) {
                            ForEach(PlaceRating.allowedScores, id: \.self) { value in
                                let color = palette.applying(to: .resolve(value)).color
                                VStack(spacing: 4) {
                                    Capsule().fill(color).frame(height: 8)
                                    Text(PlaceRating.display(value))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(brand.secondaryText)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .accessibilityLabel("Scale: blue at 1, orange at 3, red at 5")
                    }
                }
                Text("Same scale, half-point steps, and liquid motion. Red is always highest.")
                    .font(AstirTypography.caption)
                    .foregroundStyle(brand.secondaryText)
            }
            .padding(20)
        }
        .background(brand.background)
        .foregroundStyle(brand.primaryText)
        .environment(\.astirBrandMode, brand)
        .preferredColorScheme(.dark)
    }
}

#Preview("Compare · Dark") {
    RatingColorsMockup()
}

#Preview("A · Brighter · Dark") {
    RatingColorsMockup(palettes: [.brighter])
}

#Preview("B · Neon · Dark") {
    RatingColorsMockup(palettes: [.neon])
}
#endif
