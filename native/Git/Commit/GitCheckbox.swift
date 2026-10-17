import SwiftUI

/// A small checkbox in the design system's colors: outlined when off, accent-filled when on, with a
/// dash for a partial selection.
struct GitCheckbox: View {
    enum Value {
        case off, on, mixed
    }

    let value: Value
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            let shape = RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
            ZStack {
                shape.fill(value == .off ? Color.dsSurface : .dsAccent)
                shape.strokeBorder(value == .off ? Color.dsBorderStrong : .clear, lineWidth: 1)
                if value != .off {
                    Image(systemName: value == .on ? "checkmark" : "minus")
                        .font(.system(size: GitMetrics.checkboxGlyph, weight: .bold))
                        .foregroundStyle(.dsTextOnAccent)
                }
            }
            .frame(width: GitMetrics.checkbox, height: GitMetrics.checkbox)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(value == .on ? "Checked" : value == .mixed ? "Mixed" : "Unchecked")
        .accessibilityAddTraits(.isToggle)
    }
}
