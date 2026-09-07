import SwiftUI
import MapKit

// Design-only native approval harness. Production AddScreen is untouched.
private enum Theme {
    static let background = Color(red: 20/255, green: 23/255, blue: 20/255)
    static let raised = Color(red: 27/255, green: 31/255, blue: 27/255)
    static let recessed = Color(red: 16/255, green: 18/255, blue: 16/255)
    static let text = Color(red: 242/255, green: 233/255, blue: 219/255)
    static let muted = Color(red: 152/255, green: 149/255, blue: 141/255)
    static let line = Color(red: 116/255, green: 120/255, blue: 111/255)
    static let accent = Color(red: 240/255, green: 90/255, blue: 60/255)
    static let title = Font.system(.title2, design: .serif).weight(.semibold)
    static let section = Font.system(.title3, design: .serif).weight(.semibold)
    static let card = Font.custom("AvenirNext-DemiBold", size: 16, relativeTo: .body)
    static let bodySmall = Font.custom("AvenirNext-Regular", size: 14, relativeTo: .subheadline)
    static let caption = Font.custom("AvenirNext-Medium", size: 12, relativeTo: .caption)
    static let label = Font.custom("AvenirNext-DemiBold", size: 13, relativeTo: .caption)
}
private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 440
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
@main struct PreviewApp: App {
    var body: some Scene { WindowGroup { PreviewRoot().preferredColorScheme(.dark) } }
}
struct PreviewRoot: View {
    @State private var presented = false
    var body: some View {
        ZStack(alignment: .topLeading) {
            Map(initialPosition: .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 34.11, longitude: -118.30), span: MKCoordinateSpan(latitudeDelta: 0.17, longitudeDelta: 0.17))))
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("ASTIR").font(.system(size: 22, weight: .medium, design: .serif)).tracking(5.2)
                    Text("OCEAN PARK").font(.custom("AvenirNextCondensed-DemiBold", size: 9)).tracking(2.1)
                }.padding(10).background(Theme.recessed, in: RoundedRectangle(cornerRadius: 16))
                HStack(spacing: 4) {
                    pill("", symbol: "plus", active: true)
                    pill("Friends", symbol: "person.2.fill")
                    pill("You", symbol: "person.fill")
                    pill("More", symbol: "line.3.horizontal")
                }
            }.padding(.horizontal, 20).padding(.top, 10)
        }
        .foregroundStyle(Theme.text)
        .sheet(isPresented: $presented) { AddOptionsPreview() }
        .task { presented = true }
    }
    private func pill(_ label: String, symbol: String, active: Bool = false) -> some View {
        HStack(spacing: 7) { Image(systemName: symbol); if !label.isEmpty { Text(label) } }
            .font(Theme.label).frame(maxWidth: .infinity).frame(height: 44)
            .background(active ? Theme.accent : Theme.recessed, in: Capsule())
            .overlay(Capsule().stroke(Theme.line, lineWidth: active ? 0 : 1))
    }
}
struct AddOptionsPreview: View {
    @State private var expanded = false
    @State private var height: CGFloat = 440
    @State private var detent: PresentationDetent = .height(440)
    @Environment(\.dismiss) private var dismiss
    private let places = [
        ("🌲", "Ocean Park Pocket Park", "nearby · 2547 Third St · Santa Monica · Park"),
        ("🚆", "4th St & Ocean Park Blvd Stop", "nearby · Santa Monica · Transit station"),
        ("☕️", "Neighborhood Coffee", "nearby · Santa Monica · Coffee shop"),
        ("🌳", "Ocean View Park", "nearby · Santa Monica · Park"),
        ("🍽️", "Main Street Kitchen", "nearby · Santa Monica · Restaurant")
    ]
    var body: some View {
        Group {
            if expanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        search
                        Button(action: back) { Label("back to add options", systemImage: "chevron.left").font(Theme.label).foregroundStyle(Theme.accent) }
                            .accessibilityIdentifier("back")
                        ForEach(places.indices, id: \.self) { row($0) }
                    }.padding(16)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Suggested").font(Theme.section)
                            search
                            row(0)
                            row(1)
                            Button(action: seeMore) {
                                Label("See more", systemImage: "arrow.up.right")
                                    .font(Theme.label).foregroundStyle(Theme.accent)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(Theme.recessed, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
                            }.accessibilityIdentifier("seeMore")
                        }
                        // Replaces the flexible spacer with a stable section gap.
                        importSection
                    }
                    .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
                    .background(GeometryReader { proxy in Color.clear.preference(key: HeightKey.self, value: proxy.size.height) })
                }.scrollBounceBehavior(.basedOnSize)
                .onPreferenceChange(HeightKey.self) { measured in
                    let value = ceil(measured)
                    guard abs(height - value) > 1 else { return }
                    height = value
                    detent = .height(value)
                }
            }
        }
        .buttonStyle(.plain).foregroundStyle(Theme.text)
        .presentationDetents([.height(height), .large], selection: $detent)
        .presentationDragIndicator(.visible).presentationCornerRadius(24)
        .presentationBackground(Theme.background)
        .presentationContentInteraction(.resizes)
        .task {
            // Optional deterministic state exercise uses the same button actions.
            if ProcessInfo.processInfo.arguments.contains("--roundtrip") {
                try? await Task.sleep(for: .seconds(6)); seeMore()
                try? await Task.sleep(for: .seconds(6)); back()
            }
        }
    }
    private func seeMore() { withAnimation(.snappy(duration: 0.32)) { expanded = true; detent = .large } }
    private func back() { withAnimation(.snappy(duration: 0.32)) { expanded = false; detent = .height(height) } }
    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(expanded ? "I'm here now" : "add a place").font(Theme.title)
                Text(expanded ? "choose the place you're at" : "find it nearby, search, or import").font(Theme.bodySmall).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .black))
                    .frame(width: 30, height: 30).background(Theme.raised, in: Circle())
                    .overlay(Circle().stroke(Theme.line, lineWidth: 1)).frame(width: 44, height: 44)
            }
        }
    }
    private var search: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .semibold))
            Text("Search for a place").font(Theme.bodySmall)
            Spacer()
            Image(systemName: "camera.fill").font(.system(size: 18)) .foregroundStyle(Theme.accent)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.accent)
        }.foregroundStyle(Theme.muted).padding(.horizontal, 14).frame(height: 48)
            .background(Theme.recessed, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
    }
    private func row(_ i: Int) -> some View {
        HStack(spacing: 8) {
            Text(places[i].0).font(.system(size: 22)).frame(width: 40, height: 40)
                .background(Theme.accent.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(places[i].1).font(Theme.card).lineLimit(1)
                Text(places[i].2).font(Theme.caption).foregroundStyle(Theme.muted).lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "plus").font(.system(size: 12, weight: .black)).foregroundStyle(Theme.background)
                .frame(width: 28, height: 28).background(Theme.accent, in: Circle())
        }.padding(8).frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
    }
    private var importSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Import").font(Theme.section)
            HStack(spacing: 12) {
                HStack(spacing: -9) {
                    sourceIcon("mappin", color: .blue, background: .white)
                    sourceIcon("camera", color: .white, background: .pink)
                    sourceIcon("music.note", color: .white, background: .black)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Import from").font(Theme.card)
                    Text("Import your places and lists from Google Maps, Instagram, TikTok, and more here")
                        .font(Theme.caption).foregroundStyle(Theme.muted).lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(Theme.label).foregroundStyle(Theme.muted)
            }.padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 72)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
        }
    }
    private func sourceIcon(_ symbol: String, color: Color, background: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(color)
            .frame(width: 34, height: 34).background(background, in: Circle())
            .overlay(Circle().stroke(Theme.raised, lineWidth: 2))
    }
}
