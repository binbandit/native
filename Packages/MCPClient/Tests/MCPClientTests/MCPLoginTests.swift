import Exec
import Foundation
import Testing

@testable import MCPClient

@Suite("MCP browser sign-in")
struct MCPLoginTests {
    private let address =
        "https://auth.example.com/authorize?response_type=code&state=fixture-state&redirect_uri=http%3A%2F%2F127.0.0.1%3A43123%2Fcallback"
    private let callback = "http://127.0.0.1:43123/callback?code=fixture-code&state=fixture-state"

    @Test func assemblesSplitLinkAndIgnoresOtherOutput() throws {
        var parser = MCPLoginOutput()
        #expect(parser.receive(Data("Starting authentication\nhttps://docs.example.com/help\n".utf8)).isEmpty)
        let bytes = Data((address + "\r\n").utf8)
        #expect(parser.receive(bytes.prefix(80)).isEmpty)
        let link = try #require(parser.receive(bytes.dropFirst(80)).first)
        #expect(link.url.absoluteString == address)
        #expect(link.callback(callback)?.absoluteString == callback)
    }

    @Test func rejectsWrongStateDestinationDuplicatesAndTerminalControl() throws {
        let url = try #require(URL(string: address))
        let link = try #require(MCPAuthorizationLink(url))
        for invalid in [
            callback.replacingOccurrences(of: "fixture-state", with: "other"),
            callback.replacingOccurrences(of: "43123", with: "43124"),
            callback.replacingOccurrences(of: "/callback", with: "/other"),
            callback.replacingOccurrences(of: "127.0.0.1", with: "example.com"),
            callback + "&state=fixture-state", callback + "\nwhoami", callback + "\u{1b}[0m",
            callback + "#fragment",
        ] {
            #expect(link.callback(invalid) == nil)
        }
    }

    @Test func readsClaudeTerminalHyperlink() throws {
        var parser = MCPLoginOutput()
        let output = "Visit this URL to authorize:\r\n  \u{1b}]8;;\(address)\u{7}\(address)\u{1b}]8;;\u{7}\r\n"
        let links = parser.receive(Data(output.utf8))
        #expect(links.count == 1)
        #expect(links.first?.url.absoluteString == address)
    }

    @Test func rejectsUntrustedAuthorizationLinks() throws {
        for invalid in [
            address.replacingOccurrences(of: "https://auth", with: "http://auth"),
            address.replacingOccurrences(of: "https://auth", with: "https://user:password@auth"),
            address.replacingOccurrences(of: "127.0.0.1", with: "example.com"),
            address + "&state=other",
        ] {
            #expect(MCPAuthorizationLink(try #require(URL(string: invalid))) == nil)
        }
    }

    @Test @MainActor func completesThroughPrivateInput() async throws {
        let flow = MCPLoginFlow()
        let command = Command(
            "/bin/sh",
            ["-c", "test -t 0 || exit 7; printf '%s\\n' \"$LINK\"; read -r reply; test \"$reply\" = \"$CALLBACK\""],
            environment: ["LINK": address, "CALLBACK": callback], timeout: .seconds(5))
        flow.start(command, runner: LocalCommandRunner())
        defer { flow.cancel() }
        try await wait { flow.phase == .waiting }
        #expect(!flow.submitCallback(callback + "&state=other"))
        #expect(flow.inputProblem != nil)
        #expect(flow.submitCallback(callback))
        try await wait { flow.phase == .succeeded }
        #expect(flow.authorization == nil)
        #expect(flow.inputProblem == nil)
    }

    @Test @MainActor func cancellationClearsLinkAndLateOutputCannotRestoreIt() async throws {
        let flow = MCPLoginFlow()
        flow.start(
            Command("/bin/sh", ["-c", "echo \"$LINK\"; read -r reply"], environment: ["LINK": address]),
            runner: LocalCommandRunner())
        try await wait { flow.phase == .waiting }
        flow.cancel()
        try await Task.sleep(for: .milliseconds(100))
        #expect(flow.phase == .cancelled)
        #expect(flow.authorization == nil)
        #expect(!flow.submitCallback(callback))
    }

    @MainActor private func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(predicate())
    }
}
