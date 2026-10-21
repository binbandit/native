import ACP
import Foundation

// Closing an idle host session frees its live state, but must not forget how to reopen it.
extension HostStore {
    static let closedSessionConfigTable = """
        CREATE TABLE IF NOT EXISTS closed_session_config (
            agent_id TEXT NOT NULL,
            agent_session_id TEXT NOT NULL,
            config_choices TEXT NOT NULL,
            PRIMARY KEY (agent_id, agent_session_id)
        );
        """

    func keepClosedSessionConfig(_ session: StoredSession) throws {
        guard session.origin != .announced, let agentSessionID = session.agentSessionID else { return }
        try database.run(
            """
            INSERT INTO closed_session_config (agent_id, agent_session_id, config_choices) VALUES (?, ?, ?)
            ON CONFLICT(agent_id, agent_session_id) DO UPDATE SET config_choices = excluded.config_choices
            """,
            .text(session.agentID), .text(agentSessionID.rawValue), try JSONColumn.encode(session.configChoices))
    }

    func closedSessionConfig(agentID: String, agentSessionID: SessionID) throws -> [String: String]? {
        guard
            let row = try database.query(
                "SELECT config_choices FROM closed_session_config WHERE agent_id = ? AND agent_session_id = ?",
                .text(agentID), .text(agentSessionID.rawValue)
            ).first
        else { return nil }
        return JSONColumn.decode([String: String].self, row[0])
    }

    func forgetClosedSessionConfig(agentID: String, agentSessionID: SessionID) throws {
        try database.run(
            "DELETE FROM closed_session_config WHERE agent_id = ? AND agent_session_id = ?",
            .text(agentID), .text(agentSessionID.rawValue))
    }
}
