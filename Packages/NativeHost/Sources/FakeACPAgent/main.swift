import ACP
import Darwin
import Foundation
import NativeHostProtocol

// A scriptable ACP agent for the host's tests. Like a real agent it keeps its own session store
// (in $FAKE_AGENT_STORE) and writes the user's message to it as soon as a prompt arrives, so
// `session/load` replays exactly what it received. Prompts script its behavior:
//
//   slow <n> …          streams n ticks, 300 ms apart, then ends the turn (cancellable)
//   stubborn <n> …      like slow, but ignores session/cancel
//   flood <n> …         streams n chunks as fast as it can, each stamped "<seq>@<unix µs>", then ends
//   trickle <n> …       the same, one chunk a millisecond
//   crash-once …        exits mid-turn the first time it sees this text, answers normally after that
//   lose-once …         never records the prompt and hangs, the first time (a prompt that didn't arrive)
//   flaky-once …        fails with a network error the first time, answers normally after that
//   permission …        asks to approve a tool call and reports the answer
//   question …          asks a form question (elicitation/create) and reports the answer
//   mode?               answers with the session's current mode
//   /context            answers "context: 42% used", and sends that again just after the turn ends
//   anything else       answers "echo: <text>"; Native's interruption notice gets "resumed"
//
// Every prompt and steer it receives is appended to $FAKE_AGENT_STORE/received.log, with non-text
// blocks shown as "[link <name>]" and the like. With $FAKE_AGENT_GRANDCHILD set to a file, it starts
// `sleep` in a process group of its own at launch and writes its pid there, as npm does with the
// adapters it runs. With $FAKE_AGENT_NO_STEERING=1 it doesn't offer steering. Modes live in memory,
// so a reloaded session reports the default again.

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
    var modes: [SessionID: String] = [:]

    init(store: URL) {
        self.store = store
    }

    func attach(_ peer: JSONRPCPeer) {
        self.peer = peer
    }

    func handle(_ message: JSONRPCPeer.Message) async {
        guard let id = message.id, let peer else {
            if message.method == "session/cancel", let params = try? message.params(as: SessionParams.self) {
                cancelled.insert(params.sessionId)
            }
            return
        }
        do {
            try await respond(to: message, id: id, on: peer)
        } catch let error as RPCError {
            try? peer.respond(to: id, error: error)
        } catch {
            // -32603, not -32000: ACP reads -32000 as "sign in first".
            try? peer.respond(to: id, error: RPCError(code: -32603, message: error.localizedDescription))
        }
    }

    private func respond(to message: JSONRPCPeer.Message, id: RequestID, on peer: JSONRPCPeer) async throws {
        switch message.method {
        case "initialize":
            try peer.respond(
                to: id,
                with: JSONValue.object([
                    "protocolVersion": .number(1),
                    "agentCapabilities": .object([
                        "loadSession": .bool(true),
                        "sessionCapabilities": .object([
                            "list": .object([:]), "close": .object([:]), "delete": .object([:]),
                        ]),
                    ]),
                    "agentInfo": .object(["name": .string("fake-agent"), "version": .string("1")]),
                    "authMethods": .array([.object(["id": .string("token"), "name": .string("Token")])]),
                    "_meta": .object(["steering": .object(["supported": .bool(!Self.cantSteer)])]),
                ]))
        case "authenticate":
            received("authenticate", (try? message.params(as: AuthParams.self))?.methodId ?? "")
            try peer.respond(to: id, with: JSONValue.object([:]))
        case "session/new":
            let session = SessionID(UUID().uuidString)
            try save([], for: session)
            try peer.respond(
                to: id,
                with: JSONValue.object(["sessionId": .string(session.rawValue), "configOptions": options(session)]))
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
            try peer.respond(to: id, with: JSONValue.object(["configOptions": options(session)]))
        case "session/list":
            let sessions = try FileManager.default.contentsOfDirectory(atPath: store.path(percentEncoded: false))
                .filter { $0.hasSuffix(".json") }.sorted()
                .map { JSONValue.object(["sessionId": .string(String($0.dropLast(5))), "cwd": .string("/")]) }
            try peer.respond(to: id, with: JSONValue.object(["sessions": .array(sessions)]))
        case "session/delete":
            let session = try message.params(as: SessionParams.self).sessionId
            try? FileManager.default.removeItem(at: file(session))
            received("delete", session.rawValue)
            try peer.respond(to: id, with: JSONValue.object([:]))
        case "session/close":
            received("close", try message.params(as: SessionParams.self).sessionId.rawValue)
            try peer.respond(to: id, with: JSONValue.object([:]))
        case "session/prompt":
            let params = try message.params(as: PromptParams.self)
            let stopReason = try await prompt(params.sessionId, text: Self.describe(params.prompt))
            try peer.respond(to: id, with: JSONValue.object(["stopReason": .string(stopReason)]))
        case "_session/steering":
            let params = try message.params(as: PromptParams.self)
            let text = Self.describe(params.prompt)
            guard running.contains(params.sessionId) else {
                try peer.respond(to: id, with: JSONValue.object(["outcome": .string("promptRequired")]))
                return
            }
            received("steer", text)
            try append(Message(role: "user", text: text), to: params.sessionId)
            try peer.respond(to: id, with: JSONValue.object(["outcome": .string("injected")]))
        case "session/set_config_option":
            let params = try message.params(as: ConfigParams.self)
            modes[params.sessionId] = params.value
            received("config", "\(params.configId)=\(params.value)")
            try peer.respond(to: id, with: JSONValue.object(["configOptions": options(params.sessionId)]))
        default:
            try peer.respond(to: id, error: .methodNotFound(message.method))
        }
    }

    private func prompt(_ session: SessionID, text: String) async throws -> String {
        received("prompt", text)
        if text.hasPrefix("lose-once"), firstTime(text) {
            // Never recorded, never answered: as if the prompt was lost on the way in.
            try await Task.sleep(for: .seconds(3_600))
        }
        if text.hasPrefix("flaky-once"), firstTime(text) {
            throw RPCError(code: -32603, message: "Network error: connection reset by peer")
        }
        try append(Message(role: "user", text: text), to: session)
        running.insert(session)
        cancelled.remove(session)
        defer { running.remove(session) }
        let reply: String
        if text.hasPrefix("crash-once"), firstTime(text) {
            try update(session, ["sessionUpdate": .string("agent_message_chunk"), "content": Self.text("working…")])
            try await Task.sleep(for: .milliseconds(200))
            exit(3)
        } else if text.hasPrefix("slow") || text.hasPrefix("stubborn") {
            return try await tick(session, count: Self.count(in: text, default: 5), stoppable: text.hasPrefix("slow"))
        } else if text.hasPrefix("flood") || text.hasPrefix("trickle") {
            // A trickle sends one chunk a millisecond, about what a fast model streams.
            let count = Self.count(in: text, default: 1_000)
            for index in 1...count {
                if text.hasPrefix("trickle") {
                    usleep(1_000)
                }
                let stamp = Int64(Date.now.timeIntervalSince1970 * 1_000_000)
                try update(
                    session,
                    ["sessionUpdate": .string("agent_message_chunk"), "content": Self.text("\(index)@\(stamp) ")])
            }
            reply = "streamed \(count)"
        } else if text.hasPrefix("permission") {
            reply = "permission: \(try await askPermission(session))"
        } else if text.hasPrefix("question") {
            reply = "question: \(try await askQuestion(session))"
        } else if text == "mode?" {
            reply = "mode: \(modes[session] ?? "default")"
        } else if text == "/context" {
            reply = "context: 42% used"
            // claude-agent-acp sends a local command's output twice, the second after the turn.
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                try? self.update(
                    session, ["sessionUpdate": .string("agent_message_chunk"), "content": Self.text("\n\(reply)\n")])
            }
        } else if text.contains("[Native] Your previous turn was interrupted") {
            reply = "resumed"
        } else {
            reply = "echo: \(text)"
        }
        try update(session, ["sessionUpdate": .string("agent_message_chunk"), "content": Self.text(reply)])
        try append(Message(role: "agent", text: reply), to: session)
        return "end_turn"
    }

    private func tick(_ session: SessionID, count: Int, stoppable: Bool) async throws -> String {
        var reply = ""
        for tick in 1...count {
            try await Task.sleep(for: .milliseconds(300))
            if stoppable, cancelled.contains(session) {
                try append(Message(role: "agent", text: reply), to: session)
                return "cancelled"
            }
            let chunk = "tick \(tick)\n"
            reply += chunk
            try update(session, ["sessionUpdate": .string("agent_message_chunk"), "content": Self.text(chunk)])
        }
        try append(Message(role: "agent", text: reply), to: session)
        return "end_turn"
    }

    private func askPermission(_ session: SessionID) async throws -> String {
        let answer = try await peer?.request(
            "session/request_permission",
            JSONValue.object([
                "sessionId": .string(session.rawValue),
                "toolCall": .object([
                    "toolCallId": .string("call-\(UUID().uuidString.prefix(8))"),
                    "title": .string("Write notes.txt"), "kind": .string("edit"),
                ]),
                "options": .array([
                    .object(["optionId": .string("allow"), "name": .string("Allow"), "kind": .string("allow_once")]),
                    .object(["optionId": .string("reject"), "name": .string("Reject"), "kind": .string("reject_once")]),
                ]),
            ]), as: JSONValue.self)
        return answer?["outcome"]?["optionId"]?.stringValue ?? answer?["outcome"]?["outcome"]?.stringValue ?? "none"
    }

    private func askQuestion(_ session: SessionID) async throws -> String {
        let answer = try await peer?.request(
            "elicitation/create",
            JSONValue.object([
                "sessionId": .string(session.rawValue), "mode": .string("form"), "message": .string("Which color?"),
                "requestedSchema": .object([
                    "type": .string("object"), "properties": .object(["color": .object(["type": .string("string")])]),
                ]),
            ]), as: JSONValue.self)
        let color = answer?["content"]?["color"]?.stringValue
        return "\(answer?["action"]?.stringValue ?? "none")\(color.map { " \($0)" } ?? "")"
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

    private func options(_ session: SessionID) -> JSONValue {
        .array([
            .object([
                "id": .string("mode"), "name": .string("Mode"), "category": .string("mode"), "type": .string("select"),
                "currentValue": .string(modes[session] ?? "default"),
                "options": .array([
                    .object(["value": .string("default"), "name": .string("Default")]),
                    .object(["value": .string("plan"), "name": .string("Plan")]),
                ]),
            ])
        ])
    }

    /// `FAKE_AGENT_NO_STEERING=1` makes it an agent that can't take messages mid-turn.
    private static let cantSteer = ProcessInfo.processInfo.environment["FAKE_AGENT_NO_STEERING"] == "1"

    private static func count(in text: String, default value: Int) -> Int {
        max(Int(text.split(separator: " ").dropFirst().first ?? "") ?? value, 1)
    }

    /// A prompt's blocks as one line: text as it is, anything else named.
    private static func describe(_ blocks: [ContentBlock]) -> String {
        blocks.map { block in
            switch block {
            case .text(let text): text
            case .resourceLink(_, let name): "[link \(name)]"
            case .resource(let uri, _): "[resource \(uri)]"
            case .image: "[image]"
            case .unsupported(let type): "[\(type)]"
            }
        }.joined()
    }

    private static func text(_ text: String) -> JSONValue {
        .object(["type": .string("text"), "text": .string(text)])
    }

    struct SessionParams: Decodable { var sessionId: SessionID }
    struct AuthParams: Decodable { var methodId: String }
    struct ConfigParams: Decodable {
        var sessionId: SessionID
        var configId: String
        var value: String
    }
    struct PromptParams: Decodable {
        var sessionId: SessionID
        var prompt: [ContentBlock]
    }
}

/// `sleep` in a process group of its own, as npm puts the adapters it runs; its pid goes to `file`.
func startGrandchild(recordingIn file: String) {
    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
    posix_spawnattr_setpgroup(&attributes, 0)
    var pid: pid_t = 0
    let words: [String] = ["/bin/sleep", "600"]
    let arguments = words.map { strdup($0) }
    defer { arguments.forEach { free($0) } }
    if posix_spawn(&pid, "/bin/sleep", nil, &attributes, arguments + [nil], [nil]) == 0 {
        try? String(pid).write(toFile: file, atomically: true, encoding: .utf8)
    }
    posix_spawnattr_destroy(&attributes)
}

let environment = ProcessInfo.processInfo.environment
let store = URL(filePath: environment["FAKE_AGENT_STORE"] ?? NSTemporaryDirectory(), directoryHint: .isDirectory)
try? FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
if let file = environment["FAKE_AGENT_GRANDCHILD"] {
    startGrandchild(recordingIn: file)
}
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
