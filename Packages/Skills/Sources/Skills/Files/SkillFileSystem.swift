import Foundation

/// The files of the machine whose skills are listed and installed: this Mac today, a remote
/// Native Host later. Paths are that machine's. Everything the package reads or writes goes
/// through this, so a host can serve it.
public protocol SkillFileSystem: Sendable {
    /// Entry names in a directory, hidden ones included; nil when it isn't a readable directory.
    func contentsOfDirectory(atPath path: String) -> [String]?
    func contents(atPath path: String) -> Data?
    /// What's at `path`, following symbolic links; nil when nothing is.
    func itemKind(atPath path: String) -> SkillItemKind?
    func isSymbolicLink(atPath path: String) -> Bool
    /// `path` with every symbolic link resolved, to tell copies from links to the same folder.
    func resolvingSymlinks(atPath path: String) -> String
    func isExecutable(atPath path: String) -> Bool
    func size(atPath path: String) -> Int?

    func createDirectory(atPath path: String) throws
    func write(_ data: Data, toPath path: String, executable: Bool) throws
    /// Copies a file or a folder and everything in it; `destination` must not exist.
    func copyItem(atPath source: String, toPath destination: String) throws
    /// Moves a file, folder or symbolic link itself (never what a link points to).
    func moveItem(atPath source: String, toPath destination: String) throws
    func removeItem(atPath path: String) throws
    /// A new, empty directory for staging, which the caller removes.
    func makeTemporaryDirectory() throws -> String
}

public enum SkillItemKind: Sendable {
    case file
    case directory
}

extension SkillFileSystem {
    func exists(_ path: String) -> Bool {
        itemKind(atPath: path) != nil || isSymbolicLink(atPath: path)
    }
}

/// This Mac's files.
public struct LocalSkillFiles: SkillFileSystem {
    public init() {}

    private var manager: FileManager { .default }

    public func contentsOfDirectory(atPath path: String) -> [String]? {
        guard itemKind(atPath: path) == .directory else { return nil }
        return try? manager.contentsOfDirectory(atPath: path)
    }

    public func contents(atPath path: String) -> Data? {
        manager.contents(atPath: path)
    }

    public func itemKind(atPath path: String) -> SkillItemKind? {
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
        return isDirectory.boolValue ? .directory : .file
    }

    public func isSymbolicLink(atPath path: String) -> Bool {
        (try? manager.destinationOfSymbolicLink(atPath: path)) != nil
    }

    public func resolvingSymlinks(atPath path: String) -> String {
        URL(filePath: path).resolvingSymlinksInPath().path(percentEncoded: false)
    }

    public func isExecutable(atPath path: String) -> Bool {
        itemKind(atPath: path) == .file && manager.isExecutableFile(atPath: path)
    }

    public func size(atPath path: String) -> Int? {
        (try? manager.attributesOfItem(atPath: path)[.size] as? NSNumber)?.intValue
    }

    public func createDirectory(atPath path: String) throws {
        try manager.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    public func write(_ data: Data, toPath path: String, executable: Bool) throws {
        try createDirectory(atPath: URL(filePath: path).deletingLastPathComponent().path(percentEncoded: false))
        try data.write(to: URL(filePath: path), options: .atomic)
        if executable {
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        }
    }

    public func copyItem(atPath source: String, toPath destination: String) throws {
        try createDirectory(atPath: URL(filePath: destination).deletingLastPathComponent().path(percentEncoded: false))
        try manager.copyItem(atPath: source, toPath: destination)
    }

    public func moveItem(atPath source: String, toPath destination: String) throws {
        try createDirectory(atPath: URL(filePath: destination).deletingLastPathComponent().path(percentEncoded: false))
        try manager.moveItem(atPath: source, toPath: destination)
    }

    public func removeItem(atPath path: String) throws {
        try manager.removeItem(atPath: path)
    }

    public func makeTemporaryDirectory() throws -> String {
        let url = manager.temporaryDirectory.appending(path: "native-skills-\(UUID().uuidString)")
        try manager.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path(percentEncoded: false)
    }
}

/// Paths as this package compares and shows them.
public enum SkillPaths {
    /// `url`'s path without a trailing slash, the key projects are stored under.
    public static func key(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    static func join(_ base: String, _ components: String...) -> String {
        components.reduce(base) { path, component in
            path.hasSuffix("/") ? path + component : path + "/" + component
        }
    }

    /// Whether `path` is `folder` or inside it.
    static func path(_ path: String, isInside folder: String) -> Bool {
        path == folder || path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }

    /// `~/…` for paths in `home`, for showing.
    public static func abbreviated(_ path: String, home: String) -> String {
        Self.path(path, isInside: home) ? "~" + path.dropFirst(home.count) : path
    }
}
