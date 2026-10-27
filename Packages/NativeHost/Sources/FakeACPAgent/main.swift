import ACP
import Foundation
import NativeHostProtocol

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// A scriptable ACP agent for the host's tests. Like a real agent it keeps its own session store
// (in $FAKE_AGENT_STORE) and writes the user's message to it as soon as a prompt arrives, so
// `session/load` replays exactly what it received (`session/resume` reopens a session without the
// replay). Prompts script its behavior:
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
//   config?             answers with its mode, model and effort, as "config: mode=… model=… effort=…"
//   leave-plan          leaves Plan Mode itself, as an agent does once its plan is approved, and says so
//                       (config_option_update)
//   /context            answers "context: 42% used", and sends that again just after the turn ends
//   tool <name> <json>  calls one of Native's tools (the `native` MCP server it was given) and answers
//                       "tool: <its text>"
//   (a prompt in Native's task or message header runs the script after the header)
//   delegate …          starts a task on the fake agent with the rest as its prompt (start_task), notes
//                       it in its store, waits for it (wait_for_task) and answers "delegated: <reply>";
//                       told its turn was interrupted, it goes back to waiting for a task it noted
//   anything else       answers "echo: <text>"; Native's interruption notice gets "resumed"
//
// Every prompt and steer it receives is appended to $FAKE_AGENT_STORE/received.log, with non-text
// blocks shown as "[link <name>]" and the like; every load's MCP servers (name and command) go to loads.log,
// every new session's to news.log, and every call of Native's tools to tools.log. With $FAKE_AGENT_GRANDCHILD set to a file, it starts
// `sleep` in a process group of its own at launch and writes its pid there, as npm does with the
// adapters it runs. With $FAKE_AGENT_NO_STEERING=1 it doesn't offer steering. `/rename <name>` renames
// the session without a model, as codex-acp does (to received.log as "rename"), unless
// $FAKE_AGENT_RENAME_ASKS_MODEL=1, which answers it like any other prompt. Settings (mode, model,
// effort) live in memory, so a reloaded session reports the defaults again; like codex-acp, choosing
// a model puts the effort back to that model's default. It lists the effort (id "effort") before the
// model. On a session it loaded (not one it started), it won't change the options named in
// $FAKE_AGENT_LOCKED_ON_RELOAD (comma-separated ids): it turns set_config_option away with an error,
// or for `<id>=keep` answers as if it had changed it. Either way the attempt goes to received.log as
// "locked". With $FAKE_AGENT_RELOAD_DEFAULTS (`effort=low,model=beta`), a session it loaded reports
// those values instead of its usual defaults, as an agent that reopens sessions on other defaults
// (codex-acp on its built-in ones); new sessions keep the usual defaults.
//
// With $FAKE_AGENT_SIGN_IN=1 it also offers sign-in methods and reports its status
// (FakeAgent+SignIn.swift).

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
    var models: [SessionID: String] = [:]
    var efforts: [SessionID: String] = [:]
    /// Sessions this process loaded rather than started, for `$FAKE_AGENT_LOCKED_ON_RELOAD`.
    var loaded: Set<SessionID> = []
    /// Native's tools for each session, as `session/new` and `session/load` last gave them.
    var nativeTools: [SessionID: URL] = [:]

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
                note("cancels.log", params.sessionId.rawValue)
                if ProcessInfo.processInfo.environment["FAKE_AGENT_EXIT_ON_CANCEL"] == "1" { exit(0) }
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
                        "loadSession": .bool(ProcessInfo.processInfo.environment["FAKE_AGENT_NO_LOAD"] != "1"),
                        "sessionCapabilities": .object(
                            [
                                "list": .object([:]), "delete": .object([:]),
                                "resume": ProcessInfo.processInfo.environment["FAKE_AGENT_NO_RESUME"] == "1"
                                    ? .null : .object([:]),
                            ].merging(Self.closeCapability) { $1 }),
                    ]),
                    "agentInfo": .object(["name": .string("fake-agent"), "version": .string("1")]),
                    "authMethods": .array([.object(["id": .string("token"), "name": .string("Token")])]),
                    "_meta": .object(["steering": .object(["supported": .bool(!Self.cantSteer)])]),
                ]).addingFakeSignIn(for: message))
            if Self.signsIn { try reportSignInStatus(on: peer) }
        case "authenticate":
            if try await signIn(message, id: id, on: peer) { return }
            received("authenticate", (try? message.params(as: AuthParams.self))?.methodId ?? "")
            try peer.respond(to: id, with: JSONValue.object([:]))
        case "session/new":
            let session = SessionID(UUID().uuidString)
            try save([], for: session)
            nativeTools[session] = Self.nativeTools(in: message)
            let servers =
                (try? message.params(as: LoadParams.self))?.mcpServers.map { "\($0.name) \($0.command ?? "")" } ?? []
            note("news.log", servers.joined(separator: ","))
            try peer.respond(
                to: id,
                with: JSONValue.object(["sessionId": .string(session.rawValue), "configOptions": options(session)]))
        case "session/load":
            try emitChildText("Child history")
            if ProcessInfo.processInfo.environment["FAKE_AGENT_LOAD_HANG_ONCE"] == "1", firstTime("load-hang") {
                note("loads.log", "waiting")
                try await Task.sleep(for: .seconds(3_600))
            }
            let session = try message.params(as: SessionParams.self).sessionId
            let servers =
                (try? message.params(as: LoadParams.self))?.mcpServers.map { "\($0.name) \($0.command ?? "")" } ?? []
            note("loads.log", servers.joined(separator: ","))
            nativeTools[session] = Self.nativeTools(in: message)
            loaded.insert(session)
            for (configID, value) in Self.reloadDefaults {
                switch configID {
                case "model": models[session] = models[session] ?? value
                case "effort": efforts[session] = efforts[session] ?? value
                default: modes[session] = modes[session] ?? value
                }
            }
            for (index, entry) in try load(session).enumerated() {
                let kind = entry.role == "user" ? "user_message_chunk" : "agent_message_chunk"
                try update(
                    session,
                    [
                        "sessionUpdate": .string(kind), "messageId": .string("m\(index)"),
                        "content": Self.text(entry.text),
                    ])
            }
            try reportReloadConfig(session)
            try peer.respond(to: id, with: JSONValue.object(["configOptions": options(session)]))
            if ProcessInfo.processInfo.environment["FAKE_AGENT_CHILD_AFTER_LOAD"] == "1" {
                try emitChildText("Fresh at boundary")
                try emitChildConfig()
            }
        case "session/resume":
            try emitChildText("Fresh child update")
            // Like a load without the replay.
            let session = try message.params(as: SessionParams.self).sessionId
            guard FileManager.default.fileExists(atPath: file(session).path(percentEncoded: false)) else {
                throw RPCError(code: -32602, message: "No session \(session.rawValue)")
            }
            received("resume", session.rawValue)
            nativeTools[session] = Self.nativeTools(in: message)
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
            if ProcessInfo.processInfo.environment["FAKE_AGENT_REJECT_CLOSE"] == "1",
                !FileManager.default.fileExists(atPath: store.appendingPathComponent("allow-close").path)
            {
                throw RPCError(code: -32603, message: "Fixture refused to close the session")
            }
            let session = try message.params(as: SessionParams.self).sessionId
            received("close", session.rawValue)
            // Freed, as a real agent does: a resume reports the defaults again.
            (modes[session], models[session], efforts[session]) = (nil, nil, nil)
            try peer.respond(to: id, with: JSONValue.object([:]))
        case "session/prompt":
            let params = try message.params(as: PromptParams.self)
            let text = Self.describe(params.prompt)
            if text.hasPrefix("/rename "), !Self.renameAsksModel {
                try await rename(params.sessionId, to: String(text.dropFirst("/rename ".count)), id: id, on: peer)
                return
            }
            let stopReason = try await prompt(params.sessionId, text: text)
            try peer.respond(to: id, with: JSONValue.object(["stopReason": .string(stopReason)]))
        case "_session/steering":
            let params = try message.params(as: PromptParams.self)
            let text = Self.describe(params.prompt)
            guard running.contains(params.sessionId) else {
                try peer.respond(to: id, with: JSONValue.object(["outcome": .string("promptRequired")]))
                return
            }
            received("steer", text)
            if ProcessInfo.processInfo.environment["FAKE_AGENT_DELAY_STEER"] == "1" {
                try await Task.sleep(for: .seconds(3))
                received("steer-accepted", text)
            }
            try append(Message(role: "user", text: text), to: params.sessionId)
            try peer.respond(to: id, with: JSONValue.object(["outcome": .string("injected")]))
        case "session/set_config_option":
            let params = try message.params(as: ConfigParams.self)
            if loaded.contains(params.sessionId), params.configId == "model",
                ProcessInfo.processInfo.environment["FAKE_AGENT_CHILD_ON_RESTORE"] == "1"
            {
                try emitChildText("Fresh during restore")
                try emitChildConfig()
            }
            if loaded.contains(params.sessionId),
                ProcessInfo.processInfo.environment["FAKE_AGENT_CRASH_ON_RESTORE"] == "1",
                firstTime("restore-\(params.sessionId.rawValue)")
            {
                received("restore-crash", params.configId)
                exit(3)
            }
            if loaded.contains(params.sessionId), let lock = Self.reloadLocks[params.configId] {
                received("locked", "\(params.configId)=\(params.value)")
                guard lock == .keep else {
                    throw RPCError(
                        code: -32603, message: "\(params.configId.capitalized) can't change in a resumed session")
                }
                try peer.respond(to: id, with: JSONValue.object(["configOptions": options(params.sessionId)]))
                return
            }
            switch params.configId {
            case "model":
                models[params.sessionId] = params.value
                efforts[params.sessionId] = nil
            case "effort":
                efforts[params.sessionId] = params.value
            default:
                modes[params.sessionId] = params.value
            }
            received("config", "\(params.configId)=\(params.value)")
            try reportReloadConfig(params.sessionId)
            try peer.respond(to: id, with: JSONValue.object(["configOptions": options(params.sessionId)]))
        case "logout" where Self.signsIn:
            try logOut(id: id, on: peer)
        default:
            try peer.respond(to: id, error: .methodNotFound(message.method))
        }
    }

    /// `/rename` as codex-acp 2.2.2 answers it (captured from it): handled without a model, so the
    /// usage is null, and the new title follows the answer.
    private func rename(_ session: SessionID, to name: String, id: RequestID, on peer: JSONRPCPeer) async throws {
        cancelled.remove(session)
        received("rename", name)
        // A file gate lets tests stop or restart the agent while naming is still in flight.
        let environment = ProcessInfo.processInfo.environment
        if let gate = environment["FAKE_AGENT_RENAME_GATE"] {
            while !FileManager.default.fileExists(atPath: gate) {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        let stopped = cancelled.contains(session) && environment["FAKE_AGENT_RENAME_IGNORES_CANCEL"] != "1"
        try peer.respond(
            to: id,
            with: JSONValue.object([
                "stopReason": .string(stopped ? "cancelled" : "end_turn"), "usage": .null,
                "_meta": .object(["quota": .object(["token_count": .null, "model_usage": .array([])])]),
            ]))
        if !stopped {
            try update(session, ["sessionUpdate": .string("session_info_update"), "title": .string(name)])
        }
    }

    private func prompt(_ session: SessionID, text framed: String) async throws -> String {
        // A task's prompt or a message from another session opens with Native's header; the script is
        // what follows it.
        let isFramed = framed.hasPrefix("[A task from your parent session (") || framed.hasPrefix("[Message from ")
        let text = isFramed ? framed.components(separatedBy: "]\n\n").dropFirst().joined(separator: "]\n\n") : framed
        // Publish receipt only after the restart marker is durable; the crash harness kills on receipt.
        let losesPrompt = text.hasPrefix("lose-once") && firstTime(text)
        received("prompt", framed)
        if losesPrompt {
            // Never recorded, never answered: as if the prompt was lost on the way in.
            try await Task.sleep(for: .seconds(3_600))
        }
        if text.hasPrefix("flaky-once"), firstTime(text) {
            throw RPCError(code: -32603, message: "Network error: connection reset by peer")
        }
        // As received, header and all, as an agent records it.
        try append(Message(role: "user", text: framed), to: session)
        running.insert(session)
        cancelled.remove(session)
        defer { running.remove(session) }
        let reply: String
        if text.hasPrefix("crash-once"), firstTime(text) {
            try update(session, ["sessionUpdate": .string("agent_message_chunk"), "content": Self.text("working…")])
            try await Task.sleep(for: .milliseconds(200))
            exit(3)
        } else if text == "stuck-tool" {
            try update(
                session,
                [
                    "sessionUpdate": .string("tool_call"), "toolCallId": .string("sleep"),
                    "title": .string("sleep 600"), "kind": .string("execute"), "status": .string("in_progress"),
                ])
            return try await cancelLeavingCommand(session, ignoringCancel: true)
        } else if text == "tool-sleep" {
            try update(
                session,
                [
                    "sessionUpdate": .string("tool_call"), "toolCallId": .string("sleep"),
                    "title": .string("sleep 20"), "kind": .string("execute"), "status": .string("in_progress"),
                ])
            for _ in 0..<20 {
                try await Task.sleep(for: .milliseconds(100))
                if cancelled.contains(session) { return "cancelled" }
            }
            received("tool-finished", "sleep")
            try update(
                session,
                [
                    "sessionUpdate": .string("tool_call_update"), "toolCallId": .string("sleep"),
                    "status": .string("completed"),
                ])
            return try await tick(session, count: 4, stoppable: true)
        } else if text == "cancel-leaves-command" {
            return try await cancelLeavingCommand(session)
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
        } else if text == "leave-plan" {
            modes[session] = "default"
            try update(session, ["sessionUpdate": .string("config_option_update"), "configOptions": options(session)])
            reply = "left plan mode"
        } else if text == "mode?" {
            reply = "mode: \(modes[session] ?? "default")"
        } else if text == "config?" {
            reply =
                "config: mode=\(modes[session] ?? "default") model=\(models[session] ?? "alpha") effort=\(efforts[session] ?? "medium")"
        } else if text == "/context" {
            reply = "context: 42% used"
            // claude-agent-acp sends a local command's output twice, the second after the turn.
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                try? self.update(
                    session, ["sessionUpdate": .string("agent_message_chunk"), "content": Self.text("\n\(reply)\n")])
            }
        } else if text.hasPrefix("tool ") {
            let words = text.split(separator: " ", maxSplits: 2).map(String.init)
            let arguments = words.count > 2 ? try JSONDecoder().decode(JSONValue.self, from: Data(words[2].utf8)) : nil
            reply =
                "tool: \(try await callTool(session, words[1], arguments ?? .object([:]))["text"]?.stringValue ?? "")"
        } else if text.hasPrefix("delegate ") {
            let started = try await callTool(
                session, "start_task",
                .object([
                    "agent": .string("fake"), "prompt": .string(String(text.dropFirst("delegate ".count))),
                    "title": .string("Delegated"),
                ]))
            guard let taskID = started["structured"]?["task_id"]?.stringValue else {
                throw RPCError(code: -32603, message: "start_task failed: \(started["text"]?.stringValue ?? "")")
            }
            try Data(taskID.utf8).write(to: delegation(session))
            reply = try await awaitDelegation(session)
        } else if text.contains("[Native] Your previous turn was interrupted") {
            reply =
                FileManager.default.fileExists(atPath: delegation(session).path(percentEncoded: false))
                ? try await awaitDelegation(session) : "resumed"
        } else {
            reply = "echo: \(text)"
        }
        try update(session, ["sessionUpdate": .string("agent_message_chunk"), "content": Self.text(reply)])
        try append(Message(role: "agent", text: reply), to: session)
        return "end_turn"
    }

    // MARK: - Native's tools

    /// Calls one of Native's tools over MCP, as an agent would: `{"text", "structured", "isError"}`.
    private func callTool(_ session: SessionID, _ name: String, _ arguments: JSONValue) async throws -> JSONValue {
        guard let url = nativeTools[session] else {
            throw RPCError(code: -32603, message: "No native MCP server for this session")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2025-11-25", forHTTPHeaderField: "MCP-Protocol-Version")
        request.httpBody = try JSONEncoder().encode(
            JSONValue.object([
                "jsonrpc": .string("2.0"), "id": .number(1), "method": .string("tools/call"),
                "params": .object(["name": .string(name), "arguments": arguments]),
            ]))
        request.timeoutInterval = 300
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw RPCError(
                code: -32603, message: "native MCP answered \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        let result = try JSONDecoder().decode(JSONValue.self, from: data)["result"]
        var text = ""
        if case .array(let content)? = result?["content"], let first = content.first?["text"]?.stringValue {
            text = first
        }
        note("tools.log", "\(name)\t\(text)")
        return .object([
            "text": .string(text), "structured": result?["structuredContent"] ?? .null,
            "isError": result?["isError"] ?? .bool(false),
        ])
    }

    /// Waits for the task this session delegated until it isn't running, then forgets it.
    private func awaitDelegation(_ session: SessionID) async throws -> String {
        let taskID = try String(contentsOf: delegation(session), encoding: .utf8)
        while true {
            if cancelled.contains(session) { return "stopped waiting" }
            let result = try await callTool(
                session, "wait_for_task", .object(["task_id": .string(taskID), "timeout_seconds": .number(2)]))
            let status = result["structured"]?["status"]?.stringValue
            if status != "running" && status != "needs_approval" {
                try? FileManager.default.removeItem(at: delegation(session))
                return "delegated: \(result["structured"]?["reply"]?.stringValue ?? status ?? "")"
            }
        }
    }

    private func delegation(_ session: SessionID) -> URL {
        store.appending(path: "\(session.rawValue).delegation")
    }

    private static func nativeTools(in message: JSONRPCPeer.Message) -> URL? {
        (try? message.params(as: LoadParams.self))?.mcpServers.first { $0.name == "native" }?.url.flatMap(
            URL.init(string:))
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

    private func emitChildConfig() throws {
        let ids = ProcessInfo.processInfo.environment["FAKE_AGENT_CHILD_IDS"] ?? ""
        for id in ids.split(separator: ",") {
            let child = SessionID(String(id))
            try update(child, ["sessionUpdate": .string("config_option_update"), "configOptions": options(child)])
        }
    }

    private func emitChildText(_ text: String) throws {
        let ids = ProcessInfo.processInfo.environment["FAKE_AGENT_CHILD_IDS"] ?? ""
        for id in ids.split(separator: ",") {
            try update(
                SessionID(String(id)),
                [
                    "sessionUpdate": .string("agent_message_chunk"), "content": Self.text(text),
                ])
        }
    }

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
        _ = FileManager.default.createFile(atPath: marker.path(percentEncoded: false), contents: Data())
        return true
    }

    private func received(_ kind: String, _ text: String) {
        note("received.log", "\(kind)\t\(text)")
    }

    private func note(_ file: String, _ text: String) {
        let log = store.appending(path: file)
        let line = Data("\(text.replacingOccurrences(of: "\n", with: " "))\n".utf8)
        if let handle = try? FileHandle(forWritingTo: log) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
            try? handle.close()
        } else {
            try? line.write(to: log)
        }
    }

    private func options(_ session: SessionID) -> JSONValue {
        let readOnly: [JSONValue] =
            ProcessInfo.processInfo.environment["FAKE_AGENT_READ_ONLY"] == "1"
            ? [.object(["value": .string("read-only"), "name": .string("Read-only")])] : []
        let options: [JSONValue] = [
            .object([
                "id": .string("mode"), "name": .string("Mode"), "category": .string("mode"), "type": .string("select"),
                "currentValue": .string(modes[session] ?? "default"),
                "options": .array(
                    [
                        .object(["value": .string("default"), "name": .string("Default")]),
                        .object(["value": .string("plan"), "name": .string("Plan")]),
                    ] + readOnly),
            ]),
            Self.select(
                "effort", category: "thought_level", current: efforts[session] ?? "medium",
                values: ["low", "medium", "high"]),
            Self.select("model", category: "model", current: models[session] ?? "alpha", values: ["alpha", "beta"]),
        ]
        guard loaded.contains(session) else { return .array(options) }
        let missing = ProcessInfo.processInfo.environment["FAKE_AGENT_RELOAD_MISSING"]
        return .array(
            options.compactMap { option in
                guard case .object(var fields) = option, let id = fields["id"]?.stringValue else { return option }
                if missing == id { return nil }
                if let missing, missing.hasPrefix(id + "="), case .array(let values)? = fields["options"] {
                    let value = String(missing.dropFirst(id.count + 1))
                    fields["options"] = .array(values.filter { $0["value"]?.stringValue != value })
                }
                return .object(fields)
            })
    }

    /// Opt-in notifications and missing settings exercise adapters whose reload differs from new.
    private func reportReloadConfig(_ session: SessionID) throws {
        guard loaded.contains(session), ProcessInfo.processInfo.environment["FAKE_AGENT_RELOAD_UPDATES"] == "1"
        else { return }
        try update(session, ["sessionUpdate": .string("config_option_update"), "configOptions": options(session)])
    }

    private static func select(_ id: String, category: String, current: String, values: [String]) -> JSONValue {
        .object([
            "id": .string(id), "name": .string(id.capitalized), "category": .string(category),
            "type": .string("select"), "currentValue": .string(current),
            "options": .array(values.map { .object(["value": .string($0), "name": .string($0.capitalized)]) }),
        ])
    }

    /// Exercises agents that cannot confirm a session close.
    private static let closeCapability: [String: JSONValue] =
        ProcessInfo.processInfo.environment["FAKE_AGENT_NO_CLOSE"] == "1" ? [:] : ["close": .object([:])]

    /// `FAKE_AGENT_NO_STEERING=1` makes it an agent that can't take messages mid-turn.
    private static let cantSteer = ProcessInfo.processInfo.environment["FAKE_AGENT_NO_STEERING"] == "1"
    /// Answers `/rename` like any other prompt, as an agent whose model handles it would.
    private static let renameAsksModel = ProcessInfo.processInfo.environment["FAKE_AGENT_RENAME_ASKS_MODEL"] == "1"

    /// What it does about a change to an option `$FAKE_AGENT_LOCKED_ON_RELOAD` names, on a loaded session.
    enum ReloadLock {
        case refuse, keep
    }

    /// `FAKE_AGENT_LOCKED_ON_RELOAD`, by option id: `effort` refuses, `effort=keep` keeps quietly.
    private static let reloadLocks: [String: ReloadLock] = Dictionary(
        (ProcessInfo.processInfo.environment["FAKE_AGENT_LOCKED_ON_RELOAD"] ?? "").split(separator: ",").map { entry in
            let parts = entry.split(separator: "=", maxSplits: 1)
            return (String(parts[0]), parts.count > 1 && parts[1] == "keep" ? ReloadLock.keep : .refuse)
        }, uniquingKeysWith: { _, last in last })

    /// `FAKE_AGENT_RELOAD_DEFAULTS`, by option id: what a loaded session is on until someone sets it.
    private static let reloadDefaults: [String: String] = Dictionary(
        (ProcessInfo.processInfo.environment["FAKE_AGENT_RELOAD_DEFAULTS"] ?? "").split(separator: ",")
            .map { $0.split(separator: "=", maxSplits: 1).map(String.init) }
            .filter { $0.count == 2 }.map { ($0[0], $0[1]) },
        uniquingKeysWith: { _, last in last })

    private static func count(in text: String, default value: Int) -> Int {
        max(Int(text.split(separator: " ").dropFirst().first ?? "") ?? value, 1)
    }

    /// A prompt's blocks as one line: text as it is, anything else named.
    private static func describe(_ blocks: [ContentBlock]) -> String {
        blocks.map { block in
            switch block {
            case .text(let text): text
            case .resourceLink(_, let name): "[link \(name)]"
            case .resource(let uri, _, _), .resourceBlob(let uri, _, _): "[resource \(uri)]"
            case .image: "[image]"
            case .unsupported(let type): "[\(type)]"
            }
        }.joined()
    }

    private static func text(_ text: String) -> JSONValue {
        .object(["type": .string("text"), "text": .string(text)])
    }

    struct SessionParams: Decodable { var sessionId: SessionID }
    struct LoadParams: Decodable {
        struct Server: Decodable {
            var name: String
            var command: String?
            var url: String?
        }
        var mcpServers: [Server]
    }
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
    // An opaque pointer on Darwin, a struct in Glibc.
    #if canImport(Darwin)
    var attributes: posix_spawnattr_t?
    #else
    var attributes = posix_spawnattr_t()
    #endif
    posix_spawnattr_init(&attributes)
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
    posix_spawnattr_setpgroup(&attributes, 0)
    var pid: pid_t = 0
    let words: [String] = ["/bin/sleep", "600"]
    let arguments = words.map { strdup($0) }
    defer { arguments.forEach { free($0) } }
    #if os(Linux)
    // Foundation watches its child's exit through an inherited socket. Passing that socket to
    // sleep would hide the fake agent's crash until sleep exits, preventing recovery from running.
    var actions = posix_spawn_file_actions_t()
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    for entry in (try? FileManager.default.contentsOfDirectory(atPath: "/proc/self/fd")) ?? [] {
        if let descriptor = Int32(entry), descriptor > STDERR_FILENO {
            posix_spawn_file_actions_addclose(&actions, descriptor)
        }
    }
    let result = posix_spawn(&pid, "/bin/sleep", &actions, &attributes, arguments + [nil], [nil])
    #else
    let result = posix_spawn(&pid, "/bin/sleep", nil, &attributes, arguments + [nil], [nil])
    #endif
    if result == 0 {
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
