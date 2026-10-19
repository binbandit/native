import Foundation

/// A project's top-level folder as the detectors read it: its entries listed once, small files read
/// on demand. Detection only looks at the root (and a project file's own folder, for Xcode), so it
/// stays cheap on any size of repo.
struct ProjectFolder {
    let url: URL
    /// The root's entry names.
    let entries: Set<String>

    /// Files bigger than this aren't read: a manifest never is, and a huge generated file isn't
    /// worth parsing for suggestions.
    static let maxFileSize = 1 << 20

    init(_ url: URL) {
        self.url = url
        entries = Set((try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))) ?? [])
    }

    func has(_ name: String) -> Bool {
        entries.contains(name)
    }

    /// The first of `names` the root has.
    func first(of names: [String]) -> String? {
        names.first(where: has)
    }

    func data(_ relativePath: String) -> Data? {
        let file = url.appending(path: relativePath)
        guard
            let size = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
            size.isRegularFile == true, (size.fileSize ?? 0) <= Self.maxFileSize
        else { return nil }
        return try? Data(contentsOf: file)
    }

    func text(_ relativePath: String) -> String? {
        data(relativePath).map { String(decoding: $0, as: UTF8.self) }
    }

    func isDirectory(_ relativePath: String) -> Bool {
        var isDirectory: ObjCBool = false
        let path = url.appending(path: relativePath).path(percentEncoded: false)
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// The names in a subfolder, or none.
    func entries(in relativePath: String) -> [String] {
        let path = url.appending(path: relativePath).path(percentEncoded: false)
        return ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).sorted()
    }
}
