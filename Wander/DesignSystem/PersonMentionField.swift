import SwiftUI
import UIKit

/// Shared native input for comments, place notes, and person-aware search.
struct PersonMentionField: View {
    @Environment(\.astirBrandMode) private var brand
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var auth: AuthSessionStore
    @Binding var text: String
    var mentions: Binding<[PersonMention]>?
    var focus: Binding<Bool>?
    var placeholder: String
    var accessibilityLabel: String
    var accessibilityIdentifier: String
    var minimumLines = 1
    var maximumLines = 4
    var isSearch = false
    var submitOnReturn = false
    var onSubmit: () -> Void = {}
    var onSelect: (ProfileShell) -> Void = { _ in }
    var onFocus: () -> Void = {}
    var onQueryChange: (Bool) -> Void = { _ in }
    /// Keep the suggestion panel outside each surface's input chrome.
    var decorateInput: (AnyView) -> AnyView = { $0 }
    @State private var internalMentions: [PersonMention] = []
    @State private var internalFocus = false
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var retry = 0
    @State private var replacementID = UUID()
    @StateObject private var results = PersonTypeaheadModel()
    @StateObject private var editor = PersonMentionInputController()
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 58

    private var mentionBinding: Binding<[PersonMention]> { mentions ?? $internalMentions }
    private var focusBinding: Binding<Bool> { focus ?? $internalFocus }
    private var query: PersonMentionQuery? {
        guard focusBinding.wrappedValue else { return nil }
        return PersonMentionDraft(text: text, mentions: mentionBinding.wrappedValue).query(at: selection)
    }
    private var requestID: String {
        "\(store.currentUser.id)|\(auth.isSignedIn)|\(query?.range.location ?? -1)|\(query?.text ?? "")|\(retry)"
    }
    private var candidates: [ProfileShell] {
        (store.personTypeaheadConnections + results.profiles).filter(store.isEligibleForPersonTypeahead)
    }
    private var suggestionHeight: CGFloat {
        guard query != nil else { return 0 }
        let count = results.profiles.filter(store.isEligibleForPersonTypeahead).count
        let rows = count == 0 ? 48 : min(CGFloat(count) * rowHeight, min(rowHeight * 3.5, 220))
        return rows + (results.failed ? 44 : 0) + 12
    }

    var body: some View {
        decorateInput(AnyView(PersonMentionNativeInput(
                text: $text, mentions: mentionBinding, selection: $selection, focus: focusBinding,
                placeholder: placeholder, accessibilityLabel: accessibilityLabel,
                accessibilityIdentifier: accessibilityIdentifier,
                replacementID: replacementID,
                editor: editor,
                primaryColor: UIColor(brand.primaryText), accentColor: UIColor(brand.accentText),
                placeholderColor: UIColor(brand.secondaryText),
                minimumLines: minimumLines, maximumLines: maximumLines, isSearch: isSearch, submitOnReturn: submitOnReturn,
                suggestions: AnyView(suggestions.environment(\.astirBrandMode, brand)),
                suggestionHeight: suggestionHeight,
                onSubmit: onSubmit, onFocus: onFocus, onCompletionRequest: complete
            )))
        .task(id: requestID) {
            let owner = store.currentUser.id
            await results.search(
                query: query?.text, ownerID: "\(owner)|\(auth.isSignedIn)",
                local: { store.personTypeaheadConnections },
                recommendations: {
                    guard auth.isSignedIn, backend.profileRepository != nil else { return [] }
                    return try await backend.peopleRecommendations(userID: owner, limit: 50).map(\.profile)
                },
                remote: { query in
                    guard auth.isSignedIn, backend.profileRepository != nil else { return [] }
                    return try await backend.searchProfiles(handleQuery: query)
                },
                eligible: { store.currentUser.id == owner && store.isEligibleForPersonTypeahead($0) }
            )
        }
        .onChange(of: store.currentUser.id) { _, _ in
            results.cancelCompletions()
            text = ""
            mentionBinding.wrappedValue = []
            focusBinding.wrappedValue = false
        }
        .onChange(of: query) { _, value in onQueryChange(value != nil) }
        .onChange(of: text) { _, value in
            let valid = mentionBinding.wrappedValue.filter { $0.isValid(in: value) }
            if valid != mentionBinding.wrappedValue { mentionBinding.wrappedValue = valid }
        }
        .onChange(of: auth.isSignedIn) { _, _ in results.cancelCompletions() }
        .onDisappear { results.cancelCompletions(); onQueryChange(false) }
    }

    private func complete(_ request: PersonMentionCompletionRequest) {
        let owner = store.currentUser.id
        results.complete(request: request, local: candidates, remote: { query in
            guard auth.isSignedIn, backend.profileRepository != nil else { return [] }
            return try await backend.searchProfiles(handleQuery: query)
        }, eligible: { store.currentUser.id == owner && store.isEligibleForPersonTypeahead($0) }) { request, person in
            guard let person, store.currentUser.id == owner, focusBinding.wrappedValue else { return }
            guard editor.complete(request, person: person) else { return }
            results.rebaseCompletions(replacing: request.query.range, with: "@\(PersonMentionCandidates.name(for: person))")
            onSelect(person)
        }
    }

    private var suggestions: some View {
        let profiles = results.profiles.filter(store.isEligibleForPersonTypeahead)
        return VStack(spacing: 0) {
            if !profiles.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(profiles) { profile in
                            Button {
                                guard let query else { return }
                                var draft = PersonMentionDraft(text: text, mentions: mentionBinding.wrappedValue)
                                guard let caret = draft.select(profile, for: query) else { return }
                                results.cancelCompletions()
                                mentionBinding.wrappedValue = draft.mentions
                                text = draft.text
                                selection = caret
                                replacementID = UUID()
                                focusBinding.wrappedValue = true
                                onSelect(profile)
                            } label: {
                                HStack(spacing: 10) {
                                    WanderAvatar(initials: PersonMentionCandidates.name(for: profile).split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined(),
                                                 avatarURL: profile.avatarURL, size: 34, color: brand.accentWash)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(PersonMentionCandidates.name(for: profile))
                                            .font(AstirTypography.control)
                                            .foregroundStyle(brand.primaryText)
                                        Text("@\(profile.handle)")
                                            .font(AstirTypography.caption)
                                            .foregroundStyle(brand.secondaryText)
                                    }
                                    .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(PersonMentionCandidates.name(for: profile)), @\(profile.handle)")
                            .accessibilityHint("Insert this person")
                            .accessibilityIdentifier("\(accessibilityIdentifier).person.\(profile.id)")
                        }
                    }
                }
                .scrollIndicators(.visible)
                .scrollDismissesKeyboard(.never)
                .frame(height: min(CGFloat(profiles.count) * rowHeight, min(rowHeight * 3.5, 220)))
            } else if results.isLoading {
                ProgressView("Finding people…").font(AstirTypography.caption).padding(12)
            } else if !results.failed {
                Text("No people found").font(AstirTypography.bodySmall).padding(12)
            }
            if results.failed {
                HStack {
                    Text(profiles.isEmpty ? "Couldn't load people." : "Showing available people.")
                        .font(AstirTypography.caption)
                    Spacer(minLength: 4)
                    Button("Retry") { retry += 1 }.frame(minHeight: 44)
                }
                .padding(.horizontal, 10)
            }
        }
        .foregroundStyle(brand.secondaryText)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(brand.raisedBackground)
        .accessibilityIdentifier("\(accessibilityIdentifier).suggestions")
    }
}

struct PersonMentionNativeInput: UIViewRepresentable {
    @Binding var text: String
    @Binding var mentions: [PersonMention]
    @Binding var selection: NSRange
    @Binding var focus: Bool
    let placeholder: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let replacementID: UUID
    let editor: PersonMentionInputController
    let primaryColor: UIColor
    let accentColor: UIColor
    let placeholderColor: UIColor
    let minimumLines: Int
    let maximumLines: Int
    let isSearch: Bool
    let submitOnReturn: Bool
    let suggestions: AnyView
    let suggestionHeight: CGFloat
    let onSubmit: () -> Void
    let onFocus: () -> Void
    let onCompletionRequest: (PersonMentionCompletionRequest) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MentionTextView {
        let view = MentionTextView()
        view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.delegate = context.coordinator
        editor.view = view
        editor.coordinator = context.coordinator
        view.adjustsFontForContentSizeCategory = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.keyboardDismissMode = .interactive
        view.autocorrectionType = isSearch ? .no : .default
        view.autocapitalizationType = isSearch ? .none : .sentences
        view.returnKeyType = isSearch ? .search : (submitOnReturn ? .send : .default)
        view.allowsEditingTextAttributes = false
        return view
    }

    static func dismantleUIView(_ view: MentionTextView, coordinator: Coordinator) {
        if coordinator.parent.editor.view === view {
            coordinator.parent.editor.view = nil
            coordinator.parent.editor.coordinator = nil
        }
    }

    func updateUIView(_ view: MentionTextView, context: Context) {
        guard !context.coordinator.updating else { return }
        // Parent forms can render an earlier snapshot after UIKit has already
        // published newer keystrokes. Wait for that publication to be reflected
        // before accepting a replacement, otherwise the last character is lost.
        if let pending = context.coordinator.pendingText {
            guard text == pending || replacementID != context.coordinator.parent.replacementID else { return }
            context.coordinator.pendingText = nil
        }
        context.coordinator.parent = self
        guard view.markedTextRange == nil else { return }
        context.coordinator.updating = true
        defer { context.coordinator.updating = false }
        let replacesText = view.text != text
        if replacesText {
            view.text = text
            context.coordinator.lastText = text
        }
        let font = regularFont
        if view.font == nil { view.font = font }
        view.tintColor = accentColor
        view.accessibilityLabel = accessibilityLabel
        view.accessibilityIdentifier = accessibilityIdentifier
        view.placeholder.text = placeholder
        view.placeholder.font = font
        view.placeholder.textColor = placeholderColor
        view.placeholder.isHidden = !text.isEmpty
        context.coordinator.style(view)
        // Native selection is authoritative during typing. Only apply a caret
        // supplied with an external replacement, such as choosing a person.
        if replacesText, selection.location >= 0, selection.location <= text.utf16.count,
           selection.length <= text.utf16.count - selection.location {
            view.selectedRange = selection
        }
        context.coordinator.synchronizeFocus(view)
        if replacesText { view.invalidateIntrinsicContentSize() }
        view.setNeedsLayout()
        context.coordinator.updateSuggestions(for: view)
    }

    private var regularFont: UIFont { inputFont(bold: false) }

    private func inputFont(bold: Bool) -> UIFont {
        let style: UIFont.TextStyle = isSearch ? .subheadline : .body
        let size: CGFloat = isSearch ? 14 : 16
        let font = UIFont(name: bold ? "AvenirNext-Bold" : "AvenirNext-Regular", size: size)
            ?? UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MentionTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let lineHeight = regularFont.lineHeight
        let desired = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let minimum = lineHeight * CGFloat(minimumLines) + 12
        let maximum = lineHeight * CGFloat(maximumLines) + 12
        if uiView.isScrollEnabled != (desired > maximum) { uiView.isScrollEnabled = desired > maximum }
        return CGSize(width: width, height: max(minimum, min(maximum, desired)))
    }

    final class MentionTextView: UITextView {
        let placeholder = UILabel()
        override init(frame: CGRect, textContainer: NSTextContainer?) {
            super.init(frame: frame, textContainer: textContainer)
            placeholder.isUserInteractionEnabled = false
            placeholder.numberOfLines = 0
            addSubview(placeholder)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layoutSubviews() {
            super.layoutSubviews()
            let size = placeholder.sizeThatFits(CGSize(width: bounds.width, height: bounds.height))
            placeholder.frame = CGRect(x: 0, y: textContainerInset.top, width: bounds.width, height: min(size.height, bounds.height - 12))
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PersonMentionNativeInput
        var lastText: String
        var pendingText: String?
        var updating = false
        var focusUpdatePending = false
        let accessory = MentionKeyboardAccessory()
        init(_ parent: PersonMentionNativeInput) {
            self.parent = parent
            lastText = parent.text
        }

        /// Async completion must transform UIKit's current draft. A SwiftUI
        /// snapshot can be a few keystrokes behind when the lookup returns.
        func complete(_ request: PersonMentionCompletionRequest, person: ProfileShell, in view: UITextView) -> Bool {
            guard !updating, view.isFirstResponder, view.markedTextRange == nil else { return false }
            var draft = PersonMentionDraft(text: lastText, mentions: parent.mentions)
            draft.reconcile(view.text)
            guard let caret = draft.complete(request, person: person, at: view.selectedRange) else { return false }
            updating = true
            defer { updating = false }
            view.textStorage.replaceCharacters(in: request.query.range, with: "@\(PersonMentionCandidates.name(for: person))")
            view.selectedRange = caret
            lastText = draft.text
            pendingText = draft.text
            parent.mentions = draft.mentions
            parent.text = draft.text
            parent.selection = caret
            style(view)
            view.invalidateIntrinsicContentSize()
            return true
        }

        func updateSuggestions(for view: UITextView) {
            accessory.host.rootView = parent.suggestions
            guard accessory.contentHeight != parent.suggestionHeight else { return }
            accessory.contentHeight = parent.suggestionHeight
            accessory.heightConstraint.constant = parent.suggestionHeight
            accessory.frame.size.height = parent.suggestionHeight
            view.inputAccessoryView = parent.suggestionHeight > 0 ? accessory : nil
            accessory.invalidateIntrinsicContentSize()
            accessory.setNeedsLayout()
            DispatchQueue.main.async { [weak view] in
                guard let view, view.isFirstResponder else { return }
                view.reloadInputViews()
            }
        }

        // Becoming first responder can ask SwiftUI to resolve its responder
        // graph. Do it after updateUIView completes to avoid a graph cycle.
        func synchronizeFocus(_ view: UITextView) {
            guard !focusUpdatePending else { return }
            focusUpdatePending = true
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self else { return }
                self.focusUpdatePending = false
                guard let view, view.window != nil else { return }
                if self.parent.focus, !view.isFirstResponder { view.becomeFirstResponder() }
                if !self.parent.focus, view.isFirstResponder { view.resignFirstResponder() }
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !updating else { return }
            updating = true
            defer { updating = false }
            var draft = PersonMentionDraft(text: lastText, mentions: parent.mentions)
            draft.reconcile(textView.text)
            lastText = draft.text
            pendingText = draft.text
            parent.text = draft.text
            if parent.mentions != draft.mentions { parent.mentions = draft.mentions }
            parent.selection = textView.selectedRange
            if textView.markedTextRange == nil { style(textView) }
            textView.invalidateIntrinsicContentSize()
            if textView.markedTextRange == nil,
               let request = PersonMentionCompletionRequest(draft: draft, selection: textView.selectedRange) {
                parent.onCompletionRequest(request)
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // UIKit reports a typing selection before didChange publishes the
            // new text. Publishing that caret early can render the old text.
            guard !updating, textView.markedTextRange == nil,
                  textView.text == parent.text else { return }
            parent.selection = textView.selectedRange
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.focus = true
            parent.onFocus()
        }

        func textViewDidEndEditing(_ textView: UITextView) { parent.focus = false }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if (parent.isSearch || parent.submitOnReturn), text == "\n" {
                parent.onSubmit()
                return false
            }
            return true
        }

        func style(_ view: UITextView) {
            let font = parent.regularFont
            let caret = view.selectedRange
            let wasUpdating = updating
            updating = true
            defer { updating = wasUpdating }
            let normal: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: parent.primaryColor]
            view.textStorage.beginEditing()
            view.textStorage.setAttributes(normal, range: NSRange(location: 0, length: view.text.utf16.count))
            let bold = parent.inputFont(bold: true)
            for mention in parent.mentions where mention.isValid(in: view.text) {
                view.textStorage.addAttributes([.font: bold, .foregroundColor: parent.accentColor], range: mention.nameRange)
            }
            view.textStorage.endEditing()
            view.selectedRange = caret
            view.typingAttributes = normal
        }
    }

    /// UIKit positions this view at the keyboard edge for every input surface,
    /// independent of a search bar's position or a note's scroll offset.
    final class MentionKeyboardAccessory: UIInputView {
        let host = UIHostingController(rootView: AnyView(EmptyView()))
        var contentHeight: CGFloat = 0
        private(set) var heightConstraint: NSLayoutConstraint!

        init() {
            super.init(frame: .zero, inputViewStyle: .keyboard)
            allowsSelfSizing = true
            autoresizingMask = [.flexibleWidth]
            heightConstraint = heightAnchor.constraint(equalToConstant: 0)
            heightConstraint.priority = .required
            heightConstraint.isActive = true
            host.view.backgroundColor = .clear
            host.safeAreaRegions = []
            addSubview(host.view)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: contentHeight)
        }
        override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
            CGSize(width: targetSize.width, height: contentHeight)
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            host.view.frame = bounds
        }
    }
}

@MainActor
final class PersonMentionInputController: ObservableObject {
    weak var view: UITextView?
    weak var coordinator: PersonMentionNativeInput.Coordinator?

    func complete(_ request: PersonMentionCompletionRequest, person: ProfileShell) -> Bool {
        guard let view, let coordinator else { return false }
        return coordinator.complete(request, person: person, in: view)
    }
}
