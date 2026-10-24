import SwiftUI

/// The sheet dim covers both columns; the panel itself is centered on the task's column.
struct QuickEntryScrim: ViewModifier {
    let isPresented: Bool
    var dismiss: () -> Void = {}
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .disabled(isPresented)
            .accessibilityHidden(isPresented)
            .overlay {
                if isPresented {
                    (scheme == .dark ? DS.QuickEntry.scrimDark : DS.QuickEntry.scrimLight)
                        .contentShape(.rect)
                        .onTapGesture(perform: dismiss)
                        .accessibilityHidden(true)
                }
            }
    }
}
