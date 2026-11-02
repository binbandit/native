import ACP
import Experiments
import SwiftUI

/// Connects one task history to the app at launch: whether it's on, the agents its transcript names,
/// and joining a conversation that a change of agent starts to its task's history.
@MainActor
enum TaskHistoryWiring {
    static func connect(model: AppModel) {
        let contexts = TaskHistoryContexts.shared
        contexts.isEnabled = { model.experiments.value(of: .taskHistory) }
        contexts.agent = { model.runtime(AgentDefinition.ID(rawValue: $0))?.agent }
        // Runs after the hooks connected before it, such as Modes copying the earlier selection.
        let started = model.sessionHooks.taskStarted
        model.sessionHooks.taskStarted = { session, earlier, project in
            await started(session, earlier, project)
            await contexts.join(session, continuing: earlier)
        }
    }

    /// What a task's transcript shows before its own conversation: the agents before a change of
    /// agent, for a session that a change started.
    static func prelude(for session: SessionModel) -> TranscriptPrelude? {
        guard let earlier = session.services.earlierConversations.conversation(before: session.key),
            earlier.agent != session.agent.id
        else { return nil }
        return TranscriptPrelude(content: AnyView(TaskHistoryPrelude(session: session)))
    }

    /// What a task's transcript shows with its context markers: for a host transfer's marker, what
    /// the other agents did that it considered.
    static func markerContext(for session: SessionModel) -> TranscriptMarkerContext {
        TranscriptMarkerContext { marker in
            TaskHistoryTransfer.isMarkerID(marker.id)
                ? AnyView(TaskHistoryMarkerContent(session: session, marker: marker)) : nil
        }
    }
}
