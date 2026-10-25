/// The kinds of place a copy can live. Only the file-backed ones can be approved as roots; the rest
/// are reached through their owner (preferences, Keychain, a paired host) or not at all.
public enum DataRootKind: String, CaseIterable, Codable, Sendable {
    /// `~/Library/Application Support/<bundle id>`, or the iPad container's.
    case appSupport
    /// The host's folder: `Application Support/Native`, `Native/Channels/<channel>`, or
    /// `$XDG_DATA_HOME/Native` on a portable host.
    case hostData
    /// `~/.native`, or the folder a setting moves part of it to.
    case nativeHome
    /// `~/Library/Caches/<bundle id>`.
    case caches
    /// The operating system's temporary folder.
    case temporary
    /// A git repository a project points at.
    case repository
    /// An agent's own configuration folder.
    case agentHome
    /// A folder the user picked (a clone folder, an export destination).
    case userChosen
    /// The app's preferences domain.
    case preferences
    case keychain
    case pairedHost
    case operatingSystem
    case customerManaged

    public var isFileBacked: Bool {
        switch self {
        case .appSupport, .hostData, .nativeHome, .caches, .temporary, .repository, .agentHome, .userChosen: true
        case .preferences, .keychain, .pairedHost, .operatingSystem, .customerManaged: false
        }
    }

    /// How documentation spells the root.
    public var label: String {
        switch self {
        case .appSupport: "AppSupport"
        case .hostData: "HostDir"
        case .nativeHome: "~/.native"
        case .caches: "Caches"
        case .temporary: "$TMPDIR"
        case .repository: "<repository>"
        case .agentHome: "<agent home>"
        case .userChosen: "<chosen folder>"
        case .preferences: "defaults"
        case .keychain: "Keychain"
        case .pairedHost: "<paired host>"
        case .operatingSystem: "OS"
        case .customerManaged: "customer"
        }
    }
}

/// One concrete root. Some kinds have several (each repository, each agent), told apart by an
/// instance id the caller chooses.
public struct DataRoot: Hashable, Codable, Sendable {
    public var kind: DataRootKind
    public var instance: String?

    public init(_ kind: DataRootKind, instance: String? = nil) {
        self.kind = kind
        self.instance = instance
    }
}

/// Where a store's copy lives, as the inventory declares it. File templates use `<name>` for one
/// caller-supplied part, which may sit inside a component (`registry-<hash>.json`).
public enum DataLocation: Equatable, Sendable {
    case file(DataRootKind, [String])
    case defaults([String])
    case keychain(service: String)
    /// Refs and config sections inside a repository, which git may pack into one file.
    case gitRefs([String])
    /// Kept by an owner outside Native, described rather than addressed.
    case elsewhere(DataRootKind, String)
    /// Not known yet (a store whose schema hasn't landed).
    case undetermined

    /// Whether `path` lies inside this file location. Only file templates match, and only paths in
    /// a root of the same kind.
    func contains(_ path: DataRelativePath) -> Bool {
        guard case .file(let kind, let template) = self, path.root.kind == kind,
            path.components.count >= template.count
        else { return false }
        return zip(template, path.components).allSatisfy { DataPathPattern.matches($0, $1) }
    }
}

/// A path the caller reports for a copy: components under one of its roots, never an absolute
/// path, so the planner never takes a path string as permission.
public struct DataRelativePath: Hashable, Codable, Sendable, CustomStringConvertible {
    public var root: DataRoot
    public var components: [String]

    public init(_ root: DataRoot, _ components: [String]) {
        self.root = root
        self.components = components
    }

    /// Each component names one entry: no empty or dot components and no separators, so the path
    /// can't climb out of its root however it's joined.
    public var isConfined: Bool {
        !components.isEmpty && components.allSatisfy(DataPathPattern.isPlainComponent)
    }

    public var description: String {
        ([root.instance.map { "\(root.kind.label)[\($0)]" } ?? root.kind.label] + components)
            .joined(separator: "/")
    }
}

/// The roots a caller lets the planner name, with their absolute paths. The planner resolves a
/// copy's path only against these, lexically, and never looks at the disk.
public struct DataApprovedRoots: Equatable, Sendable {
    private let paths: [DataRoot: String]
    /// Roots offered with a path that isn't absolute and plain, or that aren't file-backed.
    public let rejected: Set<DataRoot>

    public init(_ roots: [DataRoot: String] = [:]) {
        var paths: [DataRoot: String] = [:]
        var rejected: Set<DataRoot> = []
        for (root, offered) in roots {
            // A folder path may end in a separator; nothing else about it is normalized.
            let path = offered.count > 1 && offered.hasSuffix("/") ? String(offered.dropLast()) : offered
            let components = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
            let isPlain =
                path.hasPrefix("/") && !components.isEmpty
                && components.allSatisfy { DataPathPattern.isPlainComponent(String($0)) }
            if root.kind.isFileBacked && isPlain { paths[root] = path } else { rejected.insert(root) }
        }
        self.paths = paths
        self.rejected = rejected
    }

    /// The absolute path a confined relative path names, when its root is approved.
    public func resolve(_ path: DataRelativePath) -> String? {
        guard path.isConfined, let base = paths[path.root] else { return nil }
        return ([base] + path.components).joined(separator: "/")
    }
}

enum DataPathPattern {
    static func isPlainComponent(_ component: String) -> Bool {
        !component.isEmpty && component != "." && component != ".."
            && !component.contains(where: { $0 == "/" || $0 == "\\" || $0 == "\0" })
    }

    /// `<name>` stands for one or more characters of a single component.
    static func matches(_ pattern: String, _ component: String) -> Bool {
        guard isPlainComponent(component) else { return false }
        // The literal text around each placeholder: "registry-<hash>.json" is ["registry-", ".json"].
        var literals: [Substring] = []
        var rest = Substring(pattern)
        while let open = rest.firstIndex(of: "<"), let close = rest[open...].firstIndex(of: ">") {
            literals.append(rest[..<open])
            rest = rest[rest.index(after: close)...]
        }
        literals.append(rest)
        guard literals.count > 1 else { return pattern == component }
        let text = Substring(component)
        guard let first = literals.first, text.hasPrefix(first) else { return false }
        return matchesAfterPlaceholder(literals.dropFirst(), text.dropFirst(first.count))
    }

    /// `text` starts with a placeholder, which takes at least one character, followed by `literals`
    /// in order with a placeholder between each.
    private static func matchesAfterPlaceholder(_ literals: ArraySlice<Substring>, _ text: Substring) -> Bool {
        guard let literal = literals.first else { return false }
        guard literals.count > 1 else { return text.count > literal.count && text.hasSuffix(literal) }
        var start = text.dropFirst()
        while !start.isEmpty {
            if start.hasPrefix(literal), matchesAfterPlaceholder(literals.dropFirst(), start.dropFirst(literal.count)) {
                return true
            }
            start = start.dropFirst()
        }
        return false
    }
}
