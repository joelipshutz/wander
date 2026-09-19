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
    var recipientAction: String {
        switch self {
        case .profile: "Explore Ryan’s places"
        case .map: "Explore this map"
        case .list: "Explore this list"
        case .place: "Save to Wanna Go"
        case .checkIn: "Open check-in"
        case .wanna: "Let’s Go"
        case .invitation: "Join the list"
        }
    }
}

private typealias ShareCardMockFormat = ShareCardFormat

extension ShareCardMockKind {
    func card(count: Int, dated: Bool = false) -> ShareCardContent {
        let name: String = switch self {
        case .profile: "Ryan Lieblein"
        case .map: "A day in Silver Lake"
        case .list, .invitation: "Good nights, great tables"
        default: "Bar Chelou"
        }
        return ShareCardContent(kind: ShareCardContent.Kind(rawValue: rawValue)!, name: name,
            ownerName: "Ryan Lieblein", detail: self == .profile ? "@ryan · Los Angeles" : "Pasadena · French",
            date: self == .checkIn || (self == .wanna && dated) ? Date(timeIntervalSince1970: 1_789_754_400) : nil,
            count: self == .map ? 6 : count)
    }
    @MainActor var images: ShareCardImages {
        ShareCardImages(photos: CommonGroundMockImages.photos.map { Optional($0) },
            map: self == .profile || self == .map ? UIImage(named: "OnboardingMapDiary") : nil)
    }
}

struct ShareCardDesignMockupRoot: View {
    @State private var kind: ShareCardMockKind
    @State private var format: ShareCardMockFormat
    @State private var count = 4
    @State private var showsRecipient = false
    @State private var dark = false
    @State private var dated = false
    @State private var showsShareSheet = false

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
        _dated = State(initialValue: arguments.contains("-ShareCardDated"))
    }

    var body: some View {
        content
            .environment(\.astirBrandMode, dark ? .editorial : .editorialLight)
            .preferredColorScheme(dark ? .dark : .light)
    }

    private var content: some View {
        NavigationStack {
            ShareCardMockWorkspace(kind: $kind, format: $format, count: $count, dated: $dated, showsRecipient: $showsRecipient)
                .navigationTitle("Share preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Try sharing") { showsShareSheet = true }
                            .accessibilityIdentifier("share-mock.try")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dark.toggle() } label: {
                            Image(systemName: dark ? "sun.max" : "moon")
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Toggle preview appearance")
                    }
                }
                .sheet(isPresented: $showsShareSheet) {
                    ActivitySharePreviewScreen(card: kind.card(count: count, dated: dated),
                        content: .place(item: URL(string: "https://getrec.me/places/40000000-0000-0000-0000-000000000264")!, name: "Sample preview", message: "Sample preview"),
                        loadImages: { kind.images })
                }
                .sheet(isPresented: $showsRecipient) {
                    ShareCardMockRecipient(kind: kind, count: count, dated: dated)
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
    @Binding var dated: Bool
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
                        Text("Production cards · sample content").font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
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

                if kind == .wanna {
                    Toggle("Planned date", isOn: $dated).accessibilityIdentifier("share-mock.dated")
                }
                VStack(spacing: 14) {
                    ShareCardMockScaledArtwork(kind: kind, count: count, format: format, dated: dated)
                        .frame(maxWidth: format == .story ? 280 : .infinity)
                        .frame(maxWidth: .infinity)
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
                     : "Artwork uses the production renderer. Photos and names here are sample content.")
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

private struct ShareCardMockScaledArtwork: View {
    let kind: ShareCardMockKind
    let count: Int
    var format: ShareCardFormat = .link
    var dated = false
    var body: some View {
        GeometryReader { geometry in
            ShareCardArtwork(content: kind.card(count: count, dated: dated), images: kind.images, format: format)
                .frame(width: format.size.width, height: format.size.height)
                .scaleEffect(geometry.size.width / format.size.width, anchor: .topLeading)
                .accessibilityIdentifier("share-mock.headline")
        }
        .aspectRatio(format.size, contentMode: .fit)
    }
}

private struct ShareCardMockRecipient: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.astirBrandMode) private var brand
    let kind: ShareCardMockKind
    let count: Int
    let dated: Bool
    @State private var showsDesignNotice = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("From Ryan").font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                    ShareCardMockScaledArtwork(kind: kind, count: count, dated: dated)
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
