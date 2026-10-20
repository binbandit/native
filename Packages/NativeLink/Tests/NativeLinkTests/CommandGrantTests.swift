import ACP
import Foundation
import NativeHostProtocol
import Testing

@testable import NativeLink

/// The `runCommands` grant at the gateway: commands, files and projects, and session requests that
/// would have an agent start a command (docs/durability.md, "What a client may do").
@Suite("Running commands from a paired device")
struct CommandGrantTests {
    private let commanding = LinkGrants(runCommands: true)

    @Test func commandsFilesAndProjectsTakeTheGrant() {
        typealias Method = HostProtocol.Method
        for method in [
            Method.execRun, Method.execCancel, Method.listProjects, Method.addProject, Method.removeProject,
            "_native/fs/read", Method.setMCPServers, Method.syncAgents,
        ] {
            #expect(!LinkMethodPolicy.allows(method, with: .standard), "\(method)")
            #expect(!LinkMethodPolicy.allows(method, with: LinkGrants(managePlugins: true, manageHost: true)))
            #expect(LinkMethodPolicy.allows(method, with: commanding), "\(method)")
        }
        // Driving tasks needs no grant; stopping agents or deleting their sessions isn't offered at all.
        for method in [
            Method.respondQuestion, Method.runHidden, Method.restoreQueued, Method.moveQueued, Method.listAgents,
            Method.startAgent, Method.authenticateAgent, Method.listAgentSessions,
        ] {
            #expect(LinkMethodPolicy.allows(method, with: .standard), "\(method)")
        }
        for method in [
            Method.stopAgent, Method.restartAgent, Method.deleteAgentSession, Method.shutdown, Method.updateReport,
        ] {
            #expect(
                !LinkMethodPolicy.allows(
                    method, with: LinkGrants(managePlugins: true, manageHost: true, runCommands: true)))
        }
    }

    @Test func hostStatusIsOpenAndChangingTheHostTakesManageHost() {
        typealias Method = HostProtocol.Method
        for method in [
            Method.hostStatus, Method.doctor, Method.listNotifications, Method.acknowledgeNotifications,
            Method.actOnNotification, Method.checkAgentSignIn, Method.cancelAgentSignIn,
        ] {
            #expect(LinkMethodPolicy.allows(method, with: .standard), "\(method)")
        }
        for method in [
            Method.updateInstall, Method.setKeepAwake, Method.setAgentCredential, Method.removeAgentCredential,
        ] {
            #expect(!LinkMethodPolicy.allows(method, with: LinkGrants(managePlugins: true, runCommands: true)))
            #expect(LinkMethodPolicy.allows(method, with: LinkGrants(manageHost: true)), "\(method)")
        }
    }

    @Test func sessionRequestsThatStartCommandsTakeTheGrant() {
        typealias Method = HostProtocol.Method
        let stdio: JSONValue = .object(["name": .string("tool"), "command": .string("/bin/sh"), "args": .array([])])
        let http: JSONValue = .object(["type": .string("http"), "name": .string("docs"), "url": .string("https://x")])
        let disguised: JSONValue = .object(["type": .string("http"), "name": .string("x"), "command": .string("sh")])
        func params(_ servers: [JSONValue], meta: JSONValue? = nil) -> JSONValue {
            var fields: [String: JSONValue] = [
                "agentID": .string("claude"), "cwd": .string("/p"), "mcpServers": .array(servers),
            ]
            fields["meta"] = meta
            return .object(fields)
        }
        for method in [Method.newSession, Method.openSession] {
            #expect(LinkMethodPolicy.allows(method, params: params([]), with: .standard))
            #expect(LinkMethodPolicy.allows(method, params: params([http]), with: .standard))
            #expect(!LinkMethodPolicy.allows(method, params: params([http, stdio]), with: .standard))
            #expect(!LinkMethodPolicy.allows(method, params: params([disguised]), with: .standard))
            #expect(
                !LinkMethodPolicy.allows(
                    method, params: params([], meta: .object(["claudeCode": .object([:])])), with: .standard))
            #expect(
                LinkMethodPolicy.allows(method, params: params([stdio], meta: .object(["a": .null])), with: commanding))
        }
        let commands: JSONValue = .object(["limit": .number(10), "includeCommands": .bool(true)])
        #expect(!LinkMethodPolicy.allows(Method.listActivity, params: commands, with: .standard))
        #expect(LinkMethodPolicy.allows(Method.listActivity, params: commands, with: commanding))
    }

    @Test func aDeviceWithoutTheGrantIsAnsweredLikeTheHostWould() async throws {
        let harness = try GatewayHarness()
        let (_, channel) = try await harness.pairDevice()
        let (stream, _) = try #require(harness.admitted.withLock { $0.first })
        var forwarded = stream.incoming().makeAsyncIterator()
        var replies = channel.incoming().makeAsyncIterator()

        channel.write(
            Data(
                #"{"jsonrpc":"2.0","id":1,"method":"session/new","params":{"agentID":"a","cwd":"/p","origin":"user","attach":false,"mcpServers":[{"name":"x","command":"/bin/sh","args":[],"env":[]}]}}"#
                    .utf8 + [0x0A]))
        let reply = String(decoding: try #require(await replies.next()), as: UTF8.self)
        #expect(reply.contains(#""id":1"#))
        #expect(reply.contains(#""hostError":"notAuthorized""#))

        channel.write(
            Data(#"{"jsonrpc":"2.0","id":2,"method":"_native/exec/run","params":{}}"#.utf8 + [0x0A]))
        #expect(String(decoding: try #require(await replies.next()), as: UTF8.self).contains("-32601"))

        // What's allowed goes through, and nothing refused reached the host before it.
        let allowed = #"{"jsonrpc":"2.0","id":3,"method":"session/list","params":{}}"#
        channel.write(Data(allowed.utf8 + [0x0A]))
        #expect(String(decoding: try #require(await forwarded.next()), as: UTF8.self).contains(#""id":3"#))
    }

    @Test func pairingsKeepWhatTheyHadAndMacsAreOfferedTheGrant() throws {
        let old = try JSONDecoder().decode(LinkGrants.self, from: Data(#"{"manageHost":true}"#.utf8))
        #expect(old == LinkGrants(manageHost: true))
        #expect(try JSONDecoder().decode(LinkGrants.self, from: JSONEncoder().encode(commanding)) == commanding)

        func request(_ model: String, usedCode: Bool) -> LinkPairingRequest {
            LinkPairingRequest(
                device: LinkDeviceInfo(name: "d", model: model, system: "s"),
                verification: VerificationCode(digits: "000000"),
                usedCode: usedCode)
        }
        #expect(LinkGrants.suggested(for: request("Mac16,1", usedCode: false)).runCommands)
        #expect(!LinkGrants.suggested(for: request("Mac16,1", usedCode: true)).runCommands)
        #expect(!LinkGrants.suggested(for: request("iPhone", usedCode: false)).runCommands)
        #expect(!LinkGrants.suggested(for: request("iPad", usedCode: false)).runCommands)
    }
}
