import Foundation
import Observation

/// The user's Dock badge choice, observable so its shared Settings row and wiring apply changes at once.
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
