import Foundation

/// Reads a project's files for its icon. Locally that's the file system; a client of a remote host
/// gets an implementation that asks the host, so icon detection never assumes the files are here.
protocol ProjectFileReading: Sendable {
    /// The bytes of the file at `path` (relative to `root`), or nil when it's missing, unreadable or
    /// larger than `limit`.
    func data(atPath path: String, in root: URL, limit: Int) async -> Data?
    /// The names in the directory at `path` (relative to `root`), or nil when it isn't one.
    func entries(atPath path: String, in root: URL) async -> [String]?
}

/// The project's files on this machine.
nonisolated struct LocalProjectFiles: ProjectFileReading {
    func data(atPath path: String, in root: URL, limit: Int) async -> Data? {
        let url = root.appending(path: path)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
            size.isRegularFile == true, (size.fileSize ?? .max) <= limit
        else { return nil }
        return try? Data(contentsOf: url)
    }

    func entries(atPath path: String, in root: URL) async -> [String]? {
        let url = path.isEmpty ? root : root.appending(path: path)
        return try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))
    }
}
