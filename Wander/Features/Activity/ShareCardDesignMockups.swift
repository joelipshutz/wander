#if DEBUG
import SwiftUI

/// Local design rehearsal only. No URLs are published and no share destinations are invoked.
enum ShareCardMockKind: String, CaseIterable, Identifiable {
    case profile, map, list, place, checkIn, wanna, invitation
    var id: String { rawValue }
    var title: String {
        switch self {
        case .profile: "Profile"
        case .map: "Saved map"
        case .list: "List"
        case .place: "Place"
        case .checkIn: "Check-in"
        case .wanna: "Wanna Go"
        case .invitation: "List invitation"
        }
    }
    var isActivity: Bool { self == .checkIn || self == .wanna }
    var hasCollage: Bool { self == .list || self == .invitation }
    var headline: String {
        switch self {
        case .profile: "Discover Ryan’s world"
        case .map: "A day in Silver Lake"
        case .list: "Good nights, great tables"
        case .place: "Bar Chelou"
        case .checkIn: "Ryan checked in"
        case .wanna: "Ryan wants to go"
        case .invitation: "Build this list with Ryan"
        }
    }
    var context: String {
        switch self {
        case .profile: "Places worth passing on · @ryan"
        case .map: "Ryan’s saved map · 6 places"
        case .list: "A few favorites, from Ryan"
        case .place: "French · Pasadena, Los Angeles"
        case .checkIn: "Bar Chelou · September 18"
        case .wanna: "Bar Chelou · On Ryan’s radar"
        case .invitation: "Good nights, great tables"
        }
    }
    var recipientAction: String {
        switch self {
        case .profile: "Explore Ryan’s places"
        case .map: "Explore this map"
        case .list: "Explore this list"
        case .place: "Save to Wanna Go"
        case .checkIn: "Open check-in"
        case .wanna: "Open Wanna Go"
        case .invitation: "Join the list"
        }
    }
}

private enum ShareCardMockFormat: String, CaseIterable, Identifiable {
    case link = "Link", story = "Story", post = "Post"
    var id: String { rawValue }
    var height: CGFloat { self == .story ? 640 : 450 }
}

struct ShareCardDesignMockupRoot: View {
    @State private var kind: ShareCardMockKind
    @State private var format: ShareCardMockFormat
    @State private var count = 4
    @State private var showsRecipient = false
    @State private var dark = false

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        _kind = State(initialValue: value(after: "-WanderShareCardMockup").flatMap(ShareCardMockKind.init) ?? .profile)
        _format = State(initialValue: value(after: "-ShareCardFormat").flatMap(ShareCardMockFormat.init) ?? .link)
        _count = State(initialValue: value(after: "-ShareCardCount").flatMap(Int.init).map { min(4, max(0, $0)) } ?? 4)
        _dark = State(initialValue: arguments.contains("-ShareCardDark"))
    }

    var body: some View {
        content
            .environment(\.astirBrandMode, dark ? .editorial : .editorialLight)
            .preferredColorScheme(dark ? .dark : .light)
    }

    private var content: some View {
        NavigationStack {
            ShareCardMockWorkspace(kind: $kind, format: $format, count: $count, showsRecipient: $showsRecipient)
                .navigationTitle("Share preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dark.toggle() } label: {
                            Image(systemName: dark ? "sun.max" : "moon")
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Toggle preview appearance")
                    }
                }
                .sheet(isPresented: $showsRecipient) {
                    ShareCardMockRecipient(kind: kind, count: count)
                }
        }
        .tint(dark ? AstirTheme.paper.color : AstirTheme.ink.color)
    }
}

private struct ShareCardMockWorkspace: View {
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var kind: ShareCardMockKind
    @Binding var format: ShareCardMockFormat
    @Binding var count: Int
    @Binding var showsRecipient: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                let headerLayout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
                headerLayout {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("A little worth sharing.").font(AstirTypography.sectionTitle)
                        Text("Native design previews").font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                    }
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    Picker("Share type", selection: $kind) {
                        ForEach(ShareCardMockKind.allCases) { item in Text(item.title).tag(item) }
                    }
                    .pickerStyle(.menu)
                    .tint(brand.accentText)
                    .accessibilityIdentifier("share-mock.kind")
                }
                Picker("Format", selection: $format) {
                    ForEach(ShareCardMockFormat.allCases) { item in Text(item.rawValue).tag(item) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("share-mock.format")

                if kind.hasCollage {
                    Stepper(value: $count, in: 0...4) {
                        Text("\(count) \(count == 1 ? "place" : "places") in this list")
                            .font(AstirTypography.bodySmall)
                    }
                    .accessibilityIdentifier("share-mock.count")
                }

                VStack(spacing: 14) {
                    if format == .link {
                        ShareCardMockLink(kind: kind, count: count)
                    } else {
                        ShareCardMockScaledArtwork(kind: kind, count: count, format: format)
                            .frame(maxWidth: format == .story ? 280 : 340)
                            .frame(maxWidth: .infinity)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: format == .link ? "link" : "photo")
                        Text(format == .link ? "Message link preview" : format == .story ? "9:16 · Instagram Stories / TikTok" : "4:5 · Instagram / TikTok photo post")
                    }
                    .font(AstirTypography.caption)
                    .foregroundStyle(brand.secondaryText)
                }

                Button { showsRecipient = true } label: {
                    HStack {
                        Image(systemName: "arrow.up.right")
                        Text("Preview opening link")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(AstirTypography.control)
                    .padding(16)
                    .foregroundStyle(brand.accentForeground)
                    .background(brand.accent, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("share-mock.open")
                Text(format == .link
                     ? "Sample content for design review. Tap above to rehearse the recipient’s view."
                     : "Artwork preview. A separate share link opens this exact item; link stickers and website routing come in the build phase.")
                    .font(AstirTypography.bodySmall)
                    .foregroundStyle(brand.secondaryText)
            }
            .foregroundStyle(brand.primaryText)
            .padding(20)
        }
        .background(brand.background)
        .accessibilityIdentifier("share-mock.workspace")
    }
}

private struct ShareCardMockLink: View {
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.dynamicTypeSize) private var typeSize
    let kind: ShareCardMockKind
    let count: Int

    var body: some View {
        VStack(spacing: 0) {
            ShareCardMockHero(kind: kind, count: count)
                .frame(height: kind == .profile ? 238 : 226)
                // The artwork is a fixed export canvas; the adjacent title remains scalable.
                .environment(\.dynamicTypeSize, .large)
            ViewThatFits(in: .horizontal) {
                if !typeSize.isAccessibilitySize { footer(compact: false) }
                footer(compact: true)
            }
        }
        .background(brand.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(brand.border.opacity(0.3), lineWidth: 0.75))
    }

    private func footer(compact: Bool) -> some View {
        HStack(spacing: 12) {
            if !typeSize.isAccessibilitySize {
                Image("InvitationAppIcon").resizable().scaledToFit()
                    .frame(width: compact ? 34 : 42, height: compact ? 34 : 42)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(kind.headline)
                    .font(.system(.headline, design: .serif).weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("share-mock.headline")
                Text(footerSubtitle)
                    .font(AstirTypography.caption)
                    .foregroundStyle(brand.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !compact {
                Text("View").font(AstirTypography.bodySmall.weight(.semibold))
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .foregroundStyle(brand.accentForeground)
                    .background(brand.accent, in: Capsule())
                    .accessibilityHidden(true)
            }
        }
        .padding(14)
    }

    private var footerSubtitle: String {
        if kind == .list { return "\(count) \(count == 1 ? "place" : "places") · Curated by Ryan" }
        return kind.context
    }
}

private struct ShareCardMockHero: View {
    let kind: ShareCardMockKind
    let count: Int

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                artwork
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                if kind != .profile && !(kind.hasCollage && count == 0) {
                    LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 5) {
                        if kind.isActivity {
                            HStack(spacing: 7) {
                                ShareCardMockAvatar(size: 25)
                                Text(kind == .checkIn ? "CHECKED IN" : "WANNA GO")
                                    .font(AstirTypography.metadata).tracking(1.5)
                            }
                        }
                        Text(visualTitle).font(.system(.title2, design: .serif).weight(.semibold))
                        Text(visualSubtitle).font(AstirTypography.bodySmall)
                    }
                    .foregroundStyle(.white).padding(18)
                }
                if kind == .profile {
                    LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                    HStack(alignment: .center, spacing: 14) {
                        ShareCardMockAvatar(size: 66)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Ryan Lieblein").font(.system(.title2, design: .serif).weight(.semibold))
                            Text("@ryan · Los Angeles").font(AstirTypography.bodySmall)
                        }
                    }
                    .foregroundStyle(.white).padding(18)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }

    @ViewBuilder private var artwork: some View {
        if kind == .profile || kind == .map {
            Image("OnboardingMapDiary").resizable().scaledToFill()
                .accessibilityLabel("Sample saved-place map of Silver Lake")
        } else if kind.hasCollage {
            ShareCardMockCollage(count: count)
        } else {
            CommonGroundPhoto(tile: kind == .checkIn ? 2 : kind == .wanna ? 3 : 0)
        }
    }

    private var visualTitle: String {
        if kind.hasCollage { return "Good nights,\ngreat tables" }
        if kind == .map { return "A day in Silver Lake" }
        return "Bar Chelou"
    }
    private var visualSubtitle: String {
        if kind.hasCollage { return "Los Angeles · \(count) \(count == 1 ? "place" : "places")" }
        if kind == .map { return "6 places · Saved by Ryan" }
        return "Pasadena · French"
    }
}

private struct ShareCardMockAvatar: View {
    let size: CGFloat
    var body: some View {
        Text("RL")
            .font(.system(size: size * 0.31, weight: .medium, design: .serif))
            .foregroundStyle(AstirTheme.ink.color)
            .frame(width: size, height: size)
            .background(AstirTheme.paper.color, in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 2))
            .accessibilityHidden(true)
    }
}

private struct ShareCardMockCollage: View {
    @Environment(\.astirBrandMode) private var brand
    let count: Int
    var body: some View {
        if count == 0 {
            VStack(spacing: 12) {
                Image(systemName: "rectangle.stack").font(.system(size: 36, weight: .light))
                Text("Good nights, great tables").font(AstirTypography.sectionTitle)
                Text("The first place is still to come.").font(AstirTypography.bodySmall)
            }
            .foregroundStyle(brand.primaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(brand.recessedBackground)
        } else if count == 1 {
            CommonGroundPhoto(tile: 0)
        } else {
            HStack(spacing: 3) {
                CommonGroundPhoto(tile: 0)
                if count == 2 {
                    CommonGroundPhoto(tile: 3)
                } else {
                    VStack(spacing: 3) {
                        CommonGroundPhoto(tile: 1)
                        if count == 3 {
                            CommonGroundPhoto(tile: 3)
                        } else {
                            HStack(spacing: 3) {
                                CommonGroundPhoto(tile: 2)
                                CommonGroundPhoto(tile: 3)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ShareCardMockScaledArtwork: View {
    let kind: ShareCardMockKind
    let count: Int
    let format: ShareCardMockFormat
    var body: some View {
        GeometryReader { geometry in
            ShareCardMockSocial(kind: kind, count: count, story: format == .story)
                .frame(width: 360, height: format.height)
                .environment(\.dynamicTypeSize, .large)
                .scaleEffect(geometry.size.width / 360, anchor: .topLeading)
        }
        .aspectRatio(360 / format.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct ShareCardMockSocial: View {
    @Environment(\.astirBrandMode) private var brand
    let kind: ShareCardMockKind
    let count: Int
    let story: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image("InvitationAppIcon").resizable().frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                Text("ASTIR").font(AstirTheme.wordmark(20)).tracking(2)
                Spacer()
                Text(kind.title.uppercased()).font(.custom("AvenirNextCondensed-DemiBold", size: 11)).tracking(1.2)
            }
            .padding(.horizontal, 26)
            .padding(.top, story ? 64 : 22)
            .padding(.bottom, 18)

            ShareCardMockHero(kind: kind, count: count)
                .frame(height: story ? 278 : 208)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.horizontal, 18)

            VStack(alignment: .leading, spacing: 8) {
                Text(socialTitle)
                    .font(.system(size: kind == .profile ? 30 : 29, weight: .medium, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)
                Text(socialSubtitle)
                    .font(.custom("AvenirNext-Medium", size: 13))
                    .foregroundStyle(brand.secondaryText)
                HStack {
                    Rectangle().fill(brand.accent).frame(width: 22, height: 2)
                    Text("getrec.me").font(.custom("AvenirNext-DemiBold", size: 12))
                    Spacer()
                    Image(systemName: kind == .wanna ? "bookmark" : "arrow.up.right")
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 26).padding(.top, 20)
            Spacer(minLength: 0)
            if story {
                // Room for platform overlays/link stickers; no fake clickable button in the bitmap.
                Color.clear.frame(height: 74)
            }
        }
        .foregroundStyle(brand.primaryText)
        .background(brand.background)
    }

    private var socialTitle: String {
        switch kind {
        case .checkIn: "Ryan was here."
        case .wanna: "On Ryan’s radar."
        default: kind.headline
        }
    }
    private var socialSubtitle: String {
        if kind == .checkIn { return "A check-in at Bar Chelou · September 18" }
        if kind == .wanna { return "Wanna go to Bar Chelou?" }
        if kind.hasCollage { return "\(count) \(count == 1 ? "place" : "places") · Los Angeles · @ryan" }
        return kind.context
    }
}

private struct ShareCardMockRecipient: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.astirBrandMode) private var brand
    let kind: ShareCardMockKind
    let count: Int
    @State private var showsDesignNotice = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("From Ryan").font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                    ShareCardMockLink(kind: kind, count: count)
                    Text(kind.recipientAction).font(AstirTypography.sheetTitle)
                    Text("\(kind.title) destination preview. The production link will open this specific shared item.")
                        .font(AstirTypography.body).foregroundStyle(brand.secondaryText)
                    Button(kind.recipientAction) { showsDesignNotice = true }
                        .font(AstirTypography.control).frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(brand.accentForeground)
                        .background(brand.accent, in: Capsule())
                    Text("Design rehearsal · no changes will be saved")
                        .font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                }.padding(20)
            }
            .background(brand.background).foregroundStyle(brand.primaryText)
            .navigationTitle("Opened link").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Preview only", isPresented: $showsDesignNotice) {
                Button("OK", role: .cancel) {}
            } message: { Text("Production sharing and website routes will be connected after design approval.") }
        }
    }
}

#Preview { ShareCardDesignMockupRoot() }
#endif
