import SwiftUI

extension View {
    /// Draws a plain text field the way goal and workflow forms do, like the composer's surface:
    /// 12pt text on the surface fill inside a 1pt border that darkens on focus.
    func automationField() -> some View {
        modifier(AutomationField())
    }
}

private struct AutomationField: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        content
            .textFieldStyle(.plain)
            .font(.dsBody)
            .tracking(DS.Tracking.tight)
            .foregroundStyle(.dsTextPrimary)
            .focused($isFocused)
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm)
            .frame(minHeight: DS.Size.controlSM)
            .background(.dsSurface, in: shape)
            .overlay { shape.strokeBorder(isFocused ? Color.dsBorderHover : .dsBorder, lineWidth: 1) }
    }
}
