import MapKit

@main
struct ListHeaderPreviewApp: App {
    private let light = ProcessInfo.processInfo.arguments.contains("--light")
    var body: some Scene {
        WindowGroup {
            ListHeaderPreview()
                .environment(\.astirBrandMode, light ? .editorialLight : .editorial)
                .preferredColorScheme(light ? .light : .dark)
        }
    }
}

struct ListHeaderPreview: View {
    @Environment(\.astirBrandMode) private var mode
    @State private var path = ["detail"]
    @State private var lastAction: String?
    private let owner = ProcessInfo.processInfo.arguments.contains("--owner")
    private let collaborator = ProcessInfo.processInfo.arguments.contains("--collaborator")

    var body: some View {
        TabView(selection: .constant(2)) {
            Text("Map").tabItem { Label("Map", systemImage: "map.fill") }.tag(0)
            Text("Feed").tabItem { Label("Feed", systemImage: "newspaper.fill") }.tag(1)
            NavigationStack(path: $path) {
                Button("Open list") { path = ["detail"] }
                    .navigationDestination(for: String.self) { _ in detail }
            }
            .tabItem {
                Label { Text("Lists") } icon: { Image(uiImage: NarrowPaperTabIcon.image) }
            }.tag(2)
            Text("Profile").tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }.tag(3)
        }
        .tint(mode.accent)
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Weekend favorites").font(AstirTypography.screenTitle)
                    .padding(.top, 8)
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 32))
                    Text(owner ? "You" : "Alex Morgan").font(AstirTypography.cardTitle)
                    Text(collaborator ? "shared list" : "solo list").foregroundStyle(mode.secondaryText)
                    Spacer(minLength: 0)
                    Text("6 places").foregroundStyle(mode.accentText)
                }.font(AstirTypography.caption).padding(.vertical, 12)
                mapCard
                Text("places").font(AstirTypography.sectionTitle)
                place("Santa Monica Seafood", "check-in · Oyster bar · Santa Monica", "🦪")
                place("RVR", "check-in · Japanese · Los Angeles", "🇯🇵")
                place("Mutsu", "wanna go · Japanese · Los Angeles", "🇯🇵")
            }.padding(16)
        }
        .background(mode.background.ignoresSafeArea())
        .foregroundStyle(mode.primaryText)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ListDetailHeaderToolbar {
                Button { lastAction = "Share list" } label: {
                    ListDetailHeaderActionLabel(systemImage: "square.and.arrow.up")
                }.accessibilityLabel("Share list")
                if owner || collaborator {
                    Button { lastAction = "Add places to list" } label: {
                        ListDetailHeaderActionLabel(systemImage: "plus")
                    }.accessibilityLabel("Add places to list")
                }
                if owner {
                    Button { lastAction = "Edit list" } label: {
                        ListDetailHeaderActionLabel(systemImage: "pencil")
                    }.accessibilityLabel("Edit list")
                } else {
                    Menu {
                        if collaborator {
                            Button("Leave List", role: .destructive) { lastAction = "Leave List" }
                        }
                        Button("Report list", systemImage: "exclamationmark.bubble") { lastAction = "Report list" }
                    } label: {
                        ListDetailHeaderActionLabel(systemImage: "ellipsis")
                    }.accessibilityLabel("List actions")
                }
            }
        }
        .alert(lastAction ?? "", isPresented: Binding(get: { lastAction != nil }, set: { if !$0 { lastAction = nil } })) {
            Button("OK") { lastAction = nil }
        } message: { Text("Preview action received") }
    }

    private var mapCard: some View {
        VStack(spacing: 0) {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 34.015, longitude: -118.48),
                span: MKCoordinateSpan(latitudeDelta: 0.11, longitudeDelta: 0.11)
            ))) {
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: 34.03, longitude: -118.49)) {
                    Text("🦪").font(.title2).padding(12).background(mode.background, in: Circle())
                        .overlay(Circle().stroke(.cyan.opacity(0.7), lineWidth: 3))
                }
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: 33.995, longitude: -118.46)) {
                    Text("5").font(.title2.bold()).padding(12).background(mode.background, in: Circle())
                        .overlay(Circle().stroke(mode.accent, style: StrokeStyle(lineWidth: 3, dash: [2, 3])))
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .allowsHitTesting(false)
            .frame(height: 190)
            HStack {
                Label("View map", systemImage: "map.fill").font(AstirTypography.cardTitle)
                Spacer()
                Text("6 places").font(AstirTypography.bodySmall)
                Image(systemName: "chevron.right").font(.body.bold())
            }.padding(16).background(mode.raisedBackground)
        }.clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(mode.border))
    }

    private func place(_ name: String, _ subtitle: String, _ emoji: String) -> some View {
        HStack(spacing: 14) {
            Text(emoji).font(.system(size: 26)).frame(width: 48, height: 48)
                .background(mode.background, in: Circle())
                .overlay(Circle().stroke(.cyan.opacity(0.6), lineWidth: 3))
            VStack(alignment: .leading, spacing: 5) {
                Text(name).font(AstirTypography.cardTitle)
                Text(subtitle).font(AstirTypography.bodySmall).foregroundStyle(mode.secondaryText)
            }
            Spacer(minLength: 0)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(mode.raisedBackground, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(mode.border))
    }
}

// Preview proposal: 22×26pt paper canvas.
// Native tab selection supplies tint.
@MainActor
private enum NarrowPaperTabIcon {
    static let image: UIImage = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 22, height: 26))
        return renderer.image { context in
            UIColor.black.setFill()
            UIBezierPath(roundedRect: CGRect(x: 1, y: 1, width: 20, height: 24), cornerRadius: 2.4).fill()
            context.cgContext.setBlendMode(.clear)
            for y: CGFloat in [6.5, 13, 19.5] {
                UIBezierPath(ovalIn: CGRect(x: 3.6, y: y - 1, width: 2, height: 2)).fill()
                UIBezierPath(
                    roundedRect: CGRect(x: 7.2, y: y - 0.7, width: 11.2, height: 1.4),
                    cornerRadius: 0.7
                ).fill()
            }
        }.withRenderingMode(.alwaysTemplate)
    }()
}
