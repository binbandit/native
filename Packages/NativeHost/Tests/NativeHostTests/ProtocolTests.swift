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
            .permissionRequested(toolCallID: "call-1", request: .object(["sessionId": .string("s")])),
            .permissionResolved(toolCallID: "call-1", optionID: nil),
            .turnEnded(stopReason: "end_turn"),
            .turnFailed(message: "Rate limited"),
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
}

private actor PeerBox {
    var peer: JSONRPCPeer?
    func set(_ peer: JSONRPCPeer) { self.peer = peer }
}

private actor Received {
    var count = 0
    func add() { count += 1 }
}
