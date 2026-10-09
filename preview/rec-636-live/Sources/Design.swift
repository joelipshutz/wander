import SwiftUI

enum Ink {
    static let coral = Color(red: 240 / 255, green: 90 / 255, blue: 60 / 255)
    static let paper = Color(red: 242 / 255, green: 233 / 255, blue: 219 / 255)
    static let black = Color(red: 20 / 255, green: 23 / 255, blue: 20 / 255)
    static let canvas = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(Ink.black) : UIColor(Ink.paper) })
    static let text = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(Ink.paper) : UIColor(Ink.black) })
    static let muted = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 185 / 255, green: 179 / 255, blue: 167 / 255, alpha: 1) : UIColor(red: 98 / 255, green: 95 / 255, blue: 87 / 255, alpha: 1) })
    static let surface = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.12, green: 0.13, blue: 0.12, alpha: 1) : UIColor(red: 0.98, green: 0.95, blue: 0.90, alpha: 1) })
    static let accentText = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(Ink.coral) : UIColor(red: 178 / 255, green: 54 / 255, blue: 32 / 255, alpha: 1) })
    static func body(_ size: CGFloat = 16, weight: String = "Regular", relativeTo: Font.TextStyle = .body) -> Font {
        .custom("AvenirNext-\(weight)", size: size, relativeTo: relativeTo)
    }
    static func title(_ size: CGFloat = 30) -> Font {
        .system(size >= 34 ? .largeTitle : size >= 28 ? .title : .title2, design: .serif, weight: .regular)
    }
}
struct EditorialTitle: View {
    let text: String
    var size: CGFloat = 30
    var body: some View { Text(text).font(Ink.title(size)).fixedSize(horizontal: false, vertical: true) }
}
struct Avatar: View {
    let initials: String
    var size: CGFloat = 42
    var body: some View {
        Text(initials).font(Ink.body(size * 0.31, weight: "DemiBold"))
            .foregroundStyle(Ink.text).frame(width: size, height: size)
            .background(Ink.coral.opacity(0.17), in: Circle())
            .overlay(Circle().stroke(Ink.text.opacity(0.12), lineWidth: 1))
            .accessibilityHidden(true)
    }
}
struct SignalButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Ink.body(16, weight: "DemiBold"))
            .foregroundStyle(Ink.black).frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.vertical, 14)
            .background(Ink.coral.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 18))
    }
}
struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Ink.body(14, weight: "DemiBold"))
            .foregroundStyle(Ink.text).padding(.horizontal, 15).frame(minHeight: 44)
            .background(Ink.text.opacity(configuration.isPressed ? 0.14 : 0.065), in: Capsule())
    }
}
struct GlassButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Ink.body(14, weight: "DemiBold"))
            .foregroundStyle(Ink.text).padding(.horizontal, 16).frame(minHeight: 46)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Ink.text.opacity(0.10), lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.65 : 1)
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}
struct ReviewMenu: View {
    @EnvironmentObject var store: ReviewStore
    var body: some View {
        Menu {
            Section("Review scenarios · fictional data") {
                Picker("Activity scenario", selection: $store.scenario) {
                    ForEach(ReviewScenario.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            Button("Show transition again", systemImage: "sparkles") { store.cancelAreaDraft(); store.showTransition = true; store.tab = .live; store.drawer = .half }
            Button("Demo inbox", systemImage: "tray") { store.sheet = .inbox }
            Button("About this prototype", systemImage: "info.circle") { store.sheet = .guide }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 19, weight: .semibold)).frame(width: 46, height: 46)
                .background(.regularMaterial, in: Circle())
        }.tint(Ink.text).accessibilityLabel("Review options").accessibilityIdentifier("review.menu")
    }
}
struct AddPlaceButton: View {
    @EnvironmentObject private var store: ReviewStore
    var body: some View {
        Button { store.sheet = .add } label: {
            Image(systemName: "plus").font(.system(size: 22, weight: .medium)).frame(width: 46, height: 46)
                .background(Ink.coral, in: Circle()).foregroundStyle(Ink.black)
        }.accessibilityLabel("Add a place").accessibilityIdentifier("add.open")
    }
}
struct DemoNote: View {
    var text = "Fictional people & places. Actions stay in this demo."
    var body: some View {
        Label(text, systemImage: "circle.dotted").font(Ink.body(12, relativeTo: .caption)).foregroundStyle(Ink.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
struct SheetShell<Content: View>: View {
    let title: String
    var doneTitle: String = "Done"
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView { VStack(alignment: .leading, spacing: 22) { content }.padding(24).frame(maxWidth: .infinity, alignment: .leading) }
                .scrollDismissesKeyboard(.interactively)
                .background(Ink.canvas).foregroundStyle(Ink.text)
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(doneTitle) { dismiss() }.tint(Ink.accentText).frame(minHeight: 44) } }
        }.presentationDragIndicator(.visible)
    }
}
