import SwiftUI
import MapKit

// Compiled with the production design-system definitions by render-build.py.
// Sample content only; these buttons never call app services.
@main
struct GlassApprovalPreviewApp: App {
    var body: some Scene {
        WindowGroup { GlassApprovalPreview() }
    }
}

struct GlassApprovalPreview: View {
    private let arguments = ProcessInfo.processInfo.arguments
    private var scene: String {
        guard let index = arguments.firstIndex(of: "--scene"), arguments.indices.contains(index + 1) else { return "map" }
        return arguments[index + 1]
    }
    private var light: Bool { arguments.contains("--light") }
    private var mode: AstirBrandMode { light ? .editorialLight : .editorial }
    @State private var selection = "first"
    @State private var actionCount = 0
    @State private var activeCardAction: PlaceCardPreviewAction?
    @State private var query = ""

    var body: some View {
        ZStack {
            mode.background.ignoresSafeArea()
            switch scene {
            case "map": mapScreen
            case "feed": feedScreen
            case "lists": listsScreen
            default: mapScreen
            }
        }
        .foregroundStyle(mode.primaryText)
        .environment(\.astirBrandMode, mode)
        .preferredColorScheme(light ? .light : .dark)
        .overlay(alignment: .topTrailing) {
            if actionCount > 0 {
                Text("Action \(actionCount)")
                    .font(.caption2).padding(5).background(mode.background, in: Capsule())
                    .accessibilityIdentifier("preview.actionCount")
            }
        }
    }

    private func action() { actionCount += 1 }
    private func plus(_ label: String) -> some View {
        AstirIconActionButton(systemImage: "plus", accessibilityLabel: label, isAddAction: true, action: action)
    }
    private func tabs(_ first: String, _ second: String) -> some View {
        AstirEditorialSegmentedSwitch(
            options: [WanderSegmentOption(id: "first", title: first), WanderSegmentOption(id: "second", title: second)],
            selection: $selection, interactive: true
        )
    }
    private var search: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
            TextField("Search places", text: $query)
                .font(AstirTypography.control)
        }
        .foregroundStyle(mode.secondaryText).padding(.horizontal, 12).frame(height: 44)
        .astirOutlinedSurface(castsShadow: true, interactive: true)
    }
    private var map: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.0034, longitude: -118.4800),
            span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
        ))) {
            Annotation("Coffee", coordinate: CLLocationCoordinate2D(latitude: 34.004, longitude: -118.484)) {
                Image(systemName: "cup.and.saucer.fill").padding(10)
                    .foregroundStyle(AstirTheme.ink.color).background(mode.accent, in: Circle())
            }
            Annotation("Dinner", coordinate: CLLocationCoordinate2D(latitude: 33.999, longitude: -118.473)) {
                Image(systemName: "fork.knife").padding(10)
                    .foregroundStyle(AstirTheme.ink.color).background(mode.accent, in: Circle())
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls { }
    }
    private var filters: some View {
        HStack(spacing: 4) {
            ForEach(["Featured", "Friends", "You", "More"], id: \.self) { label in
                Button(action: action) {
                    Text(label).font(AstirTypography.label)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(label == "Featured" ? mode.accentText : mode.primaryText)
                        .astirGlassSurface(cornerRadius: 18, selected: label == "Featured", castsShadow: true)
                }.buttonStyle(.plain)
            }
        }
    }
    private var mapScreen: some View {
        ZStack {
            map.ignoresSafeArea()
            VStack {
                AstirFloatingHeaderSurface {
                    VStack(alignment: .leading, spacing: 4) {
                        AstirMastheadLockup(presentation: .localizedBlur)
                        filters
                    }.padding(.horizontal, 12)
                }
                Spacer()
                previewPlaceCard
                WanderGlassButtonCluster(mergeSpacing: 12) {
                    HStack(spacing: 12) { search; plus("Map add") }
                }.padding(.horizontal, 12)
                bottomNav("Map")
            }.padding(.top, 8)
        }
    }
    private var photo: some View {
        Image(uiImage: UIImage(contentsOfFile: Bundle.main.path(forResource: "places", ofType: "png")!)!)
            .resizable().scaledToFill()
    }
    private var previewPlaceCard: some View {
        ZStack(alignment: .bottomLeading) {
            photo.frame(height: 178).clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A neighborhood favorite").font(AstirTypography.sectionTitle)
                    Text("Coffee · Ocean Park").font(AstirTypography.caption)
                    Text("4.8 ★   ·   0.3 mi").font(AstirTypography.label)
                }.foregroundStyle(.white)
                Spacer()
                ZStack {
                    WanderGlassButtonCluster(mergeSpacing: 0) {
                        VStack(spacing: 4) {
                            cardAction("plus", id: .primary)
                            cardAction("list.bullet", id: .addToList)
                            cardAction("square.and.arrow.up", id: .share)
                        }
                    }
                    VStack(spacing: 4) {
                        ForEach(["plus", "list.bullet", "square.and.arrow.up"], id: \.self) { icon in
                            Image(systemName: icon).font(.system(size: 17, weight: .black))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                        }
                    }.allowsHitTesting(false)
                }
            }.padding(16)
        }
        .frame(height: 178).clipShape(RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 12)
    }
    private func cardAction(_ icon: String, id: PlaceCardPreviewAction) -> some View {
        Button(action: action) { Image(systemName: icon) }
            .buttonStyle(PlaceCardGlassActionButtonStyle(actionID: id, activeAction: $activeCardAction))
            .accessibilityLabel("Place card \(icon)")
    }
    private var feedScreen: some View {
        VStack(spacing: 16) {
            AstirFloatingHeaderSurface(mergeSpacing: WanderTheme.spacing2) {
                VStack(spacing: 8) {
                    HStack(spacing: 8) { AstirMastheadLockup(presentation: .localizedBlur); search }
                    HStack(spacing: 8) { tabs("Places", "People"); plus("Feed add") }
                }.padding(.horizontal, 16).padding(.vertical, 8)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Worth coming back for").font(AstirTypography.screenTitle)
                    Text("Places from your people").font(AstirTypography.body).foregroundStyle(mode.secondaryText)
                    photo.frame(height: 270).clipped().clipShape(RoundedRectangle(cornerRadius: 22))
                    Text("A good morning starts here").font(AstirTypography.sectionTitle)
                    Text("Coffee · Ocean Park").font(AstirTypography.caption).foregroundStyle(mode.secondaryText)
                    Divider()
                    Label("Saved by a friend", systemImage: "person.crop.circle").font(AstirTypography.bodySmall)
                }.padding(.horizontal, 24)
            }
            bottomNav("Feed")
        }
    }
    private var listsScreen: some View {
        VStack(spacing: 20) {
            AstirFloatingHeaderSurface(mergeSpacing: WanderTheme.spacing2) {
                HStack(spacing: 8) { tabs("My lists", "Shared"); plus("New list") }
                    .padding(.horizontal, 16).padding(.vertical, 8)
            }
            VStack(alignment: .leading, spacing: 16) {
                Text("Your good places").font(AstirTypography.screenTitle)
                ForEach(["Slow mornings", "Around the neighborhood", "Next dinner"], id: \.self) { title in
                    HStack(spacing: 16) {
                        Image(systemName: "list.bullet").font(.title).foregroundStyle(mode.accent)
                            .frame(width: 60, height: 74).background(mode.accentWash, in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(title).font(AstirTypography.cardTitle)
                            Text("6 places · Only you").font(AstirTypography.caption).foregroundStyle(mode.secondaryText)
                        }
                        Spacer()
                    }.padding(16).background(mode.raisedBackground, in: RoundedRectangle(cornerRadius: 20))
                }
            }.padding(.horizontal, 24)
            Spacer()
            bottomNav("Lists")
        }
    }
    private func bottomNav(_ active: String) -> some View {
        HStack {
            ForEach(["Map", "Feed", "Lists", "Profile"], id: \.self) { name in
                let symbol = ["Map": "map", "Feed": "newspaper", "Lists": "list.bullet", "Profile": "person.crop.circle"][name]!
                VStack(spacing: 4) { Image(systemName: symbol).font(.system(size: 21)); Text(name).font(.system(size: 10)) }
                    .foregroundStyle(name == active ? mode.accent : mode.secondaryText).frame(maxWidth: .infinity)
            }
        }.padding(12).background(mode.background.opacity(0.96))
    }
}
