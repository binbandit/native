import ACP
import Foundation

extension AppModel: StatusBarSource {
    var statusBarTasks: [TaskActivity] {
        let tasks = sessionList.compactMap { summary -> TaskActivity? in
            guard let session = session(summary.id) else { return nil }
            let status = session.taskStatus
            // Only what's on a turn or blocked on the user. Loading a task's history isn't work.
            guard status == .working || status.needsAttention else { return nil }
            return TaskActivity(
                id: summary.id,
                title: session.displayTitle,
                agentName: session.agentName,
                projectName: projects.project(summary.project)?.name,
                status: status,
                since: session.lastActivity,
                workingAnimation: session.workingAnimation
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
}
