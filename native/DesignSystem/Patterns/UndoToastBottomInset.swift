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
                // Composer and notice surfaces all start after this top margin. Measure their
                // visible edge so the toast's twelve-point gap does not count that margin twice.
                Color.clear.preference(
                    key: UndoToastBottomInset.self,
                    value: isEnabled ? max(0, geometry.size.height - DS.Space.md) : 0)
            }
        }
    }
}
