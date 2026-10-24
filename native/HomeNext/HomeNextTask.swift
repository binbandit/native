import ACP
import Foundation
import TaskList

/// A Home row. Actions retain the exact session and request they were drawn from.
struct HomeNextTask: Identifiable {
    let id: SessionKey
    let title: String
    let agent: String
    let status: TaskStatus
    let ask: String
    let date: Date?
    var host: String?
    var request: HomeNextRequest?
    var session: SessionModel?
    var finishedAt: Date?
    var diff: String?

    var requestID: HomeNextRequest.ID? { request?.id }

    var kind: HomeAskOrder.Kind {
        if let request { return request.kind }
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
