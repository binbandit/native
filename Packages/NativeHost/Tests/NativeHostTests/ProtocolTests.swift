import ACP
import Foundation
import NativeHostProtocol
import Testing

@Suite("Wire protocol")
struct ProtocolTests {
    private func roundTrip<Value: Codable>(_ value: Value) throws -> Value {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(Value.self, from: encoder.encode(value))
    }

    @Test(
        "Every event survives the wire",
        arguments: [
            HostEvent.Payload.reset(loading: true),
            .loaded,
            .update(
                .object(["sessionUpdate": .string("usage_update"), "used": .number(12_345), "size": .number(200_000)])),
            .prompt(PromptEcho(text: "Fix it", steered: true, origin: .queued)),
            .prompt(
                PromptEcho(
                    text: "Look", requestID: UUID(), shown: false,
                    attachments: [EchoAttachment(name: "a.png", url: URL(filePath: "/tmp/a.png"), imageBase64: "AAAA")],
                    preamble: PreambleMarker(id: "debug", label: "Debug mode", symbol: "ant"))),
            .permissionRequested(toolCallID: "call-1", request: .object(["sessionId": .string("s")])),
            .permissionResolved(toolCallID: "call-1", optionID: nil),
            .questionAsked(questionID: "q1", request: .object(["sessionId": .string("s"), "mode": .string("form")])),
            .questionResolved(questionID: "q1"),
            .turnEnded(stopReason: "end_turn"),
            .turnFailed(message: "Rate limited", error: nil),
            .turnFailed(
                message: "Sign in", error: RPCError(code: -32000, message: "auth", data: .object(["x": .bool(true)]))),
            .turnFailed(
                message: "Codex couldn't be reached", error: nil,
                retry: DeliveryRetry(agentName: "Codex", reason: "Network error", delay: 5)),
            .notice(text: "Hi", isError: false),
            .recovered(
                RecoveryNote(
                    cause: .hostStopped, action: .resumed, agentName: "Codex",
                    interruptedAt: Date(timeIntervalSince1970: 1_700_000_000))),
        ])
    func eventRoundTrip(_ payload: HostEvent.Payload) throws {
        let event = HostEvent(seq: 7, at: Date(timeIntervalSince1970: 1_700_000_000.5), payload: payload)
        #expect(try roundTrip(event) == event)
    }

    @Test("Values a newer peer sends decode as unknown instead of failing")
    func unknownValues() throws {
        let json = Data(#"{"seq":1,"at":0,"type":"teleported"}"#.utf8)
        #expect(try JSONDecoder().decode(HostEvent.self, from: json).payload == .unsupported(type: "teleported"))
        #expect(try JSONDecoder().decode(HostSessionPhase.self, from: Data(#""hibernating""#.utf8)) == .unknown)
        #expect(try JSONDecoder().decode(PromptDelivery.self, from: Data(#""queued""#.utf8)) == .queued)
    }

    @Test("Held steer status survives the wire and older queues still decode")
    func heldSteerStatus() throws {
        let item = QueuedPrompt(text: "After the command", waitingForTool: "sleep 20")
        #expect(try roundTrip(item) == item)
        let old = Data(
            "{\"id\":\"\(item.id.uuidString)\",\"text\":\"Earlier\",\"isEchoed\":true,\"attachments\":[]}".utf8)
        #expect(try JSONDecoder().decode(QueuedPrompt.self, from: old).waitingForTool == nil)
    }

    @Test("Forwarded integers stay integers, so the reducer can decode them")
    func integersSurviveForwarding() throws {
        let update = JSONValue.object([
            "sessionUpdate": .string("usage_update"), "used": .number(12_345), "size": .number(200_000),
        ])
        let data = try JSONEncoder().encode(update)
        #expect(String(decoding: data, as: UTF8.self).contains("12345"))
        #expect(!String(decoding: data, as: UTF8.self).contains("12345.0"))
        var mirror = SessionMirror()
        mirror.apply(HostEvent(seq: 1, payload: .update(update)))
        #expect(mirror.state.usage?.used == 12_345)
    }

    @Test("A request gets its response after every notification sent before it")
    func peerOrdering() async throws {
        let (clientEnd, serverEnd) = try UnixSocket.pair()
        let server = PeerBox()
        let serverPeer = JSONRPCPeer(channel: ByteChannel.socket(serverEnd, label: "server"), label: "server") {
            event in
            guard case .request(let message) = event, let id = message.id else { return }
            let peer = await server.peer
            for index in 0..<50 {
                try? peer?.notify("tick", ["index": index])
            }
            try? peer?.respond(to: id, with: ["echo": (try? message.params(as: [String: String].self))?["text"] ?? ""])
        }
        await server.set(serverPeer)
        let received = Received()
        let client = JSONRPCPeer(channel: ByteChannel.socket(clientEnd, label: "client"), label: "client") { event in
            if case .notification = event { await received.add() }
        }
        serverPeer.start()
        client.start()
        let response = try await client.request("echo", ["text": "hi"], as: [String: String].self)
        #expect(response == ["echo": "hi"])
        #expect(await received.count == 50)
        client.close()
        await client.closed()
        #expect(client.isClosed)
    }
    @Test("Response hooks finish before subsequent notifications", .timeLimit(.minutes(1)), arguments: [false, true])
    func responseBoundaryOrdering(fails: Bool) async throws {
        let (clientEnd, serverEnd) = try UnixSocket.pair()
        let server = PeerBox()
        let serverPeer = JSONRPCPeer(channel: ByteChannel.socket(serverEnd, label: "boundary-server"), label: "server")
        {
            event in
            guard case .request(let message) = event, let id = message.id, let peer = await server.peer else { return }
            try? peer.notify("before", [String: String]())
            if fails {
                try? peer.respond(to: id, error: RPCError(code: -32000, message: "fixture refusal"))
            } else {
                try? peer.respond(to: id, with: ["echo": "ok"])
            }
            try? peer.notify("after", [String: String]())
        }
        await server.set(serverPeer)
        let received = Recorded<String>()
        let client = JSONRPCPeer(channel: ByteChannel.socket(clientEnd, label: "boundary-client"), label: "client") {
            event in
            if case .notification(let message) = event { received.append(message.method) }
        }
        defer { client.close(); serverPeer.close() }
        let (started, starting) = AsyncStream.makeStream(of: Void.self)
        let (released, release) = AsyncStream.makeStream(of: Void.self)
        defer { release.finish() }
        serverPeer.start()
        client.start()
        let request = Task {
            do {
                let result = try await client.request(
                    "echo", [String: String](), as: [String: String].self,
                    onResponse: {
                        starting.yield()
                        for await _ in released { break }
                        received.append("response")
                    })
                #expect(!fails && result == ["echo": "ok"])
            } catch {
                #expect(fails && (error as? RPCError)?.code == -32000)
            }
        }
        for await _ in started { break }
        #expect(received.values == ["before"])
        release.yield()
        await request.value
        try await pollUntil("the notification after the response") { received.values.count == 3 }
        #expect(received.values == ["before", "response", "after"])
        client.close()
        await client.closed()
    }

}

private actor PeerBox {
    var peer: JSONRPCPeer?
    func set(_ peer: JSONRPCPeer) { self.peer = peer }
}

private actor Received {
    var count = 0
    func add() { count += 1 }
}
