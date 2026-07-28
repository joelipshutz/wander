import SwiftUI

struct PlaceRatingReaction: Equatable {
    let score: Double
    let label: String

    var isMinimum: Bool {
        score == PlaceRating.minimumScore
    }

    var isMaximum: Bool {
        score == PlaceRating.maximumScore
    }

    var isExtreme: Bool {
        isMinimum || isMaximum
    }

    var accessibilityValue: String {
        "\(PlaceRating.display(score)) out of 5, \(label)"
    }

    static func resolve(_ score: Double) -> PlaceRatingReaction {
        let normalized = PlaceRating.normalized(score) ?? PlaceRating.defaultScore
        let label = switch normalized {
        case 1: "oof"
        case 1.5: "rough"
        case 2: "meh"
        case 2.5: "ehhh"
        case 3: "mid"
        case 3.5: "okayyy"
        case 4: "yeah"
        case 4.5: "oh baby"
        default: "wow"
        }
        return PlaceRatingReaction(score: normalized, label: label)
    }
}

struct PlaceRatingSlider: View {
    @Binding var score: Double
    var isCompact = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isDragging = false
    @State private var endpointPulse: Double?
    @State private var selectionFeedbackTrigger = 0
    @State private var endpointFeedbackTrigger = 0

    private var reaction: PlaceRatingReaction {
        PlaceRatingReaction.resolve(score)
    }

    private var normalizedScore: Double {
        let span = PlaceRating.maximumScore - PlaceRating.minimumScore
        guard span > 0 else { return 1 }
        return (reaction.score - PlaceRating.minimumScore) / span
    }

    private var ratingTint: Color {
        switch reaction.score {
        case ...1.5:
            WanderTheme.stateError.color
        case ...2.5:
            WanderTheme.terracottaDark.color
        case ...3.5:
            WanderTheme.textMuted.color
        default:
            WanderTheme.terracotta.color
        }
    }

    private var reactionRotation: Angle {
        guard !reduceMotion else { return .zero }
        if endpointPulse == PlaceRating.minimumScore {
            return .degrees(-5)
        }
        if endpointPulse == PlaceRating.maximumScore {
            return .degrees(5)
        }
        guard isDragging else { return .zero }
        return .degrees((normalizedScore - 0.5) * 6)
    }

    private var reactionScale: CGFloat {
        if endpointPulse == PlaceRating.maximumScore {
            return reduceMotion ? 1 : 1.18
        }
        if endpointPulse == PlaceRating.minimumScore {
            return reduceMotion ? 1 : 0.92
        }
        return isDragging && !reduceMotion ? 1.06 : 1
    }

    private var shakeOffset: CGFloat {
        endpointPulse == PlaceRating.minimumScore && !reduceMotion ? -3 : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? WanderTheme.spacing1 : WanderTheme.spacing2) {
            HStack(spacing: WanderTheme.spacing1) {
                Text("rating")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)

                Text("5 is best")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WanderTheme.textFaint.color)

                Spacer(minLength: WanderTheme.spacing1)

                Text("\(PlaceRating.display(reaction.score))/5")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(WanderTheme.textInk.color)
                    .contentTransition(.numericText(value: reaction.score))

                Text(reaction.label)
                    .font(.system(size: reaction.isExtreme ? 17 : 15, weight: .black, design: .rounded))
                    .foregroundStyle(ratingTint)
                    .padding(.horizontal, WanderTheme.spacing2)
                    .padding(.vertical, 5)
                    .background(ratingTint.opacity(0.14))
                    .clipShape(Capsule())
                    .rotationEffect(reactionRotation)
                    .scaleEffect(reactionScale)
            }

            ratingTrack

            HStack {
                ForEach(1...5, id: \.self) { value in
                    Text("\(value)")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(abs(Double(value) - reaction.score) < 0.001 ? ratingTint : WanderTheme.textMuted.color)
                        .fontWeight(abs(Double(value) - reaction.score) < 0.001 ? .black : .bold)
                }
            }
            .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .padding(.vertical, isCompact ? WanderTheme.spacing2 : WanderTheme.spacing3)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(
                    reaction.isExtreme ? ratingTint.opacity(endpointPulse == nil ? 0.16 : 0.42) : .clear,
                    lineWidth: 1
                )
        }
        .offset(x: shakeOffset)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.62), value: score)
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.58), value: isDragging)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("place-rating-slider")
        .accessibilityLabel("Rating")
        .accessibilityValue(reaction.accessibilityValue)
        .accessibilityHint("Swipe up or down to change the rating by half a point.")
        .accessibilityAdjustableAction(adjustRating)
        .sensoryFeedback(.selection, trigger: selectionFeedbackTrigger)
        .sensoryFeedback(.impact(weight: .heavy), trigger: endpointFeedbackTrigger)
    }

    private var ratingTrack: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 18
            let trackWidth = max(1, geometry.size.width - (inset * 2))
            let thumbX = inset + (trackWidth * normalizedScore)
            let lift: CGFloat = isDragging && !reduceMotion ? 8 : 0
            let thumbY = (geometry.size.height / 2) - lift

            ZStack {
                ElasticRatingTrack(progress: normalizedScore, lift: lift)
                    .stroke(
                        WanderTheme.borderStrong.color.opacity(0.62),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: trackWidth, height: geometry.size.height)

                ElasticRatingTrack(progress: normalizedScore, lift: lift)
                    .trim(from: 0, to: normalizedScore)
                    .stroke(
                        ratingTint,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: trackWidth, height: geometry.size.height)

                ForEach(PlaceRating.allowedScores, id: \.self) { value in
                    let tickProgress = (value - PlaceRating.minimumScore)
                        / (PlaceRating.maximumScore - PlaceRating.minimumScore)
                    let isWholeNumber = value.rounded() == value

                    Circle()
                        .fill(value <= reaction.score ? ratingTint : WanderTheme.surfaceRaised.color)
                        .overlay {
                            Circle()
                                .stroke(WanderTheme.borderStrong.color, lineWidth: 1)
                        }
                        .frame(
                            width: isWholeNumber ? 7 : 4,
                            height: isWholeNumber ? 7 : 4
                        )
                        .position(
                            x: inset + (trackWidth * tickProgress),
                            y: geometry.size.height / 2
                        )
                }

                if reaction.isMaximum {
                    RatingEndpointBurst(tint: WanderTheme.categorySun.color)
                        .frame(width: 52, height: 52)
                        .scaleEffect(endpointPulse == PlaceRating.maximumScore && !reduceMotion ? 1 : 0.58)
                        .opacity(endpointPulse == PlaceRating.maximumScore && !reduceMotion ? 1 : 0)
                        .position(x: thumbX, y: thumbY)
                }

                Circle()
                    .fill(WanderTheme.surfaceRaised.color)
                    .overlay {
                        Circle()
                            .stroke(ratingTint, lineWidth: 6)
                    }
                    .overlay {
                        Circle()
                            .fill(ratingTint)
                            .frame(width: 8, height: 8)
                    }
                    .frame(width: 32, height: 32)
                    .shadow(color: WanderTheme.textInk.color.opacity(0.15), radius: 4, y: 2)
                    .scaleEffect(
                        x: endpointPulse == PlaceRating.minimumScore && !reduceMotion ? 1.14 : thumbScale,
                        y: endpointPulse == PlaceRating.minimumScore && !reduceMotion ? 0.72 : thumbScale
                    )
                    .position(x: thumbX, y: thumbY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.62)) {
                                isDragging = true
                            }
                        }
                        updateScore(for: value.location.x, inset: inset, trackWidth: trackWidth)
                    }
                    .onEnded { value in
                        updateScore(for: value.location.x, inset: inset, trackWidth: trackWidth)
                        finishInteraction()
                    }
            )
        }
        .frame(height: 52)
    }

    private var thumbScale: CGFloat {
        if isDragging && !reduceMotion {
            return reaction.isExtreme ? 1.16 : 1.08
        }
        return 1
    }

    private func updateScore(for locationX: CGFloat, inset: CGFloat, trackWidth: CGFloat) {
        let progress = min(max((locationX - inset) / trackWidth, 0), 1)
        let span = PlaceRating.maximumScore - PlaceRating.minimumScore
        setScore(PlaceRating.minimumScore + (Double(progress) * span))
    }

    private func setScore(_ candidate: Double) {
        let normalized = PlaceRating.normalized(candidate) ?? PlaceRating.defaultScore
        guard normalized != score else { return }

        score = normalized
        endpointPulse = nil
        selectionFeedbackTrigger += 1
    }

    private func adjustRating(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment:
            setScore(score + PlaceRating.step)
        case .decrement:
            setScore(score - PlaceRating.step)
        @unknown default:
            break
        }
    }

    private func finishInteraction() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.7)) {
            isDragging = false
        }

        let settledReaction = PlaceRatingReaction.resolve(score)
        guard settledReaction.isExtreme else {
            endpointPulse = nil
            return
        }

        endpointFeedbackTrigger += 1
        let settledScore = settledReaction.score
        let animation: Animation? = if reduceMotion {
            nil
        } else if settledReaction.isMinimum {
            .linear(duration: 0.065).repeatCount(5, autoreverses: true)
        } else {
            .spring(response: 0.3, dampingFraction: 0.42)
        }

        withAnimation(animation) {
            endpointPulse = settledScore
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(440))
            guard endpointPulse == settledScore else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                endpointPulse = nil
            }
        }
    }
}

private struct ElasticRatingTrack: Shape {
    var progress: CGFloat
    var lift: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, lift) }
        set {
            progress = newValue.first
            lift = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let thumbX = rect.minX + (rect.width * progress)
        let restingY = rect.midY
        let liftedY = restingY - lift
        let influence: CGFloat = 38

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: restingY))
        path.addCurve(
            to: CGPoint(x: thumbX, y: liftedY),
            control1: CGPoint(x: max(rect.minX, thumbX - influence), y: restingY),
            control2: CGPoint(x: max(rect.minX, thumbX - (influence * 0.5)), y: liftedY)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: restingY),
            control1: CGPoint(x: min(rect.maxX, thumbX + (influence * 0.5)), y: liftedY),
            control2: CGPoint(x: min(rect.maxX, thumbX + influence), y: restingY)
        )
        return path
    }
}

private struct RatingEndpointBurst: View {
    let tint: Color

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                Capsule()
                    .fill(tint)
                    .frame(width: 3, height: 10)
                    .offset(y: -22)
                    .rotationEffect(.degrees(Double(index) * 45))
            }
        }
        .accessibilityHidden(true)
    }
}
