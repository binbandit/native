import Foundation
import NativeAutomation

extension Expedition {
    /// What an attention item says, the same on its card and in its notification.
    public func headline(for item: ExpeditionAttention) -> String {
        switch item.kind {
        case .routeReady:
            "\(crew.lead.name) proposed a route"
        case .routeChange:
            "\(crew.lead.name) wants to change the legs ahead"
        case .baseFailed:
            "The crew's workspace couldn't be made"
        case .budgetReached:
            "The budget is spent"
        case .pullRequestFailed:
            "The pull request didn't open"
        case .stopped(let slot, let status):
            switch status {
            case .blocked: "\(agent(of: slot).name) needs you on \(name(of: slot))"
            case .limited: "\(agent(of: slot).name) hit a limit on \(name(of: slot))"
            case .interrupted: "\(name(of: slot)) was cut off"
            case .cancelled: "\(name(of: slot)) was stopped"
            default: "\(name(of: slot)) stopped short"
            }
        }
    }

    public func detail(for item: ExpeditionAttention) -> String? {
        switch item.kind {
        case .routeReady:
            route.map {
                "\($0.legs.count) \($0.legs.count == 1 ? "leg" : "legs"), \($0.assignments.count) \($0.assignments.count == 1 ? "assignment" : "assignments"). Review it, then approve it or ask for changes."
            }
        case .routeChange:
            "It rewrites work you approved, so it waits for you. The crew holds until you decide."
        case .baseFailed(let message), .pullRequestFailed(let message):
            message
        case .budgetReached(let reason):
            "\(reason). Turns in flight finished; nothing new goes out until you add to it, wrap up or stop."
        case .stopped(_, let status):
            status == .interrupted
                ? "Native quit while it was working. Resume tells the agent its turn was cut off." : status.reason
        }
    }
}
