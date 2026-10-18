import ACP
import Foundation
import Synchronization
import Testing

/// Waits are bounded, but a connection stuck in a way they don't cover would otherwise hang the run.
@Suite(.timeLimit(.minutes(1)))
struct ACPConnectionTests {
    @Test func sendWritesTheRequestAndReturnsItsResponse() async throws {
        let agent = await FakeAgent()
        defer { agent.hangUp() }
        let initialize = InitializeRequest(clientInfo: Implementation(name: "probe", version: "0"))
        let response = Task { try await agent.connection.send(initialize) }

        let request = try #require(await agent.message(0))
        // The captured envelope, around whatever params the request encodes to today.
        guard case .object(var expected) = try Wire.json(Wire.initializeRequest) else {
            Issue.record("Expected a JSON object")
            return
        }
        expected["params"] = try Wire.json(encoding: initialize)
        #expect(request == .object(expected))
        try agent.reply(to: request, result: Wire.initializeResult)

        #expect(try await response.value.agentInfo?.title == "Claude Agent")
    }

    @Test func responsesReachTheirCallersInAnyOrder() async throws {
        let agent = await FakeAgent()
        defer { agent.hangUp() }
        let one = Task { try await agent.connection.send(NewSessionRequest(cwd: "/one")) }
        let two = Task { try await agent.connection.send(NewSessionRequest(cwd: "/two")) }

        let first = try #require(await agent.message(0))
        let second = try #require(await agent.message(1))
        #expect(first["id"] != second["id"])
        // Answer the later request first; each result names the cwd it answers.
        for request in [second, first] {
            let cwd = try #require(request["params"]?["cwd"]?.stringValue)
            try agent.reply(to: request, result: #"{"sessionId":"for:\#(cwd)"}"#)
        }

        #expect(try await one.value.sessionId == SessionID("for:/one"))
        #expect(try await two.value.sessionId == SessionID("for:/two"))
    }

    @Test func errorResponseThrowsTheRPCError() async throws {
        let agent = await FakeAgent()
        defer { agent.hangUp() }
        let response = Task { try await agent.connection.send(NewSessionRequest(cwd: "/one")) }

        let request = try #require(await agent.message(0))
        try agent.reply(to: request, error: #"{"code":-32000,"message":"Authentication required"}"#)

        await #expect(throws: RPCError(code: -32000, message: "Authentication required")) {
            try await response.value
        }
    }

    @Test func permissionRequestReachesTheHandlerAndTheAnswerGoesBack() async throws {
        let agent = await FakeAgent()
        defer { agent.hangUp() }
        try agent.write(Wire.permissionRequest)

        try #require(await eventually { !agent.events.all.isEmpty })
        let (id, request) = try #require(agent.events.all.first?.permissionRequest)
        #expect(id == .int(0))
        #expect(request.toolCall.toolCallId == Wire.writeToolCallID)

        try await agent.connection.respond(to: id, with: RequestPermissionResponse.selected(optionId: "allow-once"))
        let answer = try #require(await agent.message(0))
        #expect(answer == (try Wire.json(Wire.permissionResponse)))
    }

    @Test func unknownAgentRequestGetsMethodNotFound() async throws {
        let agent = await FakeAgent()
        defer { agent.hangUp() }
        // Extension notifications are ignored without a reply.
        try agent.write(Wire.authStatusNotification)
        // We advertise no fs capability, so this is unexpected; the string id must come back as is.
        try agent.write(
            #"{"jsonrpc":"2.0","id":"fs-1","method":"fs/read_text_file","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","path":"/etc/hosts"}}"#
        )

        let reply = try #require(await agent.message(0))
        #expect(
            reply
                == (try Wire.json(
                    #"{"jsonrpc":"2.0","id":"fs-1","error":{"code":-32601,"message":"Method not found: fs/read_text_file"}}"#
                )))
        #expect(agent.events.all.isEmpty)
    }

    @Test func eventsBeforeAResponseAreHandledBeforeSendReturns() async throws {
        // A slow handler, so a connection that didn't wait for it would let the response overtake the updates.
        let agent = await FakeAgent(handlingDelay: .milliseconds(2))
        defer { agent.hangUp() }
        let prompt = Task {
            try await agent.connection.send(PromptRequest(sessionId: Wire.sessionID, prompt: [.text(Wire.promptText)]))
        }

        let request = try #require(await agent.message(0))
        for chunk in Wire.agentMessageChunks {
            try agent.write(chunk)
        }
        try agent.reply(to: request, result: Wire.promptResult)

        #expect(try await prompt.value.stopReason == .endTurn)
        let handled = agent.events.all
        #expect(handled.count == Wire.agentMessageChunks.count)
        #expect(handled.compactMap(\.agentMessageText).joined() == Wire.agentMessage)
    }

    @Test func agentExitFailsPendingRequestsAndReportsDisconnect() async throws {
        let agent = await FakeAgent()
        defer { agent.hangUp() }
        let prompt = Task {
            try await agent.connection.send(PromptRequest(sessionId: Wire.sessionID, prompt: [.text("hi")]))
        }
        try #require(await agent.message(0) != nil)

        agent.hangUp()

        await #expect(throws: ACPConnectionError.disconnected) {
            try await prompt.value
        }
        #expect(await eventually { agent.events.all.contains { $0.isDisconnected } })
        await #expect(throws: ACPConnectionError.disconnected) {
            try await agent.connection.send(PromptRequest(sessionId: Wire.sessionID, prompt: [.text("again")]))
        }
    }

    @Test func connectionsReadIndependently() async throws {
        // Never writes, so its connection sits waiting for input.
        let idle = await FakeAgent()
        defer { idle.hangUp() }
        let busy = await FakeAgent()
        defer { busy.hangUp() }

        for (index, chunk) in Wire.agentMessageChunks.prefix(3).enumerated() {
            try busy.write(chunk)
            try #require(await eventually(within: .seconds(1)) { busy.events.all.count == index + 1 })
        }
        #expect(idle.events.all.isEmpty)
    }
}

// MARK: - Harness

/// Plays the agent's end of an `ACPConnection` over two in-process pipes.
private final class FakeAgent: Sendable {
    let connection: ACPConnection
    let events: Recording<AgentEvent>
    /// What the client wrote, one decoded line per element.
    private let received = Recording<JSONValue>()
    /// The agent's stdout, which the connection reads.
    private let output: FileHandle

    init(handlingDelay: Duration = .zero) async {
        let toAgent = Pipe()
        let toClient = Pipe()
        let events = Recording<AgentEvent>()
        self.events = events
        output = toClient.fileHandleForWriting
        connection = ACPConnection(
            reading: toClient.fileHandleForReading,
            writing: toAgent.fileHandleForWriting,
            onEvent: { event in
                if handlingDelay > .zero {
                    try? await Task.sleep(for: handlingDelay)
                }
                events.append(event)
            }
        )

        // A thread of its own rather than `FileHandle.bytes`, which would queue behind the
        // connection's own blocked read.
        let input = toAgent.fileHandleForReading
        let received = received
        Thread.detachNewThread {
            var pending = Data()
            while true {
                let data = input.availableData
                guard !data.isEmpty else { return }  // End of file: the connection closed its end.
                pending.append(data)
                while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                    let line = String(decoding: pending[..<newline], as: UTF8.self)
                    pending.removeSubrange(...newline)
                    // Undecodable output still surfaces, as a string, so the test fails on it.
                    received.append((try? Wire.json(line)) ?? .string(line))
                }
            }
        }

        await connection.start()
    }

    /// The client's message at `index`, in the order it wrote them, once it arrives.
    func message(_ index: Int) async -> JSONValue? {
        await received.element(at: index)
    }

    func write(_ line: String) throws {
        try output.write(contentsOf: Data((line + "\n").utf8))
    }

    /// Answers a request the client sent, echoing its id.
    func reply(to request: JSONValue, result: String) throws {
        try reply(to: request, member: "result", value: result)
    }

    func reply(to request: JSONValue, error: String) throws {
        try reply(to: request, member: "error", value: error)
    }

    /// Closes the agent's stdout, as if it exited. Safe to call more than once.
    func hangUp() {
        try? output.close()
    }

    private func reply(to request: JSONValue, member: String, value: String) throws {
        let id = try String(decoding: JSONEncoder().encode(request["id"]), as: UTF8.self)
        try write(#"{"jsonrpc":"2.0","id":\#(id),"\#(member)":\#(value)}"#)
    }
}

/// An append-only log that tests can poll.
private final class Recording<Element: Sendable>: Sendable {
    private let elements = Mutex<[Element]>([])

    var all: [Element] {
        elements.withLock { $0 }
    }

    func append(_ element: Element) {
        elements.withLock { $0.append(element) }
    }

    func element(at index: Int) async -> Element? {
        guard await eventually({ all.count > index }) else { return nil }
        return all[index]
    }
}

/// Polls `condition` until it holds or `timeout` passes.
private func eventually(within timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return true
}

private extension AgentEvent {
    var permissionRequest: (id: RequestID, request: RequestPermissionRequest)? {
        guard case .permissionRequest(let id, let request) = self else { return nil }
        return (id, request)
    }

    var agentMessageText: String? {
        guard case .sessionUpdate(let notification) = self, case .agentMessageChunk(let chunk) = notification.update
        else { return nil }
        return chunk.content.text
    }

    var isDisconnected: Bool {
        if case .disconnected = self { true } else { false }
    }
}
