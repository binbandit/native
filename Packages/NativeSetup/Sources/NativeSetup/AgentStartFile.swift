import Foundation

/// The file a failed start names, read and changed only at the user's request. Reads are limited
/// to small text files; a change keeps the original beside it and leaves its permissions and
/// symbolic links as they were.
public enum AgentStartFile {
    /// Settings files are a few kilobytes; anything far larger isn't one to show or edit.
    static let maximumSize = 256 * 1024

    /// Where the original goes before a fix-it changes the file.
    public static func backupPath(for path: String) -> String {
        path + ".native-backup"
    }

    /// The file's text, or nil when it's missing, not a regular file, too large or not UTF-8.
    public static func read(_ path: String) -> String? {
        let url = URL(filePath: path).resolvingSymlinksInPath()
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
            values.isRegularFile == true, (values.fileSize ?? .max) <= maximumSize,
            let data = try? Data(contentsOf: url)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Applies `fixIt` to the file the diagnostic names, after copying the original to
    /// `backupPath(for:)`. Returns where the original was kept.
    @discardableResult
    public static func apply(_ fixIt: AgentStartFixIt, at diagnostic: AgentStartDiagnostic) throws(Failure) -> String {
        let url = URL(filePath: diagnostic.path).resolvingSymlinksInPath()
        guard let contents = read(url.path) else { throw .unreadable(diagnostic.fileName) }
        guard let fixed = fixIt.apply(to: contents, at: diagnostic) else { throw .changed(diagnostic.fileName) }
        let backup = URL(filePath: backupPath(for: url.path))
        let fileManager = FileManager.default
        do {
            let permissions = try fileManager.attributesOfItem(atPath: url.path)[.posixPermissions]
            if fileManager.fileExists(atPath: backup.path) { try fileManager.removeItem(at: backup) }
            try fileManager.copyItem(at: url, to: backup)
            try Data(fixed.utf8).write(to: url, options: .atomic)
            if let permissions {
                try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
            }
        } catch {
            throw .notWritten(diagnostic.fileName, error.localizedDescription)
        }
        return backup.path
    }

    public enum Failure: Error, Equatable, LocalizedError {
        case unreadable(String)
        /// The line no longer holds the value the agent rejected.
        case changed(String)
        case notWritten(String, String)

        public var errorDescription: String? {
            switch self {
            case .unreadable(let file): "Native couldn't read \(file), so nothing was changed."
            case .changed(let file):
                "\(file) changed since the agent read it, so nothing was changed. Retry to read it again."
            case .notWritten(let file, let reason): "Couldn't change \(file): \(reason)"
            }
        }
    }
}
