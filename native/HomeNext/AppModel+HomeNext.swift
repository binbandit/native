import ACP
import Foundation

extension AppModel {
    var homeNextTasks: [HomeNextTask] {
        sessionList.map { summary in
            let live = session(summary.id)
            let status = live?.taskStatus ?? .idle
            let approval = live.flatMap(homeNextApproval)
            let turn = status == .done ? live?.state.turns.last : nil
            let changes = turn.flatMap { live?.state.summary(of: $0) }
            return HomeNextTask(
                id: summary.id, title: title(for: summary), agent: summary.agent.displayName,
                status: approval == nil ? status : .needsPermission,
                ask: live?.wait?.summary
                    ?? (status == .failed
                        ? "The agent stopped. Open the task to review its output and retry." : status.label),
                date: approval?.1.startedAt ?? lastActivity(for: summary),
                host: remotePlace(of: summary.id)?.host.name,
                approval: approval?.1, approvalSession: approval?.0, finishedAt: turn?.endedAt,
                diff: changes.flatMap {
                    $0.linesAdded + $0.linesRemoved > 0
                        ? DSFormat.diffStat(added: $0.linesAdded, removed: $0.linesRemoved) : nil
                })
        }
    }

    private func homeNextApproval(_ session: SessionModel) -> (SessionModel, ToolCallState)? {
        if let call = session.permissionRequests.first, call.kind != .switchMode {
            return (session, call)
        }
        return session.children.values.sorted { $0.id.rawValue < $1.id.rawValue }
            .lazy.compactMap(homeNextApproval).first
    }

    func openHomeNextTask(_ key: SessionKey) { selection = key }

    func openHomeNextFolder() { isAddingProject = true }

    /// A dropped file must never become a project merely because it has a file URL.
    func dropHomeNextFolders(_ urls: [URL]) -> Bool {
        let folders = urls.filter { url in
            url.isFileURL && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        guard !folders.isEmpty else { return false }
        Task { for folder in folders { await addProject(folder) } }
        return true
    }
}
