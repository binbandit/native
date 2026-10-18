import ACP
import Foundation
import NativePolicy
import Observation
import Search
import os

/// Search across every agent run (docs/search.md). Owns the index and keeps it filled: live
/// sessions as their turns end, past sessions from each agent's own history, and sessions of agents
/// without a history reader as Native loads them. Answers the panel's queries and opens what they
/// find at the exact message.
///
/// Everything heavy (reading history, building documents, SQLite) runs off the main thread at low
/// priority; the main thread only hands over snapshots and shows results.
@Observable
final class TranscriptSearchCenter {
    /// Whether the panel is showing.
    var isPresented = false {
        didSet {
            if isPresented, !oldValue { panelOpened() }
        }
    }
    /// What the panel searches for. Changing it, or `filters`, searches again.
    var query = "" {
        didSet { scheduleSearch() }
    }
    var filters = SearchFilters() {
        didSet { scheduleSearch() }
    }
    private(set) var results = SearchResults.empty
    /// The query `results` answer.
    private(set) var answeredQuery: SearchQuery?
    /// Set only by TranscriptSearchCenter+History.swift.
    var indexing = TranscriptSearchIndexing.idle
    /// Why search can't run right now (the index couldn't be opened), in plain words.
    private(set) var failure: String?
    /// Set only by TranscriptSearchCenter+History.swift.
    var statistics: SearchIndexStatistics?
    /// The last search that failed, which the panel says rather than showing no results.
    private(set) var searchFailure: String?

    /// Whether past sessions are read from the agents' own history, not only Native's.
    var includesAgentHistory: Bool {
        didSet {
            UserDefaults.standard.set(includesAgentHistory, forKey: Self.includesHistoryKey)
            includesAgentHistory ? startBackfill() : stopBackfill()
        }
    }
    /// Folders whose sessions are never indexed (Settings ▸ Search).
    private(set) var excludedFolders: [String] {
        didSet { UserDefaults.standard.set(excludedFolders, forKey: Self.excludedFoldersKey) }
    }

    // Internal only for TranscriptSearchCenter+History.swift, as are the backfill's members below.
    @ObservationIgnored var index: SearchIndex?
    @ObservationIgnored weak var model: AppModel?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored var backfillTask: Task<Void, Never>?
    @ObservationIgnored var lastBackfill: Date?
    @ObservationIgnored var lastRefresh = Date.distantPast
    @ObservationIgnored var pendingBackfill: Task<Void, Never>?
    @ObservationIgnored var backfillID: UUID?
    /// Something changed while a pass ran (a turn ended, a project was included): run another.
    @ObservationIgnored var needsAnotherPass = false
    @ObservationIgnored private var liveTasks: [SessionKey: Task<Void, Never>] = [:]
    @ObservationIgnored private var observers: [Task<Void, Never>] = []

    private static let includesHistoryKey = "search.includesAgentHistory"
    private static let excludedFoldersKey = "search.excludedFolders"
    nonisolated static let logger = Logger(subsystem: "Native", category: "Search")

    init(defaults: UserDefaults = .standard) {
        includesAgentHistory = defaults.object(forKey: Self.includesHistoryKey) as? Bool ?? true
        excludedFolders = defaults.stringArray(forKey: Self.excludedFoldersKey) ?? []
    }

    // MARK: - Lifecycle

    /// Opens the index and starts keeping it filled, once the window is up: nothing here is
    /// needed to draw it. Called once by the composition root.
    func connect(to model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        Task(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            await self?.openIndex()
        }
    }

    private func openIndex() async {
        let url = SearchIndex.defaultURL(bundleIdentifier: Bundle.main.bundleIdentifier)
        do {
            index = try await Self.open(url)
            failure = nil
        } catch {
            Self.logger.error("Couldn't open the search index: \(error, privacy: .public)")
            failure = "Native couldn't open its search index (\(error.localizedDescription))."
            return
        }
        await refreshStatistics()
        observeSelection()
        observeArchive()
        startBackfill()
        if isPresented {
            scheduleSearch(debounce: false)
        }
    }

    /// Whether the Search plugin is on. Off, nothing is indexed and the panel offers to turn it on.
    var isEnabled: Bool {
        model?.plugins.isEnabled(BuiltInPlugins.search.manifest.id) ?? true
    }

    func turnOn() {
        model?.plugins.setEnabled(true, for: BuiltInPlugins.search.manifest.id)
        startBackfill()
        scheduleSearch(debounce: false)
    }

    /// Opens the index again after it failed to open.
    func reopen() {
        Task { await openIndex() }
    }

    /// Runs the current search again.
    func retry() {
        scheduleSearch(debounce: false)
    }

    /// Opening SQLite and checking its schema touch the disk, so it happens off the main thread.
    @concurrent nonisolated private static func open(_ url: URL) async throws -> SearchIndex {
        try await SearchIndex(url: url)
    }

    /// Shows the panel, with `query` in its field when given.
    func present(query: String? = nil) {
        if let query {
            self.query = query
        }
        isPresented = true
    }

    private func panelOpened() {
        scheduleSearch(debounce: false)
        // Pick up sessions the agents' CLIs recorded since the last pass, without polling.
        if let lastBackfill, Date.now.timeIntervalSince(lastBackfill) > 300 {
            startBackfill()
        }
    }

    // MARK: - Searching

    func scheduleSearch(debounce: Bool = true) {
        searchTask?.cancel()
        let query = SearchQuery(query, filters: filters)
        searchTask = Task { [weak self] in
            if debounce {
                try? await Task.sleep(for: .milliseconds(80))
            }
            guard let self, !Task.isCancelled, let index = self.index else { return }
            do {
                let results = try await index.search(query)
                guard !Task.isCancelled else { return }
                self.results = results
                answeredQuery = query
                searchFailure = nil
            } catch {
                guard !Task.isCancelled else { return }
                Self.logger.error("Search failed: \(error, privacy: .public)")
                searchFailure = error.localizedDescription
            }
        }
    }

    /// Opens a result's task, and when `hit` is given, scrolls its transcript to that message and
    /// highlights it once the session has loaded.
    func open(_ group: SearchGroup, hit: SearchHit?) {
        guard let model else { return }
        isPresented = false
        let key = SessionKey(searchKey: group.session.key)
        model.showSearchedSession(
            key, cwd: group.session.cwd, title: group.session.title, projectFolder: group.session.project)
        guard let hit else { return }
        let words = ParsedSearchQuery(answeredQuery ?? SearchQuery(query)).highlightWords
        Task {
            guard let session = await model.loadedSession(key) else { return }
            let items = session.state.items
            let index =
                hit.anchor.index(in: items)
                ?? items.firstIndex { item in
                    let text = SearchDocument.documents(transcript: [item]).first?.text ?? ""
                    return words.contains { text.localizedCaseInsensitiveContains($0) }
                }
            if let index {
                session.transcriptReveal = TranscriptReveal(itemID: items[index].id)
            }
        }
    }

    // MARK: - Live sessions

    func handle(_ event: SessionEvent) {
        switch event {
        case .turnEnded(let context, _), .turnFailed(let context, _, _, _):
            guard context.parentID == nil else { return }
            scheduleLiveIndex(clientID: context.clientID)
        default:
            break
        }
    }

    /// Indexes a session a moment after its turn ends, so a burst of turns (a queue draining) is
    /// one write, and never anything per streamed chunk.
    private func scheduleLiveIndex(clientID: UUID) {
        guard let session = model?.session(clientID: clientID), !session.isSubagent else { return }
        // An agent with a history reader has just written the turn to its log: reading that log
        // from its checkpoint costs only the new lines, and keeps one source of truth per session.
        if readerAgents.contains(session.agent.id) {
            scheduleBackfill()
            return
        }
        let key = session.key
        liveTasks[key]?.cancel()
        liveTasks[key] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.indexLive(session)
        }
    }

    private func indexLive(_ session: SessionModel) async {
        liveTasks[session.key] = nil
        guard isEnabled, let index, let record = record(for: session) else { return }
        await Self.write(record, items: session.state.items, plan: session.state.plan, to: index)
        await refreshStatistics()
    }

    @concurrent nonisolated private static func write(
        _ record: SearchSessionRecord, items: [TranscriptItem], plan: [PlanEntry], to index: SearchIndex
    ) async {
        let documents = SearchDocument.documents(transcript: items, plan: plan)
        do {
            try await index.replace(record, documents: documents)
        } catch {
            logger.error("Couldn't index a session: \(error, privacy: .public)")
        }
    }

    private func record(for session: SessionModel) -> SearchSessionRecord? {
        guard let model else { return nil }
        let cwd = session.cwd.folderPath
        guard !TranscriptSearchBackfill.isExcluded(cwd, by: excludedFolders) else { return nil }
        let project = model.catalog.lookup(session.key).flatMap { model.projects.project($0.project)?.path }
        return SearchSessionRecord(
            key: session.key.searchKey, title: session.displayTitle, cwd: cwd,
            project: project ?? TranscriptSearchBackfill.folder(containing: cwd, in: projectFolders) ?? cwd,
            updatedAt: session.lastActivity ?? .now, isArchived: model.isArchived(session.key))
    }

    /// The oldest activity the organization lets search keep (`policy.search.retentionDays`).
    var retainedSince: Date? {
        PolicyCenter.shared.policy.searchRetentionDays.map { Date.now.addingTimeInterval(-Double($0) * 86_400) }
    }

    var projectFolders: [String] {
        model?.projects.all.map(\.path) ?? []
    }

    /// Sessions of agents without a history reader are indexed as the user opens them.
    private func observeSelection() {
        guard let model else { return }
        observers.append(
            Task { [weak self] in
                for await key in Observations({ model.selection }) {
                    guard let self, let key, !self.readerAgents.contains(key.agent) else { continue }
                    Task {
                        guard let session = await model.loadedSession(key) else { return }
                        await self.indexLive(session)
                    }
                }
            })
    }

    var readerAgents: Set<AgentDefinition.ID> {
        guard includesAgentHistory, let model else { return [] }
        return Set(model.plugins.historyReaders.map(\.agent))
    }

    /// Keeps the index's archived flags in step with the sidebar's, so archived tasks are a filter.
    private func observeArchive() {
        guard let model else { return }
        observers.append(
            Task { [weak self] in
                var previous: Set<SessionKey>?
                for await archived in Observations({ model.archivedSessions.keys }) {
                    guard let index = self?.index else { return }
                    defer { previous = archived }
                    guard let previous else { continue }
                    for key in archived.symmetricDifference(previous) {
                        try? await index.setArchived(key.searchKey, archived.contains(key))
                    }
                }
            })
    }

    // MARK: - Privacy

    /// Forgets everything indexed and starts over from the agents' history.
    func clearIndex() async {
        stopBackfill()
        do {
            try await index?.removeAll()
        } catch {
            searchFailure = "Couldn't clear the index: \(error.localizedDescription)"
        }
        results = .empty
        answeredQuery = nil
        await refreshStatistics()
        startBackfill()
    }

    func exclude(_ folder: String) async {
        guard !excludedFolders.contains(folder) else { return }
        excludedFolders.append(folder)
        stopBackfill()
        // Under each spelling agents record it by, as the index compares paths as text.
        for spelling in SessionFolder.listingPaths(for: folder) {
            try? await index?.removeSessions(under: spelling)
        }
        await refreshStatistics()
        scheduleSearch(debounce: false)
        startBackfill()
    }

    /// Indexes a folder's sessions again; the next pass picks up its history.
    func include(_ folder: String) async {
        excludedFolders.removeAll { $0 == folder }
        stopBackfill()
        // Its files' checkpoints say they were seen; forgetting them has the next pass read them.
        for spelling in SessionFolder.listingPaths(for: folder) {
            try? await index?.removeCheckpoints(under: spelling)
        }
        startBackfill()
    }
}

/// How far indexing past sessions has got.
nonisolated enum TranscriptSearchIndexing: Equatable, Sendable {
    case idle
    case indexing(done: Int, total: Int)
    /// Waiting to continue until the Mac is on power again (or leaves Low Power Mode).
    case paused(done: Int, total: Int)
}

extension SessionKey {
    var searchKey: SearchSessionKey {
        SearchSessionKey(agent: agent.rawValue, session: id.rawValue)
    }

    init(searchKey: SearchSessionKey) {
        self.init(agent: AgentDefinition.ID(rawValue: searchKey.agent), id: SessionID(searchKey.session))
    }
}
