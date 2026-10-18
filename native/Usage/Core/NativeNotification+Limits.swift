import Foundation

// Usage-limit notifications, worded by `LimitStatus` like every other surface.
extension NativeNotification {
    init(_ alert: LimitAlert, now: Date) {
        switch alert {
        case .reached(let limit, let sessions):
            let status = limit.limitStatus()
            self.init(limit, kind: .limitReached, title: status.headline, body: Self.reachedBody(status, sessions, now: now))
            if let first = sessions.first {
                session = first.session.rawValue
                sessionTitle = first.title
            }
            actions = limit.resetsAt != nil && !sessions.isEmpty ? [.resumeAtReset, .snoozeUntilReset] : [.snoozeUntilReset]
        case .warning(let limit):
            let status = limit.limitStatus()
            let body = status.resetText(now: now).map { $0.sentenceCased + "." } ?? "Requests may stop soon."
            self.init(limit, kind: .limitWarning, title: status.headline, body: body)
            actions = [.snoozeUntilReset]
        case .availableAgain(let limit):
            self.init(
                limit, kind: .limitReset, title: "\(limit.agentName) is available again",
                body: "\(limit.limitStatus().availableAgainText). Nothing was sent while you were snoozed.")
            isAlwaysShown = true
        case .rescheduled(let limit, let ref, let date):
            self.init(
                id: "native.usage-limit.\(limit.agent.rawValue)", kind: .limitRescheduled, about: ref,
                title: limit.limitStatus().headline,
                body: "Hit the limit again. Native will resume \(ref.title.map { "“\($0)”" } ?? "the task") at \(DSFormat.time(date, now: now)).")
        case .resumeFailed(let ref):
            self.init(
                id: "native.usage-limit.\(ref.agent.rawValue).resume.\(ref.session.rawValue)", kind: .resumeFailed,
                about: ref, title: "Couldn’t resume \(ref.title.map { "“\($0)”" } ?? "a \(ref.agentName) task")",
                body: "\(ref.agentName) wasn’t available after the reset. Open the task to carry on.")
            isAlwaysShown = true
        }
    }

    /// One per provider: a newer status replaces the last instead of piling up.
    private init(_ limit: ProviderLimit, kind: Kind, title: String, body: String) {
        self.init(
            id: "native.usage-limit.\(limit.agent.rawValue)", kind: kind, agent: limit.agent.rawValue,
            agentName: limit.agentName, title: title, body: body)
    }

    private static func reachedBody(_ status: LimitStatus, _ sessions: [UsageSessionRef], now: Date) -> String {
        guard let reset = status.resetText(now: now) else {
            return status.message ?? "Native can’t tell when it resets."
        }
        let resets = reset.sentenceCased + "."
        switch sessions.count {
        case 0: return resets
        case 1: return "\(resets) \(sessions[0].title.map { "“\($0)”" } ?? "Your task") stopped and can pick up then."
        default: return "\(resets) \(sessions.count) tasks stopped and can pick up then."
        }
    }
}

extension String {
    fileprivate var sentenceCased: String {
        prefix(1).uppercased() + dropFirst()
    }
}
