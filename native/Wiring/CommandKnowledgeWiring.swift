/// Count live approval requests at the model boundary, independent of whether their view is open.
/// Preview models never connect this wiring, so rendering fixtures cannot write coverage data.
enum CommandKnowledgeWiring {
    static func connect(_ model: AppModel) {
        let plugins = model.plugins
        model.sessionHooks.approvalsChanged = { session, requests in
            guard CommandKnowledgeCenter.isAvailable, !session.isRestoringHistory else { return }
            CommandKnowledgeCenter.shared.note(requests, session: session.clientID, knowledge: plugins.commandKnowledge)
        }
    }
}
