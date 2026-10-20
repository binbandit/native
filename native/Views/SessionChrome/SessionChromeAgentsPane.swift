#if DEBUG && NATIVE_SESSION_CHROME_WIP
import ACP
import SwiftUI

/// The task's subagents as a pane: the list, or the one picked's own conversation.
struct SessionChromeAgentsPane: View {
    let session: SessionModel
    let chrome: SessionChromeModel

    var body: some View {
        let subagents = session.state.subagents
        if let id = chrome.openSubagent, let subagent = subagents.first(where: { $0.id == id }) {
            SubagentInspector(subagent: subagent, child: session.child(id))
        } else if subagents.isEmpty {
            EmptyStateView(
                "No subagents yet", systemImage: "person.2",
                message: "When the agent hands work to a subagent, its conversation shows here.")
        } else {
            ScrollView {
                VStack(spacing: DS.Space.sm) {
                    ForEach(subagents, id: \.id) { subagent in
                        SubagentCard(subagent: subagent) { chrome.openSubagent = subagent.id }
                    }
                }
                .padding(DS.Space.lg)
            }
        }
    }
}
#endif
