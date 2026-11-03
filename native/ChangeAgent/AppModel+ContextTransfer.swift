import ACP
import Experiments
import NativeHostClient
import NativeHostProtocol

extension AppModel {
    func contextTransfer(from source: SessionModel, to target: SessionModel) async -> ContextTransfer {
        let transcript = await changeAgentContext(source)
        var context: ContextTransfer.Draft
        if let history = await historyContext(of: source) {
            // The task's own items, every agent's, so the receipt names what the new conversation
            // has seen; the transcript adds what the history doesn't keep (the goal, changed files).
            context = history
            let extras = transcript.items.filter { [.goal, .file, .status].contains($0.reference.kind) }
            context.items =
                extras.filter { $0.reference.kind == .goal } + history.items
                + extras.filter { $0.reference.kind != .goal }
        } else {
            let prior = source.services.modelContinuations.transfer(for: source.key)
            context = transcript.after(prior)
            if prior == nil, let legacy = source.services.modelContinuations.context(for: source.key) {
                context.items.insert(
                    .init(
                        reference: .init(
                            source: .init(agent: source.agent.id.rawValue, session: source.id),
                            id: "legacy-context", kind: .legacy, position: -1), text: legacy), at: 0)
            }
        }
        return ContextTransfer(
            draft: context,
            destination: .init(agent: target.agent.id.rawValue, session: target.id),
            model: ComposerSettings(target.configOptions).model?.value,
            plan: .resolve(.freshConversation, target: .init(negotiated: nil, options: target.configOptions)),
            budget: .init(windowTokens: target.usage?.size, usedTokens: target.usage?.used ?? 0))
    }

    /// The newest of the task's history on its host, as a handoff's draft, behind the `task-history`
    /// gate. Nil without one: the transcript's excerpt goes instead, as before.
    private func historyContext(of source: SessionModel) async -> ContextTransfer.Draft? {
        guard experiments.value(of: .taskHistory), let link = source.host,
            let summary = try? await link.client.historySummary(of: link.id),
            let items = try? await link.client.readHistory(
                ReadHistoryParams(sessionID: link.id, after: max(0, summary.head - 500), through: summary.head)),
            !items.isEmpty
        else { return nil }
        return TaskHistoryDelta.draft(items, participants: summary.participants)
    }
}
