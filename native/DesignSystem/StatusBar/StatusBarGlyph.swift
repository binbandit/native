import SwiftUI

/// A status-bar item's glyph: an SF Symbol at the sidebar footer's regular weight, a size up from
/// the caption beside it, in a fixed square so items' text lines up whatever the symbol's shape.
public struct StatusBarGlyph: View {
    let systemName: String

    public init(_ systemName: String) {
        self.systemName = systemName
    }

    public var body: some View {
        Image(systemName: systemName)
            .font(.dsBody)
            .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
            .accessibilityHidden(true)
    }
}
