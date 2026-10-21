import SwiftUI

extension View {
    /// Draws a text field as a setting's control, outlined: 32pt like the other controls, 14pt text,
    /// a 6pt radius and the accent outline while editing, so it reads as a control in both
    /// appearances.
    ///
    ///     TextField(".env*", text: $patterns).settingsField()
    func settingsField(focus: FocusState<Bool>.Binding? = nil) -> some View {
        modifier(SettingsFieldModifier(externalFocus: focus))
    }
}

private struct SettingsFieldModifier: ViewModifier {
    let externalFocus: FocusState<Bool>.Binding?
    @FocusState private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled

    // A field has one focus binding; callers that restore focus also drive its outline.
    private var focus: FocusState<Bool>.Binding { externalFocus ?? $isFocused }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        content
            .textFieldStyle(.plain)
            .font(SettingsTextStyle.body.font)
            .foregroundStyle(.dsTextPrimary)
            .focused(focus)
            .padding(.horizontal, DS.Space.lg)
            .frame(minHeight: SettingsMetrics.controlHeight)
            .background(.dsBackground, in: shape)
            .overlay { shape.strokeBorder(focus.wrappedValue ? Color.dsAccent : Color.dsBorder, lineWidth: 1) }
            .opacity(isEnabled ? 1 : 0.5)
    }
}

#if DEBUG
private struct SettingsTextFieldPreviewContent: View {
    @State private var text = "Mac mini"
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: DS.Space.lg) {
            TextField("Default focus", text: $text).settingsField()
            TextField("Shared focus", text: $text).settingsField(focus: $isFocused)
            TextField("Disabled", text: .constant("Read only")).settingsField().disabled(true)
            Button("Focus shared field") { isFocused = true }
                .buttonStyle(.ds(.secondary))
        }
        .padding(DS.Space.xxl)
        .frame(width: DS.Size.popoverWidth)
    }
}

#Preview("Settings fields - Focus and disabled") {
    DSPreviewPair {
        SettingsTextFieldPreviewContent()
    }
}
#endif
