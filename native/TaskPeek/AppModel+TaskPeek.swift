import ACP
import Experiments
import Foundation

extension AppModel {
    var offersTaskPeek: Bool { experiments.value(of: .sidebarNext) || experiments.value(of: .homeNext) }

    var homeNextOwnsAskShortcut: Bool {
        experiments.value(of: .homeNext) && taskPeek.homeIsVisible && taskPeek.request == nil
    }

    var oldestTaskAsk: TaskPeekAsk? {
        sessionList.flatMap { taskAsks(for: $0.id) }.min { $0.since < $1.since }
    }

    /// What Answer Oldest Ask would answer right now. Rows show its keycap only on this ask, so a
    /// hint never points at a keystroke Home has taken for its own approval.
    var answerShortcutAsk: TaskPeekAsk? { homeNextOwnsAskShortcut ? nil : oldestTaskAsk }

    func taskAsks(for key: SessionKey) -> [TaskPeekAsk] {
        guard taskIsAvailable(key), taskIsReachable(key), let session = session(key) else { return [] }
        return TaskPeekAsk.requests(in: session, task: key)
    }

    func taskIsAvailable(_ key: SessionKey) -> Bool {
        catalog.contains(key) && !pendingDeletionKeys.contains(key)
    }

    func taskIsReachable(_ key: SessionKey) -> Bool {
        guard case .remote(let host) = device(of: key) else { return true }
        return hosts.host(host)?.isOnline == true
    }

    func peekTask(_ key: SessionKey, ask: TaskPeekAsk? = nil) {
        guard offersTaskPeek, taskIsAvailable(key) else { return }
        let ask = ask ?? taskAsks(for: key).first
        // Repeating the review shortcut must not replace an instruction being edited in this Peek.
        if let current = taskPeek.request, current.task == key, let shown = current.ask,
            shown.id == ask?.id, shown.isCurrent
        {
            return
        }
        taskPeek.answerFailure = nil
        taskPeek.approvalAttempt = 0
        taskPeek.restoresSidebarFocus = true
        taskPeek.request = .init(task: key, ask: ask)
        Task { await loadSession(key) }
    }

    func closeTaskPeek() {
        closeTaskPeek(restoringSidebarFocus: true)
    }

    func closeTaskPeek(restoringSidebarFocus: Bool) {
        taskPeek.restoresSidebarFocus = restoringSidebarFocus
        taskPeek.request = nil
        taskPeek.answerFailure = nil
    }

    func openPeekedTask(_ key: SessionKey) {
        closeTasksNeedingAttention()
        closeTaskPeek(restoringSidebarFocus: false)
        selection = key
    }

    func answerOldestTaskAsk() async {
        guard offersTaskPeek, !taskPeek.isAnswering, let ask = answerShortcutAsk else { return }
        if case .permission(let call) = ask.content, call.allowsQuickApproval,
            let option = call.permission?.options.first(where: { $0.kind == .allowOnce })
        {
            await answerTaskAsk(ask, option: option)
        } else {
            peekTask(ask.task, ask: ask)
        }
    }

    func answerTaskAsk(_ ask: TaskPeekAsk, option: PermissionOption) async {
        guard !taskPeek.isAnswering, taskIsAvailable(ask.task), taskIsReachable(ask.task),
            session(ask.session.key) === ask.session, ask.isCurrent,
            case .permission(let call) = ask.content, call.permission?.options.contains(option) == true
        else { return }
        let presentation = peekPresenting(ask)
        taskPeek.isAnswering = true
        taskPeek.answerFailure = nil
        defer { taskPeek.isAnswering = false }
        do {
            try await ask.session.respondToPermission(option, call: call)
            if let presentation, taskPeek.request?.id == presentation { closeTaskPeek() }
        } catch {
            // A failed shortcut also opens the exact ask for recovery, without replacing a newer Peek.
            guard taskPeek.request?.id == presentation else { return }
            if presentation == nil { peekTask(ask.task, ask: ask) }
            taskPeek.answerFailure = error.localizedDescription
            taskPeek.approvalAttempt += 1
        }
    }

    func answerTaskQuestion(_ ask: TaskPeekAsk, content: [String: JSONValue]?) async {
        guard !taskPeek.isAnswering, taskIsAvailable(ask.task), taskIsReachable(ask.task),
            session(ask.session.key) === ask.session, ask.isCurrent,
            case .question = ask.content
        else { return }
        let presentation = peekPresenting(ask)
        taskPeek.isAnswering = true
        if let content { await ask.session.answerQuestion(content) } else { await ask.session.declineQuestion() }
        if let presentation, taskPeek.request?.id == presentation { closeTaskPeek() }
        taskPeek.isAnswering = false
    }

    func instructTaskAsk(_ ask: TaskPeekAsk, text: String) async throws {
        guard !taskPeek.isAnswering, taskIsAvailable(ask.task), taskIsReachable(ask.task),
            session(ask.session.key) === ask.session, ask.isCurrent, case .permission(let call) = ask.content
        else { throw CancellationError() }
        let presentation = peekPresenting(ask)
        taskPeek.isAnswering = true
        defer { taskPeek.isAnswering = false }
        try await ask.session.instructBeforeDecliningPermission(text, call: call)
        if let presentation, taskPeek.request?.id == presentation { closeTaskPeek() }
    }

    private func peekPresenting(_ ask: TaskPeekAsk) -> UUID? {
        guard let request = taskPeek.request, request.task == ask.task,
            request.ask == nil || request.ask?.id == ask.id
        else { return nil }
        // A Peek opened while loading has no captured ask. Bind its answer to this presentation,
        // so a later Peek is kept even if the response takes time.
        return request.id
    }

    /// Recovery uses the same host/agent lifecycle as the task screen and leaves the current task alone.
    func recoverPeekedTask(_ key: SessionKey) async {
        guard !taskPeek.isRecovering, taskIsAvailable(key), taskIsReachable(key), let session = session(key),
            session.taskStatus == .failed
        else { return }
        taskPeek.isRecovering = true
        defer { taskPeek.isRecovering = false }
        let presentation = taskPeek.request?.id
        if session.phase == .disconnected, session.host == nil {
            await restart(key.agent, preservingDrafts: true)
            await loadSession(key)
        } else {
            do {
                try await session.submit(Self.interruptedTurnPrompt, .queue, echo: false)
            } catch {
                session.addNotice("Couldn't continue: \(error.localizedDescription)", isError: true)
                return
            }
        }
        if let recovered = self.session(key), recovered.taskStatus != .failed,
            taskPeek.request?.id == presentation
        {
            closeTaskPeek()
        }
    }
}
