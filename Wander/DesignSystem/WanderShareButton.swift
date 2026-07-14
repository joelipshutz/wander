import SwiftUI

struct WanderShareContent: Equatable {
    let item: URL
    let subject: String
    let message: String

    static func profile(id: String, displayName: String, handle: String) -> WanderShareContent? {
        guard let item = appURL(host: "profiles", pathComponent: id) else { return nil }
        return WanderShareContent(
            item: item,
            subject: displayName,
            message: "See @\(handle) on rec.me"
        )
    }

    static func place(item: URL, name: String, message: String) -> WanderShareContent {
        WanderShareContent(item: item, subject: name, message: message)
    }

    private static func appURL(host: String, pathComponent: String) -> URL? {
        var components = URLComponents()
        components.scheme = "recme"
        components.host = host
        components.path = "/\(pathComponent)"
        return components.url
    }
}

struct WanderShareButton<Label: View>: View {
    let content: WanderShareContent
    private let label: () -> Label

    init(content: WanderShareContent, @ViewBuilder label: @escaping () -> Label) {
        self.content = content
        self.label = label
    }

    var body: some View {
        ShareLink(
            item: content.item,
            subject: Text(content.subject),
            message: Text(content.message),
            label: label
        )
    }
}
