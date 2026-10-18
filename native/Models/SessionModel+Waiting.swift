import ACP

/// What a session is waiting on the user for, in a line.
enum SessionWait: Equatable {
    /// A question from the agent.
    case input(String)
    /// Approval to run a tool.
    case permission(String)
    /// A plan to approve or send back.
    case planReview(String)

    /// The wait in a line, for rows and tooltips: a question reads differently from a permission
    /// request, so the user knows whether to answer or to approve.
    var summary: String {
        switch self {
        case .input(let question): "Waiting for your answer: \(question)"
        case .permission(let tool): "Allow \(tool)?"
        case .planReview(let plan): "Review the plan: \(plan)"
        }
    }
}

extension SessionModel {
    /// The first thing this session, or a subagent under it, needs from the user; nil when nothing.
    var wait: SessionWait? {
        if let question = pendingQuestion {
            return .input(question.request.message)
        }
        if let toolCallID = state.pendingPermissions.first?.toolCallID {
            let call = state.items.lazy.compactMap { item -> ToolCallState? in
                if case .toolCall(let call) = item, call.id == toolCallID { call } else { nil }
            }.first
            let title = call?.title ?? "Run a tool"
            return call?.kind == .switchMode ? .planReview(title) : .permission(title)
        }
        return children.values.lazy.compactMap(\.wait).first
    }
}
