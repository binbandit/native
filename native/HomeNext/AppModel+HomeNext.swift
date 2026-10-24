import ACP
import Foundation
import TaskList

extension AppModel {
    func homeNextTasks(retaining current: HomeNextRequest.ID?) -> [HomeNextTask] {
        sessionList.map { summary in
            let live = session(summary.id)
            let status = live?.taskStatus ?? .idle
            let requests = (live.map(homeNextRequests) ?? []).sorted { $0.kind.rawValue < $1.kind.rawValue }
            let request = HomeAskOrder.first(requests, retaining: current, id: \.id)
            let turn = status == .done ? live?.state.turns.last : nil
            let changes = turn.flatMap { live?.state.summary(of: $0) }
            return HomeNextTask(
                id: summary.id, title: title(for: summary), agent: summary.agent.displayName,
                status: request?.status ?? status,
                ask: request?.summary ?? live?.wait?.summary
                    ?? (status == .failed
                        ? live.flatMap { TurnFailureContext(state: $0.state).details }
                            ?? "The agent stopped before finishing. Retry or open the task."
                        : status.label),
                date: request?.call?.startedAt ?? lastActivity(for: summary),
                host: remotePlace(of: summary.id)?.host.name,
                request: request, session: live, finishedAt: turn?.endedAt,
                diff: changes.flatMap {
                    $0.linesAdded + $0.linesRemoved > 0
                        ? DSFormat.diffStat(added: $0.linesAdded, removed: $0.linesRemoved) : nil
                })
        }
    }

    private func homeNextRequests(_ session: SessionModel) -> [HomeNextRequest] {
        session.permissionRequests.map { HomeNextRequest(session: session, call: $0) }
            + (session.pendingQuestion.map { [HomeNextRequest(session: session, question: $0)] } ?? [])
            + session.children.values.sorted { $0.id.rawValue < $1.id.rawValue }.flatMap(homeNextRequests)
    }

    func setHomeNextVisible(_ visible: Bool) { taskPeek.homeIsVisible = visible }

    func peekHomeNextTask(_ task: HomeNextTask) {
        let ask = taskAsks(for: task.id).first { ask in
            guard let request = task.request, request.session === ask.session else { return false }
            switch ask.content {
            case .permission(let call): return call == request.call
            case .question(let question): return question.id == request.question?.id
            }
        }
        peekTask(task.id, ask: ask)
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
