import NativeAutomation
import SwiftUI

/// A text field in goal and workflow forms, drawn like the composer's surface: 12pt text on the
/// surface fill inside a 1pt border that darkens on focus. The placeholder is drawn here, in the
/// design system's color, because macOS fields ignore a styled prompt.
struct AutomationTextField: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var axis: Axis = .horizontal
    var lines: ClosedRange<Int> = 1...1
    var font: Font = .dsBody
    var onSubmit: () -> Void = {}
    private var focusesOnAppear = false

    @FocusState private var isFocused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        // An empty title: macOS would show a title as a second placeholder under ours.
        TextField("", text: $text, axis: axis)
            .lineLimit(lines)
            .textFieldStyle(.plain)
            .font(font)
            .tracking(DS.Tracking.tight)
            .labelsHidden()
            .focused($isFocused)
            .onSubmit(onSubmit)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(font)
                        .tracking(DS.Tracking.tight)
                        .foregroundStyle(.dsTextTertiary)
                        .lineLimit(lines.upperBound)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm)
            .frame(minHeight: DS.Size.controlSM)
            .background(.dsSurface, in: shape)
            .overlay { shape.strokeBorder(isFocused ? Color.dsBorderHover : .dsBorder, lineWidth: 1) }
            .accessibilityLabel(label)
            .onAppear {
                if focusesOnAppear {
                    isFocused = true
                }
            }
    }

    /// Takes keyboard focus as soon as it appears.
    func focusedOnAppear() -> AutomationTextField {
        var field = self
        field.focusesOnAppear = true
        return field
    }
}
