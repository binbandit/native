import ACP
import NativeHostProtocol

/// What a context marker shows of the agents before it: their messages and tool calls, one run per
/// agent, as transcript rows.
struct TaskHistoryContext: Equatable {
    struct Run: Identifiable, Equatable {
        let id: Int
        /// Nil for an agent that's no longer available, which is named generically.
        let agent: AgentDefinition?
        let rows: [TranscriptRow]

        var agentName: String { agent?.displayName ?? "An earlier agent" }
    }

    let runs: [Run]
    /// Older messages are in the earlier conversations, not here.
    let omitsEarlier: Bool

    init(runs: [Run], omitsEarlier: Bool) {
        self.runs = runs
        self.omitsEarlier = omitsEarlier
    }

    init(runs: [TaskHistoryRun], omitsEarlier: Bool, agent: @MainActor (String) -> AgentDefinition?) {
        self.runs = runs.map { run in
            Run(
                id: run.id, agent: agent(run.participant.agentID),
                rows: TranscriptRow.rows(from: run.items.compactMap(\.transcriptItem), grouping: true))
        }
        self.omitsEarlier = omitsEarlier
    }
}
