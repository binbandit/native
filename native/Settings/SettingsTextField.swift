import SwiftUI

extension View {
    /// Draws a text field as a setting's control, in the reference app's outline: 32pt like the other
    /// controls, 14pt text, a 6pt radius and the accent outline while editing, so it reads as a
    /// control in both appearances.
    ///
    ///     TextField(".env*", text: $patterns).settingsField()
    func settingsField() -> some View {
        modifier(SettingsFieldModifier())
    }
}

private struct SettingsFieldModifier: ViewModifier {
    @FocusState private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        content
            .textFieldStyle(.plain)
            .font(SettingsTextStyle.body.font)
            .foregroundStyle(.dsTextPrimary)
            .focused($isFocused)
            .padding(.horizontal, DS.Space.lg)
            .frame(minHeight: SettingsMetrics.controlHeight)
            .background(.dsBackground, in: shape)
            .overlay { shape.strokeBorder(isFocused ? Color.dsAccent : Color.dsBorder, lineWidth: 1) }
            .opacity(isEnabled ? 1 : 0.5)
    }
}
