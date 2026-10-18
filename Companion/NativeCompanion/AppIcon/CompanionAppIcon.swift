import UIKit

/// The app icon themes, matching the Mac's: the one picked in Settings sets the accent too
/// (`docs/decisions.md`, "Accent follows the app icon theme"). Each is a layered alternate icon,
/// `AppIcon-<theme>`, that `scripts/companion/app-icons.sh` builds from the icon work's documents.
enum CompanionAppIcon: String, CaseIterable, Identifiable, Codable {
    case original, cobalt, fern, ember, prism, arcade

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    /// The alternate icon's name; nil is the primary icon.
    var iconName: String? {
        self == .original ? nil : "AppIcon-\(rawValue)"
    }
}

/// The alternate icons this build carries, as its Info.plist lists them, and their images for
/// previews.
enum BundledAppIcons {
    static let names: Set<String> = {
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let alternates = icons?["CFBundleAlternateIcons"] as? [String: Any]
        return Set(alternates?.keys.map(\.self) ?? [])
    }()

    /// The icon's own artwork, for a picker row; nil is the primary icon.
    static func image(_ name: String?) -> UIImage? {
        UIImage(named: name ?? "AppIcon")
    }
}
