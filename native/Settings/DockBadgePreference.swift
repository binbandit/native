import Foundation
import Observation

/// What the Dock badge counts. One shared, observable instance, so the badge follows the Settings
/// row the moment it changes.
@MainActor
@Observable
final class DockBadgePreference {
    enum Mode: String, CaseIterable, Identifiable, Sendable {
        case needsYou
        case needsYouOrUnread
        case off

        var id: Self { self }

        var title: String {
            switch self {
            case .needsYou: "Needs you"
            case .needsYouOrUnread: "Needs you or unread"
            case .off: "Off"
            }
        }
    }

    static let shared = DockBadgePreference()

    var mode: Mode {
        didSet { defaults.set(mode.rawValue, forKey: Self.storageKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private static let storageKey = "dockBadge"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: Self.storageKey).flatMap(Mode.init(rawValue:)) ?? .needsYou
    }
}
