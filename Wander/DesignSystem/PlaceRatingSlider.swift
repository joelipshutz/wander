import SwiftUI

struct PlaceRatingSlider: View {
    @Binding var score: Int

    private var normalizedScore: Double {
        let span = Double(PlaceRating.maximumScore - PlaceRating.minimumScore)
        guard span > 0 else { return 1 }
        return Double(score - PlaceRating.minimumScore) / span
    }

    private var ratingTint: Color {
        let opacity = 0.35 + (1 - 0.35) * normalizedScore
        return WanderTheme.stateError.color.opacity(opacity)
    }

    private var ratingLabel: String {
        switch score {
        case 1: "oof"
        case 2: "meh"
        case 3: "mid"
        case 4: "yeah"
        default: "wow"
        }
    }

    private var sliderValue: Binding<Double> {
        Binding(
            get: { Double(score) },
            set: { score = PlaceRating.normalized(Int($0.rounded())) ?? PlaceRating.defaultScore }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack {
                Text("rating")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                Text("5 is best")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WanderTheme.textFaint.color)
                Spacer()
                Text("\(score)/5 · \(ratingLabel)")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(ratingTint)
            }

            Slider(
                value: sliderValue,
                in: Double(PlaceRating.minimumScore)...Double(PlaceRating.maximumScore),
                step: 1
            )
            .tint(ratingTint)

            HStack {
                ForEach(PlaceRating.minimumScore...PlaceRating.maximumScore, id: \.self) { value in
                    Text("\(value)")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(value == score ? ratingTint : WanderTheme.textMuted.color)
                        .fontWeight(value == score ? .black : .bold)
                }
            }
            .font(.system(size: 11, weight: .bold))
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }
}
