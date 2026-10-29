import SwiftUI

/// The sidebar's search button. Go ▸ Search Tasks… remains available when the sidebar is collapsed.
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
