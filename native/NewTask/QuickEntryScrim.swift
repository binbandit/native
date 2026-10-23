import SwiftUI

/// The sheet dim covers both columns; the panel itself is centered on the task's column.
struct QuickEntryScrim: ViewModifier {
    let entry: QuickEntryModel
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .disabled(entry.isEnabled && entry.isPresented)
            .accessibilityHidden(entry.isEnabled && entry.isPresented)
            .overlay {
                if entry.isEnabled && entry.isPresented {
                    (scheme == .dark ? DS.QuickEntry.scrimDark : DS.QuickEntry.scrimLight)
                        .contentShape(.rect)
                        .onTapGesture { entry.dismiss() }
                        .accessibilityHidden(true)
                }
            }
    }
}
