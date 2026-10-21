import SessionTools
import SwiftUI

/// The panel beside the conversation: a tab for each side tool that has something to show, the open
/// one's pane under them, and Close. Escape closes it while focus is in it.
struct SessionToolsSidePanel: View {
    let tabs: [SessionToolContribution]
    let open: SessionToolContribution
    let context: (SessionToolContribution) -> SessionToolContext
    let select: (SessionToolID) -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.xxs) {
                ForEach(tabs) { tool in
                    SessionToolTab(
                        title: tool.title, systemImage: tool.systemImage,
                        accessory: tool.fact(context(tool))?.accessory,
                        isSelected: tool.id == open.id
                    ) {
                        select(tool.id)
                    }
                }
                Spacer(minLength: DS.Space.sm)
                IconButton("Close Side Panel", systemImage: "xmark", action: close)
            }
            .padding(.horizontal, DS.Space.md)
            .frame(height: DS.SessionTools.stripHeight)
            SeparatorLine()
            open.pane?(context(open))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.dsBackground)
        .onKeyPress(.escape) {
            close()
            return .handled
        }
    }
}

#if DEBUG
#Preview("Changes panel - Populated") {
    DSPreviewPair { SessionToolsPreviewFixtures.sidePanel }
}
#Preview("Changes panel - Clean, loading and error") {
    DSPreviewPair {
        if let context = SessionToolsPreviewFixtures.context {
            ForEach(["Clean", "Loading", "Error"], id: \.self) { state in
                let tool = SessionToolsPreviewFixtures.stateTool(state)
                SessionToolsSidePanel(tabs: [tool], open: tool, context: { _ in context }, select: { _ in }, close: {})
                    .frame(width: 340, height: 360)
            }
        }
    }
}
#endif
