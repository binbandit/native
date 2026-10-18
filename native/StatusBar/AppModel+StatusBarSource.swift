import ACP
import Foundation

extension AppModel: StatusBarSource {
    var statusBarTasks: [TaskActivity] {
        let tasks = sessionList.compactMap { summary -> TaskActivity? in
            guard let session = session(summary.id), let status = Self.activeStatus(of: session) else { return nil }
            return TaskActivity(
                id: summary.id,
                title: session.displayTitle,
                agentName: session.agentName,
                projectName: projects.project(summary.project)?.name,
                status: status,
                since: session.lastActivity
            )
        }
        // Waiting on the user first: those are the ones to act on.
        return tasks.filter(\.needsAttention) + tasks.filter { !$0.needsAttention }
    }

    var statusBarAgentProcesses: [ProcessSampler.Root] {
        agents.compactMap { runtime in
            runtime.processIdentifier.map {
                ProcessSampler.Root(pid: $0, kind: .agent(runtime.agent.id.rawValue), title: runtime.agent.displayName)
            }
        }
    }

    func showTask(_ id: SessionKey) {
        selection = id
    }

    /// A task's status while it's busy or needs the user; nil when it's neither. What it waits for
    /// comes first: a task can be both working and waiting on an approval.
    private static func activeStatus(of session: SessionModel) -> TaskStatus? {
        switch session.wait {
        case .input: .needsInput
        case .permission: .needsPermission
        case .planReview: .needsPlanReview
        case nil: session.phase == .prompting ? .working : nil
        }
    }
}
