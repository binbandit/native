import ACP
import Foundation
import NativeHostProtocol

// Editing the queue of messages waiting for the running turn: changing, removing (and putting back),
// reordering, and sending one now.
extension HostCore {
    /// How many removed messages each session keeps for putting back.
    static let removedQueueLimit = 20

    /// Edits a queued message; emptying one that carries no attachments removes it.
    func updateQueued(_ params: QueueItemParams) throws {
        let session = try session(params.sessionID)
        guard let index = session.queue.firstIndex(where: { $0.prompt.id == params.itemID && !$0.isSteering }) else {
            throw HostError.notInQueue
        }
        let text = params.text.map(PromptQuote.trimmed) ?? ""
        if text.isEmpty, session.queue[index].prompt.attachments.isEmpty {
            remember(session.queue.remove(at: index).prompt, in: session)
        } else {
            session.queue[index].prompt.text = text
            if let content = session.queue[index].prompt.content {
                // The words were the content's text blocks; what else it carries stays.
                session.queue[index].prompt.content = [.text(text)] + content.filter { $0.text == nil }
            }
        }
        try store.setQueue(session.queue, for: session.id)
        publish(session)
    }

    func removeQueued(_ params: QueueItemParams) throws {
        let session = try session(params.sessionID)
        guard let index = session.queue.firstIndex(where: { $0.prompt.id == params.itemID && !$0.isSteering }) else {
            return
        }
        remember(session.queue.remove(at: index).prompt, in: session)
        try store.setQueue(session.queue, for: session.id)
        publish(session)
    }

    /// Puts a removed message back at `index` (undo).
    func restoreQueued(_ params: RestoreQueuedParams) throws {
        let session = try session(params.sessionID)
        guard let removed = session.removedFromQueue.lastIndex(where: { $0.id == params.itemID }) else {
            throw HostError.notInQueue
        }
        let prompt = session.removedFromQueue.remove(at: removed)
        let index = min(max(params.index, 0), session.queue.count)
        session.queue.insert(StoredQueueItem(prompt: prompt, isSteering: false), at: index)
        try store.setQueue(session.queue, for: session.id)
        publish(session)
        deliverPendingSteer(in: session)
    }

    /// Moves a queued message to just before `before`, or to the end.
    func moveQueued(_ params: MoveQueuedParams) throws {
        let session = try session(params.sessionID)
        guard params.before != params.itemID,
            let index = session.queue.firstIndex(where: { $0.prompt.id == params.itemID && !$0.isSteering })
        else { return }
        let item = session.queue.remove(at: index)
        let target = params.before.flatMap { before in session.queue.firstIndex { $0.prompt.id == before } }
        session.queue.insert(item, at: target ?? session.queue.endIndex)
        try store.setQueue(session.queue, for: session.id)
        publish(session)
    }

    /// Uses the same tool-safe path as Steer, or sends the next prompt when the session is idle.
    func sendQueuedNow(_ params: QueueItemParams) async throws {
        let session = try session(params.sessionID)
        guard let index = session.queue.firstIndex(where: { $0.prompt.id == params.itemID && !$0.isSteering }) else {
            return
        }
        switch session.phase {
        case .prompting where !session.isStopping:
            let item = session.queue.remove(at: index)
            try store.setQueue(session.queue, for: session.id)
            _ = try await submitSteer(item.prompt, into: session)
        case .idle where session.turn == nil && session.hiddenCommand == nil:
            cancelRetry(of: session)
            let item = session.queue.remove(at: index)
            try startTurn(in: session, prompt: item.prompt)
        default:
            break
        }
    }

    private func remember(_ prompt: OutgoingPrompt, in session: HostSession) {
        session.removedFromQueue.append(prompt)
        if session.removedFromQueue.count > Self.removedQueueLimit {
            session.removedFromQueue.removeFirst()
        }
    }
}
