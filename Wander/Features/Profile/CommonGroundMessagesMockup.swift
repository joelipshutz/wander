import SwiftUI
import UIKit

/// A local conversation preview. Its invitation opens another SwiftUI preview,
/// never Messages, a URL, or a delivery service.
struct CommonGroundMessagesMockup: View {
    let draft: CommonGroundInvitationDraft
    var isReply = false
    var onClose: (() -> Void)? = nil

    var body: some View {
        CGMessagesConversation(draft: draft, isReply: isReply, onClose: onClose)
            .astirAdaptiveBrandMode()
    }
}

private struct CGMessagesConversation: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    let draft: CommonGroundInvitationDraft
    let isReply: Bool
    let onClose: (() -> Void)?
    @State private var showsRecipient = false
    @State private var reply = ""

    private var contact: String { isReply ? draft.place.viewer.shortName : draft.place.partner.shortName }
    private var messageBlue: Color { Color(red: 0.025, green: 0.38, blue: 0.80) }
    private var linkBlue: Color {
        colorScheme == .dark ? Color(red: 0.38, green: 0.65, blue: 1) : messageBlue
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("iMessage")
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)

                    HStack(alignment: .top, spacing: 0) {
                        if !isReply { Spacer(minLength: messageIndent) }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(draft.message)
                                .font(.system(.body))
                                .foregroundStyle(isReply ? Color.primary : .white)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    isReply ? Color(uiColor: .secondarySystemBackground) : messageBlue,
                                    in: RoundedRectangle(cornerRadius: 20)
                                )
                                .accessibilityIdentifier("common-ground.messages.message")

                            Button {
                                showsRecipient = true
                            } label: {
                                invitationPreview
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(draft.linkTitle). \(draft.linkSubtitle). View invitation")
                            .accessibilityValue(draft.whenText ?? "No time proposed")
                            .accessibilityHint("Opens \(draft.place.viewer.shortName)’s invitation in this preview")
                            .accessibilityIdentifier("common-ground.messages.open-invitation")
                        }
                        if isReply { Spacer(minLength: messageIndent) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composerBar
            }
            .navigationTitle(contact)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Text(String(contact.prefix(1)))
                            .font(.system(.caption, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.gray, in: Circle())
                            .accessibilityHidden(true)
                        Text(contact).font(.system(.headline))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Messages with \(contact)")
                    .accessibilityIdentifier("common-ground.messages.conversation")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let onClose { onClose() } else { dismiss() }
                    }
                        .accessibilityLabel("Close Messages preview")
                        .accessibilityIdentifier("common-ground.messages.close")
                }
            }
            .navigationDestination(isPresented: $showsRecipient) {
                CommonGroundInvitationMockup(draft: draft, opensEnvelope: true, initiallyOpened: true)
                    .navigationBarBackButtonHidden(true)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showsRecipient = false
                            } label: {
                                Label("Messages", systemImage: "chevron.left")
                            }
                            .accessibilityLabel("Back to Messages")
                            .accessibilityIdentifier("common-ground.recipient.close")
                        }
                    }
                    .tint(brand.accentText)
            }
        }
        .tint(linkBlue)
    }

    private var messageIndent: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 8 : 26
    }

    private var invitationPreview: some View {
        CGInvitationLinkPreview(draft: draft, showsViewButton: true)
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }

    private var composerBar: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 27))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)

                Group {
                    if isReply {
                        TextField("Write a reply…", text: $reply, axis: .vertical)
                            .lineLimit(1...4)
                            .accessibilityLabel("Reply draft, preview only")
                    } else {
                        Text("iMessage")
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityHidden(true)
                    }
                }
                .font(.system(.body))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                }
            }
            Text("Messages preview · nothing is sent")
                .font(.system(.caption))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("common-ground.messages.preview-notice")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Color(uiColor: .systemBackground))
    }
}

#Preview("Messages · Invitation") {
    CommonGroundMessagesMockup(draft: .preview)
        .preferredColorScheme(.light)
}

#Preview("Messages · Reply") {
    CommonGroundMessagesMockup(draft: .preview, isReply: true)
        .preferredColorScheme(.dark)
}
