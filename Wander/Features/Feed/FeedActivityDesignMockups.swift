#if DEBUG
import SwiftUI

enum FeedActivityDesignMockupPage: String, CaseIterable {
    case control
    case placeCard
    case trustedStory

    static func resolved(
        from arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> FeedActivityDesignMockupPage? {
        guard let flagIndex = arguments.firstIndex(of: "-WanderFeedDesignMockup") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return .control
        }

        return FeedActivityDesignMockupPage(rawValue: arguments[valueIndex]) ?? .control
    }

    var studyLabel: String {
        switch self {
        case .control:
            "A · Ticket control"
        case .placeCard:
            "B · Place postcard"
        case .trustedStory:
            "C · Trusted story"
        }
    }

    var studySummary: String {
        switch self {
        case .control:
            "Actor and action first; compact and familiar."
        case .placeCard:
            "Place and photo first; attribution becomes social proof."
        case .trustedStory:
            "Person first; place preview carries the useful detail."
        }
    }
}

struct FeedActivityDesignMockupRoot: View {
    let page: FeedActivityDesignMockupPage

    var body: some View {
        FeedActivityDesignMockupScreen(page: page)
            .preferredColorScheme(.light)
            .accessibilityIdentifier("feedDesignMockup.\(page.rawValue)")
    }
}

private struct FeedActivityDesignMockupScreen: View {
    let page: FeedActivityDesignMockupPage

    var body: some View {
        VStack(spacing: 0) {
            FeedActivityMockupHeader()
                .fixedSize(horizontal: false, vertical: true)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                        Color.clear
                            .frame(height: 0)
                            .id("feed-design-top")

                        FeedActivityMockupStudyHeading(page: page)

                        card

                        FeedActivityMockupNextStoryHint()
                    }
                    .padding(.horizontal, WanderTheme.spacing4)
                    .padding(.top, WanderTheme.spacing4)
                    .padding(.bottom, WanderTheme.spacing6)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    proxy.scrollTo("feed-design-top", anchor: .top)
                }
            }

            FeedActivityMockupTabBar()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
        .foregroundStyle(WanderTheme.textInk.color)
    }

    @ViewBuilder
    private var card: some View {
        switch page {
        case .control:
            FeedActivityTicketControlCard(activity: .dunsmoor)
        case .placeCard:
            FeedActivityPlacePostcard(activity: .dunsmoor)
        case .trustedStory:
            FeedActivityTrustedStoryCard(activity: .dunsmoor)
        }
    }
}

private struct FeedActivityMockupStudyHeading: View {
    let page: FeedActivityDesignMockupPage

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
            HStack(alignment: .firstTextBaseline) {
                Text(page.studyLabel)
                    .font(WanderTypography.editorialSectionTitle)

                Spacer(minLength: WanderTheme.spacing2)

                Text("REC-337")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(WanderTheme.terracottaDark.color)
                    .padding(.horizontal, WanderTheme.spacing2)
                    .frame(minHeight: 28)
                    .background(WanderTheme.terracottaTint.color)
                    .clipShape(Capsule())
            }

            Text(page.studySummary)
                .font(WanderTypography.metadata)
                .foregroundStyle(WanderTheme.textMuted.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FeedActivityMockupHeader: View {
    var body: some View {
        VStack(spacing: WanderTheme.spacing3) {
            HStack(spacing: WanderTheme.spacing3) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("rec.me")
                        .font(WanderTypography.editorialMasthead)

                    Text("from people you follow")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }

                Spacer()

                FeedActivityMockupHeaderButton(
                    systemImage: "magnifyingglass",
                    accessibilityLabel: "Search Feed"
                )
                FeedActivityMockupHeaderButton(
                    systemImage: "plus",
                    accessibilityLabel: "Add a place",
                    tint: WanderTheme.terracotta.color
                )
            }

            HStack(spacing: WanderTheme.spacing1) {
                FeedActivityMockupSegment(title: "places", isSelected: true)
                FeedActivityMockupSegment(title: "people", isSelected: false)
            }
            .padding(4)
            .background(WanderTheme.surfaceSand.color)
            .clipShape(Capsule())
        }
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.top, WanderTheme.spacing2)
        .padding(.bottom, WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WanderTheme.borderHairline.color)
                .frame(height: 1)
        }
    }
}

private struct FeedActivityMockupHeaderButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var tint = WanderTheme.textInk.color

    var body: some View {
        Button(action: {}) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                .background(WanderTheme.surfaceRaised.color)
                .clipShape(Circle())
                .overlay(Circle().stroke(WanderTheme.borderHairline.color, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct FeedActivityMockupSegment: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(isSelected ? WanderTheme.textInk.color : WanderTheme.textMuted.color)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(isSelected ? WanderTheme.surfaceRaised.color : Color.clear)
            .clipShape(Capsule())
    }
}

private struct FeedActivityTicketControlCard: View {
    let activity: FeedActivityDesignFixture

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(spacing: WanderTheme.spacing2) {
                FeedActivityMockupAvatar(activity: activity, size: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text(activity.actorName)
                        .font(.system(size: 14, weight: .black))
                        .lineLimit(1)

                    Text("CHECKED IN · \(activity.timestamp.uppercased())")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(0.9)
                        .foregroundStyle(WanderTheme.pinSocial.color)
                }

                Spacer(minLength: WanderTheme.spacing1)

                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.pinSocial.color)
                    .frame(width: 30, height: 30)
                    .background(WanderTheme.pinSocial.color.opacity(0.13))
                    .clipShape(Circle())
            }
            .frame(minHeight: WanderTheme.tapMinimum)

            HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(activity.placeName)
                        .font(WanderTypography.editorialCardTitle)
                        .lineLimit(2)

                    FeedActivityMockupMetadata(activity: activity, showsRatingInline: true)

                    Text("“\(activity.note)”")
                        .font(.system(size: 13, weight: .medium))
                        .italic()
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                FeedActivityMockupPlaceArtwork()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
            }

            FeedActivityMockupActionRow()
        }
        .padding(WanderTheme.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .checkInTicketSurface(
            accent: WanderTheme.pinSocial.color,
            surface: WanderTheme.surfaceBone.color,
            surroundingSurface: WanderTheme.canvasWarm.color,
            notchEdges: .trailing,
            castsShadow: false,
            borderWidth: 1.5
        )
    }
}

private struct FeedActivityPlacePostcard: View {
    let activity: FeedActivityDesignFixture

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FeedActivityMockupPlaceArtwork()
                .frame(height: 176)
                .overlay(alignment: .topLeading) {
                    Label("CHECKED IN", systemImage: "checkmark")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(WanderTheme.textInk.color)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 30)
                        .background(WanderTheme.surfaceBone.color.opacity(0.94))
                        .clipShape(Capsule())
                        .padding(WanderTheme.spacing3)
                }

            VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    HStack(alignment: .firstTextBaseline, spacing: WanderTheme.spacing2) {
                        Text(activity.placeName)
                            .font(.system(.title2, design: .serif, weight: .bold))
                            .lineLimit(2)

                        Spacer(minLength: WanderTheme.spacing1)

                        FeedActivityMockupRating(value: activity.rating)
                    }

                    Label(activity.placeDetail, systemImage: "fork.knife")
                        .font(WanderTypography.metadata)
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(2)
                }

                HStack(spacing: WanderTheme.spacing2) {
                    FeedActivityMockupAvatar(activity: activity, size: 36)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(activity.actorName) checked in")
                            .font(.system(size: 14, weight: .bold))
                        Text("\(activity.timestamp) · someone you follow")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(WanderTheme.textMuted.color)
                    }
                }

                Text("“\(activity.note)”")
                    .font(WanderTypography.body)
                    .foregroundStyle(WanderTheme.textInk.color)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()
                    .overlay(WanderTheme.borderHairline.color)

                FeedActivityMockupActionRow()
            }
            .padding(WanderTheme.spacing4)
        }
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        }
    }
}

private struct FeedActivityTrustedStoryCard: View {
    let activity: FeedActivityDesignFixture

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                FeedActivityMockupAvatar(activity: activity, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    (Text(activity.actorName).bold() + Text(" checked in"))
                        .font(.system(size: 15))
                        .lineLimit(2)

                    Text("\(activity.timestamp) · from your Feed")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }

                Spacer(minLength: WanderTheme.spacing1)

                Button(action: {}) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Activity actions")
            }

            HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                FeedActivityMockupPlaceArtwork()
                    .frame(width: 112, height: 128)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))

                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    Text(activity.placeName)
                        .font(WanderTypography.editorialCardTitle)
                        .lineLimit(2)

                    FeedActivityMockupMetadata(activity: activity, showsRatingInline: false)

                    FeedActivityMockupRating(value: activity.rating)

                    Spacer(minLength: 0)

                    Label("Open place", systemImage: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WanderTheme.terracottaDark.color)
                }
                .padding(.vertical, WanderTheme.spacing1)
                .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
            }

            Text("“\(activity.note)”")
                .font(.system(size: 15, weight: .medium, design: .serif))
                .foregroundStyle(WanderTheme.textInk.color)
                .padding(WanderTheme.spacing3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WanderTheme.terracottaTint.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))

            Divider()
                .overlay(WanderTheme.borderHairline.color)

            FeedActivityMockupActionRow(showsOverflow: false)
        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(WanderTheme.pinSocial.color)
                .frame(width: 4)
                .padding(.vertical, WanderTheme.spacing4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        }
    }
}

private struct FeedActivityMockupMetadata: View {
    let activity: FeedActivityDesignFixture
    let showsRatingInline: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: WanderTheme.spacing1) {
                Label(activity.placeDetail, systemImage: "fork.knife")
                    .lineLimit(1)

                if showsRatingInline {
                    Spacer(minLength: 0)
                    Label(activity.rating, systemImage: "star.fill")
                        .fontWeight(.black)
                        .foregroundStyle(WanderTheme.terracottaDark.color)
                        .fixedSize()
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Label(activity.placeDetail, systemImage: "fork.knife")
                    .lineLimit(2)
                if showsRatingInline {
                    Label(activity.rating, systemImage: "star.fill")
                        .fontWeight(.black)
                        .foregroundStyle(WanderTheme.terracottaDark.color)
                }
            }
        }
        .font(WanderTypography.metadata)
        .foregroundStyle(WanderTheme.textMuted.color)
    }
}

private struct FeedActivityMockupRating: View {
    let value: String

    var body: some View {
        Label(value, systemImage: "star.fill")
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundStyle(WanderTheme.terracottaDark.color)
            .padding(.horizontal, 9)
            .frame(minHeight: 30)
            .background(WanderTheme.terracottaTint.color)
            .clipShape(Capsule())
            .accessibilityLabel("Rating \(value) out of 5")
    }
}

private struct FeedActivityMockupActionRow: View {
    var showsOverflow = true

    var body: some View {
        HStack(spacing: WanderTheme.spacing1) {
            FeedActivityMockupActionButton(
                systemImage: "heart",
                count: "24",
                accessibilityLabel: "Like activity"
            )
            FeedActivityMockupActionButton(
                systemImage: "bubble.right",
                count: "6",
                accessibilityLabel: "Open comments"
            )
            FeedActivityMockupActionButton(
                systemImage: "paperplane",
                accessibilityLabel: "Share activity"
            )

            if showsOverflow {
                FeedActivityMockupActionButton(
                    systemImage: "ellipsis",
                    accessibilityLabel: "Activity actions"
                )
            }

            Spacer(minLength: WanderTheme.spacing1)

            FeedActivityMockupActionButton(
                systemImage: "bookmark",
                accessibilityLabel: "Add to Wanna"
            )
        }
        .frame(minHeight: WanderTheme.tapMinimum)
    }
}

private struct FeedActivityMockupActionButton: View {
    let systemImage: String
    var count: String?
    let accessibilityLabel: String

    var body: some View {
        Button(action: {}) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))

                if let count {
                    Text(count)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(WanderTheme.textInk.color)
            .frame(minWidth: WanderTheme.tapMinimum, minHeight: WanderTheme.tapMinimum)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(count ?? "")
    }
}

private struct FeedActivityMockupAvatar: View {
    let activity: FeedActivityDesignFixture
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [activity.avatarColor, activity.avatarColor.opacity(0.68)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Text(activity.actorInitials)
                    .font(.system(size: size * 0.34, weight: .black, design: .rounded))
                    .foregroundStyle(WanderTheme.textOnAction.color)
            }
            .frame(width: size, height: size)
            .accessibilityLabel(activity.actorName)
    }
}

private struct FeedActivityMockupPlaceArtwork: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [WanderTheme.skyTint.color, Color(red: 0.74, green: 0.84, blue: 0.77)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Circle()
                    .fill(WanderTheme.categorySun.color.opacity(0.9))
                    .frame(width: proxy.size.width * 0.2)
                    .position(x: proxy.size.width * 0.78, y: proxy.size.height * 0.23)

                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(red: 0.79, green: 0.36, blue: 0.25))
                    .frame(width: proxy.size.width * 0.58, height: proxy.size.height * 0.44)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color(red: 0.31, green: 0.20, blue: 0.14))
                            .frame(height: max(8, proxy.size.height * 0.08))
                    }
                    .position(x: proxy.size.width * 0.48, y: proxy.size.height * 0.68)

                HStack(spacing: proxy.size.width * 0.04) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(WanderTheme.sunTint.color)
                            .frame(
                                width: proxy.size.width * 0.1,
                                height: proxy.size.height * 0.14
                            )
                    }
                }
                .position(x: proxy.size.width * 0.48, y: proxy.size.height * 0.7)

                Rectangle()
                    .fill(WanderTheme.categoryMoss.color)
                    .frame(height: proxy.size.height * 0.16)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.94)

                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: min(proxy.size.width, proxy.size.height) * 0.22, weight: .bold))
                    .foregroundStyle(WanderTheme.terracotta.color, WanderTheme.surfaceBone.color)
                    .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
                    .position(x: proxy.size.width * 0.82, y: proxy.size.height * 0.63)
            }
        }
        .accessibilityLabel("Illustration of Dunsmoor")
    }
}

private struct FeedActivityMockupNextStoryHint: View {
    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Circle()
                .fill(WanderTheme.categorySage.color.opacity(0.55))
                .frame(width: 36, height: 36)
                .overlay {
                    Text("AR")
                        .font(.caption.weight(.black))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Andrew added Bar Flores to Wanna")
                    .font(.subheadline.weight(.bold))
                Text("1h · Echo Park · Bar")
                    .font(.caption)
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
        .accessibilityElement(children: .combine)
    }
}

private struct FeedActivityMockupTabBar: View {
    var body: some View {
        HStack {
            FeedActivityMockupTabItem(title: "Map", systemImage: "map", isSelected: false)
            FeedActivityMockupTabItem(title: "Feed", systemImage: "newspaper", isSelected: true)
            FeedActivityMockupTabItem(title: "Lists", systemImage: "bookmark.square", isSelected: false)
            FeedActivityMockupTabItem(title: "Profile", systemImage: "person.crop.circle", isSelected: false)
        }
        .padding(.top, WanderTheme.spacing2)
        .padding(.bottom, WanderTheme.spacing1)
        .background(WanderTheme.surfaceBone.color)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WanderTheme.borderHairline.color)
                .frame(height: 1)
        }
    }
}

private struct FeedActivityMockupTabItem: View {
    let title: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: isSelected ? .bold : .medium))
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
        }
        .foregroundStyle(isSelected ? WanderTheme.terracotta.color : WanderTheme.textMuted.color)
        .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct FeedActivityDesignFixture {
    let actorName: String
    let actorInitials: String
    let avatarColor: Color
    let timestamp: String
    let placeName: String
    let placeDetail: String
    let rating: String
    let note: String

    static let dunsmoor = FeedActivityDesignFixture(
        actorName: "Maya Chen",
        actorInitials: "MC",
        avatarColor: WanderTheme.avatarSofia.color,
        timestamp: "18m",
        placeName: "Dunsmoor",
        placeDetail: "Glassell Park · New American",
        rating: "4.8",
        note: "Order the cornbread. Worth a detour with a few friends."
    )
}
#endif
