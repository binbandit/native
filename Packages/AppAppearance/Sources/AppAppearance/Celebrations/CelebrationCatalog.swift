import Foundation

/// Where a plugin's celebrations come from, for checking their artwork.
public struct CelebrationSource {
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

    public init(
        pluginID: String, location: Location, assetExists: @escaping (String) -> Bool = { _ in false },
        homeMarks: Set<String> = [], nativeVersion: String? = nil,
        fileExists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    ) {
        self.pluginID = pluginID
        self.location = location
        self.assetExists = assetExists
        self.homeMarks = homeMarks
        self.nativeVersion = nativeVersion
        self.fileExists = fileExists
    }
}

/// Every celebration from the loaded plugins, validated one by one: a contribution with a problem is
/// listed in `problems` and left out, and nothing else is affected.
public struct CelebrationCatalog: Hashable, Sendable {
    /// In catalogue order: plugins in load order, each plugin's in manifest order.
    public private(set) var events: [CelebrationEvent] = []
    public private(set) var problems: [CelebrationProblem] = []

    public init() {}

    public func event(_ id: CelebrationID) -> CelebrationEvent? {
        events.first { $0.id == id }
    }

    /// Only the celebrations of the given plugins, as when some are switched off. Problems stay, so
    /// the catalogue can still explain them.
    public func limited(toPlugins pluginIDs: Set<String>) -> CelebrationCatalog {
        var catalog = self
        catalog.events = events.filter { pluginIDs.contains($0.pluginID) }
        return catalog
    }

    public mutating func add(_ contributions: CelebrationContributions, from source: CelebrationSource) {
        problems += contributions.malformed.map { problem in
            var problem = problem
            problem.pluginID = source.pluginID
            return problem
        }
        for contribution in contributions.valid {
            do {
                events.append(try Self.validate(contribution, from: source, order: events.count, taken: events))
            } catch let failure as Failure {
                problems.append(
                    CelebrationProblem(
                        index: nil, id: contribution.id.rawValue, message: failure.message, pluginID: source.pluginID))
            } catch {
                problems.append(
                    CelebrationProblem(
                        index: nil, id: contribution.id.rawValue, message: "\(error)", pluginID: source.pluginID))
            }
        }
    }

    // MARK: - Validation

    private struct Failure: Error {
        let message: String
    }

    private static func validate(
        _ contribution: CelebrationContribution, from source: CelebrationSource, order: Int,
        taken: [CelebrationEvent]
    ) throws -> CelebrationEvent {
        try checkIdentity(contribution, from: source, taken: taken)
        try checkCompatibility(contribution.compatibility, nativeVersion: source.nativeVersion)
        try checkWindows(contribution.display)
        let (appIcon, icons) = try iconStatus(contribution.artwork.appIcon, from: source)
        return CelebrationEvent(
            contribution: contribution, pluginID: source.pluginID, order: order, appIcon: appIcon,
            home: homeStatus(contribution.artwork.home, marks: source.homeMarks), icons: icons)
    }

    private static func checkIdentity(
        _ contribution: CelebrationContribution, from source: CelebrationSource, taken: [CelebrationEvent]
    ) throws {
        let id = contribution.id.rawValue
        let isWellFormed =
            id.contains(".") && id.first != "." && id.last != "."
            && id.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "." || $0 == "-") }
        guard isWellFormed else {
            throw Failure(message: "The id should be namespaced lowercase words, like \"\(source.pluginID).diwali\".")
        }
        if case .folder = source.location, !id.hasPrefix(source.pluginID + ".") {
            throw Failure(message: "The id should start with the plugin's id: \"\(source.pluginID).\".")
        }
        if taken.contains(where: { $0.id == contribution.id }) {
            throw Failure(message: "Another celebration already uses the id \"\(id)\".")
        }
        if contribution.title.fallback.trimmingCharacters(in: .whitespaces).isEmpty {
            throw Failure(message: "The title is empty.")
        }
    }

    private static func checkCompatibility(_ compatibility: CelebrationCompatibility, nativeVersion: String?) throws {
        if compatibility.manifestVersion > CelebrationCompatibility.supportedManifestVersion {
            throw Failure(message: "It needs a newer version of Native (celebrations format \(compatibility.manifestVersion)).")
        }
        if let minimum = compatibility.minimumNativeVersion, let nativeVersion,
            nativeVersion.compare(minimum, options: .numeric) == .orderedAscending
        {
            throw Failure(message: "It needs Native \(minimum) or later.")
        }
    }

    private static func checkWindows(_ display: CelebrationDisplay) throws {
        var seen: Set<CelebrationWindow.ID> = [.core]
        for window in display.windows {
            guard seen.insert(window.id).inserted else {
                throw Failure(message: "Two display windows use the id \"\(window.id.rawValue)\".")
            }
            let reach = 0...CelebrationWindow.maximumReach
            guard reach.contains(window.daysBefore), reach.contains(window.daysAfter) else {
                throw Failure(
                    message:
                        "The \"\(window.id.rawValue)\" window can reach 0 to \(CelebrationWindow.maximumReach) days either side."
                )
            }
        }
        guard seen.contains(display.defaultWindow) else {
            throw Failure(message: "The default window \"\(display.defaultWindow.rawValue)\" isn't one of its windows.")
        }
    }

    /// Bad references (a path outside the plugin's folder) reject the contribution; missing files only
    /// keep the icon from applying, and say what's missing.
    private static func iconStatus(
        _ artwork: CelebrationIconArtwork?, from source: CelebrationSource
    ) throws -> (CelebrationEvent.SurfaceStatus, [AppIconVariant: AppIconImagePair]) {
        switch artwork {
        case nil: return (.notOffered, [:])
        case .forthcoming: return (.forthcoming, [:])
        case .channels(let channels):
            var icons: [AppIconVariant: AppIconImagePair] = [:]
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
                icons[variant] = AppIconImagePair(light: light, dark: dark)
            }
            guard missing.isEmpty else {
                return (.unavailable("Missing " + missing.formatted(.list(type: .and)) + "."), [:])
            }
            return (.ready, icons)
        }
    }

    private static func image(_ reference: CelebrationImageReference, from source: CelebrationSource) throws
        -> AppIconImage
    {
        switch (reference, source.location) {
        case (.asset(let name), .builtIn):
            return .asset(name)
        case (.path(let path), .folder(let folder)):
            guard let url = contained(path, in: folder) else {
                throw Failure(message: "The artwork path \"\(path)\" isn't inside the plugin's folder.")
            }
            return .file(url)
        case (.asset(let name), .folder):
            throw Failure(message: "\"\(name)\" names a compiled image; use a path inside the plugin's folder.")
        case (.path(let path), .builtIn):
            throw Failure(message: "Built-in artwork \"\(path)\" should name a compiled image.")
        }
    }

    private static func exists(_ image: AppIconImage, in source: CelebrationSource) -> Bool {
        switch image {
        case .asset(let name): source.assetExists(name)
        case .file(let url): source.fileExists(url)
        }
    }

    /// The file `path` names inside `folder`, or nil when it's absolute or escapes it (`..`, a symlink
    /// out of the folder).
    static func contained(_ path: String, in folder: URL) -> URL? {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~") else { return nil }
        let root = folder.standardizedFileURL.resolvingSymlinksInPath()
        let url = root.appending(path: path).standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = root.path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return url.path(percentEncoded: false).hasPrefix(prefix) ? url : nil
    }

    private static func homeStatus(_ artwork: CelebrationHomeArtwork?, marks: Set<String>)
        -> CelebrationEvent.SurfaceStatus
    {
        switch artwork {
        case nil: .notOffered
        case .forthcoming: .forthcoming
        case .mark(let mark) where marks.contains(mark): .ready
        case .mark: .unavailable("This version of Native can't draw its Home edition.")
        }
    }
}
