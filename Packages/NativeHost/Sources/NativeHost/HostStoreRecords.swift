import ACP
import Foundation
import NativeHostProtocol

// MARK: - Records

struct StoredSession: Hashable {
    var id: HostSessionID
    var agentID: String
    var agentSessionID: SessionID?
    var cwd: String
    var parentID: HostSessionID?
    var origin: SessionOrigin
    var title: String?
    var createdAt: Date
    var lastActivity: Date?
    var lastStopReason: String?
    var isQueuePaused: Bool
    /// ACP `McpServer` objects for the agent, handed over again on every reload.
    var mcpServers: [JSONValue]
    /// The `_meta` for `session/new` and every `session/load`.
    var meta: JSONValue?
    /// The settings the session runs with, by option id (`HostCore.pinConfig`): set back after a
    /// reload where the agent reports others (an agent may reopen a session on its default model).
    var configChoices: [String: String]
    /// Opened from the agent's own list, so the agent saved it; otherwise started here.
    var isAdopted: Bool

    init(
        id: HostSessionID, agentID: String, agentSessionID: SessionID?, cwd: String, parentID: HostSessionID?,
        origin: SessionOrigin,
        title: String? = nil, createdAt: Date = .now, lastActivity: Date? = nil, lastStopReason: String? = nil,
        isQueuePaused: Bool = false,
        mcpServers: [JSONValue] = [], meta: JSONValue? = nil, configChoices: [String: String] = [:],
        isAdopted: Bool = false
    ) {
        self.id = id
        self.agentID = agentID
        self.agentSessionID = agentSessionID
        self.cwd = cwd
        self.parentID = parentID
        self.origin = origin
        self.title = title
        self.createdAt = createdAt
        self.lastActivity = lastActivity
        self.lastStopReason = lastStopReason
        self.isQueuePaused = isQueuePaused
        self.mcpServers = mcpServers
        self.meta = meta
        self.configChoices = configChoices
        self.isAdopted = isAdopted
    }

    init?(row: [SQLiteDatabase.Value]) {
        guard let id = row[0].text.flatMap(UUID.init(uuidString:)), let agentID = row[1].text, let cwd = row[3].text,
            let createdAt = row[7].date
        else { return nil }
        self.init(
            id: HostSessionID(id), agentID: agentID, agentSessionID: row[2].text.map(SessionID.init), cwd: cwd,
            parentID: row[4].text.flatMap(UUID.init(uuidString:)).map(HostSessionID.init),
            origin: row[5].text.flatMap(SessionOrigin.init(rawValue:)) ?? .unknown, title: row[6].text,
            createdAt: createdAt,
            lastActivity: row[8].date, lastStopReason: row[9].text, isQueuePaused: row[10].bool,
            mcpServers: JSONColumn.decode([JSONValue].self, row[11]) ?? [],
            meta: JSONColumn.decode(JSONValue.self, row[12]),
            configChoices: JSONColumn.decode([String: String].self, row[13]) ?? [:], isAdopted: row[14].bool
        )
    }
}

/// A message on its way to the agent, with everything needed to send it again after a restart.
struct OutgoingPrompt: Hashable {
    /// The request id it was sent with.
    var id: UUID
    var text: String
    /// What goes to the agent when it's more than `text`.
    var content: [ContentBlock]?
    var attachments: [EchoAttachment]
    var preamble: PromptPreambleSpec?
    var isEchoed: Bool
    var origin: PromptEcho.Origin
    var steersAfterTools = false

    init(
        id: UUID = UUID(), text: String, content: [ContentBlock]? = nil, attachments: [EchoAttachment] = [],
        preamble: PromptPreambleSpec? = nil, isEchoed: Bool = true, origin: PromptEcho.Origin = .user
    ) {
        self.id = id
        self.text = text
        self.content = content
        self.attachments = attachments
        self.preamble = preamble
        self.isEchoed = isEchoed
        self.origin = origin
    }

    /// As clients see it waiting in the queue.
    var queued: QueuedPrompt {
        QueuedPrompt(
            id: id, text: text, isEchoed: isEchoed,
            attachments: attachments.map { EchoAttachment(name: $0.name, url: $0.url) })
    }

    /// What's kept beside the columns every prompt has.
    struct Extras: Codable {
        var content: [ContentBlock]?
        var attachments: [EchoAttachment]?
        var preamble: PromptPreambleSpec?
        var origin: PromptEcho.Origin?
        var steersAfterTools: Bool?
    }

    var extras: Extras {
        Extras(
            content: content, attachments: attachments.isEmpty ? nil : attachments, preamble: preamble, origin: origin,
            steersAfterTools: steersAfterTools ? true : nil)
    }

    init(id: UUID, text: String, isEchoed: Bool, extras: Extras?) {
        self.init(
            id: id, text: text, content: extras?.content, attachments: extras?.attachments ?? [],
            preamble: extras?.preamble, isEchoed: isEchoed, origin: extras?.origin ?? .user)
        steersAfterTools = extras?.steersAfterTools ?? false
    }
}

/// JSON kept in a text column.
enum JSONColumn {
    static func decode<Value: Decodable>(_ type: Value.Type, _ value: SQLiteDatabase.Value) -> Value? {
        value.text.flatMap { try? JSONDecoder().decode(type, from: Data($0.utf8)) }
    }

    static func encode(_ value: some Encodable) throws -> SQLiteDatabase.Value {
        .text(String(decoding: try JSONEncoder().encode(value), as: UTF8.self))
    }
}

/// A turn that started and hasn't ended. At most one per session.
struct UnfinishedTurn: Hashable {
    enum Kind: String {
        /// A message the user (or a tool, or the queue) sent.
        case prompt
        /// Native telling the agent its previous turn was interrupted.
        case recovery
    }

    var sessionID: HostSessionID
    var prompt: OutgoingPrompt
    var kind: Kind
    var startedAt: Date
    /// How many times recovery has already tried to finish this turn.
    var attempts: Int

    init(sessionID: HostSessionID, prompt: OutgoingPrompt, kind: Kind, startedAt: Date = .now, attempts: Int = 0) {
        self.sessionID = sessionID
        self.prompt = prompt
        self.kind = kind
        self.startedAt = startedAt
        self.attempts = attempts
    }

    var requestID: UUID { prompt.id }
    var text: String { prompt.text }

    init?(row: [SQLiteDatabase.Value]) {
        guard let session = row[0].text.flatMap(UUID.init(uuidString:)),
            let request = row[1].text.flatMap(UUID.init(uuidString:)),
            let text = row[2].text, let kind = row[3].text.flatMap(Kind.init(rawValue:)), let startedAt = row[5].date
        else { return nil }
        let prompt = OutgoingPrompt(
            id: request, text: text, isEchoed: row[4].bool,
            extras: JSONColumn.decode(OutgoingPrompt.Extras.self, row[7]))
        self.init(
            sessionID: HostSessionID(session), prompt: prompt, kind: kind, startedAt: startedAt,
            attempts: Int(row[6].integer ?? 0))
    }
}

struct StoredQueueItem: Hashable {
    var prompt: OutgoingPrompt
    /// Being steered into the running turn right now. If the host stops before the agent answers,
    /// recovery checks the agent's transcript to see whether it arrived.
    var isSteering: Bool
}
