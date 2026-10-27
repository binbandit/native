import Foundation

/// The file a failed start names, read and changed only at the user's request. The path comes from
/// the agent's output, so it authorizes nothing: only a settings file the agent's plugin declares
/// (`settingsPaths`) is opened, compared after symbolic links resolve. Anything else stays a
/// location without contents. A change keeps the original beside it and leaves its permissions and
/// symbolic links as they were.
public enum AgentStartFile {
    /// Settings files are a few kilobytes; anything far larger isn't one to show or edit.
    static let maximumSize = 256 * 1024

    /// Where the original goes before a fix-it changes the file.
    public static func backupPath(for path: String) -> String {
        path + ".native-backup"
    }

    /// The files a plugin's settings patterns name: `~/…` in `home`, `$NAME/…` in that variable's
    /// folder (none while it's unset), and anything else in the task's `folder`. Each file once, as
    /// first named, though two patterns or a link reach it.
    public static func settingsPaths(
        _ patterns: [String], home: String, environment: [String: String], folder: String?
    ) -> [String] {
        var seen: Set<String> = []
        return patterns.compactMap { pattern -> String? in
            if pattern.hasPrefix("~/") { return home + pattern.dropFirst() }
            if pattern.hasPrefix("$") {
                let name = pattern.dropFirst().prefix { $0 != "/" }
                guard let value = environment[String(name)], value.hasPrefix("/") else { return nil }
                return value + pattern.dropFirst(name.count + 1)
            }
            if pattern.hasPrefix("/") { return pattern }
            return folder.map { URL(filePath: $0).appending(path: pattern).path }
        }
        .filter { seen.insert(URL(filePath: $0).standardizedFileURL.resolvingSymlinksInPath().path).inserted }
    }

    /// Whether Native may open `path` to show or change it: it's one of the `allowed` settings
    /// files, once both resolve their links, and a link keeps the settings file's kind
    /// (`config.toml` may lead to a dotfiles copy, never to `.git-credentials`).
    public static func mayRead(_ path: String, allowed: [String]) -> Bool {
        guard path.hasPrefix("/") else { return false }
        let resolved = URL(filePath: path).standardizedFileURL.resolvingSymlinksInPath()
        return allowed.contains { declared in
            let settings = URL(filePath: declared).standardizedFileURL
            return settings.resolvingSymlinksInPath().path == resolved.path
                && !settings.pathExtension.isEmpty && settings.pathExtension == resolved.pathExtension
        }
    }

    /// The file's text, or nil when Native may not open it (`mayRead`), or it's missing, not a
    /// regular file, too large or not UTF-8.
    public static func read(_ path: String, allowed: [String]) -> String? {
        guard mayRead(path, allowed: allowed) else { return nil }
        let url = URL(filePath: path).resolvingSymlinksInPath()
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
            values.isRegularFile == true, (values.fileSize ?? .max) <= maximumSize,
            let data = try? Data(contentsOf: url)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// A fix-it written to a settings file, for taking it back.
    public struct Change: Equatable, Sendable {
        /// The file written, after symbolic links: the target, never the link.
        public let path: String
        /// Where the original was kept.
        public let backup: String
        /// The name the user knows the file by (the link's, for a link).
        public let fileName: String
        /// The text before the fix. Kept here as well as in `backup`, which the next fix of the same
        /// file replaces, so fixes taken back newest first each restore their own original.
        let original: String
        /// The text the fix wrote, so taking it back never discards a later edit.
        let written: String
    }

    /// Applies `fixIt` to the file the diagnostic names, when `allowed` has it, after copying the
    /// original to `backupPath(for:)`.
    @discardableResult
    public static func apply(
        _ fixIt: AgentStartFixIt, at diagnostic: AgentStartDiagnostic, allowed: [String]
    ) throws(Failure) -> Change {
        let url = URL(filePath: diagnostic.path).resolvingSymlinksInPath()
        guard let contents = read(diagnostic.path, allowed: allowed) else { throw .unreadable(diagnostic.fileName) }
        guard let fixed = fixIt.apply(to: contents, at: diagnostic) else { throw .changed(diagnostic.fileName) }
        let backup = URL(filePath: backupPath(for: url.path))
        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: backup.path) { try fileManager.removeItem(at: backup) }
            try fileManager.copyItem(at: url, to: backup)
            try write(fixed, to: url)
        } catch {
            throw .notWritten(diagnostic.fileName, error.localizedDescription)
        }
        return Change(
            path: url.path, backup: backup.path, fileName: diagnostic.fileName, original: contents, written: fixed)
    }

    /// Puts the original back over `change` the same way the fix wrote: to the link's target, keeping
    /// its permissions. Only while the file still holds what the fix wrote. The copy beside the file
    /// goes too, when it's this fix's.
    public static func restore(_ change: Change) throws(Failure) {
        let url = URL(filePath: change.path)
        let backup = URL(filePath: change.backup)
        let keptOriginal =
            (try? Data(contentsOf: backup)).flatMap { String(data: $0, encoding: .utf8) } == change.original
        guard let current = try? Data(contentsOf: url), String(data: current, encoding: .utf8) == change.written else {
            throw .changedSinceFix(change.fileName, backup: keptOriginal ? backup.lastPathComponent : nil)
        }
        do {
            try write(change.original, to: url)
        } catch {
            throw .notWritten(change.fileName, error.localizedDescription)
        }
        if keptOriginal { try? FileManager.default.removeItem(at: backup) }
    }

    /// Replaces the file's text atomically, keeping its permissions (an atomic write makes a new file).
    private static func write(_ text: String, to url: URL) throws {
        let fileManager = FileManager.default
        let permissions = try fileManager.attributesOfItem(atPath: url.path)[.posixPermissions]
        try Data(text.utf8).write(to: url, options: .atomic)
        if let permissions {
            try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
    }

    public enum Failure: Error, Equatable, LocalizedError {
        case unreadable(String)
        /// The line no longer holds the value the agent rejected.
        case changed(String)
        case notWritten(String, String)
        /// Taking a fix back found the file edited since; with the copy of the original, if it's there.
        case changedSinceFix(String, backup: String?)

        public var errorDescription: String? {
            switch self {
            case .unreadable(let file): "Native couldn't read \(file), so nothing was changed."
            case .changed(let file):
                "\(file) changed since the agent read it, so nothing was changed. Retry to read it again."
            case .notWritten(let file, let reason): "Couldn't change \(file): \(reason)"
            case .changedSinceFix(let file, let backup?):
                "\(file) changed after the fix, so Native left it as it is. "
                    + "The original is still beside it, in \(backup)."
            case .changedSinceFix(let file, nil): "\(file) changed after the fix, so Native left it as it is."
            }
        }
    }
}
