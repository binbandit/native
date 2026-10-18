import Foundation

/// What the user wants to hear about, as Settings › Notifications stores it.
struct NotificationPreferences {
    static let longWorkKey = "notifications.longWork"
    static let longWorkSecondsKey = "notifications.longWorkSeconds"
    static let needsYouKey = "notifications.needsYou"
    static let usageLimitsKey = "notifications.usageLimits"
    static let defaultLongWorkSeconds = 60

    var defaults: UserDefaults = .standard

    var notifiesLongWork: Bool { defaults.object(forKey: Self.longWorkKey) as? Bool ?? true }
    var longWorkThreshold: TimeInterval {
        TimeInterval(defaults.object(forKey: Self.longWorkSecondsKey) as? Int ?? Self.defaultLongWorkSeconds)
    }
    var notifiesNeedsYou: Bool { defaults.object(forKey: Self.needsYouKey) as? Bool ?? true }
    var notifiesUsageLimits: Bool { defaults.object(forKey: Self.usageLimitsKey) as? Bool ?? true }
}
