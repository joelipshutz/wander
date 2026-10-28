import SwiftUI

/// SwiftUI owns the option text so semantic colors survive the dropdown.
/// Native menu-backed Picker labels may discard per-option foreground styles.
struct LiveSemanticPicker<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let title: String
        let color: Color
        var id: Value { value }
    }

    let title: String
    @Binding var selection: Value
    let options: [Option]
    @Environment(\.astirBrandMode) private var brand
    @State private var presented = false

    private var selected: Option? { options.first { $0.value == selection } }

    var body: some View {
        Button { presented = true } label: {
            HStack {
                Text(title).foregroundStyle(brand.primaryText)
                Spacer(minLength: 12)
                Text(selected?.title ?? "").foregroundStyle(selected?.color ?? brand.primaryText)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold)).foregroundStyle(brand.secondaryText)
            }
            .font(AstirTypography.body)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selected?.title ?? "")
        .popover(isPresented: $presented, arrowEdge: .top) {
            VStack(spacing: 0) {
                ForEach(options) { option in
                    Button {
                        selection = option.value
                        presented = false
                    } label: {
                        HStack(spacing: 16) {
                            Text(option.title).foregroundStyle(option.color)
                            Spacer(minLength: 8)
                            Image(systemName: "checkmark")
                                .foregroundStyle(brand.primaryText)
                                .opacity(selection == option.value ? 1 : 0)
                        }
                        .font(AstirTypography.body.weight(.semibold))
                        .padding(.horizontal, 18)
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                    .accessibilityIdentifier("live.filter.option.\(title).\(option.title)")
                    .accessibilityAddTraits(selection == option.value ? .isSelected : [])
                }
            }
            .padding(.vertical, 6)
            .frame(minWidth: 235)
            .background(brand.raisedBackground)
            .presentationCompactAdaptation(.popover)
        }
    }
}

enum LiveFilterTint {
    /// Text companions preserve the pin hues with readable Light-mode contrast.
    static func people(_ audience: FeedAudience, brand: AstirBrandMode) -> Color {
        switch audience {
        case .everyone: brand.primaryText
        case .onlyMe: brand.accentText
        case .onlyFriends: brand.prefersDarkInterface ? WanderTheme.pinSocial.color : Color(red: 0.19, green: 0.41, blue: 0.51)
        }
    }

    static func featured(brand: AstirBrandMode) -> Color {
        brand.prefersDarkInterface ? Color(red: 0.435, green: 0.725, blue: 0.522)
            : Color(red: 0.18, green: 0.43, blue: 0.28)
    }
}
