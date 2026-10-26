import ACP
import Experiments
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

    /// ⌘N writes in Home's start field while Home shows it, rather than opening another surface.
    var homeNextOwnsNewTask: Bool {
        experiments.value(of: .homeNext) && taskPeek.homeIsVisible && selection == nil && !projects.all.isEmpty
    }

    /// What finished, asked or failed between `start` and `end`, as the user finds it on return.
    func homeNextAway(from start: Date, to end: Date) -> HomeNextAway {
        var away = HomeNextAway(start: start, end: end)
        for task in homeNextTasks(retaining: nil) {
            if away.contains(task.finishedAt) {
                away.finished += 1
            } else if task.status == .failed, away.contains(task.date) {
                away.failed += 1
            } else if task.needsYou, task.status != .limited, away.contains(task.date) {
                away.asked += 1
            }
        }
        return away
    }

    /// Use only a name the agent reported. Before its first session, show the agent rather than a wire id.
    var homeNextModelName: String? {
        guard let agent = quickEntry.agent else { return nil }
        let choices = AgentSessionDefaults.offeredChoices(for: agent, setting: .model)
        let explicit =
            quickEntry.project.flatMap { ProjectTaskDefaults.model(for: $0, agent: agent) }
            ?? AgentSessionDefaults.explicitValue(for: agent, setting: .model)
        if let explicit { return choices.first { $0.value == explicit }?.name }
        guard let name = quickEntryModelName else { return nil }
        return choices.first { $0.name == name }?.name
    }

    /// Agents paused at a usage limit, with the tasks each one stopped. Empty while Usage is off.
    var homeNextLimits: [HomeNextLimit] {
        #if DEBUG
        if let limits = homeNext.fixtureLimits { return limits }
        #endif
        guard plugins.isEnabled(BuiltInPlugins.usage.manifest.id) else { return [] }
        let limits = BuiltInPlugins.usage.limits
        return limits.providers.values
            .filter { $0.status == .reached && limits.limitStatus(for: $0.agent) != nil }
            .sorted { $0.updatedAt < $1.updatedAt }
            .map { limit in
                // Usage keeps references across deletions; only tasks that still exist can be shown.
                let stopped = limits.sessions.values
                    .filter { $0.target.agent == limit.agent && $0.target.isPromptable }
                    .filter { taskIsAvailable(SessionKey(agent: $0.target.agent, id: $0.target.session)) }
                    .sorted { $0.target.session.rawValue < $1.target.session.rawValue }
                let keys = stopped.map { SessionKey(agent: $0.target.agent, id: $0.target.session) }
                return HomeNextLimit(
                    agent: limit.agent, agentName: limit.agentName, window: limit.window?.label,
                    resetsAt: limit.resetsAt, since: limit.updatedAt, tasks: keys,
                    titles: zip(keys, stopped).map { key, session in
                        sessionList.first { $0.id == key }.map(title(for:)) ?? session.target.title ?? "A task"
                    },
                    resumes: stopped.contains { $0.resumeAt != nil })
            }
    }

    /// The limit row opens the first task it stopped in Peek.
    func peekHomeNextLimit(_ limit: HomeNextLimit) {
        guard let key = limit.tasks.first else { return }
        peekTask(key)
    }

    /// Starts the start field's draft. Return stays on Home with a receipt; ⌘Return opens the task.
    func startHomeNextTask(open: Bool) -> StartingTask? {
        guard experiments.value(of: .homeNext), quickEntry.hasMessage else { return nil }
        #if DEBUG
        // Fixtures are inert: they never start an agent or make a worktree.
        guard HomeNextPreviewFixtures.requested == nil else { return nil }
        #endif
        return startQuickEntryDraft(open: open, confirms: false)
    }

    /// An empty draft follows the project Home is showing; a draft keeps the address it was written to.
    func prepareHomeNextStart() {
        guard !quickEntry.isPresented, !composeTask.isPresented, quickEntry.draft.isEmpty, quickEntry.context == nil,
            quickEntry.attachments.isEmpty
        else {
            reconcileQuickEntryAgent()
            return
        }
        prepareQuickEntryAddress()
        reconcileQuickEntryAgent()
    }

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
