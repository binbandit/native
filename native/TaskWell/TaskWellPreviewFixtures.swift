#if DEBUG
import ACP
import Foundation

enum TaskWellPreviewFixtures {
    static var states: [TaskWellContent] {
        [
            TaskWellContent(status: .idle, agent: "Codex"),
            TaskWellContent(status: .starting, agent: "Codex", verb: "Starting"),
            TaskWellContent(status: .working, agent: "Codex", verb: "Stopping"),
            TaskWellContent(status: .working, agent: "Codex", verb: "Reconnecting"),
            TaskWellContent(
                status: .working, agent: "Claude Code", verb: "Running", object: "swift test",
                progress: .init(completed: 9, total: 12)),
            TaskWellContent(
                status: .working, agent: "A very long agent name", verb: "Reading",
                object: "Sources/Native/PromptQueueTests.swift"),
            TaskWellContent(
                status: .needsPermission, agent: "Codex", verb: "Waiting on you",
                object: "Overwrite main on github.com", attentionSince: .now),
            TaskWellContent(status: .done, agent: "Codex", outcome: outcome, showsReview: true),
            TaskWellContent(status: .idle, agent: "Codex", outcome: outcome, showsReview: true),
            TaskWellContent(status: .failed, agent: "Codex", verb: "Turn failed", object: "See the conversation"),
            TaskWellContent(status: .cancelled, agent: "Codex", verb: "Stopped"),
        ]
    }

    static var outcome: TurnSummary {
        var summary = TurnSummary(items: [TranscriptItem]())
        summary.changedFiles = [
            .init(path: "DiffRow.swift", added: 12, removed: 2),
            .init(path: "DiffLayout.swift", added: 3),
            .init(path: "DiffLayoutTests.swift", added: 2),
        ]
        return summary
    }
}
#endif
