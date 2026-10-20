import ACP
import Foundation
import NativeHostProtocol

/// An agent's `session/update` payload as the host handles it while the agent streams: the few
/// fields the host reads, and the JSON it forwards to clients untouched. Building a `JSONValue` for
/// every chunk and encoding it again for every client was most of what streaming through the host
/// cost; this is one `JSONSerialization` parse and write.
struct AgentUpdate {
    /// `sessionUpdate`, such as `agent_message_chunk`.
    let kind: String?
    /// A `session_info_update`'s title.
    let title: String?
    /// A subagent update's own session id.
    let sessionID: SessionID?
    let json: Data

    /// The session a `session/update` notification is for, and its update.
    static func parse(_ line: Data) -> (session: SessionID, update: AgentUpdate)? {
        guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let params = message["params"] as? [String: Any], let session = params["sessionId"] as? String,
            let update = params["update"] as? [String: Any],
            let json = try? JSONSerialization.data(withJSONObject: update, options: [.withoutEscapingSlashes])
        else { return nil }
        let agentUpdate = AgentUpdate(
            kind: update["sessionUpdate"] as? String, title: update["title"] as? String,
            sessionID: (update["sessionId"] as? String).map(SessionID.init), json: json)
        return (SessionID(session), agentUpdate)
    }

    private init(kind: String?, title: String?, sessionID: SessionID?, json: Data) {
        self.kind = kind
        self.title = title
        self.sessionID = sessionID
        self.json = json
    }

    /// Decoded in full, for the rare reader that needs all of it (a hidden command's reply).
    var decoded: SessionUpdate? {
        try? JSONDecoder().decode(SessionUpdate.self, from: json)
    }
}
