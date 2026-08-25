#if DEBUG
import SwiftUI

/// Design-only REC-373 checkpoint. This intentionally lives outside the app
/// target and does not reuse or alter `FeedFeaturedCard`.
struct FeedFeaturedFullBleedMockupRoot: View {
    var body: some View {
        VStack(spacing: 0) {
            mockHeader

            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    Text("Featured for you")
                        .font(WanderTypography.editorialSectionTitle)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                            FeedFeaturedFullBleedMockupCard(
                                photoPosition: .topLeft,
                                name: "Alana’s Coffee Roasters",
                                detail: "Coffee shop · Venice · CA",
                                person: "Joe Lipshutz",
                                activity: "Checked in",
                                avatarColor: WanderTheme.avatarRyan.color
                            )

                            FeedFeaturedFullBleedMockupCard(
                                photoPosition: .topRight,
                                name: "All Time",
                                detail: "Restaurant · Los Angeles · CA",
                                person: "Joe Lipshutz",
                                activity: "Added to Wanna",
                                avatarColor: WanderTheme.pinSocial.color
                            )
                        }
                        .padding(.vertical, 1)
                    }
                    .contentMargins(.horizontal, WanderTheme.spacing4, for: .scrollContent)
                    .padding(.horizontal, -WanderTheme.spacing4)

                    Text("Activity")
                        .font(WanderTypography.editorialSectionTitle)
                        .padding(.top, WanderTheme.spacing2)

                    FeedFeaturedFullBleedActivityContext()
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.top, WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing12)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FeedFeaturedFullBleedMockupTabBar()
        }
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
        .foregroundStyle(WanderTheme.textInk.color)
    }

    private var mockHeader: some View {
        VStack(spacing: WanderTheme.spacing2) {
            HStack(spacing: WanderTheme.spacing2) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .bold))

                Text("date night spots from people you follow")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WanderTheme.textFaint.color)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, WanderTheme.spacing4)
            .background(WanderTheme.surfaceRaised.color.opacity(0.88))
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(Color.white.opacity(0.84), lineWidth: 1)
            }

            HStack(spacing: WanderTheme.spacing2) {
                HStack(spacing: 0) {
                    Text("Places")
                        .foregroundStyle(WanderTheme.terracottaDark.color)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(WanderTheme.terracottaTint.color)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().stroke(WanderTheme.terracotta.color, lineWidth: 2)
                        }

                    Text("People")
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .font(.system(size: 15, weight: .bold))
                .padding(3)
                .background(WanderTheme.surfaceRaised.color.opacity(0.88))
                .clipShape(Capsule())

                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(WanderTheme.terracottaDark.color)
                    .frame(width: 52, height: 52)
                    .background(WanderTheme.terracottaTint.color)
                    .clipShape(Circle())
                    .overlay {
                        Circle().stroke(WanderTheme.terracotta.color, lineWidth: 1)
                    }
            }
        }
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.top, WanderTheme.spacing2)
        .padding(.bottom, WanderTheme.spacing2)
    }
}

private struct FeedFeaturedFullBleedMockupCard: View {
    let photoPosition: FeedFeaturedFullBleedPhotoPosition
    let name: String
    let detail: String
    let person: String
    let activity: String
    let avatarColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FeedFeaturedFullBleedMockupPhoto(position: photoPosition)
                .frame(height: FeedFeaturedFullBleedMockupMetrics.fullBleedPhotoHeight)

            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Text(name)
                    .font(WanderTypography.editorialCompactTitle)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 42, alignment: .topLeading)

                Text(detail)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(1)

                HStack(alignment: .top, spacing: WanderTheme.spacing1) {
                    Circle()
                        .fill(avatarColor)
                        .overlay {
                            Text("JL")
                                .font(.system(size: 7, weight: .black))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 20, height: 20)

                    Text("• \(person) • \(activity)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WanderTheme.stateInfo.color)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(WanderTheme.spacing3)
        }
        .frame(
            width: FeedFeaturedFullBleedMockupMetrics.cardWidth,
            height: FeedFeaturedFullBleedMockupMetrics.cardHeight,
            alignment: .topLeading
        )
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        }
    }
}

private struct FeedFeaturedFullBleedMockupPhoto: View {
    let position: FeedFeaturedFullBleedPhotoPosition

    var body: some View {
        GeometryReader { proxy in
            Image("PlaceCarouselPhotos")
                .resizable()
                .frame(width: proxy.size.width * 2, height: proxy.size.width * 2)
                .position(
                    x: position == .topLeft ? proxy.size.width : 0,
                    y: (proxy.size.width + proxy.size.height) / 2
                )
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct FeedFeaturedFullBleedActivityContext: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FeedFeaturedFullBleedMockupPhoto(position: .topLeft)
                .frame(height: 156)

            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Text("Alana’s Coffee Roasters")
                    .font(WanderTypography.editorialCardTitle)

                Text("☕  Coffee shop · Venice · CA")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
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

private struct FeedFeaturedFullBleedMockupTabBar: View {
    var body: some View {
        HStack {
            mockTab("map", "Map", isSelected: false)
            mockTab("newspaper.fill", "Feed", isSelected: true)
            mockTab("bookmark.fill", "Lists", isSelected: false)
            mockTab("person.crop.circle.fill", "Profile", isSelected: false)
        }
        .padding(.horizontal, WanderTheme.spacing2)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(Color.white.opacity(0.86), lineWidth: 1)
        }
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.bottom, WanderTheme.spacing1)
    }

    private func mockTab(_ image: String, _ title: String, isSelected: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: image)
                .font(.system(size: 19, weight: .bold))
            Text(title)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(isSelected ? WanderTheme.terracottaDark.color : WanderTheme.textInk.color)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(isSelected ? WanderTheme.textInk.color.opacity(0.07) : .clear)
        .clipShape(Capsule())
    }
}

private enum FeedFeaturedFullBleedPhotoPosition {
    case topLeft
    case topRight
}

private enum FeedFeaturedFullBleedMockupMetrics {
    static let cardWidth: CGFloat = 184
    static let cardHeight: CGFloat = 226
    static let fullBleedPhotoHeight: CGFloat = 100
}

#Preview {
    FeedFeaturedFullBleedMockupRoot()
}
#endif
