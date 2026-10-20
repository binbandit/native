import ACP
import Observation
import SessionTools
import SwiftUI

/// Subagents as a session tool: "2 subagents" under the title while the agent has handed work
/// off, and their conversations as its pane, opened from a subagent's card in the transcript.
@MainActor
enum SessionSubagentsTool {
    static let contribution = SessionToolContribution(
        spec: SessionToolSpec(id: .subagents, places: [.side, .fact, .off], defaultPlace: .side),
        title: "Subagents", systemImage: "person.2",
        fact: { context in
            let count = context.session.state.subagents.count
            guard count > 0 else { return nil }
            return SessionToolFact(text: count == 1 ? "1 subagent" : "\(count) subagents")
        },
        hasContent: { !$0.session.state.subagents.isEmpty },
        pane: { context in
            AnyView(SessionSubagentsPane(session: context.session, state: context.state(SessionSubagentsState.init)))
        },
        transcript: { context in
            SessionTranscriptActions(openSubagent: { id in
                context.state(SessionSubagentsState.init).open = id
                context.open(.subagents)
            })
        })
}

/// Which subagent's conversation the tool shows.
@Observable
final class SessionSubagentsState {
    var open: SessionID?
}

/// The task's subagents, or the open one's conversation with the way back to the list.
private struct SessionSubagentsPane: View {
    let session: SessionModel
    @Bindable var state: SessionSubagentsState

    var body: some View {
        let subagents = session.state.subagents
        if let id = state.open, let subagent = subagents.first(where: { $0.id == id }) {
            SubagentInspector(subagent: subagent, child: session.child(id))
                .safeAreaInset(edge: .top, spacing: 0) {
                    if subagents.count > 1 {
                        Button("All Subagents", systemImage: "chevron.left") { state.open = nil }
                            .buttonStyle(.ds(.ghost))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DS.Space.sm)
                    }
                }
        } else if subagents.isEmpty {
            EmptyStateView(
                "No subagents", systemImage: "person.2",
                message: "When the agent hands work to a subagent, its conversation shows here.")
        } else {
            ScrollView {
                VStack(spacing: DS.Space.sm) {
                    ForEach(subagents, id: \.id) { subagent in
                        SubagentCard(subagent: subagent) { state.open = subagent.id }
                    }
                }
                .padding(DS.Space.lg)
            }
        }
    }
}
