import SwiftUI

private struct ProfileDismissKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> Void)? = nil
}

extension EnvironmentValues {
    var dismissProfile: (@MainActor () -> Void)? {
        get { self[ProfileDismissKey.self] }
        set { self[ProfileDismissKey.self] = newValue }
    }
}

extension View {
    /// Retains the destination until its horizontal exit finishes. The native
    /// cover supplies presentation ownership, environment and dismissal events.
    func profileCover<Destination: View>(
        isPresented: Binding<Bool>,
        onDismiss: (@MainActor () -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Destination
    ) -> some View {
        modifier(ProfileCoverModifier(requested: isPresented, onDismiss: onDismiss, destination: content))
    }

    func profileCover<Item: Identifiable, Destination: View>(
        item: Binding<Item?>,
        onDismiss: (@MainActor () -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Destination
    ) -> some View {
        profileCover(
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            ),
            onDismiss: onDismiss
        ) {
            if let item = item.wrappedValue { content(item) }
        }
    }
}

private struct ProfileCoverModifier<Destination: View>: ViewModifier {
    @Binding var requested: Bool
    let onDismiss: (@MainActor () -> Void)?
    @ViewBuilder let destination: () -> Destination
    @State private var mounted = false

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $mounted, onDismiss: {
                requested = false
                onDismiss?()
            }) {
                ProfileCoverPage(requested: $requested, onFinished: {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { mounted = false }
                }, destination: destination)
                .presentationBackground(.clear)
            }
            .onChange(of: requested, initial: true) { _, requested in
                guard requested, !mounted else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { mounted = true }
            }
    }
}

private struct ProfileCoverPage<Destination: View>: View {
    @Binding var requested: Bool
    let onFinished: () -> Void
    @ViewBuilder let destination: () -> Destination
    @State private var visible = false

    var body: some View {
        ProfileSlideContainer(
            isPresented: visible && requested,
            onRequestDismiss: { requested = false },
            onTransitionCompleted: { presented in
                if !presented { onFinished() }
            }
        ) {
            destination()
                .environment(\.dismissProfile, { requested = false })
        }
        .ignoresSafeArea()
        .accessibilityAction(.escape) { requested = false }
        .task {
            await Task.yield()
            guard requested else { onFinished(); return }
            visible = true
        }
        .onChange(of: requested) { _, requested in
            if !requested { visible = false }
        }
    }
}
