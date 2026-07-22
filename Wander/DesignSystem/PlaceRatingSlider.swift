import SwiftUI

struct PlaceRatingSlider: View {
    @Binding var score: Double
    var isCompact = false

    private var normalizedScore: Double {
        let span = PlaceRating.maximumScore - PlaceRating.minimumScore
        guard span > 0 else { return 1 }
        return (score - PlaceRating.minimumScore) / span
    }

    private var ratingTint: Color {
        let opacity = 0.35 + (1 - 0.35) * normalizedScore
        return WanderTheme.stateError.color.opacity(opacity)
    }

    private var ratingLabel: String {
        switch score {
        case ..<1.5: "oof"
        case ..<2.5: "meh"
        case ..<3.5: "mid"
        case ..<4.5: "yeah"
        default: "wow"
        }
    }

    private var sliderValue: Binding<Double> {
        Binding(
            get: { score },
            set: { score = PlaceRating.normalized($0) ?? PlaceRating.defaultScore }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? WanderTheme.spacing1 : WanderTheme.spacing2) {
            HStack {
                Text("rating")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                Text("5 is best")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WanderTheme.textFaint.color)
                Spacer()
                Text("\(PlaceRating.display(score))/5 · \(ratingLabel)")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(ratingTint)
            }

            Slider(
                value: sliderValue,
                in: PlaceRating.minimumScore...PlaceRating.maximumScore,
                step: PlaceRating.step
            )
            .tint(ratingTint)

            HStack {
                ForEach(PlaceRating.allowedScores, id: \.self) { value in
                    Text(PlaceRating.display(value))
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(abs(value - score) < 0.001 ? ratingTint : WanderTheme.textMuted.color)
                        .fontWeight(abs(value - score) < 0.001 ? .black : .bold)
                }
            }
            .font(.system(size: 10, weight: .bold))
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .padding(.vertical, isCompact ? WanderTheme.spacing2 : WanderTheme.spacing3)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }
}
