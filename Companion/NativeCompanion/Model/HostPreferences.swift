import Foundation
import NativeHostProtocol

/// What the person chose for one host on this phone: its name, color and symbol (shown on every
/// row and notification from it), and which notifications it sends. Kept per host, so one host's
/// choices never touch another's.
struct HostPreferences: Codable, Hashable {
    /// Defaults to the machine's own name.
    var label: String?
    /// An accent palette id (`DSAccentPalette.all`), used for the host's mark and its screens.
    var themeID = "original"
    var symbol = "desktopcomputer"
    var notifiesAboutUpdates = true
    var notifiesAboutApprovals = true

    static let symbols = [
        "desktopcomputer", "laptopcomputer", "macmini", "server.rack", "cube", "circle.hexagongrid", "leaf", "flame",
        "bolt", "star",
    ]

    static func load(for hostID: HostID, defaults: UserDefaults = .standard) -> HostPreferences {
        guard let data = defaults.data(forKey: key(hostID)),
            let preferences = try? JSONDecoder().decode(HostPreferences.self, from: data)
        else { return HostPreferences() }
        return preferences
    }

    func save(for hostID: HostID, defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key(hostID))
    }

    static func remove(for hostID: HostID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(hostID))
    }

    private static func key(_ hostID: HostID) -> String {
        "host.\(hostID).preferences"
    }
}
