import SwiftUI

/// The task's bottom bar reserves room for undo toasts above the composer. A page without a
/// composer contributes zero, so changing pages also puts the toast back in its usual corner.
nonisolated struct UndoToastBottomInset: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    func undoToastBottomInset(isEnabled: Bool = true) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: UndoToastBottomInset.self, value: isEnabled ? geometry.size.height : 0)
            }
        }
    }
}
