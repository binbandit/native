import Foundation
import Search
import os

/// One pass over the agents' own history, reading only what's new: each file's checkpoint (its
/// size, modification time and the offset already indexed) skips an unchanged file without opening
/// it, continues a file that only grew from where the last pass stopped, and reads anything else
/// from the start. Files are streamed a megabyte at a time and written in small batches, so memory
/// stays flat however big the history is. Each batch records its files' checkpoints, so a pass
/// that's cancelled, crashes or pauses resumes where it stopped. It waits while the Mac is on
/// battery or in Low Power Mode. Its caller picks the priority.
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
    /// Looks a session up in Native's own lists, asked only for sessions a pass actually reads.
    let known: @Sendable (SearchSessionKey) async -> Known?
    /// Native's project folders, for placing sessions it doesn't list.
    let projects: [String]
    let excluded: [String]
    /// Sessions last active before this are kept out of the index (an organization's retention
    /// policy), and dropped from it first.
    let retainedSince: Date?

    /// Limits per write: small enough that a batch's memory stays bounded and a search never
    /// waits on one.
    private static let batchSessions = 25
    private static let batchDocuments = 2_000
    private static let batchBytes = 4 << 20
    private static let logger = Logger(subsystem: "Native", category: "Search")

    private struct Work {
        let reader: Reader
        let source: HistorySource
        let resume: HistoryResume?
        let isNew: Bool
    }

    /// Returns whether the pass finished (rather than being cancelled).
    @concurrent func run(report: @escaping @Sendable (TranscriptSearchIndexing) async -> Void) async -> Bool {
        if let retainedSince {
            try? await index.removeSessions(updatedBefore: retainedSince)
        }
        let checkpoints = (try? await index.checkpoints()) ?? [:]
        let work = pending(checkpoints: checkpoints)
        guard !work.isEmpty else {
            await report(.idle)
            return true
        }
        await report(.indexing(done: 0, total: work.count))
        var batch = SearchIndexBatch()
        for (done, item) in work.enumerated() {
            if Task.isCancelled { break }
            if PlatformPowerSource.prefersSavingEnergy {
                await write(&batch)
                await report(.paused(done: done, total: work.count))
                while PlatformPowerSource.prefersSavingEnergy, !Task.isCancelled {
                    await PlatformPowerSource.change()
                }
                await report(.indexing(done: done, total: work.count))
            }
            await read(item, into: &batch)
            let size = batch.size
            if size.sessions >= Self.batchSessions || size.documents >= Self.batchDocuments
                || size.bytes >= Self.batchBytes || batch.checkpoints.count >= 200
            {
                await write(&batch)
            }
            await report(.indexing(done: done + 1, total: work.count))
        }
        await write(&batch)
        await report(.idle)
        return !Task.isCancelled
    }

    /// The files to read: new ones first, newest first, then ones that changed (an active
    /// session's log, often the biggest file there is, now only its new lines).
    private func pending(checkpoints: [String: HistoryCheckpoint]) -> [Work] {
        var work: [Work] = []
        for reader in readers {
            for source in reader.reader.sources() {
                guard source.modifiedAt >= retainedSince ?? .distantPast else { continue }
                guard let checkpoint = checkpoints[source.path] else {
                    work.append(Work(reader: reader, source: source, resume: nil, isNew: true))
                    continue
                }
                guard !checkpoint.matches(source) else { continue }
                // An excluded project's files are known by their checkpoint, and never opened.
                if let cwd = checkpoint.cwd, Self.isExcluded(cwd, by: excluded) { continue }
                work.append(Work(reader: reader, source: source, resume: checkpoint.resume(for: source), isNew: false))
            }
        }
        return work.sorted { lhs, rhs in
            lhs.isNew == rhs.isNew ? lhs.source.modifiedAt > rhs.source.modifiedAt : lhs.isNew
        }
    }

    private func read(_ work: Work, into batch: inout SearchIndexBatch) async {
        let read: HistoryRead
        do {
            read = try work.reader.reader.read(work.source, resuming: work.resume)
        } catch {
            Self.logger.error(
                "Couldn't read \(work.reader.agent, privacy: .public) history: \(error, privacy: .public)")
            return
        }
        let session = read.session
        let key = session.map { SearchSessionKey(agent: work.reader.agent, session: $0.sessionID) }
        batch.checkpoints.append(
            HistoryCheckpoint(
                path: work.source.path, size: work.source.size, modifiedAt: work.source.modifiedAt, offset: read.offset,
                session: key, cwd: session?.cwd))
        guard let session, let key, !Self.isExcluded(session.cwd, by: excluded),
            (session.updatedAt ?? work.source.modifiedAt) >= retainedSince ?? .distantPast
        else { return }
        let known = await known(key)
        let record = SearchSessionRecord(
            key: key, title: known?.title ?? session.title, cwd: session.cwd,
            project: known?.project ?? Self.folder(containing: session.cwd, in: projects) ?? session.cwd,
            createdAt: session.createdAt, updatedAt: session.updatedAt, isArchived: known?.isArchived ?? false)
        let entry = SearchIndexEntry(session: record, documents: session.documents)
        if work.resume == nil {
            batch.replacing.append(entry)
        } else {
            batch.appending.append(entry)
        }
    }

    private func write(_ batch: inout SearchIndexBatch) async {
        do {
            try await index.write(batch)
        } catch {
            Self.logger.error("Couldn't index history: \(error, privacy: .public)")
        }
        batch = SearchIndexBatch()
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
