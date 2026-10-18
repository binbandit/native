import AppAppearance
import Foundation

/// One choice in the app icon picker: a built-in theme, or a plain icon set from an enabled plugin.
/// The picker draws options as data, so a plugin's icon set appears there with nothing else to add.
struct AppIconOption: Identifiable, Hashable {
    /// Stored as the user's choice, so stable: "cobalt" for a built-in theme (the format before icon
    /// sets), "set:acme.sunset" for a plugin's icon set.
    struct ID: RawRepresentable, Hashable, Sendable {
        let rawValue: String

        init(rawValue: String) {
            self.rawValue = rawValue
        }

        static func theme(_ theme: AppIconTheme) -> ID {
            ID(rawValue: theme.rawValue)
        }

        static func iconSet(_ id: IconSetID) -> ID {
            ID(rawValue: setPrefix + id.rawValue)
        }

        var theme: AppIconTheme? { AppIconTheme(rawValue: rawValue) }

        var iconSet: IconSetID? {
            rawValue.hasPrefix(Self.setPrefix) ? IconSetID(String(rawValue.dropFirst(Self.setPrefix.count))) : nil
        }

        private static let setPrefix = "set:"
    }

    enum Preview: Hashable {
        /// The compiled icon from the app bundle (Original), with the system's Clear and Tinted looks.
        case bundle
        case image(AppIconImagePair)
    }

    let id: ID
    let title: String
    let preview: Preview
    /// Nil for built-in themes; the plugin's name for an icon set.
    let pluginName: String?
    /// Why it can't be the real app icon here, shown under its tile; nil when it can. Home still
    /// dresses up with it in the app.
    let limitation: String?

    /// Every built-in theme, then the plain icon sets, previewed for this build's channel.
    static func all(iconSets: [IconSet], pluginNames: [String: String], variant: AppIconVariant) -> [AppIconOption] {
        let themes = AppIconTheme.allCases.map { theme in
            guard theme != .original else {
                return AppIconOption(id: .theme(theme), title: theme.title, preview: .bundle, pluginName: nil, limitation: nil)
            }
            let icons = theme.images
            return AppIconOption(
                id: .theme(theme), title: theme.title, preview: .image(icons), pluginName: nil,
                limitation: limitation(icons))
        }
        let sets = iconSets.compactMap { set -> AppIconOption? in
            guard let icons = set.icons[variant] else { return nil }
            return AppIconOption(
                id: .iconSet(set.id), title: set.name.resolved(), preview: .image(icons),
                pluginName: pluginNames[set.pluginID], limitation: limitation(icons))
        }
        return themes + sets
    }

    private static func limitation(_ icons: AppIconImagePair) -> String? {
        PlatformAppIcon.canApply(icons.light) ? nil : "Mac only"
    }
}
