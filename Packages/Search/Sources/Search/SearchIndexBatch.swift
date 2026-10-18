import Foundation

/// One session to index: what's known about it and its transcript (or, when appending, the part
/// of it that's new).
public struct SearchIndexEntry: Sendable {
    public var session: SearchSessionRecord
    public var documents: [SearchDocument]

    public init(session: SearchSessionRecord, documents: [SearchDocument]) {
        self.session = session
        self.documents = documents
    }
}

/// Writes applied in one transaction.
public struct SearchIndexBatch: Sendable {
    /// Sessions whose documents replace whatever was indexed for them.
    public var replacing: [SearchIndexEntry] = []
    /// Sessions whose new documents go after the ones already indexed.
    public var appending: [SearchIndexEntry] = []
    /// How far history files have been read.
    public var checkpoints: [HistoryCheckpoint] = []

    public init(
        replacing: [SearchIndexEntry] = [], appending: [SearchIndexEntry] = [], checkpoints: [HistoryCheckpoint] = []
    ) {
        self.replacing = replacing
        self.appending = appending
        self.checkpoints = checkpoints
    }

    public var isEmpty: Bool {
        replacing.isEmpty && appending.isEmpty && checkpoints.isEmpty
    }

    /// Sessions and documents in the batch, and the bytes of their text, for keeping batches small.
    public var size: (sessions: Int, documents: Int, bytes: Int) {
        let entries = replacing + appending
        let documents = entries.flatMap(\.documents)
        return (entries.count, documents.count, documents.reduce(0) { $0 + $1.text.utf8.count })
    }
}

/// How far one history file has been read: its size and modification time when it was, and the
/// byte offset just past the last complete line indexed. An unchanged file is skipped; a file that
/// only grew is read from the offset; anything else is read again from the start.
public struct HistoryCheckpoint: Hashable, Sendable {
    public var path: String
    public var size: Int
    public var modifiedAt: Date
    public var offset: Int
    /// The session the file holds; nil when it holds no conversation.
    public var session: SearchSessionKey?
    public var cwd: String?
    /// Whether that session is still in the index (a retention policy may have dropped it).
    public var isSessionIndexed: Bool

    public init(
        path: String, size: Int, modifiedAt: Date, offset: Int, session: SearchSessionKey?, cwd: String?,
        isSessionIndexed: Bool = true
    ) {
        self.path = path
        self.size = size
        self.modifiedAt = modifiedAt
        self.offset = offset
        self.session = session
        self.cwd = cwd
        self.isSessionIndexed = isSessionIndexed
    }

    /// Whether `source` is exactly the file this checkpoint read.
    public func matches(_ source: HistorySource) -> Bool {
        size == source.size && modifiedAt.timeIntervalSince1970 == source.modifiedAt.timeIntervalSince1970
    }

    /// Where to continue reading `source` from, when it only grew since: nil means from the start.
    public func resume(for source: HistorySource) -> HistoryResume? {
        guard let session, let cwd, isSessionIndexed, offset > 0, source.size >= offset else { return nil }
        return HistoryResume(offset: offset, sessionID: session.session, cwd: cwd)
    }
}

/// Where a reader continues an appended file, and what it already knows from the part it read.
public struct HistoryResume: Hashable, Sendable {
    public var offset: Int
    public var sessionID: String
    public var cwd: String

    public init(offset: Int, sessionID: String, cwd: String) {
        self.offset = offset
        self.sessionID = sessionID
        self.cwd = cwd
    }
}

/// What one read of a history file found: the session (or only its new part, when resumed) and
/// the offset to continue from next time.
public struct HistoryRead: Sendable {
    public var session: HistorySession?
    public var offset: Int

    public init(session: HistorySession?, offset: Int) {
        self.session = session
        self.offset = offset
    }
}
