import UserNotifications

/// Shows `NativeNotification`s in the system's notification center, with their actions, and reports
/// what the user does with them. Silent: Native's sounds play through the Sounds feature, so custom
/// sounds and the volume setting always apply.
///
/// It's the center's delegate, so it must exist before launch finishes: clicking one of its
/// notifications can be what launches Native.
final class UserNotificationPoster: NSObject, NativeNotificationPosting {
    var onResponse: ((NativeNotificationResponse) -> Void)?

    private let center = UNUserNotificationCenter.current()
    private static let payloadKey = "native.notification"

    override init() {
        super.init()
        center.delegate = self
        center.setNotificationCategories(Set(Self.actionSets.map(Self.category(for:))))
    }

    func post(_ notification: NativeNotification) async {
        guard let payload = try? JSONEncoder().encode(notification) else { return }
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.subtitle = notification.subtitle ?? ""
        content.body = notification.body
        content.categoryIdentifier = Self.categoryID(for: notification.actions)
        content.threadIdentifier = notification.session ?? notification.agent
        content.userInfo = [Self.payloadKey: String(decoding: payload, as: UTF8.self)]
        guard (try? await center.requestAuthorization(options: [.alert, .badge])) == true else { return }
        try? await center.add(UNNotificationRequest(identifier: notification.id, content: content, trigger: nil))
    }

    // MARK: - Categories

    /// Every set of actions a notification can carry; the center wants them registered up front.
    private static let actionSets: [[NativeNotification.Action]] = [
        [], [.allow, .reject], [.reply], [.resumeAtReset, .snoozeUntilReset], [.snoozeUntilReset],
    ]

    private static func categoryID(for actions: [NativeNotification.Action]) -> String {
        (["native"] + actions.map(\.rawValue)).joined(separator: ".")
    }

    private static func category(for actions: [NativeNotification.Action]) -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: categoryID(for: actions), actions: actions.map(action(for:)), intentIdentifiers: [])
    }

    private static func action(for action: NativeNotification.Action) -> UNNotificationAction {
        switch action {
        case .allow:
            UNNotificationAction(identifier: action.rawValue, title: "Allow")
        case .reject:
            UNNotificationAction(identifier: action.rawValue, title: "Reject", options: .destructive)
        case .reply:
            UNTextInputNotificationAction(
                identifier: action.rawValue, title: "Reply", textInputButtonTitle: "Send", textInputPlaceholder: "Your answer")
        case .resumeAtReset:
            UNNotificationAction(identifier: action.rawValue, title: "Resume at Reset")
        case .snoozeUntilReset:
            UNNotificationAction(identifier: action.rawValue, title: "Snooze Until Reset")
        }
    }
}

extension UserNotificationPoster: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Posted only when the user isn't looking at what it's about, so it shows even in Native.
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let text = response.notification.request.content.userInfo[Self.payloadKey] as? String,
            let notification = try? JSONDecoder().decode(NativeNotification.self, from: Data(text.utf8))
        else { return }
        let reply = (response as? UNTextInputNotificationResponse)?.userText
        let action = NativeNotification.Action(rawValue: response.actionIdentifier)
        let answer = NativeNotificationResponse(notification: notification, action: action, replyText: reply)
        await MainActor.run { onResponse?(answer) }
    }
}
