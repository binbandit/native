/// Whether one surface (the app icon, Home) of an icon set or celebration can be applied.
public enum AppearanceSurfaceStatus: Hashable, Sendable {
    case ready
    /// It doesn't change this surface.
    case notOffered
    /// Planned; the catalogue says the artwork is on its way.
    case forthcoming
    /// Declared but unusable, such as missing icon files; the reason is for the catalogue.
    case unavailable(String)

    public var isReady: Bool { self == .ready }
}

/// How the Home page's emblem dresses up.
public enum HomeLook: Hashable, Sendable {
    /// One of the design system's marks, by id.
    case mark(String)
    /// The plain emblem with its two links in the palette's first two colors.
    case palette(IconSetPalette)
}

/// An icon set that passed validation, with its images checked and resolved.
public struct IconSet: Hashable, Sendable, Identifiable {
    public let contribution: IconSetContribution
    public let pluginID: String
    public let appIcon: AppearanceSurfaceStatus
    /// Each channel's icons, when `appIcon` is ready.
    public let icons: [AppIconVariant: AppIconImagePair]
    public let homeStatus: AppearanceSurfaceStatus
    /// What Home draws, when `homeStatus` is ready.
    public let home: HomeLook?

    public init(
        contribution: IconSetContribution, pluginID: String, appIcon: AppearanceSurfaceStatus,
        icons: [AppIconVariant: AppIconImagePair], homeStatus: AppearanceSurfaceStatus, home: HomeLook?
    ) {
        self.contribution = contribution
        self.pluginID = pluginID
        self.appIcon = appIcon
        self.icons = icons
        self.homeStatus = homeStatus
        self.home = home
    }

    public var id: IconSetID { contribution.id }
    public var name: LocalizedText { contribution.name }

    public func icon(for variant: AppIconVariant, isDark: Bool) -> AppIconImage? {
        icons[variant]?.image(isDark: isDark)
    }
}
