import SwiftUI
import XCTest
@testable import Wander

/// Runs the real representable through SwiftUI instead of calling update directly.
@MainActor
final class PersonMentionHostedVisibilityTests: XCTestCase {
    func testSwiftUIHostedInputRetainsEditorTextMentionsAndCaretAcrossVisibility() async throws {
        try await exerciseHostedVisibility(usesMapGlass: false)
    }

    func testSwiftUIHostedMapGlassInputRetainsEditorTextMentionsAndCaretAcrossVisibility() async throws {
        try await exerciseHostedVisibility(usesMapGlass: true)
    }

    private func exerciseHostedVisibility(usesMapGlass: Bool) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
        let originalWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let state = HostedInputState()
        let editor = PersonMentionInputController()
        let host = UIHostingController(rootView: HostedInputFixture(
            state: state, editor: editor, usesMapGlass: usesMapGlass))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; originalWindow?.makeKeyAndVisible() }

        // The failing Map launch starts with More Filters open. Exercise the
        // initial hidden render as well as later hide/show updates.
        try await settle(window: window, editor: editor, visible: false)
        let view = try XCTUnwrap(editor.view)
        let coordinator = try XCTUnwrap(editor.coordinator)
        let text = state.text
        let mentions = state.mentions
        let caret = state.caret
        XCTAssertTrue(view.window === window)
        assertHidden(view)
        XCTAssertEqual(view.text, text)
        XCTAssertEqual(view.selectedRange, caret)

        state.isVisible = true
        try await settle(window: window, editor: editor, visible: true)
        assertVisible(view)
        let attributedText = NSAttributedString(attributedString: view.attributedText)

        state.isVisible = false
        try await settle(window: window, editor: editor, visible: false)
        assertHidden(view)
        XCTAssertFalse(view.isFirstResponder)
        XCTAssertTrue(editor.view === view, "Hiding must retain the native editor")
        XCTAssertTrue(editor.coordinator === coordinator)
        XCTAssertEqual(view.attributedText, attributedText)
        XCTAssertEqual(view.selectedRange, caret)
        XCTAssertEqual(state.text, text)
        XCTAssertEqual(state.mentions, mentions)

        state.isVisible = true
        try await settle(window: window, editor: editor, visible: true)
        assertVisible(view)
        XCTAssertTrue(editor.view === view)
        XCTAssertTrue(editor.coordinator === coordinator)
        XCTAssertEqual(view.attributedText, attributedText)
        XCTAssertEqual(view.selectedRange, caret)
        XCTAssertEqual(state.text, text)
        XCTAssertEqual(state.mentions, mentions)
    }

    private func assertHidden(_ view: UITextView, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(view.isHidden, file: file, line: line)
        XCTAssertFalse(view.isUserInteractionEnabled, file: file, line: line)
        XCTAssertFalse(view.isAccessibilityElement, file: file, line: line)
        XCTAssertTrue(view.accessibilityElementsHidden, file: file, line: line)
        XCTAssertNil(view.hitTest(CGPoint(x: view.bounds.midX, y: view.bounds.midY), with: nil), file: file, line: line)
    }

    private func assertVisible(_ view: UITextView, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(view.isHidden, file: file, line: line)
        XCTAssertTrue(view.isUserInteractionEnabled, file: file, line: line)
        XCTAssertTrue(view.isAccessibilityElement, file: file, line: line)
        XCTAssertFalse(view.accessibilityElementsHidden, file: file, line: line)
        XCTAssertNotNil(view.hitTest(CGPoint(x: view.bounds.midX, y: view.bounds.midY), with: nil), file: file, line: line)
    }

    private func settle(window: UIWindow, editor: PersonMentionInputController, visible: Bool) async throws {
        // Observe an actual representable update, then allow subsequent hosting
        // layout passes to run. Never mutate the native view from this helper.
        for _ in 0..<50 {
            window.rootViewController?.view.setNeedsLayout()
            window.rootViewController?.view.layoutIfNeeded()
            window.layoutIfNeeded()
            if editor.coordinator?.isVisible == visible,
               let view = editor.view, view.window === window,
               view.bounds.width > 0, view.bounds.height > 0 {
                for _ in 0..<3 {
                    try await Task.sleep(for: .milliseconds(20))
                    window.rootViewController?.view.layoutIfNeeded()
                    window.layoutIfNeeded()
                }
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("SwiftUI did not mount and update the input")
    }

    private final class HostedInputState: ObservableObject {
        @Published var isVisible = false
        @Published var text = "With @Caitlin Cortez tomorrow"
        @Published var mentions = [PersonMention(
            userID: "caitlin", handle: "cait123", name: "Caitlin Cortez", location: 5, length: 15)]
        @Published var caret = NSRange(location: 22, length: 0)
        @Published var focus = false
        let replacementID = UUID()
    }

    private struct HostedInputFixture: View {
        @ObservedObject var state: HostedInputState
        let editor: PersonMentionInputController
        let usesMapGlass: Bool

        var body: some View {
            VStack {
                Spacer()
                Group {
                    if usesMapGlass {
                        WanderGlassButtonCluster(mergeSpacing: WanderTheme.spacing3) {
                            mapChrome
                        }
                    } else {
                        input
                    }
                }
                .frame(width: 280, height: 56)
                .opacity(state.isVisible ? 1 : 0)
                .allowsHitTesting(state.isVisible)
                .accessibilityHidden(!state.isVisible)
                Spacer()
            }
        }

        private var input: some View {
            PersonMentionNativeInput(
                text: $state.text, mentions: $state.mentions, selection: $state.caret, focus: $state.focus,
                placeholder: "Search", accessibilityLabel: "Search", accessibilityIdentifier: "visibility.hostedSearch",
                replacementID: state.replacementID, editor: editor, primaryColor: .black,
                accentColor: .red, placeholderColor: .gray, minimumLines: 1, maximumLines: 1,
                isSearch: true, isVisible: state.isVisible, submitOnReturn: false,
                suggestions: AnyView(EmptyView()), suggestionHeight: 0,
                onSubmit: {}, onFocus: {}, onCompletionRequest: { _ in })
        }

        @ViewBuilder private var mapChrome: some View {
            let content = HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                input
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular.interactive(true), in: RoundedRectangle(cornerRadius: 18))
            } else {
                content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }
}
