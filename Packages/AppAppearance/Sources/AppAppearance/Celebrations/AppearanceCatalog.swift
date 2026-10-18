import Foundation

/// Where a plugin's contributions come from, for checking their artwork.
public struct ContributionSource {
    public enum Location: Sendable {
        /// Compiled into Native: artwork names images in the app's asset catalog.
        case builtIn
        /// A `plugin.json` folder: artwork paths must stay inside it.
        case folder(URL)
    }

    public let pluginID: String
    public let location: Location
    /// Whether the app has a compiled image by this name.
    public var assetExists: (String) -> Bool
    /// The Home marks this build of Native can draw.
    public var homeMarks: Set<String>
    /// This build's version, for `minimumNativeVersion`; nil skips the check.
    public var nativeVersion: String?
    public var fileExists: (URL) -> Bool
    /// Where each downloadable pack stands, for Native's own sets.
    public var packState: (String) -> IconPackState

    public init(
        pluginID: String, location: Location, assetExists: @escaping (String) -> Bool = { _ in false },
        homeMarks: Set<String> = [], nativeVersion: String? = nil,
        fileExists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) },
        packState: @escaping (String) -> IconPackState = { _ in .notDownloaded }
    ) {
        self.pluginID = pluginID
        self.location = location
        self.assetExists = assetExists
        self.homeMarks = homeMarks
        self.nativeVersion = nativeVersion
        self.fileExists = fileExists
        self.packState = packState
    }
}

/// The icon sets and celebrations of the enabled plugins, validated one by one: a contribution
/// with a problem is listed in `problems` and left out, and nothing else is affected.
public struct AppearanceCatalog: Hashable, Sendable {
    /// One plugin's contributions, in load order.
    public struct Plugin {
        public let source: ContributionSource
        public let iconSets: IconSetContributions
        public let celebrations: CelebrationContributions

        public init(source: ContributionSource, iconSets: IconSetContributions, celebrations: CelebrationContributions) {
            self.source = source
            self.iconSets = iconSets
            self.celebrations = celebrations
        }
    }

    public private(set) var iconSets: [IconSet] = []
    /// In catalogue order: plugins in load order, each plugin's in manifest order.
    public private(set) var celebrations: [CelebrationEvent] = []
    public private(set) var problems: [ContributionProblem] = []

    public init() {}

    /// Every icon set first, so a celebration can use one from another plugin.
    public init(_ plugins: [Plugin]) {
        for plugin in plugins {
            Self.collect(plugin.iconSets, from: plugin.source, into: &iconSets, problems: &problems) { set, taken in
                try Self.validate(set, from: plugin.source, taken: taken)
            }
        }
        let iconSets = iconSets
        for plugin in plugins {
            Self.collect(plugin.celebrations, from: plugin.source, into: &celebrations, problems: &problems) {
                celebration, taken in
                try Self.validate(celebration, from: plugin.source, taken: taken, iconSets: iconSets)
            }
        }
    }

    public func celebration(_ id: CelebrationID) -> CelebrationEvent? {
        celebrations.first { $0.id == id }
    }

    public func iconSet(_ id: IconSetID) -> IconSet? {
        iconSets.first { $0.id == id }
    }

    /// Icon sets offered as plain app icon themes: those no celebration uses, with icons ready.
    public var themes: [IconSet] {
        let used = Set(celebrations.compactMap(\.contribution.iconSet))
        return iconSets.filter { !used.contains($0.id) && $0.appIcon.isReady }
    }

    // MARK: - Validation

    private struct Failure: Error {
        let message: String

        init(_ message: String) {
            self.message = message
        }
    }

    /// Validates each entry on its own, so one problem only costs that entry. `validate` sees what's
    /// been accepted so far, to catch duplicate ids.
    private static func collect<Element: AppearanceContribution, Valid>(
        _ list: ContributionList<Element>, from source: ContributionSource, into accepted: inout [Valid],
        problems: inout [ContributionProblem], _ validate: (Element, [Valid]) throws -> Valid
    ) {
        problems += list.malformed.map { problem in
            var problem = problem
            problem.pluginID = source.pluginID
            return problem
        }
        for element in list.valid {
            do {
                accepted.append(try validate(element, accepted))
            } catch {
                problems.append(
                    ContributionProblem(
                        kind: Element.kind, index: nil, id: element.rawID,
                        message: (error as? Failure)?.message ?? "\(error)", pluginID: source.pluginID))
            }
        }
    }

    private static func validate(_ contribution: IconSetContribution, from source: ContributionSource, taken: [IconSet])
        throws -> IconSet
    {
        try checkIdentity(contribution.id.rawValue, from: source)
        if taken.contains(where: { $0.id == contribution.id }) {
            throw Failure("Another icon set already uses the id \"\(contribution.id)\".")
        }
        if contribution.name.fallback.trimmingCharacters(in: .whitespaces).isEmpty {
            throw Failure("The name is empty.")
        }
        let (appIcon, icons) = try iconStatus(contribution.icons, from: source)
        let (homeStatus, home) = homeStatus(contribution, marks: source.homeMarks)
        let thumbnail = try contribution.thumbnail.flatMap { pair -> AppIconImagePair? in
            let light = try image(pair.light, from: source)
            let dark = try image(pair.dark, from: source)
            return exists(light, in: source) && exists(dark, in: source) ? AppIconImagePair(light: light, dark: dark) : nil
        }
        return IconSet(
            contribution: contribution, pluginID: source.pluginID, appIcon: appIcon, icons: icons,
            homeStatus: homeStatus, home: home, thumbnail: thumbnail)
    }

    private static func validate(
        _ contribution: CelebrationContribution, from source: ContributionSource, taken: [CelebrationEvent],
        iconSets: [IconSet]
    ) throws -> CelebrationEvent {
        try checkIdentity(contribution.id.rawValue, from: source)
        if taken.contains(where: { $0.id == contribution.id }) {
            throw Failure("Another celebration already uses the id \"\(contribution.id)\".")
        }
        if contribution.title.fallback.trimmingCharacters(in: .whitespaces).isEmpty {
            throw Failure("The title is empty.")
        }
        try checkCompatibility(contribution.compatibility, nativeVersion: source.nativeVersion)
        try checkWindows(contribution.display)
        return CelebrationEvent(
            contribution: contribution, pluginID: source.pluginID, order: taken.count,
            iconSet: contribution.iconSet.flatMap { id in iconSets.first { $0.id == id } })
    }

    private static func checkIdentity(_ id: String, from source: ContributionSource) throws {
        let isWellFormed =
            id.contains(".") && id.first != "." && id.last != "."
            && id.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "." || $0 == "-") }
        guard isWellFormed else {
            throw Failure("The id should be namespaced lowercase words, like \"\(source.pluginID).diwali\".")
        }
        if case .folder = source.location, !id.hasPrefix(source.pluginID + ".") {
            throw Failure("The id should start with the plugin's id: \"\(source.pluginID).\".")
        }
    }

    private static func checkCompatibility(_ compatibility: CelebrationCompatibility, nativeVersion: String?) throws {
        if compatibility.manifestVersion > CelebrationCompatibility.supportedManifestVersion {
            throw Failure("It needs a newer version of Native (celebrations format \(compatibility.manifestVersion)).")
        }
        if let minimum = compatibility.minimumNativeVersion, let nativeVersion,
            nativeVersion.compare(minimum, options: .numeric) == .orderedAscending
        {
            throw Failure("It needs Native \(minimum) or later.")
        }
    }

    private static func checkWindows(_ display: CelebrationDisplay) throws {
        var seen: Set<CelebrationWindow.ID> = [.core]
        let reach = 0...CelebrationWindow.maximumReach
        for window in display.windows {
            guard seen.insert(window.id).inserted else {
                throw Failure("Two display windows use the id \"\(window.id.rawValue)\".")
            }
            guard reach.contains(window.daysBefore), reach.contains(window.daysAfter) else {
                throw Failure("The \"\(window.id.rawValue)\" window can reach 0 to \(reach.upperBound) days either side.")
            }
        }
        guard seen.contains(display.defaultWindow) else {
            throw Failure("The default window \"\(display.defaultWindow.rawValue)\" isn't one of its windows.")
        }
    }

    /// Bad references (a path outside the plugin's folder) reject the set; missing files only keep its
    /// icon from applying, and say what's missing.
    private static func iconStatus(_ icons: IconSetIcons?, from source: ContributionSource) throws
        -> (AppearanceSurfaceStatus, [AppIconVariant: AppIconImagePair])
    {
        switch icons {
        case nil: return (.notOffered, [:])
        case .forthcoming: return (.forthcoming, [:])
        case .pack(let edition):
            guard case .builtIn = source.location else {
                throw Failure("Only Native's own icon sets download as packs; ship the images in the plugin's folder.")
            }
            if case .ready(let icons) = source.packState(edition), icons.count == AppIconVariant.allCases.count {
                return (.ready, icons)
            }
            return (.downloadable(source.packState(edition)), [:])
        case .channels(let channels):
            var resolved: [AppIconVariant: AppIconImagePair] = [:]
            var missing: [String] = []
            for variant in AppIconVariant.allCases {
                guard let pair = channels[variant] else {
                    missing.append("\(variant.displayName) icons")
                    continue
                }
                let light = try image(pair.light, from: source)
                let dark = try image(pair.dark, from: source)
                if !exists(light, in: source) { missing.append("\(variant.displayName) light") }
                if !exists(dark, in: source) { missing.append("\(variant.displayName) dark") }
                resolved[variant] = AppIconImagePair(light: light, dark: dark)
            }
            guard missing.isEmpty else {
                return (.unavailable("Missing " + missing.formatted(.list(type: .and)) + "."), [:])
            }
            return (.ready, resolved)
        }
    }

    private static func image(_ reference: IconSetImageReference, from source: ContributionSource) throws
        -> AppIconImage
    {
        switch (reference, source.location) {
        case (.asset(let name), .builtIn):
            return .asset(name)
        case (.path(let path), .folder(let folder)):
            guard let url = contained(path, in: folder) else {
                throw Failure("The image \"\(path)\" isn't inside the plugin's folder.")
            }
            return .file(url)
        case (.asset(let name), .folder):
            throw Failure("\"\(name)\" names a compiled image; use a path inside the plugin's folder.")
        case (.path(let path), .builtIn):
            throw Failure("Built-in artwork \"\(path)\" should name a compiled image.")
        }
    }

    private static func exists(_ image: AppIconImage, in source: ContributionSource) -> Bool {
        switch image {
        case .asset(let name): source.assetExists(name)
        case .file(let url): source.fileExists(url)
        }
    }

    /// The file `path` names inside `folder`, or nil when it's absolute or escapes it (`..`, a symlink
    /// out of the folder).
    static func contained(_ path: String, in folder: URL) -> URL? {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~") else { return nil }
        let root = resolvingSymlinks(folder)
        let url = resolvingSymlinks(root.appending(path: path))
        let rootPath = root.path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return url.path(percentEncoded: false).hasPrefix(prefix) ? url : nil
    }

    /// Symlinks only resolve along a path that exists, so a missing file's folder is resolved and the
    /// rest appended: a link to outside the plugin is caught even before its target file exists.
    private static func resolvingSymlinks(_ url: URL) -> URL {
        var existing = url.standardizedFileURL
        var missing: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path(percentEncoded: false)),
            existing.pathComponents.count > 1
        {
            missing.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        return missing.reduce(existing.resolvingSymlinksInPath()) { $0.appending(path: $1) }
    }

    /// A mark this build can't draw falls back to the palette's two-tone emblem when there is one.
    private static func homeStatus(_ contribution: IconSetContribution, marks: Set<String>)
        -> (AppearanceSurfaceStatus, HomeLook?)
    {
        if let mark = contribution.homeMark, marks.contains(mark) { return (.ready, .mark(mark)) }
        if let palette = contribution.palette, palette.isTwoTone { return (.ready, .palette(palette)) }
        if contribution.homeMark != nil {
            return (.unavailable("This version of Native can't draw its Home edition."), nil)
        }
        return (.notOffered, nil)
    }
}
