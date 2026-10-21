import NativeCommands
import SwiftUI

/// Go ▸ Search Tasks… (`search.show`, ⇧⌘F unless remapped; docs/keyboard.md).
struct TranscriptSearchMenuItem: View {
    let menu: CommandMenuContext

    var body: some View {
        CommandMenuItem(.searchShow, in: menu)
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
