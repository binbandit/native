import ACP
import Darwin
import Foundation
import NativeHostProtocol

// A scriptable ACP agent for the host's crash-recovery tests. Like a real agent it keeps its own
// session store (in $FAKE_AGENT_STORE) and writes the user's message to it as soon as a prompt
// arrives, so `session/load` replays exactly what it received. Prompts script its behavior:
//
//   slow <n> …     streams n ticks, 300 ms apart, then ends the turn (cancellable)
//   crash-once …   exits mid-turn the first time it sees this text, answers normally after that
//   lose-once …    never records the prompt and hangs, the first time (a prompt that didn't arrive)
//   permission …   asks to approve a tool call and reports the answer
//   anything else  answers "echo: <text>"; Native's interruption notice gets "resumed"
//
// Every prompt and steer it receives is appended to $FAKE_AGENT_STORE/received.log.

signal(SIGPIPE, SIG_IGN)

struct Message: Codable {
    var role: String
    var text: String
}

actor FakeAgent {
    let store: URL
    var peer: JSONRPCPeer?
    var running: Set<SessionID> = []
    var cancelled: Set<SessionID> = []

    init(store: URL) {
        self.store = store
    }

    func attach(_ peer: JSONRPCPeer) {
        self.peer = peer
    }

    func handle(_ message: JSONRPCPeer.Message) async {
        guard let id = message.id, let peer else {
            if message.method == "session/cancel", let params = try? message.params(as: CancelParams.self) {
                cancelled.insert(params.sessionId)
            }
            return
        }
        do {
            switch message.method {
            case "initialize":
                try peer.respond(
                    to: id,
                    with: JSONValue.object([
                        "protocolVersion": .number(1),
                        "agentCapabilities": .object(["loadSession": .bool(true)]),
                        "agentInfo": .object(["name": .string("fake-agent"), "version": .string("1")]),
                        "_meta": .object(["steering": .object(["supported": .bool(true)])]),
                    ]))
            case "session/new":
                let session = SessionID(UUID().uuidString)
                try save([], for: session)
                try peer.respond(
                    to: id,
                    with: JSONValue.object([
                        "sessionId": .string(session.rawValue), "configOptions": Self.configOptions,
                    ]))
            case "session/load":
                let session = try message.params(as: SessionParams.self).sessionId
                for (index, entry) in try load(session).enumerated() {
                    let kind = entry.role == "user" ? "user_message_chunk" : "agent_message_chunk"
                    try update(
                        session,
                        [
                            "sessionUpdate": .string(kind), "messageId": .string("m\(index)"),
                            "content": Self.text(entry.text),
                        ])
                }
                try peer.respond(to: id, with: JSONValue.object(["configOptions": Self.configOptions]))
            case "session/prompt":
                let params = try message.params(as: PromptParams.self)
                let stopReason = try await prompt(params.sessionId, text: params.prompt.compactMap(\.text).joined())
                try peer.respond(to: id, with: JSONValue.object(["stopReason": .string(stopReason)]))
            case "_session/steering":
                let params = try message.params(as: PromptParams.self)
                let text = params.prompt.compactMap(\.text).joined()
                guard running.contains(params.sessionId) else {
                    try peer.respond(to: id, with: JSONValue.object(["outcome": .string("promptRequired")]))
                    return
                }
                received("steer", text)
                try append(Message(role: "user", text: text), to: params.sessionId)
                try peer.respond(to: id, with: JSONValue.object(["outcome": .string("injected")]))
            case "session/set_config_option":
                try peer.respond(to: id, with: JSONValue.object(["configOptions": Self.configOptions]))
            default:
                try peer.respond(to: id, error: .methodNotFound(message.method))
            }
        } catch {
            try? peer.respond(to: id, error: RPCError(code: -32000, message: error.localizedDescription))
        }
    }

    private func prompt(_ session: SessionID, text: String) async throws -> String {
        received("prompt", text)
        if text.hasPrefix("lose-once"), firstTime(text) {
            // Never recorded, never answered: as if the prompt was lost on the way in.
            try await Task.sleep(for: .seconds(3_600))
        }
        try append(Message(role: "user", text: text), to: session)
        running.insert(session)
        cancelled.remove(session)
        defer { running.remove(session) }
        var reply: String
        if text.hasPrefix("crash-once"), firstTime(text) {
            try update(session, ["sessionUpdate": .string("agent_message_chunk"), "content": Self.text("working…")])
            try await Task.sleep(for: .milliseconds(200))
            exit(3)
        } else if text.hasPrefix("slow") {
            let count = Int(text.split(separator: " ").dropFirst().first ?? "") ?? 5
            reply = ""
            for tick in 1...max(count, 1) {
                try await Task.sleep(for: .milliseconds(300))
                if cancelled.contains(session) {
                    try append(Message(role: "agent", text: reply), to: session)
                    return "cancelled"
                }
                let chunk = "tick \(tick)\n"
                reply += chunk
                try update(session, ["sessionUpdate": .string("agent_message_chunk"), "content": Self.text(chunk)])
            }
            try append(Message(role: "agent", text: reply), to: session)
            return "end_turn"
        } else if text.hasPrefix("permission") {
            let answer = try await peer?.request(
                "session/request_permission",
                JSONValue.object([
                    "sessionId": .string(session.rawValue),
                    "toolCall": .object([
                        "toolCallId": .string("call-\(UUID().uuidString.prefix(8))"),
                        "title": .string("Write notes.txt"), "kind": .string("edit"),
                    ]),
                    "options": .array([
                        .object(["optionId": .string("allow"), "name": .string("Allow"), "kind": .string("allow_once")]
                        ),
                        .object([
                            "optionId": .string("reject"), "name": .string("Reject"), "kind": .string("reject_once"),
                        ]),
                    ]),
                ]), as: JSONValue.self)
            reply =
                "permission: \(answer?["outcome"]?["optionId"]?.stringValue ?? answer?["outcome"]?["outcome"]?.stringValue ?? "none")"
        } else if text.contains("[Native] Your previous turn was interrupted") {
            reply = "resumed"
        } else {
            reply = "echo: \(text)"
        }
        try update(session, ["sessionUpdate": .string("agent_message_chunk"), "content": Self.text(reply)])
        try append(Message(role: "agent", text: reply), to: session)
        return "end_turn"
    }

    // MARK: - Store

    private func update(_ session: SessionID, _ update: [String: JSONValue]) throws {
        try peer?.notify(
            "session/update", JSONValue.object(["sessionId": .string(session.rawValue), "update": .object(update)]))
    }

    private func file(_ session: SessionID) -> URL {
        store.appending(path: "\(session.rawValue).json")
    }

    private func load(_ session: SessionID) throws -> [Message] {
        try JSONDecoder().decode([Message].self, from: Data(contentsOf: file(session)))
    }

    private func save(_ messages: [Message], for session: SessionID) throws {
        try JSONEncoder().encode(messages).write(to: file(session), options: .atomic)
    }

    private func append(_ message: Message, to session: SessionID) throws {
        try save(load(session) + [message], for: session)
    }

    /// True the first time it's asked about `text`, across restarts.
    private func firstTime(_ text: String) -> Bool {
        // A stable hash: `hashValue` changes from one process to the next.
        let hash = text.utf8.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1) }
        let marker = store.appending(path: "seen-\(hash)")
        guard !FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)) else { return false }
        FileManager.default.createFile(atPath: marker.path(percentEncoded: false), contents: Data())
        return true
    }

    private func received(_ kind: String, _ text: String) {
        let log = store.appending(path: "received.log")
        let line = Data("\(kind)\t\(text.replacingOccurrences(of: "\n", with: " "))\n".utf8)
        if let handle = try? FileHandle(forWritingTo: log) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
            try? handle.close()
        } else {
            try? line.write(to: log)
        }
    }

    private static func text(_ text: String) -> JSONValue {
        .object(["type": .string("text"), "text": .string(text)])
    }

    private static let configOptions = JSONValue.array([
        .object([
            "id": .string("mode"), "name": .string("Mode"), "category": .string("mode"), "type": .string("select"),
            "currentValue": .string("default"),
            "options": .array([
                .object(["value": .string("default"), "name": .string("Default")]),
                .object(["value": .string("plan"), "name": .string("Plan")]),
            ]),
        ])
    ])

    struct SessionParams: Decodable { var sessionId: SessionID }
    struct CancelParams: Decodable { var sessionId: SessionID }
    struct PromptParams: Decodable {
        var sessionId: SessionID
        var prompt: [ContentBlock]
    }
}

let store = URL(
    filePath: ProcessInfo.processInfo.environment["FAKE_AGENT_STORE"] ?? NSTemporaryDirectory(),
    directoryHint: .isDirectory)
try? FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
let agent = FakeAgent(store: store)
let channel = ByteChannel(reading: dup(STDIN_FILENO), writing: dup(STDOUT_FILENO), label: "fake-agent")
let peer = JSONRPCPeer(channel: channel, label: "fake-agent") { event in
    switch event {
    case .request(let message), .notification(let message):
        // Turns run concurrently with cancels and steers, as they do in real agents.
        Task { await agent.handle(message) }
    case .closed:
        exit(0)
    }
}
Task {
    await agent.attach(peer)
    peer.start()
}
dispatchMain()
