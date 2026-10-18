import Foundation
import Observation

/// What the Dock badge counts. One shared, observable instance, so the badge follows the Settings
/// row the moment it changes.
@MainActor
@Observable
final class DockBadgePreference {
    enum Mode: String, CaseIterable, Identifiable, Sendable {
        case needsYou
        case needsYouAndUnread
        case off

        var id: Self { self }

        var title: String {
            switch self {
            case .needsYou: "Tasks that need you"
            case .needsYouAndUnread: "Needs you and unread"
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
