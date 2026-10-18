import ACP
import Foundation
import Observation
import os

/// A session as the sidebar shows it: one an agent listed for a project, or one started here that
/// the agent hasn't saved yet.
struct SessionSummary: Identifiable, Hashable {
    let project: Project.ID
    let agent: AgentDefinition
    let info: SessionInfo

    var id: SessionKey {
        SessionKey(agent: agent.id, id: info.sessionId)
    }
}

/// The sessions each agent has in each project, as `session/list` reports them for the project's
/// folder, plus the ones started here that the agent hasn't saved yet. Kept on disk, so the sidebar
/// shows an agent's sessions while the agent isn't running, until it lists them again.
@Observable
final class SessionCatalog {
    private typealias Listing = [Project.ID: [AgentDefinition.ID: [SessionInfo]]]

    /// Saved right away when the user's action changed it (a new session must survive the app being
    /// killed a moment later), and once per burst while agents' listings come in.
    private var listed: Listing {
        didSet { isRefreshing ? scheduleSave() : save() }
    }
    @ObservationIgnored private let url: URL?
    @ObservationIgnored private var isSaveScheduled = false
    @ObservationIgnored private var isRefreshing = false

    static var defaultURL: URL {
        let folder = Bundle.main.bundleIdentifier ?? "Native"
        return URL.applicationSupportDirectory.appending(path: folder, directoryHint: .isDirectory)
            .appending(path: "session-catalog.json")
    }

    /// Reads the listing saved at `url`, and saves there as it changes; nil keeps it in memory.
    init(url: URL? = SessionCatalog.defaultURL) {
        self.url = url
        // A file from an incompatible build is only a stale cache; the agents list again.
        listed =
            url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Listing.self, from: $0) }
            ?? [:]
    }

    func sessions(in project: Project.ID, of agent: AgentDefinition.ID) -> [SessionInfo] {
        listed[project]?[agent] ?? []
    }

    /// The project a session is listed in, and what the agent said about it.
    func lookup(_ key: SessionKey) -> (project: Project.ID, info: SessionInfo)? {
        for (project, agents) in listed {
            if let info = agents[key.agent]?.first(where: { $0.sessionId == key.id }) {
                return (project, info)
            }
        }
        return nil
    }

    func contains(_ key: SessionKey) -> Bool {
        lookup(key) != nil
    }

    /// Whether any project lists sessions of `agent`.
    func hasSessions(of agent: AgentDefinition.ID) -> Bool {
        listed.values.contains { $0[agent]?.isEmpty == false }
    }

    /// Whether `agent` has ever listed `project`, so its (possibly empty) listing is known.
    func hasListed(_ agent: AgentDefinition.ID, in project: Project.ID) -> Bool {
        listed[project]?[agent] != nil
    }

    /// Puts another session in a listed one's place, as when a crash takes one the agent never
    /// saved and Native starts a fresh one instead.
    func swap(_ key: SessionKey, for info: SessionInfo) {
        for (project, agents) in listed {
            if let index = agents[key.agent]?.firstIndex(where: { $0.sessionId == key.id }) {
                listed[project]?[key.agent]?[index] = info
                return
            }
        }
    }

    /// Lists a session the user just started, before the agent has saved it.
    func add(_ info: SessionInfo, for agent: AgentDefinition.ID, in project: Project.ID) {
        listed[project, default: [:]][agent, default: []].insert(info, at: 0)
    }

    func remove(_ key: SessionKey) {
        for project in listed.keys {
            listed[project]?[key.agent]?.removeAll { $0.sessionId == key.id }
        }
    }

    func remove(agent: AgentDefinition.ID) {
        for project in listed.keys {
            listed[project]?[agent] = nil
        }
    }

    func remove(project: Project.ID) {
        listed[project] = nil
    }

    /// Replaces an agent's sessions in a project with a fresh listing. Sessions `isOpen` says are
    /// in use survive even when the agent hasn't saved them yet.
    func replace(
        _ agent: AgentDefinition.ID, in project: Project.ID, with fetched: [SessionInfo],
        keeping isOpen: (SessionID) -> Bool
    ) {
        isRefreshing = true
        defer { isRefreshing = false }
        let fetchedIDs = Set(fetched.map(\.sessionId))
        let unsaved = sessions(in: project, of: agent).filter {
            !fetchedIDs.contains($0.sessionId) && isOpen($0.sessionId)
        }
        listed[project, default: [:]][agent] = unsaved + fetched
    }

    /// Refreshing lists every project for every agent at once, so those changes save together.
    private func scheduleSave() {
        guard url != nil, !isSaveScheduled else { return }
        isSaveScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.isSaveScheduled = false
            self?.save()
        }
    }

    private func save() {
        guard let url else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(listed).write(to: url, options: .atomic)
        } catch {
            AppModel.logger.error("Couldn't save the session catalog: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Everything the agent lists for `cwd`, following its cursor.
    static func fetch(cwd: String, from connection: ACPConnection) async throws -> [SessionInfo] {
        var fetched: [SessionInfo] = []
        var cursor: String?
        var pages = 0
        // Some agents filter by cwd after paging, so pages can come back empty with more to go. The
        // page cap only guards against a cursor that never ends.
        repeat {
            let page = try await connection.send(ListSessionsRequest(cwd: cwd, cursor: cursor))
            fetched += page.sessions
            cursor = page.nextCursor
            pages += 1
        } while cursor != nil && fetched.count < 500 && pages < 100
        return fetched
    }
}
