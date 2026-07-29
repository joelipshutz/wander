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

struct PlaceRatingLiquidState: Equatable {
    let score: Double
    let progress: Double
    let level: Double
    let bubbleCount: Int
    let red: Double
    let green: Double
    let blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    static func resolve(_ score: Double) -> PlaceRatingLiquidState {
        let candidate = score.isFinite ? score : PlaceRating.defaultScore
        let normalized = min(
            max(candidate, PlaceRating.minimumScore),
            PlaceRating.maximumScore
        )
        let span = PlaceRating.maximumScore - PlaceRating.minimumScore
        let progress = span > 0 ? (normalized - PlaceRating.minimumScore) / span : 1
        let tone: (red: Double, green: Double, blue: Double)

        if progress <= 0.5 {
            tone = interpolate(
                from: (red: 0.24, green: 0.63, blue: 0.82),
                to: (red: 0.93, green: 0.55, blue: 0.24),
                progress: progress / 0.5
            )
        } else {
            tone = interpolate(
                from: (red: 0.93, green: 0.55, blue: 0.24),
                to: (red: 0.42, green: 0.07, blue: 0.09),
                progress: (progress - 0.5) / 0.5
            )
        }

        return PlaceRatingLiquidState(
            score: normalized,
            progress: progress,
            level: 0.14 + (progress * 0.72),
            bubbleCount: 3 + Int((progress * 9).rounded()),
            red: tone.red,
            green: tone.green,
            blue: tone.blue
        )
    }

    private static func interpolate(
        from start: (red: Double, green: Double, blue: Double),
        to end: (red: Double, green: Double, blue: Double),
        progress: Double
    ) -> (red: Double, green: Double, blue: Double) {
        let amount = min(max(progress, 0), 1)
        return (
            red: start.red + ((end.red - start.red) * amount),
            green: start.green + ((end.green - start.green) * amount),
            blue: start.blue + ((end.blue - start.blue) * amount)
        )
    }
}

struct PlaceRatingSlider: View {
    @Binding var score: Double
    var isCompact = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var interactionScore: Double?
    @State private var selectionFeedbackTrigger = 0

    private var reaction: PlaceRatingReaction {
        PlaceRatingReaction.resolve(score)
    }

    private var liquidState: PlaceRatingLiquidState {
        PlaceRatingLiquidState.resolve(interactionScore ?? reaction.score)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? WanderTheme.spacing1 : WanderTheme.spacing2) {
            HStack(spacing: WanderTheme.spacing1) {
                HStack(spacing: WanderTheme.spacing1) {
                    Text("rating")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)

                    Text("5 is best")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WanderTheme.textFaint.color)
                }
                .padding(.horizontal, WanderTheme.spacing2)
                .padding(.vertical, 5)
                .background(WanderTheme.surfaceRaised.color.opacity(0.84))
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(liquidState.color.opacity(0.18), lineWidth: 1)
                }

                Spacer(minLength: WanderTheme.spacing1)

                HStack(spacing: WanderTheme.spacing1) {
                    Text("\(PlaceRating.display(reaction.score))/5")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(WanderTheme.textInk.color)
                        .contentTransition(.numericText(value: reaction.score))

                    Text(reaction.label)
                        .font(.system(size: reaction.isExtreme ? 17 : 15, weight: .black, design: .rounded))
                        .foregroundStyle(liquidState.color)
                }
                .padding(.leading, WanderTheme.spacing2)
                .padding(.trailing, WanderTheme.spacing2)
                .padding(.vertical, 5)
                .background(WanderTheme.surfaceRaised.color.opacity(0.88))
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(liquidState.color.opacity(0.24), lineWidth: 1)
                }
                .layoutPriority(1)
            }

            ratingTrack

            HStack {
                ForEach(1...5, id: \.self) { value in
                    Text("\(value)")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(scaleLabelColor(for: value))
                        .fontWeight(abs(Double(value) - reaction.score) < 0.001 ? .black : .bold)
                }
            }
            .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .padding(.vertical, isCompact ? WanderTheme.spacing2 : WanderTheme.spacing3)
        .background {
            ZStack {
                WanderTheme.surfaceRaised.color
                BoilingRatingLiquid(state: liquidState, reduceMotion: reduceMotion)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(liquidState.color.opacity(0.34), lineWidth: 1)
        }
        .animation(
            reduceMotion || interactionScore != nil ? nil : .easeInOut(duration: 0.3),
            value: liquidState
        )
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("place-rating-slider")
        .accessibilityLabel("Rating")
        .accessibilityValue(reaction.accessibilityValue)
        .accessibilityHint("Swipe up or down to change the rating by half a point.")
        .accessibilityAdjustableAction(adjustRating)
        .sensoryFeedback(.selection, trigger: selectionFeedbackTrigger)
    }

    private var ratingTrack: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 18
            let trackWidth = max(1, geometry.size.width - (inset * 2))
            let thumbX = inset + (trackWidth * CGFloat(liquidState.progress))

            ZStack {
                Capsule()
                    .fill(WanderTheme.surfaceRaised.color.opacity(0.76))
                    .frame(width: trackWidth, height: 7)
                    .overlay {
                        Capsule()
                            .stroke(WanderTheme.borderStrong.color.opacity(0.52), lineWidth: 1)
                    }

                Capsule()
                    .fill(liquidState.color)
                    .frame(width: trackWidth * CGFloat(liquidState.progress), height: 7)
                    .frame(width: trackWidth, alignment: .leading)

                ForEach(PlaceRating.allowedScores, id: \.self) { value in
                    let tickProgress = (value - PlaceRating.minimumScore)
                        / (PlaceRating.maximumScore - PlaceRating.minimumScore)
                    let isWholeNumber = value.rounded() == value

                    Circle()
                        .fill(
                            value <= reaction.score
                                ? WanderTheme.surfaceRaised.color.opacity(0.9)
                                : WanderTheme.surfaceRaised.color.opacity(0.72)
                        )
                        .overlay {
                            Circle()
                                .stroke(liquidState.color.opacity(0.72), lineWidth: 1.5)
                        }
                        .frame(
                            width: isWholeNumber ? 7 : 4,
                            height: isWholeNumber ? 7 : 4
                        )
                        .position(
                            x: inset + (trackWidth * CGFloat(tickProgress)),
                            y: geometry.size.height / 2
                        )
                }

                Circle()
                    .fill(WanderTheme.surfaceRaised.color.opacity(0.92))
                    .overlay {
                        Circle()
                            .stroke(liquidState.color, lineWidth: 5)
                    }
                    .overlay {
                        Circle()
                            .fill(liquidState.color)
                            .frame(width: 8, height: 8)
                    }
                    .frame(width: 32, height: 32)
                    .shadow(color: WanderTheme.textInk.color.opacity(0.12), radius: 4, y: 2)
                    .position(x: thumbX, y: geometry.size.height / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateInteraction(
                            for: value.location.x,
                            inset: inset,
                            trackWidth: trackWidth
                        )
                    }
                    .onEnded { value in
                        finishInteraction(
                            at: value.location.x,
                            inset: inset,
                            trackWidth: trackWidth
                        )
                    }
            )
        }
        .frame(height: 52)
    }

    private func candidateScore(for locationX: CGFloat, inset: CGFloat, trackWidth: CGFloat) -> Double {
        let progress = min(max((locationX - inset) / trackWidth, 0), 1)
        let span = PlaceRating.maximumScore - PlaceRating.minimumScore
        return PlaceRating.minimumScore + (Double(progress) * span)
    }

    private func updateInteraction(for locationX: CGFloat, inset: CGFloat, trackWidth: CGFloat) {
        let candidate = candidateScore(for: locationX, inset: inset, trackWidth: trackWidth)
        interactionScore = candidate
        setScore(candidate)
    }

    private func finishInteraction(at locationX: CGFloat, inset: CGFloat, trackWidth: CGFloat) {
        let candidate = candidateScore(for: locationX, inset: inset, trackWidth: trackWidth)
        interactionScore = candidate
        setScore(candidate)

        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
            interactionScore = nil
        }
    }

    private func scaleLabelColor(for value: Int) -> Color {
        let isSelected = abs(Double(value) - reaction.score) < 0.001
        if liquidState.progress >= 0.7 {
            return Color.white.opacity(isSelected ? 1 : 0.92)
        }
        return isSelected ? liquidState.color : WanderTheme.textMuted.color
    }

    private func setScore(_ candidate: Double) {
        let normalized = PlaceRating.normalized(candidate) ?? PlaceRating.defaultScore
        guard normalized != score else { return }

        score = normalized
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
}

private struct BoilingRatingLiquid: View {
    let state: PlaceRatingLiquidState
    let reduceMotion: Bool

    private let horizontalPositions: [Double] = [
        0.08, 0.17, 0.28, 0.39, 0.52, 0.63,
        0.74, 0.86, 0.94, 0.33, 0.58, 0.79
    ]

    private let startingOffsets: [Double] = [
        0.12, 0.65, 0.36, 0.84, 0.48, 0.04,
        0.72, 0.27, 0.91, 0.56, 0.18, 0.77
    ]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            Canvas(
                opaque: false,
                colorMode: .nonLinear,
                rendersAsynchronously: false
            ) { graphics, size in
                let time = reduceMotion
                    ? 0
                    : context.date.timeIntervalSinceReferenceDate
                let liquidPath = liquidPath(
                    in: CGRect(origin: .zero, size: size),
                    phase: time
                )

                graphics.fill(
                    liquidPath,
                    with: .linearGradient(
                        Gradient(colors: [
                            state.color.opacity(0.34),
                            state.color.opacity(0.68)
                        ]),
                        startPoint: CGPoint(x: size.width / 2, y: 0),
                        endPoint: CGPoint(x: size.width / 2, y: size.height)
                    )
                )

                graphics.drawLayer { bubbleGraphics in
                    bubbleGraphics.clip(to: liquidPath)
                    drawBubbles(in: &bubbleGraphics, size: size, time: time)
                }

                graphics.stroke(
                    liquidPath,
                    with: .color(state.color.opacity(0.58)),
                    lineWidth: 1.5
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func liquidPath(in rect: CGRect, phase: Double) -> Path {
        let clampedLevel = min(max(state.level, 0), 1)
        let topY = rect.maxY - (rect.height * CGFloat(clampedLevel))
        let sampleCount = max(48, Int(ceil(rect.width / 6)))
        let waveStrength = 2.5 + (state.progress * 3)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: topY))

        for sample in 0...sampleCount {
            let progress = Double(sample) / Double(sampleCount)
            let x = rect.minX + (rect.width * CGFloat(progress))
            let wave = CGFloat(sin((progress * .pi * 2.1) + phase) * waveStrength)
            path.addLine(to: CGPoint(x: x, y: topY + wave))
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    private func drawBubbles(
        in graphics: inout GraphicsContext,
        size: CGSize,
        time: Double
    ) {
        for index in 0..<min(state.bubbleCount, horizontalPositions.count) {
            let speed = 0.13 + (Double(index % 4) * 0.025)
            let rawCycle = (time * speed) + startingOffsets[index]
            let cycle = rawCycle - floor(rawCycle)
            let diameter = CGFloat(4 + Double((index * 3) % 8))
            let drift = CGFloat(sin((time * 0.9) + Double(index)) * 5)
            let center = CGPoint(
                x: (size.width * CGFloat(horizontalPositions[index])) + drift,
                y: size.height + diameter - (size.height * CGFloat(cycle) * 1.12)
            )
            let bubbleRect = CGRect(
                x: center.x - (diameter / 2),
                y: center.y - (diameter / 2),
                width: diameter,
                height: diameter
            )
            let bubblePath = Path(ellipseIn: bubbleRect)

            graphics.fill(bubblePath, with: .color(Color.white.opacity(0.08)))
            graphics.stroke(
                bubblePath,
                with: .color(Color.white.opacity(0.58)),
                lineWidth: 1
            )
        }
    }
}
