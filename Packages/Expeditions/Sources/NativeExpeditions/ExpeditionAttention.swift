import Foundation
import NativeAutomation

/// Something an expedition needs from the user, derived from its state so it can't go stale: the
/// overview's cards, the sidebar's count and the notifications all read these.
public nonisolated struct ExpeditionAttention: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        /// The lead's route waits for review.
        case routeReady
        /// The lead revised the legs ahead in a way that changes approved work.
        case routeChange
        /// The base couldn't be made.
        case baseFailed(String)
        /// A seat stopped short: blocked on a question, failed, cancelled, cut off by a quit, or
        /// stopped by a limit. Its status says which, and its reason why.
        case stopped(CrewSlot, WorkflowStepStatus)
        /// The expedition's budget is spent.
        case budgetReached(String)
        case pullRequestFailed(String)
    }

    public let kind: Kind
    public let since: Date

    public var id: String {
        switch kind {
        case .routeReady: "route"
        case .routeChange: "route-change"
        case .baseFailed: "base"
        case .stopped(let slot, _): "slot-\(slot)"
        case .budgetReached: "budget"
        case .pullRequestFailed: "pull-request"
        }
    }

    /// A provider limit that resolves itself at its reset, rather than a question for the user.
    public var isLimit: Bool {
        if case .stopped(_, .limited) = kind { return true }
        return false
    }

    /// Answered by approving or turning something down, so ⌘Y and ⌘⇧⌫ apply.
    public var isApproval: Bool {
        kind == .routeReady || kind == .routeChange
    }
}

extension Expedition {
    /// Everything waiting on the user, oldest first.
    public var attention: [ExpeditionAttention] {
        guard !isStopped, endedAt == nil else { return [] }
        var items: [ExpeditionAttention] = []
        if let baseError {
            items.append(ExpeditionAttention(kind: .baseFailed(baseError), since: updatedAt))
        }
        if approvedAt == nil, lead.status == .succeeded, route != nil {
            items.append(ExpeditionAttention(kind: .routeReady, since: lead.waitingSince ?? updatedAt))
        }
        if pendingRouteChange != nil {
            items.append(ExpeditionAttention(kind: .routeChange, since: lead.waitingSince ?? updatedAt))
        }
        if lead.status.isStopped {
            items.append(ExpeditionAttention(kind: .stopped(.lead, lead.status), since: lead.waitingSince ?? updatedAt))
        }
        for run in assignments where run.status.isStopped {
            items.append(ExpeditionAttention(kind: .stopped(.assignment(run.id), run.status), since: run.waitingSince ?? run.endedAt ?? updatedAt))
        }
        for run in checkpoints where run.status.isStopped {
            items.append(ExpeditionAttention(kind: .stopped(.checkpoint(run.leg), run.status), since: run.waitingSince ?? run.endedAt ?? updatedAt))
        }
        if approvedAt != nil, !legsSettled, let reason = exhaustedBudget(at: updatedAt) {
            items.append(ExpeditionAttention(kind: .budgetReached(reason), since: updatedAt))
        }
        if let pullRequestError {
            items.append(ExpeditionAttention(kind: .pullRequestFailed(pullRequestError), since: updatedAt))
        }
        return items.sorted { $0.since < $1.since }
    }
}
