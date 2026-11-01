import ACP

extension AppModel {
    func contextTransfer(from source: SessionModel, to target: SessionModel) async -> ContextTransfer {
        let draft = await changeAgentContext(source)
        let prior = source.services.modelContinuations.transfer(for: source.key)
        var context = draft.after(prior)
        if prior == nil, let legacy = source.services.modelContinuations.context(for: source.key) {
            context.items.insert(
                .init(
                    reference: .init(
                        source: .init(agent: source.agent.id.rawValue, session: source.id),
                        id: "legacy-context", kind: .legacy, position: -1), text: legacy), at: 0)
        }
        return ContextTransfer(
            draft: context,
            destination: .init(agent: target.agent.id.rawValue, session: target.id),
            model: ComposerSettings(target.configOptions).model?.value,
            plan: .resolve(.freshConversation, target: .init(negotiated: nil, options: target.configOptions)),
            budget: .init(windowTokens: target.usage?.size, usedTokens: target.usage?.used ?? 0))
    }
}
