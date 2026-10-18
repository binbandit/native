/// Whether one surface (the app icon, Home) of an icon set or celebration can be applied.
public enum AppearanceSurfaceStatus: Hashable, Sendable {
    case ready
    /// It doesn't change this surface.
    case notOffered
    /// Planned; the catalogue says the artwork is on its way.
    case forthcoming
    /// Declared but unusable, such as missing icon files; the reason is for the catalogue.
    case unavailable(String)
    /// Native's own artwork that downloads when chosen; until it's here the surface stays as it is.
    case downloadable(IconPackState)

    public var isReady: Bool { self == .ready }

    public var isDownloadable: Bool {
        if case .downloadable = self { return true }
        return false
    }
}

/// Where a downloadable icon pack stands on this device.
public enum IconPackState: Hashable, Sendable {
    case notDownloaded
    case downloading
    /// Why the last attempt failed, in the user's terms.
    case failed(String)
    /// This build can't download icons at all (no release to fetch from); said before anyone tries.
    case unavailable(String)
    case ready([AppIconVariant: AppIconImagePair])
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
    /// A small Regular icon for previews: the bundled thumbnail, or the stable icon itself.
    public let thumbnail: AppIconImagePair?

    public init(
        contribution: IconSetContribution, pluginID: String, appIcon: AppearanceSurfaceStatus,
        icons: [AppIconVariant: AppIconImagePair], homeStatus: AppearanceSurfaceStatus, home: HomeLook?,
        thumbnail: AppIconImagePair? = nil
    ) {
        self.contribution = contribution
        self.pluginID = pluginID
        self.appIcon = appIcon
        self.icons = icons
        self.homeStatus = homeStatus
        self.home = home
        self.thumbnail = thumbnail ?? icons[.stable]
    }

    public var id: IconSetID { contribution.id }
    public var name: LocalizedText { contribution.name }

    public func icon(for variant: AppIconVariant, isDark: Bool) -> AppIconImage? {
        icons[variant]?.image(isDark: isDark)
    }
}
