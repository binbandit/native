import Foundation
import NativeHostProtocol
import SessionTitling

// Titles (`HostCore+Titles.swift`): each session's user title, generated title, and while one is
// still wanted, the first message it's written from. A row goes with its session.
extension HostStore {
    /// Created by the schema's titles step.
    static let titlesTable = """
        CREATE TABLE IF NOT EXISTS titles (
            session_id TEXT PRIMARY KEY REFERENCES sessions(id) ON DELETE CASCADE,
            user_title TEXT,
            generated_title TEXT,
            project_name TEXT,
            prompt TEXT,
            progress TEXT
        );
        """

    /// Writes a session's titles, or forgets them when there's nothing left to keep.
    func setTitles(_ state: SessionTitleState, for sessionID: HostSessionID) throws {
        guard !state.isEmpty else {
            try database.run("DELETE FROM titles WHERE session_id = ?", .text(sessionID.description))
            return
        }
        try database.run(
            """
            INSERT INTO titles (session_id, user_title, generated_title, project_name, prompt, progress, retry_count, prompt_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(session_id) DO UPDATE SET user_title = excluded.user_title,
                generated_title = excluded.generated_title, project_name = excluded.project_name,
                prompt = excluded.prompt, progress = excluded.progress, retry_count = excluded.retry_count,
                prompt_id = excluded.prompt_id
            """,
            .text(sessionID.description), .text(state.user), .text(state.generated),
            .text(state.request?.projectName), .text(state.request?.prompt), .text(state.progress?.rawValue),
            .integer(Int64(state.retryCount)), .text(state.promptID?.uuidString))
    }

    /// Every session's titles.
    func titles() throws -> [HostSessionID: SessionTitleState] {
        var titles: [HostSessionID: SessionTitleState] = [:]
        let rows = try database.query(
            "SELECT session_id, user_title, generated_title, project_name, prompt, progress, retry_count, prompt_id FROM titles"
        )
        for row in rows {
            guard let id = row[0].text.flatMap(UUID.init(uuidString:)) else { continue }
            let request = row[4].text.map { SessionTitleRequest(projectName: row[3].text ?? "", prompt: $0) }
            titles[HostSessionID(id)] = SessionTitleState(
                user: row[1].text, generated: row[2].text, request: request,
                progress: row[5].text.flatMap(SessionTitleState.Progress.init(rawValue:)),
                retryCount: Int(row[6].integer ?? 0), promptID: row[7].text.flatMap(UUID.init(uuidString:)))
        }
        return titles
    }
}
