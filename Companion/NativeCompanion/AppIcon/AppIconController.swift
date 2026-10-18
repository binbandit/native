import AppAppearance
import Foundation
import Observation
import UIKit

/// Which icon the home screen shows, and switching to it. In order: a celebration on its dates,
/// then the active host's icon, then the icon picked in Settings; "Keep Icon Fixed" leaves only the
/// last. iOS changes the icon only while the app is active and shows an alert every time, so a change
/// that falls due on its own (a celebration starting or ending) waits for the app to become active,
/// and each one is tried once. A change the person makes applies at once.
@Observable
final class AppIconController {
    /// Why the icon is what it is, for Settings to say.
    enum Reason: Equatable {
        case picked
        case celebration(title: String, through: CivilDate)
        case host(name: String)
    }

    struct Target: Equatable {
        /// Nil is the primary icon.
        let name: String?
        let reason: Reason
    }

    /// The icon picked in Settings, which also sets the accent.
    var theme: CompanionAppIcon {
        didSet {
            defaults.set(theme.rawValue, forKey: Self.themeKey)
            applyNow()
        }
    }

    /// Celebrations and hosts never change the icon.
    var keepsIconFixed: Bool {
        didSet {
            defaults.set(keepsIconFixed, forKey: Self.fixedKey)
            applyNow()
        }
    }

    /// Why the last switch didn't happen, until the next one does.
    private(set) var problem: String?
    /// The icon showing now; nil is the primary icon.
    private(set) var current: String?

    let celebrations: CompanionCelebrations

    @ObservationIgnored private let store: CompanionStore
    @ObservationIgnored private let defaults: UserDefaults
    private static let themeKey = "iconTheme"
    private static let fixedKey = "iconKeepsFixed"
    /// The last icon tried on its own, so a due change is attempted once, not at every activation.
    private static let attemptedKey = "iconAttempted"

    init(store: CompanionStore, celebrations: CompanionCelebrations, defaults: UserDefaults = .standard) {
        self.store = store
        self.celebrations = celebrations
        self.defaults = defaults
        theme = defaults.string(forKey: Self.themeKey).flatMap(CompanionAppIcon.init(rawValue:)) ?? .original
        keepsIconFixed = defaults.bool(forKey: Self.fixedKey)
        current = UIApplication.shared.alternateIconName
    }

    func target(on day: CivilDate = .today) -> Target {
        if !keepsIconFixed {
            if let active = celebrations.active(on: day) {
                return Target(
                    name: active.iconName,
                    reason: .celebration(
                        title: active.event.contribution.title.resolved(), through: active.occurrence.display.last))
            }
            if let host = store.activeHost, let icon = host.preferences.appIcon {
                return Target(name: icon.iconName, reason: .host(name: host.name))
            }
        }
        return Target(name: theme.iconName, reason: .picked)
    }

    /// The app became active, or a day began: switch if something new fell due.
    func applyDue() {
        let wanted = target().name
        current = UIApplication.shared.alternateIconName
        guard wanted != current else { return }
        let attempted = defaults.string(forKey: Self.attemptedKey)
        guard attempted != Self.key(wanted) else { return }
        defaults.set(Self.key(wanted), forKey: Self.attemptedKey)
        switchIcon(to: wanted)
    }

    /// The person changed something that decides the icon (a theme, a host's icon, the active
    /// host, a celebration): switch now, alert and all.
    func applyNow() {
        let wanted = target().name
        defaults.set(Self.key(wanted), forKey: Self.attemptedKey)
        guard UIApplication.shared.applicationState == .active,
            wanted != UIApplication.shared.alternateIconName
        else { return }
        switchIcon(to: wanted)
    }

    private func switchIcon(to name: String?) {
        guard UIApplication.shared.supportsAlternateIcons else {
            problem = "This device can't change app icons."
            return
        }
        Task {
            do {
                try await UIApplication.shared.setAlternateIconName(name)
                problem = nil
            } catch {
                problem = "Couldn't change the icon: \(error.localizedDescription)"
            }
            current = UIApplication.shared.alternateIconName
        }
    }

    private static func key(_ name: String?) -> String {
        name ?? "primary"
    }
}

extension CivilDate {
    static var today: CivilDate { CivilDate(.now, in: .current) }
}
