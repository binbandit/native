import Foundation

/// Successful folder opens on this device. Paths from paired hosts never enter this history.
public struct FolderHistory: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Identifiable, Sendable {
        public var id: URL { url }
        public let url: URL
        public let bookmark: Data?

        public init(url: URL, bookmark: Data? = nil) {
            self.url = url
            self.bookmark = bookmark
        }
    }

    public private(set) var entries: [Entry] = []
    public static let limit = 6

    public init() {}

    /// Call only after validation succeeds, with a canonical URL supplied by the platform adapter.
    public mutating func opened(_ url: URL, bookmark: Data? = nil) {
        guard url.isFileURL else { return }
        entries.removeAll { $0.url.path == url.path }
        entries.insert(Entry(url: url, bookmark: bookmark), at: 0)
        entries = Array(entries.prefix(Self.limit))
    }

    public mutating func clear() { entries.removeAll() }
}
