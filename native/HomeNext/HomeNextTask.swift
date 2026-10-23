import ACP
import Foundation
import TaskList

/// A Home row. Approval actions retain the exact session and request they were drawn from.
struct HomeNextTask: Identifiable {
    let id: SessionKey
    let title: String
    let agent: String
    let status: TaskStatus
    let ask: String
    let date: Date?
    var host: String?
    var approval: ToolCallState?
    var approvalSession: SessionModel?
    var finishedAt: Date?
    var diff: String?

    var kind: HomeAskOrder.Kind {
        if approval != nil { return .approval }
        return switch status {
        case .needsInput: .question
        case .needsPermission: .approval
        case .needsPlanReview: .plan
        case .limited: .limit
        default: .failure
        }
    }

    var needsYou: Bool { status.needsAttention || status == .failed || status == .limited }
}
