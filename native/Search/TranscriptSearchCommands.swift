import NativeCommands
import SwiftUI

/// Go ▸ Search Tasks… (`search.show`, ⇧⌘F unless remapped; docs/keyboard.md).
struct TranscriptSearchMenuItem: View {
    let commands: CommandRegistry

    var body: some View {
        CommandMenuItem(.searchShow, in: commands)
    }
}

/// "Search" at the top of the sidebar, for pointer and touch.
struct TranscriptSearchNavItem: View {
    var body: some View {
        let center = BuiltInPlugins.search.center
        SidebarNavItem(
            "Search", systemImage: "magnifyingglass", isSelected: center.isPresented,
            shortcut: CommandRegistry.shared.shortcut(for: .searchShow)?.displayString
        ) {
            TranscriptSearch.open()
        } accessory: {
            EmptyView()
        }
    }
}

extension View {
    /// Presents the search panel over the window while it's open.
    func transcriptSearchPanel() -> some View {
        modifier(TranscriptSearchPresenter())
    }
}

private struct TranscriptSearchPresenter: ViewModifier {
    @Bindable private var center = BuiltInPlugins.search.center

    func body(content: Content) -> some View {
        content.sheet(isPresented: $center.isPresented) {
            TranscriptSearchPanel(center: center)
        }
    }
}
