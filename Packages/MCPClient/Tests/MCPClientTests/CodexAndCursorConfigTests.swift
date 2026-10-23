import Foundation
import MCPClient
import Testing

@Suite("Codex configuration")
struct CodexConfigTests {
    let files = FakeFiles([
        "/home/tester/.codex/config.toml": "codex-config.toml",
        "/work/app/.codex/config.toml": "codex-project-config.toml",
        "/work/site/.codex/config.toml": "codex-project-config.toml",
    ])

    private func read() -> AgentMCPConfiguration {
        AgentConfigReader(files: files, home: .testHome, environment: [:]).read(.codex, projects: [.app, .site])
    }

    @Test func readsUserServers() throws {
        let user = read().servers.filter { $0.scope == .user }
        #expect(user.map(\.name) == ["docs", "inspector", "tracker"])
        #expect(user.first { $0.name == "tracker" }?.status == .disabled)

        let inspector = try #require(user.first { $0.name == "inspector" })
        #expect(
            inspector.server.transport
                == .stdio(
                    command: "npx",
                    arguments: ["-y", "example-inspector@2.1.0", "mcp"],
                    environment: [
                        "INSPECTOR_HOME": "/Applications/Example Inspector.app", "QUOTED": "tab\there \"quoted\" é",
                    ]
                ))
        #expect(inspector.notes == ["Passes through $INSPECTOR_LICENSE", "Only tools: open, decompile"])
    }

    @Test func resolvesPassThroughAndBearerTokens() throws {
        let config = read()
        let inspector = try #require(config.servers.first { $0.name == "inspector" })
        guard
            case .stdio(_, _, let environment, _) = inspector.resolved(
                environment: ["INSPECTOR_LICENSE": "L-1", "OTHER": "x"], project: nil
            ).transport
        else {
            Issue.record("Expected stdio")
            return
        }
        #expect(environment["INSPECTOR_LICENSE"] == "L-1")
        #expect(environment["OTHER"] == nil)

        let docs = try #require(config.servers.first { $0.name == "docs" })
        let headers = docs.resolved(environment: ["DOCS_TOKEN": "t0k", "DOCS_WORKSPACE": "acme"], project: nil)
            .transport
        #expect(
            headers
                == .http(
                    url: URL(string: "https://docs.example.com/mcp")!,
                    headers: ["Authorization": "Bearer t0k", "X-Workspace": "acme"]))
    }

    @Test func projectConfigNeedsTrust() {
        let config = read()
        #expect(config.servers.first { $0.scope == .project(.app) }?.status == .enabled)
        #expect(config.servers.first { $0.scope == .project(.site) }?.status == .awaitingApproval)
        #expect(config.effective(in: .app).map(\.name).sorted() == ["design", "docs", "inspector", "tracker"])
    }

    @Test func listingAddsPluginServersAndSignInState() throws {
        let listing = try CodexListing.decode(Fixture.data("codex-mcp-list.json"))
        #expect(listing.servers.map(\.name) == ["review", "docs", "inspector"])
        let merged = read().merging(listing)
        let review = try #require(merged.servers.first { $0.name == "review" })
        #expect(review.scope == .plugin("review"))
        #expect(review.source.path(percentEncoded: false).hasSuffix("example-bundled/review/1.4.0/"))
        #expect(merged.servers.first { $0.name == "docs" }?.authentication == .signedOut)
        // Files already describe the others; the listing doesn't duplicate them.
        #expect(merged.servers.filter { $0.name == "inspector" }.count == 1)
    }

    @Test func invalidTOMLIsAProblem() {
        let broken = FakeFiles(["/home/tester/.codex/config.toml": "claude.json"])
        let config = AgentConfigReader(files: broken, home: .testHome, environment: [:]).read(.codex, projects: [])
        #expect(config.servers.isEmpty)
        #expect(config.problems.count == 1)
    }

    @Test func followsCodexHome() {
        let moved = FakeFiles(["/opt/codex/config.toml": "codex-config.toml"])
        let config = AgentConfigReader(files: moved, home: .testHome, environment: ["CODEX_HOME": "/opt/codex"]).read(
            .codex, projects: [])
        #expect(config.servers.count == 3)
    }
}

@Suite("Cursor configuration")
struct CursorConfigTests {
    let files = FakeFiles([
        "/home/tester/.cursor/mcp.json": "cursor-mcp.json",
        "/work/app/.cursor/mcp.json": "cursor-project-mcp.json",
    ])

    @Test func projectWinsAndVariablesExpand() throws {
        let config = AgentConfigReader(files: files, home: .testHome, environment: [:]).read(.cursor, projects: [.app])
        let effective = config.effective(in: .app)
        #expect(effective.map(\.name).sorted() == ["docs", "files", "inspector"])

        let docs = try #require(effective.first { $0.name == "docs" })
        #expect(docs.scope == .project(.app))
        #expect(
            docs.resolved(environment: [:], project: .app).transport.url?.absoluteString
                == "https://docs.example.com/app/mcp")

        let files = try #require(effective.first { $0.name == "files" })
        #expect(
            files.resolved(environment: [:], project: .app).transport
                == .stdio(command: "files-mcp", arguments: ["/work/app"]))

        let inspector = try #require(effective.first { $0.name == "inspector" })
        #expect(
            inspector.resolved(environment: ["INSPECTOR_LICENSE": "L-2"], project: .app).transport.summary
                == "npx -y example-inspector@2.1.0 mcp")
        guard
            case .stdio(_, _, let environment, _) = inspector.resolved(
                environment: ["INSPECTOR_LICENSE": "L-2"], project: .app
            ).transport
        else { return }
        #expect(environment == ["INSPECTOR_LICENSE": "L-2"])
    }
}
