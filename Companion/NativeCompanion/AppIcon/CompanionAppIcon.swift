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

/// The alternate icons this build carries, as its Info.plist lists them.
enum BundledAppIcons {
    static let names: Set<String> = {
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let alternates = icons?["CFBundleAlternateIcons"] as? [String: Any]
        return Set(alternates?.keys.map(\.self) ?? [])
    }()

    /// A small light and dark render of an icon for the pickers (`IconPreview-<name>`, made by
    /// `scripts/companion/app-icons.sh`): iOS can't load app icons themselves as images. Nil is
    /// the primary icon.
    static func previewName(_ iconName: String?) -> String? {
        let name = "IconPreview-" + (iconName.map { String($0.dropFirst("AppIcon-".count)) } ?? "original")
        return UIImage(named: name) == nil ? nil : name
    }
}
