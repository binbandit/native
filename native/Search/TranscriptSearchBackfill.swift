import Foundation
import Search
import os

/// One pass over the agents' own history: reads every session file that's new or changed since it
/// was last indexed, newest first, and indexes it in batches. Resumable by construction: each
/// batch records its files' stamps, so a pass that's cancelled, crashes or pauses picks up where
/// it stopped. It runs at utility priority (background priority's I/O throttling can stall it
/// outright on a busy Mac) and waits while the Mac is on battery or in Low Power Mode.
nonisolated struct TranscriptSearchBackfill: Sendable {
    nonisolated struct Reader: Sendable {
        let agent: String
        let reader: any SessionHistoryReader
    }

    /// What Native knows about a session it lists, which wins over what the history says.
    nonisolated struct Known: Sendable {
        let title: String?
        let project: String
        let isArchived: Bool
    }

    let index: SearchIndex
    let readers: [Reader]
    let known: [SearchSessionKey: Known]
    /// Native's project folders, for placing sessions it doesn't list.
    let projects: [String]
    let excluded: [String]
    /// Sessions last active before this are kept out of the index (an organization's retention
    /// policy), and dropped from it first.
    let retainedSince: Date?

    /// Sessions per write, and documents per write: big enough to be quick, small enough that a
    /// search never waits on one.
    private static let batchSessions = 25
    private static let batchDocuments = 2_000
    private static let logger = Logger(subsystem: "Native", category: "Search")

    @concurrent func run(report: @escaping @Sendable (TranscriptSearchIndexing) async -> Void) async {
        if let retainedSince {
            try? await index.removeSessions(updatedBefore: retainedSince)
        }
        let stamps = (try? await index.sourceStamps()) ?? [:]
        let changed = readers.flatMap { reader in
            reader.reader.sources()
                .filter { stamps[$0.stamp.path] != $0.stamp.stamp && $0.modifiedAt >= retainedSince ?? .distantPast }
                .map { (reader, $0) }
        }
        // Files never indexed first, newest first. Changed ones (an active session's log, often
        // the biggest file there is) wait until the rest are searchable.
        let work = changed.sorted { lhs, rhs in
            let lhsSeen = stamps[lhs.1.stamp.path] != nil, rhsSeen = stamps[rhs.1.stamp.path] != nil
            return lhsSeen == rhsSeen ? lhs.1.modifiedAt > rhs.1.modifiedAt : !lhsSeen
        }
        guard !work.isEmpty else {
            await report(.idle)
            return
        }
        await report(.indexing(done: 0, total: work.count))
        var batch: [SearchIndexEntry] = []
        var documents = 0
        for (offset, (reader, source)) in work.enumerated() {
            if Task.isCancelled { break }
            if PlatformPowerSource.prefersSavingEnergy {
                await write(&batch, documents: &documents)
                await report(.paused(done: offset, total: work.count))
                while PlatformPowerSource.prefersSavingEnergy, !Task.isCancelled {
                    await PlatformPowerSource.change()
                }
                await report(.indexing(done: offset, total: work.count))
            }
            if let entry = entry(for: source, from: reader) {
                batch.append(entry)
                documents += entry.documents.count
                if batch.count >= Self.batchSessions || documents >= Self.batchDocuments {
                    await write(&batch, documents: &documents)
                }
            }
            await report(.indexing(done: offset + 1, total: work.count))
        }
        await write(&batch, documents: &documents)
        await report(.idle)
    }

    private func entry(for source: HistorySource, from reader: Reader) -> SearchIndexEntry? {
        let session: HistorySession?
        do {
            session = try reader.reader.read(source)
        } catch {
            Self.logger.error("Couldn't read \(reader.agent, privacy: .public) history: \(error, privacy: .public)")
            return nil
        }
        guard let session, !Self.isExcluded(session.cwd, by: excluded),
            (session.updatedAt ?? source.modifiedAt) >= retainedSince ?? .distantPast
        else { return nil }
        let key = SearchSessionKey(agent: reader.agent, session: session.sessionID)
        let known = known[key]
        let record = SearchSessionRecord(
            key: key, title: known?.title ?? session.title, cwd: session.cwd,
            project: known?.project ?? Self.folder(containing: session.cwd, in: projects) ?? session.cwd,
            createdAt: session.createdAt, updatedAt: session.updatedAt, isArchived: known?.isArchived ?? false)
        return SearchIndexEntry(session: record, documents: session.documents, source: source.stamp)
    }

    private func write(_ batch: inout [SearchIndexEntry], documents: inout Int) async {
        guard !batch.isEmpty else { return }
        do {
            try await index.replace(batch)
        } catch {
            Self.logger.error("Couldn't index history: \(error, privacy: .public)")
        }
        batch = []
        documents = 0
    }

    /// Whether `path` is one of `folders` or inside one.
    static func isExcluded(_ path: String, by folders: [String]) -> Bool {
        folders.contains { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
    }

    /// The deepest of `folders` that holds `path`.
    static func folder(containing path: String, in folders: [String]) -> String? {
        folders.filter { isExcluded(path, by: [$0]) }.max { $0.count < $1.count }
    }
}
