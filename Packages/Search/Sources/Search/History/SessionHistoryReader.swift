import Foundation

/// Reads an agent's own record of its past sessions, so search covers sessions Native never
/// loaded. Each agent's plugin provides one for its format; agents without one are indexed as
/// Native loads their sessions.
///
/// Readers only read. They run on the host (the machine with the agent's files), at low priority,
/// and must never write to or lock the agent's files.
public protocol SessionHistoryReader: Sendable {
    /// Every session file the agent has, found without parsing any of them.
    func sources() -> [HistorySource]
    /// One file's session, or nil when it holds no conversation (only metadata, say).
    func read(_ source: HistorySource) throws -> HistorySession?
}

/// One file of an agent's history.
public struct HistorySource: Hashable, Sendable {
    public var url: URL
    public var size: Int
    public var modifiedAt: Date

    public init(url: URL, size: Int, modifiedAt: Date) {
        self.url = url
        self.size = size
        self.modifiedAt = modifiedAt
    }

    /// Changes whenever the file does.
    public var stamp: SearchSourceStamp {
        SearchSourceStamp(path: url.path(percentEncoded: false), stamp: "\(size)-\(modifiedAt.timeIntervalSince1970)")
    }

    /// The `.jsonl` files under `root`, at most `maxDepth` levels down (1 is `root` itself), newest first.
    public static func jsonlFiles(under root: URL, maxDepth: Int = .max) -> [HistorySource] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isDirectoryKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return [] }
        var sources: [HistorySource] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isDirectory == true, enumerator.level >= maxDepth {
                enumerator.skipDescendants()
            }
            guard url.pathExtension == "jsonl", values.isRegularFile == true else { continue }
            sources.append(
                HistorySource(url: url, size: values.fileSize ?? 0, modifiedAt: values.contentModificationDate ?? .distantPast))
        }
        return sources.sorted { $0.modifiedAt > $1.modifiedAt }
    }
}

/// A session as an agent's history recorded it.
public struct HistorySession: Sendable {
    /// The agent's id for the session, the same one ACP uses.
    public var sessionID: String
    public var title: String?
    public var cwd: String
    public var createdAt: Date?
    public var updatedAt: Date?
    public var documents: [SearchDocument]

    public init(
        sessionID: String, title: String?, cwd: String, createdAt: Date?, updatedAt: Date?, documents: [SearchDocument]
    ) {
        self.sessionID = sessionID
        self.title = title
        self.cwd = cwd
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.documents = documents
    }
}
