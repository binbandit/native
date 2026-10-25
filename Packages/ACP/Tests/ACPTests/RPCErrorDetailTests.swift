import ACP
import Foundation
import Testing

struct RPCErrorDetailTests {
    @Test func detailIsTheAgentsTextUnderAGenericMessage() throws {
        // codex-acp 2.2.2's session/new answer for a config.toml it can't load.
        let json = #"""
            {"code":-32603,"message":"Internal error","data":"failed to load configuration: /private/tmp/home/config.toml:2:19: unknown variant `sometimes`, expected one of `untrusted`, `never`\n\nCheck /private/tmp/home and project .codex directories."}
            """#
        let error = try JSONDecoder().decode(RPCError.self, from: Data(json.utf8))
        #expect(error.localizedDescription == "Internal error")
        #expect(error.detail.hasPrefix("failed to load configuration: /private/tmp/home/config.toml:2:19"))
    }

    @Test func detailReadsTheDetailsObject() throws {
        // codex-acp 2.2.2 when session/new brings MCP servers: the reason is under data.details.
        let json = #"""
            {"code":-32603,"message":"Internal error","data":{"details":"invalid configuration: unknown variant `on_request`, expected one of `untrusted`, `on-failure`, `on-request`, `granular`, `never`\nin `approval_policy`\n"}}
            """#
        let error = try JSONDecoder().decode(RPCError.self, from: Data(json.utf8))
        #expect(error.detail.hasPrefix("invalid configuration: unknown variant `on_request`"))
        #expect(error.detail.hasSuffix("in `approval_policy`"))
    }

    @Test func detailFallsBackToTheMessage() {
        #expect(RPCError(code: -32000, message: "Authentication required").detail == "Authentication required")
        #expect(RPCError(code: -32603, message: "Internal error", data: .string("  ")).detail == "Internal error")
        #expect(
            RPCError(code: -32603, message: "Internal error", data: .object(["errorKind": .string("overloaded")]))
                .detail == "Internal error")
    }
}
