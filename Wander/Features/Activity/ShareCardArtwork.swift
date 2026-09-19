import MapKit
import SwiftUI
import UIKit

/// The same content model drives the native preview, exported artwork and link metadata.
struct ShareCardContent: Equatable {
    enum Kind: String { case profile, map, list, place, checkIn, wanna, invitation }
    let kind: Kind
    let name: String
    var ownerName: String = ""
    var detail: String = ""
    var date: Date? = nil
    var count: Int = 0

    var firstName: String { ownerName.split(separator: " ").first.map(String.init) ?? ownerName }
    var headline: String {
        switch kind {
        case .profile: "Discover \(firstName)’s world"
        case .checkIn: "\(firstName) checked in"
        case .wanna: "\(firstName) wants to go"
        case .invitation: "Build this list with \(firstName)"
        default: name
        }
    }
    var subtitle: String? {
        switch kind {
        case .profile, .invitation: nil
        case .checkIn: [name, dateLabel].compactMap { $0 }.joined(separator: " · ")
        case .wanna: "\(name) · \(dateLabel ?? "On \(firstName)’s radar")"
        case .list: "\(countLabel) · Curated by \(firstName)"
        case .map: "\(firstName)’s saved map · \(countLabel)"
        case .place: detail.isEmpty ? nil : detail
        }
    }
    var action: String {
        switch kind { case .wanna: "Let’s Go"; case .invitation: "Join"; default: "View" }
    }
    var socialTitle: String {
        switch kind {
        case .checkIn: "\(firstName) was here."
        case .wanna: dateLabel ?? "On \(firstName)’s radar."
        default: headline
        }
    }
    var socialSubtitle: String? {
        switch kind {
        case .checkIn: "A check-in at \(name)\(dateLabel.map { " · \($0)" } ?? "")"
        case .wanna: "Wanna go to \(name)?"
        default: subtitle
        }
    }
    var dateLabel: String? {
        date.map { $0.formatted(.dateTime.month(.wide).day().year()) }
    }
    var countLabel: String { "\(count) \(count == 1 ? "place" : "places")" }
    var isCollage: Bool { kind == .list || kind == .invitation }
    var label: String {
        switch kind {
        case .profile: "PROFILE"; case .map: "SAVED MAP"; case .list: "LIST"
        case .place: "PLACE"; case .checkIn: "CHECK-IN"; case .wanna: "WANNA GO"; case .invitation: "INVITATION"
        }
    }
}

enum ShareCardFormat: String, CaseIterable, Identifiable {
    case link = "Link", story = "Story", post = "Post"
    var id: String { rawValue }
    var size: CGSize {
        switch self {
        case .link: CGSize(width: 390, height: 326)
        case .story: CGSize(width: 360, height: 640)
        case .post: CGSize(width: 360, height: 450)
        }
    }
}

struct ShareCardImages {
    var photos: [UIImage?] = []
    var avatar: UIImage? = nil
    var map: UIImage? = nil
}

struct ShareCardArtwork: View {
    @Environment(\.astirBrandMode) private var brand
    let content: ShareCardContent
    let images: ShareCardImages
    var format: ShareCardFormat = .link

    var body: some View {
        Group {
            if format == .link {
                VStack(spacing: 0) {
                    hero.frame(height: 238)
                    HStack(spacing: 12) {
                        appIcon.frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(content.headline).font(.system(size: 17, weight: .semibold, design: .serif))
                                .lineLimit(2).minimumScaleFactor(0.8)
                            if let subtitle = content.subtitle {
                                Text(subtitle).font(.custom("AvenirNext-Medium", size: 11))
                                    .foregroundStyle(brand.secondaryText).lineLimit(2)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        // Actions never disappear to make room for a long list title.
                        Text(content.action).font(.custom("AvenirNext-DemiBold", size: 13))
                            .fixedSize().padding(.horizontal, 13).frame(minHeight: 40)
                            .foregroundStyle(brand.accentForeground).background(brand.accent, in: Capsule())
                    }
                    .padding(14).frame(height: 88)
                }
                .background(brand.raisedBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            } else {
                social
            }
        }
        .foregroundStyle(brand.primaryText)
        .environment(\.dynamicTypeSize, .large)
        // Clipped, scaled photos can retain a larger hit area than their visible
        // bounds. Artwork is static and must never intercept the adjacent controls.
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([content.headline, content.subtitle, content.action].compactMap { $0 }.joined(separator: ". "))
    }

    private var appIcon: some View {
        Image("InvitationAppIcon").resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var hero: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                artwork.frame(width: proxy.size.width, height: proxy.size.height).clipped()
                if !(content.isCollage && content.count == 0) {
                    if images.map != nil {
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.7), location: 0.72),
                            .init(color: .clear, location: 1)
                        ], startPoint: .top, endPoint: .bottom)
                    } else {
                        LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    }
                    HStack(alignment: .center, spacing: 12) {
                        if content.kind == .profile { avatar(size: 60) }
                        VStack(alignment: .leading, spacing: 5) {
                            if content.kind == .checkIn || content.kind == .wanna {
                                HStack(spacing: 7) {
                                    avatar(size: 25)
                                    Text(content.kind == .wanna ? "WANNA GO" : "CHECKED IN")
                                        .font(.custom("AvenirNextCondensed-DemiBold", size: 12)).tracking(1.5)
                                }
                            }
                            Text(content.kind == .profile ? content.ownerName : content.name)
                                .font(.system(size: 23, weight: .semibold, design: .serif)).lineLimit(2)
                            let detail = content.isCollage ? content.countLabel : content.detail
                            if !detail.isEmpty {
                                Text(detail).font(.custom("AvenirNext-Medium", size: 13)).lineLimit(2)
                            }
                        }
                    }.foregroundStyle(.white).padding(18)
                        .padding(.bottom, images.map == nil ? 0 : 24)
                }
            }.clipped()
        }
    }

    @ViewBuilder private var artwork: some View {
        if let map = images.map {
            // Preserve the full snapshot, including MapKit attribution.
            Image(uiImage: map).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(brand.recessedBackground)
        } else if content.isCollage && content.count == 0 {
            VStack(spacing: 12) {
                Image(systemName: "rectangle.stack").font(.system(size: 34, weight: .light))
                Text(content.name).font(.system(size: 22, weight: .medium, design: .serif))
                Text("The first place is still to come.").font(.custom("AvenirNext-Medium", size: 13))
            }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity).background(brand.recessedBackground)
        } else if content.isCollage && content.count >= 2 {
            HStack(spacing: 3) {
                photo(0)
                if content.count == 2 { photo(1) }
                else {
                    VStack(spacing: 3) {
                        photo(1)
                        if content.count == 3 { photo(2) }
                        else { HStack(spacing: 3) { photo(2); photo(3) } }
                    }
                }
            }
        } else { photo(0) }
    }

    private func photo(_ index: Int) -> some View {
        GeometryReader { proxy in
            if images.photos.indices.contains(index), let image = images.photos[index] {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height).clipped()
            } else {
                ZStack {
                    brand.recessedBackground
                    Image(systemName: content.kind == .profile || content.kind == .map ? "map" : "mappin.circle")
                        .font(.system(size: 42, weight: .light)).foregroundStyle(brand.secondaryText)
                }.frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    private func avatar(size: CGFloat) -> some View {
        Group {
            if let avatar = images.avatar { Image(uiImage: avatar).resizable().scaledToFill() }
            else {
                Text(content.ownerName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined())
                    .font(.system(size: size * 0.31, weight: .medium, design: .serif))
                    .foregroundStyle(AstirTheme.ink.color)
            }
        }.frame(width: size, height: size).background(AstirTheme.paper.color)
            .clipShape(Circle()).overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 2))
    }

    private var social: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                appIcon.frame(width: 28, height: 28)
                Text("ASTIR").font(AstirTheme.wordmark(20)).tracking(2)
                Spacer()
                Text(content.label).font(.custom("AvenirNextCondensed-DemiBold", size: 11)).tracking(1.2)
            }.padding(.horizontal, 26).padding(.top, format == .story ? 64 : 22).padding(.bottom, 18)
            hero.frame(height: format == .story ? 278 : 208)
                .clipShape(RoundedRectangle(cornerRadius: 4)).padding(.horizontal, 18)
            VStack(alignment: .leading, spacing: 8) {
                Text(content.socialTitle).font(.system(size: 29, weight: .medium, design: .serif)).lineLimit(2).minimumScaleFactor(0.8)
                if let subtitle = content.socialSubtitle {
                    Text(subtitle).font(.custom("AvenirNext-Medium", size: 13)).foregroundStyle(brand.secondaryText).lineLimit(2)
                }
                HStack {
                    Rectangle().fill(brand.accent).frame(width: 22, height: 2)
                    Text("getrec.me").font(.custom("AvenirNext-DemiBold", size: 12))
                    Spacer()
                    Image(systemName: content.kind == .wanna ? "bookmark" : "arrow.up.right")
                }.padding(.top, 6)
            }.padding(.horizontal, 26).padding(.top, 20)
            Spacer(minLength: 0)
        }.frame(width: format.size.width, height: format.size.height).background(brand.background)
    }
}

@MainActor
enum ShareCardRenderer {
    static func decode(_ data: Data) async -> UIImage? {
        await PlacePhotoImagePipeline.shared.image(from: data, canonicalPlaceKey: "share-render",
            photoKey: UUID().uuidString, targetPixelSize: 1080)?.image
    }

    static func activityImages(_ context: ActivityEngagementContext, backend: WanderBackend) async -> ShareCardImages {
        let avatar = await ActivityShareArtworkRenderer.resolveAvatarImage(avatarURL: context.actor.avatarURL)
        var photo: UIImage?
        for media in context.media.prefix(4) {
            if let path = media.localAssetRef, let data = VisitPhotoLocalFileStore.data(from: path) {
                photo = await decode(data)
            } else if let raw = media.urlString, let url = URL(string: raw), url.scheme == "https",
                      let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15)),
                      (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 15_000_000 {
                photo = await decode(data)
            }
            if photo != nil { break }
        }
        if photo == nil, let placeID = context.placeServerID {
            let request = PlacePhotoRequest(placeID: placeID, name: context.placeName, address: nil, latitude: nil, longitude: nil, sourceProvider: nil, sourceProviderPlaceID: nil)
            photo = await placeImages([request], backend: backend).first ?? nil
        }
        return ShareCardImages(photos: [photo], avatar: avatar)
    }

    static func render(_ content: ShareCardContent, images: ShareCardImages, format: ShareCardFormat = .link,
                       brand: AstirBrandMode = .editorialLight) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardArtwork(content: content, images: images, format: format)
            .environment(\.astirBrandMode, brand).frame(width: format.size.width, height: format.size.height))
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }

    static func placeImages(_ requests: [PlacePhotoRequest], backend: WanderBackend) async -> [UIImage?] {
        var images: [UIImage?] = []
        for request in requests.prefix(4) {
            guard !Task.isCancelled else { return [] }
            if let photo = try? await backend.placePhoto(for: request),
               let data = try? await backend.placePhotoImageData(for: photo, canonicalPlaceKey: request.canonicalPhotoCacheKey, variant: .card) {
                images.append(await decode(data))
            } else { images.append(nil) }
        }
        return images
    }
}

extension ActivityEngagementContext {
    func shareCard(resolving wannas: [PlaceWannaSave]) -> ShareCardContent {
        var card = shareCard
        if let exactWanna = wannas.first(where: { $0.id.caseInsensitiveCompare(activityID) == .orderedSame }) {
            // An explicitly undated repeat must never inherit the parent’s date.
            card.date = exactWanna.plannedDate
        }
        return card
    }

    var shareCard: ShareCardContent {
        ShareCardContent(kind: ticketKind == .wanna ? .wanna : ticketKind == .checkIn ? .checkIn : .place,
                         name: placeName, ownerName: actor.displayName, detail: placeDetail,
                         date: ticketKind == .wanna ? plannedDate : occurredAt)
    }
}

/// Used at existing share entry points; preparation happens only after a deliberate tap.
struct ShareCardButton<Label: View>: View {
    let content: WanderShareContent
    let card: ShareCardContent
    var onTap: () -> Void = {}
    let loadImages: () async -> ShareCardImages
    @ViewBuilder let label: () -> Label
    @State private var showsPreview = false
    var body: some View {
        Button { onTap(); showsPreview = true } label: { label() }
            .buttonStyle(.plain)
            .sheet(isPresented: $showsPreview) {
                ActivitySharePreviewScreen(card: card, content: content, loadImages: loadImages)
            }
    }
}
