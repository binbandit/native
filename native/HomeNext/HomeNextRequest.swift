import ACP
import Foundation
import TaskList

/// The owning session and the exact request on screen, including requests from subagents.
struct HomeNextRequest {
    enum ID: Hashable {
        case permission(HomeNextApprovalID)
        case question(SessionKey, RequestID)
    }

    let session: SessionModel
    var call: ToolCallState?
    var question: SessionModel.PendingQuestion?

    var id: ID? {
        if let approval = HomeNextApprovalID(session: session, call: call) { return .permission(approval) }
        return question.map { .question(session.key, $0.id) }
    }

    var kind: HomeAskOrder.Kind {
        if let call { return call.kind == .switchMode ? .plan : .approval }
        return .question
    }

    var status: TaskStatus {
        switch kind {
        case .plan: .needsPlanReview
        case .question: .needsInput
        default: .needsPermission
        }
    }

    var summary: String {
        if let question { return question.request.message }
        guard let call else { return status.label }
        return call.kind == .switchMode ? "Review the plan: \(call.title)" : "Allow \(call.title)?"
    }

}
