import SwiftUI

/// Expands inside the postcard. Navigation continues to use each original
/// event, preserving its discussion and the repository's authorization checks.
struct FeedActivityDisclosure: View {
    @Environment(\.astirBrandMode) private var brandMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var activityNavigation: ActivityNavigationCoordinator
    let group: FeedActivityGroup
    let openList: ((LocalPlaceList) -> Void)?
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
            if let list = group.lists.first {
                Button {
                    openList?(list)
                } label: {
                    Text(group.primaryActivity.kind == .listItemAdded ? "Added to " : "Also added to ")
                        .foregroundStyle(brandMode.secondaryText)
                    + Text(list.name).foregroundStyle(brandMode.primaryText)
                    + Text(group.lists.count > 1 ? " +\(group.lists.count - 1) more" : "")
                        .foregroundStyle(brandMode.secondaryText)
                }
                .font(AstirTypography.bodySmall)
                .buttonStyle(.plain)
                .frame(minHeight: WanderTheme.tapMinimum, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHint("Opens list. Expand activity to see all list additions.")
            }

            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: WanderTheme.spacing2) {
                    Text(isExpanded ? "Hide activity" : "View activity")
                    Text(group.activities.count.formatted())
                        .foregroundStyle(brandMode.secondaryText)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .font(AstirTypography.label)
                .foregroundStyle(brandMode.accentText)
                .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Hide activity" : "View activity")
            .accessibilityValue("\(isExpanded ? "Expanded" : "Collapsed"), \(group.activities.count) activities")
            .accessibilityIdentifier("feed.activity.\(group.id).disclosure")

            if isExpanded {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    ForEach(group.activities) { event in
                        timelineRow(event)
                    }
                }
                .padding(.top, WanderTheme.spacing1)
                .transition(.opacity)
            }
        }
    }

    private func timelineRow(_ event: FeedActivity) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                guard let context = event.activityEngagementContext else { return }
                auth.requireSignIn(for: .socialActivity) {
                    activityNavigation.openComments(context: context, visiblePlace: event.place)
                }
            } label: {
                HStack(alignment: .top, spacing: WanderTheme.spacing2) {
                    Image(systemName: event.sequenceSymbol)
                        .frame(width: 20)
                        .foregroundStyle(brandMode.secondaryText)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.sequenceTitle)
                            .font(AstirTypography.bodySmall)
                            .foregroundStyle(brandMode.primaryText)
                        Text(event.occurredAt.formatted(date: .abbreviated, time: .standard))
                            .font(AstirTypography.metadata)
                            .foregroundStyle(brandMode.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(AstirTypography.caption)
                        .foregroundStyle(brandMode.secondaryText)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(event.sequenceTitle), \(event.occurredAt.formatted(date: .complete, time: .standard))")
            .accessibilityHint("Opens original post and comments")
            .accessibilityIdentifier("feed.activity.\(event.id).sequenceEvent")

            if let list = event.list, event.kind == .listItemAdded {
                Button { openList?(list) } label: {
                    Text(list.name)
                        .font(AstirTypography.bodySmall)
                        .foregroundStyle(brandMode.accentText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: WanderTheme.tapMinimum, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.leading, 20 + WanderTheme.spacing2)
                .accessibilityLabel("View list \(list.name)")
            }
        }
    }
}

private extension FeedActivity {
    var sequenceTitle: String {
        switch kind {
        case .placeBeen: "Checked in"
        case .placeWannaGo: "Wanna Go"
        case .listItemAdded: "Added to a list"
        case .listCreated: "Created a list"
        case .placeSaved: "Saved a place"
        }
    }

    var sequenceSymbol: String {
        switch kind {
        case .placeBeen: "checkmark"
        case .placeWannaGo: "plus"
        case .listItemAdded, .listCreated: PlaceListSymbol.systemImage
        case .placeSaved: "bookmark"
        }
    }
}
