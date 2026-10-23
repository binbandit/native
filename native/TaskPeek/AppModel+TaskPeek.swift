import ACP
import Experiments
import Foundation

extension AppModel {
    var offersTaskPeek: Bool { experiments.value(of: .sidebarNext) }

    var oldestTaskAsk: TaskPeekAsk? {
        sessionList.flatMap { taskAsks(for: $0.id) }.min { $0.since < $1.since }
    }

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
        taskPeek.request = .init(task: key, ask: ask ?? taskAsks(for: key).first)
        Task { await loadSession(key) }
    }

    func closeTaskPeek() { taskPeek.request = nil }

    func openPeekedTask(_ key: SessionKey) {
        closeTaskPeek()
        selection = key
    }

    func answerOldestTaskAsk() async {
        guard offersTaskPeek, !taskPeek.isAnswering, let ask = oldestTaskAsk else { return }
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
        taskPeek.isAnswering = true
        await ask.session.choose(option, forToolCall: call.id)
        if taskPeek.request?.ask?.id == ask.id { closeTaskPeek() }
        taskPeek.isAnswering = false
    }

    func answerTaskQuestion(_ ask: TaskPeekAsk, content: [String: JSONValue]?) async {
        guard !taskPeek.isAnswering, taskIsAvailable(ask.task), taskIsReachable(ask.task),
            session(ask.session.key) === ask.session, ask.isCurrent,
            case .question = ask.content
        else { return }
        taskPeek.isAnswering = true
        if let content { await ask.session.answerQuestion(content) } else { await ask.session.declineQuestion() }
        if taskPeek.request?.ask?.id == ask.id { closeTaskPeek() }
        taskPeek.isAnswering = false
    }

    /// Recovery uses the same host/agent lifecycle as the task screen and leaves the current task alone.
    func recoverPeekedTask(_ key: SessionKey) async {
        guard taskIsAvailable(key), taskIsReachable(key), let session = session(key), session.taskStatus == .failed
        else { return }
        let presentation = taskPeek.request?.id
        if session.phase == .disconnected, session.host == nil {
            await restart(key.agent)
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
