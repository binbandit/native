import SwiftUI

/// The same search as Go ▸ Search Tasks…, reachable even with the sidebar collapsed.
struct TranscriptSearchToolbarButton: View {
    var body: some View {
        WindowToolbarButton(
            "Search Tasks", systemImage: "magnifyingglass",
            shortcut: CommandRegistry.shared.keyboardShortcut(for: .searchShow)
        ) {
            TranscriptSearch.open()
        }
    }
}

#if DEBUG
#Preview("Search toolbar - Available and disabled") {
    DSPreviewPair {
        HStack(spacing: DS.Space.xs) {
            TranscriptSearchToolbarButton()
            TranscriptSearchToolbarButton()
                .disabled(true)
        }
    }
}
#endif
