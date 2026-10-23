import SwiftUI

extension DS {
    /// Compose's compact panel, from the approved Quick Entry drawing.
    nonisolated enum QuickEntry {
        static let width: CGFloat = 760
        static let toolbarGap: CGFloat = 12
        static let textInsets = EdgeInsets(top: 18, leading: 20, bottom: 14, trailing: 64)
        static let editorFont = Font.ds(15)
        static let editorLineSpacing: CGFloat = 5
        static let barHeight: CGFloat = 50
        static let clipInset: CGFloat = 20
        static let clipMaxHeight: CGFloat = 96
        static let pickerMaxHeight: CGFloat = 280
        static let toastBottom: CGFloat = 80
        static let scrimLight = Color.black.opacity(0.14)
        static let scrimDark = Color.black.opacity(0.38)
    }
}
