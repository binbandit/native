import SwiftUI

/// Marks a status-bar item that has a shorter form, so the bar shortens it before dropping items.
nonisolated struct StatusBarCompactable: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    /// A shorter form of this status-bar item, for a window too narrow for every item at full
    /// length. The bar shortens items that have one, innermost first, before it drops any item
    /// whole, so what an item says survives in fewer words instead of disappearing. Keep the same
    /// glyphs and drop the words around them: "2 working 4m" becomes the working loader and "2".
    ///
    /// Apply it to the item's whole content, and keep work that should run once (a `.task`, an
    /// `.onAppear`) outside it: the bar may show either form.
    public func statusBarCompactForm(@ViewBuilder _ compact: () -> some View) -> some View {
        // Both at their ideal widths: the bar proposes one form's exact width, and either form
        // squeezed by a rounding error would cut its text short.
        ViewThatFits(in: .horizontal) {
            fixedSize(horizontal: true, vertical: false)
            compact().fixedSize(horizontal: true, vertical: false)
        }
        .layoutValue(key: StatusBarCompactable.self, value: true)
    }
}
