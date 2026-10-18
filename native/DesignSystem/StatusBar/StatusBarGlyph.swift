import SwiftUI

/// A status-bar item's glyph: an SF Symbol at the sidebar footer's size and weight, so the footer
/// and the bar under it read as one band, in a fixed square so items' text lines up whatever the
/// symbol's shape.
public struct StatusBarGlyph: View {
    let systemName: String

    public init(_ systemName: String) {
        self.systemName = systemName
    }

    public var body: some View {
        Image(systemName: systemName)
            .font(.dsCallout)
            .frame(width: DS.Size.chromeGlyph, height: DS.Size.chromeGlyph)
            .accessibilityHidden(true)
    }
}
