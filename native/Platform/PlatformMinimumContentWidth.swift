import SwiftUI

extension View {
    /// Keeps the Mac's minimum-size question from laying the content out at no width. AppKit asks a
    /// window's content for its minimum size whenever the content changes, and SwiftUI answers by
    /// laying it out at zero width: text that keeps its full height
    /// (`.fixedSize(horizontal: false, vertical: true)`) then measures a character per line, the
    /// window's minimum height grows past the screen, and AppKit eventually aborts the layout pass
    /// (docs/performance.md). With this floor the content is measured at `width` instead. Keep
    /// `width` at or under the narrowest the content can be anyway, so the window's own minimum
    /// doesn't change. iPadOS sizes windows itself, so it's the content unchanged there.
    func platformMinimumContentWidth(_ width: CGFloat) -> some View {
        #if os(macOS)
        frame(minWidth: width)
        #else
        self
        #endif
    }
}
