import ACP
import AppKit
import UserNotifications

/// Delivers limit alerts as macOS notifications, with "Resume at Reset" and "Snooze Until Reset"
/// as actions. While Native is frontmost, the session's banner says it all, so only the alerts the
/// user asked for (the reset after a snooze) or can't otherwise see (a failed resume) still post.
///
/// It's the notification center's delegate, so it must exist before launch finishes: a click on
/// one of its notifications can be what launches Native.
final class UserNotificationAlerts: NSObject, LimitAlerting {
    var onAction: ((LimitAlertAction) -> Void)?

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        center.setNotificationCategories(Set(Category.allCases.map(\.category)))
    }

    func post(_ alert: LimitAlert) async {
        let content = UNMutableNotificationContent()
        let identifier: String
        let now = Date()
        switch alert {
        case .reached(let limit, let sessions):
            guard !NSApplication.shared.isActive else { return }
            identifier = Self.identifier(for: limit.agent)
            content.title = limit.headline
            content.body = Self.reachedBody(limit, sessions: sessions, now: now)
            content.categoryIdentifier = (limit.resetsAt != nil && !sessions.isEmpty ? Category.reached : .snoozable).rawValue
            content.userInfo = Payload(agent: limit.agent, target: sessions.first).userInfo
        case .warning(let limit):
            guard !NSApplication.shared.isActive else { return }
            identifier = Self.identifier(for: limit.agent)
            content.title = limit.headline
            content.body = limit.resetsAt.map { LimitWording.reset($0, now: now).capitalizedFirst + "." } ?? "Requests may stop soon."
            content.categoryIdentifier = Category.snoozable.rawValue
            content.userInfo = Payload(agent: limit.agent, target: nil).userInfo
        case .availableAgain(let limit):
            identifier = Self.identifier(for: limit.agent)
            content.title = "\(limit.agentName) is available again"
            content.body = "\(LimitWording.availableAgain(agentName: limit.agentName, window: limit.window)). Nothing was sent while you were snoozed."
            content.userInfo = Payload(agent: limit.agent, target: nil).userInfo
        case .resumeFailed(let target):
            identifier = "\(Self.identifier(for: target.agent)).resume.\(target.session.rawValue)"
            content.title = "Couldn’t resume \(target.title.map { "“\($0)”" } ?? "a \(target.agentName) session")"
            content.body = "\(target.agentName) wasn’t available after the reset. Open the session to carry on."
            content.userInfo = Payload(agent: target.agent, target: target).userInfo
        }
        content.sound = .default
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        // One notification per provider: a newer status replaces the last instead of piling up.
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    private static func identifier(for agent: AgentDefinition.ID) -> String {
        "native.usage-limit.\(agent.rawValue)"
    }

    private static func reachedBody(_ limit: ProviderLimit, sessions: [LimitTarget], now: Date) -> String {
        guard let resetsAt = limit.resetsAt else {
            return limit.message ?? "Native can’t tell when it resets."
        }
        let resets = LimitWording.reset(resetsAt, now: now).capitalizedFirst + "."
        switch sessions.count {
        case 0: return resets
        case 1: return "\(resets) \(sessions[0].title.map { "“\($0)”" } ?? "Your session") stopped and can pick up then."
        default: return "\(resets) \(sessions.count) sessions stopped and can pick up then."
        }
    }

    fileprivate func receive(_ payload: Payload, actionIdentifier: String) {
        switch actionIdentifier {
        case Action.resumeAtReset.rawValue:
            onAction?(.resumeAtReset(payload.agent))
        case Action.snoozeUntilReset.rawValue:
            onAction?(.snoozeUntilReset(payload.agent))
        case UNNotificationDefaultActionIdentifier:
            if let target = payload.target {
                onAction?(.show(target))
            }
        default:
            break
        }
    }
}

extension UserNotificationAlerts: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Other plugins' notifications keep the system's default: not shown while Native is frontmost.
        notification.request.identifier.hasPrefix("native.usage-limit.") ? [.banner, .sound] : []
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let payload = Payload(userInfo: response.notification.request.content.userInfo) else { return }
        let action = response.actionIdentifier
        await MainActor.run { receive(payload, actionIdentifier: action) }
    }
}

private enum Action: String {
    case resumeAtReset = "native.usage-limit.resume-at-reset"
    case snoozeUntilReset = "native.usage-limit.snooze-until-reset"
}

private enum Category: String, CaseIterable {
    case reached = "native.usage-limit.reached"
    case snoozable = "native.usage-limit.snoozable"

    var category: UNNotificationCategory {
        let resume = UNNotificationAction(identifier: Action.resumeAtReset.rawValue, title: "Resume at Reset")
        let snooze = UNNotificationAction(identifier: Action.snoozeUntilReset.rawValue, title: "Snooze Until Reset")
        let actions = switch self {
        case .reached: [resume, snooze]
        case .snoozable: [snooze]
        }
        return UNNotificationCategory(identifier: rawValue, actions: actions, intentIdentifiers: [])
    }
}

/// What a notification carries so its actions can find their provider and session again, even
/// after a relaunch.
private struct Payload: Sendable {
    let agent: AgentDefinition.ID
    let target: LimitTarget?

    init(agent: AgentDefinition.ID, target: LimitTarget?) {
        self.agent = agent
        self.target = target
    }

    nonisolated init?(userInfo: [AnyHashable: Any]) {
        guard let agent = userInfo["agent"] as? String else { return nil }
        self.agent = AgentDefinition.ID(rawValue: agent)
        if let session = userInfo["session"] as? String, let agentName = userInfo["agentName"] as? String {
            target = LimitTarget(agent: self.agent, agentName: agentName, session: SessionID(session), title: userInfo["title"] as? String)
        } else {
            target = nil
        }
    }

    var userInfo: [String: String] {
        var info = ["agent": agent.rawValue]
        if let target {
            info["session"] = target.session.rawValue
            info["agentName"] = target.agentName
            info["title"] = target.title
        }
        return info
    }
}

private extension String {
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
