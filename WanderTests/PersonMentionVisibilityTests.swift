import XCTest
import SwiftUI
@testable import Wander

@MainActor
final class PersonMentionVisibilityTests: XCTestCase {
    func testContainerRetainsNativeMeasurementAndChildWhenHidden() {
        let view = PersonMentionNativeInput.MentionTextView()
        view.font = .preferredFont(forTextStyle: .body)
        view.isScrollEnabled = false
        view.text = "Short note"
        let container = PersonMentionNativeInput.InputContainerView(textView: view)
        container.frame = CGRect(x: 0, y: 0, width: 180, height: 100)
        container.layoutIfNeeded()
        let proposal = CGSize(width: 180, height: CGFloat.greatestFiniteMagnitude)
        let shortHeight = container.sizeThatFits(proposal).height
        view.text = Array(repeating: "A longer note wraps onto additional lines.", count: 5).joined(separator: " ")
        let longSize = container.sizeThatFits(proposal)
        XCTAssertGreaterThan(longSize.height, shortHeight)
        XCTAssertEqual(longSize, view.sizeThatFits(proposal))
        XCTAssertEqual(container.intrinsicContentSize, view.intrinsicContentSize)
        XCTAssertEqual(view.frame, container.bounds)
        container.setInputVisibility(false)
        XCTAssertTrue(container.subviews.first === view)
        XCTAssertEqual(container.sizeThatFits(proposal), longSize, "Hiding must preserve native sizing and text")
        XCTAssertEqual(container.accessibilityElements?.count, 0)
        container.setInputVisibility(true)
        XCTAssertTrue(container.subviews.first === view)
        XCTAssertEqual(container.accessibilityElements?.count, 1)
        XCTAssertTrue(container.accessibilityElements?.first as? UITextView === view)
    }

    func testHideAndRevealPreserveNativeTextMentionsCaretAndEditor() {
        let mention = PersonMention(userID: "caitlin", handle: "cait123", name: "Caitlin Cortez", location: 5, length: 15)
        let state = InputState(text: "With @Caitlin Cortez tomorrow", mentions: [mention], caret: NSRange(location: 22, length: 0))
        var input = makeInput(state)
        let coordinator = input.makeCoordinator()
        let view = makeView(input, coordinator: coordinator)
        input.update(view, coordinator: coordinator)
        let attributedText = NSAttributedString(attributedString: view.attributedText)
        let originalCaret = view.selectedRange
        coordinator.accessory.contentHeight = 58
        coordinator.accessory.heightConstraint.constant = 58
        coordinator.accessory.host.view.isHidden = false
        view.inputAccessoryView = coordinator.accessory

        input.isVisible = false
        input.update(view, coordinator: coordinator)
        XCTAssertTrue(view.isHidden)
        XCTAssertFalse(view.isUserInteractionEnabled)
        XCTAssertFalse(view.isAccessibilityElement)
        XCTAssertTrue(view.accessibilityElementsHidden)
        XCTAssertNil(view.hitTest(CGPoint(x: 10, y: 10), with: nil))
        XCTAssertNil(view.inputAccessoryView)
        XCTAssertTrue(coordinator.accessory.host.view.isHidden)
        XCTAssertEqual(coordinator.accessory.contentHeight, 0)
        XCTAssertEqual(view.attributedText, attributedText)
        XCTAssertEqual(view.selectedRange, originalCaret)
        XCTAssertEqual(state.mentions, [mention])
        XCTAssertTrue(input.editor.view === view)
        XCTAssertTrue(input.editor.coordinator === coordinator)

        input.isVisible = true
        input.update(view, coordinator: coordinator)
        XCTAssertFalse(view.isHidden)
        XCTAssertTrue(view.isUserInteractionEnabled)
        XCTAssertTrue(view.isAccessibilityElement)
        XCTAssertFalse(view.accessibilityElementsHidden)
        XCTAssertEqual(view.attributedText, attributedText)
        XCTAssertEqual(view.text, state.text)
        XCTAssertEqual(view.selectedRange, originalCaret)
        XCTAssertEqual(state.mentions, [mention])
    }

    func testPendingNativeEditCannotSkipVisibilityOrReactivateQueuedFocus() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let originalWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; originalWindow?.makeKeyAndVisible() }
        let state = InputState(text: "coffee", caret: NSRange(location: 6, length: 0))
        state.focus = true
        var input = makeInput(state)
        let coordinator = input.makeCoordinator()
        let view = makeView(input, coordinator: coordinator)
        controller.view.addSubview(view)
        input.update(view, coordinator: coordinator)
        XCTAssertTrue(coordinator.focusUpdatePending)

        // UIKit has typed ahead of the binding snapshot. That early return must
        // retain the edit but still hide the field before queued focus executes.
        view.text = "coffee near me"
        view.selectedRange = NSRange(location: 14, length: 0)
        coordinator.lastText = view.text
        coordinator.pendingText = view.text
        input.isVisible = false
        input.update(view, coordinator: coordinator)
        XCTAssertTrue(coordinator.parent.isVisible, "The older parent is intentionally retained by the pending-edit guard")
        XCTAssertFalse(coordinator.isVisible)
        XCTAssertTrue(view.isHidden)
        XCTAssertFalse(view.isUserInteractionEnabled)
        XCTAssertFalse(view.isAccessibilityElement)
        XCTAssertTrue(view.accessibilityElementsHidden)
        XCTAssertFalse(coordinator.textViewShouldBeginEditing(view))
        await nextMainQueueTurn()
        XCTAssertFalse(view.isFirstResponder)
        XCTAssertFalse(coordinator.focusUpdatePending)
        XCTAssertEqual(view.text, "coffee near me")
        XCTAssertEqual(view.selectedRange, NSRange(location: 14, length: 0))
        XCTAssertEqual(coordinator.pendingText, "coffee near me")

        state.text = view.text
        state.caret = view.selectedRange
        input.isVisible = true
        input.update(view, coordinator: coordinator)
        await nextMainQueueTurn()
        XCTAssertNil(coordinator.pendingText)
        XCTAssertFalse(view.isHidden)
        XCTAssertTrue(view.isFirstResponder, "A new visible update can focus the same retained native editor")
        XCTAssertEqual(view.text, "coffee near me")
        XCTAssertEqual(view.selectedRange, NSRange(location: 14, length: 0))
        view.resignFirstResponder()
    }

    func testMarkedTextCannotSkipNativeVisibilityUpdate() throws {
        let state = InputState(text: "", caret: NSRange(location: 0, length: 0))
        var input = makeInput(state)
        let coordinator = input.makeCoordinator()
        let view = makeView(input, coordinator: coordinator)
        input.update(view, coordinator: coordinator)
        view.setMarkedText("東京", selectedRange: NSRange(location: 2, length: 0))
        XCTAssertNotNil(view.markedTextRange)
        let nativeText = view.text
        let nativeCaret = view.selectedRange
        // setMarkedText can publish pendingText through the delegate. Clear
        // only that guard so this test must reach the actual IME early return.
        coordinator.pendingText = nil
        state.text = "stale SwiftUI snapshot"
        XCTAssertFalse(coordinator.updating)
        XCTAssertNil(coordinator.pendingText)
        XCTAssertNotEqual(view.text, state.text)
        input.isVisible = false
        input.update(view, coordinator: coordinator)
        XCTAssertTrue(view.isHidden)
        XCTAssertFalse(view.isUserInteractionEnabled)
        XCTAssertFalse(view.isAccessibilityElement)
        XCTAssertTrue(view.accessibilityElementsHidden)
        XCTAssertFalse(coordinator.parent.isVisible, "The update passed the pending-text guard before returning for marked text")
        XCTAssertNotNil(view.markedTextRange)
        XCTAssertEqual(view.text, nativeText, "Visibility must not replace a composing native edit with stale SwiftUI text")
        XCTAssertEqual(view.selectedRange, nativeCaret)
    }

    func testRapidHideAndRevealReschedulesSuggestionsWithoutOldTaskClearingReplacement() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let originalWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; originalWindow?.makeKeyAndVisible() }
        let state = InputState(text: "@c", caret: NSRange(location: 2, length: 0))
        state.focus = true
        var input = makeInput(state)
        let coordinator = input.makeCoordinator()
        let view = makeView(input, coordinator: coordinator)
        controller.view.addSubview(view)
        input.update(view, coordinator: coordinator)
        await nextMainQueueTurn()
        XCTAssertTrue(view.isFirstResponder)
        coordinator.accessory.contentHeight = 0
        coordinator.updateSuggestions(for: view)
        let oldTask = try XCTUnwrap(coordinator.accessoryUpdateTask)
        let oldID = try XCTUnwrap(coordinator.accessoryUpdateRequestID)

        // Do not yield between these updates: the canceled task has not exited.
        input.isVisible = false
        input.update(view, coordinator: coordinator)
        XCTAssertNil(coordinator.accessoryUpdateTask)
        state.focus = true
        input.isVisible = true
        input.update(view, coordinator: coordinator)
        let replacementTask = try XCTUnwrap(coordinator.accessoryUpdateTask)
        let replacementID = try XCTUnwrap(coordinator.accessoryUpdateRequestID)
        XCTAssertNotEqual(oldID, replacementID)
        await oldTask.value
        if let activeID = coordinator.accessoryUpdateRequestID {
            XCTAssertEqual(activeID, replacementID)
        } else {
            // Completion is also valid if the typing-pause interval elapsed.
            XCTAssertEqual(coordinator.accessory.contentHeight, input.suggestionHeight)
        }
        await replacementTask.value
        XCTAssertEqual(coordinator.accessory.contentHeight, input.suggestionHeight)
        XCTAssertFalse(coordinator.accessory.host.view.isHidden)
        XCTAssertTrue(view.inputAccessoryView === coordinator.accessory)
        view.resignFirstResponder()
    }

    private func makeInput(_ state: InputState) -> PersonMentionNativeInput {
        PersonMentionNativeInput(
            text: Binding(get: { state.text }, set: { state.text = $0 }),
            mentions: Binding(get: { state.mentions }, set: { state.mentions = $0 }),
            selection: Binding(get: { state.caret }, set: { state.caret = $0 }),
            focus: Binding(get: { state.focus }, set: { state.focus = $0 }),
            placeholder: "Search", accessibilityLabel: "Search", accessibilityIdentifier: "visibility.search",
            replacementID: UUID(), editor: PersonMentionInputController(), primaryColor: .black,
            accentColor: .red, placeholderColor: .gray, minimumLines: 1, maximumLines: 4,
            isSearch: true, submitOnReturn: false, suggestions: AnyView(Text("A person")),
            suggestionHeight: 58, onSubmit: {}, onFocus: {}, onCompletionRequest: { _ in }
        )
    }

    private func makeView(_ input: PersonMentionNativeInput, coordinator: PersonMentionNativeInput.Coordinator) -> PersonMentionNativeInput.MentionTextView {
        let view = PersonMentionNativeInput.MentionTextView(frame: CGRect(x: 0, y: 0, width: 300, height: 60), textContainer: nil)
        view.delegate = coordinator
        input.editor.view = view
        input.editor.coordinator = coordinator
        return view
    }

    private func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private final class InputState {
        var text: String
        var mentions: [PersonMention]
        var caret: NSRange
        var focus = false
        init(text: String, mentions: [PersonMention] = [], caret: NSRange) {
            self.text = text
            self.mentions = mentions
            self.caret = caret
        }
    }
}
