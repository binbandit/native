import Foundation

/// An audio file the user added. Kept as a bookmark so it survives being moved or renamed, with the
/// path as a fallback; the file itself stays where the user keeps it.
nonisolated struct CustomSound: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var bookmark: Data?
    var path: String

    init(url: URL) {
        id = UUID()
        name = url.deletingPathExtension().lastPathComponent
        bookmark = try? url.bookmarkData()
        path = url.path(percentEncoded: false)
    }

    /// Where the file is now, if it still exists.
    var url: URL? {
        var isStale = false
        if let bookmark, let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) {
            return url
        }
        let url = URL(filePath: path)
        return FileManager.default.isReadableFile(atPath: path) ? url : nil
    }

    var option: SoundOption? {
        url.map { SoundOption(id: .custom(id), title: name, source: .file($0)) }
    }
}
