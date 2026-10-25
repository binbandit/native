import ACP

extension AppModel {
    /// Keep the pending message until the real transcript or queue can replace it without a blank frame.
    var composeCanRevealTask: Bool {
        guard composeTask.isPresented, composeTask.stage == .settled, let task = composeTask.starting else {
            return false
        }
        if task.failure != nil { return true }
        guard let key = task.openedSession, let session = session(key) else { return false }
        guard task.isSendRequested else { return true }
        let showsMessage = session.state.items.contains {
            if case .message(let message) = $0 { message.role == .user } else { false }
        }
        switch task.composeSubmission {
        case .pending: return false
        case .sent: return showsMessage
        case .queued: return showsMessage || session.hasQueuedPrompts
        case .failed: return true
        }
    }

    func sendComposeFirstMessage(_ task: StartingTask, to session: SessionModel) async {
        do {
            let delivery = try await session.submit(task.draft, attaching: task.attachments, .queue)
            // A user can leave the handoff and edit the live draft before the host answers.
            if session.draft == task.draft && session.attachments == task.attachments {
                session.draft = ""
                session.attachments = []
            }
            task.composeSubmission = delivery == .queued ? .queued : .sent
        } catch {
            task.composeSubmission = .failed
            session.addNotice(
                "Couldn't send the first message. Your draft is kept. Try sending it again.", isError: true)
        }
        if composeTask.starting === task { finishComposeTransition() }
    }

    func finishComposeTransition() {
        guard composeCanRevealTask else { return }
        composeTask.isPresented = false
        composeTask.editor = nil
        composeTask.starting = nil
    }
}
