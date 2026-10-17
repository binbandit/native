import ACP
import Foundation
import Observation

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
/// folder, plus the ones started here that the agent hasn't saved yet.
@Observable
final class SessionCatalog {
    private var listed: [Project.ID: [AgentDefinition.ID: [SessionInfo]]] = [:]

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

    /// Lists a session the user just started, before the agent has saved it.
    func add(_ info: SessionInfo, for agent: AgentDefinition.ID, in project: Project.ID) {
        listed[project, default: [:]][agent, default: []].insert(info, at: 0)
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
    func replace(_ agent: AgentDefinition.ID, in project: Project.ID, with fetched: [SessionInfo], keeping isOpen: (SessionID) -> Bool) {
        let fetchedIDs = Set(fetched.map(\.sessionId))
        let unsaved = sessions(in: project, of: agent).filter { !fetchedIDs.contains($0.sessionId) && isOpen($0.sessionId) }
        listed[project, default: [:]][agent] = unsaved + fetched
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
