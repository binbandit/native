#if DEBUG
import ACP
import Foundation

/// Tasks in fixed states for the status bar's previews, so each shows exactly one situation
/// without an app model or an agent behind it.
final class TasksPreviewSource: StatusBarSource {
    let statusBarTasks: [TaskActivity]
    let statusBarAgentProcesses: [ProcessSampler.Root] = []

    /// - Parameters:
    ///   - working: How many tasks are on a turn; the longest started 74 seconds ago.
    ///   - waiting: What each task waiting on the user waits for, the first first.
    init(working: Int = 0, waiting: [TaskStatus] = []) {
        let waitingTasks = waiting.enumerated().map { index, status in
            Self.task("Fix the flaky sidebar test \(index + 1)", status: status, startedAgo: 300)
        }
        let workingTasks = (0..<working).map { index in
            Self.task("Add a slugify helper \(index + 1)", status: .working, startedAgo: 74 - Double(index) * 20)
        }
        statusBarTasks = waitingTasks + workingTasks
    }

    func showTask(_ id: SessionKey) {}

    private static func task(_ title: String, status: TaskStatus, startedAgo seconds: TimeInterval) -> TaskActivity {
        TaskActivity(
            id: SessionKey(agent: AgentDefinition.ID(rawValue: "codex"), id: SessionID(UUID().uuidString)),
            title: title, agentName: "Codex", projectName: "native", status: status,
            since: .now.addingTimeInterval(-seconds))
    }
}
#endif
