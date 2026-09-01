import SwiftUI

enum PlaceRatingExplanation: String, CaseIterable, Identifiable {
    case ratings

    var id: String { rawValue }

    var title: String {
        "Ratings"
    }

    var message: String {
        "Friends rating averages ratings from people you follow who checked in here. If none have rated it, rec.me rating shows the broader community average. Fit score is personalized from your ratings, categories, tags, and people you follow."
    }

    var accessibilityLabel: String {
        "About the \(title)"
    }
}

struct PlaceProfileRatingsRail: View {
    let presentation: PlaceProfilePresentation
    var compact = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.placeProfileVisualStyle) private var visualStyle
    @Environment(\.astirBrandMode) private var astirBrandMode

    private var metrics: [Metric] {
        [
            Metric(
                title: "Your rating",
                value: presentation.ownRating?.displayScore ?? "—",
                suffix: presentation.ownRating == nil ? nil : "/5",
                subtitle: presentation.ownRating?.subtitle ?? "No rating yet"
            ),
            Metric(
                title: presentation.overallRating?.title ?? "rec.me rating",
                value: presentation.overallRating?.displayScore ?? "—",
                suffix: presentation.overallRating == nil ? nil : "/5",
                subtitle: presentation.overallRating?.subtitle ?? "No ratings yet"
            ),
            Metric(
                title: "Fit score",
                value: presentation.fitRating?.displayScore ?? "—",
                suffix: presentation.fitRating == nil ? nil : "/5",
                subtitle: presentation.fitRating == nil ? "Keep saving to unlock" : "Based on your taste"
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? WanderTheme.spacing1 : WanderTheme.spacing2) {
            HStack(spacing: WanderTheme.spacing1) {
                Text("Ratings")
                    .font(
                        visualStyle == .astir
                            ? (compact ? AstirTypography.cardTitle : AstirTypography.sectionTitle)
                            : (compact ? WanderTypography.editorialCompactTitle : WanderTypography.editorialSectionTitle)
                    )
                    .foregroundStyle(primaryText)

                Spacer(minLength: WanderTheme.spacing2)

                PlaceRatingInfoButton(
                    explanation: .ratings,
                    tint: secondaryText
                )
            }
            .frame(minHeight: WanderTheme.tapMinimum)

            if dynamicTypeSize.isAccessibilitySize {
                accessibilityMetrics
            } else {
                horizontalMetrics
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var horizontalMetrics: some View {
        HStack(spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                metricCell(metric)

                if index < metrics.count - 1 {
                    Rectangle()
                        .fill(borderColor)
                        .frame(width: 1, height: compact ? 64 : 76)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.vertical, compact ? WanderTheme.spacing2 : WanderTheme.spacing3)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(borderColor)
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(borderColor)
                .frame(height: 1)
        }
    }

    private var accessibilityMetrics: some View {
        VStack(spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                HStack(alignment: .firstTextBaseline, spacing: WanderTheme.spacing3) {
                    VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                        Text(metric.title)
                            .font(
                                visualStyle == .astir
                                    ? AstirTypography.label
                                    : WanderTypography.label
                            )
                            .foregroundStyle(primaryText)
                        Text(metric.subtitle)
                            .font(
                                visualStyle == .astir
                                    ? AstirTypography.metadata
                                    : WanderTypography.metadata
                            )
                            .foregroundStyle(secondaryText)
                    }

                    Spacer(minLength: WanderTheme.spacing2)

                    metricValue(metric)
                }
                .padding(.vertical, WanderTheme.spacing3)

                if index < metrics.count - 1 {
                    Rectangle()
                        .fill(borderColor)
                        .frame(height: 1)
                        .accessibilityHidden(true)
                }
            }
        }
        .overlay(
            Rectangle()
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private func metricCell(_ metric: Metric) -> some View {
        VStack(spacing: WanderTheme.spacing1) {
            metricValue(metric)

            Text(metric.title)
                .font(
                    visualStyle == .astir
                        ? AstirTypography.label
                        : .system(size: compact ? 11 : 12, weight: .bold)
                )
                .foregroundStyle(primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(metric.subtitle)
                .font(
                    visualStyle == .astir
                        ? AstirTypography.caption
                        : .system(size: compact ? 9.5 : 10.5, weight: .medium)
                )
                .foregroundStyle(secondaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)
                .frame(minHeight: compact ? 22 : 26, alignment: .top)
        }
        .padding(.horizontal, compact ? WanderTheme.spacing1 : WanderTheme.spacing2)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title), \(metric.value)\(metric.suffix ?? ""), \(metric.subtitle)")
    }

    private func metricValue(_ metric: Metric) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(metric.value)
                .font(
                    visualStyle == .astir
                        ? AstirTypography.metricDisplay
                        : WanderTypography.editorialRatingDisplay
                )
                .foregroundStyle(visualStyle == .astir ? astirBrandMode.accent : WanderTheme.textInk.color)
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            if let suffix = metric.suffix {
                Text(suffix)
                    .font(
                        visualStyle == .astir
                            ? AstirTypography.metricSuffix
                            : WanderTypography.editorialRatingSuffix
                    )
                    .foregroundStyle(secondaryText)
            }
        }
    }

    private var primaryText: Color {
        visualStyle == .astir ? astirBrandMode.primaryText : WanderTheme.textInk.color
    }

    private var secondaryText: Color {
        visualStyle == .astir ? astirBrandMode.secondaryText : WanderTheme.textMuted.color
    }

    private var borderColor: Color {
        visualStyle == .astir ? astirBrandMode.border : WanderTheme.borderHairline.color
    }

    private struct Metric {
        let title: String
        let value: String
        let suffix: String?
        let subtitle: String
    }
}

struct PlaceRatingInfoButton: View {
    let explanation: PlaceRatingExplanation
    let tint: Color

    @Environment(\.astirBrandMode) private var astirBrandMode
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(explanation.accessibilityLabel)
        .accessibilityHint("Shows how this score is calculated")
        .popover(
            isPresented: $isPresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                HStack(spacing: WanderTheme.spacing2) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(tint)

                    Text(explanation.title)
                        .font(AstirTypography.cardTitle)
                        .foregroundStyle(astirBrandMode.primaryText)
                }

                Text(explanation.message)
                    .font(AstirTypography.bodySmall)
                    .foregroundStyle(astirBrandMode.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(WanderTheme.spacing3)
            .frame(idealWidth: 270, maxWidth: 290, alignment: .leading)
            .background(astirBrandMode.raisedBackground)
            .presentationCompactAdaptation(.popover)
        }
    }
}
