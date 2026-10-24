import ACP
import Foundation

extension AppModel {
    /// Independent of the sidebar's filters and collapsed projects. Count tasks, not requests.
    var tasksNeedingAttention: [TaskAttentionItem] {
        sessionList.compactMap { summary -> TaskAttentionItem? in
            guard taskIsAvailable(summary.id), taskIsReachable(summary.id) else { return nil }
            let ask = taskAsks(for: summary.id).first
            guard ask != nil || session(summary.id)?.taskStatus == .failed else { return nil }
            return TaskAttentionItem(summary: summary, ask: ask)
        }.sorted {
            let left = $0.ask?.since ?? .distantFuture
            let right = $1.ask?.since ?? .distantFuture
            if left != right { return left < right }
            if $0.id.agent != $1.id.agent { return $0.id.agent.rawValue < $1.id.agent.rawValue }
            return $0.id.id.rawValue < $1.id.id.rawValue
        }
    }

    func showTasksNeedingAttention() {
        guard offersTaskPeek, !tasksNeedingAttention.isEmpty else { return }
        closeTaskPeek()
        taskPeek.showsAttentionList = true
    }

    func closeTasksNeedingAttention() {
        guard taskPeek.showsAttentionList else { return }
        closeTaskPeek()
        taskPeek.showsAttentionList = false
    }
}
