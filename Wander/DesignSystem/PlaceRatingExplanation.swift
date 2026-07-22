import SwiftUI

enum PlaceRatingExplanation: String, CaseIterable, Identifiable {
    case recMe
    case fit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recMe:
            "rec.me rating"
        case .fit:
            "Fit rating"
        }
    }

    var message: String {
        switch self {
        case .recMe:
            "The average rating from people you follow who have been here. Your own rating is shown separately."
        case .fit:
            "A personalized match score based on places you’ve rated, the categories and tags you like, and saves from people you follow."
        }
    }

    var accessibilityLabel: String {
        "About the \(title)"
    }
}

struct PlaceRatingInfoButton: View {
    let explanation: PlaceRatingExplanation
    let tint: Color

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
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                }

                Text(explanation.message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(WanderTheme.spacing3)
            .frame(idealWidth: 270, maxWidth: 290, alignment: .leading)
            .presentationCompactAdaptation(.popover)
        }
    }
}
