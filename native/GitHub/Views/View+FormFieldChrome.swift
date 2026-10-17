import SwiftUI

extension View {
    /// The sheet's input chrome: surface fill, 1pt border that turns accent while focused.
    func formFieldChrome(isFocused: Bool, isMultiline: Bool = false, height: CGFloat = DS.Size.controlSM) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        return padding(.horizontal, DS.Space.md)
            .padding(.vertical, isMultiline ? DS.Space.sm : 0)
            .frame(minHeight: isMultiline ? nil : height)
            .background(.dsSurface, in: shape)
            .overlay { shape.strokeBorder(isFocused ? Color.dsAccent : Color.dsBorder, lineWidth: 1) }
    }
}
