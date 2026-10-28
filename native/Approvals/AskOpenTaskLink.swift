import SwiftUI

/// "Open Task ⌘↩" at the trailing edge of an ask's field, for hosts away from the task (Home).
struct AskOpenTaskLink: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.sm) {
                Text("Open Task").font(.dsBody)
                Kbd("⌘↩", compact: true)
            }
            .fixedSize()
        }
        .buttonStyle(.plain).foregroundStyle(.dsTextTertiary)
        .dsHitTarget(DS.Size.controlXS)
        .keyboardShortcut(.return, modifiers: .command)
    }
}
